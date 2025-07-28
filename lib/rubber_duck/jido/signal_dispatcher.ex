defmodule RubberDuck.Jido.SignalDispatcher do
  @moduledoc """
  CloudEvents-based signal dispatcher for Jido agents.

  This module handles the routing and delivery of signals between agents
  using the CloudEvents specification. It provides both direct (point-to-point)
  and broadcast messaging capabilities.

  ## Features

  - CloudEvents v1.0 compliant messaging
  - Direct and broadcast signal delivery
  - Signal persistence and replay (optional)
  - Telemetry integration for monitoring
  - Pattern-based subscriptions

  ## Signal Format

  Signals are automatically converted to CloudEvents format:

      %{
        specversion: "1.0",
        id: "unique-id",
        source: "rubber_duck.jido.agent_id",
        type: "agent.signal.type",
        time: "2024-01-01T00:00:00Z",
        data: %{...}
      }
  """

  use GenServer

  alias Cloudevents.Format.V_1_0.Event, as: CloudEvent

  require Logger

  @registry RubberDuck.Jido.Registry

  # Client API

  @doc """
  Starts the signal dispatcher.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Emits a signal to a target agent or broadcasts to all agents.

  ## Parameters

  - `target` - PID, agent ID, or `:broadcast`
  - `signal` - Signal data (will be converted to CloudEvent)

  ## Returns

  - `:ok` - Signal sent successfully
  - `{:error, reason}` - Failed to send signal
  """
  @spec emit(pid() | String.t() | :broadcast, map()) :: :ok | {:error, term()}
  def emit(target, signal) do
    GenServer.call(__MODULE__, {:emit, target, signal})
  end

  @doc """
  Subscribes to signals matching a pattern.

  ## Parameters

  - `subscriber` - PID of the subscriber
  - `pattern` - Pattern to match (e.g., "agent.task.*")

  ## Returns

  - `{:ok, subscription_id}` - Success
  - `{:error, reason}` - Failure
  """
  @spec subscribe(pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def subscribe(subscriber, pattern) do
    GenServer.call(__MODULE__, {:subscribe, subscriber, pattern})
  end

  @doc """
  Unsubscribes from signal patterns.

  ## Parameters

  - `subscription_id` - The subscription ID to remove

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure
  """
  @spec unsubscribe(String.t()) :: :ok | {:error, term()}
  def unsubscribe(subscription_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscription_id})
  end

  @doc """
  Gets statistics about signal processing.

  ## Returns

  A map containing:
  - `:processed` - Total signals processed
  - `:broadcast` - Total broadcasts sent
  - `:direct` - Total direct messages sent
  - `:errors` - Total errors encountered
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Get configuration
    config = Application.get_env(:rubber_duck, :jido, [])
    router_config = Keyword.get(config, :signal_router, [])
    
    state = %{
      # Subscriptions: pattern => [{subscriber_pid, subscription_id}]
      subscriptions: %{},
      # Stats
      stats: %{
        processed: 0,
        broadcast: 0,
        direct: 0,
        errors: 0
      },
      # Configuration
      config: router_config,
      # CloudEvents defaults
      cloudevents: Keyword.get(router_config, :cloudevents, [])
    }

    Logger.info("Signal dispatcher started with config: #{inspect(router_config)}")

    {:ok, state}
  end

  @impl true
  def handle_call({:emit, target, signal}, _from, state) do
    # Convert to CloudEvent
    cloud_event = build_cloud_event(signal, state.cloudevents)
    
    # Route the signal
    result = case target do
      :broadcast ->
        broadcast_signal(cloud_event, state)
        
      pid when is_pid(pid) ->
        send_to_agent(pid, cloud_event)
        
      agent_id when is_binary(agent_id) ->
        send_to_agent_by_id(agent_id, cloud_event)
    end

    # Update stats
    new_stats = update_stats(state.stats, target, result)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :jido, :signal, :emit],
      %{count: 1},
      %{target: target, type: cloud_event.type}
    )

    {:reply, result, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:subscribe, subscriber, pattern}, _from, state) do
    subscription_id = generate_subscription_id()
    
    subscriptions = Map.update(
      state.subscriptions,
      pattern,
      [{subscriber, subscription_id}],
      fn subs -> [{subscriber, subscription_id} | subs] end
    )
    
    Logger.debug("Added subscription #{subscription_id} for pattern #{pattern}")
    
    {:reply, {:ok, subscription_id}, %{state | subscriptions: subscriptions}}
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    subscriptions = state.subscriptions
    |> Enum.map(fn {pattern, subs} ->
      filtered = Enum.reject(subs, fn {_, sub_id} -> sub_id == subscription_id end)
      {pattern, filtered}
    end)
    |> Enum.reject(fn {_, subs} -> Enum.empty?(subs) end)
    |> Map.new()
    
    {:reply, :ok, %{state | subscriptions: subscriptions}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  # Private functions

  defp build_cloud_event(signal, cloudevents_config) do
    %CloudEvent{
      specversion: Keyword.get(cloudevents_config, :spec_version, "1.0"),
      id: Uniq.UUID.uuid4(),
      source: signal[:source] || Keyword.get(cloudevents_config, :default_source, "rubber_duck.jido"),
      type: signal[:type] || "agent.signal",
      time: DateTime.utc_now() |> DateTime.to_iso8601(),
      datacontenttype: Keyword.get(cloudevents_config, :content_type, "application/json"),
      data: signal[:data] || signal
    }
  end

  defp broadcast_signal(cloud_event, state) do
    # Get all agents
    agents = Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    
    # Send to all agents
    Enum.each(agents, fn {_agent_id, pid} ->
      send_signal_to_pid(pid, cloud_event)
    end)
    
    # Also send to pattern subscribers
    notify_subscribers(cloud_event, state.subscriptions)
    
    :ok
  end

  defp send_to_agent(pid, cloud_event) when is_pid(pid) do
    if Process.alive?(pid) do
      send_signal_to_pid(pid, cloud_event)
      :ok
    else
      {:error, :agent_not_alive}
    end
  end

  defp send_to_agent_by_id(agent_id, cloud_event) do
    case Registry.lookup(@registry, agent_id) do
      [{pid, _}] ->
        send_to_agent(pid, cloud_event)
        
      [] ->
        {:error, :agent_not_found}
    end
  end

  defp send_signal_to_pid(pid, cloud_event) do
    send(pid, {:signal, cloud_event})
  end

  defp notify_subscribers(cloud_event, subscriptions) do
    # Find matching patterns
    Enum.each(subscriptions, fn {pattern, subscribers} ->
      if signal_matches_pattern?(cloud_event.type, pattern) do
        Enum.each(subscribers, fn {subscriber_pid, _sub_id} ->
          if Process.alive?(subscriber_pid) do
            send(subscriber_pid, {:signal, cloud_event})
          end
        end)
      end
    end)
  end

  defp signal_matches_pattern?(signal_type, pattern) do
    # Simple pattern matching with wildcards
    regex_pattern = pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", ".*")
    |> Regex.compile!()
    
    Regex.match?(regex_pattern, signal_type)
  end

  defp update_stats(stats, target, result) do
    stats
    |> Map.update!(:processed, &(&1 + 1))
    |> update_target_stats(target)
    |> update_error_stats(result)
  end

  defp update_target_stats(stats, :broadcast) do
    Map.update!(stats, :broadcast, &(&1 + 1))
  end

  defp update_target_stats(stats, _) do
    Map.update!(stats, :direct, &(&1 + 1))
  end

  defp update_error_stats(stats, {:error, _}) do
    Map.update!(stats, :errors, &(&1 + 1))
  end

  defp update_error_stats(stats, _), do: stats

  defp generate_subscription_id do
    "sub_#{System.system_time(:millisecond)}_#{:rand.uniform(9999)}"
  end
end