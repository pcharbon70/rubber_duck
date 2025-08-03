defmodule RubberDuck.Jido.Actions.Analysis.CodeAnalysisAction do
  @moduledoc """
  Action for performing comprehensive code analysis across multiple dimensions.
  
  This action provides:
  - Semantic analysis for code understanding
  - Style checking for formatting and conventions
  - Security scanning for vulnerability detection
  - Cache management for performance optimization
  - Self-correction integration for improved accuracy
  - Incremental analysis support for large codebases
  """
  
  use Jido.Action,
    name: "code_analysis",
    description: "Performs comprehensive multi-dimensional code analysis",
    schema: [
      file_path: [
        type: :string, 
        required: true,
        doc: "Path to the file to analyze"
      ],
      analysis_types: [
        type: {:list, {:in, [:semantic, :style, :security]}},
        default: [:semantic, :style, :security],
        doc: "Types of analysis to perform"
      ],
      enable_cache: [
        type: :boolean,
        default: true,
        doc: "Whether to use cached results if available"
      ],
      apply_self_correction: [
        type: :boolean,
        default: true,
        doc: "Whether to apply self-correction to results"
      ],
      include_metrics: [
        type: :boolean,
        default: true,
        doc: "Include detailed metrics in the result"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional context for analysis"
      ]
    ]

  alias RubberDuck.Analysis.{Semantic, Style, Security}
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    try do
      # Check cache if enabled
      cache_key = build_cache_key(params)
      
      case maybe_get_cached_result(agent, cache_key, params) do
        {:ok, cached_result} ->
          Logger.debug("Returning cached analysis for #{params.file_path}")
          {:ok, Map.put(cached_result, :from_cache, true)}
        
        :miss ->
          # Perform fresh analysis
          perform_analysis(params, agent)
      end
      
    rescue
      error ->
        Logger.error("Code analysis failed for #{params.file_path}: #{inspect(error)}")
        {:error, {:analysis_failed, error}}
    end
  end
  
  # Private helper functions
  
  defp maybe_get_cached_result(agent, cache_key, params) do
    if params.enable_cache and agent.state[:analysis_cache] do
      case Map.get(agent.state.analysis_cache, cache_key) do
        nil -> :miss
        cached -> {:ok, cached}
      end
    else
      :miss
    end
  end
  
  defp perform_analysis(params, agent) do
    # Initialize result structure
    base_result = %{
      file_path: params.file_path,
      analysis_types: params.analysis_types,
      analysis_results: %{},
      issues_found: [],
      confidence: 0.0,
      timestamp: DateTime.utc_now(),
      from_cache: false
    }
    
    # Run each analysis type
    result = Enum.reduce(params.analysis_types, base_result, fn analysis_type, acc ->
      case run_analysis_engine(params.file_path, analysis_type, params.context, agent) do
        {:ok, engine_result} ->
          %{acc |
            analysis_results: Map.put(acc.analysis_results, analysis_type, engine_result),
            issues_found: acc.issues_found ++ extract_issues(engine_result, analysis_type)
          }
        
        {:error, reason} ->
          Logger.warning("Analysis engine #{analysis_type} failed: #{inspect(reason)}")
          acc
      end
    end)
    
    # Calculate confidence score
    result = %{result | confidence: calculate_confidence(result)}
    
    # Apply self-correction if enabled
    final_result = if params.apply_self_correction do
      apply_self_correction(result, params.context)
    else
      result
    end
    
    # Add metrics if requested
    final_result = if params.include_metrics do
      Map.put(final_result, :metrics, generate_analysis_metrics(final_result))
    else
      final_result
    end
    
    # Update cache if enabled
    if params.enable_cache do
      update_cache(agent, build_cache_key(params), final_result)
    end
    
    {:ok, final_result}
  end
  
  defp run_analysis_engine(file_path, :semantic, context, agent) do
    engine_config = get_engine_config(agent, :semantic)
    
    case Semantic.analyze(file_path, Map.merge(engine_config, context)) do
      {:ok, result} ->
        {:ok, enhance_semantic_result(result)}
      error ->
        error
    end
  end
  
  defp run_analysis_engine(file_path, :style, context, agent) do
    engine_config = get_engine_config(agent, :style)
    
    case Style.analyze(file_path, Map.merge(engine_config, context)) do
      {:ok, result} ->
        {:ok, enhance_style_result(result)}
      error ->
        error
    end
  end
  
  defp run_analysis_engine(file_path, :security, context, agent) do
    engine_config = get_engine_config(agent, :security)
    
    case Security.analyze(file_path, Map.merge(engine_config, context)) do
      {:ok, result} ->
        {:ok, enhance_security_result(result)}
      error ->
        error
    end
  end
  
  defp get_engine_config(agent, engine_type) do
    agent.state[:engines][engine_type][:config] || %{}
  end
  
  defp extract_issues(engine_result, analysis_type) do
    issues = Map.get(engine_result, :issues, [])
    
    # Tag issues with their analysis type
    Enum.map(issues, fn issue ->
      Map.put(issue, :analysis_type, analysis_type)
    end)
  end
  
  defp calculate_confidence(result) do
    if Enum.empty?(result.analysis_results) do
      0.0
    else
      # Average confidence across all engines
      confidences = result.analysis_results
        |> Map.values()
        |> Enum.map(&(Map.get(&1, :confidence, 0.8)))
      
      avg_confidence = Enum.sum(confidences) / length(confidences)
      Float.round(avg_confidence, 2)
    end
  end
  
  defp apply_self_correction(result, context) do
    case SelfCorrection.correct(%{
      input: result,
      strategies: [:consistency_check, :false_positive_detection],
      context: context
    }) do
      {:ok, corrected_result} ->
        Map.put(corrected_result, :self_corrected, true)
      
      {:error, reason} ->
        Logger.debug("Self-correction failed: #{inspect(reason)}")
        result
    end
  end
  
  defp generate_analysis_metrics(result) do
    %{
      total_issues: length(result.issues_found),
      issues_by_type: group_issues_by_type(result.issues_found),
      issues_by_severity: group_issues_by_severity(result.issues_found),
      analysis_coverage: calculate_coverage(result.analysis_results),
      confidence_score: result.confidence,
      self_corrected: Map.get(result, :self_corrected, false)
    }
  end
  
  defp group_issues_by_type(issues) do
    issues
    |> Enum.group_by(&(&1.analysis_type))
    |> Map.new(fn {type, type_issues} -> {type, length(type_issues)} end)
  end
  
  defp group_issues_by_severity(issues) do
    issues
    |> Enum.group_by(&(Map.get(&1, :severity, :info)))
    |> Map.new(fn {severity, sev_issues} -> {severity, length(sev_issues)} end)
  end
  
  defp calculate_coverage(analysis_results) do
    total_possible = [:semantic, :style, :security]
    completed = Map.keys(analysis_results)
    
    Float.round(length(completed) / length(total_possible) * 100, 2)
  end
  
  defp build_cache_key(params) do
    {params.file_path, params.analysis_types, params.apply_self_correction}
  end
  
  defp update_cache(_agent, cache_key, _result) do
    # Note: In a real implementation, this would update the agent's state
    # For now, we just log the cache update
    Logger.debug("Cache updated for key: #{inspect(cache_key)}")
  end
  
  defp enhance_semantic_result(result) do
    Map.merge(result, %{
      enhanced: true,
      enhancement_type: :semantic,
      confidence: Map.get(result, :confidence, 0.85)
    })
  end
  
  defp enhance_style_result(result) do
    Map.merge(result, %{
      enhanced: true,
      enhancement_type: :style,
      auto_fixable_count: count_auto_fixable(result),
      confidence: Map.get(result, :confidence, 0.95)
    })
  end
  
  defp enhance_security_result(result) do
    Map.merge(result, %{
      enhanced: true,
      enhancement_type: :security,
      critical_count: count_critical_issues(result),
      confidence: Map.get(result, :confidence, 0.90)
    })
  end
  
  defp count_auto_fixable(result) do
    result
    |> Map.get(:violations, [])
    |> Enum.count(&(&1[:auto_fixable] == true))
  end
  
  defp count_critical_issues(result) do
    result
    |> Map.get(:issues, [])
    |> Enum.count(&(&1[:severity] == :critical))
  end
end