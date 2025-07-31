# Agent-Based Status Broadcasting System

This document outlines the complete transformation of RubberDuck's status broadcasting system into a Jido agent-based architecture. The system provides real-time status updates through Phoenix channels while maintaining full integration with the agent ecosystem.

## Architecture Overview

The new system consists of:
- **Status Broadcasting Agent**: Subscribes to status signals and broadcasts to Phoenix channels
- **Status Emitter**: Utility for agents to emit status signals
- **Updated BaseAgent**: Includes status emission helpers
- **Phoenix StatusChannel**: Receives broadcasts and manages client subscriptions

## Implementation

### 1. Status Broadcasting Agent

```elixir
# lib/rubber_duck/agents/status_broadcasting_agent.ex
defmodule RubberDuck.Agents.StatusBroadcastingAgent do
  use RubberDuck.Agents.BaseAgent
  
  require Logger
  
  @categories [:engine, :tool, :workflow, :progress, :error, :info, :conversation, :analysis]
  
  defstruct [
    :agent_id,
    message_queue: :queue.new(),
    queue_size: 0,
    max_queue_size: 1000,
    batch_size: 50,
    flush_interval: 100,
    subscriptions: MapSet.new(),
    metrics: %{processed: 0, dropped: 0, batches_sent: 0, channel_broadcasts: 0}
  ]

  @impl true
  def init(opts) do
    state = struct(__MODULE__, Keyword.put(opts, :agent_id, self()))
    
    # Subscribe to all status signals from any agent
    :ok = subscribe_to_status_signals()
    
    # Start flush timer
    Process.send_after(self(), :flush_batch, state.flush_interval)
    
    Logger.info("Status Broadcasting Agent started", agent_id: state.agent_id)
    
    {:ok, state}
  end

  @impl true
  def handle_signal(%{type: "status." <> category} = signal, state) when category in ["engine", "tool", "workflow", "progress", "error", "info", "conversation", "analysis"] do
    case extract_status_data(signal) do
      {:ok, status_data} ->
        state = enqueue_message(status_data, state)
        state = maybe_flush_batch(state)
        {:ok, update_metrics(state, :processed)}
      
      {:error, reason} ->
        Logger.warning("Failed to process status signal", 
          signal_id: signal.id, 
          reason: reason
        )
        {:ok, update_metrics(state, :dropped)}
    end
  end

  @impl true
  def handle_signal(_signal, state), do: {:ok, state}

  def handle_info(:flush_batch, state) do
    state = flush_batch(state)
    Process.send_after(self(), :flush_batch, state.flush_interval)
    {:noreply, state}
  end

  def handle_info({:metrics_request, from}, state) do
    send(from, {:metrics_response, state.metrics})
    {:noreply, state}
  end

  # Private functions
  defp subscribe_to_status_signals do
    Enum.each(@categories, fn category ->
      RubberDuck.Agents.SignalRouter.subscribe("status.#{category}")
    end)
    
    # Also subscribe to wildcard patterns for subcategories
    RubberDuck.Agents.SignalRouter.subscribe("status.*")
  end

  defp extract_status_data(%{data: data, source: source, time: time, id: id} = signal) do
    with {:ok, conversation_id} <- Map.fetch(data, "conversation_id"),
         {:ok, category} <- Map.fetch(data, "category"),
         {:ok, message} <- Map.fetch(data, "message") do
      
      # Extract category from signal type as fallback
      signal_category = signal.type |> String.replace("status.", "") |> String.to_existing_atom()
      final_category = if category in @categories, do: String.to_existing_atom(category), else: signal_category
      
      status = %{
        id: id,
        conversation_id: conversation_id,
        category: final_category,
        message: message,
        metadata: Map.get(data, "metadata", %{}),
        timestamp: time || DateTime.utc_now(),
        agent_id: source,
        correlation_id: id
      }
      
      {:ok, status}
    else
      :error -> {:error, "Missing required fields in signal data"}
    end
  end

  defp enqueue_message(status_data, state) do
    if state.queue_size >= state.max_queue_size do
      # Drop oldest message and add new one (FIFO with overflow)
      {_dropped, new_queue} = :queue.out(state.message_queue)
      new_queue = :queue.in(status_data, new_queue)
      
      Logger.warning("Status queue overflow, dropping oldest message", 
        queue_size: state.queue_size,
        conversation_id: status_data.conversation_id
      )
      
      %{state | 
        message_queue: new_queue,
        metrics: update_in(state.metrics.dropped, &(&1 + 1))
      }
    else
      %{state |
        message_queue: :queue.in(status_data, state.message_queue),
        queue_size: state.queue_size + 1
      }
    end
  end

  defp maybe_flush_batch(state) do
    if state.queue_size >= state.batch_size do
      flush_batch(state)
    else
      state
    end
  end

  defp flush_batch(%{queue_size: 0} = state), do: state
  defp flush_batch(state) do
    {messages, remaining_queue} = extract_batch(state.message_queue, state.batch_size, [])
    
    # Group messages by conversation for efficient broadcasting
    grouped_messages = group_messages_by_conversation(messages)
    
    # Broadcast to Phoenix channels for each conversation
    broadcast_count = broadcast_to_channels(grouped_messages)
    
    %{state |
      message_queue: remaining_queue,
      queue_size: state.queue_size - length(messages),
      metrics: state.metrics
        |> update_in([:batches_sent], &(&1 + 1))
        |> update_in([:channel_broadcasts], &(&1 + broadcast_count))
    }
  end

  defp extract_batch(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp extract_batch(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        extract_batch(new_queue, count - 1, [item | acc])
      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp group_messages_by_conversation(messages) do
    Enum.group_by(messages, & &1.conversation_id)
  end

  defp broadcast_to_channels(grouped_messages) do
    Enum.reduce(grouped_messages, 0, fn {conversation_id, messages}, count ->
      # Group by category for efficient client-side filtering
      by_category = Enum.group_by(messages, & &1.category)
      
      Enum.each(by_category, fn {category, category_messages} ->
        broadcast_category_messages(conversation_id, category, category_messages)
      end)
      
      count + map_size(by_category)
    end)
  end

  defp broadcast_category_messages(conversation_id, category, messages) do
    topic = "status:#{conversation_id}"
    
    payload = %{
      conversation_id: conversation_id,
      category: category,
      messages: Enum.map(messages, &format_message_for_client/1),
      count: length(messages),
      timestamp: DateTime.utc_now(),
      batch_id: generate_batch_id()
    }
    
    # Broadcast to Phoenix PubSub (which StatusChannel subscribes to)
    Phoenix.PubSub.broadcast(RubberDuck.PubSub, topic, {
      :status_update, 
      category, 
      payload
    })
    
    # Also emit a signal for other agents that might want to react to status broadcasts
    emit_broadcast_signal(conversation_id, category, payload)
  end

  defp format_message_for_client(status) do
    %{
      id: status.id,
      message: status.message,
      metadata: status.metadata,
      timestamp: status.timestamp,
      agent_id: status.agent_id,
      correlation_id: status.correlation_id
    }
  end

  defp emit_broadcast_signal(conversation_id, category, payload) do
    signal = %{
      id: generate_batch_id(),
      type: "status.broadcasted",
      source: self(),
      time: DateTime.utc_now(),
      data: %{
        "conversation_id" => conversation_id,
        "category" => to_string(category),
        "payload" => payload
      }
    }
    
    RubberDuck.Agents.SignalRouter.emit_signal(signal)
  end

  defp generate_batch_id do
    :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
  end

  defp update_metrics(state, key) do
    update_in(state.metrics[key], &(&1 + 1))
  end
end
```

