defmodule RubberDuck.Agents.CommunicationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.Communication
  alias RubberDuck.Agents.Registry

  setup do
    # Start a test registry
    {:ok, registry} = Registry.start_link(keys: :unique, name: __MODULE__.TestRegistry)
    %{registry: __MODULE__.TestRegistry}
  end

  describe "send_message/4" do
    test "sends message to agent via registry", %{registry: registry} do
      # Register a test process
      agent_id = "test_agent_1"
      Registry.register(registry, agent_id, %{type: :test})

      # Send message
      message = {:test_message, "hello"}
      assert :ok = Communication.send_message(agent_id, message, :self, registry: registry)

      # Should receive the message
      assert_receive {:agent_message, ^message, :self}
    end

    test "returns error for non-existent agent", %{registry: registry} do
      message = {:test_message, "hello"}

      assert {:error, :agent_not_found} =
               Communication.send_message("non_existent", message, :self, registry: registry)
    end

    test "supports broadcast to agent type", %{registry: registry} do
      # Register multiple agents of same type
      Registry.register(registry, "agent_1", %{type: :research})
      Registry.register(registry, "agent_2", %{type: :research})
      Registry.register(registry, "agent_3", %{type: :analysis})

      # Broadcast to research agents
      message = {:broadcast, "update"}
      assert {:ok, 2} = Communication.broadcast_to_type(:research, message, :self, registry: registry)

      # Should receive 2 messages
      assert_receive {:agent_message, ^message, :self}
      assert_receive {:agent_message, ^message, :self}
      refute_receive {:agent_message, ^message, :self}
    end
  end

  describe "request_response/5" do
    test "sends request and waits for response", %{registry: registry} do
      # Register a test process that will respond
      agent_id = "responder_1"
      Registry.register(registry, agent_id, %{type: :test})

      # Spawn a process to handle the request
      spawn(fn ->
        receive do
          {:agent_request, {:calculate, 5}, from, ref} ->
            Communication.send_response(from, {:ok, 25}, ref)
        end
      end)

      # Send request
      assert {:ok, 25} =
               Communication.request_response(agent_id, {:calculate, 5}, 1000, registry: registry)
    end

    test "times out when no response", %{registry: registry} do
      agent_id = "silent_agent"
      Registry.register(registry, agent_id, %{type: :test})

      assert {:error, :timeout} =
               Communication.request_response(agent_id, {:calculate, 5}, 100, registry: registry)
    end
  end

  describe "coordinate_task/3" do
    test "coordinates task between multiple agents", %{registry: registry} do
      # Register test agents
      Registry.register(registry, "analyzer", %{type: :analysis})
      Registry.register(registry, "generator", %{type: :generation})

      coordination_spec = %{
        steps: [
          %{agent_type: :analysis, task: {:analyze, "code"}},
          %{agent_type: :generation, task: {:generate, "improvement"}}
        ],
        timeout: 1000
      }

      # Mock agent responses
      spawn(fn ->
        receive do
          {:agent_request, {:analyze, "code"}, from, ref} ->
            Communication.send_response(from, {:ok, %{issues: []}}, ref)
        end
      end)

      spawn(fn ->
        receive do
          {:agent_request, {:generate, "improvement"}, from, ref} ->
            Communication.send_response(from, {:ok, %{code: "improved"}}, ref)
        end
      end)

      assert {:ok, results} = Communication.coordinate_task(coordination_spec, self(), registry: registry)
      assert length(results) == 2
    end
  end

  describe "Protocol formatting" do
    test "formats standard agent message" do
      message = {:task_completed, %{id: "123", result: :success}}
      formatted = Communication.format_message(message, :research_agent)

      assert formatted.type == :task_completed
      assert formatted.sender == :research_agent
      assert formatted.payload == %{id: "123", result: :success}
      assert formatted.timestamp
    end

    test "formats inter-agent request" do
      request = Communication.format_request(:analyze_code, %{file: "test.ex"}, :generation_agent)

      assert request.type == :request
      assert request.action == :analyze_code
      assert request.sender == :generation_agent
      assert request.payload == %{file: "test.ex"}
      assert request.ref
    end

    test "formats coordination message" do
      coord_msg =
        Communication.format_coordination_message(
          :workflow_step_complete,
          %{step: 1, result: :ok},
          :coordinator
        )

      assert coord_msg.type == :coordination
      assert coord_msg.event == :workflow_step_complete
      assert coord_msg.sender == :coordinator
    end
  end

  describe "Message routing" do
    test "routes message based on capabilities", %{registry: registry} do
      # Register agents with capabilities
      Registry.register(registry, "agent_1", %{type: :analysis, capabilities: [:code_analysis]})
      Registry.register(registry, "agent_2", %{type: :generation, capabilities: [:code_generation]})

      # Route based on required capability
      message = {:analyze_this, "code"}

      assert {:ok, agent_id} =
               Communication.route_to_capable_agent(:code_analysis, message, registry: registry)

      assert agent_id == "agent_1"
    end

    test "returns error when no capable agent found", %{registry: registry} do
      message = {:unknown_task, "data"}

      assert {:error, :no_capable_agent} =
               Communication.route_to_capable_agent(:unknown_capability, message, registry: registry)
    end
  end

  describe "Pub/Sub patterns" do
    test "subscribes to agent events", %{registry: registry} do
      # Subscribe to events
      assert :ok = Communication.subscribe(:task_completed, self(), registry: registry)

      # Publish event
      event = {:task_completed, %{id: "123", agent: "test_agent"}}
      assert :ok = Communication.publish_event(event, registry: registry)

      # Should receive the event
      assert_receive {:agent_event, ^event}
    end

    test "unsubscribes from events", %{registry: registry} do
      # Subscribe then unsubscribe
      Communication.subscribe(:task_completed, self(), registry: registry)
      Communication.unsubscribe(:task_completed, self(), registry: registry)

      # Publish event
      event = {:task_completed, %{id: "123"}}
      Communication.publish_event(event, registry: registry)

      # Should not receive the event
      refute_receive {:agent_event, ^event}
    end
  end

  describe "Error handling" do
    test "handles agent crashes during communication", %{registry: registry} do
      # Register an agent that will crash
      agent_id = "crasher"

      pid =
        spawn(fn ->
          receive do
            _ -> raise "Intentional crash"
          end
        end)

      Registry.register(registry, agent_id, %{type: :test, pid: pid})

      # Try to communicate
      assert {:error, :agent_crashed} =
               Communication.request_response(agent_id, {:test}, 100, registry: registry)
    end
  end

  describe "Performance monitoring" do
    test "tracks message latency" do
      start_time = System.monotonic_time(:millisecond)

      # Simulate message processing
      Process.sleep(50)

      latency = Communication.calculate_latency(start_time)
      assert latency >= 50
    end

    test "maintains communication metrics" do
      metrics = Communication.get_metrics()

      assert Map.has_key?(metrics, :messages_sent)
      assert Map.has_key?(metrics, :messages_received)
      assert Map.has_key?(metrics, :average_latency)
      assert Map.has_key?(metrics, :errors)
    end
  end
end
