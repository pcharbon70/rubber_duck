defmodule RubberDuck.CLI.Commands.LLMTest do
  use ExUnit.Case, async: false

  alias RubberDuck.CLI.Commands.LLM
  alias RubberDuck.LLM.ConnectionManager

  setup do
    # Start ConnectionManager for tests
    {:ok, _pid} = ConnectionManager.start_link([])

    # Default config
    config = %{
      verbose: false,
      format: :plain
    }

    {:ok, %{config: config}}
  end

  describe "status command" do
    test "shows status of all providers", %{config: config} do
      args = %{args: ["status"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_status
      assert is_list(result.providers)
      assert is_map(result.summary)

      # Check summary fields
      assert Map.has_key?(result.summary, :total)
      assert Map.has_key?(result.summary, :connected)
      assert Map.has_key?(result.summary, :healthy)
    end

    test "includes provider details", %{config: config} do
      # Connect a provider first
      ConnectionManager.connect(:mock)

      args = %{args: ["status"]}
      assert {:ok, result} = LLM.run(args, config)

      mock_provider = Enum.find(result.providers, &(&1.name == :mock))
      assert not is_nil(mock_provider)
      assert Map.has_key?(mock_provider, :status)
      assert Map.has_key?(mock_provider, :enabled)
      assert Map.has_key?(mock_provider, :health)
      assert Map.has_key?(mock_provider, :last_used)
      assert Map.has_key?(mock_provider, :errors)
    end
  end

  describe "connect command" do
    test "connects to specific provider", %{config: config} do
      args = %{args: ["connect", "mock"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_connection
      assert result.message =~ "connected"
      assert result.provider == "mock"

      # Verify connection
      assert ConnectionManager.connected?(:mock)
    end

    test "connects to all providers when no provider specified", %{config: config} do
      args = %{args: ["connect"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_connection
      assert result.message =~ "all"
    end

    test "returns error for unknown provider", %{config: config} do
      args = %{args: ["connect", "unknown"]}

      assert {:error, message} = LLM.run(args, config)
      assert message =~ "Unknown provider"
    end
  end

  describe "disconnect command" do
    test "disconnects from specific provider", %{config: config} do
      # Connect first
      ConnectionManager.connect(:mock)

      args = %{args: ["disconnect", "mock"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_disconnection
      assert result.message =~ "Disconnected"
      assert result.provider == "mock"

      # Verify disconnection
      refute ConnectionManager.connected?(:mock)
    end

    test "disconnects from all providers when no provider specified", %{config: config} do
      # Connect first
      ConnectionManager.connect_all()

      args = %{args: ["disconnect"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_disconnection
      assert result.message =~ "all"
    end
  end

  describe "enable command" do
    test "enables a provider", %{config: config} do
      args = %{args: ["enable", "mock"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_config
      assert result.message =~ "Enabled"
      assert result.provider == "mock"

      # Verify enabled
      status = ConnectionManager.status()
      assert status[:mock][:enabled] == true
    end

    test "returns error when no provider specified", %{config: config} do
      args = %{args: ["enable"]}

      assert {:error, message} = LLM.run(args, config)
      assert message =~ "Provider name required"
    end
  end

  describe "disable command" do
    test "disables a provider", %{config: config} do
      args = %{args: ["disable", "mock"]}

      assert {:ok, result} = LLM.run(args, config)
      assert result.type == :llm_config
      assert result.message =~ "Disabled"
      assert result.provider == "mock"

      # Verify disabled
      status = ConnectionManager.status()
      assert status[:mock][:enabled] == false
    end

    test "returns error when no provider specified", %{config: config} do
      args = %{args: ["disable"]}

      assert {:error, message} = LLM.run(args, config)
      assert message =~ "Provider name required"
    end
  end

  describe "unknown subcommand" do
    test "returns error for unknown subcommand", %{config: config} do
      args = %{args: ["unknown"]}

      assert {:error, message} = LLM.run(args, config)
      assert message =~ "Unknown LLM subcommand"
    end
  end
end
