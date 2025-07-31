defmodule RubberDuck.Agents.ResponseProcessorAgent do
  @moduledoc """
  Response Processor Agent for handling post-processing of LLM responses.
  
  This agent provides comprehensive response processing including:
  - Multi-format parsing with automatic detection
  - Quality validation and scoring
  - Content enhancement and enrichment
  - Intelligent caching with TTL management
  - Performance metrics and optimization
  
  ## Actions
  
  The agent supports the following actions through the Jido pattern:
  
  ### Processing Operations
  - `ProcessResponseAction`: Main processing pipeline
  - `ParseResponseAction`: Parse specific format
  - `ValidateResponseAction`: Validate response quality
  - `EnhanceResponseAction`: Apply enhancement pipeline
  
  ### Caching Operations
  - `GetCachedResponseAction`: Retrieve from cache
  - `InvalidateCacheAction`: Remove cached entries
  - `ClearCacheAction`: Clear all cached responses
  
  ### Metrics and Configuration
  - `GetMetricsAction`: Retrieve processing metrics
  - `GetStatusAction`: Agent health and performance status
  - `ConfigureProcessorAction`: Update configuration
  """

  use Jido.Agent,
    name: "response_processor",
    description: "Processes and enhances LLM responses with parsing, validation, and caching",
    schema: [
      cache: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        total_processed: 0,
        total_cached: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_processing_time: 0.0,
        format_distribution: %{},
        quality_distribution: %{},
        error_count: 0
      }],
      parsers: [type: :map, default: %{}],
      enhancers: [type: :list, default: []],
      validators: [type: :list, default: []],
      config: [type: :map, default: %{
        cache_ttl: 7200,  # 2 hours
        max_cache_size: 10000,
        enable_streaming: true,
        quality_threshold: 0.8,
        compression_enabled: true,
        auto_enhance: true,
        fallback_to_text: true
      }]
    ],
    actions: [
      RubberDuck.Jido.Actions.ResponseProcessor.ProcessResponseAction,
      RubberDuck.Jido.Actions.ResponseProcessor.ParseResponseAction,
      RubberDuck.Jido.Actions.ResponseProcessor.ValidateResponseAction,
      RubberDuck.Jido.Actions.ResponseProcessor.EnhanceResponseAction,
      RubberDuck.Jido.Actions.ResponseProcessor.GetCachedResponseAction,
      RubberDuck.Jido.Actions.ResponseProcessor.InvalidateCacheAction,
      RubberDuck.Jido.Actions.ResponseProcessor.ClearCacheAction,
      RubberDuck.Jido.Actions.ResponseProcessor.GetMetricsAction,
      RubberDuck.Jido.Actions.ResponseProcessor.GetStatusAction,
      RubberDuck.Jido.Actions.ResponseProcessor.ConfigureProcessorAction
    ]

  alias RubberDuck.Agents.Response.Parser
  require Logger

  @impl true
  def mount(_opts, _initial_state) do
    # Initialize parsers
    parsers = initialize_parsers()
    
    # Initialize enhancers and validators
    enhancers = initialize_enhancers()
    validators = initialize_validators()
    
    state = %{
      cache: %{},
      metrics: %{
        total_processed: 0,
        total_cached: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_processing_time: 0.0,
        format_distribution: %{},
        quality_distribution: %{},
        error_count: 0
      },
      parsers: parsers,
      enhancers: enhancers,
      validators: validators,
      config: %{
        cache_ttl: 7200,  # 2 hours
        max_cache_size: 10000,
        enable_streaming: true,
        quality_threshold: 0.8,
        compression_enabled: true,
        auto_enhance: true,
        fallback_to_text: true
      }
    }
    
    # Start periodic cleanup
    schedule_cleanup()
    
    Logger.info("ResponseProcessorAgent initialized with #{map_size(parsers)} parsers")
    {:ok, state}
  end

  # GenServer callbacks for periodic tasks

  @impl true
  def handle_info(:cleanup, %{state: state} = agent) do
    updated_state = state
    |> cleanup_expired_cache()
    |> cleanup_old_metrics()
    
    schedule_cleanup()
    {:noreply, %{agent | state: updated_state}}
  end

  # Private helper functions

  defp initialize_parsers do
    %{
      json: Parser.JSONParser,
      markdown: Parser.MarkdownParser,
      text: Parser.TextParser
    }
  end

  defp initialize_enhancers do
    [
      :format_beautification,
      :link_enrichment,
      :content_cleanup,
      :readability_improvement
    ]
  end

  defp initialize_validators do
    [
      :completeness_check,
      :safety_validation,
      :quality_scoring,
      :format_validation
    ]
  end

  # Cleanup and utility functions

  defp cleanup_expired_cache(state) do
    now = DateTime.utc_now()
    
    valid_cache = state.cache
    |> Enum.filter(fn {_key, entry} ->
      DateTime.compare(now, entry.expires_at) == :lt
    end)
    |> Map.new()
    
    put_in(state.cache, valid_cache)
  end

  defp cleanup_old_metrics(state) do
    # In production, would clean up old metric data
    state
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000)  # Every 5 minutes
  end
end