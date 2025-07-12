defmodule RubberDuck.Commands.Handlers.LLMTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Commands.{Command, Context, Processor}
  alias RubberDuck.LLM.ConnectionManager

  setup do
    # Ensure Processor is started
    case Process.whereis(Processor) do
      nil -> start_supervised!(Processor)
      _pid -> :ok
    end
    
    # Create test context
    {:ok, context} = Context.new(%{
      user_id: "test_user",
      session_id: "test_session",
      permissions: [:read, :write]
    })

    {:ok, %{context: context}}
  end

  describe "status subcommand" do
    test "shows status of all providers", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :status,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert Map.has_key?(result, "type")
      assert result["type"] == "llm_status"
      assert Map.has_key?(result, "providers")
      assert is_list(result["providers"])
      assert Map.has_key?(result, "summary")
    end

    test "includes provider details in formatted output", %{context: context} do
      # Connect a provider first
      ConnectionManager.connect(:mock)

      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :status,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :table
      })

      assert {:ok, result} = Processor.execute(command)
      assert is_binary(result)
      
      # Table output should contain provider information
      assert result =~ "Name"
      assert result =~ "Status"
      assert result =~ "Health"
      assert result =~ "mock"
    end
  end

  describe "connect subcommand" do
    test "connects to specific provider", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :connect,
        args: %{provider: "mock"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_connection"
      assert result["message"] =~ "connected"
      assert result["provider"] == "mock"

      # Verify connection
      assert ConnectionManager.connected?(:mock)
    end

    test "connects to all providers when no provider specified", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :connect,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_connection"
      assert result["message"] =~ "all"
    end

    test "returns error for unknown provider", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :connect,
        args: %{provider: "unknown"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "provider_not_configured"
    end
  end

  describe "disconnect subcommand" do
    test "disconnects from specific provider", %{context: context} do
      # Connect first
      ConnectionManager.connect(:mock)

      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :disconnect,
        args: %{provider: "mock"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_disconnection"
      assert result["message"] =~ "Disconnected"
      assert result["provider"] == "mock"

      # Verify disconnection
      refute ConnectionManager.connected?(:mock)
    end

    test "disconnects from all providers when no provider specified", %{context: context} do
      # Connect first
      ConnectionManager.connect_all()

      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :disconnect,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_disconnection"
      assert result["message"] =~ "all"
    end
  end

  describe "enable subcommand" do
    test "enables a provider", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :enable,
        args: %{provider: "mock"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_config"
      assert result["message"] =~ "Enabled"
      assert result["provider"] == "mock"

      # Verify enabled
      status = ConnectionManager.status()
      assert status[:mock][:enabled] == true
    end

    test "returns error when no provider specified", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :enable,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Provider name required"
    end
  end

  describe "disable subcommand" do
    test "disables a provider", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :disable,
        args: %{provider: "mock"},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:ok, result_json} = Processor.execute(command)
      assert {:ok, result} = Jason.decode(result_json)
      
      assert result["type"] == "llm_config"
      assert result["message"] =~ "Disabled"
      assert result["provider"] == "mock"

      # Verify disabled
      status = ConnectionManager.status()
      assert status[:mock][:enabled] == false
    end

    test "returns error when no provider specified", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :disable,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Provider name required"
    end
  end

  describe "unknown subcommand" do
    test "returns error for unknown subcommand", %{context: context} do
      {:ok, command} = Command.new(%{
        name: :llm,
        subcommand: :unknown,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :json
      })

      assert {:error, reason} = Processor.execute(command)
      assert reason =~ "Invalid LLM subcommand"
    end
  end

  describe "formatting" do
    test "respects different output formats", %{context: context} do
      # Test with text format
      {:ok, text_command} = Command.new(%{
        name: :llm,
        subcommand: :status,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      })

      assert {:ok, text_result} = Processor.execute(text_command)
      assert is_binary(text_result)
      assert text_result =~ "LLM Status"

      # Test with markdown format
      {:ok, md_command} = Command.new(%{
        name: :llm,
        subcommand: :status,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :markdown
      })

      assert {:ok, md_result} = Processor.execute(md_command)
      assert is_binary(md_result)
      assert md_result =~ "#"  # Markdown headers
    end
  end
end