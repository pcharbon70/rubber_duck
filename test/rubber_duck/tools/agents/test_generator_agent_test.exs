defmodule RubberDuck.Tools.Agents.TestGeneratorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.TestGeneratorAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = TestGeneratorAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "generate_tests signal" do
    test "generates comprehensive tests for code", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_generator, params ->
        assert params.code =~ "defmodule Calculator"
        assert params.test_type == "comprehensive"
        assert params.coverage_target == 95
        
        {:ok, %{
          "tests" => """
          defmodule CalculatorTest do
            use ExUnit.Case
            
            test "add/2 adds two numbers" do
              assert Calculator.add(1, 2) == 3
            end
            
            test "add/2 handles zero" do
              assert Calculator.add(0, 5) == 5
            end
          end
          """,
          "test_count" => 2,
          "coverage_estimate" => 95,
          "test_type" => "comprehensive",
          "suggestions" => ["Consider adding property-based tests"]
        }}
      end)
      
      # Send generate_tests signal
      signal = %{
        "type" => "generate_tests",
        "data" => %{
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
          end
          """,
          "module" => "Calculator",
          "coverage_target" => 95,
          "request_id" => "test_123"
        }
      }
      
      {:ok, _updated_agent} = TestGeneratorAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, "test_generation_progress", progress_data}
      assert progress_data["status"] == "analyzing_code"
      assert progress_data["module"] == "Calculator"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive tests_generated signal
      assert_receive {:signal, "tests_generated", result_data}
      assert result_data["request_id"] == "test_123"
      assert result_data["test_count"] == 2
      assert result_data["coverage_estimate"] == 95
      assert result_data["module"] == "Calculator"
      assert result_data["suggestions"] == ["Consider adding property-based tests"]
    end
    
    test "uses custom test framework when specified", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_generator, params ->
        assert params.test_framework == "exunit_with_stream_data"
        {:ok, %{"tests" => "test code", "test_count" => 1, "coverage_estimate" => 90}}
      end)
      
      signal = %{
        "type" => "generate_tests",
        "data" => %{
          "code" => "def func, do: :ok",
          "framework" => "exunit_with_stream_data"
        }
      }
      
      {:ok, _agent} = TestGeneratorAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, "tests_generated", _}
    end
  end
  
  describe "generate_test_suite signal" do
    test "generates tests for multiple modules", %{agent: agent} do
      # Mock multiple test generations
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_generator, params ->
        module = if String.contains?(params.code, "ModuleA") do
          "ModuleA"
        else
          "ModuleB"
        end
        
        {:ok, %{
          "tests" => "defmodule #{module}Test do\n  # tests\nend",
          "test_count" => 3,
          "coverage_estimate" => 90
        }}
      end)
      
      # Generate test suite
      suite_signal = %{
        "type" => "generate_test_suite",
        "data" => %{
          "name" => "Project Test Suite",
          "modules" => [
            %{"code" => "defmodule ModuleA do\nend", "module" => "ModuleA"},
            %{"code" => "defmodule ModuleB do\nend", "module" => "ModuleB"}
          ],
          "coverage_target" => 90
        }
      }
      
      {:ok, agent} = TestGeneratorAgent.handle_signal(agent, suite_signal)
      
      assert_receive {:signal, "test_suite_started", suite_data}
      assert suite_data["module_count"] == 2
      
      # Wait for all generations
      Process.sleep(200)
      
      # Should receive suite completion
      assert_receive {:signal, "test_suite_generated", completion_data}
      assert completion_data["module_count"] == 2
      assert completion_data["average_coverage"] == 90
      
      # Verify suite in state
      suite_id = completion_data["suite_id"]
      suite = agent.state.test_suites[suite_id]
      assert suite.status == "complete"
      assert map_size(suite.tests) == 2
    end
  end
  
  describe "update_tests signal" do
    test "generates additional tests to improve coverage", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_generator, params ->
        assert params.existing_tests =~ "existing test"
        assert params.coverage_target == 95
        assert params.test_type == "unit"
        
        # Should focus on missing coverage
        assert params.code =~ "Focus on testing these aspects"
        
        {:ok, %{
          "tests" => """
          test "divide/2 handles division by zero" do
            assert_raise ArithmeticError, fn ->
              Calculator.divide(10, 0)
            end
          end
          """,
          "test_count" => 1,
          "coverage_estimate" => 95
        }}
      end)
      
      update_signal = %{
        "type" => "update_tests",
        "data" => %{
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
            def divide(a, b), do: a / b
          end
          """,
          "existing_tests" => """
          test "add/2 existing test" do
            assert Calculator.add(1, 1) == 2
          end
          """,
          "coverage_target" => 95
        }
      }
      
      {:ok, _agent} = TestGeneratorAgent.handle_signal(agent, update_signal)
      Process.sleep(100)
      
      assert_receive {:signal, "tests_generated", result_data}
      assert result_data["test_count"] == 1
    end
  end
  
  describe "analyze_coverage signal" do
    test "analyzes test coverage for a module", %{agent: agent} do
      # Add some coverage data
      agent = put_in(agent.state.coverage_data["MyModule"], %{
        percentage: 85,
        tested_functions: 17,
        total_functions: 20,
        test_count: 25
      })
      
      coverage_signal = %{
        "type" => "analyze_coverage",
        "data" => %{
          "module" => "MyModule",
          "code" => """
          defmodule MyModule do
            def func1, do: :ok
            def func2, do: :ok
          end
          """
        }
      }
      
      {:ok, agent} = TestGeneratorAgent.handle_signal(agent, coverage_signal)
      
      assert_receive {:signal, "coverage_analyzed", report}
      assert report["module"] == "MyModule"
      assert report["current_coverage"] == 85
      assert report["target_coverage"] == 90
      assert report["metrics"]["tested_functions"] == 17
      assert report["metrics"]["total_functions"] == 20
      assert report["suggestions"] != nil
      
      # Verify updated in state
      assert agent.state.coverage_data["MyModule"]["current_coverage"] == 85
    end
  end
  
  describe "generate_property_tests signal" do
    test "generates property-based tests", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_generator, params ->
        assert params.test_type == "property"
        assert params.test_framework == "exunit_with_stream_data"
        assert params.include_mocks == false
        
        {:ok, %{
          "tests" => """
          property "reversing twice returns original" do
            check all list <- list_of(integer()) do
              assert list |> Enum.reverse() |> Enum.reverse() == list
            end
          end
          """,
          "test_count" => 1,
          "coverage_estimate" => 100
        }}
      end)
      
      property_signal = %{
        "type" => "generate_property_tests",
        "data" => %{
          "code" => "def reverse(list), do: Enum.reverse(list)",
          "properties" => ["idempotence", "length_preservation"],
          "request_id" => "prop_123"
        }
      }
      
      {:ok, _agent} = TestGeneratorAgent.handle_signal(agent, property_signal)
      
      assert_receive {:signal, "property_generation_started", start_data}
      assert start_data["properties"] == ["idempotence", "length_preservation"]
      
      Process.sleep(100)
      
      assert_receive {:signal, "tests_generated", result_data}
      assert result_data["tests"] =~ "property"
    end
  end
  
  describe "suggest_test_improvements signal" do
    test "suggests improvements for existing tests", %{agent: agent} do
      suggest_signal = %{
        "type" => "suggest_test_improvements",
        "data" => %{
          "module" => "Calculator",
          "tests" => """
          defmodule CalculatorTest do
            use ExUnit.Case
            
            test "add works" do
              Calculator.add(1, 2)
            end
            
            test "multiply works" do
              result = Calculator.multiply(3, 4)
            end
          end
          """,
          "code" => """
          defmodule Calculator do
            def add(a, b), do: a + b
            def multiply(a, b), do: a * b
            def divide(a, b), do: a / b
          end
          """
        }
      }
      
      {:ok, _agent} = TestGeneratorAgent.handle_signal(agent, suggest_signal)
      
      assert_receive {:signal, "test_suggestions", suggestions_data}
      assert suggestions_data["module"] == "Calculator"
      assert suggestions_data["suggestions"]["missing_assertions"] != nil
      assert suggestions_data["suggestions"]["untested_edge_cases"] != nil
      assert suggestions_data["quality_score"] != nil
    end
  end
  
  describe "test suite management" do
    test "tracks active test suite", %{agent: agent} do
      # Create a test suite
      suite_signal = %{
        "type" => "generate_test_suite",
        "data" => %{
          "suite_id" => "suite_123",
          "name" => "Active Suite",
          "modules" => []
        }
      }
      
      {:ok, agent} = TestGeneratorAgent.handle_signal(agent, suite_signal)
      
      assert agent.state.active_suite == "suite_123"
      assert agent.state.test_suites["suite_123"].name == "Active Suite"
    end
  end
  
  describe "generation history" do
    test "maintains generation history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :test_generator, _params ->
        {:ok, %{
          "tests" => "test code",
          "test_count" => 2,
          "coverage_estimate" => 90,
          "test_type" => "unit"
        }}
      end)
      
      # Generate multiple tests
      for i <- 1..3 do
        signal = %{
          "type" => "generate_tests",
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "module" => "Module#{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = TestGeneratorAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.generation_history) == 3
      
      # Verify most recent first
      [first | _] = agent.state.generation_history
      assert first.id == "hist_3"
      assert first.module == "Module3"
    end
    
    test "respects history size limit", %{agent: agent} do
      # Set small limit
      agent = put_in(agent.state.max_history_size, 2)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :test_generator, _params ->
        {:ok, %{"tests" => "test", "test_count" => 1, "coverage_estimate" => 90}}
      end)
      
      # Generate 3 tests
      for i <- 1..3 do
        signal = %{
          "type" => "generate_tests",
          "data" => %{
            "code" => "def func#{i}, do: :ok",
            "request_id" => "size_#{i}"
          }
        }
        
        {:ok, agent} = TestGeneratorAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Should only have 2 entries
      assert length(agent.state.generation_history) == 2
    end
  end
  
  describe "statistics tracking" do
    test "tracks test generation statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_generator, params ->
        test_type = params.test_type
        {:ok, %{
          "tests" => "tests",
          "test_count" => if(test_type == "unit", do: 3, else: 2),
          "coverage_estimate" => 85,
          "test_type" => test_type
        }}
      end)
      
      # Generate unit tests
      signal1 = %{
        "type" => "generate_tests",
        "data" => %{
          "code" => "code",
          "test_type" => "unit",
          "module" => "Mod1"
        }
      }
      
      {:ok, agent} = TestGeneratorAgent.handle_signal(agent, signal1)
      Process.sleep(100)
      
      # Generate property tests
      signal2 = %{
        "type" => "generate_tests",
        "data" => %{
          "code" => "code",
          "test_type" => "property",
          "module" => "Mod2"
        }
      }
      
      {:ok, agent} = TestGeneratorAgent.handle_signal(agent, signal2)
      Process.sleep(100)
      
      # Check statistics
      stats = agent.state.test_stats
      assert stats.total_tests_generated == 5  # 3 + 2
      assert stats.by_type["unit"] == 3
      assert stats.by_type["property"] == 2
      assert stats.modules_tested == 2
      assert stats.average_coverage == 85
    end
  end
  
  describe "coverage goals" do
    test "uses module-specific coverage goals", %{agent: agent} do
      # Set specific goal for a module
      agent = put_in(agent.state.coverage_goals["SpecialModule"], 100)
      
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_generator, params ->
        assert params.coverage_target == 100
        {:ok, %{"tests" => "test", "test_count" => 1, "coverage_estimate" => 100}}
      end)
      
      signal = %{
        "type" => "generate_tests",
        "data" => %{
          "code" => "code",
          "module" => "SpecialModule"
        }
      }
      
      {:ok, _agent} = TestGeneratorAgent.handle_signal(agent, signal)
    end
  end
end