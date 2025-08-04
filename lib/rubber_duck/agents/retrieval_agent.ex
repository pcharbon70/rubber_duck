defmodule RubberDuck.Agents.RetrievalAgent do
  @moduledoc """
  Retrieval Agent for managing advanced retrieval strategies in the RAG pipeline.
  
  This agent coordinates multiple retrieval approaches including semantic similarity,
  hybrid search, contextual retrieval, and multi-hop retrieval patterns. It provides
  a unified interface for all retrieval operations with proper caching and optimization.
  
  ## Responsibilities
  
  - Coordinate semantic vector-based retrieval
  - Manage hybrid search combining semantic and keyword approaches
  - Handle contextual retrieval with conversation history
  - Execute multi-hop retrieval for complex queries
  - Provide result ranking and filtering
  - Implement caching and optimization strategies
  
  ## Available Actions
  
  - `SemanticRetrievalAction` - Vector embedding-based retrieval
  - `HybridRetrievalAction` - Combined semantic + keyword search
  - `ContextualRetrievalAction` - Context-aware retrieval
  - `MultiHopRetrievalAction` - Iterative retrieval expansion
  - `RankResultsAction` - Result ranking and filtering
  - `CacheResultsAction` - Result caching and optimization
  """

  use Jido.Agent,
    name: "retrieval_agent",
    description: "Manages advanced retrieval strategies for RAG pipeline",
    schema: [
      # Retrieval configuration
      config: [type: :map, default: %{
        default_strategy: :hybrid,
        default_limit: 10,
        default_threshold: 0.7,
        cache_ttl: 3600,
        max_cache_size: 1000
      }],
      
      # Active retrieval cache
      cache: [type: :map, default: %{}],
      
      # Retrieval history and analytics
      retrieval_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 100],
      
      # Performance metrics
      metrics: [type: :map, default: %{
        total_retrievals: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_retrieval_time: 0.0,
        strategies_used: %{}
      }]
    ],
    actions: [
      __MODULE__.SemanticRetrievalAction,
      __MODULE__.HybridRetrievalAction,
      __MODULE__.ContextualRetrievalAction,
      __MODULE__.MultiHopRetrievalAction,
      __MODULE__.RankResultsAction,
      __MODULE__.CacheResultsAction
    ]

  alias RubberDuck.Agents.ErrorHandling
  alias RubberDuck.RAG.Retrieval
  require Logger

  @impl true
  def mount(opts, initial_state) do
    Logger.info("Mounting retrieval agent", opts: opts)
    
    # Initialize with configuration validation
    config = initial_state[:config] || %{
      default_strategy: :hybrid,
      default_limit: 10,
      default_threshold: 0.7,
      cache_ttl: 3600,
      max_cache_size: 1000
    }
    
    state = %{
      config: config,
      cache: %{},
      retrieval_history: [],
      max_history: 100,
      metrics: %{
        total_retrievals: 0,
        cache_hits: 0,
        cache_misses: 0,
        avg_retrieval_time: 0.0,
        strategies_used: %{}
      }
    }
    
    Logger.info("RetrievalAgent mounted successfully")
    state
  end

  # Action definitions

  defmodule SemanticRetrievalAction do
    @moduledoc """
    Performs semantic retrieval using vector embeddings.
    
    Uses cosine similarity to find the most relevant documents based on
    semantic meaning rather than keyword matching.
    """
    use Jido.Action,
      name: "semantic_retrieval",
      description: "Semantic vector-based document retrieval",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        limit: [type: :integer, default: 10, doc: "Maximum results to return"],
        threshold: [type: :float, default: 0.7, doc: "Minimum similarity threshold"],
        project_id: [type: :string, required: false, doc: "Filter by project ID"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Starting semantic retrieval", query: params.query, limit: params.limit)
        
        case Retrieval.semantic_retrieval(params.query, [
          limit: params.limit,
          threshold: params.threshold,
          project_id: Map.get(params, :project_id)
        ]) do
          {:ok, results} ->
            Logger.info("Semantic retrieval completed", results_count: length(results))
            {:ok, %{
              strategy: :semantic,
              query: params.query,
              results: results,
              limit: params.limit,
              threshold: params.threshold,
              retrieved_at: DateTime.utc_now()
            }}
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end
  end

  defmodule HybridRetrievalAction do
    @moduledoc """
    Performs hybrid retrieval combining semantic and keyword search.
    
    Merges results from both approaches using reciprocal rank fusion
    for improved retrieval quality.
    """
    use Jido.Action,
      name: "hybrid_retrieval",
      description: "Combined semantic and keyword retrieval",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        limit: [type: :integer, default: 10, doc: "Maximum results to return"],
        project_id: [type: :string, required: false, doc: "Filter by project ID"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Starting hybrid retrieval", query: params.query, limit: params.limit)
        
        case Retrieval.hybrid_retrieval(params.query, [
          limit: params.limit,
          project_id: Map.get(params, :project_id)
        ]) do
          {:ok, results} ->
            Logger.info("Hybrid retrieval completed", results_count: length(results))
            {:ok, %{
              strategy: :hybrid,
              query: params.query,
              results: results,
              limit: params.limit,
              retrieved_at: DateTime.utc_now()
            }}
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end
  end

  defmodule ContextualRetrievalAction do
    @moduledoc """
    Performs contextual retrieval considering conversation history.
    
    Enhances the search query with context from recent interactions
    and re-scores results based on contextual relevance.
    """
    use Jido.Action,
      name: "contextual_retrieval",
      description: "Context-aware document retrieval",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        context: [type: :map, default: %{}, doc: "Contextual information"],
        limit: [type: :integer, default: 10, doc: "Maximum results to return"],
        project_id: [type: :string, required: false, doc: "Filter by project ID"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Starting contextual retrieval", query: params.query, limit: params.limit)
        
        case Retrieval.contextual_retrieval(params.query, [
          context: params.context,
          limit: params.limit,
          project_id: Map.get(params, :project_id)
        ]) do
          {:ok, results} ->
            Logger.info("Contextual retrieval completed", results_count: length(results))
            {:ok, %{
              strategy: :contextual,
              query: params.query,
              context: params.context,
              results: results,
              limit: params.limit,
              retrieved_at: DateTime.utc_now()
            }}
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end
  end

  defmodule MultiHopRetrievalAction do
    @moduledoc """
    Performs multi-hop retrieval for complex queries.
    
    Iteratively retrieves and expands the search based on initial results,
    following chains of related information.
    """
    use Jido.Action,
      name: "multi_hop_retrieval",
      description: "Multi-hop iterative document retrieval",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        max_hops: [type: :integer, default: 2, doc: "Maximum retrieval hops"],
        limit: [type: :integer, default: 10, doc: "Maximum results to return"],
        project_id: [type: :string, required: false, doc: "Filter by project ID"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.info("Starting multi-hop retrieval", 
          query: params.query, 
          max_hops: params.max_hops, 
          limit: params.limit
        )
        
        case Retrieval.multi_hop_retrieval(params.query, [
          max_hops: params.max_hops,
          limit: params.limit,
          project_id: Map.get(params, :project_id)
        ]) do
          {:ok, results} ->
            Logger.info("Multi-hop retrieval completed", 
              results_count: length(results),
              hops_executed: params.max_hops
            )
            {:ok, %{
              strategy: :multi_hop,
              query: params.query,
              max_hops: params.max_hops,
              results: results,
              limit: params.limit,
              retrieved_at: DateTime.utc_now()
            }}
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end
  end

  defmodule RankResultsAction do
    @moduledoc """
    Ranks and filters retrieval results based on various criteria.
    
    Applies scoring algorithms, relevance filtering, and result optimization
    to improve the quality of retrieved documents.
    """
    use Jido.Action,
      name: "rank_results",
      description: "Rank and filter retrieval results",
      schema: [
        results: [type: {:list, :map}, required: true, doc: "Results to rank"],
        ranking_strategy: [type: :atom, default: :relevance, doc: "Ranking strategy"],
        filter_threshold: [type: :float, default: 0.0, doc: "Minimum score threshold"],
        max_results: [type: :integer, required: false, doc: "Maximum results to return"]
      ]

    @impl true
    def run(params, _context) do
      ErrorHandling.safe_execute(fn ->
        Logger.debug("Ranking results", 
          input_count: length(params.results),
          strategy: params.ranking_strategy
        )
        
        case apply_ranking(params.results, params.ranking_strategy, params.filter_threshold) do
          {:ok, ranked_results} ->
            final_results = if params.max_results do
              Enum.take(ranked_results, params.max_results)
            else
              ranked_results
            end
            
            Logger.debug("Results ranking completed", 
              output_count: length(final_results),
              filtered_count: length(params.results) - length(final_results)
            )
            
            {:ok, %{
              ranked_results: final_results,
              original_count: length(params.results),
              final_count: length(final_results),
              ranking_strategy: params.ranking_strategy,
              filter_threshold: params.filter_threshold,
              ranked_at: DateTime.utc_now()
            }}
          {:error, error} ->
            ErrorHandling.categorize_error(error)
        end
      end)
    end

    defp apply_ranking(results, :relevance, threshold) do
      try do
        ranked = results
        |> Enum.filter(fn result -> Map.get(result, :score, 0) >= threshold end)
        |> Enum.sort_by(fn result -> Map.get(result, :score, 0) end, :desc)
        
        {:ok, ranked}
      rescue
        error -> {:error, "Ranking failed: #{Exception.message(error)}"}
      end
    end
    
    defp apply_ranking(results, :recency, threshold) do
      try do
        ranked = results
        |> Enum.filter(fn result -> Map.get(result, :score, 0) >= threshold end)
        |> Enum.sort_by(fn result -> 
          Map.get(result.metadata || %{}, :created_at, DateTime.utc_now())
        end, {:desc, DateTime})
        
        {:ok, ranked}
      rescue
        error -> {:error, "Ranking failed: #{Exception.message(error)}"}
      end
    end
    
    defp apply_ranking(results, _strategy, threshold) do
      # Default to relevance ranking
      apply_ranking(results, :relevance, threshold)
    end
  end

  defmodule CacheResultsAction do
    @moduledoc """
    Caches retrieval results for improved performance.
    
    Manages result caching with TTL expiration and cache size limits
    to optimize repeated retrieval operations.
    """
    use Jido.Action,
      name: "cache_results",
      description: "Cache retrieval results for performance",
      schema: [
        cache_key: [type: :string, required: true, doc: "Cache key for results"],
        results: [type: {:list, :map}, required: true, doc: "Results to cache"],
        ttl: [type: :integer, default: 3600, doc: "Time to live in seconds"]
      ]

    @impl true
    def run(params, context) do
      ErrorHandling.safe_execute(fn ->
        agent = context.agent
        cache_entry = %{
          results: params.results,
          cached_at: DateTime.utc_now(),
          expires_at: DateTime.add(DateTime.utc_now(), params.ttl),
          ttl: params.ttl
        }
        
        # Update agent cache
        updated_cache = Map.put(agent.state.cache, params.cache_key, cache_entry)
        
        # Cleanup expired entries if cache is getting large
        cleaned_cache = if map_size(updated_cache) > agent.state.config.max_cache_size do
          cleanup_expired_cache(updated_cache)
        else
          updated_cache
        end
        
        Logger.debug("Results cached", 
          cache_key: params.cache_key,
          results_count: length(params.results),
          ttl: params.ttl
        )
        
        {:ok, %{
          cached: true,
          cache_key: params.cache_key,
          results_count: length(params.results),
          ttl: params.ttl,
          expires_at: cache_entry.expires_at,
          cached_at: cache_entry.cached_at
        }, %{agent: %{agent | state: %{agent.state | cache: cleaned_cache}}}}
      end)
    end

    defp cleanup_expired_cache(cache) do
      now = DateTime.utc_now()
      
      cache
      |> Enum.filter(fn {_key, entry} ->
        DateTime.compare(now, entry.expires_at) == :lt
      end)
      |> Map.new()
    end
  end
end