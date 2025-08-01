defmodule RubberDuck.CorrectionStrategy.StrategySelector do
  @moduledoc """
  Strategy selection engine with multi-criteria decision making.
  
  Provides intelligent strategy selection through:
  - Multi-criteria decision algorithms
  - Constraint satisfaction checking
  - A/B testing framework
  - Machine learning-based recommendations
  - Confidence scoring and uncertainty quantification
  """

  alias RubberDuck.CorrectionStrategy.{CostEstimator, StrategyLibrary}

  @doc """
  Selects optimal strategies based on multi-criteria analysis.
  """
  def select_strategies(strategies, error_context, constraints, options \\ %{}) do
    selection_method = Map.get(options, "method", "weighted_scoring")
    
    case selection_method do
      "weighted_scoring" ->
        weighted_scoring_selection(strategies, error_context, constraints, options)
      
      "pareto_optimal" ->
        pareto_optimal_selection(strategies, error_context, constraints, options)
      
      "machine_learning" ->
        ml_based_selection(strategies, error_context, constraints, options)
      
      "a_b_testing" ->
        ab_testing_selection(strategies, error_context, constraints, options)
      
      _ ->
        weighted_scoring_selection(strategies, error_context, constraints, options)
    end
  end

  @doc """
  Evaluates strategy compatibility with error context and constraints.
  """
  def evaluate_compatibility(strategy, error_context, constraints) do
    checks = %{
      prerequisite_check: check_prerequisites(strategy, error_context),
      constraint_check: check_constraints(strategy, error_context, constraints),
      capability_check: check_capabilities(strategy, error_context),
      resource_check: check_resource_availability(strategy, constraints)
    }
    
    overall_compatibility = checks
    |> Map.values()
    |> Enum.all?(& &1.passed)
    
    %{
      compatible: overall_compatibility,
      checks: checks,
      compatibility_score: calculate_compatibility_score(checks)
    }
  end

  @doc """
  Performs A/B testing between strategies for continuous improvement.
  """
  def setup_ab_test(strategies, test_config) do
    test_groups = create_test_groups(strategies, test_config)
    
    %{
      test_id: generate_test_id(),
      groups: test_groups,
      config: test_config,
      status: :active,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Analyzes A/B test results and provides recommendations.
  """
  def analyze_ab_test(test_data) do
    group_results = test_data.groups
    |> Enum.map(fn {group_id, group_data} ->
      {group_id, analyze_group_performance(group_data)}
    end)
    |> Map.new()
    
    winner = determine_winning_strategy(group_results)
    statistical_significance = calculate_statistical_significance(group_results)
    
    %{
      results: group_results,
      winner: winner,
      statistical_significance: statistical_significance,
      recommendations: generate_ab_recommendations(group_results, winner),
      confidence: statistical_significance.confidence
    }
  end

  # Private Functions

  # Weighted Scoring Selection
  defp weighted_scoring_selection(strategies, error_context, constraints, options) do
    weights = Map.get(options, "weights", default_weights())
    
    scored_strategies = strategies
    |> Enum.map(fn {strategy_id, strategy} ->
      scores = calculate_strategy_scores(strategy, error_context, constraints)
      weighted_score = calculate_weighted_score(scores, weights)
      
      %{
        strategy_id: strategy_id,
        strategy: strategy,
        raw_scores: scores,
        weighted_score: weighted_score,
        confidence: calculate_selection_confidence(scores, strategy)
      }
    end)
    |> Enum.filter(fn scored_strategy ->
      scored_strategy.confidence >= Map.get(constraints, "confidence_threshold", 0.5)
    end)
    |> Enum.sort_by(& &1.weighted_score, :desc)
    
    top_recommendation = get_top_recommendation(scored_strategies)
    
    %{
      strategies: scored_strategies,
      recommendation: top_recommendation,
      selection_method: "weighted_scoring",
      weights_used: weights
    }
  end

  # Pareto Optimal Selection
  defp pareto_optimal_selection(strategies, error_context, constraints, _options) do
    # Evaluate strategies on multiple objectives
    evaluated_strategies = strategies
    |> Enum.map(fn {strategy_id, strategy} ->
      objectives = %{
        cost: -calculate_cost_objective(strategy, error_context),  # Negative for minimization
        effectiveness: calculate_effectiveness_objective(strategy, error_context),
        reliability: calculate_reliability_objective(strategy, error_context),
        speed: calculate_speed_objective(strategy, error_context)
      }
      
      %{
        strategy_id: strategy_id,
        strategy: strategy,
        objectives: objectives
      }
    end)
    
    # Find Pareto optimal solutions
    pareto_optimal = find_pareto_optimal(evaluated_strategies)
    
    # Select best from Pareto frontier
    best_pareto = select_from_pareto_frontier(pareto_optimal, constraints)
    
    %{
      strategies: evaluated_strategies,
      pareto_optimal: pareto_optimal,
      recommendation: best_pareto,
      selection_method: "pareto_optimal"
    }
  end

  # Machine Learning Selection
  defp ml_based_selection(strategies, error_context, constraints, options) do
    model_data = Map.get(options, "model_data", %{})
    
    # Extract features from error context
    features = extract_features(error_context, strategies)
    
    # Apply learned model if available
    predictions = if map_size(model_data) > 0 do
      apply_learned_model(features, model_data, strategies)
    else
      # Fallback to weighted scoring with learned weights
      learned_weights = extract_learned_weights(model_data)
      weighted_scoring_selection(strategies, error_context, constraints, %{"weights" => learned_weights})
    end
    
    %{
      strategies: predictions.strategies || [],
      recommendation: predictions.recommendation,
      selection_method: "machine_learning",
      features_used: features,
      model_confidence: Map.get(predictions, :model_confidence, 0.5)
    }
  end

  # A/B Testing Selection
  defp ab_testing_selection(strategies, error_context, constraints, options) do
    active_tests = Map.get(options, "active_tests", [])
    
    # Check if error context matches any active tests
    applicable_test = find_applicable_test(active_tests, error_context)
    
    if applicable_test do
      # Select strategy based on A/B test assignment
      assigned_strategy = assign_test_strategy(applicable_test, error_context)
      
      %{
        strategies: [assigned_strategy],
        recommendation: assigned_strategy,
        selection_method: "a_b_testing",
        test_info: applicable_test
      }
    else
      # Fall back to weighted scoring
      weighted_scoring_selection(strategies, error_context, constraints, options)
    end
  end

  # Strategy Scoring Functions
  defp calculate_strategy_scores(strategy, error_context, constraints) do
    %{
      effectiveness: calculate_effectiveness_score(strategy, error_context),
      cost_efficiency: calculate_cost_efficiency_score(strategy, error_context),
      reliability: calculate_reliability_score(strategy, error_context),
      speed: calculate_speed_score(strategy, error_context),
      risk: calculate_risk_score(strategy, error_context),
      user_experience: calculate_user_experience_score(strategy, error_context)
    }
  end

  defp calculate_effectiveness_score(strategy, error_context) do
    base_effectiveness = strategy.success_rate
    
    # Adjust for error category match
    category_match = if matches_error_category?(strategy, error_context) do
      1.2
    else
      0.8
    end
    
    # Adjust for complexity handling
    complexity_handling = get_complexity_handling_score(strategy, error_context)
    
    min(1.0, base_effectiveness * category_match * complexity_handling)
  end

  defp calculate_cost_efficiency_score(strategy, error_context) do
    base_cost = strategy.base_cost
    estimated_value = estimate_correction_value(error_context)
    
    if base_cost > 0 and estimated_value > 0 do
      # Higher score for better value-to-cost ratio
      min(1.0, estimated_value / base_cost / 10)  # Normalize to 0-1 range
    else
      0.5  # Default score
    end
  end

  defp calculate_reliability_score(strategy, error_context) do
    # Base reliability from success rate
    base_reliability = strategy.success_rate
    
    # Adjust for rollback capability
    rollback_bonus = if has_rollback_capability?(strategy) do
      0.1
    else
      0.0
    end
    
    # Adjust for testing coverage
    testing_bonus = if has_comprehensive_testing?(strategy) do
      0.1
    else
      0.0
    end
    
    min(1.0, base_reliability + rollback_bonus + testing_bonus)
  end

  defp calculate_speed_score(strategy, error_context) do
    execution_time = strategy.metadata["avg_execution_time"] || 2000
    
    # Normalize to 0-1 scale (faster = higher score)
    max_acceptable_time = 10000  # 10 seconds
    speed_score = max(0.0, (max_acceptable_time - execution_time) / max_acceptable_time)
    
    # Adjust for parallelization capability
    if supports_parallelization?(strategy) do
      min(1.0, speed_score * 1.2)
    else
      speed_score
    end
  end

  defp calculate_risk_score(strategy, error_context) do
    risk_level = strategy.metadata["risk_level"] || "medium"
    
    base_risk_score = case risk_level do
      "low" -> 0.9
      "medium" -> 0.7
      "high" -> 0.4
      "critical" -> 0.1
      _ -> 0.7
    end
    
    # Adjust for error criticality
    error_criticality = Map.get(error_context, "criticality", "medium")
    criticality_adjustment = case error_criticality do
      "low" -> 0.0
      "medium" -> -0.1
      "high" -> -0.2
      "critical" -> -0.3
      _ -> -0.1
    end
    
    max(0.0, min(1.0, base_risk_score + criticality_adjustment))
  end

  defp calculate_user_experience_score(strategy, error_context) do
    # Score based on user interaction requirements
    requires_interaction = requires_user_interaction?(strategy)
    user_available = Map.get(error_context, "user_available", false)
    
    base_ux_score = if requires_interaction do
      if user_available do
        0.6  # Interactive but user available
      else
        0.2  # Interactive but user not available
      end
    else
      0.9  # Fully automated
    end
    
    # Adjust for clarity of output
    output_clarity = strategy.metadata["output_clarity"] || "medium"
    clarity_bonus = case output_clarity do
      "high" -> 0.1
      "medium" -> 0.0
      "low" -> -0.1
      _ -> 0.0
    end
    
    max(0.0, min(1.0, base_ux_score + clarity_bonus))
  end

  defp calculate_weighted_score(scores, weights) do
    total_weight = Map.values(weights) |> Enum.sum()
    
    if total_weight > 0 do
      weighted_sum = scores
      |> Enum.map(fn {criterion, score} ->
        weight = Map.get(weights, criterion, 0.0)
        score * weight
      end)
      |> Enum.sum()
      
      weighted_sum / total_weight
    else
      0.0
    end
  end

  defp calculate_selection_confidence(scores, strategy) do
    # Base confidence from score consistency
    score_values = Map.values(scores)
    mean_score = Enum.sum(score_values) / length(score_values)
    
    variance = score_values
    |> Enum.map(fn score -> :math.pow(score - mean_score, 2) end)
    |> Enum.sum()
    |> Kernel./(length(score_values))
    
    consistency_confidence = max(0.0, 1.0 - variance)
    
    # Adjust for strategy maturity
    maturity_confidence = strategy.metadata["maturity"] || 0.7
    
    # Combined confidence
    (consistency_confidence + maturity_confidence) / 2
  end

  # Compatibility Checking
  defp check_prerequisites(strategy, error_context) do
    missing_prerequisites = strategy.prerequisites
    |> Enum.filter(fn prereq ->
      not prerequisite_satisfied?(prereq, error_context)
    end)
    
    %{
      passed: length(missing_prerequisites) == 0,
      missing: missing_prerequisites,
      details: "Prerequisites check"
    }
  end

  defp check_constraints(strategy, error_context, constraints) do
    violated_constraints = constraints
    |> Enum.filter(fn {constraint_type, constraint_value} ->
      not constraint_satisfied?(strategy, error_context, constraint_type, constraint_value)
    end)
    
    %{
      passed: length(violated_constraints) == 0,
      violations: violated_constraints,
      details: "Constraints check"
    }
  end

  defp check_capabilities(strategy, error_context) do
    required_capabilities = extract_required_capabilities(error_context)
    
    missing_capabilities = required_capabilities
    |> Enum.filter(fn capability ->
      not strategy_has_capability?(strategy, capability)
    end)
    
    %{
      passed: length(missing_capabilities) == 0,
      missing: missing_capabilities,
      details: "Capabilities check"
    }
  end

  defp check_resource_availability(strategy, constraints) do
    resource_requirements = extract_resource_requirements(strategy)
    available_resources = Map.get(constraints, "available_resources", %{})
    
    insufficient_resources = resource_requirements
    |> Enum.filter(fn {resource_type, required_amount} ->
      available_amount = Map.get(available_resources, resource_type, 0)
      required_amount > available_amount
    end)
    
    %{
      passed: length(insufficient_resources) == 0,
      insufficient: insufficient_resources,
      details: "Resource availability check"
    }
  end

  # A/B Testing Functions
  defp create_test_groups(strategies, test_config) do
    group_size = Map.get(test_config, "group_size", 0.5)
    
    strategies
    |> Enum.with_index()
    |> Enum.map(fn {{strategy_id, strategy}, index} ->
      group_id = "group_#{index}"
      
      {group_id, %{
        strategy_id: strategy_id,
        strategy: strategy,
        allocation: group_size,
        participants: [],
        outcomes: []
      }}
    end)
    |> Map.new()
  end

  defp find_applicable_test(active_tests, error_context) do
    active_tests
    |> Enum.find(fn test ->
      test_matches_context?(test, error_context)
    end)
  end

  defp assign_test_strategy(test, error_context) do
    # Simple hash-based assignment for consistency
    error_hash = :crypto.hash(:md5, inspect(error_context))
    |> Base.encode16()
    |> String.slice(0, 8)
    |> String.to_integer(16)
    
    group_count = map_size(test.groups)
    group_index = rem(error_hash, group_count)
    
    {_group_id, group_data} = test.groups |> Enum.at(group_index)
    
    %{
      strategy_id: group_data.strategy_id,
      strategy: group_data.strategy,
      test_assignment: %{
        test_id: test.test_id,
        group_id: "group_#{group_index}"
      }
    }
  end

  # Helper Functions
  defp default_weights do
    %{
      effectiveness: 0.25,
      cost_efficiency: 0.20,
      reliability: 0.20,
      speed: 0.15,
      risk: 0.15,
      user_experience: 0.05
    }
  end

  defp matches_error_category?(strategy, error_context) do
    error_category = Map.get(error_context, "category", "unknown")
    strategy_category = strategy.category
    
    String.contains?(error_category, strategy_category) or
    strategy_category == "general"
  end

  defp get_complexity_handling_score(strategy, error_context) do
    error_complexity = Map.get(error_context, "complexity", "medium")
    strategy_max_complexity = strategy.metadata["max_complexity"] || "high"
    
    complexity_levels = ["low", "medium", "high", "critical"]
    error_level = Enum.find_index(complexity_levels, &(&1 == error_complexity)) || 1
    strategy_level = Enum.find_index(complexity_levels, &(&1 == strategy_max_complexity)) || 2
    
    if strategy_level >= error_level do
      1.0
    else
      0.5  # Can't handle the complexity
    end
  end

  defp estimate_correction_value(error_context) do
    # Simple value estimation based on error impact
    severity = Map.get(error_context, "severity", 5)
    urgency = Map.get(error_context, "urgency", "medium")
    
    urgency_multiplier = case urgency do
      "critical" -> 3.0
      "high" -> 2.0
      "medium" -> 1.0
      "low" -> 0.5
      _ -> 1.0
    end
    
    severity * urgency_multiplier
  end

  defp has_rollback_capability?(strategy) do
    strategy.metadata["rollback_capability"] == true
  end

  defp has_comprehensive_testing?(strategy) do
    strategy.metadata["test_coverage"] == "comprehensive"
  end

  defp supports_parallelization?(strategy) do
    strategy.metadata["parallelizable"] == true
  end

  defp requires_user_interaction?(strategy) do
    strategy.prerequisites
    |> Enum.any?(fn prereq -> prereq == "user_available" end)
  end

  defp prerequisite_satisfied?(prereq, error_context) do
    case prereq do
      "user_available" -> Map.get(error_context, "user_available", false)
      "syntax_parser_available" -> true  # Assume available
      "test_suite_exists" -> Map.get(error_context, "has_tests", false)
      _ -> true  # Unknown prerequisites assumed satisfied
    end
  end

  defp constraint_satisfied?(strategy, error_context, constraint_type, constraint_value) do
    case constraint_type do
      "max_cost" ->
        strategy.base_cost <= constraint_value
      
      "max_time" ->
        execution_time = strategy.metadata["avg_execution_time"] || 2000
        execution_time <= constraint_value
      
      "min_confidence" ->
        strategy.success_rate >= constraint_value
      
      _ ->
        true  # Unknown constraints assumed satisfied
    end
  end

  defp extract_required_capabilities(error_context) do
    error_type = Map.get(error_context, "error_type", "unknown")
    language = Map.get(error_context, "language", "unknown")
    
    capabilities = []
    
    capabilities = if error_type == "syntax_error" do
      ["syntax_parsing" | capabilities]
    else
      capabilities
    end
    
    capabilities = if language != "unknown" do
      ["#{language}_support" | capabilities]
    else
      capabilities
    end
    
    capabilities
  end

  defp strategy_has_capability?(strategy, capability) do
    supported_capabilities = strategy.metadata["capabilities"] || []
    capability in supported_capabilities
  end

  defp extract_resource_requirements(strategy) do
    %{
      "cpu" => strategy.metadata["cpu_requirements"] || 1.0,
      "memory" => strategy.metadata["memory_requirements"] || 1.0,
      "time" => strategy.metadata["avg_execution_time"] || 2000
    }
  end

  defp calculate_compatibility_score(checks) do
    passed_checks = checks
    |> Map.values()
    |> Enum.count(& &1.passed)
    
    total_checks = map_size(checks)
    
    if total_checks > 0 do
      passed_checks / total_checks
    else
      0.0
    end
  end

  defp get_top_recommendation(scored_strategies) do
    case scored_strategies do
      [top | _] ->
        %{
          strategy_id: top.strategy_id,
          strategy: top.strategy,
          score: top.weighted_score,
          confidence: top.confidence,
          reasoning: "Highest weighted score among compatible strategies"
        }
      
      [] ->
        %{
          strategy_id: nil,
          strategy: nil,
          score: 0.0,
          confidence: 0.0,
          reasoning: "No compatible strategies found"
        }
    end
  end

  # Pareto Optimization
  defp find_pareto_optimal(strategies) do
    strategies
    |> Enum.filter(fn candidate ->
      not dominated_by_any?(candidate, strategies)
    end)
  end

  defp dominated_by_any?(candidate, strategies) do
    strategies
    |> Enum.any?(fn other ->
      candidate.strategy_id != other.strategy_id and dominates?(other, candidate)
    end)
  end

  defp dominates?(strategy_a, strategy_b) do
    objectives_a = Map.values(strategy_a.objectives)
    objectives_b = Map.values(strategy_b.objectives)
    
    # A dominates B if A is better or equal in all objectives and strictly better in at least one
    better_or_equal = Enum.zip(objectives_a, objectives_b)
    |> Enum.all?(fn {a, b} -> a >= b end)
    
    strictly_better = Enum.zip(objectives_a, objectives_b)
    |> Enum.any?(fn {a, b} -> a > b end)
    
    better_or_equal and strictly_better
  end

  defp select_from_pareto_frontier(pareto_optimal, constraints) do
    # Select based on user preferences or default criteria
    preference_weights = Map.get(constraints, "preference_weights", %{
      "cost" => -0.3,  # Minimize cost
      "effectiveness" => 0.3,
      "reliability" => 0.25,
      "speed" => 0.15
    })
    
    pareto_optimal
    |> Enum.map(fn strategy ->
      preference_score = strategy.objectives
      |> Enum.map(fn {objective, value} ->
        weight = Map.get(preference_weights, Atom.to_string(objective), 0.0)
        value * weight
      end)
      |> Enum.sum()
      
      Map.put(strategy, :preference_score, preference_score)
    end)
    |> Enum.max_by(& &1.preference_score, fn -> nil end)
  end

  # ML Helper Functions
  defp extract_features(error_context, strategies) do
    %{
      error_type: Map.get(error_context, "error_type", "unknown"),
      complexity: complexity_to_numeric(Map.get(error_context, "complexity", "medium")),
      severity: Map.get(error_context, "severity", 5),
      file_size: Map.get(error_context, "file_size", 500),
      available_strategies: map_size(strategies),
      user_available: if(Map.get(error_context, "user_available", false), do: 1, else: 0)
    }
  end

  defp complexity_to_numeric(complexity) do
    case complexity do
      "low" -> 1
      "medium" -> 2
      "high" -> 3
      "critical" -> 4
      _ -> 2
    end
  end

  defp apply_learned_model(features, model_data, strategies) do
    # Simple linear model application (placeholder for more sophisticated ML)
    weights = Map.get(model_data, "feature_weights", %{})
    
    model_score = features
    |> Enum.map(fn {feature, value} ->
      weight = Map.get(weights, Atom.to_string(feature), 0.0)
      value * weight
    end)
    |> Enum.sum()
    
    # Select strategy based on model prediction
    best_strategy = strategies
    |> Enum.max_by(fn {_id, strategy} -> strategy.success_rate * model_score end, fn -> nil end)
    
    if best_strategy do
      {strategy_id, strategy} = best_strategy
      
      %{
        strategies: [%{strategy_id: strategy_id, strategy: strategy, model_score: model_score}],
        recommendation: %{strategy_id: strategy_id, strategy: strategy},
        model_confidence: min(1.0, abs(model_score) / 10)
      }
    else
      %{strategies: [], recommendation: nil, model_confidence: 0.0}
    end
  end

  defp extract_learned_weights(model_data) do
    Map.get(model_data, "learned_weights", default_weights())
  end

  # A/B Testing Helper Functions
  defp test_matches_context?(test, error_context) do
    test_criteria = test.config["criteria"] || %{}
    
    test_criteria
    |> Enum.all?(fn {criterion, expected_value} ->
      actual_value = Map.get(error_context, criterion)
      actual_value == expected_value
    end)
  end

  defp analyze_group_performance(group_data) do
    outcomes = group_data.outcomes
    
    if length(outcomes) > 0 do
      success_rate = Enum.count(outcomes, & &1["success"]) / length(outcomes)
      avg_cost = Enum.sum(Enum.map(outcomes, & &1["cost"])) / length(outcomes)
      avg_time = Enum.sum(Enum.map(outcomes, & &1["execution_time"])) / length(outcomes)
      
      %{
        participants: length(outcomes),
        success_rate: success_rate,
        avg_cost: avg_cost,
        avg_execution_time: avg_time,
        confidence_interval: calculate_confidence_interval(outcomes, "success")
      }
    else
      %{
        participants: 0,
        success_rate: 0.0,
        avg_cost: 0.0,
        avg_execution_time: 0.0,
        confidence_interval: {0.0, 0.0}
      }
    end
  end

  defp determine_winning_strategy(group_results) do
    group_results
    |> Enum.max_by(fn {_group_id, results} -> results.success_rate end, fn -> nil end)
  end

  defp calculate_statistical_significance(group_results) do
    if map_size(group_results) >= 2 do
      # Simple statistical significance calculation
      results_list = Map.values(group_results)
      
      # Use chi-square test for success rate comparison
      chi_square = calculate_chi_square(results_list)
      p_value = chi_square_to_p_value(chi_square, map_size(group_results) - 1)
      
      %{
        chi_square: chi_square,
        p_value: p_value,
        significant: p_value < 0.05,
        confidence: 1.0 - p_value
      }
    else
      %{
        chi_square: 0.0,
        p_value: 1.0,
        significant: false,
        confidence: 0.0
      }
    end
  end

  defp generate_ab_recommendations(group_results, winner) do
    recommendations = []
    
    recommendations = if winner do
      [%{
        type: :strategy_adoption,
        description: "Adopt winning strategy based on A/B test results",
        strategy_group: elem(winner, 0),
        confidence: "high"
      } | recommendations]
    else
      recommendations
    end
    
    # Check for inconclusive results
    success_rates = group_results
    |> Map.values()
    |> Enum.map(& &1.success_rate)
    
    rate_variance = calculate_variance(success_rates)
    
    recommendations = if rate_variance < 0.01 do
      [%{
        type: :extend_test,
        description: "Results are too close - extend test duration",
        confidence: "medium"
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp calculate_confidence_interval(outcomes, metric) do
    if length(outcomes) > 1 do
      values = Enum.map(outcomes, & &1[metric])
      mean = Enum.sum(values) / length(values)
      
      variance = values
      |> Enum.map(fn value -> :math.pow(value - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values) - 1)
      
      std_error = :math.sqrt(variance / length(values))
      margin_of_error = 1.96 * std_error  # 95% confidence interval
      
      {mean - margin_of_error, mean + margin_of_error}
    else
      {0.0, 0.0}
    end
  end

  defp calculate_chi_square(results_list) do
    # Simplified chi-square calculation
    total_participants = Enum.sum(Enum.map(results_list, & &1.participants))
    
    if total_participants > 0 do
      expected_success_rate = results_list
      |> Enum.map(fn result -> result.success_rate * result.participants end)
      |> Enum.sum()
      |> Kernel./(total_participants)
      
      results_list
      |> Enum.map(fn result ->
        expected_successes = expected_success_rate * result.participants
        actual_successes = result.success_rate * result.participants
        
        if expected_successes > 0 do
          :math.pow(actual_successes - expected_successes, 2) / expected_successes
        else
          0.0
        end
      end)
      |> Enum.sum()
    else
      0.0
    end
  end

  defp chi_square_to_p_value(chi_square, degrees_of_freedom) do
    # Simplified p-value calculation (would use proper statistical library in production)
    cond do
      chi_square > 6.635 -> 0.01  # p < 0.01
      chi_square > 3.841 -> 0.05  # p < 0.05
      chi_square > 2.706 -> 0.10  # p < 0.10
      true -> 0.50  # p >= 0.50
    end
  end

  defp calculate_variance(values) do
    if length(values) > 1 do
      mean = Enum.sum(values) / length(values)
      
      values
      |> Enum.map(fn value -> :math.pow(value - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))
    else
      0.0
    end
  end

  defp generate_test_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end

  # Objective Calculation Functions
  defp calculate_cost_objective(strategy, error_context) do
    # Simple cost calculation for Pareto analysis
    base_cost = strategy.base_cost
    complexity_multiplier = complexity_to_numeric(Map.get(error_context, "complexity", "medium"))
    
    base_cost * complexity_multiplier
  end

  defp calculate_effectiveness_objective(strategy, error_context) do
    calculate_effectiveness_score(strategy, error_context)
  end

  defp calculate_reliability_objective(strategy, error_context) do
    calculate_reliability_score(strategy, error_context)
  end

  defp calculate_speed_objective(strategy, error_context) do
    calculate_speed_score(strategy, error_context)
  end
end