### 2. Status Emitter for Agents

```elixir
# lib/rubber_duck/agents/status_emitter.ex
defmodule RubberDuck.Agents.StatusEmitter do
  @moduledoc """
  Utility module for agents to emit status signals.
  These signals are automatically picked up by the StatusBroadcastingAgent
  and broadcasted to Phoenix channels.
  """
  
  alias RubberDuck.Agents.SignalRouter
  
  @categories [:engine, :tool, :workflow, :progress, :error, :info, :conversation, :analysis]

  @doc """
  Emit a status signal from an agent.
  Fire-and-forget, non-blocking operation.
  """
  def emit_status(agent_id, conversation_id, category, message, metadata \\ %{})
  
  # Skip if no conversation_id
  def emit_status(_agent_id, nil, _category, _message, _metadata), do: :ok
  
  def emit_status(agent_id, conversation_id, category, message, metadata) 
      when category in @categories do
    
    signal = %{
      id: generate_correlation_id(),
      type: "status.#{category}",
      source: agent_id,
      time: DateTime.utc_now(),
      data: %{
        "conversation_id" => conversation_id,
        "category" => to_string(category),
        "message" => message,
        "metadata" => metadata,
        "agent_id" => inspect(agent_id)
      }
    }
    
    # Emit signal asynchronously to avoid blocking the calling agent
    Task.start(fn ->
      SignalRouter.emit_signal(signal)
    end)
    
    :ok
  end
  
  def emit_status(_agent_id, _conversation_id, category, _message, _metadata) do
    require Logger
    Logger.warning("Invalid status category: #{inspect(category)}")
    :ok
  end

  # Convenience functions for different categories
  def emit_engine_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :engine, message, metadata)
  end

  def emit_tool_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :tool, message, metadata)
  end

  def emit_workflow_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :workflow, message, metadata)
  end

  def emit_progress_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :progress, message, metadata)
  end

  def emit_error_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :error, message, metadata)
  end

  def emit_info_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :info, message, metadata)
  end

  def emit_conversation_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :conversation, message, metadata)
  end

  def emit_analysis_status(agent_id, conversation_id, message, metadata \\ %{}) do
    emit_status(agent_id, conversation_id, :analysis, message, metadata)
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end
end
```

