defmodule RubberDuck.ErrorDetection.ErrorClassifier do
  @moduledoc """
  Error classification system for categorizing and scoring detected errors.
  
  Provides comprehensive error classification through:
  - Error taxonomy and categorization
  - Severity scoring and impact analysis
  - Priority-based routing and handling
  - Context-aware classification
  - Learning-based classification improvement
  """

  require Logger

  # Error taxonomy definitions
  @error_taxonomy %{
    syntax: %{
      description: "Syntax and parsing errors",
      base_severity: 8,
      subcategories: [:parsing, :missing_tokens, :invalid_structure, :encoding]
    },
    logic: %{
      description: "Logic and algorithmic errors",
      base_severity: 7,
      subcategories: [:infinite_loops, :unreachable_code, :wrong_conditions, :data_flow]
    },
    runtime: %{
      description: "Runtime and execution errors",
      base_severity: 9,
      subcategories: [:exceptions, :timeouts, :memory_issues, :resource_exhaustion]
    },
    security: %{
      description: "Security vulnerabilities and risks",
      base_severity: 9,
      subcategories: [:injection, :xss, :authentication, :authorization, :secrets]
    },
    performance: %{
      description: "Performance and optimization issues",
      base_severity: 5,
      subcategories: [:slow_queries, :memory_leaks, :cpu_intensive, :io_bottlenecks]
    },
    quality: %{
      description: "Code quality and maintainability",
      base_severity: 4,
      subcategories: [:complexity, :duplication, :naming, :documentation, :formatting]
    },
    compatibility: %{
      description: "Version and platform compatibility",
      base_severity: 6,
      subcategories: [:version_conflicts, :platform_specific, :deprecated_apis, :breaking_changes]
    }
  }

  # Impact scoring weights
  @impact_weights %{
    user_facing: 2.0,
    data_integrity: 2.5,
    system_stability: 2.0,
    security_risk: 3.0,
    performance_impact: 1.5,
    maintainability: 1.0
  }

  @doc """
  Classifies a list of errors using the specified strategy.
  """
  def classify_errors(errors, classification_rules, strategy \\ "comprehensive") do
    Logger.info("Classifying #{length(errors)} errors with strategy: #{strategy}")
    
    try do
      classified = case strategy do
        "comprehensive" ->
          comprehensive_classification(errors, classification_rules)
        
        "severity_focused" ->
          severity_focused_classification(errors, classification_rules)
        
        "impact_analysis" ->
          impact_analysis_classification(errors, classification_rules)
        
        "context_aware" ->
          context_aware_classification(errors, classification_rules)
        
        "machine_learning" ->
          ml_based_classification(errors, classification_rules)
        
        _ ->
          basic_classification(errors, classification_rules)
      end
      
      # Sort by priority (severity + impact)
      Enum.sort_by(classified, &calculate_priority/1, :desc)
    rescue
      e ->
        Logger.error("Error in classification: #{Exception.message(e)}")
        # Return basic classification as fallback
        basic_classification(errors, classification_rules)
    end
  end

  @doc """
  Creates a new classification rule.
  """
  def create_classification_rule(pattern, category, severity, conditions \\ []) do
    %{
      id: generate_rule_id(pattern, category),
      pattern: pattern,
      category: category,
      severity: severity,
      conditions: conditions,
      confidence: 1.0,
      created_at: DateTime.utc_now(),
      usage_count: 0,
      success_rate: 1.0
    }
  end

  @doc """
  Updates classification rules based on feedback.
  """
  def update_classification_rules(rules, feedback) do
    try do
      updated_rules = rules
      |> update_rule_success_rates(feedback)
      |> adjust_rule_severities(feedback)
      |> add_new_rules_from_feedback(feedback)
      |> remove_ineffective_rules(feedback)
      
      Logger.info("Updated #{map_size(updated_rules)} classification rules")
      updated_rules
    rescue
      e ->
        Logger.error("Error updating classification rules: #{Exception.message(e)}")
        rules
    end
  end

  @doc """
  Analyzes error impact across different dimensions.
  """
  def analyze_error_impact(error, context \\ %{}) do
    impact_dimensions = %{
      user_facing: assess_user_impact(error, context),
      data_integrity: assess_data_integrity_impact(error, context),
      system_stability: assess_system_stability_impact(error, context),
      security_risk: assess_security_risk(error, context),
      performance_impact: assess_performance_impact(error, context),
      maintainability: assess_maintainability_impact(error, context)
    }
    
    overall_impact = calculate_overall_impact(impact_dimensions)
    
    %{
      dimensions: impact_dimensions,
      overall_impact: overall_impact,
      weighted_score: calculate_weighted_impact_score(impact_dimensions)
    }
  end

  # Private Implementation Functions

  # Classification Strategies
  defp comprehensive_classification(errors, rules) do
    errors
    |> Enum.map(fn error ->
      # Apply all classification steps
      error
      |> classify_by_taxonomy()
      |> apply_classification_rules(rules)
      |> calculate_severity_score()
      |> analyze_impact()
      |> determine_routing()
    end)
  end

  defp severity_focused_classification(errors, rules) do
    errors
    |> Enum.map(fn error ->
      error
      |> classify_by_taxonomy()
      |> apply_classification_rules(rules)
      |> calculate_enhanced_severity_score()
    end)
  end

  defp impact_analysis_classification(errors, rules) do
    errors
    |> Enum.map(fn error ->
      error
      |> classify_by_taxonomy()
      |> apply_classification_rules(rules)
      |> analyze_comprehensive_impact()
    end)
  end

  defp context_aware_classification(errors, rules) do
    # Group errors by context for better classification
    context_groups = group_errors_by_context(errors)
    
    context_groups
    |> Enum.flat_map(fn {context, context_errors} ->
      classify_errors_in_context(context_errors, context, rules)
    end)
  end

  defp ml_based_classification(errors, rules) do
    # Use machine learning models for classification
    features = extract_error_features(errors)
    predictions = apply_ml_models(features, rules)
    
    errors
    |> Enum.zip(predictions)
    |> Enum.map(fn {error, prediction} ->
      Map.merge(error, prediction)
    end)
  end

  defp basic_classification(errors, _rules) do
    errors
    |> Enum.map(&classify_by_taxonomy/1)
  end

  # Core Classification Functions
  defp classify_by_taxonomy(error) do
    category = determine_primary_category(error)
    subcategory = determine_subcategory(error, category)
    
    taxonomy_info = Map.get(@error_taxonomy, category, %{})
    base_severity = Map.get(taxonomy_info, :base_severity, 5)
    
    Map.merge(error, %{
      primary_category: category,
      subcategory: subcategory,
      base_severity: base_severity,
      taxonomy_description: Map.get(taxonomy_info, :description, "Unknown category")
    })
  end

  defp apply_classification_rules(error, rules) do
    # Find matching rules
    matching_rules = find_matching_rules(error, rules)
    
    # Apply rules to enhance classification
    enhanced_error = Enum.reduce(matching_rules, error, fn rule, acc_error ->
      apply_single_rule(acc_error, rule)
    end)
    
    Map.put(enhanced_error, :applied_rules, Enum.map(matching_rules, & &1.id))
  end

  defp calculate_severity_score(error) do
    base_severity = Map.get(error, :base_severity, 5)
    confidence = Map.get(error, :confidence, 0.5)
    
    # Adjust severity based on various factors
    adjustments = [
      security_adjustment(error),
      complexity_adjustment(error),
      frequency_adjustment(error),
      context_adjustment(error)
    ]
    
    total_adjustment = Enum.sum(adjustments)
    final_severity = max(1, min(10, base_severity + total_adjustment))
    
    Map.merge(error, %{
      severity_score: final_severity,
      severity_confidence: confidence,
      severity_adjustments: adjustments
    })
  end

  defp analyze_impact(error) do
    impact_analysis = analyze_error_impact(error, %{})
    
    Map.merge(error, %{
      impact_analysis: impact_analysis,
      impact_score: impact_analysis.weighted_score
    })
  end

  defp determine_routing(error) do
    severity = Map.get(error, :severity_score, 5)
    impact = Map.get(error, :impact_score, 0)
    category = Map.get(error, :primary_category, :unknown)
    
    routing_decision = cond do
      severity >= 9 || impact >= 8 ->
        %{priority: :critical, handler: :immediate_response, escalation: true}
      
      severity >= 7 || impact >= 6 ->
        %{priority: :high, handler: :priority_queue, escalation: false}
      
      severity >= 5 || impact >= 4 ->
        %{priority: :medium, handler: :standard_queue, escalation: false}
      
      category == :security ->
        %{priority: :high, handler: :security_team, escalation: true}
      
      true ->
        %{priority: :low, handler: :background_processing, escalation: false}
    end
    
    Map.put(error, :routing, routing_decision)
  end

  # Category Determination
  defp determine_primary_category(error) do
    error_type = Map.get(error, :type, :unknown)
    description = Map.get(error, :description, "")
    category_hint = Map.get(error, :category, nil)
    
    cond do
      category_hint && Map.has_key?(@error_taxonomy, category_hint) ->
        category_hint
      
      error_type == :syntax_error ->
        :syntax
      
      error_type == :runtime_error ->
        :runtime
      
      String.contains?(String.downcase(description), ["security", "vulnerability", "exploit"]) ->
        :security
      
      String.contains?(String.downcase(description), ["performance", "slow", "timeout"]) ->
        :performance
      
      String.contains?(String.downcase(description), ["logic", "algorithm", "condition"]) ->
        :logic
      
      String.contains?(String.downcase(description), ["quality", "maintainability", "complexity"]) ->
        :quality
      
      true ->
        :unknown
    end
  end

  defp determine_subcategory(error, category) do
    description = String.downcase(Map.get(error, :description, ""))
    subcategories = get_subcategories(category)
    
    # Find best matching subcategory
    subcategories
    |> Enum.find(fn subcategory ->
      subcategory_keywords = get_subcategory_keywords(subcategory)
      Enum.any?(subcategory_keywords, &String.contains?(description, &1))
    end) || :general
  end

  defp get_subcategories(category) do
    @error_taxonomy
    |> Map.get(category, %{})
    |> Map.get(:subcategories, [:general])
  end

  defp get_subcategory_keywords(subcategory) do
    case subcategory do
      :parsing -> ["parse", "syntax", "token"]
      :missing_tokens -> ["missing", "expected", "incomplete"]
      :invalid_structure -> ["invalid", "malformed", "structure"]
      :encoding -> ["encoding", "utf", "character"]
      :infinite_loops -> ["infinite", "loop", "endless"]
      :unreachable_code -> ["unreachable", "dead code", "never executed"]
      :wrong_conditions -> ["condition", "branch", "if", "case"]
      :data_flow -> ["data flow", "variable", "assignment"]
      :exceptions -> ["exception", "error", "crash"]
      :timeouts -> ["timeout", "deadline", "expired"]
      :memory_issues -> ["memory", "allocation", "leak"]
      :resource_exhaustion -> ["resource", "exhausted", "limit"]
      :injection -> ["injection", "sql", "command"]
      :xss -> ["xss", "cross-site", "script"]
      :authentication -> ["auth", "login", "credential"]
      :authorization -> ["permission", "access", "forbidden"]
      :secrets -> ["secret", "password", "key", "token"]
      _ -> [Atom.to_string(subcategory)]
    end
  end

  # Severity Adjustments
  defp security_adjustment(error) do
    category = Map.get(error, :primary_category)
    if category == :security, do: 2, else: 0
  end

  defp complexity_adjustment(error) do
    # Increase severity for complex errors
    description_length = String.length(Map.get(error, :description, ""))
    if description_length > 200, do: 1, else: 0
  end

  defp frequency_adjustment(error) do
    frequency = Map.get(error, :frequency, 1)
    cond do
      frequency > 10 -> 2
      frequency > 5 -> 1
      true -> 0
    end
  end

  defp context_adjustment(error) do
    # Adjust based on error context
    line = Map.get(error, :line, 0)
    if line > 0, do: 0, else: -1  # Errors without line info are less severe
  end

  # Impact Assessment Functions
  defp assess_user_impact(error, context) do
    category = Map.get(error, :primary_category, :unknown)
    _severity = Map.get(error, :severity_score, 5)
    user_facing = Map.get(context, :user_facing, false)
    
    base_impact = case category do
      :security -> 9
      :runtime -> 8
      :syntax -> 7
      :performance -> 6
      _ -> 4
    end
    
    if user_facing, do: min(10, base_impact + 2), else: base_impact
  end

  defp assess_data_integrity_impact(error, context) do
    category = Map.get(error, :primary_category, :unknown)
    affects_data = Map.get(context, :affects_data, false)
    
    base_impact = case category do
      :security -> 10
      :logic -> 8
      :runtime -> 7
      _ -> 3
    end
    
    if affects_data, do: min(10, base_impact + 3), else: base_impact
  end

  defp assess_system_stability_impact(error, context) do
    category = Map.get(error, :primary_category, :unknown)
    critical_system = Map.get(context, :critical_system, false)
    
    base_impact = case category do
      :runtime -> 9
      :security -> 8
      :logic -> 6
      _ -> 4
    end
    
    if critical_system, do: min(10, base_impact + 2), else: base_impact
  end

  defp assess_security_risk(error, _context) do
    category = Map.get(error, :primary_category, :unknown)
    
    case category do
      :security -> 10
      :logic -> 5
      :runtime -> 4
      _ -> 2
    end
  end

  defp assess_performance_impact(error, context) do
    category = Map.get(error, :primary_category, :unknown)
    performance_critical = Map.get(context, :performance_critical, false)
    
    base_impact = case category do
      :performance -> 9
      :logic -> 6
      :runtime -> 5
      _ -> 3
    end
    
    if performance_critical, do: min(10, base_impact + 2), else: base_impact
  end

  defp assess_maintainability_impact(error, _context) do
    category = Map.get(error, :primary_category, :unknown)
    
    case category do
      :quality -> 8
      :logic -> 6
      :syntax -> 4
      _ -> 3
    end
  end

  defp calculate_overall_impact(impact_dimensions) do
    values = Map.values(impact_dimensions)
    max_impact = Enum.max(values)
    avg_impact = Enum.sum(values) / length(values)
    
    # Overall impact is weighted towards the maximum
    (max_impact * 0.7) + (avg_impact * 0.3)
  end

  defp calculate_weighted_impact_score(impact_dimensions) do
    @impact_weights
    |> Enum.map(fn {dimension, weight} ->
      impact = Map.get(impact_dimensions, dimension, 0)
      impact * weight
    end)
    |> Enum.sum()
    |> Kernel./(Enum.sum(Map.values(@impact_weights)))
  end

  # Rule Management Functions
  defp find_matching_rules(error, rules) do
    rules
    |> Map.values()
    |> Enum.filter(&rule_matches_error?(&1, error))
  end

  defp rule_matches_error?(rule, error) do
    pattern = rule.pattern
    description = Map.get(error, :description, "")
    category = Map.get(error, :primary_category, :unknown)
    
    # Check pattern match
    pattern_match = cond do
      is_binary(pattern) -> String.contains?(String.downcase(description), String.downcase(pattern))
      is_struct(pattern, Regex) -> Regex.match?(pattern, description)
      true -> false
    end
    
    # Check category match if specified
    category_match = case Map.get(rule, :category) do
      nil -> true
      rule_category -> rule_category == category
    end
    
    # Check additional conditions
    conditions_match = check_rule_conditions(rule.conditions, error)
    
    pattern_match && category_match && conditions_match
  end

  defp check_rule_conditions(conditions, error) do
    Enum.all?(conditions, fn condition ->
      check_single_condition(condition, error)
    end)
  end

  defp check_single_condition(%{field: field, operator: operator, value: value}, error) do
    error_value = Map.get(error, String.to_atom(field))
    
    case operator do
      "eq" -> error_value == value
      "ne" -> error_value != value
      "gt" -> error_value > value
      "lt" -> error_value < value
      "gte" -> error_value >= value
      "lte" -> error_value <= value
      "contains" -> String.contains?(to_string(error_value), to_string(value))
      _ -> true
    end
  end
  defp check_single_condition(_, _), do: true

  defp apply_single_rule(error, rule) do
    # Update rule usage statistics
    _updated_rule = %{rule | usage_count: rule.usage_count + 1}
    
    # Apply rule modifications to error
    error
    |> apply_rule_severity_override(rule)
    |> apply_rule_category_override(rule)
    |> apply_rule_metadata(rule)
  end

  defp apply_rule_severity_override(error, rule) do
    case Map.get(rule, :severity_override) do
      nil -> error
      severity -> Map.put(error, :rule_severity, severity)
    end
  end

  defp apply_rule_category_override(error, rule) do
    case Map.get(rule, :category_override) do
      nil -> error
      category -> Map.put(error, :rule_category, category)
    end
  end

  defp apply_rule_metadata(error, rule) do
    rule_metadata = %{
      rule_id: rule.id,
      rule_confidence: rule.confidence,
      rule_applied_at: DateTime.utc_now()
    }
    
    Map.put(error, :rule_metadata, rule_metadata)
  end

  # Helper Functions
  defp calculate_priority(error) do
    severity = Map.get(error, :severity_score, 5)
    impact = Map.get(error, :impact_score, 0)
    
    # Weighted priority calculation
    (severity * 0.6) + (impact * 0.4)
  end

  defp generate_rule_id(pattern, category) do
    content = "#{pattern}_#{category}"
    :crypto.hash(:md5, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  # Placeholder implementations for complex features
  defp calculate_enhanced_severity_score(error), do: calculate_severity_score(error)
  defp analyze_comprehensive_impact(error), do: analyze_impact(error)
  defp group_errors_by_context(errors), do: %{"default" => errors}
  defp classify_errors_in_context(errors, _context, rules) do
    Enum.map(errors, fn error ->
      error
      |> classify_by_taxonomy()
      |> apply_classification_rules(rules)
    end)
  end
  defp extract_error_features(errors), do: Enum.map(errors, &[&1])
  defp apply_ml_models(_features, _rules), do: []
  defp update_rule_success_rates(rules, _feedback), do: rules
  defp adjust_rule_severities(rules, _feedback), do: rules
  defp add_new_rules_from_feedback(rules, _feedback), do: rules
  defp remove_ineffective_rules(rules, _feedback), do: rules
end