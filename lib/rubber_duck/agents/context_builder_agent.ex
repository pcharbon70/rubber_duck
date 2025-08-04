defmodule RubberDuck.Agents.ContextBuilderAgent do
  @moduledoc """
  Context Builder Agent for intelligent context aggregation and optimization.
  
  This agent manages the collection, prioritization, and optimization of context
  from multiple sources to provide relevant information for LLM interactions.
  It ensures efficient token usage while maximizing context relevance.
  
  Migrated to Jido-compliant action-based architecture for better maintainability,
  testability, and reusability of context management workflows.
  
  ## Responsibilities
  
  - Route context requests to appropriate Actions
  - Maintain context sources registry and configuration
  - Provide centralized context caching and metrics
  - Handle context lifecycle management
  - Support streaming and real-time context updates
  
  ## State Structure
  
  ```elixir
  %{
    sources: %{source_id => source_config},
    cache: %{request_id => built_context},
    active_builds: %{request_id => build_state},
    priorities: %{
      relevance_weight: float,
      recency_weight: float,
      importance_weight: float
    },
    metrics: %{
      builds_completed: integer,
      avg_build_time_ms: float,
      cache_hit_rate: float,
      avg_compression_ratio: float
    },
    config: %{
      max_cache_size: integer,
      default_max_tokens: integer,
      compression_threshold: integer
    }
  }
  ```
  """

  use Jido.Agent,
    name: "context_builder",
    description: "Manages context aggregation, prioritization, and optimization for LLM interactions",
    schema: [
      sources: [type: :map, default: %{}, doc: "Registered context sources"],
      cache: [type: :map, default: %{}, doc: "Built context cache"],
      active_builds: [type: :map, default: %{}, doc: "Active context builds"],
      priorities: [type: :map, default: %{}, doc: "Context prioritization weights"],
      metrics: [type: :map, default: %{}, doc: "Performance and usage metrics"],
      config: [type: :map, default: %{}, doc: "Agent configuration"]
    ]

  alias RubberDuck.Context.ContextSource
  # Actions are defined in the agent's actions list
  require Logger

  @default_config %{
    max_cache_size: 100,
    cache_ttl: 300_000,  # 5 minutes
    default_max_tokens: 4000,
    compression_threshold: 1000,
    parallel_source_limit: 10,
    source_timeout: 5000,
    dedup_threshold: 0.85,
    summary_ratio: 0.3
  }

  @default_priorities %{
    relevance_weight: 0.4,
    recency_weight: 0.3,
    importance_weight: 0.3
  }

  # @source_types [:memory, :code_analysis, :documentation, :conversation, :planning, :custom]

  ## Initialization

  @impl Jido.Agent
  def mount(opts, initial_state) do
    Logger.info("Mounting ContextBuilderAgent", opts: opts)
    
    state = Map.merge(initial_state, %{
      sources: initialize_default_sources(),
      cache: %{},
      active_builds: %{},
      priorities: @default_priorities,
      metrics: %{
        builds_completed: 0,
        avg_build_time_ms: 0.0,
        cache_hits: 0,
        cache_misses: 0,
        total_tokens_saved: 0,
        avg_compression_ratio: 1.0,
        source_failures: %{}
      },
      config: Map.merge(@default_config, Map.get(opts, :config, %{}))
    })
    
    # Schedule periodic cache cleanup
    Process.send_after(self(), :cleanup_cache, 60_000)
    
    {:ok, state}
  end

  ## Action-based Signal Processing
  
  # All signal handling now routed through Actions via signal_mappings
  # This enables:
  # - Pure function-based business logic
  # - Reusable action components
  # - Better testability and maintainability
  # - Consistent error handling patterns
  
  # Signal-to-Action parameter extraction functions
  
  # ContextAssemblyAction parameter extractors
  def extract_build_params(signal_data) do
    %{
      mode: :build,
      request_id: signal_data["request_id"],
      purpose: signal_data["purpose"] || "general",
      max_tokens: signal_data["max_tokens"] || @default_config.default_max_tokens,
      required_sources: signal_data["required_sources"] || [],
      excluded_sources: signal_data["excluded_sources"] || [],
      filters: signal_data["filters"] || %{},
      preferences: signal_data["preferences"] || %{},
      streaming: signal_data["streaming"] || false,
      priority: string_to_atom(signal_data["priority"]) || :normal
    }
  end

  def extract_context_update_params(signal_data) do
    %{
      mode: :update,
      request_id: signal_data["request_id"],
      update_data: signal_data["updates"] || %{}
    }
  end

  def extract_stream_params(signal_data) do
    %{
      mode: :stream,
      request_id: signal_data["request_id"],
      purpose: signal_data["purpose"] || "general",
      max_tokens: signal_data["max_tokens"] || @default_config.default_max_tokens,
      chunk_size: signal_data["chunk_size"] || 1000,
      streaming: true
    }
  end

  # ContextCacheAction parameter extractors
  def extract_invalidate_params(signal_data) do
    %{
      operation: :invalidate,
      invalidation_pattern: signal_data["pattern"],
      request_id: signal_data["request_id"],
      cache_key: signal_data["cache_key"]
    }
  end

  def extract_stats_params(_signal_data) do
    %{
      operation: :stats,
      metrics_enabled: true,
      include_detailed_metrics: true
    }
  end

  def extract_cleanup_params(signal_data) do
    %{
      operation: :cleanup,
      cleanup_threshold: signal_data["threshold"] || 0.8,
      max_entries: signal_data["max_entries"] || @default_config.max_cache_size
    }
  end

  # ContextSourceManagementAction parameter extractors
  def extract_register_params(signal_data) do
    %{
      operation: :register,
      source_data: signal_data
    }
  end

  def extract_source_update_params(signal_data) do
    %{
      operation: :update,
      source_id: signal_data["source_id"],
      updates: signal_data["updates"] || %{}
    }
  end

  def extract_remove_params(signal_data) do
    %{
      operation: :remove,
      source_id: signal_data["source_id"]
    }
  end

  def extract_status_params(signal_data) do
    %{
      operation: :status,
      source_id: signal_data["source_id"],
      include_config: signal_data["include_config"] || false
    }
  end

  # ContextConfigurationAction parameter extractors
  def extract_priorities_params(signal_data) do
    %{
      operation: :set_priorities,
      priorities: %{
        relevance_weight: signal_data["relevance_weight"],
        recency_weight: signal_data["recency_weight"],
        importance_weight: signal_data["importance_weight"]
      }
    }
  end

  def extract_limits_params(signal_data) do
    %{
      operation: :configure_limits,
      limits: signal_data
    }
  end

  def extract_metrics_params(signal_data) do
    %{
      operation: :get_metrics,
      include_detailed_metrics: signal_data["detailed"] || false,
      metrics_time_range: signal_data["time_range"] || 24
    }
  end

  # BaseAgent callback implementations
  
  @impl RubberDuck.Agents.BaseAgent
  def signal_mappings do
    %{
      # Context operations → ContextAssemblyAction
      "build_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_build_params},
      "update_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_context_update_params},
      "stream_context" => {RubberDuck.Jido.Actions.Context.ContextAssemblyAction, :extract_stream_params},
      
      # Cache operations → ContextCacheAction
      "invalidate_context" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_invalidate_params},
      "get_cache_stats" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_stats_params},
      "cleanup_cache" => {RubberDuck.Jido.Actions.Context.ContextCacheAction, :extract_cleanup_params},
      
      # Source management → ContextSourceManagementAction
      "register_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_register_params},
      "update_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_source_update_params},
      "remove_source" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_remove_params},
      "get_source_status" => {RubberDuck.Jido.Actions.Context.ContextSourceManagementAction, :extract_status_params},
      
      # Configuration → ContextConfigurationAction
      "set_priorities" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_priorities_params},
      "configure_limits" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_limits_params},
      "get_metrics" => {RubberDuck.Jido.Actions.Context.ContextConfigurationAction, :extract_metrics_params}
    }
  end

  # Helper functions
  defp string_to_atom(nil), do: nil
  defp string_to_atom(str) when is_binary(str), do: String.to_atom(str)
  defp string_to_atom(atom) when is_atom(atom), do: atom

  ## Private Functions

  defp initialize_default_sources do
    %{
      "memory_source" => ContextSource.new(%{
        id: "memory_source",
        name: "Memory System",
        type: :memory,
        weight: 1.0,
        config: %{
          "include_short_term" => true,
          "include_long_term" => true
        }
      }),
      "code_source" => ContextSource.new(%{
        id: "code_source",
        name: "Code Analysis",
        type: :code_analysis,
        weight: 0.8,
        config: %{
          "max_file_size" => 10000,
          "include_comments" => true
        }
      })
    }
  end

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, 60_000)  # Every minute
  end

  # Handle periodic cache cleanup  
  def handle_info(:cleanup_cache, agent) do
    # Remove expired cache entries
    now = DateTime.utc_now()
    
    updated_cache = agent.cache
    |> Enum.filter(fn {_id, context} ->
      age = DateTime.diff(now, context["timestamp"], :millisecond)
      age < agent.config.cache_ttl
    end)
    |> Map.new()
    
    removed = map_size(agent.cache) - map_size(updated_cache)
    
    if removed > 0 do
      Logger.debug("Context cache cleanup: removed #{removed} expired entries")
    end
    
    schedule_cache_cleanup()
    
    {:noreply, %{agent | cache: updated_cache}}
  end

  # Handle streaming completion
  def handle_info({:streaming_complete, request_id}, agent) do
    # Clean up active build
    agent = update_in(agent.active_builds, &Map.delete(&1, request_id))
    {:noreply, agent}
  end

  ## Lifecycle Hooks

  @impl Jido.Agent
  def on_before_run(agent) do
    Logger.debug("ContextBuilderAgent preparing to run action",
      agent_id: agent.id,
      cache_size: map_size(agent.state.cache)
    )
    {:ok, agent}
  end

  @impl Jido.Agent
  def on_after_run(agent, _result, metadata) do
    # Update metrics after action completion
    updated_metrics = Map.update(agent.state.metrics, :builds_completed, 1, &(&1 + 1))
    updated_state = Map.put(agent.state, :metrics, updated_metrics)
    
    Logger.debug("ContextBuilderAgent completed action",
      agent_id: agent.id,
      action: metadata[:action],
      builds_completed: updated_metrics.builds_completed
    )
    
    {:ok, %{agent | state: updated_state}}
  end

  @impl Jido.Agent
  def on_error(agent, error) do
    Logger.error("ContextBuilderAgent encountered error",
      agent_id: agent.id,
      error: error
    )
    {:ok, agent}
  end

  @impl Jido.Agent
  def shutdown(agent, reason) do
    Logger.info("ContextBuilderAgent shutting down",
      agent_id: agent.id,
      reason: reason,
      cache_size: map_size(agent.state.cache)
    )
    :ok
  end
end