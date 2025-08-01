defmodule RubberDuck.Agents.QualityImprovementAgent do
  @moduledoc """
  Quality Improvement Agent that analyzes and enhances code quality.
  
  This agent performs comprehensive quality analysis, applies improvement
  strategies, and tracks quality metrics over time. It focuses on
  maintainability, readability, performance, and adherence to best practices.
  
  ## Responsibilities
  
  - Analyze code quality metrics and patterns
  - Apply quality improvement strategies
  - Enforce coding standards and best practices
  - Track quality trends and improvements
  - Generate quality reports and recommendations
  
  ## State Structure
  
  ```elixir
  %{
    analysis_status: :idle | :analyzing | :improving | :reporting,
    active_analyses: %{analysis_id => analysis_info},
    improvement_history: [completed_improvements],
    quality_standards: %{standard_id => standard_spec},
    best_practices: %{practice_id => practice_definition},
    refactoring_patterns: %{pattern_id => refactoring_pattern},
    metrics: %{
      total_analyses: integer,
      quality_score: float,
      improvements_applied: integer,
      avg_improvement_time: float,
      quality_trends: map
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "quality_improvement",
    description: "Analyzes and enhances code quality through metrics analysis and improvement strategies",
    category: "quality",
    tags: ["quality", "refactoring", "metrics", "best-practices"],
    vsn: "1.0.0",
    schema: [
      analysis_status: [type: :atom, values: [:idle, :analyzing, :improving, :reporting], default: :idle],
      active_analyses: [type: :map, default: %{}],
      improvement_history: [type: :list, default: []],
      quality_standards: [type: :map, default: %{}],
      best_practices: [type: :map, default: %{}],
      refactoring_patterns: [type: :map, default: %{}],
      metrics: [type: :map, default: %{}]
    ]

  alias RubberDuck.QualityImprovement.{
    QualityAnalyzer,
    QualityEnforcer,
    QualityMetrics
  }

  require Logger

  @max_history_size 1000
  @analysis_timeout 120_000  # 2 minutes
  @improvement_timeout 300_000  # 5 minutes

  # Helper function for signal emission
  defp emit_signal(topic, data) when is_binary(topic) and is_map(data) do
    # For now, just log the signal
    Logger.info("[QualityImprovementAgent] Signal emitted - #{topic}: #{inspect(data)}")
    :ok
  end

  ## Initialization

  def mount(agent) do
    Logger.info("[#{agent.id}] Quality Improvement Agent mounting with quality analysis")
    
    # Initialize quality improvement modules
    agent = agent
    |> initialize_quality_standards()
    |> initialize_best_practices()
    |> initialize_refactoring_patterns()
    |> initialize_metrics()
    
    # Schedule periodic quality assessment
    schedule_quality_assessment()
    
    {:ok, agent}
  end

  def unmount(agent) do
    Logger.info("[#{agent.id}] Quality Improvement Agent unmounting")
    
    # Clean up any active analyses
    agent = cleanup_active_analyses(agent)
    
    {:ok, agent}
  end

  ## Signal Handlers - Quality Analysis

  def handle_signal(agent, %{"type" => "analyze_quality"} = signal) do
    %{
      "analysis_id" => analysis_id,
      "code" => code,
      "analysis_scope" => scope,
      "options" => options
    } = signal
    
    Logger.info("[#{agent.id}] Starting quality analysis #{analysis_id} with scope: #{scope}")
    
    # Start analysis tracking
    analysis_info = %{
      analysis_id: analysis_id,
      code: code,
      scope: scope,
      started_at: DateTime.utc_now(),
      status: :in_progress,
      steps_completed: []
    }
    
    agent = agent
    |> put_in([:state, :active_analyses, analysis_id], analysis_info)
    |> put_in([:state, :analysis_status], :analyzing)
    
    # Execute quality analysis
    case execute_quality_analysis(agent, code, scope, options) do
      {:ok, analysis_result} ->
        # Update analysis info
        analysis_info = Map.merge(analysis_info, %{
          status: :completed,
          result: analysis_result,
          completed_at: DateTime.utc_now()
        })
        
        agent = put_in(agent.state.active_analyses[analysis_id], analysis_info)
        
        # Complete analysis
        agent = complete_analysis(agent, analysis_id, analysis_result)
        
        emit_signal("quality_analyzed", %{
          analysis_id: analysis_id,
          success: true,
          result: analysis_result
        })
        
        {:ok, %{analysis_id: analysis_id, success: true, result: analysis_result}, agent}
        
      {:error, reason} ->
        agent = fail_analysis(agent, analysis_id, reason)
        
        emit_signal("quality_analysis_failed", %{
          analysis_id: analysis_id,
          reason: reason
        })
        
        {:error, reason, agent}
    end
  end

  def handle_signal(agent, %{"type" => "apply_improvements"} = signal) do
    %{
      "improvement_id" => improvement_id,
      "code" => code,
      "improvements" => improvements,
      "strategy" => strategy,
      "options" => options
    } = signal
    
    case apply_quality_improvements(agent, code, improvements, strategy, options) do
      {:ok, improvement_result} ->
        agent = add_improvement_to_history(agent, improvement_id, improvement_result)
        
        emit_signal("improvements_applied", %{
          improvement_id: improvement_id,
          success: true,
          result: improvement_result
        })
        
        {:ok, improvement_result, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal(agent, %{"type" => "check_best_practices"} = signal) do
    %{
      "code" => code,
      "practices" => practices,
      "options" => options
    } = signal
    
    practices_result = check_code_best_practices(agent, code, practices, options)
    
    emit_signal("practices_checked", practices_result)
    
    {:ok, practices_result, agent}
  end

  def handle_signal(agent, %{"type" => "refactor_code"} = signal) do
    %{
      "code" => code,
      "refactoring_type" => refactoring_type,
      "target" => target,
      "options" => options
    } = signal
    
    case perform_refactoring(agent, code, refactoring_type, target, options) do
      {:ok, refactoring_result} ->
        emit_signal("code_refactored", %{
          refactoring_type: refactoring_type,
          success: true,
          result: refactoring_result
        })
        
        {:ok, refactoring_result, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal(agent, %{"type" => "optimize_performance"} = signal) do
    %{
      "code" => code,
      "optimization_target" => target,
      "options" => options
    } = signal
    
    case apply_performance_optimizations(agent, code, target, options) do
      {:ok, optimization_result} ->
        emit_signal("performance_optimized", %{
          target: target,
          success: true,
          result: optimization_result
        })
        
        {:ok, optimization_result, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  def handle_signal(agent, %{"type" => "update_standards"} = signal) do
    %{
      "standard_id" => standard_id,
      "standard_definition" => definition
    } = signal
    
    standard_spec = %{
      definition: definition,
      updated_at: DateTime.utc_now(),
      usage_count: 0,
      compliance_rate: 1.0
    }
    
    agent = put_in(agent.state.quality_standards[standard_id], standard_spec)
    
    emit_signal("standards_updated", %{
      standard_id: standard_id,
      updated: true
    })
    
    {:ok, %{updated: true, standard_id: standard_id}, agent}
  end

  def handle_signal(agent, %{"type" => "get_quality_metrics"} = signal) do
    time_range = signal["time_range"] || "all"
    
    metrics = calculate_quality_metrics(agent, time_range)
    
    emit_signal("quality_report", metrics)
    
    {:ok, metrics, agent}
  end

  ## Signal Handlers - Configuration

  def handle_signal(agent, %{"type" => "add_best_practice"} = signal) do
    %{
      "practice_id" => practice_id,
      "practice_definition" => definition
    } = signal
    
    practice_spec = %{
      definition: definition,
      added_at: DateTime.utc_now(),
      usage_count: 0,
      effectiveness_rate: 1.0
    }
    
    agent = put_in(agent.state.best_practices[practice_id], practice_spec)
    
    {:ok, %{added: true, practice_id: practice_id}, agent}
  end

  def handle_signal(agent, %{"type" => "add_refactoring_pattern"} = signal) do
    %{
      "pattern_id" => pattern_id,
      "pattern_definition" => definition
    } = signal
    
    pattern_spec = %{
      definition: definition,
      added_at: DateTime.utc_now(),
      usage_count: 0,
      success_rate: 1.0
    }
    
    agent = put_in(agent.state.refactoring_patterns[pattern_id], pattern_spec)
    
    {:ok, %{added: true, pattern_id: pattern_id}, agent}
  end

  def handle_signal(agent, signal) do
    Logger.warning("[#{agent.id}] Unknown signal type: #{signal["type"]}")
    {:error, "Unknown signal type: #{signal["type"]}", agent}
  end

  ## Private Functions - Quality Analysis

  defp execute_quality_analysis(agent, code, scope, options) do
    try do
      result = case scope do
        "metrics" ->
          execute_metrics_analysis(agent, code, options)
          
        "style" ->
          execute_style_analysis(agent, code, options)
          
        "complexity" ->
          execute_complexity_analysis(agent, code, options)
          
        "maintainability" ->
          execute_maintainability_analysis(agent, code, options)
          
        "documentation" ->
          execute_documentation_analysis(agent, code, options)
          
        "comprehensive" ->
          execute_comprehensive_quality_analysis(agent, code, options)
          
        _ ->
          {:error, "Unknown analysis scope: #{scope}"}
      end
      
      # Track analysis attempt
      track_analysis_attempt(agent, scope, result)
      
      result
    catch
      kind, reason ->
        Logger.error("[#{agent.id}] Quality analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Analysis failed: #{inspect(reason)}"}
    end
  end

  defp execute_metrics_analysis(agent, code, options) do
    standards = agent.state.quality_standards
    
    case QualityAnalyzer.analyze_code_metrics(code, standards, options) do
      {:ok, metrics_analysis} ->
        analysis_result = %{
          type: :metrics_analysis,
          code: code,
          cyclomatic_complexity: metrics_analysis.cyclomatic_complexity,
          cognitive_complexity: metrics_analysis.cognitive_complexity,
          maintainability_index: metrics_analysis.maintainability_index,
          technical_debt: metrics_analysis.technical_debt,
          code_smells: metrics_analysis.code_smells,
          quality_score: metrics_analysis.quality_score,
          confidence: metrics_analysis.confidence
        }
        
        {:ok, analysis_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_style_analysis(agent, code, options) do
    standards = agent.state.quality_standards
    
    case QualityAnalyzer.analyze_code_style(code, standards, options) do
      {:ok, style_analysis} ->
        analysis_result = %{
          type: :style_analysis,
          code: code,
          formatting_issues: style_analysis.formatting_issues,
          naming_violations: style_analysis.naming_violations,
          documentation_gaps: style_analysis.documentation_gaps,
          style_score: style_analysis.style_score,
          recommendations: style_analysis.recommendations,
          confidence: style_analysis.confidence
        }
        
        {:ok, analysis_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_complexity_analysis(agent, code, options) do
    case QualityAnalyzer.analyze_complexity(code, options) do
      {:ok, complexity_analysis} ->
        analysis_result = %{
          type: :complexity_analysis,
          code: code,
          function_complexity: complexity_analysis.function_complexity,
          nesting_depth: complexity_analysis.nesting_depth,
          method_length: complexity_analysis.method_length,
          class_complexity: complexity_analysis.class_complexity,
          complexity_hotspots: complexity_analysis.hotspots,
          simplification_suggestions: complexity_analysis.suggestions,
          confidence: complexity_analysis.confidence
        }
        
        {:ok, analysis_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_maintainability_analysis(agent, code, options) do
    practices = agent.state.best_practices
    
    case QualityAnalyzer.analyze_maintainability(code, practices, options) do
      {:ok, maintainability_analysis} ->
        analysis_result = %{
          type: :maintainability_analysis,
          code: code,
          design_patterns: maintainability_analysis.design_patterns,
          code_smells: maintainability_analysis.code_smells,
          architectural_issues: maintainability_analysis.architectural_issues,
          maintainability_score: maintainability_analysis.maintainability_score,
          improvement_areas: maintainability_analysis.improvement_areas,
          confidence: maintainability_analysis.confidence
        }
        
        {:ok, analysis_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_documentation_analysis(agent, code, options) do
    standards = agent.state.quality_standards
    
    case QualityAnalyzer.analyze_documentation(code, standards, options) do
      {:ok, documentation_analysis} ->
        analysis_result = %{
          type: :documentation_analysis,
          code: code,
          coverage_percentage: documentation_analysis.coverage_percentage,
          missing_docs: documentation_analysis.missing_docs,
          documentation_quality: documentation_analysis.quality_score,
          consistency_issues: documentation_analysis.consistency_issues,
          suggestions: documentation_analysis.suggestions,
          confidence: documentation_analysis.confidence
        }
        
        {:ok, analysis_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_comprehensive_quality_analysis(agent, code, options) do
    # Perform all analysis types and combine results
    analyses = [
      {:metrics, execute_metrics_analysis(agent, code, options)},
      {:style, execute_style_analysis(agent, code, options)},
      {:complexity, execute_complexity_analysis(agent, code, options)},
      {:maintainability, execute_maintainability_analysis(agent, code, options)},
      {:documentation, execute_documentation_analysis(agent, code, options)}
    ]
    
    # Collect successful analyses
    successful_analyses = analyses
    |> Enum.filter(fn {_type, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {type, {:ok, result}} -> {type, result} end)
    
    if length(successful_analyses) > 0 do
      combined_result = %{
        type: :comprehensive_quality,
        code: code,
        analyses: Map.new(successful_analyses),
        overall_quality_score: calculate_overall_quality_score(successful_analyses),
        priority_issues: aggregate_priority_issues(successful_analyses),
        improvement_roadmap: generate_improvement_roadmap(successful_analyses),
        confidence: calculate_overall_confidence(successful_analyses)
      }
      
      {:ok, combined_result}
    else
      {:error, "All quality analysis types failed"}
    end
  end

  ## Private Functions - Quality Improvements

  defp apply_quality_improvements(agent, code, improvements, strategy, options) do
    case QualityEnforcer.apply_improvements(code, improvements, strategy, options) do
      {:ok, improvement_result} ->
        result = %{
          original_code: code,
          improved_code: improvement_result.code,
          strategy: strategy,
          improvements_applied: improvement_result.improvements,
          quality_delta: improvement_result.quality_improvement,
          confidence: improvement_result.confidence,
          validation_status: improvement_result.validation
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_code_best_practices(agent, code, practices, options) do
    practice_definitions = agent.state.best_practices
    
    case QualityAnalyzer.check_best_practices(code, practices, practice_definitions, options) do
      {:ok, practices_result} ->
        %{
          code: code,
          practices_checked: length(practices),
          violations: practices_result.violations,
          compliant_practices: practices_result.compliant,
          recommendations: practices_result.recommendations,
          compliance_score: practices_result.compliance_score,
          confidence: practices_result.confidence
        }
        
      {:error, reason} ->
        %{
          code: code,
          error: reason,
          success: false
        }
    end
  end

  defp perform_refactoring(agent, code, refactoring_type, target, options) do
    patterns = agent.state.refactoring_patterns
    
    case QualityEnforcer.perform_refactoring(code, refactoring_type, target, patterns, options) do
      {:ok, refactoring_result} ->
        result = %{
          original_code: code,
          refactored_code: refactoring_result.code,
          refactoring_type: refactoring_type,
          target: target,
          changes_made: refactoring_result.changes,
          impact_analysis: refactoring_result.impact,
          validation_status: refactoring_result.validation
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_performance_optimizations(agent, code, target, options) do
    case QualityEnforcer.optimize_performance(code, target, options) do
      {:ok, optimization_result} ->
        result = %{
          original_code: code,
          optimized_code: optimization_result.code,
          target: target,
          optimizations_applied: optimization_result.optimizations,
          performance_improvement: optimization_result.improvement,
          validation_status: optimization_result.validation
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private Functions - History Management

  defp complete_analysis(agent, analysis_id, analysis_result) do
    analysis_info = agent.state.active_analyses[analysis_id]
    
    completed_analysis = Map.merge(analysis_info, %{
      status: :completed,
      result: analysis_result,
      completed_at: DateTime.utc_now(),
      duration_ms: DateTime.diff(DateTime.utc_now(), analysis_info.started_at, :millisecond)
    })
    
    agent
    |> update_in([:state, :active_analyses], &Map.delete(&1, analysis_id))
    |> update_in([:state, :improvement_history], &add_to_history(&1, completed_analysis))
    |> update_quality_metrics(completed_analysis)
    |> update_analysis_status()
  end

  defp fail_analysis(agent, analysis_id, reason) do
    analysis_info = agent.state.active_analyses[analysis_id]
    
    failed_analysis = Map.merge(analysis_info, %{
      status: :failed,
      failure_reason: reason,
      failed_at: DateTime.utc_now()
    })
    
    agent
    |> update_in([:state, :active_analyses], &Map.delete(&1, analysis_id))
    |> update_in([:state, :improvement_history], &add_to_history(&1, failed_analysis))
    |> update_quality_metrics(failed_analysis)
    |> update_analysis_status()
  end

  defp add_to_history(history, entry) do
    [entry | history]
    |> Enum.take(@max_history_size)
  end

  defp add_improvement_to_history(agent, improvement_id, improvement_result) do
    improvement_entry = %{
      type: :improvement,
      improvement_id: improvement_id,
      result: improvement_result,
      timestamp: DateTime.utc_now()
    }
    
    update_in(agent.state.improvement_history, &add_to_history(&1, improvement_entry))
  end

  ## Private Functions - Metrics

  defp initialize_metrics(agent) do
    put_in(agent.state.metrics, %{
      total_analyses: 0,
      successful_analyses: 0,
      failed_analyses: 0,
      metrics_analyses: 0,
      style_analyses: 0,
      complexity_analyses: 0,
      maintainability_analyses: 0,
      documentation_analyses: 0,
      improvements_applied: 0,
      avg_analysis_time: 0.0,
      quality_score: 0.0,
      avg_improvement_time: 0.0,
      quality_trends: %{
        weekly: [],
        monthly: [],
        yearly: []
      }
    })
  end

  defp update_quality_metrics(agent, analysis) do
    metrics = agent.state.metrics
    
    if analysis.status == :completed do
      total = metrics.total_analyses + 1
      successful = metrics.successful_analyses + 1
      
      # Update type counters
      type_key = case analysis.result.type do
        :metrics_analysis -> :metrics_analyses
        :style_analysis -> :style_analyses
        :complexity_analysis -> :complexity_analyses
        :maintainability_analysis -> :maintainability_analyses
        :documentation_analysis -> :documentation_analyses
        _ -> :other_analyses
      end
      
      type_count = Map.get(metrics, type_key, 0) + 1
      
      # Update averages
      avg_time = (metrics.avg_analysis_time * metrics.total_analyses + analysis.duration_ms) / total
      
      # Update quality score based on analysis result
      quality_score = case analysis.result do
        %{quality_score: score} -> (metrics.quality_score + score) / 2
        %{overall_quality_score: score} -> (metrics.quality_score + score) / 2
        _ -> metrics.quality_score
      end
      
      agent
      |> put_in([:state, :metrics, :total_analyses], total)
      |> put_in([:state, :metrics, :successful_analyses], successful)
      |> put_in([:state, :metrics, type_key], type_count)
      |> put_in([:state, :metrics, :avg_analysis_time], avg_time)
      |> put_in([:state, :metrics, :quality_score], quality_score)
    else
      agent
      |> update_in([:state, :metrics, :total_analyses], &(&1 + 1))
      |> update_in([:state, :metrics, :failed_analyses], &(&1 + 1))
    end
  end

  defp calculate_quality_metrics(agent, time_range) do
    history = filter_history_by_time(agent.state.improvement_history, time_range)
    
    if Enum.empty?(history) do
      agent.state.metrics
    else
      # Calculate metrics for filtered history
      total = length(history)
      successful = Enum.count(history, &(&1.status == :completed))
      improvements = Enum.count(history, &(&1.type == :improvement))
      
      success_rate = if total > 0, do: successful / total, else: 0.0
      
      Map.merge(agent.state.metrics, %{
        time_range: time_range,
        total_in_range: total,
        successful_in_range: successful,
        improvements_in_range: improvements,
        success_rate_in_range: success_rate
      })
    end
  end

  defp filter_history_by_time(history, "all"), do: history
  
  defp filter_history_by_time(history, time_range) do
    cutoff = case time_range do
      "hour" -> DateTime.add(DateTime.utc_now(), -1, :hour)
      "day" -> DateTime.add(DateTime.utc_now(), -1, :day)
      "week" -> DateTime.add(DateTime.utc_now(), -7, :day)
      "month" -> DateTime.add(DateTime.utc_now(), -30, :day)
      _ -> DateTime.add(DateTime.utc_now(), -1, :day)
    end
    
    Enum.filter(history, fn entry ->
      timestamp = entry[:completed_at] || entry[:failed_at] || entry[:timestamp]
      timestamp && DateTime.compare(timestamp, cutoff) == :gt
    end)
  end

  ## Private Functions - Helpers

  defp initialize_quality_standards(agent) do
    default_standards = %{
      "cyclomatic_complexity" => %{
        definition: %{max_value: 10, warning_threshold: 7},
        updated_at: DateTime.utc_now(),
        usage_count: 0,
        compliance_rate: 1.0
      },
      "method_length" => %{
        definition: %{max_lines: 30, warning_threshold: 20},
        updated_at: DateTime.utc_now(),
        usage_count: 0,
        compliance_rate: 1.0
      },
      "documentation_coverage" => %{
        definition: %{min_coverage: 80, warning_threshold: 60},
        updated_at: DateTime.utc_now(),
        usage_count: 0,
        compliance_rate: 1.0
      }
    }
    
    put_in(agent.state.quality_standards, default_standards)
  end

  defp initialize_best_practices(agent) do
    default_practices = %{
      "single_responsibility" => %{
        definition: %{description: "Each class should have only one reason to change"},
        added_at: DateTime.utc_now(),
        usage_count: 0,
        effectiveness_rate: 1.0
      },
      "dry_principle" => %{
        definition: %{description: "Don't repeat yourself - avoid code duplication"},
        added_at: DateTime.utc_now(),
        usage_count: 0,
        effectiveness_rate: 1.0
      },
      "meaningful_names" => %{
        definition: %{description: "Use descriptive and meaningful variable/function names"},
        added_at: DateTime.utc_now(),
        usage_count: 0,
        effectiveness_rate: 1.0
      }
    }
    
    put_in(agent.state.best_practices, default_practices)
  end

  defp initialize_refactoring_patterns(agent) do
    default_patterns = %{
      "extract_method" => %{
        definition: %{
          description: "Extract repeated code into separate methods",
          complexity_threshold: 15
        },
        added_at: DateTime.utc_now(),
        usage_count: 0,
        success_rate: 1.0
      },
      "inline_variable" => %{
        definition: %{
          description: "Remove unnecessary intermediate variables",
          simplification_threshold: 5
        },
        added_at: DateTime.utc_now(),
        usage_count: 0,
        success_rate: 1.0
      },
      "rename_method" => %{
        definition: %{
          description: "Improve method names for better readability",
          clarity_threshold: 0.7
        },
        added_at: DateTime.utc_now(),
        usage_count: 0,
        success_rate: 1.0
      }
    }
    
    put_in(agent.state.refactoring_patterns, default_patterns)
  end

  defp cleanup_active_analyses(agent) do
    # Mark all active analyses as interrupted
    interrupted_analyses = agent.state.active_analyses
    |> Enum.map(fn {_id, info} ->
      Map.merge(info, %{
        status: :interrupted,
        interrupted_at: DateTime.utc_now()
      })
    end)
    
    agent
    |> put_in([:state, :active_analyses], %{})
    |> update_in([:state, :improvement_history], &((interrupted_analyses ++ &1) |> Enum.take(@max_history_size)))
  end

  defp update_analysis_status(agent) do
    if map_size(agent.state.active_analyses) == 0 do
      put_in(agent.state.analysis_status, :idle)
    else
      agent
    end
  end

  defp track_analysis_attempt(_agent, _scope, _result) do
    # Track attempt for learning
    :ok
  end

  defp calculate_overall_quality_score(analyses) do
    scores = analyses
    |> Enum.map(fn {_type, result} ->
      case result do
        %{quality_score: score} -> score
        %{overall_quality_score: score} -> score
        %{style_score: score} -> score
        %{maintainability_score: score} -> score
        _ -> 0.5  # Default moderate score
      end
    end)
    
    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp aggregate_priority_issues(analyses) do
    analyses
    |> Enum.flat_map(fn {_type, result} ->
      # Extract high-priority issues from each analysis type
      case result.type do
        :metrics_analysis -> result.code_smells || []
        :style_analysis -> result.formatting_issues || []
        :complexity_analysis -> result.complexity_hotspots || []
        :maintainability_analysis -> result.architectural_issues || []
        :documentation_analysis -> result.missing_docs || []
        _ -> []
      end
    end)
    |> Enum.take(10)  # Top 10 priority issues
  end

  defp generate_improvement_roadmap(analyses) do
    # Generate prioritized improvement recommendations
    roadmap_items = analyses
    |> Enum.flat_map(fn {type, result} ->
      case type do
        :metrics -> [%{priority: "high", action: "Reduce cyclomatic complexity", scope: "methods"}]
        :style -> [%{priority: "medium", action: "Fix formatting issues", scope: "codebase"}]
        :complexity -> [%{priority: "high", action: "Simplify complex methods", scope: "hotspots"}]
        :maintainability -> [%{priority: "medium", action: "Apply design patterns", scope: "architecture"}]
        :documentation -> [%{priority: "low", action: "Add missing documentation", scope: "public APIs"}]
        _ -> []
      end
    end)
    |> Enum.sort_by(fn item ->
      case item.priority do
        "high" -> 1
        "medium" -> 2
        "low" -> 3
        _ -> 4
      end
    end)
    
    roadmap_items
  end

  defp calculate_overall_confidence(analyses) do
    confidences = analyses
    |> Enum.map(fn {_type, result} -> result.confidence end)
    
    if length(confidences) > 0 do
      Enum.sum(confidences) / length(confidences)
    else
      0.0
    end
  end

  defp schedule_quality_assessment do
    Process.send_after(self(), :assess_quality, 300_000)  # Every 5 minutes
  end

  @impl true
  def handle_info(:assess_quality, agent) do
    # Update quality trends
    current_score = agent.state.metrics.quality_score
    
    # Add to weekly trend
    weekly_trends = [current_score | agent.state.metrics.quality_trends.weekly]
    |> Enum.take(168)  # Keep one week of hourly data
    
    agent = put_in(agent.state.metrics.quality_trends.weekly, weekly_trends)
    
    schedule_quality_assessment()
    
    {:noreply, agent}
  end
end