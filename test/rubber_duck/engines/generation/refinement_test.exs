defmodule RubberDuck.Engines.Generation.RefinementTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Engines.Generation.Refinement
  
  describe "refine_code/1" do
    test "refines code based on error feedback" do
      request = %{
        code: """
        def example_function(arg) do
          if arg do
            process(arg
          end
        end
        """,
        feedback: %{
          type: :error,
          message: "Unbalanced parentheses",
          specific_issues: [
            %{
              line: 3,
              description: "Unbalanced parentheses in function call",
              severity: :error
            }
          ]
        },
        language: :elixir,
        original_prompt: "Create example function",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, result} = Refinement.refine_code(request)
      
      assert result.refined_code =~ "process(arg)"
      assert length(result.changes_made) > 0
      assert result.iteration == 1
      refute result.converged
    end
    
    test "stops refinement at max iterations" do
      request = %{
        code: "def test do :ok end",
        feedback: %{
          type: :improvement,
          message: "Could be better"
        },
        language: :elixir,
        original_prompt: "Test function",
        iteration: 5,  # Already at max
        context: %{}
      }
      
      assert {:ok, result} = Refinement.refine_code(request)
      
      assert result.iteration == 5
      refute result.converged
      assert result.refined_code == request.code
    end
    
    test "detects convergence when no changes made" do
      code = """
      def well_formed_function(arg) do
        {:ok, arg}
      end
      """
      
      request = %{
        code: code,
        feedback: %{
          type: :improvement,
          message: "Minor improvements only"
        },
        language: :elixir,
        original_prompt: "Create function",
        iteration: 1,
        context: %{}
      }
      
      assert {:ok, result} = Refinement.refine_code(request)
      
      # If no significant changes, should converge
      if result.refined_code == code do
        assert result.converged
      end
    end
  end
  
  describe "apply_refinement/1" do
    test "fixes syntax errors" do
      request = %{
        code: """
        def broken_function do
          undefined_func()
        end
        """,
        feedback: %{
          type: :error,
          message: "Undefined function",
          specific_issues: [
            %{
              line: 2,
              description: "Undefined function `undefined_func`",
              severity: :error
            }
          ]
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "def undefined_func"
      assert length(changes) > 0
      assert hd(changes).type == :fix
    end
    
    test "applies style improvements" do
      request = %{
        code: """
        def badlyNamedFunction ( x,y,z ) do
        x+y+z
        end
        """,
        feedback: %{
          type: :style,
          message: "Fix code style"
        },
        language: :elixir,
        original_prompt: "Add function",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      # Should fix indentation and possibly naming
      refute refined_code =~ "badlyNamedFunction"
      assert length(changes) > 0
      assert Enum.any?(changes, &(&1.type == :style))
    end
    
    test "applies performance optimizations" do
      request = %{
        code: """
        def process_list(items) do
          items
          |> Enum.map(&transform/1)
          |> Enum.filter(&valid?/1)
        end
        """,
        feedback: %{
          type: :performance,
          message: "Optimize enum operations"
        },
        language: :elixir,
        original_prompt: "Process list",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      assert length(changes) > 0
      # May combine operations or suggest more efficient approach
    end
    
    test "improves code clarity" do
      request = %{
        code: """
        def f(x) do
          x * 2
        end
        """,
        feedback: %{
          type: :clarity,
          message: "Improve readability"
        },
        language: :elixir,
        original_prompt: "Double value",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      # Should improve variable names and possibly add type specs
      refute refined_code =~ "def f("
      assert length(changes) > 0
    end
  end
  
  describe "converged?/3" do
    test "returns true for identical code" do
      code = "def test do :ok end"
      
      assert Refinement.converged?(code, code, [])
    end
    
    test "returns false for significant changes" do
      original = "def test do :ok end"
      refined = """
      def test do
        result = process()
        {:ok, result}
      end
      """
      
      changes = [
        %{type: :enhancement, description: "Added processing"}
      ]
      
      refute Refinement.converged?(original, refined, changes)
    end
    
    test "returns true for minor style changes only" do
      original = "def test do\n:ok\nend"
      refined = "def test do\n  :ok\nend"
      
      changes = [
        %{type: :style, description: "Fixed indentation"}
      ]
      
      assert Refinement.converged?(original, refined, changes)
    end
  end
  
  describe "error fixing" do
    test "fixes unbalanced delimiters" do
      request = %{
        code: """
        def broken(arg) do
          if condition do
            something(
          end
        end
        """,
        feedback: %{
          type: :error,
          message: "Unbalanced delimiters",
          specific_issues: []
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _changes} = Refinement.apply_refinement(request)
      
      # Count parentheses
      opens = String.graphemes(refined_code) |> Enum.count(&(&1 == "("))
      closes = String.graphemes(refined_code) |> Enum.count(&(&1 == ")"))
      
      assert opens == closes
    end
    
    test "adds missing function definitions" do
      request = %{
        code: """
        def caller do
          missing_function()
        end
        """,
        feedback: %{
          type: :error,
          message: "Undefined function",
          specific_issues: [
            %{
              line: 2,
              description: "Undefined function `missing_function`",
              severity: :error
            }
          ]
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "def missing_function"
      assert Enum.any?(changes, &(&1.type == :fix))
    end
  end
  
  describe "style improvements" do
    test "fixes indentation" do
      request = %{
        code: """
        def unindented do
        result = calculate()
        process(result)
        end
        """,
        feedback: %{
          type: :style,
          message: "Fix indentation"
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      lines = String.split(refined_code, "\n")
      # Body should be indented
      assert Enum.any?(lines, &String.starts_with?(&1, "  "))
    end
    
    test "adds moduledoc if missing" do
      request = %{
        code: """
        defmodule TestModule do
          def test, do: :ok
        end
        """,
        feedback: %{
          type: :style,
          message: "Add documentation"
        },
        language: :elixir,
        original_prompt: "Test module",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "@moduledoc"
    end
    
    test "fixes naming conventions" do
      request = %{
        code: """
        def CamelCaseFunction do
          :ok
        end
        """,
        feedback: %{
          type: :style,
          message: "Fix naming"
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      refute refined_code =~ "CamelCaseFunction"
    end
  end
  
  describe "performance optimizations" do
    test "optimizes multiple enum operations" do
      request = %{
        code: """
        def process(items) do
          items
          |> Enum.map(&transform/1)
          |> Enum.filter(&valid?/1)
        end
        """,
        feedback: %{
          type: :performance,
          message: "Combine enum operations"
        },
        language: :elixir,
        original_prompt: "Process items",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      assert length(changes) > 0
      # May suggest filter_map or other optimization
    end
    
    test "optimizes string concatenation" do
      request = %{
        code: """
        def build_string(items) do
          Enum.reduce(items, "", fn item, acc ->
            acc <> item
          end)
        end
        """,
        feedback: %{
          type: :performance,
          message: "Optimize string building"
        },
        language: :elixir,
        original_prompt: "Build string",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      # Should suggest Enum.join or IO lists
      assert refined_code =~ "Enum.join" or refined_code =~ "Enum.map"
    end
  end
  
  describe "clarity improvements" do
    test "improves variable names" do
      request = %{
        code: """
        def calc(x, y) do
          z = x + y
          z * 2
        end
        """,
        feedback: %{
          type: :clarity,
          message: "Improve naming"
        },
        language: :elixir,
        original_prompt: "Calculate sum",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      # Should have better names
      refute refined_code =~ "def calc("
      refute refined_code =~ " z ="
    end
    
    test "adds type specs" do
      request = %{
        code: """
        def add(a, b) do
          a + b
        end
        """,
        feedback: %{
          type: :clarity,
          message: "Add type annotations"
        },
        language: :elixir,
        original_prompt: "Add numbers",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "@spec"
    end
  end
  
  describe "general refinements" do
    test "prefers pattern matching over conditionals" do
      request = %{
        code: """
        def check(value) do
          if is_nil(value) do
            :empty
          else
            {:ok, value}
          end
        end
        """,
        feedback: %{
          type: :improvement,
          message: "Use pattern matching"
        },
        language: :elixir,
        original_prompt: "Check value",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, changes} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "case" or refined_code =~ "def check(nil)"
      assert length(changes) > 0
    end
    
    test "extracts magic numbers to constants" do
      request = %{
        code: """
        defmodule Calculator do
          def calculate(value) do
            value * 3600 + 86400
          end
        end
        """,
        feedback: %{
          type: :improvement,
          message: "Extract constants"
        },
        language: :elixir,
        original_prompt: "Time calculator",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, refined_code, _} = Refinement.apply_refinement(request)
      
      assert refined_code =~ "@default_"
    end
  end
  
  describe "confidence calculation" do
    test "high confidence for no changes" do
      request = %{
        code: "def perfect do :ok end",
        feedback: %{
          type: :improvement,
          message: "Already good"
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 0,
        context: %{}
      }
      
      assert {:ok, result} = Refinement.refine_code(request)
      
      if result.refined_code == request.code do
        assert result.confidence >= 0.8
      end
    end
    
    test "lower confidence with more changes and iterations" do
      request = %{
        code: "def bad do nil end",
        feedback: %{
          type: :error,
          message: "Multiple issues",
          specific_issues: [
            %{line: 1, description: "Issue 1", severity: :error},
            %{line: 1, description: "Issue 2", severity: :error}
          ]
        },
        language: :elixir,
        original_prompt: "Test",
        iteration: 3,
        context: %{}
      }
      
      assert {:ok, result} = Refinement.refine_code(request)
      
      # More iterations and changes should reduce confidence
      assert result.confidence < 0.8
    end
  end
end