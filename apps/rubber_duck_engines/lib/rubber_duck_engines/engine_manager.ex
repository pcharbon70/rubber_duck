defmodule RubberDuckEngines.EngineManager do
  @moduledoc """
  Central manager for analysis engines in the RubberDuck system.
  
  Handles engine discovery, registration, lifecycle management,
  and request routing to appropriate engines.
  """

  use RubberDuckCore.BaseServer

  alias RubberDuckCore.{Analysis, PubSub}
  alias RubberDuckEngines.EngineSupervisor

  # Client API

  @doc """
  Registers an engine with the manager.
  """
  def register_engine(manager \\ __MODULE__, engine_module, config \\ %{}) do
    GenServer.call(via_tuple(manager), {:register_engine, engine_module, config})
  end

  @doc """
  Unregisters an engine from the manager.
  """
  def unregister_engine(manager \\ __MODULE__, engine_module) do
    GenServer.call(via_tuple(manager), {:unregister_engine, engine_module})
  end

  @doc """
  Lists all registered engines and their capabilities.
  """
  def list_engines(manager \\ __MODULE__) do
    GenServer.call(via_tuple(manager), :list_engines)
  end

  @doc """
  Submits an analysis request to the appropriate engine.
  """
  def analyze(manager \\ __MODULE__, analysis_request) do
    GenServer.call(via_tuple(manager), {:analyze, analysis_request}, 30_000)
  end

  @doc """
  Gets the health status of all engines.
  """
  def health_status(manager \\ __MODULE__) do
    GenServer.call(via_tuple(manager), :health_status)
  end

  @doc """
  Finds engines capable of handling a specific analysis type.
  """
  def find_engines_for(manager \\ __MODULE__, analysis_type) do
    GenServer.call(via_tuple(manager), {:find_engines_for, analysis_type})
  end

  # Server callbacks

  def initial_state(_args) do
    # Subscribe to analysis requests from core
    PubSub.subscribe("analysis_requests")
    
    %{
      engines: %{},              # engine_module => %{pid, capabilities, config}
      engine_health: %{},        # engine_module => health_info
      request_queue: :queue.new(),
      metrics: %{
        total_requests: 0,
        successful_analyses: 0,
        failed_analyses: 0
      }
    }
  end

  @impl true
  def handle_call({:register_engine, engine_module, config}, _from, state) do
    case start_engine(engine_module, config) do
      {:ok, pid} ->
        # Get engine capabilities
        capabilities = GenServer.call(pid, :capabilities)
        
        engine_info = %{
          pid: pid,
          capabilities: capabilities,
          config: config,
          registered_at: DateTime.utc_now()
        }
        
        new_engines = Map.put(state.engines, engine_module, engine_info)
        new_state = %{state | engines: new_engines}
        
        {:reply, {:ok, pid}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unregister_engine, engine_module}, _from, state) do
    case Map.get(state.engines, engine_module) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      %{pid: pid} ->
        GenServer.stop(pid)
        new_engines = Map.delete(state.engines, engine_module)
        new_health = Map.delete(state.engine_health, engine_module)
        new_state = %{state | engines: new_engines, engine_health: new_health}
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:list_engines, _from, state) do
    engines_info = 
      state.engines
      |> Enum.map(fn {module, info} ->
        %{
          module: module,
          capabilities: info.capabilities,
          registered_at: info.registered_at,
          health: Map.get(state.engine_health, module, %{status: :unknown})
        }
      end)
    
    {:reply, engines_info, state}
  end

  def handle_call({:analyze, analysis_request}, _from, state) do
    case route_analysis_request(analysis_request, state) do
      {:ok, result} ->
        new_metrics = update_metrics(state.metrics, :success)
        new_state = %{state | metrics: new_metrics}
        {:reply, {:ok, result}, new_state}
      
      {:error, reason} ->
        new_metrics = update_metrics(state.metrics, :failure)
        new_state = %{state | metrics: new_metrics}
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:health_status, _from, state) do
    health_checks = 
      state.engines
      |> Enum.map(fn {module, %{pid: pid}} ->
        try do
          health = GenServer.call(pid, :health_check, 5_000)
          {module, health}
        catch
          :exit, _ -> {module, %{status: :unhealthy, diagnostics: %{error: "unreachable"}}}
        end
      end)
      |> Map.new()
    
    new_state = %{state | engine_health: health_checks}
    
    overall_status = determine_overall_health(health_checks)
    result = %{
      overall: overall_status,
      engines: health_checks,
      metrics: state.metrics
    }
    
    {:reply, result, new_state}
  end

  def handle_call({:find_engines_for, analysis_type}, _from, state) do
    matching_engines = 
      state.engines
      |> Enum.filter(fn {_module, info} ->
        Enum.any?(info.capabilities, fn capability ->
          analysis_type in capability.input_types
        end)
      end)
      |> Enum.map(fn {module, _info} -> module end)
    
    {:reply, matching_engines, state}
  end

  # Handle analysis requests from PubSub
  @impl true
  def handle_info({:pubsub_event, "analysis_requests", event}, state) do
    case event.type do
      :analysis_requested ->
        analysis_request = event.data.analysis_request
        
        # Process async to avoid blocking
        Task.start(fn ->
          case route_analysis_request(analysis_request, state) do
            {:ok, result} ->
              PubSub.broadcast("analysis_results", :analysis_completed, %{
                analysis_id: analysis_request.id,
                result: result
              })
            
            {:error, reason} ->
              PubSub.broadcast("analysis_results", :analysis_failed, %{
                analysis_id: analysis_request.id,
                error: reason
              })
          end
        end)
        
        {:noreply, state}
      
      _ ->
        {:noreply, state}
    end
  end

  # Private functions

  defp start_engine(engine_module, config) do
    EngineSupervisor.start_engine(engine_module, config)
  end

  defp route_analysis_request(%Analysis{type: analysis_type} = request, state) do
    # Find engines that can handle this analysis type
    capable_engines = 
      state.engines
      |> Enum.filter(fn {_module, info} ->
        Enum.any?(info.capabilities, fn capability ->
          analysis_type in capability.input_types
        end)
      end)
    
    case capable_engines do
      [] ->
        {:error, "No engines available for analysis type: #{analysis_type}"}
      
      [{_module, %{pid: pid}} | _] ->
        # For now, use the first available engine
        # TODO: Implement load balancing and engine selection strategy
        try do
          GenServer.call(pid, {:analyze, request}, 30_000)
        catch
          :exit, reason -> {:error, "Engine call failed: #{inspect(reason)}"}
        end
    end
  end

  defp update_metrics(metrics, :success) do
    %{metrics | 
      total_requests: metrics.total_requests + 1,
      successful_analyses: metrics.successful_analyses + 1
    }
  end

  defp update_metrics(metrics, :failure) do
    %{metrics | 
      total_requests: metrics.total_requests + 1,
      failed_analyses: metrics.failed_analyses + 1
    }
  end

  defp determine_overall_health(health_checks) do
    statuses = health_checks |> Map.values() |> Enum.map(& &1.status)
    
    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :degraded
      true -> :healthy
    end
  end

end