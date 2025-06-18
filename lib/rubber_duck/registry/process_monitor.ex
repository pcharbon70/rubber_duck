defmodule RubberDuck.Registry.ProcessMonitor do
  @moduledoc """
  Process monitoring and automatic cleanup for the global registry.
  Handles process lifecycle events, automatic re-registration, and garbage collection
  of dead processes from the distributed registry.
  """
  use GenServer
  require Logger

  alias RubberDuck.Registry.GlobalRegistry

  defstruct [
    :monitored_processes,
    :cleanup_interval,
    :metrics,
    :auto_recovery
  ]

  @cleanup_interval 60_000  # 1 minute
  @max_recovery_attempts 3

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a process to monitoring with automatic cleanup.
  """
  def add_monitoring(name, pid, monitor_ref \\ nil) do
    GenServer.cast(__MODULE__, {:add_monitoring, name, pid, monitor_ref})
  end

  @doc """
  Removes a process from monitoring.
  """
  def remove_monitoring(name) do
    GenServer.cast(__MODULE__, {:remove_monitoring, name})
  end

  @doc """
  Gets monitoring statistics.
  """
  def get_monitoring_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Triggers manual cleanup of dead processes.
  """
  def trigger_cleanup do
    GenServer.cast(__MODULE__, :trigger_cleanup)
  end

  @doc """
  Sets auto-recovery configuration for a process.
  """
  def configure_auto_recovery(name, recovery_config) do
    GenServer.cast(__MODULE__, {:configure_recovery, name, recovery_config})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Global Registry Process Monitor")
    
    state = %__MODULE__{
      monitored_processes: %{},
      cleanup_interval: Keyword.get(opts, :cleanup_interval, @cleanup_interval),
      auto_recovery: Keyword.get(opts, :auto_recovery, true),
      metrics: initialize_metrics()
    }
    
    # Schedule periodic cleanup
    schedule_cleanup(state.cleanup_interval)
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:add_monitoring, name, pid, monitor_ref}, state) do
    # Create monitor reference if not provided
    ref = monitor_ref || Process.monitor(pid)
    
    monitoring_info = %{
      pid: pid,
      monitor_ref: ref,
      registered_at: System.monotonic_time(:millisecond),
      node: node(pid),
      recovery_attempts: 0,
      last_health_check: System.monotonic_time(:millisecond)
    }
    
    new_monitored = Map.put(state.monitored_processes, name, monitoring_info)
    new_metrics = update_monitoring_metrics(state.metrics, :process_added)
    
    Logger.debug("Added monitoring for process #{inspect(name)} (#{inspect(pid)})")
    
    {:noreply, %{state | monitored_processes: new_monitored, metrics: new_metrics}}
  end

  @impl true
  def handle_cast({:remove_monitoring, name}, state) do
    case Map.get(state.monitored_processes, name) do
      nil ->
        {:noreply, state}
      
      monitoring_info ->
        # Demonitor the process
        Process.demonitor(monitoring_info.monitor_ref, [:flush])
        
        new_monitored = Map.delete(state.monitored_processes, name)
        new_metrics = update_monitoring_metrics(state.metrics, :process_removed)
        
        Logger.debug("Removed monitoring for process #{inspect(name)}")
        
        {:noreply, %{state | monitored_processes: new_monitored, metrics: new_metrics}}
    end
  end

  @impl true
  def handle_cast(:trigger_cleanup, state) do
    new_state = perform_cleanup(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:configure_recovery, name, recovery_config}, state) do
    case Map.get(state.monitored_processes, name) do
      nil ->
        Logger.warning("Cannot configure recovery for unmonitored process: #{inspect(name)}")
        {:noreply, state}
      
      monitoring_info ->
        updated_info = Map.put(monitoring_info, :recovery_config, recovery_config)
        new_monitored = Map.put(state.monitored_processes, name, updated_info)
        
        Logger.debug("Configured auto-recovery for #{inspect(name)}")
        {:noreply, %{state | monitored_processes: new_monitored}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_monitored: map_size(state.monitored_processes),
      metrics: state.metrics,
      processes_by_node: group_processes_by_node(state.monitored_processes),
      health_summary: calculate_health_summary(state.monitored_processes)
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Find the process that went down
    case find_process_by_ref(state.monitored_processes, ref) do
      nil ->
        Logger.debug("Received DOWN message for unknown process: #{inspect(pid)}")
        {:noreply, state}
      
      {name, monitoring_info} ->
        Logger.warning("Monitored process #{inspect(name)} went down: #{inspect(reason)}")
        
        new_state = handle_process_down(state, name, monitoring_info, reason)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:cleanup_processes, state) do
    new_state = perform_cleanup(state)
    
    # Schedule next cleanup
    schedule_cleanup(state.cleanup_interval)
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:retry_recovery, name}, state) do
    case Map.get(state.monitored_processes, name) do
      nil ->
        {:noreply, state}
      
      monitoring_info ->
        new_state = attempt_process_recovery(state, name, monitoring_info)
        {:noreply, new_state}
    end
  end

  # Private functions

  defp handle_process_down(state, name, monitoring_info, reason) do
    # Update metrics
    new_metrics = update_monitoring_metrics(state.metrics, :process_down)
    
    # Remove from global registry
    GlobalRegistry.unregister(name)
    
    # Attempt recovery if configured
    if state.auto_recovery and should_attempt_recovery?(monitoring_info, reason) do
      schedule_recovery_attempt(name, monitoring_info.recovery_attempts)
      
      # Keep monitoring info for recovery attempts
      updated_info = %{monitoring_info | 
        recovery_attempts: monitoring_info.recovery_attempts + 1,
        last_failure: %{reason: reason, timestamp: System.monotonic_time(:millisecond)}
      }
      
      new_monitored = Map.put(state.monitored_processes, name, updated_info)
      %{state | monitored_processes: new_monitored, metrics: new_metrics}
    else
      # Remove from monitoring
      new_monitored = Map.delete(state.monitored_processes, name)
      %{state | monitored_processes: new_monitored, metrics: new_metrics}
    end
  end

  defp should_attempt_recovery?(monitoring_info, reason) do
    # Don't recover if too many attempts already made
    if monitoring_info.recovery_attempts >= @max_recovery_attempts do
      Logger.warning("Max recovery attempts reached for process, giving up")
      false
    else
      # Don't recover from intentional shutdowns
      case reason do
        :normal -> false
        :shutdown -> false
        {:shutdown, _} -> false
        _ -> true
      end
    end
  end

  defp schedule_recovery_attempt(name, attempt_count) do
    # Exponential backoff: 1s, 2s, 4s, 8s, etc.
    delay = min(30_000, :math.pow(2, attempt_count) * 1000) |> round()
    
    Logger.info("Scheduling recovery attempt #{attempt_count + 1} for #{inspect(name)} in #{delay}ms")
    Process.send_after(self(), {:retry_recovery, name}, delay)
  end

  defp attempt_process_recovery(state, name, monitoring_info) do
    Logger.info("Attempting recovery for process #{inspect(name)}")
    
    case Map.get(monitoring_info, :recovery_config) do
      nil ->
        Logger.warning("No recovery configuration for #{inspect(name)}")
        # Remove from monitoring
        new_monitored = Map.delete(state.monitored_processes, name)
        %{state | monitored_processes: new_monitored}
      
      recovery_config ->
        case execute_recovery(name, recovery_config, monitoring_info) do
          {:ok, new_pid} ->
            Logger.info("Successfully recovered process #{inspect(name)}")
            
            # Update monitoring with new PID
            new_ref = Process.monitor(new_pid)
            updated_info = %{monitoring_info |
              pid: new_pid,
              monitor_ref: new_ref,
              recovery_attempts: 0,
              last_recovery: System.monotonic_time(:millisecond),
              node: node(new_pid)
            }
            
            new_monitored = Map.put(state.monitored_processes, name, updated_info)
            new_metrics = update_monitoring_metrics(state.metrics, :process_recovered)
            
            %{state | monitored_processes: new_monitored, metrics: new_metrics}
          
          {:error, reason} ->
            Logger.error("Recovery failed for #{inspect(name)}: #{inspect(reason)}")
            
            # Schedule another attempt if under limit
            if monitoring_info.recovery_attempts < @max_recovery_attempts - 1 do
              schedule_recovery_attempt(name, monitoring_info.recovery_attempts)
              state
            else
              # Give up and remove from monitoring
              new_monitored = Map.delete(state.monitored_processes, name)
              new_metrics = update_monitoring_metrics(state.metrics, :recovery_failed)
              %{state | monitored_processes: new_monitored, metrics: new_metrics}
            end
        end
    end
  end

  defp execute_recovery(name, recovery_config, monitoring_info) do
    try do
      case recovery_config do
        %{module: module, function: function, args: args} ->
          case apply(module, function, [name, monitoring_info | args]) do
            {:ok, pid} when is_pid(pid) ->
              # Re-register in global registry
              case GlobalRegistry.register_persistent(name, pid, recovery_config[:metadata] || %{}) do
                :ok -> {:ok, pid}
                error -> error
              end
            
            other ->
              {:error, {:invalid_recovery_result, other}}
          end
        
        %{supervisor: supervisor, child_spec: child_spec} ->
          # Restart via supervisor
          case Supervisor.start_child(supervisor, child_spec) do
            {:ok, pid} when is_pid(pid) ->
              GlobalRegistry.register_persistent(name, pid, recovery_config[:metadata] || %{})
              {:ok, pid}
            
            {:ok, pid, _info} when is_pid(pid) ->
              GlobalRegistry.register_persistent(name, pid, recovery_config[:metadata] || %{})
              {:ok, pid}
            
            error ->
              error
          end
        
        _ ->
          {:error, :invalid_recovery_config}
      end
    rescue
      e ->
        {:error, {:recovery_exception, e}}
    end
  end

  defp perform_cleanup(state) do
    Logger.debug("Performing registry cleanup")
    
    # Check all monitored processes for health
    {healthy_processes, dead_processes} = check_process_health(state.monitored_processes)
    
    # Clean up dead processes
    Enum.each(dead_processes, fn {name, _monitoring_info} ->
      Logger.debug("Cleaning up dead process: #{inspect(name)}")
      GlobalRegistry.unregister(name)
    end)
    
    # Update metrics
    cleanup_count = length(dead_processes)
    new_metrics = state.metrics
    |> update_monitoring_metrics(:cleanup_performed)
    |> Map.update(:processes_cleaned, cleanup_count, &(&1 + cleanup_count))
    
    if cleanup_count > 0 do
      Logger.info("Cleaned up #{cleanup_count} dead processes")
    end
    
    %{state | monitored_processes: healthy_processes, metrics: new_metrics}
  end

  defp check_process_health(monitored_processes) do
    Enum.split_with(monitored_processes, fn {_name, monitoring_info} ->
      Process.alive?(monitoring_info.pid)
    end)
  end

  defp find_process_by_ref(monitored_processes, ref) do
    Enum.find(monitored_processes, fn {_name, monitoring_info} ->
      monitoring_info.monitor_ref == ref
    end)
  end

  defp group_processes_by_node(monitored_processes) do
    Enum.group_by(monitored_processes, fn {_name, monitoring_info} ->
      monitoring_info.node
    end)
    |> Enum.map(fn {node, processes} ->
      {node, length(processes)}
    end)
    |> Enum.into(%{})
  end

  defp calculate_health_summary(monitored_processes) do
    total = map_size(monitored_processes)
    
    if total == 0 do
      %{total: 0, healthy: 0, unhealthy: 0, health_ratio: 1.0}
    else
      {healthy, unhealthy} = check_process_health(monitored_processes)
      healthy_count = length(healthy)
      unhealthy_count = length(unhealthy)
      
      %{
        total: total,
        healthy: healthy_count,
        unhealthy: unhealthy_count,
        health_ratio: healthy_count / total
      }
    end
  end

  defp initialize_metrics do
    %{
      processes_added: 0,
      processes_removed: 0,
      processes_down: 0,
      processes_recovered: 0,
      recovery_failed: 0,
      cleanup_performed: 0,
      processes_cleaned: 0,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  defp update_monitoring_metrics(metrics, event) do
    Map.update(metrics, event, 1, &(&1 + 1))
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_processes, interval)
  end
end