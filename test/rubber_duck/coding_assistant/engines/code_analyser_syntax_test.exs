defmodule RubberDuck.CodingAssistant.Engines.CodeAnalyserSyntaxTest do
  use ExUnit.Case, async: true
  alias RubberDuck.CodingAssistant.Engines.CodeAnalyser

  setup do
    # Initialize the engine state directly
    config = %{
      languages: [:elixir, :javascript, :python],
      cache_size: 1000
    }
    {:ok, state} = CodeAnalyser.init(config)
    {:ok, state: state}
  end

  describe "syntax analysis with error detection" do
    test "detects unclosed strings in Elixir", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def hello do
          message = "Hello world
          IO.puts(message)
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.status == :success
      assert result.data.syntax.valid == false
      assert length(result.data.syntax.errors) > 0
      
      error = List.first(result.data.syntax.errors)
      assert error.message =~ "Unclosed double quote"
      assert error.line == 2
    end

    test "detects missing 'do' in Elixir function definitions", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def calculate(a, b)
          a + b
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "missing 'do'"
      end)
    end

    test "detects unbalanced brackets in JavaScript", %{state: state} do
      code_data = %{
        file_path: "test.js",
        content: """
        function calculate(a, b) {
          if (a > b) {
            return a - b;
          }
        // Missing closing brace
        """,
        language: :javascript
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "Unmatched" or error.message =~ "bracket"
      end)
    end

    test "detects missing colons in Python", %{state: state} do
      code_data = %{
        file_path: "test.py",
        content: """
        def calculate(a, b)
            return a + b
        """,
        language: :python
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "missing colon"
      end)
    end

    test "detects indentation errors in Python", %{state: state} do
      code_data = %{
        file_path: "test.py",
        content: """
        def hello():
        print("Hello")
            print("World")
        """,
        language: :python
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "Indentation"
      end)
    end

    test "detects incomplete constructs", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        defmodule MyModule do
          def incomplete_function do
            case value do
              :ok ->
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "Incomplete" or error.message =~ "Unclosed"
      end)
    end

    test "provides line and column information for errors", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def test do
          x = 1 +
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.line != nil and error.column != nil
      end)
    end

    test "detects multiple syntax errors", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def broken do
          x = "unclosed string
          y = 'another unclosed
          if true
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert length(result.data.syntax.errors) >= 2
    end

    test "provides syntax warnings for deprecated patterns", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def old_style do
          # Using deprecated patterns
          Dict.new()
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      # Should have warnings even if syntax is valid
      assert is_list(result.data.syntax.warnings)
    end

    test "handles valid code correctly", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        defmodule ValidModule do
          def valid_function(a, b) do
            a + b
          end
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.status == :success
      assert result.data.syntax.valid == true
      assert result.data.syntax.errors == []
    end
  end

  describe "language-specific syntax validation" do
    test "validates Elixir-specific syntax", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        defmodule Test do
          # Missing @ for module attribute
          moduledoc "Test module"
          
          # Invalid pattern match
          {ok, result} = some_function()
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert length(result.data.syntax.errors) > 0
    end

    test "validates JavaScript arrow function syntax", %{state: state} do
      code_data = %{
        file_path: "test.js",
        content: """
        const broken = (a, b) = {
          return a + b;
        };
        """,
        language: :javascript
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "arrow" or error.message =~ "=>"
      end)
    end

    test "validates Python async/await syntax", %{state: state} do
      code_data = %{
        file_path: "test.py",
        content: """
        def regular_function():
            await some_async_call()
        """,
        language: :python
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      assert result.data.syntax.valid == false
      assert Enum.any?(result.data.syntax.errors, fn error ->
        error.message =~ "await" or error.message =~ "async"
      end)
    end
  end

  describe "error severity and categorization" do
    test "categorizes errors by severity", %{state: state} do
      code_data = %{
        file_path: "test.ex",
        content: """
        def test do
          # Critical error - syntax
          x = "unclosed
          
          # Warning - style
          very_very_very_long_variable_name_that_should_be_shorter = 1
        end
        """,
        language: :elixir
      }

      {:ok, result, _new_state} = CodeAnalyser.process_real_time(code_data, state)
      
      errors = result.data.syntax.errors
      assert Enum.any?(errors, fn e -> e.severity == :error end)
      
      warnings = result.data.syntax.warnings
      assert is_list(warnings)
    end
  end
end