defmodule RubberDuck.Tools.Agents.CodeGeneratorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeGeneratorAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeGeneratorAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "generate_code signal" do
    test "generates code successfully", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_generator, params ->
        assert params.description == "Create a function to calculate factorial"
        assert params.style == "functional"
        
        {:ok, %{
          "code" => """
          def factorial(0), do: 1
          def factorial(n) when n > 0, do: n * factorial(n - 1)
          """,
          "language" => "elixir",
          "description" => params.description
        }}
      end)
      
      # Send generate_code signal
      signal = %{
        "type" => "generate_code",
        "data" => %{
          "description" => "Create a function to calculate factorial",
          "style" => "functional",
          "request_id" => "gen_123",
          "user_id" => "user_1",
          "project_id" => "proj_1"
        }
      }
      
      {:ok, _updated_agent} = CodeGeneratorAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, "generation_progress", progress_data}
      assert progress_data["request_id"] == "gen_123"
      assert progress_data["status"] == "started"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive code_generated signal
      assert_receive {:signal, "code_generated", result_data}
      assert result_data["request_id"] == "gen_123"
      assert result_data["code"] =~ "factorial"
      assert result_data["metadata"]["style"] == "functional"
      assert result_data["metadata"]["has_tests"] == false
    end
    
    test "generates code with tests when requested", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_generator, params ->
        assert params.include_tests == true
        
        {:ok, %{
          "code" => "def add(a, b), do: a + b",
          "tests" => """
          test "adds two numbers" do
            assert add(1, 2) == 3
          end
          """,
          "language" => "elixir",
          "description" => params.description
        }}
      end)
      
      signal = %{
        "type" => "generate_code",
        "data" => %{
          "description" => "Create an add function",
          "include_tests" => true
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, "code_generated", result_data}
      assert result_data["tests"] =~ "test"
      assert result_data["metadata"]["has_tests"] == true
    end
    
    test "adds generation to history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_generator, _ ->
        {:ok, %{
          "code" => "def hello, do: :world",
          "language" => "elixir",
          "description" => "hello function"
        }}
      end)
      
      signal = %{
        "type" => "generate_code",
        "data" => %{
          "description" => "Create hello function",
          "request_id" => "hist_1"
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Check generation was added to history
      assert length(agent.state.generation_history) == 1
      [entry | _] = agent.state.generation_history
      assert entry.id == "hist_1"
      assert entry.code =~ "hello"
    end
  end
  
  describe "generate_from_template signal" do
    test "generates code from saved template", %{agent: agent} do
      # Save a template first
      save_signal = %{
        "type" => "save_template",
        "data" => %{
          "name" => "genserver_template",
          "description" => "Create a GenServer named {{name}} with {{features}}",
          "variables" => ["name", "features"],
          "context" => %{"type" => "genserver"},
          "style" => "defensive"
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, save_signal)
      
      assert_receive {:signal, "template_saved", _}
      
      # Mock the generation
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_generator, params ->
        assert params.description =~ "MyServer"
        assert params.description =~ "state management"
        assert params.style == "defensive"
        
        {:ok, %{
          "code" => "defmodule MyServer do\n  use GenServer\n  # ...\nend",
          "language" => "elixir"
        }}
      end)
      
      # Generate from template
      generate_signal = %{
        "type" => "generate_from_template",
        "data" => %{
          "template" => "genserver_template",
          "variables" => %{
            "name" => "MyServer",
            "features" => "state management"
          },
          "request_id" => "template_gen_1"
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, generate_signal)
      
      assert_receive {:signal, "template_applied", template_data}
      assert template_data["template"] == "genserver_template"
      
      Process.sleep(100)
      
      assert_receive {:signal, "code_generated", result_data}
      assert result_data["code"] =~ "MyServer"
    end
    
    test "handles missing template gracefully", %{agent: agent} do
      signal = %{
        "type" => "generate_from_template",
        "data" => %{
          "template" => "non_existent",
          "request_id" => "missing_1"
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, signal)
      
      assert_receive {:signal, "generation_error", error_data}
      assert error_data["error"] =~ "Template not found"
      assert error_data["request_id"] == "missing_1"
    end
  end
  
  describe "batch_generate signal" do
    test "processes multiple generation requests", %{agent: agent} do
      # Mock multiple executions
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_generator, params ->
        code = case params.description do
          desc when desc =~ "add" -> "def add(a, b), do: a + b"
          desc when desc =~ "multiply" -> "def multiply(a, b), do: a * b"
          desc when desc =~ "divide" -> "def divide(a, b), do: a / b"
        end
        
        {:ok, %{
          "code" => code,
          "language" => "elixir",
          "description" => params.description
        }}
      end)
      
      batch_signal = %{
        "type" => "batch_generate",
        "data" => %{
          "batch_id" => "batch_123",
          "requests" => [
            %{"description" => "Create add function", "id" => "add"},
            %{"description" => "Create multiply function", "id" => "multiply"},
            %{"description" => "Create divide function", "id" => "divide"}
          ]
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, batch_signal)
      
      assert_receive {:signal, "batch_started", batch_data}
      assert batch_data["batch_id"] == "batch_123"
      assert batch_data["total_requests"] == 3
      
      # Wait for all to complete
      Process.sleep(300)
      
      assert_receive {:signal, "batch_completed", completion_data}
      assert completion_data["batch_id"] == "batch_123"
      assert completion_data["total"] == 3
      assert length(completion_data["results"]) == 3
      
      # Verify batch results in state
      batch_result = agent.state.batch_results["batch_123"]
      assert batch_result.completed == 3
    end
  end
  
  describe "refine_generation signal" do
    test "refines existing code with improvements", %{agent: agent} do
      original_code = """
      def calculate(x, y) do
        x + y
      end
      """
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_generator, params ->
        assert params.description =~ "Refine the following Elixir code"
        assert params.description =~ "Add documentation"
        assert params.description =~ "Add type specs"
        assert params.context["refinement"] == true
        assert params.context["original_code"] == original_code
        
        {:ok, %{
          "code" => """
          @doc "Calculates the sum of two numbers"
          @spec calculate(number(), number()) :: number()
          def calculate(x, y) do
            x + y
          end
          """,
          "language" => "elixir"
        }}
      end)
      
      refine_signal = %{
        "type" => "refine_generation",
        "data" => %{
          "original_code" => original_code,
          "refinements" => [
            "Add documentation",
            "Add type specs"
          ],
          "request_id" => "refine_1"
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, refine_signal)
      Process.sleep(100)
      
      assert_receive {:signal, "code_generated", result_data}
      assert result_data["code"] =~ "@doc"
      assert result_data["code"] =~ "@spec"
    end
  end
  
  describe "get_generation_history signal" do
    test "retrieves filtered and paginated history", %{agent: agent} do
      # Add some history entries
      history_entries = [
        %{
          id: "h1",
          description: "Create add function",
          code: "def add(a, b), do: a + b",
          tests: nil,
          style: "functional",
          generated_at: DateTime.utc_now()
        },
        %{
          id: "h2",
          description: "Create multiply function",
          code: "def multiply(a, b), do: a * b",
          tests: "test multiply",
          style: "defensive",
          generated_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        },
        %{
          id: "h3",
          description: "Create divide function",
          code: "def divide(a, b), do: a / b",
          tests: nil,
          style: "functional",
          generated_at: DateTime.add(DateTime.utc_now(), -7200, :second)
        }
      ]
      
      agent = put_in(agent.state.generation_history, history_entries)
      agent = put_in(agent.state.generation_stats.total_generated, 3)
      
      # Get all history
      history_signal = %{
        "type" => "get_generation_history",
        "data" => %{
          "page" => 1,
          "page_size" => 2
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, history_signal)
      
      assert_receive {:signal, "history_retrieved", history_data}
      assert length(history_data["history"]) == 2
      assert history_data["pagination"]["page"] == 1
      assert history_data["pagination"]["total"] == 3
      assert history_data["pagination"]["has_next"] == true
      assert history_data["total_generated"] == 3
      
      # Test filtering by style
      filter_signal = %{
        "type" => "get_generation_history",
        "data" => %{
          "filter" => %{"style" => "functional"}
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, filter_signal)
      
      assert_receive {:signal, "history_retrieved", filtered_data}
      assert length(filtered_data["history"]) == 2
      assert Enum.all?(filtered_data["history"], &(&1.style == "functional"))
      
      # Test filtering by has_tests
      tests_signal = %{
        "type" => "get_generation_history",
        "data" => %{
          "filter" => %{"has_tests" => true}
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, tests_signal)
      
      assert_receive {:signal, "history_retrieved", tests_data}
      assert length(tests_data["history"]) == 1
      assert hd(tests_data["history"]).id == "h2"
    end
    
    test "searches history by content", %{agent: agent} do
      history_entries = [
        %{
          id: "h1",
          description: "Create factorial function",
          code: "def factorial(n), do: ...",
          generated_at: DateTime.utc_now()
        },
        %{
          id: "h2",
          description: "Create fibonacci function",
          code: "def fibonacci(n), do: ...",
          generated_at: DateTime.utc_now()
        }
      ]
      
      agent = put_in(agent.state.generation_history, history_entries)
      
      search_signal = %{
        "type" => "get_generation_history",
        "data" => %{
          "filter" => %{"search" => "factorial"}
        }
      }
      
      {:ok, _agent} = CodeGeneratorAgent.handle_signal(agent, search_signal)
      
      assert_receive {:signal, "history_retrieved", search_data}
      assert length(search_data["history"]) == 1
      assert hd(search_data["history"]).id == "h1"
    end
  end
  
  describe "statistics tracking" do
    test "updates generation statistics correctly", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_generator, params ->
        code = if params.include_tests do
          %{"code" => "def test, do: :ok", "tests" => "test code"}
        else
          %{"code" => "def hello, do: :world"}
        end
        
        {:ok, Map.merge(code, %{"language" => "elixir"})}
      end)
      
      # Generate without tests
      signal1 = %{
        "type" => "generate_code",
        "data" => %{
          "description" => "Create hello",
          "style" => "functional"
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, signal1)
      Process.sleep(100)
      
      # Generate with tests
      signal2 = %{
        "type" => "generate_code",
        "data" => %{
          "description" => "Create test",
          "style" => "functional",
          "include_tests" => true
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, signal2)
      Process.sleep(100)
      
      # Check statistics
      stats = agent.state.generation_stats
      assert stats.total_generated == 2
      assert stats.by_style["functional"] == 2
      assert stats.with_tests == 1
      assert stats.average_length > 0
    end
  end
  
  describe "template management" do
    test "saves and manages templates", %{agent: agent} do
      template_signal = %{
        "type" => "save_template",
        "data" => %{
          "name" => "test_template",
          "description" => "Generate {{type}} with name {{name}}",
          "variables" => ["type", "name"],
          "style" => "idiomatic"
        }
      }
      
      {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, template_signal)
      
      assert_receive {:signal, "template_saved", save_data}
      assert save_data["name"] == "test_template"
      
      # Verify template in state
      template = agent.state.templates["test_template"]
      assert template["description"] =~ "{{type}}"
      assert template["variables"] == ["type", "name"]
      assert template["style"] == "idiomatic"
      assert template["created_at"] != nil
    end
  end
  
  describe "history size limits" do
    test "respects max history size", %{agent: agent} do
      # Set small limit for testing
      agent = put_in(agent.state.max_history_size, 3)
      
      # Mock multiple generations
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 5, fn :code_generator, params ->
        {:ok, %{
          "code" => "def func#{System.unique_integer()}, do: :ok",
          "language" => "elixir",
          "description" => params.description
        }}
      end)
      
      # Generate 5 times
      for i <- 1..5 do
        signal = %{
          "type" => "generate_code",
          "data" => %{
            "description" => "Function #{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeGeneratorAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Should only have 3 most recent entries
      assert length(agent.state.generation_history) == 3
      
      # Verify it's the most recent ones
      [first | _] = agent.state.generation_history
      assert first.id == "hist_5"
    end
  end
end