defmodule RubberDuck.Planning.Repository.ChangeImpactAnalyzer do
  @moduledoc """
  Analyzes the impact of proposed changes across the repository.
  
  This module provides sophisticated analysis of how changes to specific files
  will affect the rest of the codebase, including dependency impact, test
  requirements, risk assessment, and change propagation simulation.
  """

  alias RubberDuck.Planning.Repository.{RepositoryAnalyzer, DependencyGraph}
  
  require Logger

  @type impact_analysis :: %{
    changed_files: [String.t()],
    directly_affected: [String.t()],
    transitively_affected: [String.t()],
    test_files_needed: [String.t()],
    risk_assessment: risk_assessment(),
    change_propagation: [propagation_step()],
    compilation_order: [String.t()],
    parallel_groups: [[String.t()]],
    estimated_effort: effort_estimate()
  }

  @type risk_assessment :: %{
    overall_risk: risk_level(),
    factors: [risk_factor()],
    confidence: float(),
    recommendations: [String.t()]
  }

  @type risk_level :: :low | :medium | :high | :critical
  
  @type risk_factor :: %{
    type: risk_factor_type(),
    severity: risk_level(),
    description: String.t(),
    affected_files: [String.t()],
    mitigation: String.t()
  }

  @type risk_factor_type :: 
    :high_complexity_files | :many_dependents | :core_modules | 
    :test_coverage_gaps | :architectural_changes | :breaking_changes

  @type propagation_step :: %{
    step: non_neg_integer(),
    files: [String.t()],
    reason: String.t(),
    impact_type: :compilation | :runtime | :test
  }

  @type effort_estimate :: %{
    total_files: non_neg_integer(),
    complexity_score: float(),
    estimated_hours: float(),
    confidence: float()
  }

  @doc """
  Analyzes the impact of changing the specified files.
  """
  @spec analyze_impact(RepositoryAnalyzer.analysis_result(), [String.t()], keyword()) :: 
    {:ok, impact_analysis()} | {:error, term()}
  def analyze_impact(repo_analysis, changed_files, opts \\ []) do
    Logger.info("Analyzing impact of changes to #{length(changed_files)} files")
    
    with {:ok, affected_files} <- get_affected_files(repo_analysis, changed_files),
         {:ok, test_files} <- determine_test_requirements(repo_analysis, changed_files ++ affected_files),
         {:ok, compilation_order} <- determine_compilation_order(repo_analysis, changed_files ++ affected_files),
         {:ok, parallel_groups} <- identify_parallel_groups(repo_analysis, changed_files ++ affected_files),
         {:ok, risk_assessment} <- assess_change_risk(repo_analysis, changed_files, affected_files, opts),
         {:ok, propagation} <- simulate_change_propagation(repo_analysis, changed_files),
         {:ok, effort} <- estimate_effort(repo_analysis, changed_files, affected_files) do
      
      impact = %{
        changed_files: changed_files,
        directly_affected: affected_files.direct,
        transitively_affected: affected_files.transitive,
        test_files_needed: test_files,
        risk_assessment: risk_assessment,
        change_propagation: propagation,
        compilation_order: compilation_order,
        parallel_groups: parallel_groups,
        estimated_effort: effort
      }
      
      Logger.info("Impact analysis complete: #{length(affected_files.direct)} direct, " <>
                  "#{length(affected_files.transitive)} transitive files affected")
      {:ok, impact}
    else
      error ->
        Logger.error("Impact analysis failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Analyzes the risk of a breaking change across the repository.
  """
  @spec analyze_breaking_change(RepositoryAnalyzer.analysis_result(), String.t(), [String.t()]) ::
    {:ok, impact_analysis()} | {:error, term()}
  def analyze_breaking_change(repo_analysis, changed_module, affected_functions) do
    Logger.info("Analyzing breaking change impact for module #{changed_module}")
    
    # Find all files that use the affected functions
    affected_files = find_function_usage(repo_analysis, changed_module, affected_functions)
    
    analyze_impact(repo_analysis, affected_files, breaking_change: true)
  end

  @doc """
  Suggests mitigation strategies for high-risk changes.
  """
  @spec suggest_mitigations(impact_analysis()) :: [mitigation_strategy()]
  def suggest_mitigations(%{risk_assessment: risk} = _impact) do
    risk.factors
    |> Enum.flat_map(&generate_mitigation_strategies/1)
    |> Enum.uniq_by(& &1.type)
  end

  @type mitigation_strategy :: %{
    type: mitigation_type(),
    description: String.t(),
    effort: effort_level(),
    effectiveness: float()
  }

  @type mitigation_type :: 
    :incremental_rollout | :feature_flags | :backward_compatibility | 
    :extensive_testing | :staged_deployment | :documentation_update

  @type effort_level :: :low | :medium | :high

  # Private functions

  defp get_affected_files(repo_analysis, changed_files) do
    direct = DependencyGraph.get_dependent_files(repo_analysis.dependencies, changed_files)
    transitive = DependencyGraph.get_dependent_files(repo_analysis.dependencies, direct)
    
    {:ok, %{
      direct: direct,
      transitive: transitive -- direct  # Remove direct dependencies from transitive
    }}
  end

  defp determine_test_requirements(repo_analysis, all_affected_files) do
    test_files = RepositoryAnalyzer.find_associated_tests(repo_analysis, all_affected_files)
    
    # Add integration tests that might be affected
    integration_tests = find_integration_tests(repo_analysis, all_affected_files)
    
    {:ok, Enum.uniq(test_files ++ integration_tests)}
  end

  defp determine_compilation_order(repo_analysis, files) do
    case RepositoryAnalyzer.get_compilation_order(repo_analysis) do
      {:ok, full_order} ->
        # Filter to only include affected files, maintaining order
        filtered_order = Enum.filter(full_order, &(&1 in files))
        {:ok, filtered_order}
      
      error ->
        error
    end
  end

  defp identify_parallel_groups(repo_analysis, files) do
    # Group files that have no dependencies between them
    file_set = MapSet.new(files)
    
    groups = files
    |> Enum.group_by(fn file ->
      deps = DependencyGraph.get_direct_dependencies(repo_analysis.dependencies, file)
      deps_in_set = Enum.filter(deps, &MapSet.member?(file_set, &1))
      length(deps_in_set)  # Group by dependency count within the set
    end)
    |> Map.values()
    |> Enum.filter(&(length(&1) > 1))  # Only return groups with multiple files
    
    {:ok, groups}
  end

  defp assess_change_risk(repo_analysis, changed_files, affected_files, opts) do
    is_breaking = Keyword.get(opts, :breaking_change, false)
    
    factors = []
    
    # Analyze complexity of changed files
    factors = factors ++ assess_complexity_risk(repo_analysis, changed_files)
    
    # Analyze dependency impact
    factors = factors ++ assess_dependency_risk(repo_analysis, affected_files)
    
    # Analyze architectural impact
    factors = factors ++ assess_architectural_risk(repo_analysis, changed_files)
    
    # Analyze test coverage
    factors = factors ++ assess_test_coverage_risk(repo_analysis, changed_files ++ affected_files.direct)
    
    # Add breaking change risk if applicable
    factors = if is_breaking do
      factors ++ [%{
        type: :breaking_changes,
        severity: :high,
        description: "This change includes breaking API modifications",
        affected_files: affected_files.direct ++ affected_files.transitive,
        mitigation: "Implement backward compatibility or staged rollout"
      }]
    else
      factors
    end
    
    overall_risk = calculate_overall_risk(factors)
    confidence = calculate_risk_confidence(factors, repo_analysis)
    recommendations = generate_risk_recommendations(factors, overall_risk)
    
    {:ok, %{
      overall_risk: overall_risk,
      factors: factors,
      confidence: confidence,
      recommendations: recommendations
    }}
  end

  defp simulate_change_propagation(repo_analysis, changed_files) do
    steps = []
    
    # Step 1: Direct compilation dependencies
    step1_files = DependencyGraph.get_dependent_files(repo_analysis.dependencies, changed_files)
    steps = steps ++ [%{
      step: 1,
      files: step1_files,
      reason: "Direct compilation dependencies",
      impact_type: :compilation
    }]
    
    # Step 2: Transitive dependencies
    step2_files = DependencyGraph.get_dependent_files(repo_analysis.dependencies, step1_files)
    |> Enum.reject(&(&1 in step1_files))
    
    steps = if length(step2_files) > 0 do
      steps ++ [%{
        step: 2,
        files: step2_files,
        reason: "Transitive compilation dependencies",
        impact_type: :compilation
      }]
    else
      steps
    end
    
    # Step 3: Test dependencies
    all_affected = changed_files ++ step1_files ++ step2_files
    test_files = RepositoryAnalyzer.find_associated_tests(repo_analysis, all_affected)
    
    steps = if length(test_files) > 0 do
      steps ++ [%{
        step: length(steps) + 1,
        files: test_files,
        reason: "Test files for changed modules",
        impact_type: :test
      }]
    else
      steps
    end
    
    {:ok, steps}
  end

  defp estimate_effort(repo_analysis, changed_files, affected_files) do
    all_files = changed_files ++ affected_files.direct ++ affected_files.transitive
    total_files = length(all_files)
    
    # Calculate complexity score based on file types and sizes
    complexity_score = if total_files > 0 do
      all_files
      |> Enum.map(fn file ->
        file_info = Enum.find(repo_analysis.files, &(&1.path == file))
        case file_info do
          nil -> 1.0  # Default complexity
          info -> complexity_to_score(info.complexity)
        end
      end)
      |> Enum.sum()
    else
      0.0
    end
    
    # Estimate hours based on complexity and file count
    base_hours_per_file = 0.5
    complexity_multiplier = if total_files > 0, do: complexity_score / total_files, else: 1.0
    estimated_hours = total_files * base_hours_per_file * complexity_multiplier
    
    # Calculate confidence based on available information
    confidence = calculate_effort_confidence(repo_analysis, all_files)
    
    {:ok, %{
      total_files: total_files,
      complexity_score: complexity_score,
      estimated_hours: Float.round(estimated_hours, 1),
      confidence: confidence
    }}
  end

  defp find_function_usage(repo_analysis, module_name, _function_names) do
    # This is a simplified implementation
    # In a full implementation, we'd parse AST to find actual function calls
    repo_analysis.files
    |> Enum.filter(fn file ->
      Enum.any?(file.modules, fn mod ->
        module_name in (mod.imports ++ mod.aliases ++ mod.uses)
      end)
    end)
    |> Enum.map(& &1.path)
  end

  defp find_integration_tests(repo_analysis, _files) do
    # Find test files that might test integration between modules
    repo_analysis.files
    |> Enum.filter(&(&1.type == :test))
    |> Enum.filter(fn file ->
      String.contains?(file.path, "integration") or
      String.contains?(file.path, "feature") or
      String.contains?(file.path, "e2e")
    end)
    |> Enum.map(& &1.path)
  end

  defp assess_complexity_risk(repo_analysis, files) do
    complex_files = repo_analysis.files
    |> Enum.filter(&(&1.path in files and &1.complexity in [:complex, :very_complex]))
    
    case complex_files do
      [] -> []
      files ->
        [%{
          type: :high_complexity_files,
          severity: :medium,
          description: "Changes involve high complexity files",
          affected_files: Enum.map(files, & &1.path),
          mitigation: "Increase testing and code review rigor"
        }]
    end
  end

  defp assess_dependency_risk(_repo_analysis, affected_files) do
    total_affected = length(affected_files.direct) + length(affected_files.transitive)
    
    cond do
      total_affected > 50 ->
        [%{
          type: :many_dependents,
          severity: :critical,
          description: "Changes affect #{total_affected} files across the repository",
          affected_files: affected_files.direct ++ affected_files.transitive,
          mitigation: "Consider breaking into smaller, incremental changes"
        }]
      
      total_affected > 20 ->
        [%{
          type: :many_dependents,
          severity: :high,
          description: "Changes affect #{total_affected} files",
          affected_files: affected_files.direct ++ affected_files.transitive,
          mitigation: "Thorough testing and staged rollout recommended"
        }]
      
      total_affected > 5 ->
        [%{
          type: :many_dependents,
          severity: :medium,
          description: "Changes affect #{total_affected} files",
          affected_files: affected_files.direct ++ affected_files.transitive,
          mitigation: "Ensure comprehensive test coverage"
        }]
      
      true ->
        []
    end
  end

  defp assess_architectural_risk(repo_analysis, files) do
    # Check if changes affect core architectural components
    core_patterns = [:phoenix_context, :otp_application]
    
    affected_patterns = repo_analysis.patterns
    |> Enum.filter(fn pattern ->
      pattern.type in core_patterns and
      Enum.any?(pattern.files, &(&1 in files))
    end)
    
    case affected_patterns do
      [] -> []
      patterns ->
        [%{
          type: :architectural_changes,
          severity: :high,
          description: "Changes affect core architectural components: #{Enum.map(patterns, & &1.name) |> Enum.join(", ")}",
          affected_files: files,
          mitigation: "Review architectural impact and update documentation"
        }]
    end
  end

  defp assess_test_coverage_risk(repo_analysis, files) do
    test_files = RepositoryAnalyzer.find_associated_tests(repo_analysis, files)
    coverage_ratio = if length(files) > 0, do: length(test_files) / length(files), else: 1.0
    
    cond do
      coverage_ratio < 0.3 ->
        [%{
          type: :test_coverage_gaps,
          severity: :high,
          description: "Low test coverage for affected files (#{Float.round(coverage_ratio * 100, 1)}%)",
          affected_files: files,
          mitigation: "Add comprehensive tests before implementing changes"
        }]
      
      coverage_ratio < 0.6 ->
        [%{
          type: :test_coverage_gaps,
          severity: :medium,
          description: "Moderate test coverage for affected files (#{Float.round(coverage_ratio * 100, 1)}%)",
          affected_files: files,
          mitigation: "Consider adding additional test coverage"
        }]
      
      true ->
        []
    end
  end

  defp calculate_overall_risk(factors) do
    case factors do
      [] -> :low
      factors ->
        max_severity = factors
        |> Enum.map(& &1.severity)
        |> Enum.max()
        
        critical_count = Enum.count(factors, &(&1.severity == :critical))
        high_count = Enum.count(factors, &(&1.severity == :high))
        
        cond do
          critical_count > 0 -> :critical
          max_severity == :high and high_count >= 2 -> :critical
          max_severity == :high -> :high
          Enum.count(factors, &(&1.severity == :medium)) >= 3 -> :high
          true -> :medium
        end
    end
  end

  defp calculate_risk_confidence(factors, repo_analysis) do
    base_confidence = 0.7
    
    # Increase confidence based on available analysis
    structure_bonus = if repo_analysis.structure.type != :plain_elixir, do: 0.1, else: 0.0
    pattern_bonus = min(length(repo_analysis.patterns) * 0.05, 0.15)
    
    # Decrease confidence if we have many unknown factors
    unknown_penalty = length(factors) * 0.02
    
    (base_confidence + structure_bonus + pattern_bonus - unknown_penalty)
    |> max(0.1)
    |> min(1.0)
  end

  defp generate_risk_recommendations(factors, overall_risk) do
    base_recommendations = case overall_risk do
      :critical -> [
        "Consider breaking changes into smaller increments",
        "Implement comprehensive rollback plan",
        "Use feature flags for controlled rollout"
      ]
      :high -> [
        "Increase test coverage before implementation",
        "Plan staged deployment strategy",
        "Conduct thorough code review"
      ]
      :medium -> [
        "Ensure adequate test coverage",
        "Monitor deployment closely"
      ]
      :low -> [
        "Standard testing and review process sufficient"
      ]
    end
    
    factor_recommendations = factors
    |> Enum.flat_map(fn factor ->
      case factor.type do
        :breaking_changes -> ["Implement backward compatibility layer"]
        :high_complexity_files -> ["Add extra review time for complex files"]
        :test_coverage_gaps -> ["Prioritize test creation for uncovered files"]
        _ -> []
      end
    end)
    
    Enum.uniq(base_recommendations ++ factor_recommendations)
  end

  defp complexity_to_score(complexity) do
    case complexity do
      :simple -> 1.0
      :medium -> 2.0
      :complex -> 4.0
      :very_complex -> 8.0
    end
  end

  defp calculate_effort_confidence(repo_analysis, files) do
    # Higher confidence if we have detailed analysis for all files
    analyzed_files = Enum.count(files, fn file ->
      Enum.any?(repo_analysis.files, &(&1.path == file))
    end)
    
    coverage = analyzed_files / length(files)
    
    # Base confidence, adjusted by coverage and repository structure knowledge
    base = 0.6
    coverage_bonus = coverage * 0.3
    structure_bonus = if repo_analysis.structure.type != :plain_elixir, do: 0.1, else: 0.0
    
    (base + coverage_bonus + structure_bonus) |> min(0.95)
  end

  defp generate_mitigation_strategies(factor) do
    case factor.type do
      :high_complexity_files ->
        [%{
          type: :extensive_testing,
          description: "Add comprehensive unit and integration tests for complex files",
          effort: :high,
          effectiveness: 0.8
        }]
      
      :many_dependents ->
        [%{
          type: :staged_deployment,
          description: "Deploy changes in stages to minimize blast radius",
          effort: :medium,
          effectiveness: 0.7
        }]
      
      :breaking_changes ->
        [%{
          type: :backward_compatibility,
          description: "Implement backward compatibility layer during transition",
          effort: :high,
          effectiveness: 0.9
        }]
      
      :test_coverage_gaps ->
        [%{
          type: :extensive_testing,
          description: "Create comprehensive test suite before implementing changes",
          effort: :medium,
          effectiveness: 0.85
        }]
      
      _ ->
        []
    end
  end
end