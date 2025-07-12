defmodule RubberDuck.Commands.Handlers.AnalyzeTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Commands.{Command, Context, Processor}

  setup do
    # Ensure Processor is started
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    # Create test files
    test_dir = Path.join(System.tmp_dir!(), "analyze_test_#{System.unique_integer()}")
    File.mkdir_p!(test_dir)
    
    test_file = Path.join(test_dir, "test.ex")
    test_content = """
    defmodule Test do
      def hello(name) do
        "Hello, \#{name}!"
      end
    end
    """
    File.write!(test_file, test_content)
    
    # Create test context
    {:ok, context} = Context.new(%{
      user_id: "test_user",
      session_id: "test_session",
      permissions: [:read]
    })

    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)

    {:ok, %{
      context: context,
      test_dir: test_dir,
      test_file: test_file
    }}
  end

  describe "analyze command" do
    test "analyzes a single file", %{context: context, test_file: test_file} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: test_file},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert Map.has_key?(result, "analysis_results")
      assert Map.has_key?(result, "file_count")
      assert result["file_count"] == 1
      
      # Check first analysis result
      [first_result | _] = result["analysis_results"]
      assert first_result["file"] == test_file
      assert Map.has_key?(first_result, "metrics")
      assert Map.has_key?(first_result, "issues")
    end

    test "analyzes directory recursively", %{context: context, test_dir: test_dir} do
      # Create nested file
      nested_dir = Path.join(test_dir, "nested")
      File.mkdir_p!(nested_dir)
      nested_file = Path.join(nested_dir, "nested.ex")
      File.write!(nested_file, "defmodule Nested do\nend")

      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: test_dir},
        options: %{recursive: true},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["file_count"] == 2
      assert length(result["analysis_results"]) == 2
    end

    test "handles non-existent path", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: "/non/existent/path"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Path not found"
    end

    test "respects analysis type option", %{context: context, test_file: test_file} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: test_file},
        options: %{type: "security"},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      [first_result | _] = result["analysis_results"]
      assert first_result["type"] == "security"
    end

    test "formats output as table", %{context: context, test_file: test_file} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: test_file},
        options: %{},
        context: context,
        client_type: :cli,
        format: :table
      })

      assert {:ok, result} = Processor.execute(command)
      assert is_binary(result)
      
      # Table format should have headers and dividers
      assert result =~ "File"
      assert result =~ "Issues"
      assert result =~ "Lines"
      assert result =~ "Complexity"
      assert result =~ "+---"
      assert result =~ "|"
    end
  end

  describe "permissions" do
    test "allows read-only users to analyze", %{test_file: test_file} do
      {:ok, context} = Context.new(%{
        user_id: "readonly_user",
        session_id: "test_session",
        permissions: [:read]
      })

      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: test_file},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, _result} = Processor.execute(command)
    end
  end
end