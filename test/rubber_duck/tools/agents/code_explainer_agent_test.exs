defmodule RubberDuck.Tools.Agents.CodeExplainerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeExplainerAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeExplainerAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "explain_code signal" do
    test "explains code with comprehensive analysis", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, params ->
        assert params.code =~ "defmodule Calculator"
        assert params.explanation_type == "comprehensive"
        assert params.target_audience == "intermediate"
        assert params.include_examples == true
        
        {:ok, %{
          "explanation" => """
          This Calculator module provides basic arithmetic operations.
          The add/2 function takes two numbers and returns their sum.
          It uses pattern matching to handle different input types.
          """,
          "code" => params.code,
          "type" => "comprehensive",
          "analysis" => %{
            "functions" => [%{"name" => "add", "arity" => 2}],
            "modules" => [%{"name" => "Calculator"}],
            "complexity" => 1
          },
          "examples" => ["Calculator.add(1, 2)  # => 3"]
        }}
      end)
      
      # Send explain_code signal
      signal = %{
        "type" => "explain_code",
        "data" => %{
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
          end
          """,
          "request_id" => "explain_123"
        }
      }
      
      {:ok, _updated_agent} = CodeExplainerAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, %Jido.Signal{type: "code.explanation.progress"} = progress_signal}
      assert progress_signal.data.status == "analyzing"
      assert progress_signal.data.explanation_type == "comprehensive"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive explained signal
      assert_receive {:signal, %Jido.Signal{type: "code.explained"} = result_signal}
      assert result_signal.data.request_id == "explain_123"
      assert result_signal.data.explanation =~ "Calculator module"
      assert result_signal.data.type == "comprehensive"
      assert result_signal.data.examples != nil
    end
    
    test "uses custom audience and explanation type", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, params ->
        assert params.target_audience == "beginner"
        assert params.explanation_type == "summary"
        assert params.include_examples == false
        
        {:ok, %{
          "explanation" => "Simple function that adds two numbers.",
          "code" => params.code,
          "type" => "summary",
          "analysis" => %{"complexity" => 1}
        }}
      end)
      
      signal = %{
        "type" => "explain_code",
        "data" => %{
          "code" => "def add(a, b), do: a + b",
          "explanation_type" => "summary",
          "target_audience" => "beginner",
          "include_examples" => false
        }
      }
      
      {:ok, _agent} = CodeExplainerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.explained"}}
    end
    
    test "applies agent default preferences", %{agent: agent} do
      # Set custom defaults
      agent = agent
      |> put_in([:state, :default_audience], "expert")
      |> put_in([:state, :default_explanation_type], "technical")
      |> put_in([:state, :include_examples_by_default], false)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, params ->
        assert params.target_audience == "expert"
        assert params.explanation_type == "technical"
        assert params.include_examples == false
        
        {:ok, %{
          "explanation" => "Technical analysis...",
          "code" => params.code,
          "type" => "technical",
          "analysis" => %{}
        }}
      end)
      
      signal = %{
        "type" => "explain_code",
        "data" => %{
          "code" => "def func, do: :ok"
        }
      }
      
      {:ok, _agent} = CodeExplainerAgent.handle_signal(agent, signal)
    end
  end
  
  describe "generate_documentation signal" do
    test "generates docstring documentation", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, params ->
        assert params.explanation_type == "docstring"
        assert params.include_examples == true
        assert "parameters" in params.focus_areas
        
        {:ok, %{
          "explanation" => """
          @doc \"\"\"
          Adds two numbers together.
          
          ## Parameters
          - a: First number
          - b: Second number
          
          ## Examples
          
              iex> Calculator.add(1, 2)
              3
          \"\"\"
          """,
          "code" => params.code,
          "type" => "docstring",
          "analysis" => %{}
        }}
      end)
      
      signal = %{
        "type" => "generate_documentation",
        "data" => %{
          "code" => "def add(a, b), do: a + b"
        }
      }
      
      {:ok, _agent} = CodeExplainerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should receive both explained and documentation generated signals
      assert_receive {:signal, %Jido.Signal{type: "code.explained"}}
      assert_receive {:signal, %Jido.Signal{type: "code.documentation.generated"} = doc_signal}
      assert doc_signal.data.documentation =~ "@doc"
      assert doc_signal.data.format == "elixir_docs"
    end
  end
  
  describe "explain_project signal" do
    test "explains multiple project files", %{agent: agent} do
      # Create temporary project structure
      {:ok, temp_dir} = Temp.mkdir("explain_project_test")
      
      lib_dir = Path.join(temp_dir, "lib")
      File.mkdir_p!(lib_dir)
      
      file1 = Path.join(lib_dir, "module1.ex")
      file2 = Path.join(lib_dir, "module2.ex")
      
      File.write!(file1, "defmodule Module1 do\n  def func1, do: :ok1\nend")
      File.write!(file2, "defmodule Module2 do\n  def func2, do: :ok2\nend")
      
      # Mock explanations for both files
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_explainer, params ->
        explanation = case params.code do
          code when code =~ "Module1" -> "Explanation for Module1"
          code when code =~ "Module2" -> "Explanation for Module2"
        end
        
        {:ok, %{
          "explanation" => explanation,
          "code" => params.code,
          "type" => "summary",
          "analysis" => %{"complexity" => 1}
        }}
      end)
      
      project_signal = %{
        "type" => "explain_project",
        "data" => %{
          "project_path" => temp_dir,
          "explanation_type" => "summary"
        }
      }
      
      {:ok, agent} = CodeExplainerAgent.handle_signal(agent, project_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.explanation.batch.started"} = start_signal}
      assert start_signal.data.total_files == 2
      
      # Wait for batch completion
      Process.sleep(200)
      
      assert_receive {:signal, %Jido.Signal{type: "code.explanation.batch.completed"} = complete_signal}
      assert map_size(complete_signal.data.explanations) == 2
      
      # Verify batch in state
      batch_id = start_signal.data.batch_id
      batch = agent.state.batch_explanations[batch_id]
      assert batch.completed == 2
      
      # Cleanup
      File.rm_rf!(temp_dir)
    end
  end
  
  describe "explain_diff signal" do
    test "explains code changes and their impact", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, params ->
        assert params.explanation_type == "comprehensive"
        assert "changes" in params.focus_areas
        assert "impact" in params.focus_areas
        
        {:ok, %{
          "explanation" => """
          The function was modified to include error handling.
          Added a guard clause to prevent division by zero.
          This improves the robustness of the function.
          """,
          "code" => params.code,
          "type" => "comprehensive",
          "analysis" => %{"complexity" => 2}
        }}
      end)
      
      old_code = "def divide(a, b), do: a / b"
      new_code = """
      def divide(a, b) when b != 0, do: a / b
      def divide(_, 0), do: {:error, :division_by_zero}
      """
      
      diff_signal = %{
        "type" => "explain_diff",
        "data" => %{
          "old_code" => old_code,
          "new_code" => new_code,
          "change_type" => "enhancement",
          "request_id" => "diff_123"
        }
      }
      
      {:ok, _agent} = CodeExplainerAgent.handle_signal(agent, diff_signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.diff.explained"} = diff_signal}
      assert diff_signal.data.old_code == old_code
      assert diff_signal.data.new_code == new_code
      assert diff_signal.data.change_type == "enhancement"
      assert diff_signal.data.explanation =~ "error handling"
    end
  end
  
  describe "create_tutorial signal" do
    test "creates step-by-step learning tutorial", %{agent: agent} do
      # Mock explanations for tutorial steps
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_explainer, params ->
        step_explanation = case params.code do
          code when code =~ "defmodule" -> "This defines a module structure"
          code when code =~ "def " -> "This defines functions"
          code when code =~ "do:" -> "This is the function implementation"
        end
        
        {:ok, %{
          "explanation" => step_explanation,
          "code" => params.code,
          "type" => "beginner",
          "analysis" => %{}
        }}
      end)
      
      tutorial_signal = %{
        "type" => "create_tutorial",
        "data" => %{
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
            def subtract(a, b), do: a - b
          end
          """,
          "title" => "Calculator Tutorial",
          "difficulty" => "beginner"
        }
      }
      
      {:ok, agent} = CodeExplainerAgent.handle_signal(agent, tutorial_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.tutorial.started"} = start_signal}
      assert start_signal.data.title == "Calculator Tutorial"
      assert start_signal.data.difficulty == "beginner"
      assert start_signal.data.total_steps == 3
      
      # Wait for tutorial completion
      Process.sleep(300)
      
      assert_receive {:signal, %Jido.Signal{type: "code.tutorial.created"} = complete_signal}
      tutorial = complete_signal.data.tutorial
      assert length(tutorial.steps) == 3
      assert Enum.all?(tutorial.steps, &Map.has_key?(&1, :explanation))
      
      # Verify tutorial in state
      tutorial_id = complete_signal.data.tutorial_id
      stored_tutorial = agent.state.tutorials[tutorial_id]
      assert stored_tutorial.title == "Calculator Tutorial"
    end
  end
  
  describe "update_explanation_preferences signal" do
    test "updates agent preferences", %{agent: agent} do
      prefs_signal = %{
        "type" => "update_explanation_preferences",
        "data" => %{
          "default_audience" => "expert",
          "default_explanation_type" => "technical",
          "include_examples" => false,
          "style_preferences" => %{
            "expert" => %{"tone" => "formal", "depth" => "deep"}
          }
        }
      }
      
      {:ok, agent} = CodeExplainerAgent.handle_signal(agent, prefs_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.explanation.preferences.updated"} = prefs_signal}
      assert prefs_signal.data.default_audience == "expert"
      assert prefs_signal.data.default_explanation_type == "technical"
      assert prefs_signal.data.include_examples_by_default == false
      
      # Verify preferences in state
      assert agent.state.default_audience == "expert"
      assert agent.state.default_explanation_type == "technical"
      assert agent.state.include_examples_by_default == false
      assert agent.state.style_preferences["expert"]["tone"] == "formal"
    end
  end
  
  describe "explanation history" do
    test "maintains explanation history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_explainer, _params ->
        {:ok, %{
          "explanation" => "Code explanation",
          "code" => "def func, do: :ok",
          "type" => "comprehensive",
          "analysis" => %{"complexity" => 2}
        }}
      end)
      
      # Generate multiple explanations
      for i <- 1..3 do
        signal = %{
          "type" => "explain_code",
          "data" => %{
            "code" => "def func#{i}, do: :ok#{i}",
            "target_audience" => "intermediate",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeExplainerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.explanation_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.explanation_history
      assert first.id == "hist_3"
      assert first.target_audience == "intermediate"
      assert first.explanation_type == "comprehensive"
    end
    
    test "respects history size limit", %{agent: agent} do
      # Set small limit
      agent = put_in(agent.state.max_history_size, 2)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_explainer, _params ->
        {:ok, %{
          "explanation" => "explanation",
          "code" => "code",
          "type" => "summary",
          "analysis" => %{}
        }}
      end)
      
      # Generate 3 explanations
      for i <- 1..3 do
        signal = %{
          "type" => "explain_code",
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "request_id" => "limit_#{i}"
          }
        }
        
        {:ok, agent} = CodeExplainerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Should only keep 2 most recent
      assert length(agent.state.explanation_history) == 2
    end
  end
  
  describe "statistics tracking" do
    test "tracks explanation statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_explainer, params ->
        complexity = case params.target_audience do
          "beginner" -> 1
          "intermediate" -> 3
          "expert" -> 5
        end
        
        {:ok, %{
          "explanation" => "explanation",
          "code" => params.code,
          "type" => params.explanation_type,
          "analysis" => %{"complexity" => complexity}
        }}
      end)
      
      # Generate explanations with different types and audiences
      explanations = [
        %{"explanation_type" => "summary", "target_audience" => "beginner"},
        %{"explanation_type" => "comprehensive", "target_audience" => "intermediate"},
        %{"explanation_type" => "technical", "target_audience" => "expert"}
      ]
      
      for {explanation, i} <- Enum.with_index(explanations) do
        signal = %{
          "type" => "explain_code",
          "data" => Map.merge(explanation, %{
            "code" => "def func#{i}, do: :ok"
          })
        }
        
        {:ok, agent} = CodeExplainerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.explanation_stats
      assert stats.total_explained == 3
      assert stats.by_type["summary"] == 1
      assert stats.by_type["comprehensive"] == 1
      assert stats.by_type["technical"] == 1
      assert stats.by_audience["beginner"] == 1
      assert stats.by_audience["intermediate"] == 1
      assert stats.by_audience["expert"] == 1
      assert stats.average_complexity == 3.0  # (1 + 3 + 5) / 3
    end
  end
  
  describe "code type detection" do
    test "detects different code types correctly", %{agent: agent} do
      code_types = [
        {"defmodule Test do\nend", "module"},
        {"def hello, do: :world", "function"},
        {"defp private_func, do: :ok", "private_function"},
        {"use GenServer", "genserver"},
        {"use Phoenix.Controller", "phoenix"},
        {"test \"something\" do\nend", "test"}
      ]
      
      for {code, expected_type} <- code_types do
        expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_explainer, _params ->
          {:ok, %{
            "explanation" => "explanation",
            "code" => code,
            "type" => "summary",
            "analysis" => %{}
          }}
        end)
        
        signal = %{
          "type" => "explain_code",
          "data" => %{
            "code" => code,
            "request_id" => "type_test_#{expected_type}"
          }
        }
        
        {:ok, agent} = CodeExplainerAgent.handle_signal(agent, signal)
        Process.sleep(50)
        
        # Verify code type was detected correctly in history
        [latest | _] = agent.state.explanation_history
        assert latest.code_type == expected_type
      end
    end
  end
end