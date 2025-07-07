defmodule RubberDuck.Context.Manager do
  @moduledoc """
  Main interface for context building, coordinating strategies, caching, and optimization.
  """

  alias RubberDuck.Context.{Cache, AdaptiveSelector, Optimizer, Scorer}
  alias RubberDuck.Context.Strategies.{FIM, RAG, LongContext}

  @strategy_modules %{
    fim: FIM,
    rag: RAG,
    long_context: LongContext
  }

  @doc """
  Builds context for a query using the most appropriate strategy.

  Options:
  - `:strategy` - Force a specific strategy (:fim, :rag, :long_context, or :auto)
  - `:max_tokens` - Maximum tokens for the context
  - `:user_id` - User ID for personalization
  - `:session_id` - Session ID for recent context
  - `:project_id` - Project ID for project-specific context
  - `:cursor_position` - Cursor position for FIM strategy
  - `:file_content` - Current file content
  - `:files` - List of files for multi-file context
  - `:skip_cache` - Skip cache lookup
  - `:skip_optimization` - Skip context optimization
  """
  def build_context(query, opts \\ []) do
    # Check cache first unless skipped
    cache_key = Cache.generate_key(query, opts)

    if not Keyword.get(opts, :skip_cache, false) do
      case Cache.get(cache_key) do
        {:ok, cached_context} ->
          {:ok, Map.put(cached_context, :from_cache, true)}

        {:error, :not_found} ->
          build_and_cache_context(query, opts, cache_key)
      end
    else
      build_new_context(query, opts)
    end
  end

  @doc """
  Builds context using a specific strategy.
  """
  def build_with_strategy(query, strategy, opts) when is_atom(strategy) do
    case Map.get(@strategy_modules, strategy) do
      nil ->
        {:error, {:invalid_strategy, strategy}}

      strategy_module ->
        with {:ok, context} <- strategy_module.build(query, opts),
             {:ok, optimized} <- maybe_optimize(context, opts) do
          {:ok, optimized}
        end
    end
  end

  @doc """
  Evaluates context quality for the given query.
  """
  def evaluate_context(context, query, opts \\ []) do
    Scorer.score(context, query, opts)
  end

  @doc """
  Provides feedback about context quality to improve future selections.
  """
  def provide_feedback(query, context, quality_score) do
    AdaptiveSelector.record_feedback(query, context.strategy, quality_score)
  end

  @doc """
  Gets suggestions for improving a context.
  """
  def get_improvement_suggestions(context, query) do
    score_result = Scorer.score(context, query)
    Scorer.suggest_improvements(context, query, score_result)
  end

  @doc """
  Invalidates cached contexts for a user or session.
  """
  def invalidate_cache(%{user_id: user_id} = pattern) do
    Cache.invalidate_pattern(pattern)
  end

  def invalidate_cache(key) when is_binary(key) do
    Cache.invalidate(key)
  end

  # Private functions

  defp build_and_cache_context(query, opts, cache_key) do
    case build_new_context(query, opts) do
      {:ok, context} = result ->
        # Cache the result
        ttl = Keyword.get(opts, :cache_ttl, 15)
        Cache.put(cache_key, context, ttl)
        result

      error ->
        error
    end
  end

  defp build_new_context(query, opts) do
    # Determine strategy
    strategy = Keyword.get(opts, :strategy, :auto)

    case select_strategy(strategy, query, opts) do
      {:ok, selected_strategy} ->
        # Build context with selected strategy
        build_with_strategy(query, selected_strategy, opts)

      error ->
        error
    end
  end

  defp select_strategy(:auto, query, opts) do
    case AdaptiveSelector.select_strategy(query, opts) do
      {:ok, strategy, _confidence} ->
        {:ok, strategy}

      error ->
        error
    end
  end

  defp select_strategy(strategy, _query, _opts) when is_atom(strategy) do
    if Map.has_key?(@strategy_modules, strategy) do
      {:ok, strategy}
    else
      {:error, {:invalid_strategy, strategy}}
    end
  end

  defp maybe_optimize(context, opts) do
    if Keyword.get(opts, :skip_optimization, false) do
      {:ok, context}
    else
      Optimizer.optimize(context, opts)
    end
  end
end
