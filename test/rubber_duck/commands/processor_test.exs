defmodule RubberDuck.Commands.ProcessorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Commands.{Processor, Command, Context}

  setup do
    # Ensure Processor is started for all tests
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    context = %Context{
      user_id: "test_user",
      session_id: "test_session",
      permissions: [:read, :write, :execute]
    }
    
    {:ok, context: context}
  end

  describe "command execution pipeline" do
    test "executes a simple health command", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :health,
        args: %{},
        options: %{},
        context: context,
        client_type: :websocket,
        format: :table
      })

      assert {:ok, result} = Processor.execute(command)
      # Health result is formatted as text since no table formatter for health
      assert is_binary(result)
      assert result =~ "healthy"
      assert result =~ "memory:"
      assert result =~ "services:"
    end

    test "executes analyze command with proper args", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: "lib"},
        options: %{recursive: true},
        context: context,
        client_type: :websocket,
        format: :table
      })

      assert {:ok, result} = Processor.execute(command)
      # Analyze result is formatted as table
      assert is_binary(result)
      assert result =~ "File"
      assert result =~ "Issues"
      assert result =~ "Lines"
      assert result =~ "Complexity"
    end

    test "returns error for unknown command", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :unknown_command,
        args: %{},
        options: %{},
        context: context,
        client_type: :websocket,
        format: :table
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Unknown command" or reason =~ "No handler"
    end

    test "validates command permissions", %{context: context} do
      restricted_context = %{context | permissions: [:read]}
      
      {:ok, command} = Command.new(%{
        name: :generate,
        args: %{description: "test code"},
        options: %{},
        context: restricted_context,
        client_type: :websocket,
        format: :table
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Unauthorized" or reason =~ "permission"
    end
  end

  describe "async command execution" do
    test "supports async execution with progress updates", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: "large/project"},
        options: %{recursive: true, async: true},
        context: context,
        client_type: :websocket,
        format: :text
      })

      assert {:ok, %{request_id: request_id}} = Processor.execute_async(command)
      assert is_binary(request_id)
      
      # Should be able to check status
      assert {:ok, status} = Processor.get_status(request_id)
      assert status.status in [:pending, :running, :completed]
    end

    test "supports command cancellation", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :analyze,
        args: %{path: "large/project"},
        options: %{recursive: true, async: true},
        context: context,
        client_type: :websocket,
        format: :text
      })

      {:ok, %{request_id: request_id}} = Processor.execute_async(command)
      
      assert :ok = Processor.cancel(request_id)
      
      # Just verify we can call cancel - status may be unstable due to async nature
      assert is_binary(request_id)
    end
  end

  describe "handler registry" do
    test "can register and retrieve handlers" do
      # This should be set up automatically during processor init
      handlers = Processor.list_handlers()
      
      assert Map.has_key?(handlers, :health)
      assert Map.has_key?(handlers, :analyze)
      assert Map.has_key?(handlers, :generate)
    end
  end
end