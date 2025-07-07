defmodule RubberDuck.SelfCorrection.Learner do
  @moduledoc """
  Learns from correction history to improve future correction effectiveness.

  Uses historical data to identify patterns, adjust strategy priorities,
  and provide recommendations for better correction outcomes.
  """

  use GenServer
  require Logger

  alias RubberDuck.SelfCorrection.History

  @learning_interval :timer.minutes(15)
  @min_samples_for_learning 10

  # Client API

  @doc """
  Starts the learner process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets learned insights for a specific correction scenario.
  """
  @spec get_insights(atom(), atom(), map()) :: map()
  def get_insights(content_type, issue_type, context \\ %{}) do
    GenServer.call(__MODULE__, {:get_insights, content_type, issue_type, context})
  end

  @doc """
  Updates strategy recommendations based on recent history.
  """
  @spec update_recommendations() :: :ok
  def update_recommendations() do
    GenServer.cast(__MODULE__, :update_recommendations)
  end

  @doc """
  Gets the current strategy effectiveness rankings.
  """
  @spec get_strategy_rankings() :: [map()]
  def get_strategy_rankings() do
    GenServer.call(__MODULE__, :get_strategy_rankings)
  end

  @doc """
  Provides correction suggestions based on learned patterns.
  """
  @spec suggest_corrections(String.t(), atom(), map()) :: [map()]
  def suggest_corrections(content, content_type, context) do
    GenServer.call(__MODULE__, {:suggest_corrections, content, content_type, context})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic learning
    schedule_learning()

    state = %{
      learned_patterns: %{},
      strategy_effectiveness: %{},
      issue_correlations: %{},
      convergence_models: %{},
      last_learning: nil
    }

    # Perform initial learning
    {:ok, state, {:continue, :initial_learning}}
  end

  @impl true
  def handle_continue(:initial_learning, state) do
    Logger.info("Performing initial learning from correction history")
    new_state = perform_learning(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_insights, content_type, issue_type, context}, _from, state) do
    insights = generate_insights(state, content_type, issue_type, context)
    {:reply, insights, state}
  end

  @impl true
  def handle_call(:get_strategy_rankings, _from, state) do
    rankings = calculate_strategy_rankings(state)
    {:reply, rankings, state}
  end

  @impl true
  def handle_call({:suggest_corrections, content, content_type, context}, _from, state) do
    suggestions = generate_correction_suggestions(state, content, content_type, context)
    {:reply, suggestions, state}
  end

  @impl true
  def handle_cast(:update_recommendations, state) do
    new_state = perform_learning(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:scheduled_learning, state) do
    Logger.debug("Running scheduled learning update")

    new_state = perform_learning(state)

    # Schedule next learning
    schedule_learning()

    {:noreply, new_state}
  end

  # Private functions

  defp perform_learning(state) do
    # Get recent history
    history = History.get_history(:all, limit: 1000)

    if length(history) >= @min_samples_for_learning do
      # Learn patterns
      patterns = learn_patterns(history)

      # Calculate strategy effectiveness
      effectiveness = calculate_effectiveness(history)

      # Identify issue correlations
      correlations = find_issue_correlations(history)

      # Model convergence patterns
      convergence = model_convergence_patterns(history)

      %{
        state
        | learned_patterns: patterns,
          strategy_effectiveness: effectiveness,
          issue_correlations: correlations,
          convergence_models: convergence,
          last_learning: DateTime.utc_now()
      }
    else
      Logger.info("Not enough history for learning (#{length(history)} samples)")
      state
    end
  end

  defp learn_patterns(history) do
    # Group by content type and issue type
    grouped =
      Enum.group_by(history, fn entry ->
        {entry.content_type, get_primary_issue_type(entry)}
      end)

    # Analyze each group
    Enum.map(grouped, fn {{content_type, issue_type}, entries} ->
      successful_entries = Enum.filter(entries, & &1.success)

      pattern = %{
        content_type: content_type,
        issue_type: issue_type,
        sample_size: length(entries),
        success_rate: length(successful_entries) / max(1, length(entries)),
        effective_strategies: identify_effective_strategies(successful_entries),
        common_corrections: extract_common_corrections(successful_entries),
        average_iterations: calculate_avg_iterations(entries),
        typical_improvement: calculate_typical_improvement(successful_entries)
      }

      {{content_type, issue_type}, pattern}
    end)
    |> Enum.into(%{})
  end

  defp get_primary_issue_type(entry) do
    # Extract the most common issue type from the entry
    entry.issues_found
    |> Enum.frequencies()
    |> Enum.max_by(fn {_type, count} -> count end, fn -> {:unknown, 0} end)
    |> elem(0)
  end

  defp identify_effective_strategies(entries) do
    entries
    |> Enum.group_by(& &1.strategy)
    |> Enum.map(fn {strategy, strategy_entries} ->
      avg_improvement = calculate_avg_improvement(strategy_entries)
      avg_iterations = calculate_avg_iterations(strategy_entries)

      {strategy,
       %{
         effectiveness: avg_improvement,
         efficiency: 1.0 / max(1, avg_iterations),
         usage_count: length(strategy_entries)
       }}
    end)
    |> Enum.sort_by(fn {_strategy, metrics} -> metrics.effectiveness end, :desc)
    |> Enum.take(3)
  end

  defp extract_common_corrections(entries) do
    entries
    |> Enum.flat_map(& &1.corrections_applied)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_correction, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {correction, count} ->
      %{correction: correction, frequency: count / length(entries)}
    end)
  end

  defp calculate_avg_iterations(entries) when length(entries) == 0, do: 0

  defp calculate_avg_iterations(entries) do
    total = Enum.sum(Enum.map(entries, & &1.iterations))
    total / length(entries)
  end

  defp calculate_avg_improvement(entries) when length(entries) == 0, do: 0

  defp calculate_avg_improvement(entries) do
    improvements =
      entries
      |> Enum.map(& &1.improvement_score)
      |> Enum.filter(&is_number/1)

    if length(improvements) > 0 do
      Enum.sum(improvements) / length(improvements)
    else
      0
    end
  end

  defp calculate_typical_improvement(entries) do
    improvements =
      entries
      |> Enum.map(& &1.improvement_score)
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    if length(improvements) > 0 do
      %{
        min: List.first(improvements),
        max: List.last(improvements),
        median: calculate_median(improvements),
        average: Enum.sum(improvements) / length(improvements)
      }
    else
      %{min: 0, max: 0, median: 0, average: 0}
    end
  end

  defp calculate_median([]), do: 0

  defp calculate_median(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
    else
      Enum.at(sorted_list, mid)
    end
  end

  defp calculate_effectiveness(history) do
    # Group by strategy
    history
    |> Enum.group_by(& &1.strategy)
    |> Enum.map(fn {strategy, entries} ->
      successful = Enum.filter(entries, & &1.success)

      effectiveness = %{
        success_rate: length(successful) / max(1, length(entries)),
        average_improvement: calculate_avg_improvement(successful),
        average_iterations: calculate_avg_iterations(entries),
        convergence_speed: calculate_convergence_speed(entries),
        reliability: calculate_reliability(entries),
        sample_size: length(entries)
      }

      {strategy, effectiveness}
    end)
    |> Enum.into(%{})
  end

  defp calculate_convergence_speed(entries) do
    convergence_times =
      entries
      |> Enum.map(& &1.convergence_time)
      |> Enum.filter(&is_number/1)

    if length(convergence_times) > 0 do
      avg_time = Enum.sum(convergence_times) / length(convergence_times)
      # Convert to speed (inverse of time)
      1.0 / max(0.1, avg_time)
    else
      0
    end
  end

  defp calculate_reliability(entries) do
    # Measure consistency of outcomes
    if length(entries) < 2 do
      # Neutral reliability for small samples
      0.5
    else
      success_rates =
        entries
        |> Enum.chunk_every(10)
        |> Enum.map(fn chunk ->
          successful = Enum.count(chunk, & &1.success)
          successful / length(chunk)
        end)

      # Calculate variance
      mean = Enum.sum(success_rates) / length(success_rates)

      variance =
        Enum.sum(
          Enum.map(success_rates, fn rate ->
            :math.pow(rate - mean, 2)
          end)
        ) / length(success_rates)

      # Convert variance to reliability score (lower variance = higher reliability)
      1.0 - min(1.0, variance)
    end
  end

  defp find_issue_correlations(history) do
    # Find which issues commonly appear together
    issue_pairs =
      history
      |> Enum.flat_map(fn entry ->
        issues = entry.issues_found

        # Generate all pairs
        for i1 <- issues, i2 <- issues, i1 != i2 do
          {min(i1, i2), max(i1, i2)}
        end
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_pair, count} -> count >= 5 end)
      |> Enum.sort_by(fn {_pair, count} -> count end, :desc)
      |> Enum.take(20)

    issue_pairs
  end

  defp model_convergence_patterns(history) do
    # Model how different scenarios converge
    history
    |> Enum.group_by(fn entry ->
      {entry.content_type, entry.strategy}
    end)
    |> Enum.map(fn {{content_type, strategy}, entries} ->
      convergence_data =
        entries
        |> Enum.filter(& &1.success)
        |> Enum.map(fn entry ->
          %{
            iterations: entry.iterations,
            convergence_time: entry.convergence_time,
            improvement: entry.improvement_score,
            initial_issues: length(entry.issues_found)
          }
        end)

      model =
        if length(convergence_data) >= 5 do
          %{
            avg_iterations: calculate_avg_field(convergence_data, :iterations),
            iteration_range: calculate_range(convergence_data, :iterations),
            time_per_iteration: calculate_time_per_iteration(convergence_data),
            improvement_per_iteration: calculate_improvement_rate(convergence_data),
            complexity_factor: calculate_complexity_factor(convergence_data)
          }
        else
          %{insufficient_data: true}
        end

      {{content_type, strategy}, model}
    end)
    |> Enum.into(%{})
  end

  defp calculate_avg_field(data, field) do
    values = Enum.map(data, &Map.get(&1, field, 0))

    if length(values) > 0 do
      Enum.sum(values) / length(values)
    else
      0
    end
  end

  defp calculate_range(data, field) do
    values = Enum.map(data, &Map.get(&1, field, 0))

    if length(values) > 0 do
      {Enum.min(values), Enum.max(values)}
    else
      {0, 0}
    end
  end

  defp calculate_time_per_iteration(data) do
    valid_data =
      Enum.filter(data, fn d ->
        d.iterations > 0 && is_number(d.convergence_time)
      end)

    if length(valid_data) > 0 do
      times =
        Enum.map(valid_data, fn d ->
          d.convergence_time / d.iterations
        end)

      Enum.sum(times) / length(times)
    else
      0
    end
  end

  defp calculate_improvement_rate(data) do
    valid_data =
      Enum.filter(data, fn d ->
        d.iterations > 0 && is_number(d.improvement)
      end)

    if length(valid_data) > 0 do
      rates =
        Enum.map(valid_data, fn d ->
          d.improvement / d.iterations
        end)

      Enum.sum(rates) / length(rates)
    else
      0
    end
  end

  defp calculate_complexity_factor(data) do
    # Estimate complexity based on initial issues and iterations needed
    if length(data) > 0 do
      factors =
        Enum.map(data, fn d ->
          d.initial_issues * d.iterations
        end)

      Enum.sum(factors) / length(factors)
    else
      1.0
    end
  end

  defp generate_insights(state, content_type, issue_type, _context) do
    # Look up learned patterns
    pattern = Map.get(state.learned_patterns, {content_type, issue_type})

    base_insights = %{
      has_historical_data: pattern != nil,
      recommended_strategies: get_recommended_strategies(state, content_type, issue_type),
      expected_iterations: get_expected_iterations(state, content_type, issue_type),
      expected_improvement: get_expected_improvement(state, content_type, issue_type),
      confidence_level: calculate_confidence(pattern),
      tips: generate_tips(state, content_type, issue_type)
    }

    if pattern do
      Map.merge(base_insights, %{
        success_rate: pattern.success_rate,
        sample_size: pattern.sample_size,
        common_corrections: pattern.common_corrections
      })
    else
      base_insights
    end
  end

  defp get_recommended_strategies(state, content_type, issue_type) do
    # Get pattern-specific recommendations
    pattern = Map.get(state.learned_patterns, {content_type, issue_type})

    if pattern && pattern.effective_strategies != [] do
      Enum.map(pattern.effective_strategies, fn {strategy, _metrics} ->
        strategy
      end)
    else
      # Fall back to general effectiveness
      state.strategy_effectiveness
      |> Enum.filter(fn {_strategy, metrics} ->
        metrics.sample_size >= 5
      end)
      |> Enum.sort_by(
        fn {_strategy, metrics} ->
          # Score based on success rate and improvement
          metrics.success_rate * metrics.average_improvement
        end,
        :desc
      )
      |> Enum.take(3)
      |> Enum.map(fn {strategy, _metrics} -> strategy end)
    end
  end

  defp get_expected_iterations(state, content_type, issue_type) do
    # Check convergence model
    convergence_models = state.convergence_models

    # Try specific model first
    avg_iterations =
      convergence_models
      |> Enum.filter(fn {{ct, _strategy}, model} ->
        ct == content_type && !Map.get(model, :insufficient_data, false)
      end)
      |> Enum.map(fn {_key, model} -> model.avg_iterations end)

    if length(avg_iterations) > 0 do
      Enum.sum(avg_iterations) / length(avg_iterations)
    else
      # Fall back to pattern data
      pattern = Map.get(state.learned_patterns, {content_type, issue_type})
      if pattern, do: pattern.average_iterations, else: 3.0
    end
  end

  defp get_expected_improvement(state, content_type, issue_type) do
    pattern = Map.get(state.learned_patterns, {content_type, issue_type})

    if pattern && pattern.typical_improvement do
      pattern.typical_improvement
    else
      %{min: 0.1, max: 0.3, median: 0.2, average: 0.2}
    end
  end

  defp calculate_confidence(nil), do: :low

  defp calculate_confidence(pattern) do
    cond do
      pattern.sample_size >= 50 && pattern.success_rate >= 0.8 -> :high
      pattern.sample_size >= 20 && pattern.success_rate >= 0.6 -> :medium
      true -> :low
    end
  end

  defp generate_tips(state, content_type, issue_type) do
    tips = []

    # Add tips based on correlations
    correlations = Map.get(state.issue_correlations, issue_type, [])

    tips =
      if length(correlations) > 0 do
        correlated =
          correlations
          |> Enum.take(3)
          |> Enum.map(fn {{_i1, i2}, _count} -> i2 end)
          |> Enum.join(", ")

        ["This issue often appears with: #{correlated}" | tips]
      else
        tips
      end

    # Add strategy-specific tips
    pattern = Map.get(state.learned_patterns, {content_type, issue_type})

    if pattern && length(pattern.effective_strategies) > 0 do
      {best_strategy, metrics} = List.first(pattern.effective_strategies)
      tip = "#{best_strategy} strategy has #{Float.round(metrics.effectiveness * 100, 1)}% effectiveness for this issue"
      [tip | tips]
    else
      tips
    end
  end

  defp calculate_strategy_rankings(state) do
    state.strategy_effectiveness
    |> Enum.map(fn {strategy, metrics} ->
      # Calculate composite score
      score = calculate_composite_score(metrics)

      %{
        strategy: strategy,
        score: score,
        success_rate: metrics.success_rate,
        average_improvement: metrics.average_improvement,
        reliability: metrics.reliability,
        sample_size: metrics.sample_size
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp calculate_composite_score(metrics) do
    # Weight different factors
    weights = %{
      success_rate: 0.3,
      average_improvement: 0.3,
      reliability: 0.2,
      convergence_speed: 0.2
    }

    # Normalize sample size impact (diminishing returns)
    sample_factor = :math.log(max(1, metrics.sample_size)) / :math.log(100)
    sample_factor = min(1.0, sample_factor)

    base_score =
      weights.success_rate * metrics.success_rate +
        weights.average_improvement * metrics.average_improvement +
        weights.reliability * metrics.reliability +
        weights.convergence_speed * metrics.convergence_speed

    # Apply sample size factor
    base_score * (0.5 + 0.5 * sample_factor)
  end

  defp generate_correction_suggestions(state, _content, content_type, _context) do
    # Get relevant patterns
    patterns =
      state.learned_patterns
      |> Enum.filter(fn {{ct, _}, _} -> ct == content_type end)
      |> Enum.sort_by(fn {_key, pattern} -> pattern.success_rate end, :desc)
      |> Enum.take(5)

    # Generate suggestions based on patterns
    Enum.flat_map(patterns, fn {{_ct, issue_type}, pattern} ->
      if pattern.sample_size >= 5 do
        pattern.common_corrections
        |> Enum.take(2)
        |> Enum.map(fn correction_info ->
          %{
            issue_type: issue_type,
            correction: correction_info.correction,
            confidence: pattern.success_rate * correction_info.frequency,
            based_on_samples: pattern.sample_size,
            recommended_strategy: get_best_strategy(pattern)
          }
        end)
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  defp get_best_strategy(pattern) do
    if pattern.effective_strategies != [] do
      {strategy, _metrics} = List.first(pattern.effective_strategies)
      strategy
    else
      :auto
    end
  end

  defp schedule_learning() do
    Process.send_after(self(), :scheduled_learning, @learning_interval)
  end
end
