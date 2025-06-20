defmodule RubberDuck.Commands.CommandSupervisorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Commands.CommandSupervisor
  alias RubberDuck.Commands.CommandHandler
  alias RubberDuck.Commands.CommandBehaviour
  alias RubberDuck.Commands.CommandMetadata
  
  # Mock command for testing
  defmodule TestCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "test_command",
        description: "A test command",
        category: :testing,
        parameters: [
          %CommandMetadata.Parameter{
            name: :message,
            type: :string,
            required: true,
            description: "Test message"
          }
        ]
      }
    end
    
    @impl true
    def validate(params) do
      if Map.has_key?(params, :message) and is_binary(params.message) do
        :ok
      else
        {:error, [{:message, "is required and must be a string"}]}
      end
    end
    
    @impl true
    def execute(%{message: message}, context) do
      Process.sleep(10)
      {:ok, "Processed: #{message} in context: #{inspect(context)}"}
    end
  end
  
  defmodule LongRunningCommand do
    @behaviour CommandBehaviour
    
    @impl true
    def metadata do
      %CommandMetadata{
        name: "long_running_command",
        description: "A long running command",
        category: :testing,
        async: true
      }
    end
    
    @impl true
    def validate(_params), do: :ok
    
    @impl true
    def execute(params, _context) do
      duration = Map.get(params, :duration, 1000)
      Process.sleep(duration)
      {:ok, "Long running completed after #{duration}ms"}
    end
  end
  
  setup_all do
    # Start the command supervisor for testing
    case CommandSupervisor.start_link(name: :test_command_supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    :ok
  end
  
  setup do
    # Clean up any existing commands before each test
    children = GenServer.call(:test_command_supervisor, :which_children)
    
    Enum.each(children, fn {_id, pid, _type, _modules} ->
      if is_pid(pid) do
        DynamicSupervisor.terminate_child(:test_command_supervisor, pid)
      end
    end)
    
    :ok
  end
  
  describe "start_command/2" do
    test "starts a command handler with automatic placement" do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1", session_id: "session_1"}
      }
      
      assert {:ok, pid} = CommandSupervisor.start_command(config)
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Verify it appears in the children list
      children = CommandSupervisor.list_commands()
      assert Enum.any?(children, fn {id, child_pid, _type, _modules} ->
        id == "test_123" and child_pid == pid
      end)
    end
    
    test "starts command with least loaded placement strategy" do
      config = %{
        command_module: TestCommand,
        command_id: "test_least_loaded",
        context: %{user_id: "user_1"}
      }
      
      assert {:ok, pid} = CommandSupervisor.start_command(config, placement_strategy: :least_loaded)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
    
    test "starts command with round robin placement strategy" do
      config = %{
        command_module: TestCommand,
        command_id: "test_round_robin",
        context: %{user_id: "user_1"}
      }
      
      assert {:ok, pid} = CommandSupervisor.start_command(config, placement_strategy: :round_robin)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
    
    test "starts command with specific node placement" do
      config = %{
        command_module: TestCommand,
        command_id: "test_node_specific",
        context: %{user_id: "user_1"}
      }
      
      current_node = node()
      assert {:ok, pid} = CommandSupervisor.start_command(config, placement_strategy: {:node, current_node})
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert node(pid) == current_node
    end
  end
  
  describe "terminate_command/1" do
    test "terminates command by PID" do
      config = %{
        command_module: TestCommand,
        command_id: "test_terminate_pid",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandSupervisor.start_command(config)
      assert Process.alive?(pid)
      
      assert :ok = CommandSupervisor.terminate_command(pid)
      
      # Wait a bit for termination
      Process.sleep(10)
      refute Process.alive?(pid)
    end
    
    test "terminates command by ID" do
      config = %{
        command_module: TestCommand,
        command_id: "test_terminate_id",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandSupervisor.start_command(config)
      assert Process.alive?(pid)
      
      assert :ok = CommandSupervisor.terminate_command("test_terminate_id")
      
      # Wait a bit for termination
      Process.sleep(10)
      refute Process.alive?(pid)
    end
    
    test "returns error for non-existent command ID" do
      assert {:error, :command_not_found} = CommandSupervisor.terminate_command("non_existent")
    end
  end
  
  describe "find_command/1" do
    test "finds existing command by ID" do
      config = %{
        command_module: TestCommand,
        command_id: "test_find",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandSupervisor.start_command(config)
      
      assert {:ok, found_pid} = CommandSupervisor.find_command("test_find")
      assert found_pid == pid
    end
    
    test "returns error for non-existent command" do
      assert {:error, :command_not_found} = CommandSupervisor.find_command("non_existent")
    end
  end
  
  describe "list_commands/0" do
    test "lists all active commands" do
      config1 = %{
        command_module: TestCommand,
        command_id: "test_list_1",
        context: %{user_id: "user_1"}
      }
      
      config2 = %{
        command_module: TestCommand,
        command_id: "test_list_2",
        context: %{user_id: "user_2"}
      }
      
      {:ok, _pid1} = CommandSupervisor.start_command(config1)
      {:ok, _pid2} = CommandSupervisor.start_command(config2)
      
      children = CommandSupervisor.list_commands()
      
      command_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)
      assert "test_list_1" in command_ids
      assert "test_list_2" in command_ids
    end
  end
  
  describe "get_stats/0" do
    test "returns comprehensive supervisor statistics" do
      config = %{
        command_module: TestCommand,
        command_id: "test_stats",
        context: %{user_id: "user_1"}
      }
      
      {:ok, _pid} = CommandSupervisor.start_command(config)
      
      stats = CommandSupervisor.get_stats()
      
      assert is_map(stats)
      assert is_integer(stats.total_commands)
      assert is_integer(stats.active_commands)
      assert is_map(stats.commands_by_node)
      assert is_map(stats.commands_by_status)
      assert is_list(stats.cluster_nodes)
      assert is_map(stats.load_distribution)
      
      assert stats.total_commands >= 1
      assert stats.active_commands >= 1
    end
    
    test "tracks commands by status" do
      config1 = %{
        command_module: TestCommand,
        command_id: "test_status_1",
        context: %{user_id: "user_1"}
      }
      
      config2 = %{
        command_module: LongRunningCommand,
        command_id: "test_status_2",
        context: %{user_id: "user_2"}
      }
      
      {:ok, _pid1} = CommandSupervisor.start_command(config1)
      {:ok, pid2} = CommandSupervisor.start_command(config2)
      
      # Start async execution on the long running command
      CommandHandler.execute_async(pid2, %{duration: 100})
      
      stats = CommandSupervisor.get_stats()
      
      assert is_map(stats.commands_by_status)
      assert Map.get(stats.commands_by_status, :ready, 0) >= 1
    end
  end
  
  describe "migrate_command/2" do
    test "migrates command with state preservation" do
      config = %{
        command_module: TestCommand,
        command_id: "test_migrate",
        context: %{user_id: "user_1"},
        metadata: %{priority: :high}
      }
      
      {:ok, original_pid} = CommandSupervisor.start_command(config)
      original_node = node(original_pid)
      
      # Migration to same node for testing (in real scenario would be different node)
      assert {:ok, new_pid} = CommandSupervisor.migrate_command("test_migrate", original_node)
      
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
      refute Process.alive?(original_pid)
      
      # Verify state was preserved
      state = CommandHandler.get_state(new_pid)
      assert state.command_id == "test_migrate"
      assert state.context.user_id == "user_1"
      assert state.metadata.priority == :high
    end
    
    test "returns error for non-existent command" do
      assert {:error, :command_not_found} = CommandSupervisor.migrate_command("non_existent", node())
    end
  end
  
  describe "balance_load/0" do
    test "reports balanced load when load is even" do
      # Start just one command - should be balanced on single node
      config = %{
        command_module: TestCommand,
        command_id: "test_balance",
        context: %{user_id: "user_1"}
      }
      
      {:ok, _pid} = CommandSupervisor.start_command(config)
      
      assert {:ok, :already_balanced} = CommandSupervisor.balance_load()
    end
    
    test "provides load balancing analysis" do
      # This is a simplified test since we're on a single node
      result = CommandSupervisor.balance_load()
      assert match?({:ok, _}, result)
    end
  end
  
  describe "shutdown_gracefully/1" do
    test "gracefully shuts down all commands" do
      configs = [
        %{
          command_module: TestCommand,
          command_id: "test_shutdown_1",
          context: %{user_id: "user_1"}
        },
        %{
          command_module: TestCommand,
          command_id: "test_shutdown_2",
          context: %{user_id: "user_2"}
        }
      ]
      
      pids = Enum.map(configs, fn config ->
        {:ok, pid} = CommandSupervisor.start_command(config)
        pid
      end)
      
      Enum.each(pids, &assert(Process.alive?(&1)))
      
      assert {:ok, result} = CommandSupervisor.shutdown_gracefully(5000)
      assert result.total == 2
      assert result.successful >= 0
      assert result.failed >= 0
      assert result.successful + result.failed == result.total
      
      # Wait for shutdown to complete
      Process.sleep(100)
      
      Enum.each(pids, &refute(Process.alive?(&1)))
    end
    
    test "handles shutdown timeout gracefully" do
      config = %{
        command_module: LongRunningCommand,
        command_id: "test_shutdown_timeout",
        context: %{user_id: "user_1"}
      }
      
      {:ok, pid} = CommandSupervisor.start_command(config)
      
      # Start a long running operation
      CommandHandler.execute_async(pid, %{duration: 10_000})
      
      # Shutdown with short timeout
      assert {:ok, result} = CommandSupervisor.shutdown_gracefully(100)
      assert result.total == 1
    end
  end
  
  describe "cluster event handling" do
    test "handles node join events" do
      assert :ok = CommandSupervisor.handle_node_join(:test_node)
    end
    
    test "handles node leave events" do
      assert :ok = CommandSupervisor.handle_node_leave(:test_node)
    end
  end
  
  describe "cluster membership" do
    test "gets cluster members" do
      members = CommandSupervisor.get_cluster_members()
      assert is_list(members)
      assert node() in members
    end
  end
  
  describe "load distribution calculation" do
    test "calculates load distribution with multiple commands" do
      configs = [
        %{
          command_module: TestCommand,
          command_id: "test_load_1",
          context: %{user_id: "user_1"}
        },
        %{
          command_module: TestCommand,
          command_id: "test_load_2",
          context: %{user_id: "user_2"}
        },
        %{
          command_module: TestCommand,
          command_id: "test_load_3",
          context: %{user_id: "user_3"}
        }
      ]
      
      Enum.each(configs, fn config ->
        {:ok, _pid} = CommandSupervisor.start_command(config)
      end)
      
      stats = CommandSupervisor.get_stats()
      load_dist = stats.load_distribution
      
      assert is_float(load_dist.balance_score)
      assert load_dist.balance_score >= 0.0 and load_dist.balance_score <= 1.0
      assert is_float(load_dist.variance)
      assert is_float(load_dist.avg_commands_per_node)
      assert is_integer(load_dist.max_commands_per_node)
      assert is_integer(load_dist.min_commands_per_node)
    end
  end
end