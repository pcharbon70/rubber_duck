defmodule RubberDuck.Agents.ErrorDetectionAgent do
  @moduledoc """
  Error Detection Agent for comprehensive system error monitoring and analysis.
  
  This agent provides proactive error detection across the RubberDuck system through:
  
  - Multi-source error monitoring (syntax, logic, runtime, quality, security)
  - Pattern recognition and anomaly detection
  - Error classification with severity scoring
  - Real-time and batch analysis capabilities
  - Performance metrics and optimization
  - Integration with telemetry and logging systems
  
  ## Signals
  
  ### Input Signals
  - `error_detection_request` - Request error detection for specific code/content
  - `pattern_analysis_request` - Analyze error patterns and trends
  - `error_classification_request` - Classify and score detected errors
  - `detection_metrics_request` - Request detection performance metrics
  - `error_batch_analysis` - Perform batch analysis on historical data
  - `detection_config_update` - Update detection configuration
  - `pattern_learning_update` - Update pattern recognition from feedback
  
  ### Output Signals
  - `error_detection_result` - Results of error detection analysis
  - `pattern_analysis_result` - Pattern analysis findings
  - `error_classification_result` - Error classification and severity
  - `detection_metrics_report` - Performance and accuracy metrics
  - `error_alert` - High-priority error alerts
  - `pattern_update_confirmation` - Pattern learning confirmations
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "error_detection",
    description: "Comprehensive error detection and analysis agent",
    category: "monitoring",
    schema: [
      detection_status: [type: :atom, values: [:idle, :detecting, :analyzing, :learning], default: :idle],
      active_detections: [type: :map, default: %{}],
      error_patterns: [type: :map, default: %{}],
      classification_rules: [type: :map, default: %{}],
      detection_config: [type: :map, default: %{
        syntax_detection: true,
        logic_detection: true,
        runtime_monitoring: true,
        quality_checks: true,
        security_scanning: true,
        pattern_learning: true,
        confidence_threshold: 0.7,
        batch_size: 100
      }],
      metrics: [type: :map, default: %{
        total_detections: 0,
        errors_found: 0,
        false_positives: 0,
        detection_accuracy: 0.0,
        avg_detection_time: 0.0,
        pattern_matches: 0,
        classifications_made: 0
      }]
    ]

  require Logger
  
  alias RubberDuck.ErrorDetection.{
    SourceDetector,
    PatternRecognizer,
    ErrorClassifier,
    MetricsCollector
  }

  # Signal Handlers

  @impl true
  def handle_signal(agent, %{"type" => "error_detection_request"} = signal) do
    %{
      "data" => %{
        "content" => content,
        "content_type" => content_type,
        "detection_types" => detection_types
      } = _data
    } = signal
    
    detection_id = signal["id"]
    
    Logger.info("Starting error detection for content type: #{content_type}")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | detection_status: :detecting}}
    
    # Track active detection
    detection_info = %{
      content_type: content_type,
      detection_types: detection_types || get_default_detection_types(agent),
      started_at: DateTime.utc_now(),
      status: :in_progress
    }
    
    agent = put_in(agent.state.active_detections[detection_id], detection_info)
    
    # Perform error detection
    detection_result = perform_error_detection(agent, content, content_type, detection_types)
    
    # Update metrics
    agent = update_detection_metrics(agent, detection_id, detection_result)
    
    # Classify detected errors
    classified_errors = classify_detected_errors(agent, detection_result)
    
    # Check for high-priority alerts
    agent = check_and_emit_alerts(agent, classified_errors)
    
    # Emit detection result
    status = if match?({:ok, _}, detection_result), do: "completed", else: "failed"
    
    result_signal = Jido.Signal.new!(%{
      type: "error.detection.result",
      source: "agent:#{agent.id}",
      data: %{
        detection_id: detection_id,
        status: status,
        errors_found: length(classified_errors),
        classified_errors: classified_errors,
        detection_time_ms: calculate_detection_time(detection_info),
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, result_signal)
    
    # Clean up active detection
    agent = %{agent | state: %{agent.state | 
      detection_status: :idle,
      active_detections: Map.delete(agent.state.active_detections, detection_id)
    }}
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "pattern_analysis_request"} = signal) do
    %{
      "data" => %{
        "analysis_type" => analysis_type,
        "time_range" => time_range
      } = data
    } = signal
    
    analysis_id = signal["id"]
    
    Logger.info("Starting pattern analysis: #{analysis_type}")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | detection_status: :analyzing}}
    
    # Perform pattern analysis
    analysis_result = case analysis_type do
      "clustering" ->
        PatternRecognizer.cluster_error_patterns(agent.state.error_patterns, data)
      
      "trending" ->
        PatternRecognizer.analyze_error_trends(agent.state.error_patterns, time_range)
      
      "anomaly_detection" ->
        PatternRecognizer.detect_anomalies(agent.state.error_patterns, data)
      
      _ ->
        {:error, "Unknown analysis type: #{analysis_type}"}
    end
    
    # Update pattern metrics
    agent = update_pattern_metrics(agent, analysis_id, analysis_result)
    
    # Emit analysis result
    status = if match?({:ok, _}, analysis_result), do: "completed", else: "failed"
    
    result_signal = Jido.Signal.new!(%{
      type: "error.pattern.analysis.result",
      source: "agent:#{agent.id}",
      data: %{
        analysis_id: analysis_id,
        analysis_type: analysis_type,
        status: status,
        result: analysis_result,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, result_signal)
    
    # Reset status
    agent = %{agent | state: %{agent.state | detection_status: :idle}}
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "error_classification_request"} = signal) do
    %{
      "data" => %{
        "errors" => errors,
        "classification_strategy" => strategy
      }
    } = signal
    
    classification_id = signal["id"]
    
    Logger.info("Classifying #{length(errors)} errors with strategy: #{strategy}")
    
    # Classify errors using the specified strategy
    classification_result = ErrorClassifier.classify_errors(
      errors, 
      agent.state.classification_rules, 
      strategy
    )
    
    # Update classification metrics
    agent = update_classification_metrics(agent, classification_id, classification_result)
    
    # Emit classification result
    result_signal = Jido.Signal.new!(%{
      type: "error.classification.result",
      source: "agent:#{agent.id}",
      data: %{
        classification_id: classification_id,
        classified_errors: classification_result,
        strategy_used: strategy,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, result_signal)
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "detection_metrics_request"} = signal) do
    metrics_id = signal["id"]
    
    # Collect comprehensive metrics
    detailed_metrics = MetricsCollector.collect_detection_metrics(agent.state.metrics)
    
    # Emit metrics report
    metrics_signal = Jido.Signal.new!(%{
      type: "error.detection.metrics.report",
      source: "agent:#{agent.id}",
      data: %{
        metrics_id: metrics_id,
        metrics: detailed_metrics,
        collection_timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, metrics_signal)
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "error_batch_analysis"} = signal) do
    %{
      "data" => %{
        "batch_data" => batch_data,
        "analysis_config" => config
      }
    } = signal
    
    batch_id = signal["id"]
    
    Logger.info("Starting batch analysis for #{length(batch_data)} items")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | detection_status: :analyzing}}
    
    # Process batch data
    batch_results = process_batch_analysis(agent, batch_data, config)
    
    # Update batch metrics
    agent = update_batch_metrics(agent, batch_id, batch_results)
    
    # Emit batch analysis result
    result_signal = Jido.Signal.new!(%{
      type: "error.batch.analysis.result",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        processed_count: length(batch_data),
        results: batch_results,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, result_signal)
    
    # Reset status
    agent = %{agent | state: %{agent.state | detection_status: :idle}}
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "detection_config_update"} = signal) do
    %{
      "data" => %{
        "config_updates" => updates
      }
    } = signal
    
    Logger.info("Updating detection configuration")
    
    # Update configuration
    new_config = Map.merge(agent.state.detection_config, updates)
    agent = %{agent | state: %{agent.state | detection_config: new_config}}
    
    # Emit confirmation
    confirmation_signal = Jido.Signal.new!(%{
      type: "error.detection.config.updated",
      source: "agent:#{agent.id}",
      data: %{
        updated_config: new_config,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, confirmation_signal)
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "pattern_learning_update"} = signal) do
    %{
      "data" => %{
        "feedback" => feedback,
        "learning_type" => learning_type
      }
    } = signal
    
    Logger.info("Processing pattern learning update: #{learning_type}")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | detection_status: :learning}}
    
    # Apply pattern learning
    updated_patterns = apply_pattern_learning(agent.state.error_patterns, feedback, learning_type)
    agent = %{agent | state: %{agent.state | error_patterns: updated_patterns}}
    
    # Emit learning confirmation
    confirmation_signal = Jido.Signal.new!(%{
      type: "error.pattern.learning.updated",
      source: "agent:#{agent.id}",
      data: %{
        learning_type: learning_type,
        patterns_updated: map_size(updated_patterns),
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, confirmation_signal)
    
    # Reset status
    agent = %{agent | state: %{agent.state | detection_status: :idle}}
    
    {:ok, agent}
  end

  # Default signal handler
  def handle_signal(agent, signal) do
    Logger.warning("Unhandled signal type: #{signal["type"]}")
    {:ok, agent}
  end

  # Private Helper Functions

  defp get_default_detection_types(agent) do
    config = agent.state.detection_config
    
    []
    |> maybe_add("syntax", config.syntax_detection)
    |> maybe_add("logic", config.logic_detection)
    |> maybe_add("runtime", config.runtime_monitoring)
    |> maybe_add("quality", config.quality_checks)
    |> maybe_add("security", config.security_scanning)
  end

  defp maybe_add(list, type, true), do: [type | list]
  defp maybe_add(list, _type, false), do: list

  defp perform_error_detection(agent, content, content_type, detection_types) do
    config = agent.state.detection_config
    
    detection_results = Enum.map(detection_types, fn type ->
      case type do
        "syntax" ->
          SourceDetector.detect_syntax_errors(content, content_type, config)
        
        "logic" ->
          SourceDetector.detect_logic_errors(content, content_type, config)
        
        "runtime" ->
          SourceDetector.detect_runtime_errors(content, content_type, config)
        
        "quality" ->
          SourceDetector.detect_quality_issues(content, content_type, config)
        
        "security" ->
          SourceDetector.detect_security_issues(content, content_type, config)
        
        _ ->
          {:error, "Unknown detection type: #{type}"}
      end
    end)
    
    # Combine results
    errors = detection_results
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.flat_map(fn {:ok, errors} -> errors end)
    
    {:ok, errors}
  end

  defp classify_detected_errors(agent, {:ok, errors}) do
    ErrorClassifier.classify_errors(errors, agent.state.classification_rules, "comprehensive")
  end
  defp classify_detected_errors(_agent, _error_result), do: []

  defp check_and_emit_alerts(agent, classified_errors) do
    high_priority_errors = Enum.filter(classified_errors, &(&1.severity >= 8))
    
    if length(high_priority_errors) > 0 do
      alert_signal = Jido.Signal.new!(%{
        type: "error.alert.high_priority",
        source: "agent:#{agent.id}",
        data: %{
          alert_count: length(high_priority_errors),
          high_priority_errors: high_priority_errors,
          timestamp: DateTime.utc_now()
        }
      })
      
      emit_signal(agent, alert_signal)
    end
    
    agent
  end

  defp calculate_detection_time(detection_info) do
    DateTime.diff(DateTime.utc_now(), detection_info.started_at, :millisecond)
  end

  defp update_detection_metrics(agent, _detection_id, detection_result) do
    case detection_result do
      {:ok, errors} ->
        metrics = agent.state.metrics
        
        updated_metrics = %{metrics |
          total_detections: metrics.total_detections + 1,
          errors_found: metrics.errors_found + length(errors)
        }
        
        %{agent | state: %{agent.state | metrics: updated_metrics}}
      
      _error_result ->
        agent
    end
  end

  defp update_pattern_metrics(agent, _analysis_id, {:ok, _result}) do
    metrics = agent.state.metrics
    updated_metrics = %{metrics | pattern_matches: metrics.pattern_matches + 1}
    %{agent | state: %{agent.state | metrics: updated_metrics}}
  end
  defp update_pattern_metrics(agent, _analysis_id, {:error, _}), do: agent

  defp update_classification_metrics(agent, _classification_id, classified_errors) do
    metrics = agent.state.metrics
    updated_metrics = %{metrics | classifications_made: metrics.classifications_made + length(classified_errors)}
    %{agent | state: %{agent.state | metrics: updated_metrics}}
  end

  defp process_batch_analysis(agent, batch_data, config) do
    batch_size = config["batch_size"] || agent.state.detection_config.batch_size
    
    batch_data
    |> Enum.chunk_every(batch_size)
    |> Enum.map(fn chunk ->
      Enum.map(chunk, fn item ->
        perform_error_detection(agent, item["content"], item["content_type"], item["detection_types"])
      end)
    end)
    |> List.flatten()
  end

  defp update_batch_metrics(agent, _batch_id, results) do
    successful_results = Enum.count(results, &match?({:ok, _}, &1))
    metrics = agent.state.metrics
    
    updated_metrics = %{metrics |
      total_detections: metrics.total_detections + length(results),
      errors_found: metrics.errors_found + successful_results
    }
    
    %{agent | state: %{agent.state | metrics: updated_metrics}}
  end

  defp apply_pattern_learning(patterns, feedback, learning_type) do
    case learning_type do
      "false_positive_reduction" ->
        PatternRecognizer.reduce_false_positives(patterns, feedback)
      
      "accuracy_improvement" ->
        PatternRecognizer.improve_accuracy(patterns, feedback)
      
      "new_pattern_detection" ->
        PatternRecognizer.learn_new_patterns(patterns, feedback)
      
      _ ->
        patterns
    end
  end

  # Health check implementation
  @impl true
  def health_check(agent) do
    issues = []
    
    # Check detection status
    issues = if agent.state.detection_status == :idle do
      issues
    else
      ["Agent not in idle state" | issues]
    end
    
    # Check metrics sanity
    issues = if agent.state.metrics.total_detections >= 0 do
      issues
    else
      ["Invalid metrics detected" | issues]
    end
    
    if length(issues) == 0 do
      {:healthy, %{status: "All systems operational", last_check: DateTime.utc_now()}}
    else
      {:unhealthy, %{issues: issues, last_check: DateTime.utc_now()}}
    end
  end
end