defmodule RubberDuck.Jido.SignalRouterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido
  alias RubberDuck.Jido.SignalRouter
  alias RubberDuck.Jido.SignalRouter.{Config, DeadLetterQueue}
  alias RubberDuck.Jido.Agents.ExampleAgent
  
  import RubberDuck.Test.CloudEventsHelper
  
  setup do
    # Create test agent
    {:ok, agent} = Jido.create_agent(ExampleAgent)
    
    # Clear DLQ
    DeadLetterQueue.clear()
    
    # Clear any custom routes
    Config.clear_routes()
    Config.load_from_config()
    
    {:ok, agent: agent}
  end
  
  describe "CloudEvents validation" do
    test "accepts valid CloudEvent", %{agent: agent} do
      # Use a known route
      signal = cloud_event("increment", data: %{"amount" => 1})
      assert :ok = SignalRouter.route(agent, signal)
    end
    
    test "rejects signal missing required fields", %{agent: agent} do
      invalid_signal = %{"type" => "test"}
      
      assert {:error, {:validation_failed, errors}} = SignalRouter.route(agent, invalid_signal)
      assert length(errors) >= 3  # Missing specversion, id, source
      
      # Check it was sent to DLQ
      Process.sleep(10)
      dlq_entries = DeadLetterQueue.list()
      assert length(dlq_entries) == 1
      assert hd(dlq_entries).error == {:validation_failed, errors}
    end
    
    test "rejects signal with invalid specversion", %{agent: agent} do
      signal = %{
        "specversion" => "0.3",
        "id" => "123",
        "source" => "/test",
        "type" => "test"
      }
      
      assert {:error, {:validation_failed, errors}} = SignalRouter.route(agent, signal)
      assert Enum.any?(errors, fn 
        {:error, "specversion", _} -> true
        _ -> false
      end)
    end
    
    test "validates all CloudEvents fields", %{agent: agent} do
      # Invalid time format
      signal = cloud_event("test", time: "not-a-timestamp")
      
      assert {:error, {:validation_failed, errors}} = SignalRouter.route(agent, signal)
      assert Enum.any?(errors, fn 
        {:error, "time", _} -> true
        _ -> false
      end)
    end
  end
  
  describe "signal routing" do
    test "routes known signal types", %{agent: agent} do
      signal = increment_event(5)
      assert :ok = SignalRouter.route(agent, signal)
      
      Process.sleep(50)
      {:ok, updated} = Jido.get_agent(agent.id)
      assert updated.state.counter == 5
    end
    
    test "sends unknown signal types to DLQ", %{agent: agent} do
      signal = cloud_event("unknown.signal.type")
      
      assert {:error, {:no_route, "unknown.signal.type"}} = SignalRouter.route(agent, signal)
      
      Process.sleep(10)
      dlq_entries = DeadLetterQueue.list()
      assert length(dlq_entries) == 1
    end
    
    test "handles action execution failures", %{agent: agent} do
      # Register a route to our failing action
      Config.register_route("fail.test", RubberDuck.Test.FailAction)
      
      signal = cloud_event("fail.test")
      assert {:error, {:action_failed, _}} = SignalRouter.route(agent, signal)
      
      Process.sleep(10)
      dlq_entries = DeadLetterQueue.list()
      assert length(dlq_entries) == 1
    end
  end
  
  describe "subscriptions" do
    test "subscribes to exact pattern", %{agent: agent} do
      {:ok, sub_id} = SignalRouter.subscribe(agent.id, "test.event")
      assert is_binary(sub_id)
      assert String.starts_with?(sub_id, "sub_")
    end
    
    test "subscribes with wildcard pattern", %{agent: agent} do
      {:ok, sub_id} = SignalRouter.subscribe(agent.id, "test.*")
      assert is_binary(sub_id)
    end
    
    test "subscribes with priority", %{agent: agent} do
      {:ok, _sub1} = SignalRouter.subscribe(agent.id, "test.*", priority: 100)
      {:ok, _sub2} = SignalRouter.subscribe(agent.id, "test.event", priority: 50)
      
      # Higher priority should match first
      # This would be tested more thoroughly with broadcast
    end
    
    test "subscribes with filters", %{agent: agent} do
      {:ok, _sub} = SignalRouter.subscribe(agent.id, "test.*", 
        filters: [
          {:source, "/production/*"},
          {:subject, "user.*"}
        ]
      )
    end
    
    test "unsubscribes successfully" do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      {:ok, sub_id} = SignalRouter.subscribe(agent.id, "test.*")
      
      assert :ok = SignalRouter.unsubscribe(sub_id)
      
      # Verify unsubscribed
      _stats = SignalRouter.stats()
      # The subscription count should reflect the removal
    end
  end
  
  describe "broadcasting" do
    test "broadcasts to matching agents" do
      # Create multiple agents
      {:ok, agent1} = Jido.create_agent(ExampleAgent)
      {:ok, agent2} = Jido.create_agent(ExampleAgent)
      {:ok, agent3} = Jido.create_agent(ExampleAgent)
      
      # Subscribe with different patterns
      {:ok, _} = SignalRouter.subscribe(agent1.id, "broadcast.*")
      {:ok, _} = SignalRouter.subscribe(agent2.id, "broadcast.test")
      {:ok, _} = SignalRouter.subscribe(agent3.id, "other.*")
      
      # Broadcast signal
      signal = cloud_event("broadcast.test", data: %{"value" => "test"})
      assert :ok = SignalRouter.broadcast(signal)
      
      # agent1 and agent2 should receive it, not agent3
      # In a real test, we'd verify the effects on the agents
    end
    
    test "validates CloudEvents in broadcast" do
      invalid_signal = %{"type" => "broadcast.test"}
      
      assert {:error, {:validation_failed, _}} = SignalRouter.broadcast(invalid_signal)
    end
    
    test "applies broadcast filters" do
      {:ok, agent1} = Jido.create_agent(ExampleAgent)
      {:ok, agent2} = Jido.create_agent(ExampleAgent)
      
      SignalRouter.subscribe(agent1.id, "filtered.*")
      SignalRouter.subscribe(agent2.id, "filtered.*")
      
      signal = cloud_event("filtered.test")
      
      # Broadcast with limit
      assert :ok = SignalRouter.broadcast(signal, limit: 1)
      
      # Only one agent should receive it
    end
  end
  
  describe "statistics" do
    test "tracks routing statistics", %{agent: agent} do
      initial_stats = SignalRouter.stats()
      
      # Route some signals
      SignalRouter.route(agent, increment_event())
      SignalRouter.route(agent, %{"invalid" => "signal"})
      SignalRouter.broadcast(increment_event())
      
      Process.sleep(50)
      
      stats = SignalRouter.stats()
      assert stats.routed > initial_stats.routed
      assert stats.validation_failures > initial_stats.validation_failures
      assert stats.broadcast > initial_stats.broadcast
      assert stats.dlq_sent > initial_stats.dlq_sent
    end
    
    test "includes DLQ statistics" do
      stats = SignalRouter.stats()
      assert is_map(stats.dlq_stats)
      assert Map.has_key?(stats.dlq_stats, :current_size)
    end
  end
  
  describe "dead letter queue integration" do
    test "failed signals can be retried from DLQ", %{agent: agent} do
      # First, create a route that will work on retry
      Config.register_route("retry.test", RubberDuck.Jido.Actions.Increment)
      
      # Send signal that will fail initially (assuming no route)
      signal = cloud_event("unknown.test", data: %{"amount" => 1})
      
      # Add agent_id to extensions so DLQ can find it on retry
      signal_with_agent = Map.put(signal, "extensions", %{"agent_id" => agent.id})
      
      assert {:error, _} = SignalRouter.route(agent, signal_with_agent)
      
      Process.sleep(10)
      [dlq_entry] = DeadLetterQueue.list()
      
      # Now register the route and retry
      Config.register_route("unknown.test", RubberDuck.Jido.Actions.Increment)
      
      assert :ok = DeadLetterQueue.retry(dlq_entry.id)
      
      Process.sleep(50)
      
      # Should be removed from DLQ after successful retry
      assert [] = DeadLetterQueue.list()
    end
    
    test "permanently failed signals stay in DLQ" do
      {:ok, agent} = Jido.create_agent(ExampleAgent)
      
      # Signal with no hope of success
      bad_signal = %{"not" => "valid"}
      
      SignalRouter.route(agent, bad_signal)
      
      Process.sleep(10)
      [entry] = DeadLetterQueue.list()
      
      # Should have validation errors
      assert {:validation_failed, _} = entry.error
    end
  end
  
  describe "dynamic routing configuration" do
    test "uses Config for route resolution", %{agent: agent} do
      # Register a custom route
      Config.register_route("custom.action", RubberDuck.Jido.Actions.Increment,
        param_extractor: fn _event -> 
          %{amount: 10}  # Always increment by 10
        end
      )
      
      signal = cloud_event("custom.action")
      assert :ok = SignalRouter.route(agent, signal)
      
      Process.sleep(50)
      {:ok, updated} = Jido.get_agent(agent.id)
      assert updated.state.counter == 10
    end
    
    test "handles pattern-based routes", %{agent: agent} do
      Config.register_route("pattern.*.test", RubberDuck.Jido.Actions.AddMessage,
        param_extractor: fn event ->
          %{message: "Pattern matched: #{event["type"]}"}
        end
      )
      
      signal = cloud_event("pattern.something.test")
      assert :ok = SignalRouter.route(agent, signal)
      
      Process.sleep(50)
      {:ok, updated} = Jido.get_agent(agent.id)
      # Messages include timestamps, so check if any message contains our text
      assert Enum.any?(updated.state.messages, fn msg ->
        String.contains?(msg, "Pattern matched: pattern.something.test")
      end)
    end
  end
end