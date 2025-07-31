defmodule RubberDuck.Jido.Actions.Analysis.AnalyzeCodeAction do
  @moduledoc """
  Action for comprehensive code analysis across multiple dimensions.
  
  This action performs semantic, style, and security analysis on code files,
  providing comprehensive quality assessments and actionable insights.
  """
  
  use Jido.Action,
    name: "analyze_code",
    description: "Performs comprehensive code analysis with semantic, style, and security checks",
    schema: [
      file_path: [
        type: :string,
        required: true,
        doc: "Path to the file to analyze"
      ],
      analysis_types: [
        type: {:list, :atom},
        default: [:semantic, :style, :security],
        doc: "Types of analysis to perform"
      ],
      task_id: [
        type: :string,
        default: nil,
        doc: "Task identifier for tracking"
      ],
      enable_self_correction: [
        type: :boolean,
        default: true,
        doc: "Whether to apply self-correction to results"
      ]
    ]

  alias RubberDuck.Analysis.{Semantic, Style, Security}
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{file_path: file_path, analysis_types: analysis_types} = params
    
    Logger.info("Analyzing code file: #{file_path}")
    
    # Check cache first
    cache_key = {file_path, analysis_types}
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        handle_cache_hit(agent, cached_result, params)
        
      :not_found ->
        handle_cache_miss(agent, params, cache_key)
    end
  end

  # Private functions
  
  defp handle_cache_hit(agent, cached_result, params) do
    Logger.debug("Returning cached analysis for #{params.file_path}")
    
    # Update metrics for cache hit
    with {:ok, _, %{agent: updated_agent}} <- update_metrics(agent, :analyze_code_cached),
         {:ok, _, %{agent: final_agent}} <- update_last_activity(updated_agent) do
      {:ok, cached_result, %{agent: final_agent}}
    end
  end
  
  defp handle_cache_miss(agent, params, cache_key) do
    %{file_path: file_path, analysis_types: analysis_types} = params
    
    # Perform fresh analysis
    case perform_comprehensive_analysis(file_path, analysis_types, params, agent) do
      {:ok, analysis_result} ->
        # Apply self-correction if configured
        final_result = if params.enable_self_correction do
          apply_self_correction(analysis_result, params, agent)
        else
          analysis_result
        end
        
        # Update cache and state
        with {:ok, _, %{agent: cached_agent}} <- update_cache(agent, cache_key, final_result),
             {:ok, _, %{agent: metrics_agent}} <- update_metrics(cached_agent, :analyze_code),
             {:ok, _, %{agent: final_agent}} <- update_last_activity(metrics_agent),
             {:ok, _} <- emit_analysis_result(final_agent, final_result, params) do
          {:ok, final_result, %{agent: final_agent}}
        end
        
      {:error, reason} ->
        Logger.error("Analysis failed for #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp perform_comprehensive_analysis(file_path, analysis_types, params, agent) do
    base_result = %{
      task_id: params.task_id,
      file_path: file_path,
      analysis_results: %{},
      issues_found: [],
      confidence: 0.0,
      timestamp: DateTime.utc_now()
    }
    
    try do
      # Run each analysis type
      result = analysis_types
      |> Enum.reduce(base_result, fn analysis_type, acc ->
        case run_analysis_engine(file_path, analysis_type, params, agent) do
          {:ok, engine_result} ->
            %{
              acc
              | analysis_results: Map.put(acc.analysis_results, analysis_type, engine_result),
                issues_found: acc.issues_found ++ extract_issues(engine_result)
            }
          {:error, reason} ->
            Logger.warning("Analysis engine #{analysis_type} failed: #{inspect(reason)}")
            acc
        end
      end)
      
      # Calculate overall confidence
      final_result = %{result | confidence: calculate_analysis_confidence(result)}
      {:ok, final_result}
      
    rescue
      error ->
        {:error, "Analysis failed: #{Exception.message(error)}"}
    end
  end
  
  defp run_analysis_engine(file_path, :semantic, _params, agent) do
    engine_config = get_in(agent.state.engines, [:semantic, :config]) || %{}
    Semantic.analyze(file_path, engine_config)
  end
  
  defp run_analysis_engine(file_path, :style, _params, agent) do
    engine_config = get_in(agent.state.engines, [:style, :config]) || %{}
    Style.analyze(file_path, engine_config)
  end
  
  defp run_analysis_engine(file_path, :security, _params, agent) do
    engine_config = get_in(agent.state.engines, [:security, :config]) || %{}
    Security.analyze(file_path, engine_config)
  end
  
  defp extract_issues(engine_result) do
    Map.get(engine_result, :issues, [])
  end
  
  defp calculate_analysis_confidence(analysis_result) do
    if Enum.empty?(analysis_result.analysis_results) do
      0.0
    else
      # Average confidence across all engines
      confidences = analysis_result.analysis_results
      |> Map.values()
      |> Enum.map(&Map.get(&1, :confidence, 0.8))
      
      Enum.sum(confidences) / length(confidences)
    end
  end
  
  defp apply_self_correction(analysis_result, params, _agent) do
    case SelfCorrection.correct(%{
           input: analysis_result,
           strategies: [:consistency_check, :false_positive_detection],
           context: params
         }) do
      {:ok, corrected_result} ->
        Map.put(corrected_result, :self_corrected, true)
        
      {:error, _reason} ->
        analysis_result
    end
  end
  
  # State management helpers
  
  defp get_cached_result(agent, cache_key) do
    case Map.get(agent.state.analysis_cache, cache_key) do
      nil -> :not_found
      result -> {:ok, result}
    end
  end
  
  defp update_cache(agent, cache_key, result) do
    state_updates = %{
      analysis_cache: Map.put(agent.state.analysis_cache, cache_key, result)
    }
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_metrics(agent, metric_type) do
    current_metrics = agent.state.metrics
    updated_metrics = current_metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(metric_type, 1, &(&1 + 1))
    
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_last_activity(agent) do
    state_updates = %{last_activity: DateTime.utc_now()}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_analysis_result(agent, result, params) do
    signal_params = %{
      signal_type: "analysis.code.complete",
      data: %{
        task_id: params.task_id,
        file_path: params.file_path,
        result: result,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end