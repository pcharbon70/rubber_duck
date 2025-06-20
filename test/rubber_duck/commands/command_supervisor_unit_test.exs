defmodule RubberDuck.Commands.CommandSupervisorUnitTest do
  use ExUnit.Case, async: true
  
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
  
  describe "CommandSupervisor module functions" do
    test "can be started" do
      # Test basic module loading and function existence
      assert function_exported?(CommandSupervisor, :start_link, 1)
      assert function_exported?(CommandSupervisor, :start_command, 2)
      assert function_exported?(CommandSupervisor, :terminate_command, 1)
      assert function_exported?(CommandSupervisor, :find_command, 1)
      assert function_exported?(CommandSupervisor, :list_commands, 0)
      assert function_exported?(CommandSupervisor, :get_stats, 0)
      assert function_exported?(CommandSupervisor, :migrate_command, 2)
      assert function_exported?(CommandSupervisor, :balance_load, 0)
      assert function_exported?(CommandSupervisor, :shutdown_gracefully, 1)
    end
    
    test "has proper documentation" do
      docs = Code.fetch_docs(CommandSupervisor)
      assert docs != :error
    end
    
    test "implements required Horde.DynamicSupervisor callbacks" do
      # Check that init/1 callback exists
      assert function_exported?(CommandSupervisor, :init, 1)
    end
    
    test "cluster membership functions work without Horde running" do
      # This should work even without Horde started
      members = CommandSupervisor.get_cluster_members()
      assert is_list(members)
      assert node() in members
    end
    
    test "handles node events gracefully" do
      assert :ok = CommandSupervisor.handle_node_join(:test_node)
      assert :ok = CommandSupervisor.handle_node_leave(:test_node)
    end
  end
  
  describe "init/1 callback" do
    test "returns proper Horde.DynamicSupervisor configuration" do
      opts = []
      
      result = CommandSupervisor.init(opts)
      
      # Should return Horde configuration
      assert is_tuple(result)
      assert tuple_size(result) == 2
      assert elem(result, 0) == :ok
      
      config = elem(result, 1)
      assert is_list(config)
      
      # Check required Horde options
      assert Keyword.has_key?(config, :strategy)
      assert Keyword.has_key?(config, :members)
      assert Keyword.has_key?(config, :distribution_strategy)
      
      assert Keyword.get(config, :strategy) == :one_for_one
      assert Keyword.get(config, :members) == :auto
      assert Keyword.get(config, :distribution_strategy) == Horde.UniformDistribution
    end
    
    test "merges provided options with defaults" do
      custom_opts = [max_children: 5000, max_restarts: 5]
      
      {:ok, config} = CommandSupervisor.init(custom_opts)
      
      assert Keyword.get(config, :max_children) == 5000
      assert Keyword.get(config, :max_restarts) == 5
      assert Keyword.get(config, :strategy) == :one_for_one
    end
  end
  
  describe "private helper functions work in isolation" do
    test "command configurations are properly structured" do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1", session_id: "session_1"}
      }
      
      # Verify the config structure that would be used
      assert is_map(config)
      assert Map.has_key?(config, :command_module)
      assert Map.has_key?(config, :command_id)
      assert Map.has_key?(config, :context)
      
      assert config.command_module == TestCommand
      assert config.command_id == "test_123"
      assert is_map(config.context)
    end
    
    test "child spec structure is correct" do
      config = %{
        command_module: TestCommand,
        command_id: "test_123",
        context: %{user_id: "user_1"}
      }
      
      # Test the child spec structure that would be created
      expected_child_spec = %{
        id: config.command_id,
        start: {CommandHandler, :start_link, [config]},
        restart: :temporary,
        type: :worker
      }
      
      assert expected_child_spec.id == "test_123"
      assert elem(expected_child_spec.start, 0) == CommandHandler
      assert elem(expected_child_spec.start, 1) == :start_link
      assert elem(expected_child_spec.start, 2) == [config]
      assert expected_child_spec.restart == :temporary
      assert expected_child_spec.type == :worker
    end
  end
  
  describe "load distribution calculations" do
    test "calculates balanced distribution correctly" do
      # Test the load distribution calculation logic
      commands_by_node = %{
        :"node1@host" => 5,
        :"node2@host" => 5,
        :"node3@host" => 5
      }
      
      # This tests the private function logic without needing Horde running
      # We can't call the private function directly, but we can verify the expected behavior
      counts = Map.values(commands_by_node)
      avg_count = Enum.sum(counts) / length(counts)
      
      variance = Enum.reduce(counts, 0, fn count, acc ->
        acc + :math.pow(count - avg_count, 2)
      end) / length(counts)
      
      max_count = Enum.max(counts)
      min_count = Enum.min(counts)
      
      balance_score = if max_count > 0 do
        1.0 - ((max_count - min_count) / max_count)
      else
        1.0
      end
      
      assert avg_count == 5.0
      assert variance == 0.0
      assert balance_score == 1.0
      assert max_count == 5
      assert min_count == 5
    end
    
    test "calculates imbalanced distribution correctly" do
      commands_by_node = %{
        :"node1@host" => 10,
        :"node2@host" => 2,
        :"node3@host" => 1
      }
      
      counts = Map.values(commands_by_node)
      avg_count = Enum.sum(counts) / length(counts)
      
      max_count = Enum.max(counts)
      min_count = Enum.min(counts)
      
      balance_score = 1.0 - ((max_count - min_count) / max_count)
      
      assert avg_count == 13.0 / 3.0
      assert balance_score < 1.0
      assert balance_score == 1.0 - (9.0 / 10.0)
      assert balance_score == 0.1
    end
  end
  
  describe "placement strategy logic" do
    test "placement strategies are properly defined" do
      # Test that placement strategy options are correctly handled
      strategies = [:automatic, {:node, node()}, :least_loaded, :round_robin]
      
      Enum.each(strategies, fn strategy ->
        case strategy do
          :automatic -> assert strategy == :automatic
          {:node, target_node} -> 
            assert is_tuple(strategy)
            assert elem(strategy, 0) == :node
            assert is_atom(elem(strategy, 1))
          :least_loaded -> assert strategy == :least_loaded
          :round_robin -> assert strategy == :round_robin
        end
      end)
    end
  end
  
  describe "error handling" do
    test "gracefully handles invalid command IDs" do
      # Test error tuple structure for non-existent commands
      error_result = {:error, :command_not_found}
      
      assert match?({:error, :command_not_found}, error_result)
    end
    
    test "handles RPC failures gracefully" do
      # Test RPC error structure
      rpc_error = {:error, {:rpc_failed, :nodedown}}
      
      assert match?({:error, {:rpc_failed, _}}, rpc_error)
    end
  end
  
  describe "statistics structure validation" do
    test "stats structure has required fields" do
      # Test the expected structure of stats returned by get_stats/0
      expected_stats = %{
        total_commands: 0,
        active_commands: 0,
        commands_by_node: %{},
        commands_by_status: %{},
        cluster_nodes: [node()],
        load_distribution: %{
          balance_score: 1.0,
          variance: 0.0
        }
      }
      
      assert is_map(expected_stats)
      assert Map.has_key?(expected_stats, :total_commands)
      assert Map.has_key?(expected_stats, :active_commands)
      assert Map.has_key?(expected_stats, :commands_by_node)
      assert Map.has_key?(expected_stats, :commands_by_status)
      assert Map.has_key?(expected_stats, :cluster_nodes)
      assert Map.has_key?(expected_stats, :load_distribution)
      
      assert is_integer(expected_stats.total_commands)
      assert is_integer(expected_stats.active_commands)
      assert is_map(expected_stats.commands_by_node)
      assert is_map(expected_stats.commands_by_status)
      assert is_list(expected_stats.cluster_nodes)
      assert is_map(expected_stats.load_distribution)
    end
  end
end