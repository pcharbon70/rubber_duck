defmodule RubberDuck.Agents.ShortTermMemoryAgent do
  @moduledoc """
  Short-Term Memory Agent for managing fast access to recent conversation memory.
  
  This agent provides:
  - In-memory storage using ETS tables for ultra-fast access
  - Multiple indexing strategies (by user, session, time)
  - TTL-based expiration and automatic cleanup
  - Memory analytics and monitoring
  - Integration with Memory.Interaction resource
  
  ## Available Actions
  
  - `store_memory` - Store memory item with TTL
  - `get_memory` - Retrieve memory item by ID
  - `search_by_user` - Search items by user ID
  - `search_by_session` - Search items by user and session
  - `cleanup_expired` - Remove expired items
  - `get_analytics` - Get memory analytics
  - `store_with_persistence` - Store with Ash persistence
  
  ## Configuration
  
  - `ttl_seconds`: Time-to-live for memory items (default: 3600)
  - `max_items`: Maximum items before LRU eviction (default: 10000)
  - `cleanup_interval`: Cleanup timer interval in ms (default: 60000)
  """
  
  use Jido.Agent,
    name: "short_term_memory",
    description: "Manages fast access to recent conversation memory",
    schema: [
      # Storage structures
      memory_store: [type: :map, default: %{}],
      indexes: [type: :map, default: %{
        by_user: %{},
        by_session: %{},
        by_time: %{}
      }],
      
      # Metrics tracking
      metrics: [type: :map, default: %{
        total_items: 0,
        cache_hits: 0,
        cache_misses: 0,
        memory_usage_bytes: 0,
        avg_item_size: 0.0,
        last_cleanup: nil
      }],
      
      # Configuration
      config: [type: :map, default: %{
        ttl_seconds: 3600,
        max_items: 10000,
        cleanup_interval: 60000
      }],
      
      # ETS table references
      ets_tables: [type: :map, default: %{}],
      
      # Access tracking
      access_patterns: [type: {:list, :map}, default: []]
    ],
    actions: [
      RubberDuck.Jido.Actions.ShortTermMemory.StoreMemoryAction,
      RubberDuck.Jido.Actions.ShortTermMemory.GetMemoryAction,
      RubberDuck.Jido.Actions.ShortTermMemory.SearchByUserAction,
      RubberDuck.Jido.Actions.ShortTermMemory.SearchBySessionAction,
      RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction,
      RubberDuck.Jido.Actions.ShortTermMemory.GetAnalyticsAction,
      RubberDuck.Jido.Actions.ShortTermMemory.StoreWithPersistenceAction
    ]
  
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  require Logger
  
  # alias RubberDuck.Memory  # Commented out as not currently used
  
  # Lifecycle callbacks
  
  @impl Jido.Agent
  def mount(agent, opts \\ []) do
    ErrorHandling.safe_execute(fn ->
      Logger.info("Mounting short-term memory agent", agent_id: agent.id)
      
      # Initialize configuration with provided options
      case safe_merge_config(agent.state.config, opts) do
        {:ok, config} ->
          updated_state = Map.put(agent.state, :config, config)
          agent = Map.put(agent, :state, updated_state)
          
          # Initialize ETS tables with error handling
          case safe_initialize_ets_tables(agent) do
            {:ok, agent} ->
              # Schedule cleanup timer
              safe_schedule_cleanup(agent.state.config.cleanup_interval)
              Logger.info("Short-term memory agent mounted successfully", agent_id: agent.id)
              {:ok, agent}
              
            {:error, error} -> ErrorHandling.categorize_error(error)
          end
          
        {:error, error} -> ErrorHandling.categorize_error(error)
      end
    end)
  end
  
  @impl Jido.Agent
  def shutdown(agent, reason) do
    ErrorHandling.safe_execute(fn ->
      Logger.info("ShortTermMemoryAgent shutting down", agent_id: agent.id, reason: reason)
      
      # Clean up ETS tables with error handling
      case safe_cleanup_ets_tables(agent) do
        :ok -> 
          Logger.info("Short-term memory agent shutdown completed", agent_id: agent.id)
          {:ok, agent}
        {:error, error} -> 
          Logger.warning("Error during shutdown cleanup", agent_id: agent.id, error: inspect(error))
          {:ok, agent}  # Continue shutdown even if cleanup fails
      end
    end)
  end
  
  # Convenience functions for accessing agent data
  
  def get_state(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :get_state)
  end
  
  def store_memory(agent_pid, params) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid_and_params(agent_pid, params) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.StoreMemoryAction, params) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def get_memory(agent_pid, params) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid_and_params(agent_pid, params) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.GetMemoryAction, params) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def search_by_user(agent_pid, params) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid_and_params(agent_pid, params) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.SearchByUserAction, params) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def search_by_session(agent_pid, params) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid_and_params(agent_pid, params) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.SearchBySessionAction, params) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def cleanup_expired(agent_pid) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid(agent_pid) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction, %{}) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def get_analytics(agent_pid) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid(agent_pid) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.GetAnalyticsAction, %{}) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  def store_with_persistence(agent_pid, params) when is_pid(agent_pid) do
    ErrorHandling.safe_execute(fn ->
      case validate_pid_and_params(agent_pid, params) do
        :ok ->
          case __MODULE__.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.StoreWithPersistenceAction, params) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> ErrorHandling.categorize_error(reason)
          end
        error -> error
      end
    end)
  end
  
  # Support for get_state call
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    case ErrorHandling.safe_execute(fn -> state.agent.state end) do
      {:ok, agent_state} -> {:reply, agent_state, state}
      {:error, error} -> 
        Logger.error("Failed to get agent state: #{inspect(error)}")
        {:reply, %{error: "Failed to retrieve state"}, state}
    end
  end
  
  # Timer-based cleanup
  @impl GenServer
  def handle_info(:cleanup_expired, state) do
    case ErrorHandling.safe_execute(fn ->
      case __MODULE__.cmd(self(), RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction, %{}) do
        {:ok, result} ->
          Logger.debug("Automatic cleanup completed", items_cleaned: Map.get(result, :items_cleaned, 0))
          :ok
        {:error, reason} ->
          Logger.warning("Automatic cleanup failed: #{inspect(reason)}")
          :ok  # Continue scheduling even if cleanup fails
      end
    end) do
      {:ok, _} -> 
        safe_schedule_cleanup(state.agent.state.config.cleanup_interval)
        {:noreply, state}
      {:error, error} ->
        Logger.error("Error in cleanup timer: #{inspect(error)}")
        safe_schedule_cleanup(state.agent.state.config.cleanup_interval)
        {:noreply, state}
    end
  end
  
  # Private utility functions
  
  # Parameter validation functions
  defp validate_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      :ok
    else
      ErrorHandling.validation_error("Process is not alive", %{pid: pid})
    end
  end
  defp validate_pid(pid), do: ErrorHandling.validation_error("Invalid PID", %{pid: pid})
  
  defp validate_pid_and_params(pid, params) do
    with :ok <- validate_pid(pid),
         :ok <- validate_params(params) do
      :ok
    end
  end
  
  defp validate_params(params) when is_map(params), do: :ok
  defp validate_params(params), do: ErrorHandling.validation_error("Invalid parameters format", %{params: params})
  
  # Safe configuration handling
  defp safe_merge_config(base_config, opts) do
    try do
      config = Map.merge(base_config, Map.new(opts))
      
      # Validate configuration values
      case validate_config(config) do
        :ok -> {:ok, config}
        error -> error
      end
    rescue
      error -> ErrorHandling.system_error("Failed to merge configuration: #{Exception.message(error)}", %{opts: opts})
    end
  end
  
  defp validate_config(%{ttl_seconds: ttl, max_items: max, cleanup_interval: interval}) 
       when is_integer(ttl) and ttl > 0 and is_integer(max) and max > 0 and is_integer(interval) and interval > 0 do
    :ok
  end
  defp validate_config(config), do: ErrorHandling.validation_error("Invalid configuration values", %{config: config})
  
  # Safe ETS table operations
  defp safe_initialize_ets_tables(agent) do
    try do
      agent = initialize_ets_tables(agent)
      {:ok, agent}
    rescue
      error -> ErrorHandling.system_error("Failed to initialize ETS tables: #{Exception.message(error)}", %{agent_id: agent.id})
    end
  end

  defp initialize_ets_tables(agent) do
    table_name = :"stm_#{agent.id}"
    user_index_name = :"stm_user_#{agent.id}"
    session_index_name = :"stm_session_#{agent.id}"
    time_index_name = :"stm_time_#{agent.id}"
    
    # Create ETS tables
    primary_table = :ets.new(table_name, [:set, :public, :named_table])
    user_index = :ets.new(user_index_name, [:bag, :public, :named_table])
    session_index = :ets.new(session_index_name, [:bag, :public, :named_table])
    time_index = :ets.new(time_index_name, [:ordered_set, :public, :named_table])
    
    ets_tables = %{
      primary: primary_table,
      user_index: user_index,
      session_index: session_index,
      time_index: time_index
    }
    
    updated_state = Map.put(agent.state, :ets_tables, ets_tables)
    Map.put(agent, :state, updated_state)
  end
  
  defp safe_cleanup_ets_tables(agent) do
    try do
      cleanup_ets_tables(agent)
      :ok
    rescue
      error -> {:error, "Failed to cleanup ETS tables: #{Exception.message(error)}"}
    end
  end
  
  defp cleanup_ets_tables(agent) do
    Enum.each(agent.state.ets_tables, fn {_name, table} ->
      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)
  end
  
  defp safe_schedule_cleanup(interval) do
    try do
      schedule_cleanup(interval)
    rescue
      error -> Logger.error("Failed to schedule cleanup: #{Exception.message(error)}")
    end
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_expired, interval)
  end
end