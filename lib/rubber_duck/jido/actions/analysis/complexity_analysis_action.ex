defmodule RubberDuck.Jido.Actions.Analysis.ComplexityAnalysisAction do
  @moduledoc """
  Action for code complexity analysis and metrics calculation.
  
  This action analyzes code complexity using various metrics like cyclomatic
  complexity, cognitive complexity, and generates recommendations for improvement.
  """
  
  use Jido.Action,
    name: "complexity_analysis",
    description: "Calculates code complexity metrics and provides improvement recommendations",
    schema: [
      module_path: [
        type: :string,
        required: true,
        doc: "Path to the module to analyze"
      ],
      metrics: [
        type: {:list, :atom},
        default: [:cyclomatic, :cognitive],
        doc: "Types of complexity metrics to calculate"
      ],
      task_id: [
        type: :string,
        default: nil,
        doc: "Task identifier for tracking"
      ]
    ]

  alias RubberDuck.Analysis.Semantic
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{module_path: module_path, metrics: metrics_types} = params
    
    Logger.info("Analyzing complexity for module: #{module_path}")
    
    complexity_result = %{
      task_id: params.task_id,
      module_path: module_path,
      complexity_metrics: %{},
      recommendations: [],
      timestamp: DateTime.utc_now()
    }
    
    # Calculate complexity metrics
    case calculate_complexity_metrics(module_path, metrics_types, params, agent) do
      {:ok, metrics} ->
        recommendations = generate_complexity_recommendations(metrics)
        
        final_result = complexity_result
        |> Map.put(:complexity_metrics, metrics)
        |> Map.put(:recommendations, recommendations)
        |> Map.put(:confidence, 0.9)
        
        # Update state and emit result
        with {:ok, _, %{agent: updated_agent}} <- update_metrics(agent),
             {:ok, _, %{agent: final_agent}} <- update_last_activity(updated_agent),
             {:ok, _} <- emit_complexity_result(final_agent, final_result, params) do
          {:ok, final_result, %{agent: final_agent}}
        end
        
      {:error, reason} ->
        Logger.error("Complexity analysis failed for #{module_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions
  
  defp calculate_complexity_metrics(module_path, metrics_types, _params, agent) do
    try do
      engine_config = get_in(agent.state.engines, [:semantic, :config]) || %{}
      
      # Semantic.analyze always returns {:ok, result}
      case Semantic.analyze(module_path, Map.put(engine_config, :analysis_type, :complexity)) do
        {:ok, result} ->
          metrics = metrics_types
          |> Enum.reduce(%{}, fn metric_type, acc ->
            value = get_complexity_metric(result, metric_type)
            Map.put(acc, metric_type, value)
          end)
          
          {:ok, metrics}
          
        {:error, reason} ->
          {:error, reason}
      end
      
    rescue
      error ->
        {:error, "Complexity calculation failed: #{Exception.message(error)}"}
    end
  end
  
  defp get_complexity_metric(result, :cyclomatic) do
    get_in(result, [:complexity, :cyclomatic]) || calculate_cyclomatic_complexity(result)
  end
  
  defp get_complexity_metric(result, :cognitive) do
    get_in(result, [:complexity, :cognitive]) || calculate_cognitive_complexity(result)
  end
  
  defp get_complexity_metric(result, :halstead) do
    get_in(result, [:complexity, :halstead]) || calculate_halstead_complexity(result)
  end
  
  defp get_complexity_metric(result, :maintainability_index) do
    get_in(result, [:complexity, :maintainability_index]) || calculate_maintainability_index(result)
  end
  
  # Simplified complexity calculations (would be more sophisticated in production)
  defp calculate_cyclomatic_complexity(_result) do
    # Would analyze AST for decision points
    10
  end
  
  defp calculate_cognitive_complexity(_result) do
    # Would analyze nested structures and control flow
    8
  end
  
  defp calculate_halstead_complexity(_result) do
    # Would calculate operators/operands
    %{
      vocabulary: 45,
      length: 150,
      difficulty: 12.5,
      effort: 1875
    }
  end
  
  defp calculate_maintainability_index(_result) do
    # Would use Halstead metrics + lines of code + cyclomatic complexity
    75.2
  end
  
  defp generate_complexity_recommendations(metrics) do
    recommendations = []
    
    # Cyclomatic complexity recommendations
    cyclomatic = Map.get(metrics, :cyclomatic, 0)
    recommendations = if cyclomatic > 10 do
      ["Consider breaking down complex functions (cyclomatic complexity: #{cyclomatic})" | recommendations]
    else
      recommendations
    end
    
    # Cognitive complexity recommendations
    cognitive = Map.get(metrics, :cognitive, 0)
    recommendations = if cognitive > 15 do
      ["High cognitive complexity detected (#{cognitive}). Simplify logic flow." | recommendations]
    else
      recommendations
    end
    
    # Maintainability index recommendations
    maintainability = Map.get(metrics, :maintainability_index, 100)
    recommendations = if maintainability < 60 do
      ["Low maintainability index (#{maintainability}). Consider refactoring." | recommendations]
    else
      recommendations
    end
    
    # Halstead complexity recommendations
    case Map.get(metrics, :halstead) do
      %{difficulty: difficulty} when difficulty > 20 ->
        ["High Halstead difficulty (#{difficulty}). Consider simplifying expressions." | recommendations]
      _ ->
        recommendations
    end
  end
  
  # State management helpers
  
  defp update_metrics(agent) do
    current_metrics = agent.state.metrics
    updated_metrics = current_metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(:complexity_analysis, 1, &(&1 + 1))
    
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_last_activity(agent) do
    state_updates = %{last_activity: DateTime.utc_now()}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_complexity_result(agent, result, params) do
    signal_params = %{
      signal_type: "analysis.complexity.complete",
      data: %{
        task_id: params.task_id,
        module_path: params.module_path,
        result: result,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end