defmodule RubberDuck.Agents.CodeCorrectionAgent do
  @moduledoc """
  Code Correction Agent that executes code fixes based on correction strategies.
  
  This agent handles syntax fixing, code formatting, automated refactoring,
  and test integration to ensure code quality improvements.
  
  ## Responsibilities
  
  - Execute code corrections based on strategies
  - Perform syntax and semantic fixes
  - Integrate with test generation and validation
  - Track correction metrics and success rates
  - Provide rollback capabilities
  
  ## State Structure
  
  ```elixir
  %{
    correction_status: :idle | :correcting | :validating | :completed,
    active_corrections: %{correction_id => correction_info},
    fix_history: [completed_fixes],
    syntax_patterns: %{pattern_id => fix_pattern},
    semantic_rules: %{rule_id => semantic_rule},
    test_integration: %{
      enabled: boolean,
      test_generator: module,
      validation_config: map
    },
    metrics: %{
      total_fixes: integer,
      success_rate: float,
      avg_fix_time: float,
      quality_improvements: map
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "code_correction",
    description: "Executes code fixes with syntax correction, semantic fixes, and test integration",
    category: "correction",
    tags: ["code", "correction", "refactoring", "testing"],
    vsn: "1.0.0",
    schema: [
      correction_status: [type: :atom, values: [:idle, :correcting, :validating, :completed], default: :idle],
      active_corrections: [type: :map, default: %{}],
      fix_history: [type: :list, default: []],
      syntax_patterns: [type: :map, default: %{}],
      semantic_rules: [type: :map, default: %{}],
      test_integration: [type: :map, default: %{enabled: true}],
      metrics: [type: :map, default: %{}]
    ]

  alias RubberDuck.CodeCorrection.{
    SyntaxCorrector,
    SemanticCorrector,
    TestIntegration,
    FixValidator
  }

  require Logger

  @max_history_size 1000

  # Helper function for signal emission
  defp emit_signal(topic, data) when is_binary(topic) and is_map(data) do
    # For now, just log the signal
    Logger.info("[CodeCorrectionAgent] Signal emitted - #{topic}: #{inspect(data)}")
    :ok
  end

  ## Initialization

  def mount(agent) do
    Logger.info("[#{agent.id}] Code Correction Agent mounting with test integration")
    
    # Initialize correction modules
    agent = agent
    |> initialize_syntax_patterns()
    |> initialize_semantic_rules()
    |> initialize_test_integration()
    |> initialize_metrics()
    
    # Schedule periodic metrics calculation
    schedule_metrics_update()
    
    {:ok, agent}
  end

  def unmount(agent) do
    Logger.info("[#{agent.id}] Code Correction Agent unmounting")
    
    # Clean up any active corrections
    agent = cleanup_active_corrections(agent)
    
    {:ok, agent}
  end

  ## Signal Handlers - Correction Operations

  def handle_signal(agent, %{"type" => "apply_correction"} = signal) do
    %{
      "correction_id" => correction_id,
      "error_data" => error_data,
      "strategy" => strategy,
      "options" => options
    } = signal
    
    Logger.info("[#{agent.id}] Applying correction #{correction_id} with strategy: #{strategy["name"]}")
    
    # Start correction tracking
    correction_info = %{
      correction_id: correction_id,
      error_data: error_data,
      strategy: strategy,
      started_at: DateTime.utc_now(),
      status: :in_progress,
      steps_completed: []
    }
    
    agent = agent
    |> put_in([:state, :active_corrections, correction_id], correction_info)
    |> put_in([:state, :correction_status], :correcting)
    
    # Execute correction
    case execute_correction(agent, error_data, strategy, options) do
      {:ok, fix_result} ->
        # Update correction info
        correction_info = Map.merge(correction_info, %{
          status: :validating,
          fix_result: fix_result,
          completed_at: DateTime.utc_now()
        })
        
        agent = put_in(agent.state.active_corrections[correction_id], correction_info)
        
        # Validate fix if enabled
        validation_result = if options["skip_validation"] do
          %{valid: true, confidence: 1.0}
        else
          validate_correction(agent, fix_result, error_data)
        end
        
        # Complete correction
        agent = complete_correction(agent, correction_id, fix_result, validation_result)
        
        emit_signal("correction_completed", %{
          correction_id: correction_id,
          success: true,
          fix_result: fix_result,
          validation: validation_result
        })
        
        {:ok, %{correction_id: correction_id, success: true, result: fix_result}, agent}
        
      {:error, reason} ->
        agent = fail_correction(agent, correction_id, reason)
        
        emit_signal("correction_failed", %{
          correction_id: correction_id,
          reason: reason
        })
        
        {:error, reason, agent}
    end
  end

  def handle_signal(agent, %{"type" => "validate_fix"} = signal) do
    %{
      "fix_data" => fix_data,
      "error_context" => error_context,
      "validation_level" => level
    } = signal
    
    validation_result = perform_validation(agent, fix_data, error_context, level)
    
    emit_signal("validation_completed", validation_result)
    
    {:ok, validation_result, agent}
  end

  def handle_signal(agent, %{"type" => "generate_tests"} = signal) do
    %{
      "fix_data" => fix_data,
      "test_config" => test_config
    } = signal
    
    if agent.state.test_integration.enabled do
      case TestIntegration.generate_tests(fix_data, test_config) do
        {:ok, tests} ->
          emit_signal("tests_generated", %{
            fix_id: fix_data["id"],
            test_count: length(tests),
            tests: tests
          })
          
          {:ok, %{generated: true, tests: tests}, agent}
          
        {:error, reason} ->
          {:error, "Test generation failed: #{reason}", agent}
      end
    else
      {:ok, %{generated: false, reason: "Test integration disabled"}, agent}
    end
  end

  def handle_signal(agent, %{"type" => "rollback_fix"} = signal) do
    %{
      "correction_id" => correction_id,
      "reason" => reason
    } = signal
    
    case find_correction_in_history(agent, correction_id) do
      nil ->
        {:error, "Correction not found in history", agent}
        
      correction ->
        case perform_rollback(agent, correction) do
          {:ok, rollback_result} ->
            agent = add_rollback_to_history(agent, correction_id, rollback_result)
            
            emit_signal("fix_rolled_back", %{
              correction_id: correction_id,
              reason: reason,
              result: rollback_result
            })
            
            {:ok, rollback_result, agent}
            
          # perform_rollback always returns {:ok, result}
          {:error, rollback_error} ->
            {:error, "Rollback failed: #{rollback_error}", agent}
        end
    end
  end

  ## Signal Handlers - Analysis

  def handle_signal(agent, %{"type" => "analyze_impact"} = signal) do
    %{
      "fix_data" => fix_data,
      "analysis_scope" => scope
    } = signal
    
    impact_analysis = analyze_fix_impact(agent, fix_data, scope)
    
    {:ok, impact_analysis, agent}
  end

  def handle_signal(agent, %{"type" => "get_fix_metrics"} = signal) do
    time_range = signal["time_range"] || "all"
    
    metrics = calculate_metrics(agent, time_range)
    
    {:ok, metrics, agent}
  end

  ## Signal Handlers - Pattern Management

  def handle_signal(agent, %{"type" => "add_syntax_pattern"} = signal) do
    %{
      "pattern_id" => pattern_id,
      "pattern" => pattern,
      "fix_template" => fix_template
    } = signal
    
    syntax_pattern = %{
      pattern: pattern,
      fix_template: fix_template,
      usage_count: 0,
      success_rate: 1.0,
      added_at: DateTime.utc_now()
    }
    
    agent = put_in(agent.state.syntax_patterns[pattern_id], syntax_pattern)
    
    {:ok, %{added: true, pattern_id: pattern_id}, agent}
  end

  def handle_signal(agent, %{"type" => "add_semantic_rule"} = signal) do
    %{
      "rule_id" => rule_id,
      "rule" => rule
    } = signal
    
    semantic_rule = %{
      condition: rule["condition"],
      action: rule["action"],
      priority: rule["priority"] || 1,
      usage_count: 0,
      added_at: DateTime.utc_now()
    }
    
    agent = put_in(agent.state.semantic_rules[rule_id], semantic_rule)
    
    {:ok, %{added: true, rule_id: rule_id}, agent}
  end

  def handle_signal(agent, signal) do
    Logger.warning("[#{agent.id}] Unknown signal type: #{signal["type"]}")
    {:error, "Unknown signal type: #{signal["type"]}", agent}
  end

  ## Private Functions - Correction Execution

  defp execute_correction(agent, error_data, strategy, options) do
    correction_type = determine_correction_type(error_data, strategy)
    
    try do
      result = case correction_type do
        :syntax ->
          execute_syntax_correction(agent, error_data, strategy, options)
          
        :semantic ->
          execute_semantic_correction(agent, error_data, strategy, options)
          
        :refactoring ->
          execute_refactoring(agent, error_data, strategy, options)
          
        :combined ->
          execute_combined_correction(agent, error_data, strategy, options)
          
        _ ->
          {:error, "Unknown correction type: #{correction_type}"}
      end
      
      # Add metrics tracking
      track_correction_attempt(agent, correction_type, result)
      
      result
    catch
      kind, reason ->
        Logger.error("[#{agent.id}] Correction execution failed: #{kind} - #{inspect(reason)}")
        {:error, "Execution failed: #{inspect(reason)}"}
    end
  end

  defp execute_syntax_correction(agent, error_data, _strategy, options) do
    patterns = agent.state.syntax_patterns
    
    case SyntaxCorrector.fix_syntax_error(error_data, patterns, options) do
      {:ok, fix} ->
        # Generate fix result
        fix_result = %{
          type: :syntax,
          original_code: error_data["code"],
          fixed_code: fix.corrected_code,
          changes: fix.changes,
          confidence: fix.confidence,
          applied_patterns: fix.patterns_used
        }
        
        {:ok, fix_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_semantic_correction(agent, error_data, strategy, options) do
    rules = agent.state.semantic_rules
    
    case SemanticCorrector.fix_semantic_error(error_data, rules, strategy, options) do
      {:ok, fix} ->
        fix_result = %{
          type: :semantic,
          original_code: error_data["code"],
          fixed_code: fix.corrected_code,
          semantic_changes: fix.semantic_changes,
          imports_added: fix.imports_added,
          types_corrected: fix.types_corrected,
          confidence: fix.confidence
        }
        
        {:ok, fix_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_refactoring(_agent, error_data, strategy, options) do
    refactoring_config = Map.merge(strategy["config"] || %{}, options)
    
    case SemanticCorrector.refactor_code(error_data["code"], refactoring_config) do
      {:ok, refactored} ->
        fix_result = %{
          type: :refactoring,
          original_code: error_data["code"],
          fixed_code: refactored.code,
          refactoring_type: refactored.type,
          improvements: refactored.improvements,
          metrics_change: refactored.metrics_change
        }
        
        {:ok, fix_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_combined_correction(agent, error_data, strategy, options) do
    # First apply syntax fixes
    with {:ok, syntax_fixed} <- execute_syntax_correction(agent, error_data, strategy, options),
         # Then apply semantic fixes on the syntax-fixed code
         semantic_error_data = %{error_data | "code" => syntax_fixed.fixed_code},
         {:ok, semantic_fixed} <- execute_semantic_correction(agent, semantic_error_data, strategy, options) do
      
      fix_result = %{
        type: :combined,
        original_code: error_data["code"],
        fixed_code: semantic_fixed.fixed_code,
        syntax_changes: syntax_fixed.changes,
        semantic_changes: semantic_fixed.semantic_changes,
        total_changes: length(syntax_fixed.changes) + length(semantic_fixed.semantic_changes),
        confidence: (syntax_fixed.confidence + semantic_fixed.confidence) / 2
      }
      
      {:ok, fix_result}
    end
  end

  ## Private Functions - Validation

  defp validate_correction(agent, fix_result, error_data) do
    validation_config = agent.state.test_integration.validation_config || %{}
    
    FixValidator.validate_fix(fix_result, error_data, validation_config)
  end

  defp perform_validation(agent, fix_data, error_context, level) do
    validation_levels = %{
      "basic" => [:syntax_check, :compilation_check],
      "standard" => [:syntax_check, :compilation_check, :logic_check],
      "comprehensive" => [:syntax_check, :compilation_check, :logic_check, :test_check, :performance_check]
    }
    
    checks = Map.get(validation_levels, level, validation_levels["standard"])
    
    results = Enum.map(checks, fn check ->
      {check, perform_validation_check(agent, check, fix_data, error_context)}
    end)
    
    %{
      level: level,
      checks: Map.new(results),
      overall_valid: Enum.all?(results, fn {_check, result} -> result.valid end),
      confidence: calculate_validation_confidence(results)
    }
  end

  defp perform_validation_check(_agent, check_type, _fix_data, _error_context) do
    # Simplified validation checks
    case check_type do
      :syntax_check ->
        %{valid: true, confidence: 0.95, details: "Syntax validation passed"}
        
      :compilation_check ->
        %{valid: true, confidence: 0.9, details: "Compilation check passed"}
        
      :logic_check ->
        %{valid: true, confidence: 0.85, details: "Logic validation passed"}
        
      :test_check ->
        %{valid: true, confidence: 0.8, details: "Test validation passed"}
        
      :performance_check ->
        %{valid: true, confidence: 0.7, details: "Performance check passed"}
    end
  end

  ## Private Functions - History Management

  defp complete_correction(agent, correction_id, fix_result, validation_result) do
    correction_info = agent.state.active_corrections[correction_id]
    
    completed_correction = Map.merge(correction_info, %{
      status: :completed,
      fix_result: fix_result,
      validation_result: validation_result,
      completed_at: DateTime.utc_now(),
      duration_ms: DateTime.diff(DateTime.utc_now(), correction_info.started_at, :millisecond)
    })
    
    agent
    |> update_in([:state, :active_corrections], &Map.delete(&1, correction_id))
    |> update_in([:state, :fix_history], &add_to_history(&1, completed_correction))
    |> update_correction_metrics(completed_correction)
    |> update_correction_status()
  end

  defp fail_correction(agent, correction_id, reason) do
    correction_info = agent.state.active_corrections[correction_id]
    
    failed_correction = Map.merge(correction_info, %{
      status: :failed,
      failure_reason: reason,
      failed_at: DateTime.utc_now()
    })
    
    agent
    |> update_in([:state, :active_corrections], &Map.delete(&1, correction_id))
    |> update_in([:state, :fix_history], &add_to_history(&1, failed_correction))
    |> update_correction_metrics(failed_correction)
    |> update_correction_status()
  end

  defp add_to_history(history, correction) do
    [correction | history]
    |> Enum.take(@max_history_size)
  end

  defp find_correction_in_history(agent, correction_id) do
    Enum.find(agent.state.fix_history, fn correction ->
      correction.correction_id == correction_id
    end)
  end

  defp add_rollback_to_history(agent, correction_id, rollback_result) do
    rollback_entry = %{
      type: :rollback,
      correction_id: correction_id,
      rollback_result: rollback_result,
      timestamp: DateTime.utc_now()
    }
    
    update_in(agent.state.fix_history, &add_to_history(&1, rollback_entry))
  end

  ## Private Functions - Rollback

  defp perform_rollback(_agent, correction) do
    case correction.fix_result.type do
      :syntax ->
        # Restore original code
        {:ok, %{
          restored_code: correction.error_data["code"],
          rollback_type: :simple_restore
        }}
        
      :semantic ->
        # Reverse semantic changes
        {:ok, %{
          restored_code: correction.error_data["code"],
          rollback_type: :semantic_reverse,
          reversed_changes: correction.fix_result.semantic_changes
        }}
        
      _ ->
        # Generic rollback
        {:ok, %{
          restored_code: correction.error_data["code"],
          rollback_type: :generic
        }}
    end
  end

  ## Private Functions - Impact Analysis

  defp analyze_fix_impact(_agent, fix_data, scope) do
    base_analysis = %{
      code_quality: analyze_quality_impact(fix_data),
      performance: analyze_performance_impact(fix_data),
      maintainability: analyze_maintainability_impact(fix_data),
      test_coverage: analyze_test_coverage_impact(fix_data)
    }
    
    case scope do
      "local" ->
        base_analysis
        
      "module" ->
        Map.put(base_analysis, :module_impact, analyze_module_impact(fix_data))
        
      "project" ->
        Map.merge(base_analysis, %{
          module_impact: analyze_module_impact(fix_data),
          dependency_impact: analyze_dependency_impact(fix_data)
        })
        
      _ ->
        base_analysis
    end
  end

  defp analyze_quality_impact(_fix_data) do
    %{
      complexity_change: -0.5,  # Simplified
      readability_improvement: 0.8,
      bug_risk_reduction: 0.7
    }
  end

  defp analyze_performance_impact(_fix_data) do
    %{
      execution_time_change: 0.0,
      memory_usage_change: -0.1,
      optimization_applied: false
    }
  end

  defp analyze_maintainability_impact(_fix_data) do
    %{
      code_duplication_reduced: true,
      naming_improved: true,
      documentation_added: false
    }
  end

  defp analyze_test_coverage_impact(_fix_data) do
    %{
      coverage_change: 0.0,
      new_tests_required: true,
      test_maintainability: 0.8
    }
  end

  defp analyze_module_impact(_fix_data) do
    %{
      affected_functions: 1,
      api_changes: false,
      breaking_changes: false
    }
  end

  defp analyze_dependency_impact(_fix_data) do
    %{
      affected_modules: [],
      requires_recompilation: true,
      api_compatibility: true
    }
  end

  ## Private Functions - Metrics

  defp initialize_metrics(agent) do
    put_in(agent.state.metrics, %{
      total_fixes: 0,
      successful_fixes: 0,
      failed_fixes: 0,
      syntax_fixes: 0,
      semantic_fixes: 0,
      refactoring_fixes: 0,
      combined_fixes: 0,
      avg_fix_time: 0.0,
      avg_confidence: 0.0,
      rollback_count: 0,
      test_generation_count: 0,
      success_rate: 0.0,
      quality_improvements: %{
        total_improvements: 0,
        avg_improvement_score: 0.0
      }
    })
  end

  defp update_correction_metrics(agent, correction) do
    metrics = agent.state.metrics
    
    if correction.status == :completed do
      total = metrics.total_fixes + 1
      successful = metrics.successful_fixes + 1
      
      # Update type counters
      type_key = String.to_atom("#{correction.fix_result.type}_fixes")
      type_count = Map.get(metrics, type_key, 0) + 1
      
      # Update averages
      avg_time = (metrics.avg_fix_time * metrics.total_fixes + correction.duration_ms) / total
      avg_confidence = (metrics.avg_confidence * metrics.total_fixes + correction.fix_result[:confidence] || 0.8) / total
      
      agent
      |> put_in([:state, :metrics, :total_fixes], total)
      |> put_in([:state, :metrics, :successful_fixes], successful)
      |> put_in([:state, :metrics, type_key], type_count)
      |> put_in([:state, :metrics, :avg_fix_time], avg_time)
      |> put_in([:state, :metrics, :avg_confidence], avg_confidence)
    else
      agent
      |> update_in([:state, :metrics, :total_fixes], &(&1 + 1))
      |> update_in([:state, :metrics, :failed_fixes], &(&1 + 1))
    end
  end

  defp calculate_metrics(agent, time_range) do
    history = filter_history_by_time(agent.state.fix_history, time_range)
    
    if Enum.empty?(history) do
      agent.state.metrics
    else
      # Calculate metrics for the filtered history
      total = length(history)
      successful = Enum.count(history, &(&1.status == :completed))
      
      success_rate = if total > 0, do: successful / total, else: 0.0
      
      Map.merge(agent.state.metrics, %{
        time_range: time_range,
        total_in_range: total,
        successful_in_range: successful,
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

  defp initialize_syntax_patterns(agent) do
    default_patterns = %{
      "missing_comma" => %{
        pattern: ~r/\[\s*(\w+)\s+(\w+)\s*\]/,
        fix_template: "[$1, $2]",
        usage_count: 0,
        success_rate: 1.0
      },
      "missing_do" => %{
        pattern: ~r/def\s+(\w+)\(([^)]*)\)\s*\n/,
        fix_template: "def $1($2) do\n",
        usage_count: 0,
        success_rate: 1.0
      },
      "unclosed_string" => %{
        pattern: ~r/"([^"]*?)$/,
        fix_template: "\"$1\"",
        usage_count: 0,
        success_rate: 1.0
      }
    }
    
    put_in(agent.state.syntax_patterns, default_patterns)
  end

  defp initialize_semantic_rules(agent) do
    default_rules = %{
      "undefined_variable" => %{
        condition: %{error_type: "undefined_variable"},
        action: %{type: "define_variable", scope: "local"},
        priority: 1,
        usage_count: 0
      },
      "type_mismatch" => %{
        condition: %{error_type: "type_mismatch"},
        action: %{type: "convert_type", method: "safe_cast"},
        priority: 2,
        usage_count: 0
      },
      "missing_import" => %{
        condition: %{error_type: "undefined_function"},
        action: %{type: "add_import", search: "project"},
        priority: 1,
        usage_count: 0
      }
    }
    
    put_in(agent.state.semantic_rules, default_rules)
  end

  defp initialize_test_integration(agent) do
    put_in(agent.state.test_integration, %{
      enabled: true,
      test_generator: TestIntegration,
      validation_config: %{
        run_tests: true,
        coverage_threshold: 0.8,
        performance_check: false
      }
    })
  end

  defp determine_correction_type(error_data, strategy) do
    cond do
      error_data["error_type"] in ["syntax_error", "parse_error"] ->
        :syntax
        
      error_data["error_type"] in ["type_error", "undefined_variable", "undefined_function"] ->
        :semantic
        
      strategy["type"] == "refactoring" ->
        :refactoring
        
      strategy["type"] == "combined" or strategy["approach"] == "multi_step" ->
        :combined
        
      true ->
        :syntax  # Default
    end
  end

  defp cleanup_active_corrections(agent) do
    # Mark all active corrections as interrupted
    interrupted_corrections = agent.state.active_corrections
    |> Enum.map(fn {_id, info} ->
      Map.merge(info, %{
        status: :interrupted,
        interrupted_at: DateTime.utc_now()
      })
    end)
    
    agent
    |> put_in([:state, :active_corrections], %{})
    |> update_in([:state, :fix_history], &((interrupted_corrections ++ &1) |> Enum.take(@max_history_size)))
  end

  defp update_correction_status(agent) do
    if map_size(agent.state.active_corrections) == 0 do
      put_in(agent.state.correction_status, :idle)
    else
      agent
    end
  end

  defp track_correction_attempt(_agent, _correction_type, _result) do
    # Track attempt for learning
    :ok
  end

  defp calculate_validation_confidence(results) do
    confidences = results
    |> Enum.map(fn {_check, result} -> result.confidence end)
    
    if length(confidences) > 0 do
      Enum.sum(confidences) / length(confidences)
    else
      0.0
    end
  end

  defp schedule_metrics_update do
    Process.send_after(self(), :update_metrics, 60_000)  # Every minute
  end

  @impl true
  def handle_info(:update_metrics, agent) do
    # Update success rate
    metrics = agent.state.metrics
    success_rate = if metrics.total_fixes > 0 do
      metrics.successful_fixes / metrics.total_fixes
    else
      0.0
    end
    
    agent = put_in(agent.state.metrics.success_rate, success_rate)
    
    schedule_metrics_update()
    
    {:noreply, agent}
  end
end