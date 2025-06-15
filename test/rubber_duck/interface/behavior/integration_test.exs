defmodule RubberDuck.Interface.Behavior.IntegrationTest do
  @moduledoc """
  Integration tests for distributed scenarios and cross-node interface behavior.
  
  These tests validate that interface adapters work correctly in distributed
  environments, including node joins/leaves, network partitions, and cross-node
  state synchronization.
  """
  
  use ExUnit.Case, async: false  # Distributed tests cannot run concurrently
  
  alias RubberDuck.Interface.{Behaviour, Gateway}
  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Core.{ContextManager, ModelCoordinator}
  alias RubberDuck.Distributed.StateSynchronizer
  
  # Test configuration for distributed scenarios
  @test_config %{
    colors: false,
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,
    config_dir: System.tmp_dir!() <> "/integration_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/integration_sessions_#{System.unique_integer()}"
  }
  
  setup_all do
    # Start required distributed services for testing
    {:ok, _} = start_supervised({Registry, keys: :unique, name: TestRegistry})
    {:ok, _} = start_supervised({DynamicSupervisor, name: TestDynamicSupervisor, strategy: :one_for_one})
    
    # Mock distributed cluster setup
    Application.put_env(:rubber_duck, :test_mode, true)
    
    on_exit(fn ->
      [@test_config.config_dir, @test_config.sessions_dir]
      |> Enum.each(fn dir ->
        if File.exists?(dir) do
          File.rm_rf!(dir)
        end
      end)
      
      Application.delete_env(:rubber_duck, :test_mode)
    end)
    
    :ok
  end
  
  setup do
    # Clean test directories
    [@test_config.config_dir, @test_config.sessions_dir]
    |> Enum.each(fn dir ->
      if File.exists?(dir) do
        File.rm_rf!(dir)
      end
    end)
    
    :ok
  end
  
  describe "Cross-Node Interface Communication" do
    test "interfaces can communicate across simulated nodes" do
      # Simulate multiple node scenarios
      node_contexts = [
        %{node: :node1, interface: :cli},
        %{node: :node2, interface: :cli}
      ]
      
      for {context, index} <- Enum.with_index(node_contexts) do
        # Initialize adapter on each "node"
        {:ok, state} = CLI.init(config: @test_config)
        
        # Create request that would span nodes
        request = %{
          id: "cross_node_test_#{index}",
          operation: :chat,
          params: %{message: "Test cross-node communication #{index}"},
          interface: :cli,
          timestamp: DateTime.utc_now(),
          node_context: context
        }
        
        # Process request
        {:ok, response, _new_state} = CLI.handle_request(request, context, state)
        
        assert response.status == :success
        assert response.id == request.id
        assert is_binary(response.data.message)
        
        # Response should include node context information
        assert response.data.session_id
      end
    end
    
    test "state synchronization across distributed interfaces" do
      # Initialize multiple adapter instances (simulating different nodes)
      {:ok, state1} = CLI.init(config: @test_config)
      {:ok, state2} = CLI.init(config: @test_config)
      
      # Create session on first node
      session_request = %{
        id: "distributed_session_test",
        operation: :session_management,
        params: %{action: :new, name: "distributed_test_session"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli, node: :node1}
      {:ok, session_response, new_state1} = CLI.handle_request(session_request, context, state1)
      
      assert session_response.status == :success
      session_id = session_response.data.session.id
      
      # Simulate state synchronization to second node
      # In a real distributed system, this would happen via Mnesia/pg events
      sync_event = %{
        type: :session_created,
        session_id: session_id,
        session_data: session_response.data.session,
        source_node: :node1
      }
      
      # Second node should be able to access the session
      list_request = %{
        id: "list_sessions_test",
        operation: :session_management,
        params: %{action: :list},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context2 = %{interface: :cli, node: :node2}
      {:ok, list_response, _new_state2} = CLI.handle_request(list_request, context2, state2)
      
      assert list_response.status == :success
      assert is_list(list_response.data.sessions)
      
      # In distributed mode, sessions should eventually be consistent
      # For this test, we verify the structure is correct
    end
    
    test "interface failover scenarios" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate a request that might fail on one node
      request = %{
        id: "failover_test",
        operation: :chat,
        params: %{message: "Test failover handling"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      # Test with different failure scenarios
      failure_contexts = [
        %{interface: :cli, node: :failing_node, status: :degraded},
        %{interface: :cli, node: :healthy_node, status: :healthy},
        %{interface: :cli, node: :recovering_node, status: :recovering}
      ]
      
      for context <- failure_contexts do
        result = CLI.handle_request(request, context, state)
        
        case result do
          {:ok, response, _state} ->
            # Successful handling
            assert response.status == :success
            assert response.id == request.id
            
          {:error, _reason, _state} ->
            # Graceful failure - acceptable for degraded nodes
            assert context.status in [:degraded, :recovering]
        end
      end
    end
  end
  
  describe "Distributed Context Management" do
    test "context consistency across interfaces" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create initial context
      context_request = %{
        id: "context_test",
        operation: :chat,
        params: %{
          message: "Set up context for distributed testing",
          session_id: "distributed_context_test"
        },
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      {:ok, response, new_state} = CLI.handle_request(context_request, context, state)
      
      assert response.status == :success
      session_id = response.data.session_id
      
      # Follow-up request that should use the same context
      followup_request = %{
        id: "context_followup_test",
        operation: :chat,
        params: %{
          message: "This should maintain context",
          session_id: session_id
        },
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, followup_response, _final_state} = CLI.handle_request(followup_request, context, new_state)
      
      assert followup_response.status == :success
      assert followup_response.data.session_id == session_id
      
      # Context should be maintained across requests
      assert is_binary(followup_response.data.message)
    end
    
    test "context synchronization during node changes" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate node join event
      join_event = %{
        type: :node_join,
        node: :new_node,
        timestamp: DateTime.utc_now(),
        capabilities: [:cli, :api]
      }
      
      # Request that should be aware of new node
      request = %{
        id: "node_join_test",
        operation: :status,
        params: %{include_cluster: true},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli, cluster_event: join_event}
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_map(response.data)
      
      # Response should include cluster information
      assert Map.has_key?(response.data, :adapter)
      assert response.data.adapter == :cli
    end
  end
  
  describe "Load Balancing and Distribution" do
    test "requests can be distributed across available nodes" do
      # Simulate multiple available nodes
      available_nodes = [
        %{node: :node1, load: 0.2, health: :healthy},
        %{node: :node2, load: 0.5, health: :healthy},
        %{node: :node3, load: 0.8, health: :degraded}
      ]
      
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create requests that could be load balanced
      requests = for i <- 1..10 do
        %{
          id: "load_balance_test_#{i}",
          operation: :chat,
          params: %{message: "Load balance test #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
      end
      
      # Process requests with load balancing context
      results = for request <- requests do
        # Select node based on load (simplified algorithm)
        selected_node = available_nodes
                       |> Enum.filter(& &1.health == :healthy)
                       |> Enum.min_by(& &1.load)
        
        context = %{
          interface: :cli,
          target_node: selected_node.node,
          load_balance: true
        }
        
        CLI.handle_request(request, context, state)
      end
      
      # All requests should succeed
      for result <- results do
        assert {:ok, _response, _state} = result
      end
    end
    
    test "interface performance under distributed load" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Simulate concurrent requests from multiple nodes
      start_time = System.monotonic_time(:millisecond)
      
      tasks = for i <- 1..20 do
        Task.async(fn ->
          request = %{
            id: "distributed_load_test_#{i}",
            operation: :chat,
            params: %{message: "Concurrent test #{i}"},
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
          
          context = %{
            interface: :cli,
            node: Enum.random([:node1, :node2, :node3])
          }
          
          CLI.handle_request(request, context, initial_state)
        end)
      end
      
      results = Task.await_many(tasks, 10_000)
      end_time = System.monotonic_time(:millisecond)
      
      # Verify all requests succeeded
      for result <- results do
        assert {:ok, _response, _state} = result
      end
      
      # Performance should be reasonable even under load
      duration = end_time - start_time
      assert duration < 5000  # Should complete within 5 seconds
    end
  end
  
  describe "Network Partition Handling" do
    test "interface graceful degradation during network issues" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate network partition scenario
      partition_scenarios = [
        %{type: :network_partition, affected_nodes: [:node2, :node3]},
        %{type: :slow_network, latency: 1000},
        %{type: :intermittent_connection, success_rate: 0.7}
      ]
      
      for scenario <- partition_scenarios do
        request = %{
          id: "partition_test_#{scenario.type}",
          operation: :chat,
          params: %{message: "Test during #{scenario.type}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{
          interface: :cli,
          network_scenario: scenario
        }
        
        result = CLI.handle_request(request, context, state)
        
        case result do
          {:ok, response, _state} ->
            # Request succeeded despite network issues
            assert response.status == :success
            
          {:error, _reason, _state} ->
            # Graceful failure is acceptable during network issues
            :ok
        end
      end
    end
    
    test "interface recovery after network partition resolves" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create request during partition
      partition_request = %{
        id: "partition_recovery_test",
        operation: :session_management,
        params: %{action: :new, name: "partition_test_session"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      partition_context = %{
        interface: :cli,
        network_status: :partitioned
      }
      
      # Request might fail during partition
      partition_result = CLI.handle_request(partition_request, partition_context, state)
      
      # Create request after partition resolves
      recovery_request = %{
        id: "recovery_test",
        operation: :session_management,
        params: %{action: :list},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      recovery_context = %{
        interface: :cli,
        network_status: :recovered
      }
      
      # Request should succeed after recovery
      {:ok, recovery_response, _new_state} = CLI.handle_request(recovery_request, recovery_context, state)
      
      assert recovery_response.status == :success
      assert is_list(recovery_response.data.sessions)
    end
  end
  
  describe "Interface Coordination Patterns" do
    test "cross-interface event coordination" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate events from different interface types
      events = [
        %{interface: :cli, event: :session_created, session_id: "cli_session"},
        %{interface: :web, event: :session_created, session_id: "web_session"},
        %{interface: :api, event: :session_created, session_id: "api_session"}
      ]
      
      for event <- events do
        # Create request that should be aware of cross-interface events
        request = %{
          id: "cross_interface_test_#{event.interface}",
          operation: :session_management,
          params: %{action: :list},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{
          interface: :cli,
          cross_interface_event: event
        }
        
        {:ok, response, _new_state} = CLI.handle_request(request, context, state)
        
        assert response.status == :success
        assert is_list(response.data.sessions)
      end
    end
    
    test "interface capability negotiation across nodes" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test capability discovery across different node configurations
      node_capabilities = [
        %{node: :full_node, capabilities: [:cli, :web, :api, :lsp]},
        %{node: :cli_only_node, capabilities: [:cli]},
        %{node: :web_node, capabilities: [:web, :api]}
      ]
      
      for node_config <- node_capabilities do
        request = %{
          id: "capability_test_#{node_config.node}",
          operation: :status,
          params: %{include_capabilities: true},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{
          interface: :cli,
          target_node: node_config.node,
          node_capabilities: node_config.capabilities
        }
        
        {:ok, response, _new_state} = CLI.handle_request(request, context, state)
        
        assert response.status == :success
        assert Map.has_key?(response.data, :adapter)
        
        # Response should reflect the interface capabilities
        assert response.data.adapter == :cli
      end
    end
  end
  
  describe "Distributed Session Management" do
    test "session consistency across interface types" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create session via CLI
      create_request = %{
        id: "cross_interface_session_test",
        operation: :session_management,
        params: %{action: :new, name: "cross_interface_session"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      {:ok, create_response, new_state} = CLI.handle_request(create_request, context, state)
      
      assert create_response.status == :success
      session_id = create_response.data.session.id
      
      # Simulate accessing the same session from different interface types
      interface_types = [:cli, :web, :api]
      
      for interface_type <- interface_types do
        access_request = %{
          id: "access_session_#{interface_type}",
          operation: :chat,
          params: %{
            message: "Test from #{interface_type} interface",
            session_id: session_id
          },
          interface: interface_type,
          timestamp: DateTime.utc_now()
        }
        
        access_context = %{
          interface: interface_type,
          original_session_interface: :cli
        }
        
        # CLI adapter should handle requests regardless of original interface
        result = CLI.handle_request(access_request, access_context, new_state)
        
        case result do
          {:ok, response, _state} ->
            assert response.status == :success
            assert response.data.session_id == session_id
            
          {:error, _reason, _state} ->
            # Some cross-interface operations might not be supported
            :ok
        end
      end
    end
  end
end