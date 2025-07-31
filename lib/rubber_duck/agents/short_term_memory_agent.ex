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
  
  require Logger
  
  alias RubberDuck.Memory
  
  # Lifecycle callbacks
  
  @impl Jido.Agent
  def mount(agent, opts \\ []) do
    # Initialize configuration with provided options
    config = Map.merge(agent.state.config, Map.new(opts))
    updated_state = Map.put(agent.state, :config, config)
    agent = Map.put(agent, :state, updated_state)
    
    # Initialize ETS tables
    agent = initialize_ets_tables(agent)
    
    # Schedule cleanup timer
    schedule_cleanup(agent.state.config.cleanup_interval)
    
    {:ok, agent}
  end
  
  @impl Jido.Agent
  def shutdown(agent, _reason) do
    Logger.info("ShortTermMemoryAgent shutting down", agent_id: agent.id)
    
    # Clean up ETS tables
    cleanup_ets_tables(agent)
    
    {:ok, agent}
  end
  
  # Convenience functions for accessing agent data
  
  def get_state(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :get_state)
  end
  
  def store_memory(agent_pid, params) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.StoreMemoryAction, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def get_memory(agent_pid, params) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.GetMemoryAction, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def search_by_user(agent_pid, params) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.SearchByUserAction, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def search_by_session(agent_pid, params) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.SearchBySessionAction, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def cleanup_expired(agent_pid) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction, %{}) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def get_analytics(agent_pid) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.GetAnalyticsAction, %{}) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  def store_with_persistence(agent_pid, params) when is_pid(agent_pid) do
    case Jido.Agent.cmd(agent_pid, RubberDuck.Jido.Actions.ShortTermMemory.StoreWithPersistenceAction, params) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Support for get_state call
  def handle_call(:get_state, _from, state) do
    {:reply, state.agent.state, state}
  end
  
  # Timer-based cleanup
  def handle_info(:cleanup_expired, state) do
    case Jido.Agent.cmd(self(), RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction, %{}) do
      {:ok, _result} ->
        schedule_cleanup(state.agent.state.config.cleanup_interval)
        {:noreply, state}
      {:error, _reason} ->
        schedule_cleanup(state.agent.state.config.cleanup_interval)
        {:noreply, state}
    end
  end
  
  # Private utility functions
  
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
  
  defp cleanup_ets_tables(agent) do
    Enum.each(agent.state.ets_tables, fn {_name, table} ->
      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_expired, interval)
  end
end