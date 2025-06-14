defmodule RubberDuck.LLMDataMaintenance do
  use GenServer
  require Logger
  
  @moduledoc """
  Background maintenance service for LLM data tables.
  
  Handles periodic cleanup of expired responses, provider status updates,
  data retention policies, and backup procedures for LLM-specific data.
  """
  
  alias RubberDuck.LLMDataManager
  alias RubberDuck.MnesiaManager
  
  # Run maintenance every 4 hours
  @maintenance_interval :timer.hours(4)
  
  # Run backup every 24 hours
  @backup_interval :timer.hours(24)
  
  defstruct [
    :last_cleanup,
    :last_backup,
    :cleanup_count,
    :backup_count,
    :status
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Trigger immediate cleanup of expired data
  """
  def trigger_cleanup do
    GenServer.cast(__MODULE__, :cleanup_now)
  end
  
  @doc """
  Trigger immediate backup
  """
  def trigger_backup(backup_path \\ nil) do
    GenServer.cast(__MODULE__, {:backup_now, backup_path})
  end
  
  @doc """
  Get maintenance statistics
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Get LLM data health metrics
  """
  def get_health_metrics do
    GenServer.call(__MODULE__, :get_health_metrics)
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      last_cleanup: nil,
      last_backup: nil,
      cleanup_count: 0,
      backup_count: 0,
      status: :initializing
    }
    
    # Schedule first maintenance tasks
    schedule_maintenance()
    schedule_backup()
    
    Logger.info("LLM Data Maintenance service started")
    {:ok, %{state | status: :running}}
  end
  
  @impl true
  def handle_cast(:cleanup_now, state) do
    new_state = perform_cleanup(state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:backup_now, backup_path}, state) do
    new_state = perform_backup(state, backup_path)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:scheduled_maintenance, state) do
    Logger.debug("Running scheduled LLM data maintenance")
    
    new_state = perform_cleanup(state)
    
    # Schedule next maintenance
    schedule_maintenance()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:scheduled_backup, state) do
    Logger.debug("Running scheduled LLM data backup")
    
    new_state = perform_backup(state)
    
    # Schedule next backup
    schedule_backup()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      status: state.status,
      last_cleanup: state.last_cleanup,
      last_backup: state.last_backup,
      cleanup_count: state.cleanup_count,
      backup_count: state.backup_count,
      uptime: :erlang.system_time(:millisecond) - (state.last_cleanup || 0)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_health_metrics, _from, state) do
    metrics = calculate_health_metrics()
    {:reply, metrics, state}
  end
  
  # Private Functions
  
  defp perform_cleanup(state) do
    start_time = :erlang.system_time(:millisecond)
    
    try do
      case LLMDataManager.cleanup_expired_data() do
        {:ok, cleanup_stats} ->
          end_time = :erlang.system_time(:millisecond)
          duration = end_time - start_time
          
          Logger.info("LLM data cleanup completed in #{duration}ms: #{inspect(cleanup_stats)}")
          
          %{state | 
            last_cleanup: end_time,
            cleanup_count: state.cleanup_count + 1
          }
        
        {:error, reason} ->
          Logger.error("LLM data cleanup failed: #{inspect(reason)}")
          state
      end
    rescue
      error ->
        Logger.error("LLM data cleanup exception: #{inspect(error)}")
        state
    end
  end
  
  defp perform_backup(state, backup_path \\ nil) do
    start_time = :erlang.system_time(:millisecond)
    
    # Generate backup path if not provided
    backup_path = backup_path || generate_backup_path()
    
    try do
      case MnesiaManager.create_backup(backup_path) do
        :ok ->
          end_time = :erlang.system_time(:millisecond)
          duration = end_time - start_time
          
          Logger.info("LLM data backup completed in #{duration}ms: #{backup_path}")
          
          # Clean up old backups
          cleanup_old_backups()
          
          %{state |
            last_backup: end_time,
            backup_count: state.backup_count + 1
          }
        
        {:error, reason} ->
          Logger.error("LLM data backup failed: #{inspect(reason)}")
          state
      end
    rescue
      error ->
        Logger.error("LLM data backup exception: #{inspect(error)}")
        state
    end
  end
  
  defp calculate_health_metrics do
    try do
      # Get table sizes and memory usage
      response_info = MnesiaManager.get_table_info(:llm_responses)
      provider_info = MnesiaManager.get_table_info(:llm_provider_status)
      
      # Get recent activity stats
      recent_stats = LLMDataManager.get_response_stats(time_range: :timer.hours(24))
      
      # Get provider status counts
      provider_statuses = case LLMDataManager.get_all_provider_status() do
        {:ok, statuses} -> 
          Enum.group_by(statuses, & &1.status) |> Enum.map(fn {status, list} -> {status, length(list)} end) |> Enum.into(%{})
        _ -> 
          %{}
      end
      
      %{
        tables: %{
          llm_responses: response_info,
          llm_provider_status: provider_info
        },
        recent_activity: recent_stats,
        provider_statuses: provider_statuses,
        timestamp: :erlang.system_time(:millisecond)
      }
    rescue
      error ->
        Logger.error("Failed to calculate health metrics: #{inspect(error)}")
        %{error: :calculation_failed, timestamp: :erlang.system_time(:millisecond)}
    end
  end
  
  defp generate_backup_path do
    timestamp = :erlang.system_time(:second)
    date_str = DateTime.from_unix!(timestamp) |> DateTime.to_date() |> Date.to_string()
    
    backup_dir = Application.get_env(:rubber_duck, :backup_dir, "./backups")
    File.mkdir_p!(backup_dir)
    
    Path.join(backup_dir, "llm_data_backup_#{date_str}_#{timestamp}.mnesia")
  end
  
  defp cleanup_old_backups do
    backup_dir = Application.get_env(:rubber_duck, :backup_dir, "./backups")
    retention_days = Application.get_env(:rubber_duck, :backup_retention_days, 7)
    cutoff_time = :erlang.system_time(:second) - (retention_days * 24 * 60 * 60)
    
    try do
      if File.exists?(backup_dir) do
        backup_dir
        |> File.ls!()
        |> Enum.filter(&String.contains?(&1, "llm_data_backup_"))
        |> Enum.each(fn file ->
          file_path = Path.join(backup_dir, file)
          
          case File.stat(file_path) do
            {:ok, %{mtime: mtime}} ->
              file_time = :calendar.datetime_to_gregorian_seconds(mtime) - :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
              
              if file_time < cutoff_time do
                File.rm(file_path)
                Logger.debug("Removed old backup: #{file}")
              end
            _ ->
              :ok
          end
        end)
      end
    rescue
      error ->
        Logger.warning("Failed to cleanup old backups: #{inspect(error)}")
    end
  end
  
  defp schedule_maintenance do
    Process.send_after(self(), :scheduled_maintenance, @maintenance_interval)
  end
  
  defp schedule_backup do
    Process.send_after(self(), :scheduled_backup, @backup_interval)
  end
end