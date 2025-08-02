defmodule RubberDuck.Jido.Actions.Context.ContextConfigurationAction do
  @moduledoc """
  Action for managing context builder configuration, priorities, and metrics.

  This action handles configuration updates for the context builder including
  prioritization weights, token limits, cache settings, and performance metrics
  collection and reporting.

  ## Parameters

  - `operation` - Configuration operation to perform (required: :set_priorities, :configure_limits, :get_metrics, :update_config, :reset_config)
  - `priorities` - Priority weights for context scoring (for :set_priorities operation)
  - `limits` - Token and cache limits configuration (for :configure_limits operation)
  - `config_updates` - General configuration updates (for :update_config operation)
  - `include_detailed_metrics` - Whether to include detailed performance metrics (default: false)
  - `metrics_time_range` - Time range for metrics calculation in hours (default: 24)

  ## Returns

  - `{:ok, result}` - Configuration operation completed successfully
  - `{:error, reason}` - Configuration operation failed

  ## Example

      # Set context priorities
      params = %{
        operation: :set_priorities,
        priorities: %{
          relevance_weight: 0.5,
          recency_weight: 0.3,
          importance_weight: 0.2
        }
      }

      {:ok, result} = ContextConfigurationAction.run(params, context)

      # Configure limits
      params = %{
        operation: :configure_limits,
        limits: %{
          max_cache_size: 200,
          default_max_tokens: 6000,
          compression_threshold: 1500
        }
      }

      {:ok, result} = ContextConfigurationAction.run(params, context)
  """

  use Jido.Action,
    name: "context_configuration",
    description: "Manage context builder configuration, priorities, and metrics",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Configuration operation to perform (set_priorities, configure_limits, get_metrics, update_config, reset_config)"
      ],
      priorities: [
        type: :map,
        default: %{},
        doc: "Priority weights for context scoring"
      ],
      limits: [
        type: :map,
        default: %{},
        doc: "Token and cache limits configuration"
      ],
      config_updates: [
        type: :map,
        default: %{},
        doc: "General configuration updates"
      ],
      include_detailed_metrics: [
        type: :boolean,
        default: false,
        doc: "Whether to include detailed performance metrics"
      ],
      metrics_time_range: [
        type: :integer,
        default: 24,
        doc: "Time range for metrics calculation in hours"
      ],
      reset_to_defaults: [
        type: :boolean,
        default: false,
        doc: "Whether to reset configuration to system defaults"
      ],
      validate_config: [
        type: :boolean,
        default: true,
        doc: "Whether to validate configuration changes"
      ]
    ]

  require Logger

  @default_priorities %{
    relevance_weight: 0.4,
    recency_weight: 0.3,
    importance_weight: 0.3
  }

  @default_limits %{
    max_cache_size: 100,
    cache_ttl: 300_000,  # 5 minutes
    default_max_tokens: 4000,
    compression_threshold: 1000,
    parallel_source_limit: 10,
    source_timeout: 5000,
    dedup_threshold: 0.85,
    summary_ratio: 0.3
  }

  @impl true
  def run(params, context) do
    Logger.info("Executing configuration operation: #{params.operation}")

    case params.operation do
      :set_priorities -> set_priorities(params, context)
      :configure_limits -> configure_limits(params, context)
      :get_metrics -> get_metrics(params, context)
      :update_config -> update_config(params, context)
      :reset_config -> reset_config(params, context)
      :validate_config -> validate_config(params, context)
      :export_config -> export_config(params, context)
      _ -> {:error, {:invalid_operation, params.operation}}
    end
  end

  # Priority configuration

  defp set_priorities(params, context) do
    with {:ok, validated_priorities} <- validate_priorities(params.priorities),
         {:ok, normalized_priorities} <- normalize_priorities(validated_priorities),
         {:ok, _} <- store_priorities(normalized_priorities, context) do
      
      result = %{
        priorities: normalized_priorities,
        previous_priorities: get_current_priorities(context),
        updated_at: DateTime.utc_now(),
        validation_results: %{
          weights_normalized: true,
          total_weight: 1.0,
          valid_fields: Map.keys(normalized_priorities)
        }
      }

      emit_config_updated_signal(:priorities, normalized_priorities)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Priority configuration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_priorities(priorities) do
    required_weights = [:relevance_weight, :recency_weight, :importance_weight]
    
    # Convert string keys to atoms if needed
    normalized_keys = Map.new(priorities, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end)
    
    # Check for required fields
    missing_fields = Enum.filter(required_weights, fn field ->
      not Map.has_key?(normalized_keys, field)
    end)
    
    if Enum.empty?(missing_fields) do
      # Validate weight values
      invalid_weights = Enum.filter(normalized_keys, fn {_k, v} ->
        not is_number(v) or v < 0
      end)
      
      if Enum.empty?(invalid_weights) do
        {:ok, Map.take(normalized_keys, required_weights)}
      else
        {:error, {:invalid_weights, invalid_weights}}
      end
    else
      {:error, {:missing_required_weights, missing_fields}}
    end
  end

  defp normalize_priorities(priorities) do
    total = Enum.sum(Map.values(priorities))
    
    if total > 0 do
      normalized = Map.new(priorities, fn {k, v} -> {k, v / total} end)
      {:ok, normalized}
    else
      {:error, {:invalid_priority_total, total}}
    end
  end

  # Limits configuration

  defp configure_limits(params, context) do
    with {:ok, validated_limits} <- validate_limits(params.limits),
         {:ok, _} <- store_limits(validated_limits, context) do
      
      current_limits = get_current_limits(context)
      merged_limits = Map.merge(current_limits, validated_limits)
      
      result = %{
        limits: merged_limits,
        updated_fields: Map.keys(validated_limits),
        previous_values: Map.take(current_limits, Map.keys(validated_limits)),
        updated_at: DateTime.utc_now(),
        validation_results: %{
          valid_ranges: true,
          memory_impact: estimate_memory_impact(merged_limits),
          performance_impact: estimate_performance_impact(merged_limits)
        }
      }

      emit_config_updated_signal(:limits, validated_limits)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Limits configuration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_limits(limits) do
    allowed_fields = [
      :max_cache_size, :cache_ttl, :default_max_tokens, :compression_threshold,
      :parallel_source_limit, :source_timeout, :dedup_threshold, :summary_ratio
    ]
    
    # Convert string keys to atoms if needed
    normalized_keys = Map.new(limits, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end)
    
    # Filter to allowed fields only
    filtered_limits = Map.take(normalized_keys, allowed_fields)
    
    # Validate field values
    validation_errors = Enum.reduce(filtered_limits, [], fn {field, value}, acc ->
      case validate_limit_field(field, value) do
        :ok -> acc
        {:error, reason} -> [{field, reason} | acc]
      end
    end)
    
    if Enum.empty?(validation_errors) do
      {:ok, filtered_limits}
    else
      {:error, {:invalid_limit_values, validation_errors}}
    end
  end

  defp validate_limit_field(:max_cache_size, value) when is_integer(value) and value > 0 and value <= 10000, do: :ok
  defp validate_limit_field(:cache_ttl, value) when is_integer(value) and value > 0, do: :ok
  defp validate_limit_field(:default_max_tokens, value) when is_integer(value) and value > 0 and value <= 100000, do: :ok
  defp validate_limit_field(:compression_threshold, value) when is_integer(value) and value > 0, do: :ok
  defp validate_limit_field(:parallel_source_limit, value) when is_integer(value) and value > 0 and value <= 50, do: :ok
  defp validate_limit_field(:source_timeout, value) when is_integer(value) and value > 0 and value <= 60000, do: :ok
  defp validate_limit_field(:dedup_threshold, value) when is_float(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_limit_field(:summary_ratio, value) when is_float(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_limit_field(field, value), do: {:error, {:invalid_value, field, value}}

  # Metrics collection

  defp get_metrics(params, context) do
    case collect_metrics(params, context) do
      {:ok, metrics} ->
        enhanced_metrics = if params.include_detailed_metrics do
          Map.merge(metrics, collect_detailed_metrics(params, context))
        else
          metrics
        end
        
        result = %{
          metrics: enhanced_metrics,
          collected_at: DateTime.utc_now(),
          time_range_hours: params.metrics_time_range,
          detailed: params.include_detailed_metrics
        }
        
        {:ok, result}
        
      {:error, reason} ->
        Logger.error("Metrics collection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp collect_metrics(params, context) do
    base_metrics = get_base_metrics(context)
    time_range_metrics = get_time_range_metrics(params.metrics_time_range, context)
    
    metrics = Map.merge(base_metrics, time_range_metrics)
    {:ok, metrics}
  end

  defp get_base_metrics(_context) do
    # TODO: Collect from actual agent state
    %{
      builds_completed: 0,
      avg_build_time_ms: 0.0,
      cache_hits: 0,
      cache_misses: 0,
      cache_hit_rate: 0.0,
      total_tokens_saved: 0,
      avg_compression_ratio: 1.0,
      cache_size: 0,
      active_builds: 0,
      registered_sources: 0,
      source_failures: %{}
    }
  end

  defp get_time_range_metrics(_time_range, _context) do
    # TODO: Collect time-based metrics
    %{
      builds_last_hour: 0,
      avg_response_time_ms: 0.0,
      error_rate: 0.0,
      cache_efficiency: 0.0
    }
  end

  defp collect_detailed_metrics(params, context) do
    %{
      performance_breakdown: get_performance_breakdown(context),
      source_performance: get_source_performance_metrics(context),
      cache_analysis: get_cache_analysis(context),
      resource_usage: get_resource_usage_metrics(context),
      trend_analysis: get_trend_analysis(params.metrics_time_range, context)
    }
  end

  defp get_performance_breakdown(_context) do
    %{
      source_fetch_time_ms: 0.0,
      prioritization_time_ms: 0.0,
      optimization_time_ms: 0.0,
      assembly_time_ms: 0.0
    }
  end

  defp get_source_performance_metrics(_context) do
    %{
      by_source_type: %{},
      failure_rates: %{},
      avg_response_times: %{}
    }
  end

  defp get_cache_analysis(_context) do
    %{
      hit_rate_by_purpose: %{},
      average_entry_age: 0.0,
      compression_effectiveness: 0.0,
      memory_usage_mb: 0.0
    }
  end

  defp get_resource_usage_metrics(_context) do
    %{
      memory_usage_mb: 0.0,
      cpu_usage_percent: 0.0,
      concurrent_builds: 0,
      queue_length: 0
    }
  end

  defp get_trend_analysis(_time_range, _context) do
    %{
      build_rate_trend: :stable,
      performance_trend: :stable,
      error_rate_trend: :stable,
      cache_efficiency_trend: :stable
    }
  end

  # General configuration updates

  defp update_config(params, context) do
    if params.validate_config do
      case validate_general_config(params.config_updates) do
        {:ok, validated_config} ->
          apply_config_updates(validated_config, context)
          
        {:error, reason} ->
          {:error, reason}
      end
    else
      apply_config_updates(params.config_updates, context)
    end
  end

  defp apply_config_updates(config_updates, context) do
    with {:ok, _} <- store_config_updates(config_updates, context) do
      current_config = get_current_config(context)
      
      result = %{
        updated_config: Map.merge(current_config, config_updates),
        updated_fields: Map.keys(config_updates),
        updated_at: DateTime.utc_now(),
        requires_restart: requires_restart?(config_updates)
      }

      emit_config_updated_signal(:general, config_updates)
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_general_config(config_updates) do
    # Basic validation for general configuration updates
    # TODO: Implement comprehensive validation
    {:ok, config_updates}
  end

  defp requires_restart?(config_updates) do
    restart_required_fields = [:parallel_source_limit, :source_timeout]
    
    Enum.any?(Map.keys(config_updates), fn key ->
      key in restart_required_fields
    end)
  end

  # Configuration reset

  defp reset_config(params, context) do
    if params.reset_to_defaults do
      with {:ok, _} <- store_priorities(@default_priorities, context),
           {:ok, _} <- store_limits(@default_limits, context) do
        
        result = %{
          reset_priorities: @default_priorities,
          reset_limits: @default_limits,
          reset_at: DateTime.utc_now(),
          previous_config: get_current_config(context)
        }

        emit_config_updated_signal(:reset, %{to_defaults: true})
        {:ok, result}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:reset_not_confirmed, "Set reset_to_defaults: true to confirm reset"}}
    end
  end

  # Configuration validation

  defp validate_config(params, context) do
    current_config = get_current_config(context)
    
    validation_results = %{
      priorities: validate_priorities(current_config.priorities || @default_priorities),
      limits: validate_limits(current_config.limits || @default_limits),
      consistency: check_config_consistency(current_config),
      performance_impact: estimate_performance_impact(current_config)
    }
    
    overall_valid = Enum.all?(validation_results, fn {_key, result} ->
      case result do
        {:ok, _} -> true
        :ok -> true
        _ -> false
      end
    end)
    
    result = %{
      valid: overall_valid,
      validation_results: validation_results,
      validated_at: DateTime.utc_now(),
      recommendations: generate_config_recommendations(validation_results)
    }
    
    {:ok, result}
  end

  defp check_config_consistency(config) do
    # Check for configuration inconsistencies
    issues = []
    
    # Example consistency checks
    limits = config.limits || @default_limits
    
    issues = if limits[:compression_threshold] > limits[:default_max_tokens] do
      [:compression_threshold_too_high | issues]
    else
      issues
    end
    
    if Enum.empty?(issues) do
      :ok
    else
      {:warning, issues}
    end
  end

  defp generate_config_recommendations(validation_results) do
    recommendations = []
    
    # Generate recommendations based on validation results
    recommendations = case validation_results.consistency do
      {:warning, issues} ->
        Enum.map(issues, &config_issue_to_recommendation/1) ++ recommendations
      _ ->
        recommendations
    end
    
    recommendations
  end

  defp config_issue_to_recommendation(:compression_threshold_too_high) do
    "Consider lowering compression_threshold to be less than default_max_tokens"
  end
  defp config_issue_to_recommendation(issue) do
    "Address configuration issue: #{issue}"
  end

  # Configuration export

  defp export_config(_params, context) do
    config = get_current_config(context)
    
    exported_config = %{
      priorities: config.priorities || @default_priorities,
      limits: config.limits || @default_limits,
      metadata: %{
        exported_at: DateTime.utc_now(),
        export_version: "1.0",
        agent_name: "context_builder"
      }
    }
    
    result = %{
      config: exported_config,
      format: :map,
      exported_at: DateTime.utc_now()
    }
    
    {:ok, result}
  end

  # Context interface helpers

  defp store_priorities(_priorities, _context) do
    # TODO: Store in actual agent state
    {:ok, :stored}
  end

  defp store_limits(_limits, _context) do
    # TODO: Store in actual agent state  
    {:ok, :stored}
  end

  defp store_config_updates(_config_updates, _context) do
    # TODO: Store in actual agent state
    {:ok, :stored}
  end

  defp get_current_priorities(_context) do
    # TODO: Retrieve from actual agent state
    @default_priorities
  end

  defp get_current_limits(_context) do
    # TODO: Retrieve from actual agent state
    @default_limits
  end

  defp get_current_config(_context) do
    # TODO: Retrieve from actual agent state
    %{
      priorities: @default_priorities,
      limits: @default_limits
    }
  end

  # Impact estimation

  defp estimate_memory_impact(limits) do
    cache_size_mb = (limits[:max_cache_size] || 100) * 0.1  # Rough estimate
    
    %{
      estimated_cache_size_mb: cache_size_mb,
      impact_level: cond do
        cache_size_mb < 10 -> :low
        cache_size_mb < 50 -> :medium
        true -> :high
      end
    }
  end

  defp estimate_performance_impact(config) do
    limits = config[:limits] || config
    
    impact_factors = []
    
    impact_factors = if (limits[:parallel_source_limit] || 10) > 20 do
      [:high_parallelism | impact_factors]
    else
      impact_factors
    end
    
    impact_factors = if (limits[:source_timeout] || 5000) < 1000 do
      [:low_timeout | impact_factors]
    else
      impact_factors
    end
    
    %{
      impact_factors: impact_factors,
      overall_impact: if(length(impact_factors) > 1, do: :medium, else: :low)
    }
  end

  # Signal emission

  defp emit_config_updated_signal(config_type, updates) do
    # TODO: Emit actual signal
    Logger.debug("Configuration updated: #{config_type}, updates: #{inspect(Map.keys(updates))}")
  end
end