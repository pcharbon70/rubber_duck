defmodule RubberDuck.Agents.BaseAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.SignalDispatcher
  
  # Test agent implementation
  defmodule TestAgent do
    use RubberDuck.Agents.BaseAgent,
      name: "test_agent",
      description: "Agent for testing",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :string}, default: []],
        pre_init_called: [type: :boolean, default: false],
        post_init_called: [type: :boolean, default: false]
      ]
    
    @impl true
    def handle_signal(agent, %{"type" => "increment"} = signal) do
      amount = signal["amount"] || 1
      updated_state = Map.update(agent.state, :counter, amount, &(&1 + amount))
      {:ok, %{agent | state: updated_state}}
    end
    
    @impl true
    def handle_signal(agent, %{"type" => "add_message"} = signal) do
      message = signal["message"] || ""
      updated_state = Map.update(agent.state, :messages, [message], &(&1 ++ [message]))
      {:ok, %{agent | state: updated_state}}
    end
    
    @impl true
    def handle_signal(agent, signal) do
      # Call parent for unknown signals
      super(agent, signal)
    end
    
    @impl true
    def pre_init(state) do
      {:ok, Map.put(state, :pre_init_called, true)}
    end
    
    @impl true
    def post_init(agent) do
      updated_state = Map.put(agent.state, :post_init_called, true)
      {:ok, %{agent | state: updated_state}}
    end
    
    @impl true
    def health_check(agent) do
      if agent.state.counter < 100 do
        {:healthy, %{counter: agent.state.counter}}
      else
        {:unhealthy, %{counter: agent.state.counter, reason: "Counter too high"}}
      end
    end
  end
  
  setup do
    # Ensure SignalDispatcher is started
    case Process.whereis(SignalDispatcher) do
      nil -> {:ok, _} = SignalDispatcher.start_link([])
      _ -> :ok
    end
    
    :ok
  end
  
  describe "agent creation" do
    test "creates agent with default schema values" do
      agent = %{
        id: "test-1",
        state: %{
          counter: 0,
          messages: [],
          pre_init_called: false,
          post_init_called: false
        }
      }
      
      assert agent.state.counter == 0
      assert agent.state.messages == []
    end
  end
  
  describe "signal handling" do
    test "handles increment signal" do
      agent = %{
        id: "test-2",
        state: %{counter: 5, messages: []}
      }
      
      {:ok, updated_agent} = TestAgent.handle_signal(agent, %{"type" => "increment"})
      assert updated_agent.state.counter == 6
      
      {:ok, updated_agent} = TestAgent.handle_signal(updated_agent, %{
        "type" => "increment",
        "amount" => 10
      })
      assert updated_agent.state.counter == 16
    end
    
    test "handles add_message signal" do
      agent = %{
        id: "test-3",
        state: %{counter: 0, messages: ["hello"]}
      }
      
      {:ok, updated_agent} = TestAgent.handle_signal(agent, %{
        "type" => "add_message",
        "message" => "world"
      })
      
      assert updated_agent.state.messages == ["hello", "world"]
    end
    
    test "handles unknown signals gracefully" do
      agent = %{
        id: "test-4",
        state: %{counter: 0, messages: []}
      }
      
      {:ok, updated_agent} = TestAgent.handle_signal(agent, %{"type" => "unknown"})
      assert updated_agent == agent
    end
  end
  
  describe "lifecycle hooks" do
    test "calls pre_init hook" do
      state = %{counter: 0, messages: [], pre_init_called: false}
      
      {:ok, updated_state} = TestAgent.pre_init(state)
      assert updated_state.pre_init_called == true
    end
    
    test "calls post_init hook" do
      agent = %{
        id: "test-5",
        state: %{counter: 0, messages: [], post_init_called: false}
      }
      
      {:ok, updated_agent} = TestAgent.post_init(agent)
      assert updated_agent.state.post_init_called == true
    end
  end
  
  describe "health checks" do
    test "reports healthy when counter is low" do
      agent = %{
        id: "test-6",
        state: %{counter: 10}
      }
      
      assert {:healthy, %{counter: 10}} = TestAgent.health_check(agent)
    end
    
    test "reports unhealthy when counter is high" do
      agent = %{
        id: "test-7",
        state: %{counter: 150}
      }
      
      assert {:unhealthy, %{counter: 150, reason: "Counter too high"}} = 
        TestAgent.health_check(agent)
    end
  end
  
  describe "state management" do
    test "updates state correctly" do
      agent = %{
        id: "test-8",
        state: %{counter: 0, messages: []}
      }
      
      updated_agent = TestAgent.update_state(agent, %{counter: 42})
      assert updated_agent.state.counter == 42
      assert updated_agent.state.messages == []
    end
    
    test "gets current state" do
      agent = %{
        id: "test-9",
        state: %{counter: 99, messages: ["test"]}
      }
      
      state = TestAgent.get_state(agent)
      assert state.counter == 99
      assert state.messages == ["test"]
    end
  end
  
  describe "signal emission" do
    test "emits signal with agent metadata" do
      agent = %{
        id: "test-10",
        state: %{}
      }
      
      # This would emit through SignalDispatcher in real usage
      signal = %{"type" => "test_signal", "data" => "test"}
      assert :ok = TestAgent.emit_signal(agent, signal)
    end
  end
  
  describe "subscriptions" do
    test "subscribes to signal patterns" do
      agent = %{
        id: "test-11",
        state: %{}
      }
      
      updated_agent = TestAgent.subscribe_to_signals(agent, "test.*")
      assert updated_agent.state.signal_subscriptions == ["test.*"]
      
      # Subscribe to another pattern
      updated_agent = TestAgent.subscribe_to_signals(updated_agent, "other.*")
      assert Enum.sort(updated_agent.state.signal_subscriptions) == ["other.*", "test.*"]
    end
  end
end