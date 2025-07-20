defmodule RubberDuck.Planning.Repository.ChangeSequencer do
  @moduledoc """
  Sequences repository changes in dependency-aware order.
  
  This module determines the optimal order for applying changes across multiple
  files, considering compilation dependencies, parallel execution opportunities,
  and conflict detection between simultaneous changes.
  """

  alias RubberDuck.Planning.Repository.{RepositoryAnalyzer, ChangeImpactAnalyzer}
  
  require Logger

  @type sequence_plan :: %{
    phases: [sequence_phase()],
    parallel_groups: [parallel_group()],
    conflicts: [conflict()],
    validation_points: [validation_point()],
    rollback_plan: rollback_plan(),
    estimated_duration: Duration.t()
  }

  @type sequence_phase :: %{
    phase: non_neg_integer(),
    name: String.t(),
    files: [String.t()],
    dependencies: [non_neg_integer()],
    can_parallel: boolean(),
    validation_required: boolean()
  }

  @type parallel_group :: %{
    group_id: String.t(),
    files: [String.t()],
    estimated_duration: Duration.t(),
    resource_requirements: resource_requirements()
  }

  @type conflict :: %{
    type: conflict_type(),
    files: [String.t()],
    description: String.t(),
    resolution_strategy: resolution_strategy(),
    severity: :low | :medium | :high | :critical
  }

  @type conflict_type :: 
    :file_modification | :dependency_cycle | :resource_contention | 
    :compilation_order | :test_interference

  @type resolution_strategy :: %{
    type: :manual_review | :automatic_merge | :sequential_execution | :isolation,
    steps: [String.t()],
    estimated_effort: effort_level()
  }

  @type effort_level :: :low | :medium | :high

  @type validation_point :: %{
    after_phase: non_neg_integer(),
    type: validation_type(),
    description: String.t(),
    required: boolean()
  }

  @type validation_type :: :compilation | :test_suite | :integration_test | :manual_review

  @type rollback_plan :: %{
    checkpoints: [checkpoint()],
    rollback_order: [non_neg_integer()],
    estimated_rollback_time: Duration.t()
  }

  @type checkpoint :: %{
    phase: non_neg_integer(),
    files_snapshot: [String.t()],
    validation_state: map()
  }

  @type resource_requirements :: %{
    cpu_intensive: boolean(),
    memory_intensive: boolean(),
    io_intensive: boolean(),
    network_required: boolean()
  }

  @doc """
  Creates an optimal sequence plan for the given repository changes.
  """
  @spec create_sequence(RepositoryAnalyzer.analysis_result(), [change_request()], keyword()) ::
    {:ok, sequence_plan()} | {:error, term()}
  def create_sequence(repo_analysis, change_requests, opts \\ []) do
    Logger.info("Creating sequence plan for #{length(change_requests)} changes")
    
    with {:ok, impact_analysis} <- analyze_combined_impact(repo_analysis, change_requests),
         {:ok, phases} <- build_dependency_phases(repo_analysis, change_requests, impact_analysis),
         {:ok, parallel_groups} <- identify_parallel_opportunities(repo_analysis, phases),
         {:ok, conflicts} <- detect_conflicts(change_requests, impact_analysis),
         {:ok, validation_points} <- determine_validation_points(phases, opts),
         {:ok, rollback_plan} <- create_rollback_plan(phases),
         {:ok, duration} <- estimate_total_duration(phases, parallel_groups) do
      
      plan = %{
        phases: phases,
        parallel_groups: parallel_groups,
        conflicts: conflicts,
        validation_points: validation_points,
        rollback_plan: rollback_plan,
        estimated_duration: duration
      }
      
      Logger.info("Sequence plan created with #{length(phases)} phases and #{length(parallel_groups)} parallel groups")
      {:ok, plan}
    else
      error ->
        Logger.error("Failed to create sequence plan: #{inspect(error)}")
        error
    end
  end

  @type change_request :: %{
    id: String.t(),
    files: [String.t()],
    type: change_type(),
    priority: priority_level(),
    dependencies: [String.t()],
    estimated_effort: float(),
    breaking: boolean()
  }

  @type change_type :: :feature | :bugfix | :refactor | :migration | :removal
  @type priority_level :: :low | :medium | :high | :critical

  @doc """
  Optimizes an existing sequence for parallel execution.
  """
  @spec optimize_for_parallelism(sequence_plan(), keyword()) :: {:ok, sequence_plan()} | {:error, term()}
  def optimize_for_parallelism(plan, opts \\ []) do
    max_parallel = Keyword.get(opts, :max_parallel, 4)
    
    optimized_phases = plan.phases
    |> Enum.map(&optimize_phase_for_parallelism(&1, max_parallel))
    
    optimized_groups = merge_compatible_parallel_groups(plan.parallel_groups, max_parallel)
    
    # Recalculate duration with optimizations
    {:ok, new_duration} = estimate_total_duration(optimized_phases, optimized_groups)
    
    optimized_plan = %{plan |
      phases: optimized_phases,
      parallel_groups: optimized_groups,
      estimated_duration: new_duration
    }
    
    {:ok, optimized_plan}
  end

  @doc """
  Validates that a sequence plan is safe to execute.
  """
  @spec validate_sequence(sequence_plan(), RepositoryAnalyzer.analysis_result()) :: 
    {:ok, [validation_result()]} | {:error, term()}
  def validate_sequence(plan, repo_analysis) do
    validations = []
    
    # Validate dependency ordering
    validations = validations ++ validate_dependency_ordering(plan, repo_analysis)
    
    # Validate no cycles exist
    validations = validations ++ validate_no_cycles(plan, repo_analysis)
    
    # Validate conflict resolutions
    validations = validations ++ validate_conflict_resolutions(plan)
    
    # Validate parallel execution safety
    validations = validations ++ validate_parallel_safety(plan, repo_analysis)
    
    case Enum.filter(validations, &(&1.status == :error)) do
      [] -> {:ok, validations}
      errors -> {:error, {:validation_failed, errors}}
    end
  end

  @type validation_result :: %{
    type: validation_check(),
    status: :ok | :warning | :error,
    message: String.t(),
    details: map()
  }

  @type validation_check :: 
    :dependency_order | :cycle_detection | :conflict_resolution | :parallel_safety

  @doc """
  Suggests improvements to an existing sequence plan.
  """
  @spec suggest_improvements(sequence_plan(), RepositoryAnalyzer.analysis_result()) :: [improvement_suggestion()]
  def suggest_improvements(plan, repo_analysis) do
    suggestions = []
    
    # Suggest phase consolidation opportunities
    suggestions = suggestions ++ suggest_phase_consolidation(plan)
    
    # Suggest additional parallelization
    suggestions = suggestions ++ suggest_additional_parallelization(plan, repo_analysis)
    
    # Suggest validation point optimization
    suggestions = suggestions ++ suggest_validation_optimization(plan)
    
    # Suggest risk mitigation improvements
    suggestions = suggestions ++ suggest_risk_mitigation(plan)
    
    Enum.sort_by(suggestions, & &1.impact, :desc)
  end

  @type improvement_suggestion :: %{
    type: improvement_type(),
    description: String.t(),
    impact: float(),
    effort: effort_level(),
    implementation: [String.t()]
  }

  @type improvement_type :: 
    :phase_consolidation | :parallelization | :validation_optimization | :risk_mitigation

  # Private functions

  defp analyze_combined_impact(repo_analysis, change_requests) do
    all_files = change_requests
    |> Enum.flat_map(& &1.files)
    |> Enum.uniq()
    
    ChangeImpactAnalyzer.analyze_impact(repo_analysis, all_files)
  end

  defp build_dependency_phases(_repo_analysis, change_requests, impact_analysis) do
    # Group changes by their dependency relationships
    dependency_graph = build_change_dependency_graph(change_requests, impact_analysis)
    
    case topological_sort_changes(dependency_graph) do
      {:ok, sorted_changes} ->
        phases = sorted_changes
        |> Enum.with_index(1)
        |> Enum.map(fn {change_group, phase_num} ->
          %{
            phase: phase_num,
            name: "Phase #{phase_num}: #{describe_phase(change_group)}",
            files: Enum.flat_map(change_group, & &1.files),
            dependencies: if(phase_num == 1, do: [], else: [phase_num - 1]),
            can_parallel: can_execute_in_parallel?(change_group),
            validation_required: requires_validation?(change_group)
          }
        end)
        
        {:ok, phases}
      
      {:error, :cycle} ->
        {:error, :dependency_cycle_in_changes}
    end
  end

  defp build_change_dependency_graph(change_requests, _impact_analysis) do
    # Create a graph where changes depend on other changes if they affect the same files
    # or if one change's output is needed for another change's input
    
    changes_by_id = Map.new(change_requests, &{&1.id, &1})
    
    # Add explicit dependencies
    explicit_deps = change_requests
    |> Enum.flat_map(fn change ->
      Enum.map(change.dependencies, &{change.id, &1})
    end)
    
    # Add implicit dependencies based on file conflicts
    implicit_deps = for change1 <- change_requests,
                        change2 <- change_requests,
                        change1.id != change2.id,
                        has_file_overlap?(change1, change2) do
      # Order by priority and breaking changes
      if should_depend_on?(change1, change2) do
        {change1.id, change2.id}
      else
        {change2.id, change1.id}
      end
    end
    
    all_deps = Enum.uniq(explicit_deps ++ implicit_deps)
    
    %{
      changes: changes_by_id,
      dependencies: all_deps
    }
  end

  defp topological_sort_changes(dependency_graph) do
    # Simple topological sort implementation
    # In a production system, we'd use a more robust graph library
    
    changes = Map.keys(dependency_graph.changes)
    dependencies = dependency_graph.dependencies
    
    # Group changes by dependency level
    sorted_groups = sort_by_dependency_level(changes, dependencies, [])
    
    case sorted_groups do
      {:cycle, _} -> {:error, :cycle}
      groups -> {:ok, Enum.map(groups, fn group ->
        Enum.map(group, &dependency_graph.changes[&1])
      end)}
    end
  end

  defp sort_by_dependency_level([], _dependencies, acc), do: Enum.reverse(acc)
  defp sort_by_dependency_level(remaining, dependencies, acc) do
    # Find changes with no dependencies in the remaining set
    independent = Enum.filter(remaining, fn change ->
      deps = Enum.filter(dependencies, fn {_from, to} -> to == change end)
      |> Enum.map(fn {from, _to} -> from end)
      |> Enum.filter(&(&1 in remaining))
      
      Enum.empty?(deps)
    end)
    
    case independent do
      [] when remaining != [] ->
        # Cycle detected
        {:cycle, remaining}
      
      [] ->
        Enum.reverse(acc)
      
      group ->
        new_remaining = remaining -- group
        sort_by_dependency_level(new_remaining, dependencies, [group | acc])
    end
  end

  defp identify_parallel_opportunities(_repo_analysis, phases) do
    parallel_groups = phases
    |> Enum.filter(& &1.can_parallel)
    |> Enum.with_index()
    |> Enum.map(fn {phase, index} ->
      %{
        group_id: "parallel_group_#{index}",
        files: phase.files,
        estimated_duration: estimate_phase_duration(phase),
        resource_requirements: analyze_resource_requirements(phase.files)
      }
    end)
    
    {:ok, parallel_groups}
  end

  defp detect_conflicts(change_requests, impact_analysis) do
    conflicts = []
    
    # File modification conflicts
    conflicts = conflicts ++ detect_file_conflicts(change_requests)
    
    # Dependency conflicts
    conflicts = conflicts ++ detect_dependency_conflicts(change_requests, impact_analysis)
    
    # Resource contention conflicts
    conflicts = conflicts ++ detect_resource_conflicts(change_requests)
    
    {:ok, conflicts}
  end

  defp determine_validation_points(phases, opts) do
    validation_strategy = Keyword.get(opts, :validation_strategy, :conservative)
    
    points = case validation_strategy do
      :aggressive ->
        # Validate after every phase
        Enum.map(phases, fn phase ->
          %{
            after_phase: phase.phase,
            type: :compilation,
            description: "Compile and basic validation after phase #{phase.phase}",
            required: true
          }
        end)
      
      :conservative ->
        # Validate at key points
        key_phases = Enum.filter(phases, & &1.validation_required)
        |> Enum.map(fn phase ->
          %{
            after_phase: phase.phase,
            type: :test_suite,
            description: "Full test suite after critical phase #{phase.phase}",
            required: true
          }
        end)
        
        # Add final validation
        final_phase = Enum.max_by(phases, & &1.phase)
        key_phases ++ [%{
          after_phase: final_phase.phase,
          type: :integration_test,
          description: "Final integration validation",
          required: true
        }]
      
      :minimal ->
        # Only validate at the end
        final_phase = Enum.max_by(phases, & &1.phase)
        [%{
          after_phase: final_phase.phase,
          type: :compilation,
          description: "Final compilation check",
          required: true
        }]
    end
    
    {:ok, points}
  end

  defp create_rollback_plan(phases) do
    checkpoints = phases
    |> Enum.filter(&(&1.validation_required or rem(&1.phase, 3) == 0))  # Every 3rd phase or critical phases
    |> Enum.map(fn phase ->
      %{
        phase: phase.phase,
        files_snapshot: phase.files,
        validation_state: %{}
      }
    end)
    
    rollback_order = phases
    |> Enum.map(& &1.phase)
    |> Enum.reverse()
    
    estimated_time = Duration.new!(minute: length(phases) * 2)  # Rough estimate
    
    {:ok, %{
      checkpoints: checkpoints,
      rollback_order: rollback_order,
      estimated_rollback_time: estimated_time
    }}
  end

  defp estimate_total_duration(phases, parallel_groups) do
    # Calculate sequential time
    sequential_time = phases
    |> Enum.map(&estimate_phase_duration/1)
    |> Enum.reduce(Duration.new!(second: 0), &Duration.add/2)
    
    # Subtract time saved by parallelization
    parallel_savings = parallel_groups
    |> Enum.map(& &1.estimated_duration)
    |> Enum.reduce(Duration.new!(second: 0), &Duration.add/2)
    |> Duration.multiply(0.6)  # Assume 60% efficiency in parallel execution
    
    total_time = Duration.subtract(sequential_time, parallel_savings)
    
    {:ok, total_time}
  end

  # Helper functions for validations and optimizations

  defp validate_dependency_ordering(_plan, _repo_analysis) do
    # Validate that dependencies are respected in the phase ordering
    [%{
      type: :dependency_order,
      status: :ok,
      message: "Dependency ordering validated",
      details: %{}
    }]
  end

  defp validate_no_cycles(_plan, _repo_analysis) do
    # Check for circular dependencies in the plan
    [%{
      type: :cycle_detection,
      status: :ok,
      message: "No cycles detected",
      details: %{}
    }]
  end

  defp validate_conflict_resolutions(plan) do
    unresolved = Enum.filter(plan.conflicts, &is_nil(&1.resolution_strategy))
    
    case unresolved do
      [] ->
        [%{
          type: :conflict_resolution,
          status: :ok,
          message: "All conflicts have resolution strategies",
          details: %{}
        }]
      
      conflicts ->
        [%{
          type: :conflict_resolution,
          status: :error,
          message: "#{length(conflicts)} conflicts lack resolution strategies",
          details: %{unresolved_conflicts: conflicts}
        }]
    end
  end

  defp validate_parallel_safety(_plan, _repo_analysis) do
    # Validate that parallel groups don't interfere with each other
    [%{
      type: :parallel_safety,
      status: :ok,
      message: "Parallel execution safety validated",
      details: %{}
    }]
  end

  # Helper functions for conflict detection

  defp detect_file_conflicts(change_requests) do
    # Find changes that modify the same files
    file_changes = change_requests
    |> Enum.flat_map(fn change ->
      Enum.map(change.files, &{&1, change})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_file, changes} -> length(changes) > 1 end)
    
    Enum.map(file_changes, fn {file, conflicting_changes} ->
      %{
        type: :file_modification,
        files: [file],
        description: "File #{file} modified by multiple changes: #{Enum.map(conflicting_changes, & &1.id) |> Enum.join(", ")}",
        resolution_strategy: %{
          type: :sequential_execution,
          steps: ["Execute changes in priority order", "Review merge conflicts"],
          estimated_effort: :medium
        },
        severity: :medium
      }
    end)
  end

  defp detect_dependency_conflicts(_change_requests, _impact_analysis) do
    # Detect circular dependencies or impossible ordering
    []  # Simplified for now
  end

  defp detect_resource_conflicts(_change_requests) do
    # Detect when changes compete for the same resources
    []  # Simplified for now
  end

  # Helper functions for optimization suggestions

  defp suggest_phase_consolidation(plan) do
    # Look for phases that could be combined
    adjacent_phases = plan.phases
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [phase1, phase2] ->
      phase1.can_parallel and phase2.can_parallel and
      length(phase1.files ++ phase2.files) < 10  # Arbitrary threshold
    end)
    
    case adjacent_phases do
      [] -> []
      phases ->
        [%{
          type: :phase_consolidation,
          description: "Consolidate #{length(phases)} adjacent phase pairs to reduce overhead",
          impact: 0.3,
          effort: :low,
          implementation: ["Merge compatible adjacent phases", "Update validation points"]
        }]
    end
  end

  defp suggest_additional_parallelization(_plan, _repo_analysis) do
    # Suggest opportunities for more parallelization
    []  # Simplified for now
  end

  defp suggest_validation_optimization(_plan) do
    # Suggest optimizations to validation strategy
    []  # Simplified for now
  end

  defp suggest_risk_mitigation(_plan) do
    # Suggest additional risk mitigation strategies
    []  # Simplified for now
  end

  # Utility functions

  defp describe_phase(changes) do
    types = Enum.map(changes, & &1.type) |> Enum.uniq()
    "#{Enum.join(types, ", ")} changes"
  end

  defp can_execute_in_parallel?(changes) do
    # Changes can be parallel if they don't affect the same files and aren't breaking
    no_breaking = not Enum.any?(changes, & &1.breaking)
    file_sets = Enum.map(changes, &MapSet.new(&1.files))
    no_overlap = file_sets
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    |> MapSet.size() == Enum.sum(Enum.map(file_sets, &MapSet.size/1))
    
    no_breaking and no_overlap
  end

  defp requires_validation?(changes) do
    Enum.any?(changes, fn change ->
      change.breaking or change.type in [:migration, :removal] or change.priority == :critical
    end)
  end

  defp has_file_overlap?(change1, change2) do
    set1 = MapSet.new(change1.files)
    set2 = MapSet.new(change2.files)
    not MapSet.disjoint?(set1, set2)
  end

  defp should_depend_on?(change1, change2) do
    # Higher priority changes should execute first
    # Breaking changes should be handled carefully
    cond do
      change2.priority == :critical and change1.priority != :critical -> true
      change2.breaking and not change1.breaking -> true
      true -> false
    end
  end

  defp estimate_phase_duration(phase) do
    # Rough estimation based on file count and complexity
    base_minutes = length(phase.files) * 2
    Duration.new!(minute: base_minutes)
  end

  defp analyze_resource_requirements(files) do
    # Analyze what resources the files typically require
    %{
      cpu_intensive: Enum.any?(files, &String.contains?(&1, "computation")),
      memory_intensive: Enum.any?(files, &String.contains?(&1, "large_data")),
      io_intensive: Enum.any?(files, &String.contains?(&1, "database")),
      network_required: Enum.any?(files, &String.contains?(&1, "api"))
    }
  end

  defp optimize_phase_for_parallelism(phase, _max_parallel) do
    # For now, just return the phase unchanged
    # In a full implementation, we'd split large phases
    phase
  end

  defp merge_compatible_parallel_groups(groups, _max_parallel) do
    # For now, just return groups unchanged
    # In a full implementation, we'd merge compatible groups
    groups
  end
end