defmodule RubberDuck.Tools.Agents.CodeSummarizerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeSummarizerAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeSummarizerAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "summarize_code signal" do
    test "summarizes code with default settings", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_summarizer, params ->
        assert params.code =~ "defmodule Calculator"
        assert params.summary_type == "comprehensive"
        assert params.focus_level == "module"
        assert params.target_audience == "developer"
        assert params.include_examples == true
        assert params.include_dependencies == true
        assert params.include_complexity == false
        assert params.max_length == 200
        
        {:ok, %{
          "summary" => "This Calculator module provides basic arithmetic operations with add/2 and subtract/2 functions.",
          "analysis" => %{
            "modules" => [%{"name" => "Calculator"}],
            "functions" => [%{"name" => "add", "arity" => 2}, %{"name" => "subtract", "arity" => 2}],
            "complexity" => 1,
            "dependencies" => [],
            "patterns" => []
          },
          "metadata" => %{
            "summary_type" => "comprehensive",
            "focus_level" => "module",
            "target_audience" => "developer",
            "code_metrics" => %{"lines_of_code" => 5}
          }
        }}
      end)
      
      # Send summarize_code signal
      signal = %{
        "type" => "summarize_code",
        "data" => %{
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
            def subtract(a, b), do: a - b
          end
          """,
          "request_id" => "summary_123"
        }
      }
      
      {:ok, _updated_agent} = CodeSummarizerAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, %Jido.Signal{type: "code.summary.progress"} = progress_signal}
      assert progress_signal.data.status == "analyzing"
      assert progress_signal.data.summary_type == "comprehensive"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive summarized signal
      assert_receive {:signal, %Jido.Signal{type: "code.summarized"} = result_signal}
      assert result_signal.data.request_id == "summary_123"
      assert result_signal.data.summary =~ "Calculator module"
      assert result_signal.data.summary_type == "comprehensive"
    end
    
    test "uses custom summary parameters", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_summarizer, params ->
        assert params.summary_type == "brief"
        assert params.focus_level == "function"
        assert params.target_audience == "beginner"
        assert params.include_examples == false
        assert params.max_length == 50
        
        {:ok, %{
          "summary" => "Simple function that adds two numbers.",
          "analysis" => %{"complexity" => 1},
          "metadata" => %{"summary_type" => "brief"}
        }}
      end)
      
      signal = %{
        "type" => "summarize_code",
        "data" => %{
          "code" => "def add(a, b), do: a + b",
          "summary_type" => "brief",
          "focus_level" => "function",
          "target_audience" => "beginner",
          "include_examples" => false,
          "max_length" => 50
        }
      }
      
      {:ok, _agent} = CodeSummarizerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summarized"}}
    end
    
    test "returns cached summary on second request", %{agent: agent} do
      code = "def hello, do: :world"
      
      # First request - should call executor
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_summarizer, _params ->
        {:ok, %{
          "summary" => "Function that returns :world",
          "analysis" => %{},
          "metadata" => %{}
        }}
      end)
      
      signal = %{
        "type" => "summarize_code",
        "data" => %{
          "code" => code,
          "request_id" => "cache_test_1"
        }
      }
      
      {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summarized"} = first_result}
      refute first_result.data[:from_cache]
      
      # Second request - should use cache (no executor call expected)
      signal2 = %{
        "type" => "summarize_code",
        "data" => %{
          "code" => code,
          "request_id" => "cache_test_2"
        }
      }
      
      {:ok, _agent} = CodeSummarizerAgent.handle_signal(agent, signal2)
      
      # Should receive cached result immediately
      assert_receive {:signal, %Jido.Signal{type: "code.summarized"} = cached_result}
      assert cached_result.data.from_cache == true
      assert cached_result.data.summary == "Function that returns :world"
    end
  end
  
  describe "summarize_project signal" do
    test "summarizes multiple project files", %{agent: agent} do
      # Create temporary project structure
      {:ok, temp_dir} = Temp.mkdir("summarize_project_test")
      
      lib_dir = Path.join(temp_dir, "lib")
      File.mkdir_p!(lib_dir)
      
      file1 = Path.join(lib_dir, "module1.ex")
      file2 = Path.join(lib_dir, "module2.ex")
      
      File.write!(file1, "defmodule Module1 do\n  def func1, do: :ok1\nend")
      File.write!(file2, "defmodule Module2 do\n  def func2, do: :ok2\nend")
      
      # Mock summaries for both files
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_summarizer, params ->
        summary = case params.code do
          code when code =~ "Module1" -> "Module1 provides func1 functionality"
          code when code =~ "Module2" -> "Module2 provides func2 functionality"
        end
        
        {:ok, %{
          "summary" => summary,
          "analysis" => %{"complexity" => 1},
          "metadata" => %{"summary_type" => "brief"}
        }}
      end)
      
      project_signal = %{
        "type" => "summarize_project",
        "data" => %{
          "project_path" => temp_dir,
          "summary_type" => "brief"
        }
      }
      
      {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, project_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.batch.started"} = start_signal}
      assert start_signal.data.total_files == 2
      
      # Wait for batch completion
      Process.sleep(200)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.batch.completed"} = complete_signal}
      assert map_size(complete_signal.data.summaries) == 2
      
      # Should also generate project overview
      assert_receive {:signal, %Jido.Signal{type: "code.project.overview.generated"} = overview_signal}
      assert overview_signal.data.module_count == 2
      
      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
  
  describe "batch_summarize signal" do
    test "summarizes multiple code snippets in batch", %{agent: agent} do
      # Mock summaries
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_summarizer, params ->
        summary = case params.code do
          code when code =~ "func1" -> "Function 1 summary"
          code when code =~ "func2" -> "Function 2 summary"
          code when code =~ "func3" -> "Function 3 summary"
        end
        
        {:ok, %{
          "summary" => summary,
          "analysis" => %{"complexity" => 1},
          "metadata" => %{}
        }}
      end)
      
      batch_signal = %{
        "type" => "batch_summarize",
        "data" => %{
          "batch_id" => "batch_123",
          "codes" => [
            %{"code" => "def func1, do: :ok1", "name" => "snippet1"},
            %{"code" => "def func2, do: :ok2", "name" => "snippet2"},
            %{"code" => "def func3, do: :ok3", "name" => "snippet3"}
          ]
        }
      }
      
      {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, batch_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.batch.started"} = start_signal}
      assert start_signal.data.batch_id == "batch_123"
      assert start_signal.data.total_items == 3
      
      # Wait for completion
      Process.sleep(300)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.batch.completed"} = complete_signal}
      assert complete_signal.data.batch_id == "batch_123"
      
      # Verify batch in state
      batch = agent.state.batch_summaries["batch_123"]
      assert batch.completed == 3
    end
  end
  
  describe "compare_summaries signal" do
    test "compares summaries of different code versions", %{agent: agent} do
      old_code = "def calculate(x), do: x * 2"
      new_code = """
      def calculate(x) do
        result = x * 2
        Logger.info("Calculated: #{result}")
        result
      end
      """
      
      # Mock summaries for both versions
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_summarizer, params ->
        summary = if String.contains?(params.code, "Logger") do
          "Enhanced calculate function with logging"
        else
          "Simple calculate function that doubles input"
        end
        
        complexity = if String.contains?(params.code, "Logger"), do: 3, else: 1
        
        {:ok, %{
          "summary" => summary,
          "analysis" => %{
            "complexity" => complexity,
            "functions" => [%{"name" => "calculate", "arity" => 1}]
          },
          "metadata" => %{}
        }}
      end)
      
      compare_signal = %{
        "type" => "compare_summaries",
        "data" => %{
          "old_code" => old_code,
          "new_code" => new_code,
          "request_id" => "compare_123"
        }
      }
      
      {:ok, _agent} = CodeSummarizerAgent.handle_signal(agent, compare_signal)
      
      # Wait for both summaries
      Process.sleep(200)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.comparison.completed"} = comparison}
      assert comparison.data.request_id == "compare_123"
      assert comparison.data.old_summary =~ "Simple calculate"
      assert comparison.data.new_summary =~ "Enhanced"
      assert comparison.data.changes.complexity_change == 2
    end
  end
  
  describe "generate_architecture_overview signal" do
    test "generates architectural analysis of project", %{agent: agent} do
      # Create test project
      {:ok, temp_dir} = Temp.mkdir("arch_overview_test")
      
      # Create different architectural layers
      web_dir = Path.join(temp_dir, "lib/my_app_web")
      core_dir = Path.join(temp_dir, "lib/my_app")
      
      File.mkdir_p!(web_dir)
      File.mkdir_p!(core_dir)
      
      File.write!(Path.join(web_dir, "controller.ex"), """
      defmodule MyAppWeb.Controller do
        use Phoenix.Controller
        def index(conn, _params), do: render(conn, "index.html")
      end
      """)
      
      File.write!(Path.join(core_dir, "worker.ex"), """
      defmodule MyApp.Worker do
        use GenServer
        def start_link(args), do: GenServer.start_link(__MODULE__, args)
      end
      """)
      
      # Mock summaries with patterns
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_summarizer, params ->
        {summary, patterns} = case params.code do
          code when code =~ "Phoenix.Controller" -> 
            {"Web controller for handling HTTP requests", ["phoenix", "controller"]}
          code when code =~ "GenServer" ->
            {"GenServer worker for background processing", ["genserver"]}
        end
        
        {:ok, %{
          "summary" => summary,
          "analysis" => %{
            "complexity" => 2,
            "patterns" => patterns,
            "dependencies" => []
          },
          "metadata" => %{}
        }}
      end)
      
      arch_signal = %{
        "type" => "generate_architecture_overview",
        "data" => %{
          "project_path" => temp_dir,
          "overview_id" => "arch_123"
        }
      }
      
      {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, arch_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.architecture.analysis.started"}}
      
      # Wait for analysis
      Process.sleep(6000) # Wait for "seems complete" heuristic
      
      assert_receive {:signal, %Jido.Signal{type: "code.architecture.overview.generated"} = overview}
      assert overview.data.overview_id == "arch_123"
      assert is_map(overview.data.layers)
      assert length(overview.data.layers[:web] || []) > 0
      assert length(overview.data.layers[:core] || []) > 0
      
      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
  
  describe "update_summary_preferences signal" do
    test "updates agent preferences", %{agent: agent} do
      prefs_signal = %{
        "type" => "update_summary_preferences",
        "data" => %{
          "default_summary_type" => "technical",
          "default_focus_level" => "function",
          "default_target_audience" => "expert",
          "include_examples" => false,
          "include_complexity" => true,
          "default_max_length" => 500,
          "summary_templates" => %{
            "custom" => "Custom template: %{content}"
          }
        }
      }
      
      {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, prefs_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.summary.preferences.updated"} = prefs}
      assert prefs.data.default_summary_type == "technical"
      assert prefs.data.default_focus_level == "function"
      assert prefs.data.default_target_audience == "expert"
      assert prefs.data.default_max_length == 500
      
      # Verify preferences in state
      assert agent.state.default_summary_type == "technical"
      assert agent.state.include_examples_by_default == false
      assert agent.state.include_complexity_by_default == true
      assert agent.state.summary_templates["custom"] =~ "Custom template"
    end
  end
  
  describe "summary history" do
    test "maintains summary history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_summarizer, _params ->
        {:ok, %{
          "summary" => "Test summary",
          "analysis" => %{"complexity" => 2},
          "metadata" => %{}
        }}
      end)
      
      # Generate multiple summaries
      for i <- 1..3 do
        signal = %{
          "type" => "summarize_code",
          "data" => %{
            "code" => "def func#{i}, do: :ok#{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.summary_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.summary_history
      assert first.id == "hist_3"
      assert first.complexity == 2
    end
  end
  
  describe "statistics tracking" do
    test "tracks summary statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_summarizer, params ->
        complexity = case params.summary_type do
          "brief" -> 1
          "comprehensive" -> 3
          "technical" -> 5
        end
        
        {:ok, %{
          "summary" => "Summary for #{params.summary_type}",
          "code" => params.code,
          "type" => params.summary_type,
          "analysis" => %{"complexity" => complexity},
          "metadata" => %{}
        }}
      end)
      
      # Generate summaries with different types
      summaries = [
        %{"summary_type" => "brief", "focus_level" => "function"},
        %{"summary_type" => "comprehensive", "focus_level" => "module"},
        %{"summary_type" => "technical", "focus_level" => "all"}
      ]
      
      for {summary, i} <- Enum.with_index(summaries) do
        signal = %{
          "type" => "summarize_code",
          "data" => Map.merge(summary, %{
            "code" => "def func#{i}, do: :ok",
            "file_path" => "file#{i}.ex"
          })
        }
        
        {:ok, agent} = CodeSummarizerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.summary_stats
      assert stats.total_summarized == 3
      assert stats.by_type["brief"] == 1
      assert stats.by_type["comprehensive"] == 1
      assert stats.by_type["technical"] == 1
      assert stats.by_focus_level["function"] == 1
      assert stats.by_focus_level["module"] == 1
      assert stats.by_focus_level["all"] == 1
      assert stats.average_code_size > 0
      assert length(stats.most_complex_modules) == 3
    end
  end
end