### 3. Updated BaseAgent with Status Emission

```elixir
# lib/rubber_duck/agents/base_agent.ex (updated section)
defmodule RubberDuck.Agents.BaseAgent do
  # ... existing code ...
  
  defmacro __using__(_opts) do
    quote do
      use Jido.Agent
      
      alias RubberDuck.Agents.StatusEmitter
      
      # ... existing base agent code ...
      
      # Status emission helpers available to all agents
      def emit_status(conversation_id, category, message, metadata \\ %{}) do
        StatusEmitter.emit_status(self(), conversation_id, category, message, metadata)
      end
      
      def emit_engine_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_engine_status(self(), conversation_id, message, metadata)
      end
      
      def emit_tool_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_tool_status(self(), conversation_id, message, metadata)
      end
      
      def emit_workflow_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_workflow_status(self(), conversation_id, message, metadata)
      end
      
      def emit_progress_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_progress_status(self(), conversation_id, message, metadata)
      end
      
      def emit_error_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_error_status(self(), conversation_id, message, metadata)
      end
      
      def emit_info_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_info_status(self(), conversation_id, message, metadata)
      end
      
      def emit_conversation_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_conversation_status(self(), conversation_id, message, metadata)
      end
      
      def emit_analysis_status(conversation_id, message, metadata \\ %{}) do
        StatusEmitter.emit_analysis_status(self(), conversation_id, message, metadata)
      end
    end
  end
end
```

### 4. Updated Phoenix StatusChannel

```elixir
# lib/rubber_duck_web/channels/status_channel.ex (updated)
defmodule RubberDuckWeb.StatusChannel do
  use RubberDuckWeb, :channel
  
  require Logger

  @categories [:engine, :tool, :workflow, :progress, :error, :info, :conversation, :analysis]

  def join("status:" <> conversation_id, _payload, socket) do
    case authorize_conversation_access(socket.assigns.user_id, conversation_id) do
      :ok ->
        # Subscribe to status updates for this conversation
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{conversation_id}")
        
        socket = assign(socket, :conversation_id, conversation_id)
        socket = assign(socket, :subscribed_categories, MapSet.new(@categories))
        
        Logger.info("User joined status channel", 
          user_id: socket.assigns.user_id,
          conversation_id: conversation_id
        )
        
        {:ok, socket}
        
      {:error, reason} ->
        Logger.warning("Status channel join denied", 
          user_id: socket.assigns.user_id,
          conversation_id: conversation_id,
          reason: reason
        )
        {:error, %{reason: reason}}
    end
  end

  def handle_in("subscribe_category", %{"category" => category}, socket) when category in @categories do
    category_atom = String.to_existing_atom(category)
    subscribed = MapSet.put(socket.assigns.subscribed_categories, category_atom)
    socket = assign(socket, :subscribed_categories, subscribed)
    
    {:reply, {:ok, %{subscribed_to: category}}, socket}
  end

  def handle_in("unsubscribe_category", %{"category" => category}, socket) when category in @categories do
    category_atom = String.to_existing_atom(category)
    subscribed = MapSet.delete(socket.assigns.subscribed_categories, category_atom)
    socket = assign(socket, :subscribed_categories, subscribed)
    
    {:reply, {:ok, %{unsubscribed_from: category}}, socket}
  end

  def handle_in("get_subscriptions", _payload, socket) do
    categories = socket.assigns.subscribed_categories |> MapSet.to_list()
    {:reply, {:ok, %{subscribed_categories: categories}}, socket}
  end

  def handle_in(event, payload, socket) do
    Logger.warning("Unhandled status channel event", 
      event: event, 
      payload: payload,
      user_id: socket.assigns.user_id
    )
    {:noreply, socket}
  end

  # Handle status updates from the StatusBroadcastingAgent
  def handle_info({:status_update, category, payload}, socket) do
    if MapSet.member?(socket.assigns.subscribed_categories, category) do
      push(socket, "status_update", payload)
    end
    
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("Unhandled status channel info", message: msg)
    {:noreply, socket}
  end

  defp authorize_conversation_access(user_id, conversation_id) do
    # Implement your authorization logic here
    # For now, allow access if user_id exists
    if user_id do
      :ok
    else
      {:error, "unauthorized"}
    end
  end
end
```

