defmodule RubberDuck.CodingAssistant.Engines.CodeAnalyserComplexityTest do
  use ExUnit.Case, async: true
  alias RubberDuck.CodingAssistant.Engines.CodeAnalyser

  describe "cyclomatic complexity calculation" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "calculates minimal complexity for simple function", %{state: state} do
      simple_code = %{
        file_path: "simple.ex",
        content: """
        defmodule Simple do
          def add(a, b) do
            a + b
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(simple_code, state)
      assert %{
        data: %{
          complexity: %{
            cyclomatic: 1  # No decision points
          }
        }
      } = result
    end

    test "calculates complexity for single if statement", %{state: state} do
      if_code = %{
        file_path: "if.ex",
        content: """
        defmodule IfExample do
          def check(x) do
            if x > 0 do
              :positive
            else
              :non_positive
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(if_code, state)
      assert %{
        data: %{
          complexity: %{
            cyclomatic: 2  # 1 base + 1 for if
          }
        }
      } = result
    end

    test "calculates complexity for multiple conditions", %{state: state} do
      complex_code = %{
        file_path: "complex.ex",
        content: """
        defmodule Complex do
          def process(x, y) do
            cond do
              x > 0 and y > 0 -> :both_positive
              x > 0 or y > 0 -> :one_positive
              x == 0 -> :x_zero
              y == 0 -> :y_zero
              true -> :both_negative
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
            cyclomatic: cyclomatic
          }
        }
      } = result
      
      # 1 base + 4 conditions + 2 logical operators (and, or)
      assert cyclomatic == 7
    end

    test "calculates complexity for case statement", %{state: state} do
      case_code = %{
        file_path: "case.ex",
        content: """
        defmodule CaseExample do
          def categorize(value) do
            case value do
              x when x > 100 -> :high
              x when x > 50 -> :medium
              x when x > 0 -> :low
              0 -> :zero
              _ -> :negative
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(case_code, state)
      assert %{
        data: %{
          complexity: %{
            cyclomatic: 6  # 1 base + 5 case branches
          }
        }
      } = result
    end

    test "calculates complexity for JavaScript loops and conditions", %{state: state} do
      js_code = %{
        file_path: "loops.js",
        content: """
        function processArray(arr) {
          let result = 0;
          for (let i = 0; i < arr.length; i++) {
            if (arr[i] > 0) {
              result += arr[i];
            } else if (arr[i] < 0) {
              result -= arr[i];
            }
          }
          while (result > 100) {
            result = result / 2;
          }
          return result;
        }
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(js_code, state)
      assert %{
        data: %{
          complexity: %{
            cyclomatic: 5  # 1 base + for + if + else if + while
          }
        }
      } = result
    end

    test "calculates complexity for Python exception handling", %{state: state} do
      python_code = %{
        file_path: "exceptions.py",
        content: """
        def safe_divide(a, b):
            try:
                if b == 0:
                    raise ValueError("Cannot divide by zero")
                return a / b
            except ValueError as e:
                print(f"Error: {e}")
                return None
            except Exception:
                return None
        """,
        language: :python
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(python_code, state)
      assert %{
        data: %{
          complexity: %{
            cyclomatic: 4  # 1 base + if + 2 except clauses
          }
        }
      } = result
    end
  end

  describe "cognitive complexity calculation" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "calculates cognitive complexity with nesting penalty", %{state: state} do
      nested_code = %{
        file_path: "nested.ex",
        content: """
        defmodule Nested do
          def deeply_nested(a, b, c) do
            if a > 0 do                    # +1 complexity
              if b > 0 do                  # +2 (1 + 1 nesting)
                if c > 0 do                # +3 (1 + 2 nesting)
                  :all_positive
                else
                  :c_not_positive
                end
              else
                :b_not_positive
              end
            else
              :a_not_positive
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(nested_code, state)
      assert %{
        data: %{
          complexity: %{
            cognitive: cognitive
          }
        }
      } = result
      
      # Base cognitive: 1 + 2 + 3 = 6 (for nested ifs with increasing penalty)
      assert cognitive >= 6
    end

    test "calculates cognitive complexity for logical operators", %{state: state} do
      logical_code = %{
        file_path: "logical.ex",
        content: """
        defmodule Logical do
          def complex_condition(a, b, c, d) do
            if (a > 0 and b > 0) or (c < 0 and d < 0) do
              :complex_true
            else
              :complex_false
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(logical_code, state)
      assert %{
        data: %{
          complexity: %{
            cognitive: cognitive
          }
        }
      } = result
      
      # 1 for if + 3 for logical operators (and, or, and)
      assert cognitive >= 4
    end

    test "calculates cognitive complexity for recursive calls", %{state: state} do
      recursive_code = %{
        file_path: "recursive.ex",
        content: """
        defmodule Recursive do
          def factorial(n) when n <= 1, do: 1
          def factorial(n) do
            if n > 20 do
              raise ArgumentError, "Number too large"
            else
              n * factorial(n - 1)
            end
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(recursive_code, state)
      assert %{
        data: %{
          complexity: %{
            cognitive: cognitive
          }
        }
      } = result
      
      # Should include penalty for recursion
      assert cognitive >= 2
    end
  end

  describe "Halstead metrics calculation" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "calculates Halstead metrics for simple function", %{state: state} do
      simple_code = %{
        file_path: "halstead.ex",
        content: """
        defmodule Math do
          def quadratic(a, b, c, x) do
            a * x * x + b * x + c
          end
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(simple_code, state)
      assert %{
        data: %{
          complexity: %{
            halstead: %{
              program_length: n,
              program_vocabulary: vocabulary,
              program_volume: volume,
              difficulty: difficulty,
              effort: effort
            }
          }
        }
      } = result
      
      # Basic validations
      assert n > 0
      assert vocabulary > 0
      assert volume > 0
      assert difficulty > 0
      assert effort > 0
    end

    test "calculates Halstead metrics with distinct operators and operands", %{state: state} do
      distinct_code = %{
        file_path: "distinct.js",
        content: """
        function calculate(x, y) {
          const sum = x + y;
          const diff = x - y;
          const prod = x * y;
          const quot = x / y;
          return {sum, diff, prod, quot};
        }
        """,
        language: :javascript
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(distinct_code, state)
      assert %{
        data: %{
          complexity: %{
            halstead: %{
              program_vocabulary: vocabulary
            }
          }
        }
      } = result
      
      # Should have distinct operators: =, +, -, *, /, function, const, return
      # And distinct operands: x, y, sum, diff, prod, quot
      assert vocabulary >= 14  # At least 8 operators + 6 operands
    end

    test "calculates effort increases with complexity", %{state: state} do
      simple_code = %{
        file_path: "simple.py",
        content: "def add(a, b): return a + b",
        language: :python
      }
      
      complex_code = %{
        file_path: "complex.py",
        content: """
        def complex_calc(a, b, c, d, e):
            result = 0
            if a > 0 and b > 0:
                result = (a * b) + (c / d)
            elif a < 0 or b < 0:
                result = (a - b) * (c + d)
            else:
                result = e ** 2
            return result * 1.5
        """,
        language: :python
      }
      
      assert {:ok, simple_result, _} = CodeAnalyser.process_real_time(simple_code, state)
      assert {:ok, complex_result, _} = CodeAnalyser.process_real_time(complex_code, state)
      
      simple_effort = simple_result.data.complexity.halstead.effort
      complex_effort = complex_result.data.complexity.halstead.effort
      
      # Complex code should have higher effort
      assert complex_effort > simple_effort
    end
  end

  describe "maintainability index calculation" do
    setup do
      config = %{languages: [:elixir, :javascript, :python]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "calculates maintainability index", %{state: state} do
      code = %{
        file_path: "maintain.ex",
        content: """
        defmodule Maintainable do
          def process(items) do
            items
            |> Enum.filter(&(&1.active))
            |> Enum.map(&transform/1)
            |> Enum.reduce(0, &accumulate/2)
          end
          
          defp transform(item), do: item.value * 2
          defp accumulate(value, acc), do: acc + value
        end
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(code, state)
      assert %{
        data: %{
          complexity: %{
            maintainability_index: mi
          }
        }
      } = result
      
      # Maintainability index should be between 0 and 100
      assert mi >= 0 and mi <= 100
      # Well-structured code should have high maintainability
      assert mi > 50
    end

    test "lower maintainability for complex code", %{state: state} do
      complex_code = %{
        file_path: "unmaintainable.ex",
        content: """
        defmodule Unmaintainable do
          def process(a, b, c, d, e, f, g, h, i, j) do
            if a > 0 do
              if b > 0 do
                if c > 0 do
                  if d > 0 do
                    if e > 0 do
                      result = a + b + c + d + e
                      if f > 0 do
                        result = result * f
                        if g > 0 do
                          result = result / g
                          if h > 0 do
                            result = result - h
                            if i > 0 do
                              result = result + i
                              if j > 0 do
                                result * j
                              else
                                result
                              end
                            else
                              result
                            end
                          else
                            result
                          end
                        else
                          result
                        end
                      else
                        result
                      end
                    else
                      0
                    end
                  else
                    0
                  end
                else
                  0
                end
              else
                0
              end
            else
              0
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
            maintainability_index: mi
          }
        }
      } = result
      
      # Highly complex code should have low maintainability
      assert mi < 30
    end
  end

  describe "lines of code calculation" do
    setup do
      config = %{languages: [:elixir]}
      {:ok, state} = CodeAnalyser.init(config)
      %{state: state}
    end

    test "counts non-empty, non-comment lines", %{state: state} do
      code_with_comments = %{
        file_path: "commented.ex",
        content: """
        # This is a module comment
        defmodule Example do
          # This function adds two numbers
          def add(a, b) do
            # Return the sum
            a + b
          end
          
          # Another function
          def subtract(a, b) do
            a - b
          end
        end
        
        # End of file
        """,
        language: :elixir
      }
      
      assert {:ok, result, _state} = CodeAnalyser.process_real_time(code_with_comments, state)
      assert %{
        data: %{
          complexity: %{
            lines_of_code: loc
          }
        }
      } = result
      
      # Should count only actual code lines, not comments or empty lines
      assert loc == 8  # defmodule, def add, a + b, end, def subtract, a - b, end, end
    end
  end
end