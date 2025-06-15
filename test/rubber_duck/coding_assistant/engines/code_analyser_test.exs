defmodule RubberDuck.CodingAssistant.Engines.CodeAnalyserTest do
  @moduledoc """
  Tests for the CodeAnalyser engine implementation.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.CodingAssistant.Engines.CodeAnalyser
  
  describe "EngineBehaviour compliance" do
    test "module exists and implements EngineBehaviour" do
      assert Code.ensure_loaded?(CodeAnalyser)
      
      # Check that it implements the behaviour
      behaviours = CodeAnalyser.module_info(:attributes)[:behaviour] || []
      assert RubberDuck.CodingAssistant.EngineBehaviour in behaviours
    end
    
    test "implements all required callbacks" do
      required_callbacks = [
        {:init, 1},
        {:process_real_time, 2},
        {:process_batch, 2},
        {:capabilities, 0},
        {:health_check, 1},
        {:handle_engine_event, 2},
        {:terminate, 2}
      ]
      
      # Check if all required functions exist
      for {callback_name, arity} <- required_callbacks do
        assert function_exported?(CodeAnalyser, callback_name, arity),
          "Missing required callback: #{callback_name}/#{arity}"
      end
    end
    
    test "can be initialized with configuration" do
      config = %{
        languages: [:elixir, :javascript],
        cache_size: 1000,
        rules_path: "test/fixtures/rules"
      }
      
      assert {:ok, state} = CodeAnalyser.init(config)
      assert is_map(state)
    end
    
    test "declares correct capabilities" do
      capabilities = CodeAnalyser.capabilities()
      
      expected_capabilities = [
        :syntax_analysis,
        :complexity_analysis, 
        :security_scanning,
        :code_smell_detection,
        :multi_language_support
      ]
      
      for capability <- expected_capabilities do
        assert capability in capabilities,
          "Missing expected capability: #{capability}"
      end
    end
  end
  
  describe "real-time code analysis" do
    setup do
      config = %{languages: [:elixir], cache_size: 100}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "analyzes valid Elixir code", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        defmodule TestModule do
          def hello do
            :world
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert %{
        status: :success,
        data: %{
          syntax: %{valid: true},
          complexity: %{},
          security: %{},
          code_smells: %{}
        }
      } = result
      
      assert is_map(new_state)
    end
    
    test "handles malformed code gracefully", %{state: state} do
      code_data = %{
        file_path: "invalid.ex", 
        content: "defmodule Broken do def incomplete",
        language: :elixir
      }
      
      assert {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert %{
        status: :success,
        data: %{
          syntax: %{valid: false, errors: errors}
        }
      } = result
      
      assert is_list(errors)
      assert length(errors) > 0
    end
    
    test "calculates complexity metrics", %{state: state} do
      complex_code = %{
        file_path: "complex.ex",
        content: """
        defmodule Complex do
          def complex_function(x) do
            if x > 0 do
              case x do
                1 -> :one
                2 -> :two
                n when n > 10 ->
                  if n < 20 do
                    :medium
                  else
                    :large
                  end
                _ -> :other
              end
            else
              :negative
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(complex_code, state)
      
      assert %{
        data: %{
          complexity: %{
            cyclomatic: complexity_score,
            cognitive: _cognitive_score
          }
        }
      } = result
      
      assert is_number(complexity_score)
      assert complexity_score > 1
    end
  end
  
  describe "batch processing" do
    setup do
      config = %{languages: [:elixir, :javascript]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "processes multiple files efficiently", %{state: state} do
      code_list = [
        %{file_path: "file1.ex", content: "defmodule A, do: nil", language: :elixir},
        %{file_path: "file2.js", content: "function test() { return 42; }", language: :javascript},
        %{file_path: "file3.ex", content: "defmodule B, do: def func, do: :ok", language: :elixir}
      ]
      
      assert {:ok, results, _new_state} = CodeAnalyser.process_batch(code_list, state)
      
      assert is_list(results)
      assert length(results) == 3
      
      for result <- results do
        assert %{status: :success, data: %{}} = result
      end
    end
  end
  
  describe "multi-language support" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "analyzes JavaScript code", %{state: state} do
      js_code = %{
        file_path: "test.js",
        content: """
        function calculateSum(a, b) {
          if (a < 0 || b < 0) {
            throw new Error("Negative numbers not allowed");
          }
          return a + b;
        }
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(js_code, state)
      assert %{status: :success, data: %{}} = result
    end
    
    test "analyzes Python code", %{state: state} do
      python_code = %{
        file_path: "test.py", 
        content: """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)
        """,
        language: :python
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(python_code, state)
      assert %{status: :success, data: %{}} = result
    end
  end
  
  describe "security analysis" do
    setup do
      config = %{languages: [:elixir], security_rules: :default}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "detects potential security issues", %{state: state} do
      insecure_code = %{
        file_path: "insecure.ex",
        content: """
        defmodule Insecure do
          def dangerous_eval(user_input) do
            Code.eval_string(user_input)
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(insecure_code, state)
      
      assert %{
        data: %{
          security: %{
            vulnerabilities: vulnerabilities
          }
        }
      } = result
      
      assert is_list(vulnerabilities)
      # Should detect Code.eval_string as potentially dangerous
    end
  end
  
  describe "code smell detection" do
    setup do
      config = %{languages: [:elixir]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "detects code smells", %{state: state} do
      smelly_code = %{
        file_path: "smelly.ex",
        content: """
        defmodule VeryLongFunctionName do
          def very_long_function_with_too_many_parameters_and_complex_logic(a, b, c, d, e, f, g, h) do
            if a > 0 do
              if b > 0 do
                if c > 0 do
                  if d > 0 do
                    if e > 0 do
                      if f > 0 do
                        if g > 0 do
                          h + a + b + c + d + e + f + g
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(smelly_code, state)
      
      assert %{
        data: %{
          code_smells: %{
            detected: smells
          }
        }
      } = result
      
      assert is_list(smells)
      # Should detect deep nesting, too many parameters, etc.
    end
  end
  
  describe "caching" do
    setup do
      config = %{languages: [:elixir], cache_size: 10}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "caches analysis results", %{state: state} do
      code_data = %{
        file_path: "cached.ex",
        content: "defmodule Cached, do: def test, do: :ok",
        language: :elixir
      }
      
      # First analysis
      assert {:ok, result1, state1} = CodeAnalyser.process_real_time(code_data, state)
      
      # Second analysis of same content should be faster (cached)
      assert {:ok, result2, _state2} = CodeAnalyser.process_real_time(code_data, state1)
      
      # Results should be equivalent
      assert result1.data == result2.data
    end
  end
  
  describe "health checking" do
    test "reports healthy status with good state" do
      config = %{languages: [:elixir]}
      {:ok, state} = CodeAnalyser.init(config)
      
      assert CodeAnalyser.health_check(state) == :healthy
    end
  end
  
  describe "error handling" do
    setup do
      config = %{languages: [:elixir]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "handles unsupported language gracefully", %{state: state} do
      unsupported_code = %{
        file_path: "test.asm",
        content: "mov ax, bx",
        language: :assembly
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(unsupported_code, state)
      
      assert %{
        status: :success,
        data: %{
          syntax: %{valid: false, errors: [%{message: message}]}
        }
      } = result
      
      assert String.contains?(String.downcase(message), "unsupported") or String.contains?(String.downcase(message), "unknown")
    end
    
    test "handles empty content", %{state: state} do
      empty_code = %{
        file_path: "empty.ex",
        content: "",
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(empty_code, state)
      assert %{status: :success} = result
    end
  end
end