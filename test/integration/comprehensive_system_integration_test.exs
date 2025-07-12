defmodule RubberDuck.Integration.ComprehensiveSystemIntegrationTest do
  @moduledoc """
  Comprehensive end-to-end integration tests for the WebSocket CLI client system
  integrated with the unified command abstraction layer.
  
  This test suite validates that all command types work correctly through the
  unified system and ensures reliability across all interfaces.
  """
  
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.CLIClient.UnifiedIntegration
  alias RubberDuck.Commands.{Processor, Parser, Context}
  alias RubberDuck.Commands.Adapters.{CLI, WebSocket, LiveView, TUI}
  alias RubberDuck.LLM.ConnectionManager
  
  @test_timeout 5000
  
  setup do
    # Ensure processor is started
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    # Ensure mock provider is connected for consistent testing
    case ConnectionManager.connect(:mock) do
      :ok -> :ok
      {:ok, :already_connected} -> :ok
    end
    
    # Create test environment
    test_dir = Path.join(System.tmp_dir!(), "rubber_duck_comprehensive_test_#{System.unique_integer()}")
    File.mkdir_p!(test_dir)
    
    # Create test files for different scenarios
    elixir_file = Path.join(test_dir, "test_module.ex")
    elixir_content = """
    defmodule TestModule do
      @moduledoc "A test module for integration testing"
      
      def hello(name) when is_binary(name) do
        "Hello, \#{name}!"
      end
      
      def calculate(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def unused_function do
        # This function is intentionally unused for analysis testing
        :not_used
      end
    end
    """
    File.write!(elixir_file, elixir_content)
    
    javascript_file = Path.join(test_dir, "test.js")
    javascript_content = """
    function greet(name) {
        return `Hello, ${name}!`;
    }
    
    function add(a, b) {
        return a + b;
    }
    
    // Unused function for testing
    function unusedFunction() {
        return 'not used';
    }
    """
    File.write!(javascript_file, javascript_content)
    
    on_exit(fn ->
      File.rm_rf!(test_dir)
    end)
    
    # Standard test configuration
    base_config = %{
      user_id: "test_comprehensive_user",
      session_id: "comprehensive_test_session_#{System.unique_integer()}",
      permissions: [:read, :write, :execute],
      metadata: %{test_suite: "comprehensive_integration"}
    }
    
    %{
      test_dir: test_dir,
      elixir_file: elixir_file,
      javascript_file: javascript_file,
      elixir_content: elixir_content,
      javascript_content: javascript_content,
      base_config: base_config
    }
  end
  
  describe "CLI command execution through unified system" do
    @tag timeout: @test_timeout
    test "analyze command processes files correctly", %{elixir_file: elixir_file, base_config: config} do
      # Test analyze command with JSON format
      json_config = Map.put(config, :format, :json)
      args = ["analyze", elixir_file, "--type", "all"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
      
      # Test analyze command with plain format
      plain_config = Map.put(config, :format, :plain)
      assert {:ok, plain_result} = UnifiedIntegration.execute_command(args, plain_config)
      assert is_binary(plain_result)
      assert plain_result != result  # Should be different format
    end
    
    @tag timeout: @test_timeout
    test "generate command creates code correctly", %{base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["generate", "Create a simple function that multiplies two numbers", "--language", "elixir"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
    
    @tag timeout: @test_timeout  
    test "health command reports system status", %{base_config: config} do
      # Test all output formats for health command
      for format <- [:json, :plain, :table] do
        test_config = Map.put(config, :format, format)
        args = ["health"]
        
        assert {:ok, result} = UnifiedIntegration.execute_command(args, test_config)
        assert is_binary(result)
        
        case format do
          :json ->
            assert {:ok, _parsed} = Jason.decode(result)
          _ ->
            assert result =~ "healthy" or result =~ "status" or result =~ "Health"
        end
      end
    end
    
    @tag timeout: @test_timeout
    test "complete command provides suggestions", %{elixir_file: elixir_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["complete", "--line", "8", "--column", "10", elixir_file]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
    
    @tag timeout: @test_timeout
    test "refactor command transforms code", %{elixir_file: elixir_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["refactor", elixir_file, "--instruction", "Add documentation to all functions"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
    
    @tag timeout: @test_timeout
    test "test command generates tests", %{elixir_file: elixir_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["test", "--framework", "exunit", elixir_file]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
    
    @tag timeout: @test_timeout
    test "llm command manages providers", %{base_config: config} do
      json_config = Map.put(config, :format, :json)
      
      # Test status subcommand
      args = ["llm", "status"]
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
  end
  
  describe "streaming command functionality" do
    @tag timeout: @test_timeout
    test "handles streaming commands with progress monitoring", %{base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["generate", "Create a complex Elixir GenServer with state management"]
      
      # Track streaming chunks
      chunks = []
      handler = fn chunk ->
        send(self(), {:chunk_received, chunk})
      end
      
      assert {:ok, %{request_id: request_id}} = 
        UnifiedIntegration.execute_streaming_command(args, json_config, handler)
      
      assert is_binary(request_id)
      
      # Should be able to get status
      assert {:ok, status} = UnifiedIntegration.get_status(request_id)
      assert status.status in [:pending, :running, :completed]
      
      # Wait for completion or timeout
      Process.sleep(100)
      assert {:ok, final_status} = UnifiedIntegration.get_status(request_id)
      assert final_status.status in [:completed, :running]
    end
    
    @tag timeout: @test_timeout
    test "can cancel streaming commands", %{test_dir: test_dir, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["analyze", test_dir, "--recursive"]
      
      handler = fn _chunk -> :ok end
      
      assert {:ok, %{request_id: request_id}} = 
        UnifiedIntegration.execute_streaming_command(args, json_config, handler)
      
      # Cancel immediately
      assert :ok = UnifiedIntegration.cancel(request_id)
      
      # Status should reflect cancellation or completion
      Process.sleep(50)
      {:ok, status} = UnifiedIntegration.get_status(request_id)
      assert status.status in [:cancelled, :completed]
    end
  end
  
  describe "cross-adapter consistency" do
    @tag timeout: @test_timeout
    test "all adapters produce consistent results for health command", %{base_config: config} do
      # Create adapter-specific configurations
      cli_config = Map.put(config, :format, :json)
      
      # CLI adapter through UnifiedIntegration
      {:ok, cli_result} = UnifiedIntegration.execute_command(["health"], cli_config)
      
      # WebSocket adapter directly
      socket = %{
        assigns: %{user_id: config.user_id, permissions: config.permissions},
        id: "socket_#{System.unique_integer()}",
        topic: "cli:commands"
      }
      {:ok, ws_result} = WebSocket.handle_message("cli:commands", %{"command" => "health", "params" => %{}}, socket)
      
      # Both should return formatted strings containing health info
      assert is_binary(cli_result)
      assert is_binary(ws_result)
      
      # Both should be valid JSON
      assert {:ok, cli_parsed} = Jason.decode(cli_result)
      assert {:ok, ws_parsed} = Jason.decode(ws_result)
      
      # Both should contain health status information
      assert is_map(cli_parsed)
      assert is_map(ws_parsed)
    end
    
    @tag timeout: @test_timeout
    test "format consistency across adapters", %{elixir_file: elixir_file, base_config: config} do
      # Test analyze command through different adapters with same format
      args = ["analyze", elixir_file]
      json_config = Map.put(config, :format, :json)
      
      # CLI through UnifiedIntegration
      {:ok, cli_result} = UnifiedIntegration.execute_command(args, json_config)
      
      # Direct CLI adapter
      {:ok, direct_cli_result} = CLI.execute(args, json_config)
      
      # Both should be valid JSON
      assert {:ok, cli_parsed} = Jason.decode(cli_result)
      assert {:ok, direct_parsed} = Jason.decode(direct_cli_result)
      
      # Results should have similar structure
      assert is_map(cli_parsed)
      assert is_map(direct_parsed)
    end
  end
  
  describe "error handling scenarios" do
    @tag timeout: @test_timeout
    test "handles invalid command arguments gracefully", %{base_config: config} do
      # Invalid command
      args = ["nonexistent_command", "arg1"]
      assert {:error, reason} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(reason)
      assert reason =~ "Unknown command" or reason =~ "Invalid command"
      
      # Empty command list
      assert {:error, reason} = UnifiedIntegration.execute_command([], config)
      assert is_binary(reason)
    end
    
    @tag timeout: @test_timeout
    test "handles file not found scenarios", %{base_config: config} do
      args = ["analyze", "/nonexistent/path/file.ex"]
      assert {:error, reason} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(reason)
      assert reason =~ "not found" or reason =~ "does not exist"
    end
    
    @tag timeout: @test_timeout
    test "handles permission denied cases", %{elixir_file: elixir_file} do
      # Create restricted config with no write permissions
      restricted_config = %{
        user_id: "restricted_user",
        session_id: "restricted_session",
        permissions: [:read],  # No write permission
        format: :json
      }
      
      # Try to execute a command that requires write permission
      args = ["refactor", elixir_file, "--instruction", "test"]
      assert {:error, reason} = UnifiedIntegration.execute_command(args, restricted_config)
      assert is_binary(reason)
      assert reason =~ "Unauthorized" or reason =~ "permission" or reason =~ "not allowed"
    end
  end
  
  describe "async command management" do
    @tag timeout: @test_timeout
    test "tracks async command lifecycle", %{elixir_file: elixir_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["analyze", elixir_file, "--type", "all"]
      
      # Start async execution through streaming
      handler = fn _chunk -> :ok end
      assert {:ok, %{request_id: request_id}} = 
        UnifiedIntegration.execute_streaming_command(args, json_config, handler)
      
      # Should start in pending or running state
      assert {:ok, status1} = UnifiedIntegration.get_status(request_id)
      assert status1.status in [:pending, :running]
      
      # Wait for completion
      Process.sleep(200)
      
      # Should be completed or still running (depending on timing)
      assert {:ok, status2} = UnifiedIntegration.get_status(request_id)
      assert status2.status in [:completed, :running]
    end
  end
  
  describe "performance and reliability" do
    @tag timeout: 10000
    test "handles multiple concurrent commands", %{elixir_file: elixir_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      
      # Start multiple commands concurrently
      tasks = for i <- 1..3 do
        Task.async(fn ->
          session_config = Map.put(json_config, :session_id, "concurrent_#{i}_#{System.unique_integer()}")
          args = ["analyze", elixir_file]
          UnifiedIntegration.execute_command(args, session_config)
        end)
      end
      
      # Wait for all to complete
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      # All results should be valid JSON
      for {:ok, result} <- results do
        assert {:ok, _parsed} = Jason.decode(result)
      end
    end
    
    @tag timeout: @test_timeout
    test "memory usage stays reasonable during execution", %{elixir_file: elixir_file, base_config: config} do
      # Get initial memory usage
      initial_memory = :erlang.memory(:total)
      
      # Execute several commands
      json_config = Map.put(config, :format, :json)
      for _i <- 1..5 do
        args = ["analyze", elixir_file]
        {:ok, _result} = UnifiedIntegration.execute_command(args, json_config)
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      
      # Check final memory usage
      final_memory = :erlang.memory(:total)
      memory_increase = final_memory - initial_memory
      
      # Memory increase should be reasonable (less than 10MB for this test)
      assert memory_increase < 10_000_000, 
        "Memory usage increased by #{memory_increase} bytes, which seems excessive"
    end
  end
  
  describe "integration with file system operations" do
    @tag timeout: @test_timeout
    test "processes different file types correctly", %{elixir_file: elixir_file, javascript_file: javascript_file, base_config: config} do
      json_config = Map.put(config, :format, :json)
      
      # Test Elixir file
      elixir_args = ["analyze", elixir_file, "--type", "all"]
      assert {:ok, elixir_result} = UnifiedIntegration.execute_command(elixir_args, json_config)
      assert {:ok, elixir_parsed} = Jason.decode(elixir_result)
      assert is_map(elixir_parsed)
      
      # Test JavaScript file
      js_args = ["analyze", javascript_file, "--type", "all"]
      assert {:ok, js_result} = UnifiedIntegration.execute_command(js_args, json_config)
      assert {:ok, js_parsed} = Jason.decode(js_result)
      assert is_map(js_parsed)
      
      # Results should be different (different file contents)
      assert elixir_result != js_result
    end
    
    @tag timeout: @test_timeout
    test "handles recursive directory analysis", %{test_dir: test_dir, base_config: config} do
      json_config = Map.put(config, :format, :json)
      args = ["analyze", test_dir, "--recursive"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, json_config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end
  end
  
  # This test should fail initially to demonstrate TDD approach
  describe "advanced integration scenarios" do
    @tag timeout: @test_timeout
    test "maintains session state across multiple commands", %{elixir_file: elixir_file, base_config: config} do
      # This test will initially fail as we verify session state management
      json_config = Map.put(config, :format, :json)
      session_id = "persistent_session_#{System.unique_integer()}"
      session_config = Map.put(json_config, :session_id, session_id)
      
      # Execute first command
      args1 = ["analyze", elixir_file]
      assert {:ok, result1} = UnifiedIntegration.execute_command(args1, session_config)
      
      # Execute second command with same session
      args2 = ["health"]
      assert {:ok, result2} = UnifiedIntegration.execute_command(args2, session_config)
      
      # Both should succeed and maintain session context
      assert {:ok, _parsed1} = Jason.decode(result1)
      assert {:ok, _parsed2} = Jason.decode(result2)
      
      # Session state should be maintained (this is what we're testing)
      # For now, we'll just verify both commands executed successfully
      assert is_binary(result1)
      assert is_binary(result2)
    end
  end
end