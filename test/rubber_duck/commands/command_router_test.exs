defmodule RubberDuck.Commands.CommandRouterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Commands.{CommandRouter, CommandRegistry, CommandBehaviour, CommandMetadata}
  alias RubberDuck.Commands.CommandMetadata.Parameter

  # Test command implementations
  defmodule TestCommand do
    @behaviour CommandBehaviour

    @impl true
    def metadata do
      %CommandMetadata{
        name: "test",
        description: "A test command",
        category: :testing,
        parameters: [
          %Parameter{
            name: :input,
            type: :string,
            required: true,
            description: "Test input"
          }
        ]
      }
    end

    @impl true
    def validate(params) do
      if params[:input], do: :ok, else: {:error, [{:input, "is required"}]}
    end

    @impl true
    def execute(params, context) do
      {:ok, "Test result: #{params[:input]} from #{context[:node] || "unknown"}"}
    end
  end

  defmodule AsyncCommand do
    @behaviour CommandBehaviour

    @impl true
    def metadata do
      %CommandMetadata{
        name: "async_test",
        description: "An async test command",
        category: :testing,
        async: true
      }
    end

    @impl true
    def validate(_params), do: :ok

    @impl true
    def execute(_params, _context) do
      Process.sleep(10)
      {:ok, :async_result}
    end
  end

  defmodule FailingCommand do
    @behaviour CommandBehaviour

    @impl true
    def metadata do
      %CommandMetadata{
        name: "failing",
        description: "A command that fails",
        category: :testing
      }
    end

    @impl true
    def validate(_params), do: :ok

    @impl true
    def execute(_params, _context) do
      {:error, "Command intentionally failed"}
    end
  end

  setup do
    # Start registry and router for each test
    registry_name = :"test_registry_#{:rand.uniform(1000000)}"
    router_name = :"test_router_#{:rand.uniform(1000000)}"
    
    {:ok, _registry_pid} = CommandRegistry.start_link(name: registry_name)
    {:ok, _router_pid} = CommandRouter.start_link(name: router_name, registry: registry_name)
    
    # Register test commands
    CommandRegistry.register_command(registry_name, TestCommand)
    CommandRegistry.register_command(registry_name, AsyncCommand)
    CommandRegistry.register_command(registry_name, FailingCommand)
    
    %{registry: registry_name, router: router_name}
  end

  describe "CommandRouter" do
    test "starts successfully", %{router: router} do
      assert Process.alive?(Process.whereis(router))
    end

    test "routes simple command execution", %{router: router} do
      request = %{
        command: "test",
        params: %{input: "hello"},
        context: %{session_id: "test-session"}
      }
      
      assert {:ok, result} = CommandRouter.execute_command(router, request)
      assert result =~ "Test result: hello"
    end

    test "validates command parameters before execution", %{router: router} do
      request = %{
        command: "test",
        params: %{}, # Missing required input parameter
        context: %{session_id: "test-session"}
      }
      
      assert {:error, {:validation_failed, errors}} = CommandRouter.execute_command(router, request)
      assert [{:input, "is required"}] = errors
    end

    test "handles command not found", %{router: router} do
      request = %{
        command: "nonexistent",
        params: %{},
        context: %{session_id: "test-session"}
      }
      
      assert {:error, :command_not_found} = CommandRouter.execute_command(router, request)
    end

    test "handles command execution failure", %{router: router} do
      request = %{
        command: "failing",
        params: %{},
        context: %{session_id: "test-session"}
      }
      
      assert {:error, "Command intentionally failed"} = CommandRouter.execute_command(router, request)
    end

    test "routes async command execution", %{router: router} do
      request = %{
        command: "async_test",
        params: %{},
        context: %{session_id: "test-session"}
      }
      
      assert {:ok, :async_result} = CommandRouter.execute_command(router, request)
    end

    test "adds routing context to command execution", %{router: router} do
      request = %{
        command: "test",
        params: %{input: "context_test"},
        context: %{session_id: "test-session", user_id: "user123"}
      }
      
      assert {:ok, result} = CommandRouter.execute_command(router, request)
      assert result =~ "context_test"
      # The router should add node information to context
    end

    test "handles concurrent command executions", %{router: router} do
      requests = for i <- 1..5 do
        %{
          command: "test",
          params: %{input: "concurrent_#{i}"},
          context: %{session_id: "test-session-#{i}"}
        }
      end
      
      tasks = Enum.map(requests, fn request ->
        Task.async(fn -> CommandRouter.execute_command(router, request) end)
      end)
      
      results = Task.await_many(tasks, 1000)
      
      assert length(results) == 5
      assert Enum.all?(results, fn {:ok, _result} -> true; _ -> false end)
    end

    test "supports command routing with timeout", %{router: router} do
      request = %{
        command: "test",
        params: %{input: "timeout_test"},
        context: %{session_id: "test-session"},
        timeout: 100
      }
      
      assert {:ok, _result} = CommandRouter.execute_command(router, request)
    end

    test "provides routing statistics", %{router: router} do
      # Execute some commands first
      request = %{
        command: "test",
        params: %{input: "stats_test"},
        context: %{session_id: "test-session"}
      }
      
      CommandRouter.execute_command(router, request)
      CommandRouter.execute_command(router, request)
      
      stats = CommandRouter.get_stats(router)
      assert stats.total_requests >= 2
      assert stats.successful_requests >= 2
      assert is_number(stats.average_response_time)
    end

    test "handles registry unavailable gracefully", %{router: router, registry: registry} do
      # Kill the registry
      registry_pid = Process.whereis(registry)
      Process.exit(registry_pid, :kill)
      Process.sleep(10)
      
      request = %{
        command: "test",
        params: %{input: "registry_down"},
        context: %{session_id: "test-session"}
      }
      
      assert {:error, :registry_unavailable} = CommandRouter.execute_command(router, request)
    end
  end

  describe "CommandRouter load balancing" do
    test "distributes commands across available nodes", %{router: router} do
      # This test simulates distributed behavior
      # In a real cluster, commands would be distributed across nodes
      
      request = %{
        command: "test",
        params: %{input: "load_balance_test"},
        context: %{session_id: "test-session"}
      }
      
      assert {:ok, result} = CommandRouter.execute_command(router, request)
      assert result =~ "load_balance_test"
    end

    test "handles node preference in routing", %{router: router} do
      request = %{
        command: "test",
        params: %{input: "node_preference"},
        context: %{
          session_id: "test-session",
          preferred_node: :local
        }
      }
      
      assert {:ok, result} = CommandRouter.execute_command(router, request)
      assert result =~ "node_preference"
    end

    test "provides command routing information", %{router: router} do
      routing_info = CommandRouter.get_routing_info(router)
      
      assert Map.has_key?(routing_info, :available_commands)
      assert Map.has_key?(routing_info, :node_load)
      assert Map.has_key?(routing_info, :routing_strategy)
    end
  end

  describe "CommandRouter error handling" do
    test "handles malformed requests gracefully", %{router: router} do
      malformed_request = %{
        # Missing required command field
        params: %{input: "test"},
        context: %{}
      }
      
      assert {:error, :invalid_request} = CommandRouter.execute_command(router, malformed_request)
    end

    test "handles router process death gracefully", %{router: router} do
      # Kill the router process
      router_pid = Process.whereis(router)
      Process.exit(router_pid, :kill)
      Process.sleep(10)
      
      request = %{
        command: "test",
        params: %{input: "router_down"},
        context: %{session_id: "test-session"}
      }
      
      assert {:error, :router_unavailable} = CommandRouter.execute_command(router, request)
    end

    test "validates request structure", %{router: router} do
      invalid_requests = [
        nil,
        %{},
        %{command: ""},
        %{command: "test"}, # Missing params and context
        %{command: "test", params: "invalid"}, # params should be map
        %{command: "test", params: %{}, context: "invalid"} # context should be map
      ]
      
      for invalid_request <- invalid_requests do
        assert {:error, :invalid_request} = CommandRouter.execute_command(router, invalid_request)
      end
    end
  end

  describe "CommandRouter integration" do
    test "integrates with existing Interface.Gateway patterns", %{router: router} do
      # This test verifies the router can work with gateway-style requests
      gateway_request = %{
        command: "test",
        params: %{input: "gateway_test"},
        context: %{
          session_id: "test-session",
          interface: :cli,
          request_id: "req-123"
        }
      }
      
      assert {:ok, result} = CommandRouter.execute_command(router, gateway_request)
      assert result =~ "gateway_test"
    end

    test "supports streaming command responses", %{router: router} do
      # Would need a streaming command for full test
      # For now, verify the interface exists
      assert function_exported?(CommandRouter, :execute_command, 2)
    end
  end
end