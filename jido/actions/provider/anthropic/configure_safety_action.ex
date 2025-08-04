defmodule RubberDuck.Jido.Actions.Provider.Anthropic.ConfigureSafetyAction do
  @moduledoc """
  Action for configuring Anthropic Claude safety settings and content filtering.

  This action handles the configuration of Anthropic's safety features including
  content filtering levels, topic restrictions, and harmful content blocking to
  ensure responsible AI usage according to Anthropic's safety guidelines.

  ## Parameters

  - `operation` - Safety operation to perform (required: :configure, :update, :get_status, :reset)
  - `safety_config` - Safety configuration map (required for :configure and :update)
  - `content_filtering` - Content filtering level (default: :moderate)
  - `block_flagged_content` - Whether to block flagged content (default: true)
  - `allowed_topics` - Allowed topic categories (default: :all)
  - `restricted_topics` - List of restricted topics (default: [])
  - `custom_filters` - Custom content filters (default: [])

  ## Returns

  - `{:ok, result}` - Safety configuration completed successfully
  - `{:error, reason}` - Safety configuration failed

  ## Example

      params = %{
        operation: :configure,
        safety_config: %{
          content_filtering: :strict,
          block_flagged_content: true,
          allowed_topics: [:general, :educational, :technical],
          restricted_topics: [:harmful, :inappropriate]
        }
      }

      {:ok, result} = ConfigureSafetyAction.run(params, context)
  """

  use Jido.Action,
    name: "configure_safety",
    description: "Configure Anthropic Claude safety settings and content filtering",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Safety operation to perform (configure, update, get_status, reset)"
      ],
      safety_config: [
        type: :map,
        default: %{},
        doc: "Safety configuration settings"
      ],
      content_filtering: [
        type: :atom,
        default: :moderate,
        doc: "Content filtering level (strict, moderate, relaxed)"
      ],
      block_flagged_content: [
        type: :boolean,
        default: true,
        doc: "Whether to block flagged content"
      ],
      allowed_topics: [
        type: {:union, [:atom, {:list, :atom}]},
        default: :all,
        doc: "Allowed topic categories"
      ],
      restricted_topics: [
        type: {:list, :atom},
        default: [],
        doc: "List of restricted topics"
      ],
      custom_filters: [
        type: :list,
        default: [],
        doc: "Custom content filters"
      ],
      validate_configuration: [
        type: :boolean,
        default: true,
        doc: "Whether to validate configuration against Anthropic guidelines"
      ]
    ]

  require Logger

  @valid_filtering_levels [:strict, :moderate, :relaxed]
  @valid_topics [:general, :educational, :technical, :creative, :analysis, :coding]
  @restricted_topics [:harmful, :inappropriate, :illegal, :violent, :adult]

  @impl true
  def run(params, context) do
    Logger.info("Executing Anthropic safety operation: #{params.operation}")

    case params.operation do
      :configure -> configure_safety(params, context)
      :update -> update_safety(params, context)
      :get_status -> get_safety_status(params, context)
      :reset -> reset_safety(params, context)
      :validate -> validate_safety_config(params, context)
      _ -> {:error, {:invalid_operation, params.operation}}
    end
  end

  # Safety configuration

  defp configure_safety(params, context) do
    with {:ok, validated_config} <- validate_safety_configuration(params),
         {:ok, applied_config} <- apply_safety_configuration(validated_config, context),
         {:ok, _} <- store_safety_configuration(applied_config, context) do
      
      result = %{
        safety_config: applied_config,
        configured_at: DateTime.utc_now(),
        content_filtering: applied_config.content_filtering,
        restrictions_active: length(applied_config.restricted_topics) > 0,
        custom_filters_count: length(applied_config.custom_filters),
        validation_results: %{
          compliant: true,
          warnings: [],
          recommendations: generate_safety_recommendations(applied_config)
        }
      }

      emit_safety_configured_signal(applied_config)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Safety configuration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_safety_configuration(params) do
    config = build_safety_config(params)
    
    with {:ok, _} <- validate_filtering_level(config.content_filtering),
         {:ok, _} <- validate_topics(config.allowed_topics, config.restricted_topics),
         {:ok, _} <- validate_custom_filters(config.custom_filters) do
      
      {:ok, config}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp build_safety_config(params) do
    base_config = %{
      content_filtering: params.content_filtering,
      block_flagged_content: params.block_flagged_content,
      allowed_topics: params.allowed_topics,
      restricted_topics: params.restricted_topics,
      custom_filters: params.custom_filters
    }
    
    # Merge with provided safety_config
    Map.merge(base_config, params.safety_config)
  end

  defp validate_filtering_level(level) do
    if level in @valid_filtering_levels do
      {:ok, level}
    else
      {:error, {:invalid_filtering_level, level, @valid_filtering_levels}}
    end
  end

  defp validate_topics(:all, _restricted), do: {:ok, :validated}
  defp validate_topics(allowed, restricted) when is_list(allowed) do
    invalid_allowed = allowed -- @valid_topics
    invalid_restricted = restricted -- @restricted_topics
    
    cond do
      not Enum.empty?(invalid_allowed) ->
        {:error, {:invalid_allowed_topics, invalid_allowed}}
      
      not Enum.empty?(invalid_restricted) ->
        {:error, {:invalid_restricted_topics, invalid_restricted}}
        
      not Enum.empty?(allowed -- restricted) ->
        {:ok, :validated}
        
      true ->
        {:error, {:conflicting_topics, "Allowed and restricted topics overlap"}}
    end
  end

  defp validate_custom_filters(filters) when is_list(filters) do
    invalid_filters = Enum.filter(filters, fn filter ->
      not is_map(filter) or not Map.has_key?(filter, :pattern) or not Map.has_key?(filter, :action)
    end)
    
    if Enum.empty?(invalid_filters) do
      {:ok, :validated}
    else
      {:error, {:invalid_custom_filters, invalid_filters}}
    end
  end

  defp apply_safety_configuration(config, _context) do
    # Apply configuration transformations and optimizations
    optimized_config = config
    |> optimize_filtering_rules()
    |> compile_custom_filters()
    |> add_anthropic_defaults()
    
    {:ok, optimized_config}
  end

  defp optimize_filtering_rules(config) do
    # Optimize filtering rules based on Anthropic best practices
    case config.content_filtering do
      :strict ->
        %{config | 
          block_flagged_content: true,
          restricted_topics: Enum.uniq(config.restricted_topics ++ @restricted_topics)
        }
      
      :moderate ->
        %{config | 
          restricted_topics: Enum.uniq(config.restricted_topics ++ [:harmful, :inappropriate])
        }
      
      :relaxed ->
        %{config | 
          restricted_topics: Enum.uniq(config.restricted_topics ++ [:harmful])
        }
    end
  end

  defp compile_custom_filters(config) do
    compiled_filters = Enum.map(config.custom_filters, fn filter ->
      %{filter | 
        compiled_pattern: compile_filter_pattern(filter.pattern),
        compiled_at: DateTime.utc_now()
      }
    end)
    
    %{config | custom_filters: compiled_filters}
  end

  defp compile_filter_pattern(pattern) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> regex
      {:error, _} -> pattern
    end
  end
  defp compile_filter_pattern(pattern), do: pattern

  defp add_anthropic_defaults(config) do
    Map.merge(%{
      anthropic_version: "2023-06-01",
      safety_model: "claude-3-safety",
      response_filtering: true,
      prompt_filtering: true,
      content_classification: true
    }, config)
  end

  # Safety updates

  defp update_safety(params, context) do
    case get_current_safety_config(context) do
      {:ok, current_config} ->
        updated_config = Map.merge(current_config, params.safety_config)
        
        with {:ok, validated_config} <- validate_safety_configuration(%{params | safety_config: updated_config}),
             {:ok, _} <- store_safety_configuration(validated_config, context) do
          
          result = %{
            updated_config: validated_config,
            updated_at: DateTime.utc_now(),
            changes: calculate_config_changes(current_config, validated_config),
            warnings: generate_update_warnings(current_config, validated_config)
          }
          
          emit_safety_updated_signal(current_config, validated_config)
          {:ok, result}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_config_changes(old_config, new_config) do
    changed_fields = Enum.filter(Map.keys(new_config), fn key ->
      Map.get(old_config, key) != Map.get(new_config, key)
    end)
    
    %{
      changed_fields: changed_fields,
      severity_change: calculate_severity_change(old_config, new_config),
      impact: assess_change_impact(changed_fields)
    }
  end

  defp calculate_severity_change(old_config, new_config) do
    old_level = get_filtering_severity(old_config.content_filtering)
    new_level = get_filtering_severity(new_config.content_filtering)
    
    cond do
      new_level > old_level -> :increased
      new_level < old_level -> :decreased
      true -> :unchanged
    end
  end

  defp get_filtering_severity(:strict), do: 3
  defp get_filtering_severity(:moderate), do: 2
  defp get_filtering_severity(:relaxed), do: 1

  defp assess_change_impact([]), do: :none
  defp assess_change_impact(changes) do
    high_impact_fields = [:content_filtering, :block_flagged_content, :restricted_topics]
    
    if Enum.any?(changes, &(&1 in high_impact_fields)) do
      :high
    else
      :low
    end
  end

  # Safety status

  defp get_safety_status(_params, context) do
    case get_current_safety_config(context) do
      {:ok, config} ->
        result = %{
          safety_config: config,
          status: :active,
          last_updated: config[:configured_at] || DateTime.utc_now(),
          compliance_check: %{
            anthropic_compliant: check_anthropic_compliance(config),
            safety_level: get_safety_level(config),
            active_filters: count_active_filters(config)
          },
          performance_impact: estimate_performance_impact(config)
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_anthropic_compliance(config) do
    required_settings = [
      config.block_flagged_content == true,
      config.content_filtering in @valid_filtering_levels,
      :harmful in config.restricted_topics
    ]
    
    Enum.all?(required_settings)
  end

  defp get_safety_level(config) do
    base_level = case config.content_filtering do
      :strict -> 3
      :moderate -> 2
      :relaxed -> 1
    end
    
    modifier = cond do
      length(config.restricted_topics) > 3 -> 0.5
      length(config.custom_filters) > 0 -> 0.3
      true -> 0
    end
    
    min(4, base_level + modifier)
  end

  defp count_active_filters(config) do
    %{
      content_filtering: if(config.content_filtering != :relaxed, do: 1, else: 0),
      topic_restrictions: length(config.restricted_topics),
      custom_filters: length(config.custom_filters),
      total: 1 + length(config.restricted_topics) + length(config.custom_filters)
    }
  end

  defp estimate_performance_impact(config) do
    base_impact = case config.content_filtering do
      :strict -> 0.15
      :moderate -> 0.08
      :relaxed -> 0.03
    end
    
    filter_impact = length(config.custom_filters) * 0.02
    
    total_impact = base_impact + filter_impact
    
    %{
      estimated_latency_increase_ms: round(total_impact * 1000),
      throughput_reduction_percent: round(total_impact * 100),
      impact_level: cond do
        total_impact > 0.2 -> :high
        total_impact > 0.1 -> :medium
        true -> :low
      end
    }
  end

  # Safety reset

  defp reset_safety(_params, context) do
    default_config = %{
      content_filtering: :moderate,
      block_flagged_content: true,
      allowed_topics: :all,
      restricted_topics: [:harmful],
      custom_filters: []
    }
    
    case store_safety_configuration(default_config, context) do
      {:ok, _} ->
        result = %{
          reset_to: default_config,
          reset_at: DateTime.utc_now(),
          previous_config: get_current_safety_config(context)
        }
        
        emit_safety_reset_signal()
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Configuration validation

  defp validate_safety_config(params, _context) do
    case validate_safety_configuration(params) do
      {:ok, config} ->
        result = %{
          valid: true,
          config: config,
          compliance: check_anthropic_compliance(config),
          recommendations: generate_safety_recommendations(config),
          warnings: generate_configuration_warnings(config)
        }
        
        {:ok, result}
        
      {:error, reason} ->
        result = %{
          valid: false,
          errors: [reason],
          recommendations: ["Fix validation errors and try again"]
        }
        
        {:ok, result}
    end
  end

  # Helper functions

  defp generate_safety_recommendations(config) do
    recommendations = []
    
    recommendations = if config.content_filtering == :relaxed do
      ["Consider using :moderate or :strict filtering for better safety" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(config.custom_filters) == 0 do
      ["Consider adding custom filters for domain-specific content" | recommendations]
    else
      recommendations
    end
    
    recommendations = if :educational not in (config.allowed_topics || []) and config.allowed_topics != :all do
      ["Consider allowing educational content for better user experience" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  defp generate_update_warnings(old_config, new_config) do
    warnings = []
    
    warnings = if new_config.content_filtering != old_config.content_filtering do
      severity_change = calculate_severity_change(old_config, new_config)
      warning = case severity_change do
        :decreased -> "Reduced safety filtering may allow more inappropriate content"
        :increased -> "Increased safety filtering may block more legitimate content"
        :unchanged -> nil
      end
      if warning, do: [warning | warnings], else: warnings
    else
      warnings
    end
    
    warnings = if length(new_config.custom_filters) > length(old_config.custom_filters) do
      ["Added custom filters may impact performance" | warnings]
    else
      warnings
    end
    
    Enum.reverse(warnings)
  end

  defp generate_configuration_warnings(config) do
    warnings = []
    
    warnings = if config.content_filtering == :relaxed and config.block_flagged_content == false do
      ["Very permissive configuration may allow harmful content" | warnings]
    else
      warnings
    end
    
    warnings = if length(config.custom_filters) > 10 do
      ["Large number of custom filters may impact performance significantly" | warnings]
    else
      warnings
    end
    
    Enum.reverse(warnings)
  end

  # Context interface

  defp store_safety_configuration(config, _context) do
    # TODO: Store in actual agent state
    {:ok, :stored}
  end

  defp get_current_safety_config(_context) do
    # TODO: Retrieve from actual agent state
    {:ok, %{
      content_filtering: :moderate,
      block_flagged_content: true,
      allowed_topics: :all,
      restricted_topics: [:harmful],
      custom_filters: [],
      configured_at: DateTime.utc_now()
    }}
  end

  # Signal emission

  defp emit_safety_configured_signal(config) do
    # TODO: Emit actual signal
    Logger.debug("Safety configured: #{inspect(Map.keys(config))}")
  end

  defp emit_safety_updated_signal(old_config, new_config) do
    # TODO: Emit actual signal
    Logger.debug("Safety updated from #{old_config.content_filtering} to #{new_config.content_filtering}")
  end

  defp emit_safety_reset_signal() do
    # TODO: Emit actual signal
    Logger.debug("Safety configuration reset to defaults")
  end
end