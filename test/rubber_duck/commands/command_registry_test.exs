defmodule RubberDuck.Commands.CommandRegistryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Commands.{CommandRegistry, CommandBehaviour, CommandMetadata}
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
    def execute(params, _context) do
      {:ok, "Test result: #{params[:input]}"}
    end
  end

  defmodule AnotherTestCommand do
    @behaviour CommandBehaviour

    @impl true
    def metadata do
      %CommandMetadata{
        name: "another",
        description: "Another test command",
        category: :testing,
        async: true
      }
    end

    @impl true
    def validate(_params), do: :ok

    @impl true
    def execute(_params, _context) do
      {:ok, "Another test result"}
    end
  end

  defmodule InvalidCommand do
    # Missing behaviour implementation
  end

  setup do
    # Start a fresh registry for each test
    registry_name = :"test_registry_#{:rand.uniform(1000000)}"
    {:ok, _pid} = CommandRegistry.start_link(name: registry_name)
    
    %{registry: registry_name}
  end

  describe "CommandRegistry" do
    test "starts successfully", %{registry: registry} do
      assert Process.alive?(Process.whereis(registry))
    end

    test "registers a valid command module", %{registry: registry} do
      assert :ok == CommandRegistry.register_command(registry, TestCommand)
      
      # Verify command is registered
      commands = CommandRegistry.list_commands(registry)
      assert length(commands) == 1
      assert Enum.any?(commands, &(&1.name == "test"))
    end

    test "registers multiple commands", %{registry: registry} do
      assert :ok == CommandRegistry.register_command(registry, TestCommand)
      assert :ok == CommandRegistry.register_command(registry, AnotherTestCommand)
      
      commands = CommandRegistry.list_commands(registry)
      assert length(commands) == 2
      
      command_names = Enum.map(commands, & &1.name)
      assert "test" in command_names
      assert "another" in command_names
    end

    test "rejects invalid command module", %{registry: registry} do
      assert {:error, reason} = CommandRegistry.register_command(registry, InvalidCommand)
      assert reason =~ "must implement"
    end

    test "prevents duplicate command registration", %{registry: registry} do
      assert :ok == CommandRegistry.register_command(registry, TestCommand)
      assert {:error, reason} = CommandRegistry.register_command(registry, TestCommand)
      assert reason =~ "already registered"
    end

    test "finds command by name", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      assert {:ok, metadata} = CommandRegistry.find_command(registry, "test")
      assert metadata.name == "test"
      assert metadata.description == "A test command"
      
      assert {:error, :not_found} = CommandRegistry.find_command(registry, "nonexistent")
    end

    test "finds command module by name", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      assert {:ok, TestCommand} = CommandRegistry.find_command_module(registry, "test")
      assert {:error, :not_found} = CommandRegistry.find_command_module(registry, "nonexistent")
    end

    test "unregisters command", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      assert {:ok, _metadata} = CommandRegistry.find_command(registry, "test")
      assert :ok == CommandRegistry.unregister_command(registry, "test")
      assert {:error, :not_found} = CommandRegistry.find_command(registry, "test")
    end

    test "lists commands by category", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      CommandRegistry.register_command(registry, AnotherTestCommand)
      
      testing_commands = CommandRegistry.list_commands_by_category(registry, :testing)
      assert length(testing_commands) == 2
      
      general_commands = CommandRegistry.list_commands_by_category(registry, :general)
      assert length(general_commands) == 0
    end

    test "finds commands by alias", %{registry: registry} do
      # Create command with aliases
      defmodule AliasedCommand do
        @behaviour CommandBehaviour

        @impl true
        def metadata do
          %CommandMetadata{
            name: "aliased",
            description: "Command with aliases",
            category: :testing,
            aliases: ["a", "alias"]
          }
        end

        @impl true
        def validate(_), do: :ok

        @impl true
        def execute(_, _), do: {:ok, "aliased result"}
      end
      
      CommandRegistry.register_command(registry, AliasedCommand)
      
      # Should find by main name
      assert {:ok, metadata} = CommandRegistry.find_command(registry, "aliased")
      assert metadata.name == "aliased"
      
      # Should find by aliases
      assert {:ok, metadata} = CommandRegistry.find_command(registry, "a")
      assert metadata.name == "aliased"
      
      assert {:ok, metadata} = CommandRegistry.find_command(registry, "alias")
      assert metadata.name == "aliased"
    end

    test "gets command count", %{registry: registry} do
      assert CommandRegistry.command_count(registry) == 0
      
      CommandRegistry.register_command(registry, TestCommand)
      assert CommandRegistry.command_count(registry) == 1
      
      CommandRegistry.register_command(registry, AnotherTestCommand)
      assert CommandRegistry.command_count(registry) == 2
    end

    test "checks if command exists", %{registry: registry} do
      assert CommandRegistry.command_exists?(registry, "test") == false
      
      CommandRegistry.register_command(registry, TestCommand)
      assert CommandRegistry.command_exists?(registry, "test") == true
    end

    test "validates command module during registration", %{registry: registry} do
      defmodule BadMetadataCommand do
        @behaviour CommandBehaviour

        @impl true
        def metadata do
          %CommandMetadata{
            name: "",  # Invalid empty name
            description: "Bad command",
            category: :testing
          }
        end

        @impl true
        def validate(_), do: :ok

        @impl true
        def execute(_, _), do: {:ok, "result"}
      end
      
      assert {:error, reason} = CommandRegistry.register_command(registry, BadMetadataCommand)
      assert reason =~ "invalid metadata"
    end

    test "handles registry node changes gracefully", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      # Simulate registry being available after node change
      commands = CommandRegistry.list_commands(registry)
      assert length(commands) == 1
    end

    test "provides command statistics", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      CommandRegistry.register_command(registry, AnotherTestCommand)
      
      stats = CommandRegistry.get_stats(registry)
      assert stats.total_commands == 2
      assert stats.categories == [:testing]
      assert stats.async_commands == 1
      assert stats.sync_commands == 1
    end
  end

  describe "CommandRegistry error handling" do
    test "handles registry process death gracefully", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      # Kill the registry process
      pid = Process.whereis(registry)
      Process.exit(pid, :kill)
      
      # Wait for process to actually die
      Process.sleep(10)
      
      # Should handle gracefully when registry is down
      assert {:error, :registry_unavailable} = CommandRegistry.list_commands(registry)
    end

    test "validates command name conflicts", %{registry: registry} do
      CommandRegistry.register_command(registry, TestCommand)
      
      # Try to register another command with same name
      defmodule ConflictCommand do
        @behaviour CommandBehaviour

        @impl true
        def metadata do
          %CommandMetadata{
            name: "test",  # Same name as TestCommand
            description: "Conflicting command",
            category: :testing
          }
        end

        @impl true
        def validate(_), do: :ok

        @impl true
        def execute(_, _), do: {:ok, "conflict result"}
      end
      
      assert {:error, reason} = CommandRegistry.register_command(registry, ConflictCommand)
      assert reason =~ "already registered"
    end
  end

  describe "CommandRegistry distributed features" do
    @tag :integration
    test "supports distributed command registration across nodes", %{registry: registry} do
      # This test would require multiple nodes to test properly
      # For now, just verify the interface exists
      assert function_exported?(CommandRegistry, :register_command, 2)
      assert function_exported?(CommandRegistry, :list_commands, 1)
    end
  end
end