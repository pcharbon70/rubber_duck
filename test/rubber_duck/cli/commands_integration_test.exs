defmodule RubberDuck.CLI.CommandsIntegrationTest do
  @moduledoc """
  Integration tests for CLI commands.
  
  These tests verify that all CLI commands work correctly end-to-end,
  including LLM integration, file system operations, and error handling.
  """
  
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.CLI.Commands
  alias RubberDuck.LLM.ConnectionManager
  
  setup do
    # Engine.Supervisor and ConnectionManager are already started by the application
    # Just ensure mock provider is connected
    case ConnectionManager.connect(:mock) do
      :ok -> :ok
      {:ok, :already_connected} -> :ok
    end
    
    # Create test files
    test_dir = Path.join(System.tmp_dir!(), "rubber_duck_test_#{System.unique_integer()}")
    File.mkdir_p!(test_dir)
    
    test_file = Path.join(test_dir, "test.ex")
    test_content = """
    defmodule Test do
      def hello(name) do
        "Hello, \#{name}!"
      end
      
      def unused_function do
        :not_used
      end
    end
    """
    File.write!(test_file, test_content)
    
    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)
    
    %{
      test_dir: test_dir,
      test_file: test_file,
      test_content: test_content,
      config: %RubberDuck.CLI.Config{
        format: :json,
        verbose: false,
        quiet: false,
        debug: false
      }
    }
  end
  
  describe "analyze command" do
    test "analyzes a single file successfully", %{test_file: test_file, config: config} do
      args = [
        path: test_file,
        type: :all,
        flags: [recursive: false, include_suggestions: true]
      ]
      
      assert {:ok, result} = Commands.Analyze.run(args, config)
      assert result.type == :analysis
      assert result.path == test_file
      assert is_list(result.results)
      
      # Should detect issues in the code
      issues = Enum.flat_map(result.results, & &1.issues)
      # For now, we don't detect unused functions, but we should have some issues
      assert length(issues) > 0
    end
    
    test "analyzes a directory recursively", %{test_dir: test_dir, config: config} do
      # Create nested file
      nested_dir = Path.join(test_dir, "nested")
      File.mkdir_p!(nested_dir)
      nested_file = Path.join(nested_dir, "nested.ex")
      File.write!(nested_file, "defmodule Nested do\nend")
      
      args = [
        path: test_dir,
        type: :all,
        flags: [recursive: true, include_suggestions: false]
      ]
      
      assert {:ok, result} = Commands.Analyze.run(args, config)
      assert result.type == :analysis
      assert length(result.results) == 2  # test.ex and nested.ex
    end
    
    test "handles non-existent file gracefully", %{config: config} do
      args = [
        path: "/non/existent/file.ex",
        type: :all,
        flags: [recursive: false]
      ]
      
      assert {:error, reason} = Commands.Analyze.run(args, config)
      assert reason =~ "not found" or reason =~ "does not exist"
    end
    
    test "analyzes with specific analysis type", %{test_file: test_file, config: config} do
      # Test each analysis type
      for type <- [:semantic, :style, :security] do
        args = [
          path: test_file,
          type: type,
          flags: [recursive: false]
        ]
        
        assert {:ok, result} = Commands.Analyze.run(args, config)
        assert result.type == :analysis
        
        # Verify only the requested analysis type was run
        assert Enum.all?(result.results, fn r -> r.analyzer == type end)
      end
    end
  end
  
  describe "generate command" do
    test "generates code from natural language prompt", %{config: config} do
      args = %{
        prompt: "Create a function that adds two numbers",
        language: :elixir,
        output: nil,
        context: nil,
        interactive: false
      }
      
      assert {:ok, result} = Commands.Generate.run(args, config)
      assert result.type == :generation
      assert result.language == :elixir
      assert is_binary(result.code)
      assert result.code =~ "def"  # Should contain a function definition
    end
    
    test "generates code and writes to file", %{test_dir: test_dir, config: config} do
      output_file = Path.join(test_dir, "generated.ex")
      
      args = %{
        prompt: "Create a GenServer that counts",
        language: :elixir,
        output: output_file,
        context: nil,
        interactive: false
      }
      
      assert {:ok, result} = Commands.Generate.run(args, config)
      assert result.output_file == output_file
      assert result.message =~ "written to"
      
      # Verify file was created
      assert File.exists?(output_file)
      content = File.read!(output_file)
      assert content == result.code
      assert content =~ "GenServer"
    end
    
    test "generates code with context", %{test_file: test_file, config: config} do
      args = %{
        prompt: "Add a function to greet multiple people",
        language: :elixir,
        output: nil,
        context: test_file,
        interactive: false
      }
      
      assert {:ok, result} = Commands.Generate.run(args, config)
      assert result.code =~ "def"
      # Context should influence generation (though with mock provider it's limited)
    end
    
    test "handles generation errors gracefully", %{config: config} do
      # Disconnect LLM to force error
      :ok = ConnectionManager.disconnect(:mock)
      
      args = %{
        prompt: "Generate code",
        language: :elixir,
        output: nil,
        context: nil,
        interactive: false
      }
      
      assert {:error, reason} = Commands.Generate.run(args, config)
      assert is_binary(reason)
      
      # Reconnect for other tests
      :ok = ConnectionManager.connect(:mock)
    end
  end
  
  describe "complete command" do
    test "provides code completion at cursor position", %{test_file: test_file, config: config} do
      args = %{
        file: test_file,
        line: 3,  # Inside the hello function
        column: 10
      }
      
      assert {:ok, result} = Commands.Complete.run(args, config)
      assert result.type == :completion
      assert is_list(result.completions)
      assert length(result.completions) > 0
      
      # Each completion should have required fields
      Enum.each(result.completions, fn completion ->
        assert Map.has_key?(completion, :text)
        assert Map.has_key?(completion, :score)
        assert is_binary(completion.text)
        assert is_number(completion.score)
      end)
    end
    
    test "handles invalid cursor position", %{test_file: test_file, config: config} do
      args = %{
        file: test_file,
        line: 999,  # Beyond file length
        column: 1
      }
      
      assert {:error, reason} = Commands.Complete.run(args, config)
      assert reason =~ "Invalid position" or reason =~ "out of range"
    end
    
    test "handles non-existent file", %{config: config} do
      args = %{
        file: "/non/existent/file.ex",
        line: 1,
        column: 1
      }
      
      assert {:error, reason} = Commands.Complete.run(args, config)
      assert reason =~ "not found" or reason =~ "does not exist"
    end
  end
  
  describe "refactor command" do
    test "refactors code based on instruction", %{test_file: test_file, config: config} do
      args = %{
        file: test_file,
        instruction: "Rename the hello function to greet",
        dry_run: true
      }
      
      assert {:ok, result} = Commands.Refactor.run(args, config)
      assert result.type == :refactor
      assert result.original_file == test_file
      assert is_binary(result.refactored_code)
      assert result.refactored_code =~ "def greet"
      assert result.dry_run == true
      
      # Original file should not be modified in dry run
      original_content = File.read!(test_file)
      assert original_content =~ "def hello"
    end
    
    test "applies refactoring when not in dry run mode", %{test_file: test_file, config: config} do
      # Make a copy to avoid affecting other tests
      refactor_file = test_file <> ".refactor"
      File.copy!(test_file, refactor_file)
      
      args = %{
        file: refactor_file,
        instruction: "Add documentation to all functions",
        dry_run: false
      }
      
      assert {:ok, result} = Commands.Refactor.run(args, config)
      assert result.dry_run == false
      assert result.message =~ "applied"
      
      # File should be modified
      new_content = File.read!(refactor_file)
      assert new_content != File.read!(test_file)
      assert new_content =~ "@doc"
      
      File.rm!(refactor_file)
    end
    
    test "handles refactoring errors", %{config: config} do
      args = %{
        file: "/non/existent/file.ex",
        instruction: "Refactor this",
        dry_run: true
      }
      
      assert {:error, reason} = Commands.Refactor.run(args, config)
      assert is_binary(reason)
    end
  end
  
  describe "test command" do
    test "generates tests for existing code", %{test_file: test_file, config: config} do
      args = %{
        file: test_file,
        framework: "exunit",
        output: nil
      }
      
      assert {:ok, result} = Commands.Test.run(args, config)
      assert result.type == :test_generation
      assert result.framework == "exunit"
      assert is_binary(result.tests)
      assert result.tests =~ "defmodule TestTest do"
      assert result.tests =~ "use ExUnit.Case"
      assert result.tests =~ "test"
    end
    
    test "generates tests and writes to file", %{test_file: test_file, test_dir: test_dir, config: config} do
      output_file = Path.join(test_dir, "test_test.exs")
      
      args = %{
        file: test_file,
        framework: "exunit",
        output: output_file
      }
      
      assert {:ok, result} = Commands.Test.run(args, config)
      assert result.output_file == output_file
      assert result.message =~ "written to"
      
      # Verify file was created
      assert File.exists?(output_file)
      content = File.read!(output_file)
      assert content == result.tests
    end
    
    test "handles non-Elixir files appropriately", %{test_dir: test_dir, config: config} do
      # Create a Python file
      python_file = Path.join(test_dir, "test.py")
      File.write!(python_file, "def add(a, b):\n    return a + b")
      
      args = %{
        file: python_file,
        framework: "pytest",
        output: nil
      }
      
      # Should either generate Python tests or return an appropriate error
      result = Commands.Test.run(args, config)
      
      case result do
        {:ok, res} ->
          # If it generates tests, they should be Python tests
          assert res.framework == "pytest"
          assert res.tests =~ "def test_" or res.tests =~ "import"
          
        {:error, reason} ->
          # If it errors, it should be because of language mismatch
          assert reason =~ "Python" or reason =~ "not supported"
      end
    end
  end
  
  describe "llm command" do
    test "shows LLM provider status", %{config: config} do
      args = %{}
      
      assert {:ok, result} = Commands.LLM.run(:status, args, config)
      assert result.type == :llm_status
      assert is_list(result.providers)
      
      # Should have at least the mock provider
      assert Enum.any?(result.providers, fn p -> p.name == :mock end)
      
      # Each provider should have required fields
      Enum.each(result.providers, fn provider ->
        assert Map.has_key?(provider, :name)
        assert Map.has_key?(provider, :status)
        assert Map.has_key?(provider, :enabled)
        assert Map.has_key?(provider, :health)
      end)
    end
    
    test "connects to LLM provider", %{config: config} do
      # First disconnect to ensure clean state
      ConnectionManager.disconnect(:mock)
      
      args = %{provider: "mock"}
      
      assert {:ok, result} = Commands.LLM.run(:connect, args, config)
      assert result.message =~ "connected"
      
      # Verify connection
      status = ConnectionManager.status()
      assert status[:mock].status == :connected
    end
    
    test "disconnects from LLM provider", %{config: config} do
      args = %{provider: "mock"}
      
      assert {:ok, result} = Commands.LLM.run(:disconnect, args, config)
      assert result.message =~ "Disconnected"
      
      # Verify disconnection
      status = ConnectionManager.status()
      assert status[:mock].status == :disconnected
      
      # Reconnect for other tests
      ConnectionManager.connect(:mock)
    end
    
    test "enables and disables providers", %{config: config} do
      # Disable
      args = %{provider: "mock"}
      assert {:ok, result} = Commands.LLM.run(:disable, args, config)
      assert result.message =~ "Disabled"
      
      status = ConnectionManager.status()
      assert status[:mock].enabled == false
      
      # Enable
      args = %{provider: "mock"}
      assert {:ok, result} = Commands.LLM.run(:enable, args, config)
      assert result.message =~ "Enabled"
      
      status = ConnectionManager.status()
      assert status[:mock].enabled == true
    end
  end
  
  describe "error handling" do
    test "all commands handle missing LLM connection gracefully" do
      # Disconnect all providers
      ConnectionManager.disconnect_all()
      
      config = %RubberDuck.CLI.Config{format: :json}
      
      # Test generate command
      result = Commands.Generate.run(%{prompt: "test", language: :elixir}, config)
      assert {:error, reason} = result
      assert is_binary(reason)
      
      # Test complete command  
      result = Commands.Complete.run(%{file: "test.ex", line: 1, column: 1}, config)
      assert {:error, reason} = result
      assert is_binary(reason)
      
      # Reconnect for cleanup
      ConnectionManager.connect(:mock)
    end
    
    test "all commands handle invalid input gracefully" do
      config = %RubberDuck.CLI.Config{format: :json}
      
      # Test with nil/missing required fields
      assert {:error, _} = Commands.Analyze.run([path: nil], config)
      assert {:error, _} = Commands.Generate.run(%{prompt: nil}, config)
      assert {:error, _} = Commands.Complete.run(%{file: nil}, config)
      assert {:error, _} = Commands.Refactor.run(%{file: nil, instruction: nil}, config)
      assert {:error, _} = Commands.Test.run(%{file: nil}, config)
    end
  end
  
  describe "output formatting" do
    test "commands respect format configuration", %{test_file: test_file} do
      # Test JSON format
      json_config = %RubberDuck.CLI.Config{format: :json}
      args = [path: test_file, type: :all, flags: []]
      
      {:ok, result} = Commands.Analyze.run(args, json_config)
      assert is_map(result)
      assert Map.has_key?(result, :type)
      
      # Test plain format (would need formatter integration)
      plain_config = %RubberDuck.CLI.Config{format: :plain}
      {:ok, result} = Commands.Analyze.run(args, plain_config)
      assert is_map(result)  # Still returns structured data, formatting happens later
    end
  end
end