defmodule RubberDuck.CodingAssistant.Engine do
  @moduledoc """
  Base GenServer implementation for coding assistance engines.
  
  This module provides the foundational GenServer behavior that all coding
  assistance engines can build upon. It implements the dual-mode processing
  framework (real-time and batch) and provides infrastructure for health
  monitoring, telemetry, and distributed operation.
  
  ## Features
  
  - Dual-mode processing (real-time < 100ms and batch)
  - Health monitoring and self-reporting
  - Telemetry integration for performance metrics
  - Graceful error handling and recovery
  - Process registry integration for discovery
  - Inter-engine communication support
  
  ## Usage
  
  Engines should implement the `EngineBehaviour` callbacks and use this
  module as their GenServer base:
  
      defmodule MyEngine do
        use RubberDuck.CodingAssistant.Engine
        
        @impl true
        def init(config) do
          # Engine-specific initialization
          {:ok, %{engine_config: config}}
        end
        
        @impl true
        def process_real_time(data, state) do
          # Real-time processing implementation
        end
        
        # ... other callbacks
      end
  """

  alias RubberDuck.CodingAssistant.EngineBehaviour
  
  @type engine_state :: %{
    engine_module: module(),
    engine_state: EngineBehaviour.state(),
    config: EngineBehaviour.config(),
    statistics: map(),
    health_status: EngineBehaviour.health_status(),
    last_health_check: DateTime.t() | nil,
    processing_mode: :idle | :real_time | :batch
  }

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      use GenServer
      @behaviour RubberDuck.CodingAssistant.EngineBehaviour
      
      alias RubberDuck.CodingAssistant.Engine

      def start_link(config \\ %{}) do
        name = Keyword.get(config, :name, __MODULE__)
        GenServer.start_link(__MODULE__, {__MODULE__, config}, name: name)
      end

      def child_spec(config) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [config]},
          restart: :permanent,
          shutdown: 5_000,
          type: :worker
        }
      end

      @impl GenServer
      def init({engine_module, config}) do
        Engine.init_engine(engine_module, config)
      end

      @impl GenServer
      def handle_call(request, from, state) do
        Engine.handle_engine_call(request, from, state)
      end

      @impl GenServer
      def handle_cast(request, state) do
        Engine.handle_engine_cast(request, state)
      end

      @impl GenServer
      def handle_info(message, state) do
        Engine.handle_engine_info(message, state)
      end

      @impl GenServer
      def terminate(reason, state) do
        Engine.terminate_engine(reason, state)
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  Initialize the engine GenServer with the implementing module and configuration.
  """
  def init_engine(engine_module, config) do
    case engine_module.init(config) do
      {:ok, engine_state} ->
        state = %{
          engine_module: engine_module,
          engine_state: engine_state,
          config: config,
          statistics: init_statistics(),
          health_status: :healthy,
          last_health_check: DateTime.utc_now(),
          processing_mode: :idle
        }
        
        # Schedule health checks
        schedule_health_check()
        
        # Register engine for discovery
        register_engine(engine_module, config)
        
        {:ok, state}
        
      {:error, reason} ->
        {:stop, {:init_failed, reason}}
    end
  end

  @doc """
  Handle synchronous calls to the engine.
  """
  def handle_engine_call(request, from, state) do
    case request do
      {:process_real_time, data} ->
        handle_real_time_processing(data, from, state)
        
      {:process_batch, data_list} ->
        handle_batch_processing(data_list, from, state)
        
      :capabilities ->
        capabilities = state.engine_module.capabilities()
        {:reply, capabilities, state}
        
      :health_status ->
        {:reply, state.health_status, state}
        
      :statistics ->
        {:reply, state.statistics, state}
        
      {:handle_engine_event, event} ->
        handle_engine_event(event, from, state)
        
      _ ->
        {:reply, {:error, :unknown_request}, state}
    end
  end

  @doc """
  Handle asynchronous casts to the engine.
  """
  def handle_engine_cast(request, state) do
    case request do
      {:process_batch_async, data_list} ->
        handle_batch_processing_async(data_list, state)
        
      {:engine_event, event} ->
        handle_engine_event_async(event, state)
        
      :force_health_check ->
        perform_health_check(state)
        
      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Handle info messages to the engine.
  """
  def handle_engine_info(message, state) do
    case message do
      :health_check_timer ->
        new_state = perform_health_check(state)
        schedule_health_check()
        {:noreply, new_state}
        
      {:telemetry, event_name, measurements, metadata} ->
        handle_telemetry_event(event_name, measurements, metadata, state)
        
      _ ->
        {:noreply, state}
    end
  end

  @doc """
  Terminate the engine gracefully.
  """
  def terminate_engine(reason, state) do
    # Call engine-specific terminate
    state.engine_module.terminate(reason, state.engine_state)
    
    # Unregister from discovery
    unregister_engine(state.engine_module)
    
    # Emit final telemetry
    emit_telemetry([:engine, :terminated], %{reason: reason}, %{
      engine: state.engine_module,
      uptime: calculate_uptime(state)
    })
    
    :ok
  end

  # Private implementation functions

  defp handle_real_time_processing(data, from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Enforce real-time constraint (100ms timeout)
    task = Task.async(fn ->
      state.engine_module.process_real_time(data, state.engine_state)
    end)
    
    case Task.yield(task, 100) || Task.shutdown(task) do
      {:ok, {:ok, result, new_engine_state}} ->
        processing_time = System.monotonic_time(:microsecond) - start_time
        
        # Update statistics
        new_statistics = update_statistics(state.statistics, :real_time, processing_time, :success)
        
        # Emit telemetry
        emit_telemetry([:engine, :real_time, :complete], %{
          processing_time: processing_time,
          data_size: calculate_data_size(data)
        }, %{engine: state.engine_module, status: :success})
        
        new_state = %{state |
          engine_state: new_engine_state,
          statistics: new_statistics,
          processing_mode: :idle
        }
        
        # Add processing time to result
        enhanced_result = Map.put(result, :processing_time, processing_time)
        
        {:reply, {:ok, enhanced_result}, new_state}
        
      {:ok, {:error, reason, new_engine_state}} ->
        processing_time = System.monotonic_time(:microsecond) - start_time
        new_statistics = update_statistics(state.statistics, :real_time, processing_time, :error)
        
        emit_telemetry([:engine, :real_time, :error], %{
          processing_time: processing_time
        }, %{engine: state.engine_module, error: reason})
        
        new_state = %{state |
          engine_state: new_engine_state,
          statistics: new_statistics,
          processing_mode: :idle
        }
        
        {:reply, {:error, reason}, new_state}
        
      nil ->
        # Timeout occurred
        new_statistics = update_statistics(state.statistics, :real_time, 100_000, :timeout)
        
        emit_telemetry([:engine, :real_time, :timeout], %{}, %{
          engine: state.engine_module
        })
        
        new_state = %{state |
          statistics: new_statistics,
          processing_mode: :idle
        }
        
        {:reply, {:error, :timeout}, new_state}
    end
  end

  defp handle_batch_processing(data_list, from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case state.engine_module.process_batch(data_list, state.engine_state) do
      {:ok, results, new_engine_state} ->
        processing_time = System.monotonic_time(:microsecond) - start_time
        
        new_statistics = update_statistics(state.statistics, :batch, processing_time, :success)
        
        emit_telemetry([:engine, :batch, :complete], %{
          processing_time: processing_time,
          batch_size: length(data_list),
          results_count: length(results)
        }, %{engine: state.engine_module, status: :success})
        
        new_state = %{state |
          engine_state: new_engine_state,
          statistics: new_statistics,
          processing_mode: :idle
        }
        
        {:reply, {:ok, results}, new_state}
        
      {:error, reason, new_engine_state} ->
        processing_time = System.monotonic_time(:microsecond) - start_time
        new_statistics = update_statistics(state.statistics, :batch, processing_time, :error)
        
        emit_telemetry([:engine, :batch, :error], %{
          processing_time: processing_time,
          batch_size: length(data_list)
        }, %{engine: state.engine_module, error: reason})
        
        new_state = %{state |
          engine_state: new_engine_state,
          statistics: new_statistics,
          processing_mode: :idle
        }
        
        {:reply, {:error, reason}, new_state}
    end
  end

  defp handle_batch_processing_async(data_list, state) do
    new_state = %{state | processing_mode: :batch}
    
    Task.start(fn ->
      case state.engine_module.process_batch(data_list, state.engine_state) do
        {:ok, results, _new_engine_state} ->
          emit_telemetry([:engine, :batch, :async_complete], %{
            batch_size: length(data_list),
            results_count: length(results)
          }, %{engine: state.engine_module})
          
        {:error, reason, _new_engine_state} ->
          emit_telemetry([:engine, :batch, :async_error], %{
            batch_size: length(data_list)
          }, %{engine: state.engine_module, error: reason})
      end
    end)
    
    {:noreply, new_state}
  end

  defp handle_engine_event(event, from, state) do
    case state.engine_module.handle_engine_event(event, state.engine_state) do
      {:ok, new_engine_state} ->
        new_state = %{state | engine_state: new_engine_state}
        {:reply, :ok, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp handle_engine_event_async(event, state) do
    case state.engine_module.handle_engine_event(event, state.engine_state) do
      {:ok, new_engine_state} ->
        {:noreply, %{state | engine_state: new_engine_state}}
        
      {:error, _reason} ->
        {:noreply, state}
    end
  end

  defp perform_health_check(state) do
    health_status = state.engine_module.health_check(state.engine_state)
    
    # Update health status if changed
    new_state = if health_status != state.health_status do
      emit_telemetry([:engine, :health, :status_change], %{}, %{
        engine: state.engine_module,
        old_status: state.health_status,
        new_status: health_status
      })
      
      %{state | 
        health_status: health_status,
        last_health_check: DateTime.utc_now()
      }
    else
      %{state | last_health_check: DateTime.utc_now()}
    end
    
    new_state
  end

  defp schedule_health_check do
    # Schedule next health check in 30 seconds
    Process.send_after(self(), :health_check_timer, 30_000)
  end

  defp register_engine(engine_module, config) do
    # Register with engine registry for discovery
    case Registry.register(RubberDuck.CodingAssistant.EngineRegistry, engine_module, %{
      pid: self(),
      capabilities: engine_module.capabilities(),
      config: config,
      started_at: DateTime.utc_now()
    }) do
      {:ok, _pid} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
    end
  end

  defp unregister_engine(engine_module) do
    Registry.unregister(RubberDuck.CodingAssistant.EngineRegistry, engine_module)
  end

  defp init_statistics do
    %{
      real_time: %{
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        timeout_requests: 0,
        total_processing_time: 0,
        average_processing_time: 0.0,
        min_processing_time: nil,
        max_processing_time: nil
      },
      batch: %{
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        total_processing_time: 0,
        average_processing_time: 0.0,
        total_items_processed: 0
      },
      started_at: DateTime.utc_now()
    }
  end

  defp update_statistics(stats, mode, processing_time, result) do
    mode_stats = Map.get(stats, mode)
    
    new_mode_stats = case result do
      :success ->
        update_success_stats(mode_stats, processing_time, mode)
      :error ->
        update_error_stats(mode_stats, processing_time)
      :timeout ->
        update_timeout_stats(mode_stats, processing_time)
    end
    
    Map.put(stats, mode, new_mode_stats)
  end

  defp update_success_stats(stats, processing_time, mode) do
    new_total = stats.total_requests + 1
    new_successful = stats.successful_requests + 1
    new_total_time = stats.total_processing_time + processing_time
    new_avg_time = new_total_time / new_total
    
    new_min = case stats.min_processing_time do
      nil -> processing_time
      min -> min(min, processing_time)
    end
    
    new_max = case stats.max_processing_time do
      nil -> processing_time
      max -> max(max, processing_time)
    end
    
    base_updates = %{
      total_requests: new_total,
      successful_requests: new_successful,
      total_processing_time: new_total_time,
      average_processing_time: new_avg_time,
      min_processing_time: new_min,
      max_processing_time: new_max
    }
    
    # Add mode-specific updates
    mode_specific = case mode do
      :batch -> %{total_items_processed: stats.total_items_processed + 1}
      _ -> %{}
    end
    
    Map.merge(stats, Map.merge(base_updates, mode_specific))
  end

  defp update_error_stats(stats, processing_time) do
    new_total = stats.total_requests + 1
    new_failed = stats.failed_requests + 1
    new_total_time = stats.total_processing_time + processing_time
    new_avg_time = new_total_time / new_total
    
    %{stats |
      total_requests: new_total,
      failed_requests: new_failed,
      total_processing_time: new_total_time,
      average_processing_time: new_avg_time
    }
  end

  defp update_timeout_stats(stats, processing_time) do
    new_total = stats.total_requests + 1
    new_timeout = Map.get(stats, :timeout_requests, 0) + 1
    new_total_time = stats.total_processing_time + processing_time
    new_avg_time = new_total_time / new_total
    
    %{stats |
      total_requests: new_total,
      timeout_requests: new_timeout,
      total_processing_time: new_total_time,
      average_processing_time: new_avg_time
    }
  end

  defp emit_telemetry(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  defp handle_telemetry_event(event_name, measurements, metadata, state) do
    # Forward telemetry events to interested parties
    # This can be used for monitoring, alerting, etc.
    {:noreply, state}
  end

  defp calculate_data_size(data) when is_binary(data), do: byte_size(data)
  defp calculate_data_size(data) when is_list(data), do: length(data)
  defp calculate_data_size(data) when is_map(data), do: map_size(data)
  defp calculate_data_size(_data), do: 1

  defp calculate_uptime(state) do
    DateTime.diff(DateTime.utc_now(), state.statistics.started_at, :millisecond)
  end
end