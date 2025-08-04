defmodule RubberDuck.Jido.Actions.Correction.PerformanceMetricsAction do
  @moduledoc """
  Action for collecting and reporting strategy performance metrics.
  
  This action provides comprehensive analytics on strategy effectiveness,
  learning progress, and cost prediction accuracy.
  """
  
  use Jido.Action,
    name: "performance_metrics",
    description: "Collect and analyze strategy performance metrics",
    schema: [
      metrics_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for this metrics request"
      ],
      time_range: [
        type: {:in, [:all_time, :last_30_days, :last_7_days, :last_24_hours]},
        default: :all_time,
        doc: "Time range for metrics collection"
      ],
      include_strategies: [
        type: {:list, :string},
        default: [],
        doc: "Specific strategies to include (empty for all)"
      ],
      include_trends: [
        type: :boolean,
        default: true,
        doc: "Include trend analysis"
      ],
      include_predictions: [
        type: :boolean,
        default: true,
        doc: "Include prediction accuracy metrics"
      ],
      group_by: [
        type: {:in, [:strategy, :error_type, :complexity, :time_period]},
        default: :strategy,
        doc: "How to group the metrics"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    Logger.info("Collecting performance metrics for request: #{params.metrics_id}")
    
    # Filter metrics based on time range
    filtered_history = filter_by_time_range(
      agent.state.learning_data["outcome_history"] || [],
      params.time_range
    )
    
    # Filter by specific strategies if requested
    filtered_history = if length(params.include_strategies) > 0 do
      Enum.filter(filtered_history, & &1["strategy_id"] in params.include_strategies)
    else
      filtered_history
    end
    
    # Collect base metrics
    base_metrics = collect_base_metrics(
      agent.state.performance_metrics,
      filtered_history
    )
    
    # Group metrics as requested
    grouped_metrics = group_metrics(
      filtered_history,
      params.group_by
    )
    
    # Add trend analysis if requested
    metrics_with_trends = if params.include_trends do
      add_trend_analysis(base_metrics, filtered_history, params.group_by)
    else
      base_metrics
    end
    
    # Add prediction accuracy if requested
    final_metrics = if params.include_predictions do
      add_prediction_metrics(metrics_with_trends, filtered_history)
    else
      metrics_with_trends
    end
    
    # Generate insights and recommendations
    insights = generate_insights(final_metrics, grouped_metrics)
    
    result = %{
      metrics_id: params.metrics_id,
      time_range: params.time_range,
      metrics: final_metrics,
      grouped_metrics: grouped_metrics,
      insights: insights,
      data_points: length(filtered_history),
      collection_timestamp: DateTime.utc_now()
    }
    
    {:ok, result}
  rescue
    error ->
      Logger.error("Performance metrics collection failed: #{inspect(error)}")
      {:error, %{reason: :metrics_collection_failed, details: Exception.message(error)}}
  end
  
  # Private helper functions
  
  defp filter_by_time_range(history, :all_time), do: history
  
  defp filter_by_time_range(history, time_range) do
    cutoff_time = calculate_cutoff_time(time_range)
    
    Enum.filter(history, fn entry ->
      case DateTime.from_iso8601(entry["timestamp"] || "") do
        {:ok, timestamp, _} ->
          DateTime.compare(timestamp, cutoff_time) == :gt
        _ ->
          false
      end
    end)
  end
  
  defp calculate_cutoff_time(time_range) do
    now = DateTime.utc_now()
    
    case time_range do
      :last_24_hours ->
        DateTime.add(now, -24 * 3600, :second)
      :last_7_days ->
        DateTime.add(now, -7 * 24 * 3600, :second)
      :last_30_days ->
        DateTime.add(now, -30 * 24 * 3600, :second)
      _ ->
        now
    end
  end
  
  defp collect_base_metrics(performance_metrics, filtered_history) do
    overall = performance_metrics["overall"] || %{}
    
    # Calculate success metrics
    total_attempts = length(filtered_history)
    successful_attempts = Enum.count(filtered_history, & &1["success"])
    success_rate = if total_attempts > 0 do
      successful_attempts / total_attempts
    else
      0.0
    end
    
    # Calculate cost metrics
    costs = filtered_history
    |> Enum.map(& &1["actual_cost"] || 0.0)
    |> Enum.filter(& &1 > 0)
    
    avg_cost = if length(costs) > 0 do
      Enum.sum(costs) / length(costs)
    else
      0.0
    end
    
    # Calculate time metrics
    times = filtered_history
    |> Enum.map(& &1["execution_time"] || 0)
    |> Enum.filter(& &1 > 0)
    
    avg_time = if length(times) > 0 do
      Enum.sum(times) / length(times)
    else
      0.0
    end
    
    %{
      overall: Map.merge(overall, %{
        "total_attempts" => total_attempts,
        "successful_attempts" => successful_attempts,
        "success_rate" => Float.round(success_rate, 3),
        "avg_cost" => Float.round(avg_cost, 2),
        "avg_execution_time" => Float.round(avg_time, 1),
        "min_cost" => if(length(costs) > 0, do: Enum.min(costs), else: 0.0),
        "max_cost" => if(length(costs) > 0, do: Enum.max(costs), else: 0.0),
        "min_time" => if(length(times) > 0, do: Enum.min(times), else: 0),
        "max_time" => if(length(times) > 0, do: Enum.max(times), else: 0)
      }),
      by_strategy: collect_strategy_metrics(filtered_history)
    }
  end
  
  defp collect_strategy_metrics(history) do
    history
    |> Enum.group_by(& &1["strategy_id"])
    |> Enum.map(fn {strategy_id, entries} ->
      total = length(entries)
      successful = Enum.count(entries, & &1["success"])
      
      costs = Enum.map(entries, & &1["actual_cost"] || 0.0)
      times = Enum.map(entries, & &1["execution_time"] || 0)
      
      {strategy_id, %{
        "total_attempts" => total,
        "successful_attempts" => successful,
        "success_rate" => Float.round(successful / total, 3),
        "avg_cost" => Float.round(Enum.sum(costs) / length(costs), 2),
        "avg_execution_time" => Float.round(Enum.sum(times) / length(times), 1),
        "last_used" => get_last_used(entries)
      }}
    end)
    |> Map.new()
  end
  
  defp get_last_used(entries) do
    entries
    |> Enum.map(& &1["timestamp"])
    |> Enum.filter(& &1)
    |> Enum.sort()
    |> List.last()
  end
  
  defp group_metrics(history, :strategy) do
    # Already grouped by strategy in base metrics
    %{grouping: :strategy, note: "See by_strategy in main metrics"}
  end
  
  defp group_metrics(history, :error_type) do
    history
    |> Enum.group_by(& get_in(&1, ["error_context", "error_type"]) || "unknown")
    |> Enum.map(fn {error_type, entries} ->
      {error_type, calculate_group_metrics(entries)}
    end)
    |> Map.new()
  end
  
  defp group_metrics(history, :complexity) do
    history
    |> Enum.group_by(& get_in(&1, ["error_context", "complexity"]) || "unknown")
    |> Enum.map(fn {complexity, entries} ->
      {complexity, calculate_group_metrics(entries)}
    end)
    |> Map.new()
  end
  
  defp group_metrics(history, :time_period) do
    history
    |> Enum.group_by(&get_time_period/1)
    |> Enum.map(fn {period, entries} ->
      {period, calculate_group_metrics(entries)}
    end)
    |> Map.new()
  end
  
  defp get_time_period(entry) do
    case DateTime.from_iso8601(entry["timestamp"] || "") do
      {:ok, timestamp, _} ->
        Date.to_string(DateTime.to_date(timestamp))
      _ ->
        "unknown"
    end
  end
  
  defp calculate_group_metrics(entries) do
    total = length(entries)
    successful = Enum.count(entries, & &1["success"])
    
    %{
      "count" => total,
      "success_rate" => Float.round(successful / max(total, 1), 3),
      "strategies_used" => entries |> Enum.map(& &1["strategy_id"]) |> Enum.uniq() |> length()
    }
  end
  
  defp add_trend_analysis(metrics, history, group_by) do
    # Sort history by timestamp
    sorted_history = Enum.sort_by(history, & &1["timestamp"])
    
    # Calculate rolling success rate
    window_size = 10
    rolling_rates = calculate_rolling_success_rates(sorted_history, window_size)
    
    # Determine trend direction
    trend = determine_overall_trend(rolling_rates)
    
    # Add trend data to metrics
    Map.put(metrics, :trends, %{
      overall_trend: trend,
      rolling_success_rates: rolling_rates,
      window_size: window_size,
      trend_by_group: calculate_group_trends(history, group_by)
    })
  end
  
  defp calculate_rolling_success_rates(history, window_size) do
    if length(history) >= window_size do
      history
      |> Enum.chunk_every(window_size, 1, :discard)
      |> Enum.map(fn window ->
        successful = Enum.count(window, & &1["success"])
        %{
          rate: Float.round(successful / window_size, 3),
          timestamp: List.last(window)["timestamp"]
        }
      end)
    else
      []
    end
  end
  
  defp determine_overall_trend(rolling_rates) do
    if length(rolling_rates) >= 2 do
      first_half = Enum.take(rolling_rates, div(length(rolling_rates), 2))
      second_half = Enum.drop(rolling_rates, div(length(rolling_rates), 2))
      
      avg_first = Enum.sum(Enum.map(first_half, & &1.rate)) / max(length(first_half), 1)
      avg_second = Enum.sum(Enum.map(second_half, & &1.rate)) / max(length(second_half), 1)
      
      cond do
        avg_second > avg_first + 0.05 -> :improving
        avg_second < avg_first - 0.05 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end
  
  defp calculate_group_trends(history, group_by) do
    # Simplified trend calculation by group
    case group_by do
      :strategy ->
        history
        |> Enum.group_by(& &1["strategy_id"])
        |> Enum.map(fn {strategy, entries} ->
          {strategy, determine_strategy_trend(entries)}
        end)
        |> Map.new()
      _ ->
        %{}
    end
  end
  
  defp determine_strategy_trend(entries) do
    if length(entries) >= 5 do
      recent = Enum.take(entries, -5)
      older = Enum.take(entries, 5)
      
      recent_rate = Enum.count(recent, & &1["success"]) / 5
      older_rate = Enum.count(older, & &1["success"]) / 5
      
      cond do
        recent_rate > older_rate + 0.1 -> :improving
        recent_rate < older_rate - 0.1 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end
  
  defp add_prediction_metrics(metrics, history) do
    predictions_with_actuals = history
    |> Enum.filter(& &1["predicted_cost"] && &1["actual_cost"])
    
    if length(predictions_with_actuals) > 0 do
      accuracies = Enum.map(predictions_with_actuals, fn entry ->
        predicted = entry["predicted_cost"]
        actual = entry["actual_cost"]
        error = abs(predicted - actual) / max(actual, 0.01)
        error <= 0.2  # Within 20% is accurate
      end)
      
      accuracy_rate = Enum.count(accuracies, & &1) / length(accuracies)
      
      # Calculate mean absolute percentage error (MAPE)
      mape = predictions_with_actuals
      |> Enum.map(fn entry ->
        predicted = entry["predicted_cost"]
        actual = entry["actual_cost"]
        abs(predicted - actual) / max(actual, 0.01) * 100
      end)
      |> then(fn errors -> Enum.sum(errors) / length(errors) end)
      
      Map.put(metrics, :prediction_accuracy, %{
        accuracy_rate: Float.round(accuracy_rate, 3),
        mape: Float.round(mape, 1),
        sample_size: length(predictions_with_actuals),
        confidence: calculate_prediction_confidence(accuracy_rate, length(predictions_with_actuals))
      })
    else
      Map.put(metrics, :prediction_accuracy, %{
        note: "No predictions with actuals available"
      })
    end
  end
  
  defp calculate_prediction_confidence(accuracy_rate, sample_size) do
    # Higher confidence with better accuracy and more samples
    base_confidence = accuracy_rate
    sample_factor = :math.log(max(sample_size, 1) + 1) / :math.log(100)
    
    Float.round(base_confidence * (0.5 + sample_factor * 0.5), 2)
  end
  
  defp generate_insights(metrics, grouped_metrics) do
    insights = []
    
    # Overall performance insight
    overall = metrics.overall
    insights = if overall["success_rate"] >= 0.8 do
      ["High overall success rate (#{Float.round(overall["success_rate"] * 100, 1)}%)" | insights]
    else
      ["Success rate could be improved (currently #{Float.round(overall["success_rate"] * 100, 1)}%)" | insights]
    end
    
    # Cost efficiency insight
    insights = if overall["avg_cost"] > 0 do
      ["Average correction cost: #{overall["avg_cost"]} units" | insights]
    else
      insights
    end
    
    # Trend insight
    insights = if Map.has_key?(metrics, :trends) do
      trend_msg = case metrics.trends.overall_trend do
        :improving -> "Performance is improving over time"
        :declining -> "Performance is declining - investigation recommended"
        :stable -> "Performance is stable"
        _ -> "Insufficient data for trend analysis"
      end
      [trend_msg | insights]
    else
      insights
    end
    
    # Best performing strategies
    insights = if Map.has_key?(metrics, :by_strategy) do
      best_strategies = metrics.by_strategy
      |> Enum.filter(fn {_id, data} -> data["total_attempts"] >= 3 end)
      |> Enum.sort_by(fn {_id, data} -> -data["success_rate"] end)
      |> Enum.take(3)
      |> Enum.map(fn {id, data} -> 
        "#{id}: #{Float.round(data["success_rate"] * 100, 1)}% success"
      end)
      
      if length(best_strategies) > 0 do
        ["Top strategies: " <> Enum.join(best_strategies, ", ") | insights]
      else
        insights
      end
    else
      insights
    end
    
    # Recommendations
    recommendations = generate_recommendations(metrics, grouped_metrics)
    
    %{
      insights: insights,
      recommendations: recommendations
    }
  end
  
  defp generate_recommendations(metrics, _grouped_metrics) do
    recommendations = []
    
    # Check if certain strategies are underperforming
    recommendations = if Map.has_key?(metrics, :by_strategy) do
      poor_performers = metrics.by_strategy
      |> Enum.filter(fn {_id, data} -> 
        data["total_attempts"] >= 5 && data["success_rate"] < 0.5
      end)
      |> Enum.map(fn {id, _data} -> id end)
      
      if length(poor_performers) > 0 do
        ["Review or retire strategies: #{Enum.join(poor_performers, ", ")}" | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end
    
    # Check prediction accuracy
    recommendations = if get_in(metrics, [:prediction_accuracy, :mape]) do
      mape = metrics.prediction_accuracy.mape
      if mape > 30 do
        ["Cost prediction accuracy needs improvement (MAPE: #{mape}%)" | recommendations]
      else
        recommendations
      end
    else
      recommendations
    end
    
    recommendations
  end
end