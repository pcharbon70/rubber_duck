defmodule RubberDuck.CLI.IntegrationTest do
  use ExUnit.Case

  alias RubberDuck.CLI
  alias RubberDuck.Engine.Manager

  setup do
    # Ensure engines are loaded
    :ok = Manager.load_engines(RubberDuck.Engines)

    # Wait for engines to be ready
    Process.sleep(100)

    :ok
  end

  describe "CLI commands with LLM integration" do
    test "generate command produces code" do
      args = ["generate", "Create a hello world function"]
      config = %{format: :plain}

      assert {:ok, result} = CLI.Router.route(args, config)
      assert result.type == :generation
      assert is_binary(result.code)
      assert String.contains?(result.code, "hello") or String.contains?(result.code, "Hello")
    end

    test "complete command returns suggestions" do
      # Create a temporary file
      file_content = """
      defmodule Example do
        def hello do
          IO.
        end
      end
      """

      file_path = Path.join(System.tmp_dir!(), "test_complete.ex")
      File.write!(file_path, file_content)

      args = ["complete", file_path, "--line", "3", "--column", "7"]
      config = %{format: :plain}

      assert {:ok, result} = CLI.Router.route(args, config)
      assert result.type == :completion
      assert is_list(result.suggestions)
      assert length(result.suggestions) > 0

      # Cleanup
      File.rm!(file_path)
    end

    test "analyze command detects issues" do
      # Create a file with issues
      file_content = """
      defmodule BadCode do
        def long_function(a, b, c, d, e, f, g) do
          if a do
            if b do
              if c do
                # Too deeply nested
                {a, b, c}
              end
            end
          end
        end
      end
      """

      file_path = Path.join(System.tmp_dir!(), "test_analyze.ex")
      File.write!(file_path, file_content)

      args = ["analyze", file_path]
      config = %{format: :plain}

      assert {:ok, result} = CLI.Router.route(args, config)
      assert result.type == :analysis
      assert is_list(result.results)

      # Should find at least one issue (complexity or nesting)
      issues = Enum.flat_map(result.results, & &1.issues)
      assert length(issues) > 0

      # Cleanup
      File.rm!(file_path)
    end

    test "refactor command suggests improvements" do
      file_content = """
      defmodule Example do
        def bad_name(x) do
          x + 1
        end
      end
      """

      file_path = Path.join(System.tmp_dir!(), "test_refactor.ex")
      File.write!(file_path, file_content)

      args = ["refactor", file_path, "Improve function naming", "--diff"]
      config = %{format: :plain}

      assert {:ok, result} = CLI.Router.route(args, config)
      assert is_binary(result.diff)

      # Cleanup
      File.rm!(file_path)
    end

    test "test command generates tests" do
      file_content = """
      defmodule Calculator do
        def add(a, b) do
          a + b
        end
        
        def subtract(a, b) do
          a - b
        end
      end
      """

      file_path = Path.join(System.tmp_dir!(), "calculator.ex")
      File.write!(file_path, file_content)

      args = ["test", file_path]
      config = %{format: :plain}

      assert {:ok, result} = CLI.Router.route(args, config)
      assert result.type == :test_generation
      assert is_binary(result.tests)
      assert String.contains?(result.tests, "test") or String.contains?(result.tests, "assert")

      # Cleanup
      File.rm!(file_path)
    end
  end

  describe "error handling" do
    test "handles missing file gracefully" do
      args = ["analyze", "/nonexistent/file.ex"]
      config = %{format: :plain}

      assert {:error, _message} = CLI.Router.route(args, config)
    end

    test "handles invalid command" do
      args = ["invalid_command"]
      config = %{format: :plain}

      assert {:error, message} = CLI.Router.route(args, config)
      assert String.contains?(message, "Unknown command")
    end
  end
end