### 5. Example Agent Usage

Here's how agents now emit status updates:

```elixir
# Example: LLM Router Agent
defmodule RubberDuck.Agents.LLMRouterAgent do
  use RubberDuck.Agents.BaseAgent

  @impl true
  def handle_signal(%{type: "llm.request"} = signal, state) do
    conversation_id = get_in(signal, [:data, "conversation_id"])
    
    emit_engine_status(conversation_id, "Selecting optimal LLM provider", %{
      providers_available: length(state.providers),
      selection_strategy: "cost_optimized"
    })
    
    case select_provider(signal.data) do
      {:ok, provider} ->
        emit_engine_status(conversation_id, "Provider selected: #{provider.name}", %{
          provider: provider.name,
          model: provider.model,
          estimated_cost: provider.cost_per_token
        })
        
        # Route to provider...
        {:ok, state}
        
      {:error, reason} ->
        emit_error_status(conversation_id, "Provider selection failed", %{
          error: reason,
          fallback_available: has_fallback_providers?(state)
        })
        
        {:ok, state}
    end
  end

  # Example private functions
  defp select_provider(_data) do
    # Implementation here
    {:ok, %{name: "OpenAI", model: "gpt-4", cost_per_token: 0.03}}
  end

  defp has_fallback_providers?(state) do
    length(state.providers) > 1
  end
end
```

### 6. Application Supervisor Update

```elixir
# lib/rubber_duck/application.ex (add to children)
def start(_type, _args) do
  children = [
    # ... existing children ...
    
    # Add the Status Broadcasting Agent
    {RubberDuck.Agents.StatusBroadcastingAgent, [name: :status_broadcaster]},
    
    # ... rest of children ...
  ]
  
  opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Signal Flow

1. **Agent emits status**: Any agent calls `emit_status/4` or convenience functions
2. **Signal created**: StatusEmitter creates a CloudEvent signal with type `status.{category}`
3. **Signal routed**: SignalRouter delivers signal to StatusBroadcastingAgent
4. **Message queued**: StatusBroadcastingAgent queues the message for batching
5. **Batch processed**: Messages are grouped by conversation and category
6. **Phoenix broadcast**: Batched messages are sent to Phoenix PubSub
7. **Channel delivery**: StatusChannel receives and forwards to subscribed clients

## Benefits

- **Pure Agent-Based**: No legacy components, everything flows through signals
- **Resilient**: Broadcasting agent failures don't affect other agents
- **Scalable**: Can easily add multiple broadcasting agents or specialized processors
- **Observable**: All status flows are visible through signal monitoring
- **Decoupled**: Agents only emit signals, broadcasting is handled separately
- **Consistent**: Same communication patterns as the rest of the agent system
- **Real-time**: Direct Phoenix channel integration maintains WebSocket capabilities

## Configuration

The system supports configuration through the agent initialization:

```elixir
# config/config.exs
config :rubber_duck, RubberDuck.Agents.StatusBroadcastingAgent,
  max_queue_size: 1000,
  batch_size: 50,
  flush_interval: 100
```

This creates a robust, agent-based status broadcasting system that maintains all real-time WebSocket functionality while being fully integrated with the Jido agent architecture.
