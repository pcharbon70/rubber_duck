defmodule RubberDuck.CLIClient.UnifiedIntegrationTest do
  use ExUnit.Case, async: false

  alias RubberDuck.CLIClient.UnifiedIntegration
  alias RubberDuck.Commands.Processor

  setup do
    # Ensure Processor is started
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    :ok
  end

  describe "unified command integration" do
    test "handles analyze command through unified system" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_123",
        permissions: [:read, :write],
        format: :json
      }
      
      args = ["analyze", "mix.exs"]
      
      # This should work after integration
      assert {:ok, result} = UnifiedIntegration.execute_command(args, config)
      
      # Should be JSON formatted result from unified system
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end

    test "handles streaming commands through unified system" do
      config = %{
        user_id: "cli_test_user", 
        session_id: "test_session_456",
        permissions: [:read, :write],
        format: :json
      }
      
      args = ["generate", "Create a hello world function"]
      
      # This should work for streaming commands
      assert {:ok, stream_info} = UnifiedIntegration.execute_streaming_command(args, config, fn _chunk -> :ok end)
      assert Map.has_key?(stream_info, :request_id)
    end

    test "maintains error handling compatibility" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_789", 
        permissions: [:read],
        format: :plain
      }
      
      args = ["analyze", "/nonexistent/path"]
      
      # Should return proper error format
      assert {:error, reason} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(reason)
      assert reason =~ "not found" or reason =~ "does not exist"
    end

    test "handles different output formats correctly" do
      config_json = %{
        user_id: "cli_test_user",
        session_id: "test_session_json",
        permissions: [:read, :write],
        format: :json
      }
      
      config_plain = %{config_json | format: :plain}
      config_table = %{config_json | format: :table}
      
      args = ["health"]
      
      # Test JSON format
      assert {:ok, json_result} = UnifiedIntegration.execute_command(args, config_json)
      assert is_binary(json_result)
      assert {:ok, _parsed} = Jason.decode(json_result)
      
      # Test plain text format
      assert {:ok, plain_result} = UnifiedIntegration.execute_command(args, config_plain)
      assert is_binary(plain_result)
      
      # Test table format
      assert {:ok, table_result} = UnifiedIntegration.execute_command(args, config_table)
      assert is_binary(table_result)
    end

    test "handles generate command with options" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_generate",
        permissions: [:read, :write, :execute],
        format: :json
      }
      
      args = ["generate", "Create a simple test function", "--language", "elixir"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end

    test "handles llm subcommands" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_llm",
        permissions: [:read, :write],
        format: :json
      }
      
      args = ["llm", "status"]
      
      assert {:ok, result} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(result)
      assert {:ok, parsed} = Jason.decode(result)
      assert is_map(parsed)
    end

    test "handles invalid commands gracefully" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_invalid",
        permissions: [:read, :write],
        format: :json
      }
      
      args = ["nonexistent_command", "arg1"]
      
      assert {:error, reason} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(reason)
      assert reason =~ "Unknown command" or reason =~ "Invalid command"
    end

    test "handles empty command list" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_session_empty",
        permissions: [:read, :write],
        format: :json
      }
      
      args = []
      
      assert {:error, reason} = UnifiedIntegration.execute_command(args, config)
      assert is_binary(reason)
    end

    test "generates unique session IDs when not provided" do
      config1 = %{
        user_id: "cli_test_user",
        permissions: [:read, :write],
        format: :json
      }
      
      config2 = %{
        user_id: "cli_test_user",
        permissions: [:read, :write],
        format: :json
      }
      
      args = ["health"]
      
      # Both should succeed but with different session IDs
      assert {:ok, _result1} = UnifiedIntegration.execute_command(args, config1)
      assert {:ok, _result2} = UnifiedIntegration.execute_command(args, config2)
    end
  end

  describe "streaming command integration" do
    test "handles streaming command monitoring" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_stream_monitoring",
        permissions: [:read, :write, :execute],
        format: :json
      }
      
      args = ["generate", "Create a complex module"]
      
      handler = fn chunk ->
        send(self(), {:chunk_received, chunk})
      end
      
      assert {:ok, %{request_id: request_id}} = 
        UnifiedIntegration.execute_streaming_command(args, config, handler)
      
      assert is_binary(request_id)
      
      # Should be able to get status
      assert {:ok, _status} = UnifiedIntegration.get_status(request_id)
    end

    test "handles streaming command cancellation" do
      config = %{
        user_id: "cli_test_user",
        session_id: "test_stream_cancel",
        permissions: [:read, :write, :execute],
        format: :json
      }
      
      args = ["generate", "Create a long running task"]
      
      handler = fn _chunk -> :ok end
      
      assert {:ok, %{request_id: request_id}} = 
        UnifiedIntegration.execute_streaming_command(args, config, handler)
      
      # Should be able to cancel
      assert :ok = UnifiedIntegration.cancel(request_id)
    end
  end
end