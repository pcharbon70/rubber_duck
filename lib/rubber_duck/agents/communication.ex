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

  alias RubberDuck.Agents.{Registry, AgentRegistry}

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
  def send_message(agent_id, message, sender, opts \\ []) do
    # Use custom registry if specified, otherwise use AgentRegistry
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      case AgentRegistry.lookup_agent(agent_id) do
        {:ok, pid, _metadata} ->
          formatted_message = format_message(message, sender)
          send(pid, {:agent_message, formatted_message.payload, formatted_message.sender})
          update_metrics(:messages_sent, 1)
          :ok

        {:error, :agent_not_found} ->
          {:error, :agent_not_found}
      end
    else
      # Fallback to standard Registry if needed
      registry = Keyword.get(opts, :registry, RubberDuck.Agents.Registry)

      case RubberDuck.Agents.Registry.lookup_agent(registry, agent_id) do
        {:ok, _metadata} ->
          formatted_message = format_message(message, sender)
          [{pid, _}] = Elixir.Registry.lookup(registry, agent_id)
          send(pid, {:agent_message, formatted_message.payload, formatted_message.sender})
          update_metrics(:messages_sent, 1)
          :ok

        {:error, :not_found} ->
          {:error, :agent_not_found}
      end
    end
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
  def broadcast_to_type(agent_type, message, sender, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      formatted_message = format_message(message, sender)
      broadcast_message = {:agent_message, formatted_message.payload, formatted_message.sender}

      case AgentRegistry.broadcast_to_type(agent_type, broadcast_message) do
        {:ok, count} ->
          update_metrics(:broadcasts_sent, 1)
          update_metrics(:messages_sent, count)
          {:ok, count}

        error ->
          error
      end
    else
      # Without AgentRegistry, we can't efficiently broadcast by type
      {:error, :not_supported}
    end
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
  def request_response(agent_id, request, timeout, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)
    ref = make_ref()
    sender = self()

    lookup_result =
      if use_agent_registry do
        case AgentRegistry.lookup_agent(agent_id) do
          {:ok, pid, metadata} -> {:ok, pid, metadata}
          {:error, _} -> {:error, :agent_not_found}
        end
      else
        registry = Keyword.get(opts, :registry, RubberDuck.Agents.Registry)

        case RubberDuck.Agents.Registry.lookup_agent(registry, agent_id) do
          {:ok, meta} ->
            [{pid, _}] = Elixir.Registry.lookup(registry, agent_id)
            {:ok, pid, meta}

          {:error, :not_found} ->
            {:error, :agent_not_found}
        end
      end

    case lookup_result do
      {:ok, pid, _metadata} ->
        # Monitor the agent process
        monitor_ref = Process.monitor(pid)

        # Send request
        send(pid, {:agent_request, request, sender, ref})

        # Wait for response
        start_time = System.monotonic_time(:millisecond)

        receive do
          {:agent_response, response, ^ref} ->
            Process.demonitor(monitor_ref, [:flush])
            latency = calculate_latency(start_time)
            update_metrics(:average_latency, latency)
            {:ok, response}

          {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
            update_metrics(:errors, 1)
            {:error, :agent_crashed}
        after
          timeout ->
            Process.demonitor(monitor_ref, [:flush])
            update_metrics(:timeouts, 1)
            {:error, :timeout}
        end

      {:error, reason} ->
        {:error, reason}
    end
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
  def route_to_capable_agent(capability, message, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      case AgentRegistry.find_by_capability(capability) do
        {:ok, []} ->
          {:error, :no_capable_agent}

        {:ok, agents} ->
          # Select first available agent (could implement load balancing)
          {pid, _metadata} = hd(agents)
          send(pid, {:agent_message, message, :router})
          {:ok, :message_routed}

        error ->
          error
      end
    else
      # Standard Registry doesn't support capability-based routing
      {:error, :not_supported}
    end
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
  def subscribe(event_type, subscriber, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      AgentRegistry.subscribe(event_type, subscriber)
    else
      # Standard Registry doesn't support our event subscription pattern
      {:error, :not_supported}
    end
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
  def unsubscribe(event_type, subscriber, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      AgentRegistry.unsubscribe(event_type, subscriber)
    else
      # Standard Registry doesn't support our event subscription pattern
      {:error, :not_supported}
    end
  end

  @doc """
  Publishes an event to subscribers.

  ## Parameters
  - `event` - Event to publish
  - `opts` - Options

  ## Returns
  - `:ok`
  """
  def publish_event({event_type, data} = _event, opts \\ []) do
    use_agent_registry = Keyword.get(opts, :use_agent_registry, true)

    if use_agent_registry do
      case AgentRegistry.publish_event(event_type, data) do
        {:ok, count} ->
          update_metrics(:events_published, 1)
          {:ok, count}

        error ->
          error
      end
    else
      # Standard Registry doesn't support our event publication pattern
      {:error, :not_supported}
    end
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

  defp execute_coordination_steps([step | rest], results, coordinator, registry, timeout) do
    agent_type = step.agent_type
    task = step.task

    # Try to find an agent of the required type using AgentRegistry
    case find_agent_by_type(agent_type) do
      {:ok, agent_id} ->
        # Execute step on agent
        case request_response(agent_id, task, timeout) do
          {:ok, result} ->
            # Notify coordinator of step completion
            send(coordinator, {:step_completed, step, result})

            # Continue with next step
            execute_coordination_steps(rest, [result | results], coordinator, registry, timeout)

          {:error, reason} ->
            send(coordinator, {:step_failed, step, reason})
            {:error, {:step_failed, step, reason}}
        end

      {:error, reason} ->
        send(coordinator, {:step_failed, step, reason})
        {:error, {:no_agent_available, agent_type, reason}}
    end
  end

  defp find_agent_by_type(agent_type) do
    case AgentRegistry.find_by_type(agent_type) do
      {:ok, []} ->
        {:error, :no_agents_of_type}

      {:ok, agents} ->
        # Return the first available agent's ID
        {agent_id, _pid, _metadata} = hd(agents)
        {:ok, agent_id}

      error ->
        error
    end
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
