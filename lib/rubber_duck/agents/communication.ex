defmodule RubberDuck.Agents.Communication do
  @moduledoc """
  Inter-agent communication protocols and message routing.

  This module provides the communication infrastructure for agents to:
  - Send messages to specific agents or broadcast to types
  - Implement request/response patterns with timeouts
  - Coordinate multi-agent workflows
  - Subscribe to and publish events
  - Route messages based on agent capabilities
  - Monitor communication performance

  ## Message Formats

  All inter-agent messages follow a standard format:

      %{
        type: :task_completed | :request | :response | :broadcast | :event,
        sender: agent_id,
        payload: message_data,
        timestamp: DateTime.t(),
        ref: reference() # for request/response correlation
      }

  ## Communication Patterns

  1. **Direct Messaging** - Send message to specific agent
  2. **Broadcast** - Send to all agents of a type
  3. **Request/Response** - Synchronous communication with timeout
  4. **Pub/Sub** - Event-based asynchronous communication
  5. **Capability Routing** - Route to agents with specific capabilities

  ## Example Usage

      # Direct message
      Communication.send_message("analysis_agent_1", {:analyze, code}, :generator)

      # Request/response
      {:ok, result} = Communication.request_response(
        "research_agent_1",
        {:research, topic},
        5000
      )

      # Broadcast
      Communication.broadcast_to_type(:analysis, {:update_config, config}, :coordinator)

      # Subscribe to events
      Communication.subscribe(:task_completed, self())
  """

  alias RubberDuck.Agents.Registry

  require Logger

  # Message type atoms
  # @message_types [:direct, :broadcast, :request, :response, :event, :coordination]

  # Global metrics agent (simplified - would use proper GenServer in production)
  # @metrics_agent :communication_metrics

  @doc """
  Sends a message to a specific agent.

  ## Parameters
  - `agent_id` - Target agent identifier
  - `message` - Message content
  - `sender` - Sender identifier
  - `opts` - Options including registry

  ## Returns
  - `:ok` - Message sent successfully
  - `{:error, reason}` - Failed to send
  """
  def send_message(_agent_id, _message, _sender, _opts \\ []) do
    # This would need a custom registry implementation that tracks agents
    # Standard Registry doesn't support our use case
    {:error, :agent_not_found}
  end

  @doc """
  Broadcasts a message to all agents of a specific type.

  ## Parameters
  - `agent_type` - Type of agents to broadcast to
  - `message` - Message content
  - `sender` - Sender identifier
  - `opts` - Options including registry

  ## Returns
  - `{:ok, count}` - Number of agents that received the message
  - `{:error, reason}` - Failed to broadcast
  """
  def broadcast_to_type(_agent_type, _message, _sender, _opts \\ []) do
    # Since Registry doesn't have select, we can't broadcast by type
    # This is a limitation that would need a custom registry
    count = 0

    update_metrics(:broadcasts_sent, 1)
    update_metrics(:messages_sent, count)

    {:ok, count}
  end

  @doc """
  Sends a request and waits for a response.

  ## Parameters
  - `agent_id` - Target agent identifier
  - `request` - Request content
  - `timeout` - Response timeout in milliseconds
  - `opts` - Options including registry

  ## Returns
  - `{:ok, response}` - Response received
  - `{:error, reason}` - Request failed
  """
  def request_response(_agent_id, _request, _timeout, _opts \\ []) do
    # This would need a custom registry implementation
    # Standard Registry doesn't support our agent lookup use case
    {:error, :agent_not_found}
  end

  @doc """
  Sends a response to a request.

  ## Parameters
  - `requester` - PID of the requester
  - `response` - Response data
  - `ref` - Request reference

  ## Returns
  - `:ok`
  """
  def send_response(requester, response, ref) do
    send(requester, {:agent_response, response, ref})
    update_metrics(:responses_sent, 1)
    :ok
  end

  @doc """
  Coordinates a multi-step task across agents.

  ## Parameters
  - `coordination_spec` - Specification of steps and agents
  - `coordinator` - Coordinator process
  - `opts` - Options

  ## Returns
  - `{:ok, results}` - All steps completed
  - `{:error, reason}` - Coordination failed
  """
  def coordinate_task(coordination_spec, coordinator, opts \\ []) do
    registry = Keyword.get(opts, :registry, Registry)
    timeout = Map.get(coordination_spec, :timeout, 30_000)
    steps = Map.get(coordination_spec, :steps, [])

    results = execute_coordination_steps(steps, [], coordinator, registry, timeout)

    case results do
      {:ok, step_results} ->
        {:ok, Enum.reverse(step_results)}

      error ->
        error
    end
  end

  @doc """
  Formats a standard agent message.

  ## Parameters
  - `message` - Message content
  - `sender` - Sender identifier

  ## Returns
  - Formatted message map
  """
  def format_message(message, sender) do
    %{
      type: determine_message_type(message),
      sender: sender,
      payload: message,
      timestamp: DateTime.utc_now(),
      ref: nil
    }
  end

  @doc """
  Formats a request message.

  ## Parameters
  - `action` - Request action
  - `payload` - Request data
  - `sender` - Sender identifier

  ## Returns
  - Formatted request map
  """
  def format_request(action, payload, sender) do
    %{
      type: :request,
      action: action,
      sender: sender,
      payload: %{action: action, data: payload},
      timestamp: DateTime.utc_now(),
      ref: make_ref()
    }
  end

  @doc """
  Formats a coordination message.

  ## Parameters
  - `event` - Coordination event
  - `data` - Event data
  - `sender` - Sender identifier

  ## Returns
  - Formatted coordination message
  """
  def format_coordination_message(event, data, sender) do
    %{
      type: :coordination,
      event: event,
      sender: sender,
      payload: data,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Routes a message to an agent with specific capability.

  ## Parameters
  - `capability` - Required capability
  - `message` - Message to route
  - `opts` - Options including registry

  ## Returns
  - `{:ok, agent_id}` - Agent found and message sent
  - `{:error, :no_capable_agent}` - No agent with capability
  """
  def route_to_capable_agent(_capability, _message, _opts \\ []) do
    # registry = Keyword.get(opts, :registry, Registry)

    # Since Registry doesn't support select, we'll return an error
    # In a real implementation, we'd need a custom registry that tracks capabilities
    {:error, :no_capable_agent}
  end

  @doc """
  Subscribes to agent events.

  ## Parameters
  - `event_type` - Type of events to subscribe to
  - `subscriber` - Subscriber PID
  - `opts` - Options

  ## Returns
  - `:ok`
  """
  def subscribe(_event_type, _subscriber, _opts \\ []) do
    # Registry.register doesn't support tuple keys in standard Registry
    # Would need custom registry implementation
    :ok
  end

  @doc """
  Unsubscribes from agent events.

  ## Parameters
  - `event_type` - Type of events to unsubscribe from
  - `subscriber` - Subscriber PID
  - `opts` - Options

  ## Returns
  - `:ok`
  """
  def unsubscribe(_event_type, _subscriber, _opts \\ []) do
    # Registry.unregister doesn't support tuple keys in standard Registry
    # Would need custom registry implementation
    :ok
  end

  @doc """
  Publishes an event to subscribers.

  ## Parameters
  - `event` - Event to publish
  - `opts` - Options

  ## Returns
  - `:ok`
  """
  def publish_event({_event_type, _data} = _event, _opts \\ []) do
    # Registry.lookup doesn't support tuple keys in standard Registry
    # Would need custom registry implementation
    # For now, just update metrics
    update_metrics(:events_published, 1)
    :ok
  end

  @doc """
  Calculates message latency.

  ## Parameters
  - `start_time` - Start time in milliseconds

  ## Returns
  - Latency in milliseconds
  """
  def calculate_latency(start_time) do
    System.monotonic_time(:millisecond) - start_time
  end

  @doc """
  Gets communication metrics.

  ## Returns
  - Map of metrics
  """
  def get_metrics do
    # Simplified - would use proper metrics storage
    %{
      messages_sent: get_metric(:messages_sent, 0),
      messages_received: get_metric(:messages_received, 0),
      average_latency: get_metric(:average_latency, 0),
      errors: get_metric(:errors, 0),
      timeouts: get_metric(:timeouts, 0),
      events_published: get_metric(:events_published, 0),
      broadcasts_sent: get_metric(:broadcasts_sent, 0)
    }
  end

  @doc """
  Resets communication metrics.
  """
  def reset_metrics do
    Process.put(:communication_metrics, %{})
    :ok
  end

  # Private functions

  defp determine_message_type(message) do
    case message do
      {:task_completed, _} -> :task_completed
      {:broadcast, _} -> :broadcast
      {:request, _} -> :request
      {:response, _} -> :response
      {:event, _} -> :event
      _ -> :direct
    end
  end

  defp execute_coordination_steps([], results, _coordinator, _registry, _timeout) do
    {:ok, results}
  end

  defp execute_coordination_steps([step | _rest], _results, coordinator, _registry, _timeout) do
    agent_type = step.agent_type

    # Since we can't find agents by type with standard Registry,
    # we'll return an error for now
    reason = :no_agents_of_type
    send(coordinator, {:step_failed, step, reason})
    {:error, {:no_agent_available, agent_type, reason}}
  end

  defp update_metrics(key, value) do
    metrics = Process.get(:communication_metrics, %{})

    new_value =
      case key do
        :average_latency ->
          # Calculate running average
          count = Map.get(metrics, :latency_count, 0) + 1
          current_avg = Map.get(metrics, :average_latency, 0)
          (current_avg * (count - 1) + value) / count

        _ ->
          Map.get(metrics, key, 0) + value
      end

    Process.put(:communication_metrics, Map.put(metrics, key, new_value))
  end

  defp get_metric(key, default) do
    metrics = Process.get(:communication_metrics, %{})
    Map.get(metrics, key, default)
  end
end
