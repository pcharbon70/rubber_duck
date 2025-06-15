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
  
  describe "enhanced caching" do
    setup do
      config = %{languages: [:elixir], cache_size: 10, cache_ttl: :timer.seconds(30)}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "caches analysis results with content-based keys", %{state: state} do
      code_data = %{
        file_path: "cached.ex",
        content: "defmodule Cached, do: def test, do: :ok",
        language: :elixir
      }
      
      # First analysis
      assert {:ok, result1, state1} = CodeAnalyser.process_real_time(code_data, state)
      
      # Second analysis of same content should be faster (cached)
      assert {:ok, result2, state2} = CodeAnalyser.process_real_time(code_data, state1)
      
      # Results should be equivalent
      assert result1.data == result2.data
      
      # Cache stats should show a hit
      assert state2.cache_stats.hits > state1.cache_stats.hits
      assert state2.cache_stats.hit_rate > 0
    end
    
    test "different languages have separate cache entries", %{state: state} do
      content = "function test() { return 42; }"
      
      elixir_code = %{file_path: "test.ex", content: content, language: :elixir}
      js_code = %{file_path: "test.js", content: content, language: :javascript}
      
      # Analyze same content in different languages
      assert {:ok, _result1, state1} = CodeAnalyser.process_real_time(elixir_code, state)
      assert {:ok, _result2, state2} = CodeAnalyser.process_real_time(js_code, state1)
      
      # Should have separate cache entries (2 misses, no hits)
      assert state2.cache_stats.misses == 2
      assert state2.cache_stats.hits == 0
      
      # Re-analyze same languages should hit cache
      assert {:ok, _result3, state3} = CodeAnalyser.process_real_time(elixir_code, state2)
      assert {:ok, _result4, state4} = CodeAnalyser.process_real_time(js_code, state3)
      
      # Should have 2 hits now
      assert state4.cache_stats.hits == 2
    end
    
    test "cache management via engine events", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: "defmodule Test, do: def hello, do: :world",
        language: :elixir
      }
      
      # Populate cache
      assert {:ok, _result, state1} = CodeAnalyser.process_real_time(code_data, state)
      assert map_size(state1.cache) > 0
      
      # Clear cache via event
      assert {:ok, state2} = CodeAnalyser.handle_engine_event({:clear_cache}, state1)
      assert map_size(state2.cache) == 0
      assert state2.cache_stats.hits == 0
    end
    
    test "cache configuration updates", %{state: state} do
      # Update cache configuration
      new_config = %{cache_size: 5, cache_ttl: :timer.seconds(60)}
      
      assert {:ok, updated_state} = CodeAnalyser.handle_engine_event({:configure_cache, new_config}, state)
      
      assert updated_state.cache_size == 5
      assert updated_state.cache_ttl == :timer.seconds(60)
    end
    
    test "cache statistics reporting", %{state: state} do
      code_data = %{
        file_path: "stats.ex",
        content: "defmodule Stats, do: def test, do: :ok",
        language: :elixir
      }
      
      # Generate some cache activity
      assert {:ok, _result1, state1} = CodeAnalyser.process_real_time(code_data, state)
      assert {:ok, _result2, state2} = CodeAnalyser.process_real_time(code_data, state1) # Should hit cache
      
      # Get cache statistics
      assert {:ok, _final_state, cache_info} = CodeAnalyser.handle_engine_event({:get_cache_stats}, state2)
      
      assert Map.has_key?(cache_info, :cache_size)
      assert Map.has_key?(cache_info, :hit_rate)
      assert Map.has_key?(cache_info, :total_requests)
      assert cache_info.hit_rate > 0
      assert cache_info.total_requests == 2
    end
    
    test "LRU eviction when cache is full", %{state: state} do
      # Set small cache size for testing
      small_cache_state = %{state | cache_size: 2}
      
      # Add 3 different items to force eviction
      code1 = %{file_path: "1.ex", content: "defmodule One, do: nil", language: :elixir}
      code2 = %{file_path: "2.ex", content: "defmodule Two, do: nil", language: :elixir}
      code3 = %{file_path: "3.ex", content: "defmodule Three, do: nil", language: :elixir}
      
      assert {:ok, _result1, state1} = CodeAnalyser.process_real_time(code1, small_cache_state)
      assert {:ok, _result2, state2} = CodeAnalyser.process_real_time(code2, state1)
      assert {:ok, _result3, state3} = CodeAnalyser.process_real_time(code3, state2)
      
      # Cache should not exceed max size
      assert map_size(state3.cache) <= 2
      
      # First item should be evicted, so re-analyzing it should be a cache miss
      assert {:ok, _result4, state4} = CodeAnalyser.process_real_time(code1, state3)
      
      # Should still be within cache limits
      assert map_size(state4.cache) <= 2
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
  
  describe "enhanced syntax analysis" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end
    
    test "detects unclosed brackets in Elixir", %{state: state} do
      bracket_code = %{
        file_path: "brackets.ex",
        content: """
        defmodule Test do
          def broken_function(x) do
            if x > 0 do
              {a, b, c
            end
          end  # Missing closing brace
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(bracket_code, state)
      
      assert %{
        data: %{
          syntax: %{
            errors: errors
          }
        }
      } = result
      
      # Should detect unclosed brace
      assert Enum.any?(errors, fn error -> 
        String.contains?(error.message, "Unclosed") or String.contains?(error.message, "bracket")
      end)
    end
    
    test "detects missing colons in Python", %{state: state} do
      python_code = %{
        file_path: "test.py",
        content: """
        def test_function()
            if x > 0
                return True
            else
                return False
        """,
        language: :python
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(python_code, state)
      
      assert %{
        data: %{
          syntax: %{
            errors: errors
          }
        }
      } = result
      
      # Should detect missing colons
      colon_errors = Enum.filter(errors, fn error ->
        String.contains?(error.message, "colon")
      end)
      
      assert length(colon_errors) > 0
    end
    
    test "detects incomplete Elixir constructs", %{state: state} do
      incomplete_code = %{
        file_path: "incomplete.ex",
        content: """
        defmodule MyModule do
          def complete_function, do: :ok
          
          def  # Incomplete function definition
          
          defmodule  # Incomplete module definition
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(incomplete_code, state)
      
      assert %{
        data: %{
          syntax: %{
            errors: errors
          }
        }
      } = result
      
      # Should detect incomplete constructs
      incomplete_errors = Enum.filter(errors, fn error ->
        String.contains?(error.message, "Incomplete")
      end)
      
      assert length(incomplete_errors) >= 2
    end
    
    test "provides detailed error information", %{state: state} do
      error_code = %{
        file_path: "detailed.ex",
        content: """
        defmodule Test do
          def test(x) do
            if x > 0 do
              [1, 2, 3
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(error_code, state)
      
      assert %{
        data: %{
          syntax: %{
            errors: [error | _]
          }
        }
      } = result
      
      # Verify error structure
      assert Map.has_key?(error, :message)
      assert Map.has_key?(error, :line)
      assert Map.has_key?(error, :column)
      assert Map.has_key?(error, :severity)
      assert error.severity in [:error, :warning]
    end
    
    test "handles JavaScript syntax errors", %{state: state} do
      js_code = %{
        file_path: "test.js",
        content: """
        function test() {
          if (x > 0) {
            console.log("test")
            return true
          }
        // Missing closing brace
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(js_code, state)
      
      assert %{
        data: %{
          syntax: %{
            errors: errors
          }
        }
      } = result
      
      # Should detect syntax issues
      assert length(errors) > 0
    end
    
    test "generates syntax warnings", %{state: state} do
      warning_code = %{
        file_path: "warnings.ex",
        content: """
        defmodule Test do
          def test(x) do
            x |>
            # Pipe at end of line
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(warning_code, state)
      
      assert %{
        data: %{
          syntax: %{
            warnings: warnings
          }
        }
      } = result
      
      # Should have warnings or errors for syntax issues
      assert is_list(warnings)
    end
  end
end