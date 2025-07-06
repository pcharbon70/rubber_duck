defmodule RubberDuck.SelfCorrection.Engine do
  @moduledoc """
  Central coordinator for the iterative self-correction system.
  
  Orchestrates multiple correction strategies, manages iteration control,
  and learns from correction effectiveness to improve LLM outputs.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.SelfCorrection.{Strategy, Evaluator, Corrector, History}
  alias RubberDuck.RAG.Metrics
  
  @type correction_request :: %{
    content: String.t(),
    type: atom(),
    context: map(),
    options: keyword()
  }
  
  @type correction_result :: %{
    original: String.t(),
    corrected: String.t(),
    iterations: integer(),
    improvements: [map()],
    quality_score: float(),
    metadata: map()
  }
  
  @default_options [
    max_iterations: 3,
    convergence_threshold: 0.95,
    early_stopping: true,
    strategies: [:syntax, :semantic, :logic],
    parallel: true,
    cache_results: true
  ]
  
  # Client API
  
  @doc """
  Starts the self-correction engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Performs iterative self-correction on the given content.
  
  Options:
  - max_iterations: Maximum correction iterations (default: 3)
  - convergence_threshold: Quality score to stop early (default: 0.95)
  - early_stopping: Enable early stopping (default: true)
  - strategies: List of correction strategies to apply (default: [:syntax, :semantic, :logic])
  - parallel: Run strategies in parallel (default: true)
  - cache_results: Cache correction results (default: true)
  """
  @spec correct(correction_request()) :: {:ok, correction_result()} | {:error, term()}
  def correct(request) do
    GenServer.call(__MODULE__, {:correct, request}, 30_000)
  end
  
  @doc """
  Evaluates content quality without performing corrections.
  """
  @spec evaluate(String.t(), atom(), map()) :: {:ok, map()} | {:error, term()}
  def evaluate(content, type, context \\ %{}) do
    GenServer.call(__MODULE__, {:evaluate, content, type, context})
  end
  
  @doc """
  Gets correction history for analysis.
  """
  @spec get_history(keyword()) :: {:ok, [map()]} | {:error, term()}
  def get_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_history, opts})
  end
  
  @doc """
  Gets learning insights from correction patterns.
  """
  @spec get_insights() :: {:ok, map()} | {:error, term()}
  def get_insights() do
    GenServer.call(__MODULE__, :get_insights)
  end
  
  @doc """
  Gets the current status of the correction engine.
  """
  @spec get_status() :: map()
  def get_status() do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Analyzes content without applying corrections.
  
  Returns analysis with issues found and recommendations.
  """
  @spec analyze(correction_request()) :: {:ok, map()} | {:error, term()}
  def analyze(request) do
    GenServer.call(__MODULE__, {:analyze, request})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Initialize correction strategies
    strategies = load_strategies()
    
    state = %{
      strategies: strategies,
      cache: %{},
      stats: %{
        total_corrections: 0,
        successful_corrections: 0,
        average_iterations: 0,
        average_improvement: 0
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:correct, request}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Merge default options with request options
    request_options = Map.get(request, :options, [])
    
    # Also check for options directly on request (for backward compatibility)
    direct_options = request
    |> Map.take([:max_iterations, :target_score, :strategies, :early_stopping, :convergence_threshold, :cache_results])
    |> Enum.map(fn {k, v} -> {k, v} end)
    
    options = @default_options
    |> Keyword.merge(request_options)
    |> Keyword.merge(direct_options)
    
    # Check cache if enabled
    cache_key = generate_cache_key(request)
    cached_result = if options[:cache_results], do: Map.get(state.cache, cache_key), else: nil
    
    {result, new_state} = if cached_result do
      {{:ok, cached_result}, state}
    else
      perform_correction(request, options, state)
    end
    
    # Record metrics
    duration = System.monotonic_time(:millisecond) - start_time
    record_correction_metrics(result, duration, options)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:evaluate, content, type, context}, _from, state) do
    result = Evaluator.evaluate(content, type, context, state.strategies)
    {:reply, {:ok, result}, state}
  end
  
  @impl true
  def handle_call({:get_history, opts}, _from, state) do
    # Get history from the History process
    limit = Keyword.get(opts, :limit, 100)
    history = History.get_history(:all, limit: limit)
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_call(:get_insights, _from, state) do
    # Get insights from the Learner process
    # Note: This is a placeholder - the actual implementation would need proper parameters
    insights = %{
      strategies: state.strategies,
      stats: state.stats
    }
    {:reply, {:ok, insights}, state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      state: if(Map.get(state, :current_correction), do: :correcting, else: :idle),
      stats: state.stats,
      loaded_strategies: Map.keys(state.strategies)
    }
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:analyze, request}, _from, state) do
    # Validate request
    case validate_request(request) do
      :ok ->
        # Perform analysis without correction
        analysis = perform_analysis(request, state)
        {:reply, {:ok, analysis}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Private functions
  
  defp perform_correction(request, options, state) do
    # Initial evaluation
    initial_evaluation = Evaluator.evaluate(
      request.content, 
      request.type, 
      request.context,
      state.strategies
    )
    
    # Perform iterative correction
    correction_result = iterate_corrections(
      request,
      initial_evaluation,
      options,
      state
    )
    
    # Update state with results
    new_state = update_state_with_results(state, request, correction_result)
    
    {{:ok, correction_result}, new_state}
  end
  
  defp iterate_corrections(request, initial_eval, options, state, iteration \\ 0) do
    current_content = if iteration == 0, do: request.content, else: request.content
    
    # Check stopping conditions
    if should_stop_iteration?(iteration, initial_eval, options) do
      build_final_result(request, current_content, iteration, [])
    else
      # Apply correction strategies
      corrections = apply_strategies(
        current_content,
        request.type,
        request.context,
        initial_eval,
        options,
        state
      )
      
      # Apply best correction
      {improved_content, improvement_data} = apply_best_correction(
        current_content,
        corrections,
        state
      )
      
      # Re-evaluate
      new_eval = Evaluator.evaluate(
        improved_content,
        request.type,
        request.context,
        state.strategies
      )
      
      # Check for convergence
      if has_converged?(initial_eval, new_eval, options) do
        build_final_result(request, improved_content, iteration + 1, [improvement_data])
      else
        # Continue iteration with improved content
        updated_request = %{request | content: improved_content}
        
        iterate_corrections(
          updated_request,
          new_eval,
          options,
          state,
          iteration + 1
        ) |> Map.update!(:improvements, fn imps -> [improvement_data | imps] end)
      end
    end
  end
  
  defp should_stop_iteration?(iteration, evaluation, options) do
    iteration >= options[:max_iterations] ||
    (options[:early_stopping] && evaluation.overall_score >= options[:convergence_threshold])
  end
  
  defp has_converged?(old_eval, new_eval, options) do
    new_eval.overall_score >= options[:convergence_threshold] ||
    abs(new_eval.overall_score - old_eval.overall_score) < 0.01
  end
  
  defp apply_strategies(content, type, context, evaluation, options, state) do
    strategies = Keyword.get(options, :strategies, [:syntax, :semantic, :logic])
    
    if options[:parallel] do
      strategies
      |> Enum.map(fn strategy_name ->
        Task.async(fn ->
          strategy = Map.get(state.strategies, strategy_name)
          if strategy do
            Strategy.analyze(strategy, content, type, context, evaluation)
          else
            nil
          end
        end)
      end)
      |> Task.await_many(5000)
      |> Enum.filter(& &1)
    else
      strategies
      |> Enum.map(fn strategy_name ->
        strategy = Map.get(state.strategies, strategy_name)
        if strategy do
          Strategy.analyze(strategy, content, type, context, evaluation)
        else
          nil
        end
      end)
      |> Enum.filter(& &1)
    end
  end
  
  defp apply_best_correction(content, corrections, _state) do
    # Select best correction based on confidence and priority
    best_correction = corrections
    |> Enum.sort_by(fn c -> {c.confidence, c.priority} end, :desc)
    |> List.first()
    
    if best_correction do
      corrected_content = Corrector.apply_correction(content, best_correction)
      
      improvement_data = %{
        strategy: best_correction.strategy,
        confidence: best_correction.confidence,
        changes: best_correction.changes,
        timestamp: DateTime.utc_now()
      }
      
      {corrected_content, improvement_data}
    else
      {content, nil}
    end
  end
  
  defp build_final_result(request, final_content, iterations, improvements) do
    final_eval = Evaluator.evaluate(
      final_content,
      request.type,
      request.context,
      %{}  # Empty strategies for final eval
    )
    
    %{
      original: request.content,
      corrected: final_content,
      iterations: iterations,
      improvements: Enum.filter(improvements, & &1),
      quality_score: final_eval.overall_score,
      metadata: %{
        type: request.type,
        timestamp: DateTime.utc_now(),
        convergence_achieved: final_eval.overall_score >= 0.95
      }
    }
  end
  
  defp update_state_with_results(state, request, result) do
    # Record correction in history process
    history_entry = build_history_entry(request, result)
    History.record_correction(history_entry)
    
    # Update statistics
    new_stats = update_statistics(state.stats, result)
    
    # Update cache if enabled
    new_cache = if Map.get(request, :options, %{})[:cache_results] do
      cache_key = generate_cache_key(request)
      Map.put(state.cache, cache_key, result)
    else
      state.cache
    end
    
    %{state | 
      stats: new_stats,
      cache: new_cache
    }
  end
  
  defp build_history_entry(request, result) do
    case result do
      {:ok, correction_result} ->
        %{
          correction_type: request.type,
          strategy: get_primary_strategy(correction_result),
          content_type: request.type,
          issues_found: get_issues_found(correction_result),
          corrections_applied: get_corrections_applied(correction_result),
          success: correction_result.success,
          improvement_score: calculate_improvement_score(correction_result),
          iterations: correction_result.iterations,
          convergence_time: Map.get(correction_result, :convergence_time, 0),
          metadata: Map.get(request, :context, %{})
        }
      _ ->
        %{
          correction_type: request.type,
          strategy: :unknown,
          content_type: request.type,
          issues_found: [],
          corrections_applied: [],
          success: false,
          improvement_score: 0,
          iterations: 0,
          convergence_time: 0,
          metadata: %{}
        }
    end
  end
  
  defp get_primary_strategy(result) do
    result.corrections_applied
    |> List.first()
    |> case do
      %{strategy: strategy} -> strategy
      _ -> :unknown
    end
  end
  
  defp get_issues_found(result) do
    result
    |> Map.get(:issues_found, [])
    |> Enum.map(& &1.type)
    |> Enum.uniq()
  end
  
  defp get_corrections_applied(result) do
    result.corrections_applied
    |> Enum.map(& &1.type)
  end
  
  defp calculate_improvement_score(result) do
    initial = result.initial_evaluation.overall_score
    final = result.final_evaluation.overall_score
    final - initial
  end
  
  defp update_statistics(stats, result) do
    total = stats.total_corrections + 1
    successful = if result.quality_score > 0.8 do
      stats.successful_corrections + 1
    else
      stats.successful_corrections
    end
    
    avg_iterations = ((stats.average_iterations * stats.total_corrections) + result.iterations) / total
    
    original_score = 0.5  # Baseline assumption
    improvement = result.quality_score - original_score
    avg_improvement = ((stats.average_improvement * stats.total_corrections) + improvement) / total
    
    %{stats |
      total_corrections: total,
      successful_corrections: successful,
      average_iterations: avg_iterations,
      average_improvement: avg_improvement
    }
  end
  
  defp generate_cache_key(request) do
    data = "#{request.type}:#{request.content}"
    :crypto.hash(:md5, data) |> Base.encode16()
  end
  
  defp load_strategies() do
    # Load all available correction strategies
    %{
      syntax: RubberDuck.SelfCorrection.Strategies.Syntax,
      semantic: RubberDuck.SelfCorrection.Strategies.Semantic,
      logic: RubberDuck.SelfCorrection.Strategies.Logic
    }
  end
  
  defp validate_request(request) do
    cond do
      !Map.has_key?(request, :content) ->
        {:error, "Missing required field: content"}
      
      !Map.has_key?(request, :type) ->
        {:error, "Missing required field: type"}
      
      request.type not in [:code, :text, :mixed] ->
        {:error, "Unsupported content type: #{request.type}"}
      
      true ->
        :ok
    end
  end
  
  defp perform_analysis(request, state) do
    # Evaluate current content
    initial_evaluation = Evaluator.evaluate(
      request.content,
      request.type,
      Map.get(request, :context, %{}),
      state.strategies
    )
    
    # Run all applicable strategies to find issues
    strategy_analyses = state.strategies
    |> Map.values()
    |> Enum.filter(fn strategy -> 
      request.type in apply(strategy, :supported_types, [])
    end)
    |> Enum.map(fn strategy ->
      apply(strategy, :analyze, [
        request.content,
        request.type,
        Map.get(request, :context, %{}),
        initial_evaluation
      ])
    end)
    
    # Collect all issues and recommendations
    all_issues = strategy_analyses
    |> Enum.flat_map(& &1.issues)
    |> Enum.uniq_by(& &1.type)
    
    recommended_corrections = strategy_analyses
    |> Enum.flat_map(& &1.corrections)
    |> Enum.take(5)
    
    %{
      initial_evaluation: initial_evaluation,
      issues_found: all_issues,
      strategy_analyses: strategy_analyses,
      recommended_corrections: recommended_corrections,
      metadata: %{
        analyzed_at: DateTime.utc_now()
      }
    }
  end
  
  defp record_correction_metrics(result, duration, options) do
    case result do
      {:ok, correction_result} ->
        Metrics.record_pipeline_execution(
          "self_correction",
          %{
            success: true,
            quality_score: correction_result.quality_score,
            iterations: correction_result.iterations
          },
          total_time_ms: duration,
          strategy: Enum.join(options[:strategies], ",")
        )
      
      {:error, _reason} ->
        Metrics.record_pipeline_execution(
          "self_correction",
          %{success: false},
          total_time_ms: duration
        )
    end
  end
end