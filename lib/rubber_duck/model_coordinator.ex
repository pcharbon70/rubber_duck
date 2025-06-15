defmodule RubberDuck.ModelCoordinator do
  @moduledoc """
  Coordinates AI model interactions and load balancing.
  
  This GenServer manages model registration, selection, health monitoring,
  and usage statistics for AI models in the system.
  """
  use GenServer
  
  alias RubberDuck.{EventSchemas}
  alias RubberDuck.EventBroadcasting.EventBroadcaster

  # Client API

  @doc """
  Starts the ModelCoordinator GenServer.
  
  ## Options
    * `:name` - Register the process with a specific name
    * `:config` - Initial configuration map
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    
    # Pass the name in init_arg for Registry registration
    init_arg = Keyword.put(opts, :registry_name, name)
    
    # Use via tuple for Registry-based naming when name is not the module
    server_opts = if name != __MODULE__ && name != nil do
      [name: {:via, Registry, {RubberDuck.Registry, name}}]
    else
      [name: name]
    end
    
    GenServer.start_link(__MODULE__, init_arg, server_opts)
  end

  @doc """
  Registers a new model with the coordinator.
  """
  def register_model(server \\ __MODULE__, model_spec) do
    GenServer.call(server, {:register_model, model_spec})
  end

  @doc """
  Lists all registered models.
  """
  def list_models(server \\ __MODULE__) do
    GenServer.call(server, :list_models)
  end

  @doc """
  Gets information about a specific model.
  """
  def get_model(server \\ __MODULE__, model_name) do
    GenServer.call(server, {:get_model, model_name})
  end

  @doc """
  Unregisters a model from the coordinator.
  """
  def unregister_model(server \\ __MODULE__, model_name) do
    GenServer.call(server, {:unregister_model, model_name})
  end

  @doc """
  Updates a model's configuration.
  """
  def update_model(server \\ __MODULE__, model_name, updates) do
    GenServer.call(server, {:update_model, model_name, updates})
  end

  @doc """
  Selects a model based on criteria.
  """
  def select_model(server \\ __MODULE__, criteria \\ []) do
    GenServer.call(server, {:select_model, criteria})
  end

  @doc """
  Tracks usage statistics for a model.
  """
  def track_usage(server \\ __MODULE__, model_name, status, latency) do
    GenServer.cast(server, {:track_usage, model_name, status, latency})
  end

  @doc """
  Gets usage statistics for a model.
  """
  def get_stats(server \\ __MODULE__, model_name) do
    GenServer.call(server, {:get_stats, model_name})
  end

  @doc """
  Marks a model as unhealthy.
  """
  def mark_unhealthy(server \\ __MODULE__, model_name, reason) do
    GenServer.call(server, {:mark_unhealthy, model_name, reason})
  end

  @doc """
  Marks a model as healthy.
  """
  def mark_healthy(server \\ __MODULE__, model_name) do
    GenServer.call(server, {:mark_healthy, model_name})
  end

  @doc """
  Performs a health check on the GenServer.
  """
  def health_check(server \\ __MODULE__) do
    GenServer.call(server, :health_check)
  end

  @doc """
  Gets information about the GenServer state.
  """
  def get_info(server \\ __MODULE__) do
    GenServer.call(server, :get_info)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, %{})
    
    state = %{
      models: %{},
      stats: %{},
      config: Map.merge(%{
        max_concurrent_models: 5,
        timeout: 30_000
      }, config),
      start_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:register_model, model_spec}, _from, state) do
    model = Map.merge(model_spec, %{
      health_status: :healthy,
      health_reason: nil,
      registered_at: DateTime.utc_now()
    })
    
    # Broadcast model registration event
    event_payload = EventSchemas.model_health_event(
      model.name,
      Map.get(model, :provider, "unknown"),
      :healthy,
      reason: "Model registered"
    )
    EventBroadcaster.broadcast_async(%{
      topic: "model.registration.completed",
      payload: event_payload,
      priority: :normal,
      metadata: %{component: "model_coordinator", operation: "register"}
    })
    
    new_state = put_in(state, [:models, model.name], model)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_models, _from, state) do
    models = Map.values(state.models)
    {:reply, models, state}
  end

  @impl true
  def handle_call({:get_model, model_name}, _from, state) do
    case Map.get(state.models, model_name) do
      nil -> {:reply, {:error, :model_not_found}, state}
      model -> {:reply, {:ok, model}, state}
    end
  end

  @impl true
  def handle_call({:unregister_model, model_name}, _from, state) do
    new_state = %{state | 
      models: Map.delete(state.models, model_name),
      stats: Map.delete(state.stats, model_name)
    }
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:update_model, model_name, updates}, _from, state) do
    case Map.get(state.models, model_name) do
      nil -> 
        {:reply, {:error, :model_not_found}, state}
      model ->
        updated_model = Map.merge(model, updates)
        new_state = put_in(state, [:models, model_name], updated_model)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:select_model, criteria}, _from, state) do
    capability = Keyword.get(criteria, :capability)
    session_id = Keyword.get(criteria, :session_id)
    
    available_models = state.models
    |> Map.values()
    |> Enum.filter(& &1.health_status == :healthy)
    |> filter_by_capability(capability)
    
    case available_models do
      [] -> 
        # Broadcast model selection failed event
        if session_id do
          event_payload = EventSchemas.model_selection_event(
            session_id,
            criteria,
            nil,
            "No healthy models available for criteria: #{inspect(capability)}"
          )
          EventBroadcaster.broadcast_async(%{
            topic: EventSchemas.suggest_topic(:model_selected),
            payload: event_payload,
            priority: :high,
            metadata: %{component: "model_coordinator", result: "failed"}
          })
        end
        
        {:reply, {:error, :no_model_available}, state}
        
      models -> 
        selected_model = Enum.random(models)
        
        # Broadcast model selection success event
        if session_id do
          event_payload = EventSchemas.model_selection_event(
            session_id,
            criteria,
            selected_model.name,
            "Model selected based on availability and capability match"
          )
          EventBroadcaster.broadcast_async(%{
            topic: EventSchemas.suggest_topic(:model_selected),
            payload: event_payload,
            priority: :normal,
            metadata: %{component: "model_coordinator", result: "success"}
          })
        end
        
        {:reply, {:ok, selected_model}, state}
    end
  end

  @impl true
  def handle_call({:get_stats, model_name}, _from, state) do
    stats = Map.get(state.stats, model_name, %{
      success_count: 0,
      failure_count: 0,
      total_latency: 0
    })
    
    average_latency = if stats.success_count > 0 do
      stats.total_latency / stats.success_count
    else
      0
    end
    
    stats_with_average = Map.put(stats, :average_latency, average_latency)
    {:reply, stats_with_average, state}
  end

  @impl true
  def handle_call({:mark_unhealthy, model_name, reason}, _from, state) do
    case Map.get(state.models, model_name) do
      nil -> 
        {:reply, {:error, :model_not_found}, state}
      model ->
        previous_status = model.health_status
        
        new_state = update_in(state, [:models, model_name], fn model ->
          model
          |> Map.put(:health_status, :unhealthy)
          |> Map.put(:health_reason, reason)
        end)
        
        # Broadcast model health change event
        event_payload = EventSchemas.model_health_event(
          model_name,
          Map.get(model, :provider, "unknown"),
          :unhealthy,
          previous_status: previous_status,
          reason: reason
        )
        EventBroadcaster.broadcast_async(%{
          topic: EventSchemas.suggest_topic(:model_health_changed),
          payload: event_payload,
          priority: :high,
          metadata: %{component: "model_coordinator", severity: "critical"}
        })
        
        # Notify ContextManager about health change (backward compatibility)
        RubberDuck.ContextManager.update_model_health_warning(RubberDuck.ContextManager, model_name, :unhealthy, reason)
        
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:mark_healthy, model_name}, _from, state) do
    case Map.get(state.models, model_name) do
      nil -> 
        {:reply, {:error, :model_not_found}, state}
      model ->
        previous_status = model.health_status
        
        new_state = update_in(state, [:models, model_name], fn model ->
          model
          |> Map.put(:health_status, :healthy)
          |> Map.put(:health_reason, nil)
        end)
        
        # Broadcast model health change event
        event_payload = EventSchemas.model_health_event(
          model_name,
          Map.get(model, :provider, "unknown"),
          :healthy,
          previous_status: previous_status,
          reason: "Model recovered"
        )
        EventBroadcaster.broadcast_async(%{
          topic: EventSchemas.suggest_topic(:model_health_changed),
          payload: event_payload,
          priority: :normal,
          metadata: %{component: "model_coordinator", severity: "info"}
        })
        
        # Notify ContextManager about health change (backward compatibility)
        RubberDuck.ContextManager.update_model_health_warning(RubberDuck.ContextManager, model_name, :healthy)
        
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      status: :running,
      model_count: map_size(state.models),
      memory: :erlang.process_info(self(), :memory) |> elem(1),
      uptime: System.monotonic_time(:millisecond) - state.start_time
    }
    {:reply, info, state}
  end

  @impl true
  def handle_cast({:track_usage, model_name, status, latency}, state) do
    new_state = update_in(state, [:stats, model_name], fn stats ->
      stats = stats || %{success_count: 0, failure_count: 0, total_latency: 0}
      
      case status do
        :success ->
          stats
          |> Map.update!(:success_count, &(&1 + 1))
          |> Map.update!(:total_latency, &(&1 + latency))
        :failure ->
          Map.update!(stats, :failure_count, &(&1 + 1))
      end
    end)
    
    # Broadcast model usage event
    case Map.get(state.models, model_name) do
      nil -> :ok  # Model not found, skip event
      _model ->
        event_payload = EventSchemas.model_usage_event(
          "system",  # No specific session for this usage tracking
          model_name,
          "inference",
          (if status == :success, do: :completed, else: :failed),
          duration_ms: latency
        )
        EventBroadcaster.broadcast_async(%{
          topic: "model.usage.tracked",
          payload: event_payload,
          priority: :low,
          metadata: %{component: "model_coordinator", tracking: true}
        })
    end
    
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Cleanup logic can be added here if needed
    :ok
  end

  # Private Functions

  defp filter_by_capability(models, nil), do: models
  defp filter_by_capability(models, capability) do
    Enum.filter(models, fn model ->
      capability in Map.get(model, :capabilities, [])
    end)
  end
end