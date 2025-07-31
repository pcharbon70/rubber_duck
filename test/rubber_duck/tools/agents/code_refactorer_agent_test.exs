defmodule RubberDuck.Tools.Agents.CodeRefactorerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeRefactorerAgent
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = CodeRefactorerAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "refactor_code signal" do
    test "refactors code with default settings", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_refactorer, params ->
        assert params.code =~ "magic_number = 42"
        assert params.instruction == "Extract magic numbers into constants"
        assert params.refactoring_type == "general"
        assert params.preserve_comments == true
        assert params.style_guide == "credo"
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => """
          @magic_constant 42
          
          def calculate(x) do
            x * @magic_constant
          end
          """,
          "changes" => %{
            "lines_changed" => 3,
            "functions_affected" => 1,
            "patterns_applied" => ["extract_constant"]
          },
          "refactoring_type" => "general",
          "instruction" => params.instruction
        }}
      end)
      
      # Send refactor_code signal
      signal = %{
        "type" => "refactor_code",
        "data" => %{
          "code" => """
          def calculate(x) do
            magic_number = 42
            x * magic_number
          end
          """,
          "instruction" => "Extract magic numbers into constants",
          "request_id" => "refactor_123"
        }
      }
      
      {:ok, _updated_agent} = CodeRefactorerAgent.handle_signal(agent, signal)
      
      # Should receive progress signal
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.progress"} = progress_signal}
      assert progress_signal.data.status == "analyzing"
      assert progress_signal.data.instruction =~ "Extract magic"
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive refactored signal
      assert_receive {:signal, %Jido.Signal{type: "code.refactored"} = result_signal}
      assert result_signal.data.request_id == "refactor_123"
      assert result_signal.data.refactored_code =~ "@magic_constant"
      assert result_signal.data.complexity_reduction >= 0
    end
    
    test "uses custom refactoring parameters", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_refactorer, params ->
        assert params.refactoring_type == "pattern_matching"
        assert params.preserve_comments == false
        assert params.style_guide == "custom"
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => "case value do\n  :ok -> handle_ok()\n  :error -> handle_error()\nend",
          "changes" => %{"patterns_applied" => ["if_to_case"]},
          "refactoring_type" => params.refactoring_type,
          "instruction" => params.instruction
        }}
      end)
      
      signal = %{
        "type" => "refactor_code",
        "data" => %{
          "code" => "if value == :ok, do: handle_ok(), else: handle_error()",
          "instruction" => "Convert to pattern matching",
          "refactoring_type" => "pattern_matching",
          "preserve_comments" => false,
          "style_guide" => "custom"
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactored"}}
    end
    
    test "auto-validates refactoring when enabled", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_refactorer, _params ->
        {:ok, %{
          "original_code" => "def add(a, b), do: a + b",
          "refactored_code" => "def add(a, b) when is_number(a) and is_number(b), do: a + b",
          "changes" => %{},
          "refactoring_type" => "general",
          "instruction" => "Add guards"
        }}
      end)
      
      signal = %{
        "type" => "refactor_code",
        "data" => %{
          "code" => "def add(a, b), do: a + b",
          "instruction" => "Add guards",
          "auto_validate" => true
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should receive both refactored and validation signals
      assert_receive {:signal, %Jido.Signal{type: "code.refactored"}}
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.validated"} = validation}
      assert validation.data.is_valid == true
    end
  end
  
  describe "batch_refactor signal" do
    test "refactors multiple files in batch", %{agent: agent} do
      # Mock multiple refactoring operations
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_refactorer, params ->
        refactored = case params.code do
          code when code =~ "func1" -> "def func1, do: :refactored1"
          code when code =~ "func2" -> "def func2, do: :refactored2"
          code when code =~ "func3" -> "def func3, do: :refactored3"
        end
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => refactored,
          "changes" => %{"lines_changed" => 1},
          "refactoring_type" => params.refactoring_type,
          "instruction" => params.instruction
        }}
      end)
      
      batch_signal = %{
        "type" => "batch_refactor",
        "data" => %{
          "batch_id" => "batch_123",
          "instruction" => "Simplify all functions",
          "files" => [
            %{"code" => "def func1, do: complex_logic1()", "path" => "file1.ex"},
            %{"code" => "def func2, do: complex_logic2()", "path" => "file2.ex"},
            %{"code" => "def func3, do: complex_logic3()", "path" => "file3.ex"}
          ]
        }
      }
      
      {:ok, agent} = CodeRefactorerAgent.handle_signal(agent, batch_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.batch.started"} = start_signal}
      assert start_signal.data.batch_id == "batch_123"
      assert start_signal.data.total_files == 3
      
      # Wait for all refactorings to complete
      Process.sleep(300)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.batch.completed"} = complete_signal}
      assert complete_signal.data.batch_id == "batch_123"
      assert map_size(complete_signal.data.results) == 3
      
      # Verify batch in state
      batch = agent.state.batch_refactorings["batch_123"]
      assert batch.completed == 3
    end
  end
  
  describe "suggest_refactorings signal" do
    test "analyzes code and suggests improvements", %{agent: agent} do
      complex_code = """
      def process(data) do
        if data != nil do
          if is_list(data) do
            if length(data) > 0 do
              Enum.map(data, fn x -> x * 2 end)
            else
              []
            end
          else
            raise "Not a list!"
          end
        else
          nil
        end
      end
      """
      
      # Mock refactoring for pattern matching suggestion
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_refactorer, params ->
        assert params.instruction =~ "pattern matching"
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => """
          def process(nil), do: nil
          def process([]), do: []
          def process(data) when is_list(data) do
            Enum.map(data, fn x -> x * 2 end)
          end
          def process(_), do: {:error, :not_a_list}
          """,
          "changes" => %{"patterns_applied" => ["nested_if_to_pattern_matching"]},
          "refactoring_type" => "pattern_matching",
          "instruction" => params.instruction
        }}
      end)
      
      suggest_signal = %{
        "type" => "suggest_refactorings",
        "data" => %{
          "code" => complex_code,
          "threshold" => "medium",
          "request_id" => "suggest_123"
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, suggest_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.suggested"} = suggestions}
      assert suggestions.data.request_id == "suggest_123"
      assert length(suggestions.data.suggestions) > 0
      
      # Wait for actual refactoring
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactored"} = result}
      assert result.data.refactored_code =~ "def process(nil)"
    end
  end
  
  describe "apply_pattern signal" do
    test "applies saved refactoring pattern", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :code_refactorer, params ->
        assert params.instruction == "Extract magic numbers and strings into named constants"
        assert params.refactoring_type == "extract_function"
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => "@timeout 5000\n\ndef wait, do: Process.sleep(@timeout)",
          "changes" => %{"patterns_applied" => ["extract_constants"]},
          "refactoring_type" => params.refactoring_type,
          "instruction" => params.instruction
        }}
      end)
      
      pattern_signal = %{
        "type" => "apply_pattern",
        "data" => %{
          "pattern_name" => "extract_constants",
          "code" => "def wait, do: Process.sleep(5000)"
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, pattern_signal)
      Process.sleep(100)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactored"} = result}
      assert result.data.refactored_code =~ "@timeout"
    end
    
    test "handles unknown pattern gracefully", %{agent: agent} do
      signal = %{
        "type" => "apply_pattern",
        "data" => %{
          "pattern_name" => "unknown_pattern",
          "code" => "def test, do: :ok"
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.error"} = error}
      assert error.data.error =~ "Pattern 'unknown_pattern' not found"
      assert is_list(error.data.available_patterns)
    end
  end
  
  describe "validate_refactoring signal" do
    test "validates refactoring changes", %{agent: agent} do
      original = "def add(a, b), do: a + b"
      refactored = "def add(a, b) when is_number(a) and is_number(b), do: a + b"
      
      validate_signal = %{
        "type" => "validate_refactoring",
        "data" => %{
          "original_code" => original,
          "refactored_code" => refactored,
          "request_id" => "validate_123"
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, validate_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.validated"} = validation}
      assert validation.data.request_id == "validate_123"
      assert validation.data.is_valid == true
      assert is_map(validation.data.validation_checks)
    end
    
    test "detects invalid refactoring", %{agent: agent} do
      original = "def add(a, b), do: a + b"
      refactored = "def add(a, b) when" # Invalid syntax
      
      validate_signal = %{
        "type" => "validate_refactoring",
        "data" => %{
          "original_code" => original,
          "refactored_code" => refactored
        }
      }
      
      {:ok, _agent} = CodeRefactorerAgent.handle_signal(agent, validate_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.validated"} = validation}
      assert validation.data.is_valid == false
      assert length(validation.data.errors) > 0
    end
  end
  
  describe "save_refactoring_pattern signal" do
    test "saves custom refactoring pattern", %{agent: agent} do
      pattern_signal = %{
        "type" => "save_refactoring_pattern",
        "data" => %{
          "name" => "custom_pattern",
          "instruction" => "Replace all IO.puts with Logger.info",
          "type" => "general",
          "priority" => "high",
          "user_id" => "user_123"
        }
      }
      
      {:ok, agent} = CodeRefactorerAgent.handle_signal(agent, pattern_signal)
      
      assert_receive {:signal, %Jido.Signal{type: "code.refactoring.pattern.saved"} = saved}
      assert saved.data.pattern_name == "custom_pattern"
      assert saved.data.pattern.instruction =~ "Logger.info"
      assert saved.data.pattern.priority == :high
      
      # Verify pattern saved in state
      pattern = agent.state.refactoring_patterns["custom_pattern"]
      assert pattern.instruction =~ "Logger.info"
      assert pattern.created_by == "user_123"
    end
  end
  
  describe "refactoring history" do
    test "maintains refactoring history", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_refactorer, params ->
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => "refactored: #{params.code}",
          "changes" => %{"lines_changed" => 2},
          "refactoring_type" => "simplify",
          "instruction" => params.instruction
        }}
      end)
      
      # Generate multiple refactorings
      for i <- 1..3 do
        signal = %{
          "type" => "refactor_code",
          "data" => %{
            "code" => "def func#{i}, do: complex#{i}()",
            "instruction" => "Simplify function #{i}",
            "request_id" => "hist_#{i}"
          }
        }
        
        {:ok, agent} = CodeRefactorerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check history
      assert length(agent.state.refactoring_history) == 3
      
      # Most recent should be first
      [first | _] = agent.state.refactoring_history
      assert first.id == "hist_3"
      assert first.instruction =~ "Simplify function 3"
    end
  end
  
  describe "statistics tracking" do
    test "tracks refactoring statistics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 3, fn :code_refactorer, params ->
        type = case params.instruction do
          inst when inst =~ "pattern" -> "pattern_matching"
          inst when inst =~ "error" -> "error_handling"
          _ -> "simplify"
        end
        
        {:ok, %{
          "original_code" => params.code,
          "refactored_code" => "refactored code",
          "changes" => %{},
          "refactoring_type" => type,
          "instruction" => params.instruction
        }}
      end)
      
      # Generate refactorings with different types
      refactorings = [
        %{"instruction" => "Use pattern matching"},
        %{"instruction" => "Improve error handling"},
        %{"instruction" => "Simplify logic"}
      ]
      
      for {refactoring, i} <- Enum.with_index(refactorings) do
        signal = %{
          "type" => "refactor_code",
          "data" => Map.merge(refactoring, %{
            "code" => "def func#{i}, do: :ok"
          })
        }
        
        {:ok, agent} = CodeRefactorerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check statistics
      stats = agent.state.refactoring_stats
      assert stats.total_refactored == 3
      assert stats.by_type["pattern_matching"] == 1
      assert stats.by_type["error_handling"] == 1
      assert stats.by_type["simplify"] == 1
      assert Map.has_key?(stats.most_common_issues, "missing_pattern_matching")
      assert Map.has_key?(stats.most_common_issues, "poor_error_handling")
    end
  end
  
  describe "quality improvements tracking" do
    test "tracks quality improvements per file", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :code_refactorer, _params ->
        {:ok, %{
          "original_code" => "complex code",
          "refactored_code" => "simple code",
          "changes" => %{},
          "refactoring_type" => "simplify",
          "instruction" => "Simplify"
        }}
      end)
      
      # Refactor same file twice
      for i <- 1..2 do
        signal = %{
          "type" => "refactor_code",
          "data" => %{
            "code" => "def func, do: complex_logic_#{i}",
            "instruction" => "Simplify iteration #{i}",
            "file_path" => "lib/module.ex"
          }
        }
        
        {:ok, agent} = CodeRefactorerAgent.handle_signal(agent, signal)
        Process.sleep(50)
      end
      
      # Check quality improvements
      improvements = agent.state.quality_improvements["lib/module.ex"]
      assert length(improvements) == 2
      assert Enum.all?(improvements, &Map.has_key?(&1, :complexity_reduction))
    end
  end
end