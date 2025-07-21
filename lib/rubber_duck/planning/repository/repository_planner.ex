defmodule RubberDuck.Planning.Repository.RepositoryPlanner do
  @moduledoc """
  Main interface for repository-level planning and multi-file change management.
  
  This module provides the primary API for planning repository-wide changes,
  coordinating between analysis, impact assessment, sequencing, and execution.
  It integrates with the existing planning system and ReAct execution framework.
  """

  alias RubberDuck.Planning.Plan
  alias RubberDuck.Planning.Repository.{
    RepositoryAnalyzer,
    ChangeImpactAnalyzer, 
    ChangeSequencer
  }
  alias RubberDuck.Planning.Execution.PlanExecutor
  
  require Logger

  @type repository_plan :: %{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    repository_path: String.t(),
    analysis: RepositoryAnalyzer.analysis_result(),
    changes: [change_request()],
    impact: ChangeImpactAnalyzer.impact_analysis(),
    sequence: ChangeSequencer.sequence_plan(),
    execution_plan: Plan.t() | nil,
    status: plan_status(),
    metadata: map()
  }

  @type change_request :: %{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    files: [String.t()],
    type: change_type(),
    priority: priority_level(),
    dependencies: [String.t()],
    estimated_effort: float(),
    breaking: boolean(),
    validation_required: boolean()
  }

  @type change_type :: :feature | :bugfix | :refactor | :migration | :removal | :architectural
  @type priority_level :: :low | :medium | :high | :critical
  @type plan_status :: :draft | :analyzed | :sequenced | :validated | :ready | :executing | :completed | :failed

  @doc """
  Creates a new repository-level plan for the given changes.
  """
  @spec create_plan(String.t(), String.t(), [change_request()], keyword()) :: 
    {:ok, repository_plan()} | {:error, term()}
  def create_plan(repository_path, plan_name, changes, opts \\ []) do
    Logger.info("Creating repository plan '#{plan_name}' for #{length(changes)} changes")
    
    plan_id = generate_plan_id()
    description = Keyword.get(opts, :description, "Repository-level plan: #{plan_name}")
    
    with {:ok, analysis} <- analyze_repository(repository_path, opts),
         {:ok, impact} <- analyze_changes_impact(analysis, changes),
         {:ok, sequence} <- create_change_sequence(analysis, changes, impact, opts) do
      
      plan = %{
        id: plan_id,
        name: plan_name,
        description: description,
        repository_path: repository_path,
        analysis: analysis,
        changes: changes,
        impact: impact,
        sequence: sequence,
        execution_plan: nil,
        status: :analyzed,
        metadata: %{
          created_at: DateTime.utc_now(),
          options: opts
        }
      }
      
      Logger.info("Repository plan '#{plan_name}' created successfully")
      {:ok, plan}
    else
      error ->
        Logger.error("Failed to create repository plan: #{inspect(error)}")
        error
    end
  end

  @doc """
  Converts a repository plan into an executable Ash Plan resource.
  """
  @spec convert_to_execution_plan(repository_plan()) :: {:ok, Plan.t()} | {:error, term()}
  def convert_to_execution_plan(repo_plan) do
    Logger.info("Converting repository plan to execution plan")
    
    # Create main plan resource
    plan_attrs = %{
      name: repo_plan.name,
      description: repo_plan.description,
      type: :repository_wide,
      status: :draft,
      context: %{
        repository_path: repo_plan.repository_path,
        total_files: length(get_all_affected_files(repo_plan)),
        risk_level: repo_plan.impact.risk_assessment.overall_risk
      },
      constraints: extract_constraints(repo_plan),
      metadata: %{
        repository_plan_id: repo_plan.id,
        estimated_duration: repo_plan.sequence.estimated_duration,
        parallel_capable: length(repo_plan.sequence.parallel_groups) > 0
      }
    }
    
    case Ash.create(Plan, plan_attrs) do
      {:ok, plan} ->
        case create_execution_tasks(plan, repo_plan) do
          {:ok, _tasks} ->
            updated_repo_plan = %{repo_plan | 
              execution_plan: plan,
              status: :ready
            }
            {:ok, updated_repo_plan}
          
          error ->
            Ash.destroy!(plan)
            error
        end
      
      error ->
        error
    end
  end

  @doc """
  Executes a repository plan using the ReAct execution framework.
  """
  @spec execute_plan(repository_plan(), keyword()) :: {:ok, pid()} | {:error, term()}
  def execute_plan(repo_plan, opts \\ []) do
    case repo_plan.execution_plan do
      nil ->
        {:error, :no_execution_plan}
      
      plan ->
        Logger.info("Executing repository plan '#{repo_plan.name}'")
        
        execution_opts = Keyword.merge([
          repository_mode: true,
          validation_strategy: :conservative,
          parallel_execution: length(repo_plan.sequence.parallel_groups) > 0
        ], opts)
        
        PlanExecutor.start_link(plan: plan, options: execution_opts)
    end
  end

  @doc """
  Previews the changes that would be made by a repository plan.
  """
  @spec preview_changes(repository_plan()) :: {:ok, change_preview()} | {:error, term()}
  def preview_changes(repo_plan) do
    Logger.info("Generating preview for repository plan '#{repo_plan.name}'")
    
    preview = %{
      summary: generate_change_summary(repo_plan),
      phases: preview_execution_phases(repo_plan.sequence),
      risk_factors: repo_plan.impact.risk_assessment.factors,
      affected_files: get_all_affected_files(repo_plan),
      estimated_effort: repo_plan.impact.estimated_effort,
      validation_points: repo_plan.sequence.validation_points,
      rollback_plan: repo_plan.sequence.rollback_plan
    }
    
    {:ok, preview}
  end

  @type change_preview :: %{
    summary: change_summary(),
    phases: [phase_preview()],
    risk_factors: [ChangeImpactAnalyzer.risk_factor()],
    affected_files: [String.t()],
    estimated_effort: ChangeImpactAnalyzer.effort_estimate(),
    validation_points: [ChangeSequencer.validation_point()],
    rollback_plan: ChangeSequencer.rollback_plan()
  }

  @type change_summary :: %{
    total_changes: non_neg_integer(),
    by_type: map(),
    by_priority: map(),
    breaking_changes: non_neg_integer(),
    files_affected: non_neg_integer()
  }

  @type phase_preview :: %{
    phase: non_neg_integer(),
    name: String.t(),
    changes: [String.t()],
    files: [String.t()],
    can_parallel: boolean(),
    estimated_duration: Duration.t(),
    validation_required: boolean()
  }

  @doc """
  Validates a repository plan before execution.
  """
  @spec validate_plan(repository_plan()) :: {:ok, [validation_result()]} | {:error, term()}
  def validate_plan(repo_plan) do
    Logger.info("Validating repository plan '#{repo_plan.name}'")
    
    validations = []
    
    # Validate repository analysis is current
    validations = validations ++ validate_analysis_currency(repo_plan)
    
    # Validate change definitions
    validations = validations ++ validate_change_definitions(repo_plan.changes)
    
    # Validate sequence plan
    validations = case ChangeSequencer.validate_sequence(repo_plan.sequence, repo_plan.analysis) do
      {:ok, sequence_validations} ->
        validations ++ sequence_validations
        
      {:error, errors} ->
        validations ++ [%{
          type: :sequence_validation,
          status: :error,
          message: "Sequence validation failed",
          details: %{errors: errors}
        }]
    end
    
    # Validate risk assessment
    validations = validations ++ validate_risk_assessment(repo_plan.impact.risk_assessment)
    
    case Enum.filter(validations, &(&1.status == :error)) do
      [] ->
        Logger.info("Repository plan validation passed")
        {:ok, validations}
      
      errors ->
        Logger.warning("Repository plan validation failed with #{length(errors)} errors")
        {:error, {:validation_failed, errors}}
    end
  end

  @type validation_result :: %{
    type: validation_type(),
    status: :ok | :warning | :error,
    message: String.t(),
    details: map()
  }

  @type validation_type :: 
    :analysis_currency | :change_definitions | :sequence_validation | :risk_assessment

  @doc """
  Suggests optimizations for a repository plan.
  """
  @spec suggest_optimizations(repository_plan()) :: [optimization_suggestion()]
  def suggest_optimizations(repo_plan) do
    suggestions = []
    
    # Get sequencer suggestions
    suggestions = suggestions ++ ChangeSequencer.suggest_improvements(repo_plan.sequence, repo_plan.analysis)
    
    # Add plan-level suggestions
    suggestions = suggestions ++ suggest_plan_optimizations(repo_plan)
    
    # Add risk mitigation suggestions
    suggestions = suggestions ++ ChangeImpactAnalyzer.suggest_mitigations(repo_plan.impact)
    |> Enum.map(&convert_mitigation_to_optimization/1)
    
    Enum.sort_by(suggestions, & &1.impact, :desc)
  end

  @type optimization_suggestion :: %{
    type: optimization_type(),
    description: String.t(),
    impact: float(),
    effort: effort_level(),
    implementation: [String.t()]
  }

  @type optimization_type :: 
    :change_grouping | :parallel_execution | :risk_reduction | :validation_optimization

  @type effort_level :: :low | :medium | :high

  @doc """
  Gets the current status and progress of a repository plan.
  """
  @spec get_plan_status(repository_plan()) :: plan_status_info()
  def get_plan_status(repo_plan) do
    %{
      status: repo_plan.status,
      progress: calculate_progress(repo_plan),
      current_phase: get_current_phase(repo_plan),
      next_actions: get_next_actions(repo_plan),
      issues: get_current_issues(repo_plan)
    }
  end

  @type plan_status_info :: %{
    status: plan_status(),
    progress: float(),
    current_phase: String.t() | nil,
    next_actions: [String.t()],
    issues: [String.t()]
  }

  # Private functions

  defp analyze_repository(repository_path, opts) do
    analysis_opts = Keyword.take(opts, [:patterns, :exclude])
    RepositoryAnalyzer.analyze(repository_path, analysis_opts)
  end

  defp analyze_changes_impact(analysis, changes) do
    all_files = Enum.flat_map(changes, & &1.files)
    ChangeImpactAnalyzer.analyze_impact(analysis, all_files)
  end

  defp create_change_sequence(analysis, changes, _impact, opts) do
    sequence_requests = Enum.map(changes, &convert_to_sequence_request/1)
    sequence_opts = Keyword.take(opts, [:validation_strategy, :max_parallel])
    
    ChangeSequencer.create_sequence(analysis, sequence_requests, sequence_opts)
  end

  defp convert_to_sequence_request(change) do
    %{
      id: change.id,
      files: change.files,
      type: change.type,
      priority: change.priority,
      dependencies: change.dependencies,
      estimated_effort: change.estimated_effort,
      breaking: change.breaking
    }
  end

  defp create_execution_tasks(plan, repo_plan) do
    tasks = repo_plan.sequence.phases
    |> Enum.with_index(1)
    |> Enum.map(fn {phase, position} ->
      create_task_for_phase(plan, phase, position, repo_plan)
    end)
    
    case create_all_tasks(tasks) do
      {:ok, created_tasks} ->
        # Set up task dependencies
        setup_task_dependencies(created_tasks, repo_plan.sequence.phases)
        {:ok, created_tasks}
      
      error ->
        error
    end
  end

  defp create_task_for_phase(plan, phase, position, repo_plan) do
    # Find the changes for this phase
    phase_changes = repo_plan.changes
    |> Enum.filter(fn change ->
      Enum.any?(change.files, &(&1 in phase.files))
    end)
    
    %{
      name: phase.name,
      description: "Execute #{phase.name}: #{Enum.map(phase_changes, & &1.name) |> Enum.join(", ")}",
      complexity: determine_task_complexity(phase, phase_changes),
      position: position,
      status: :pending,
      success_criteria: build_success_criteria(phase, phase_changes),
      validation_rules: build_validation_rules(phase),
      metadata: %{
        phase_number: phase.phase,
        files: phase.files,
        changes: Enum.map(phase_changes, & &1.id),
        can_parallel: phase.can_parallel,
        repository_path: repo_plan.repository_path
      },
      plan_id: plan.id
    }
  end

  defp extract_constraints(repo_plan) do
    base_constraints = [
      %{
        type: :compilation_order,
        description: "Maintain compilation dependency order",
        metadata: %{sequence_phases: length(repo_plan.sequence.phases)}
      }
    ]
    
    # Add risk-based constraints
    risk_constraints = case repo_plan.impact.risk_assessment.overall_risk do
      :critical ->
        [%{
          type: :validation_required,
          description: "Validation required after each phase due to critical risk",
          metadata: %{risk_factors: length(repo_plan.impact.risk_assessment.factors)}
        }]
      
      :high ->
        [%{
          type: :staged_rollout,
          description: "Staged rollout required due to high risk",
          metadata: %{}
        }]
      
      _ ->
        []
    end
    
    base_constraints ++ risk_constraints
  end

  defp get_all_affected_files(repo_plan) do
    changed = Enum.flat_map(repo_plan.changes, & &1.files)
    direct = repo_plan.impact.directly_affected
    transitive = repo_plan.impact.transitively_affected
    
    (changed ++ direct ++ transitive) |> Enum.uniq()
  end

  defp generate_change_summary(repo_plan) do
    changes = repo_plan.changes
    
    %{
      total_changes: length(changes),
      by_type: Enum.frequencies_by(changes, & &1.type),
      by_priority: Enum.frequencies_by(changes, & &1.priority),
      breaking_changes: Enum.count(changes, & &1.breaking),
      files_affected: length(get_all_affected_files(repo_plan))
    }
  end

  defp preview_execution_phases(sequence) do
    Enum.map(sequence.phases, fn phase ->
      %{
        phase: phase.phase,
        name: phase.name,
        changes: [],  # Would be populated with change IDs
        files: phase.files,
        can_parallel: phase.can_parallel,
        estimated_duration: estimate_phase_duration(phase),
        validation_required: phase.validation_required
      }
    end)
  end

  defp validate_analysis_currency(repo_plan) do
    created_at = repo_plan.metadata.created_at
    age_hours = DateTime.diff(DateTime.utc_now(), created_at, :hour)
    
    if age_hours > 24 do
      [%{
        type: :analysis_currency,
        status: :warning,
        message: "Repository analysis is #{age_hours} hours old, consider refreshing",
        details: %{age_hours: age_hours}
      }]
    else
      [%{
        type: :analysis_currency,
        status: :ok,
        message: "Repository analysis is current",
        details: %{age_hours: age_hours}
      }]
    end
  end

  defp validate_change_definitions(changes) do
    invalid_changes = Enum.filter(changes, fn change ->
      is_nil(change.id) or is_nil(change.name) or Enum.empty?(change.files)
    end)
    
    case invalid_changes do
      [] ->
        [%{
          type: :change_definitions,
          status: :ok,
          message: "All change definitions are valid",
          details: %{}
        }]
      
      invalid ->
        [%{
          type: :change_definitions,
          status: :error,
          message: "#{length(invalid)} changes have invalid definitions",
          details: %{invalid_changes: Enum.map(invalid, & &1.id)}
        }]
    end
  end

  defp validate_risk_assessment(risk_assessment) do
    if risk_assessment.confidence < 0.5 do
      [%{
        type: :risk_assessment,
        status: :warning,
        message: "Risk assessment has low confidence (#{Float.round(risk_assessment.confidence * 100, 1)}%)",
        details: %{confidence: risk_assessment.confidence}
      }]
    else
      [%{
        type: :risk_assessment,
        status: :ok,
        message: "Risk assessment confidence is acceptable",
        details: %{confidence: risk_assessment.confidence}
      }]
    end
  end

  defp suggest_plan_optimizations(repo_plan) do
    suggestions = []
    
    # Suggest change grouping if many small changes
    suggestions = if length(repo_plan.changes) > 10 do
      suggestions ++ [%{
        type: :change_grouping,
        description: "Consider grouping related changes to reduce coordination overhead",
        impact: 0.4,
        effort: :medium,
        implementation: ["Group changes by module or feature area", "Update sequence plan"]
      }]
    else
      suggestions
    end
    
    # Suggest parallel execution if not already optimized
    suggestions = if length(repo_plan.sequence.parallel_groups) == 0 and length(repo_plan.changes) > 3 do
      suggestions ++ [%{
        type: :parallel_execution,
        description: "Enable parallel execution for independent changes",
        impact: 0.6,
        effort: :low,
        implementation: ["Re-analyze for parallel opportunities", "Update sequence plan"]
      }]
    else
      suggestions
    end
    
    suggestions
  end

  defp convert_mitigation_to_optimization(mitigation) do
    %{
      type: :risk_reduction,
      description: mitigation.description,
      impact: mitigation.effectiveness,
      effort: mitigation.effort,
      implementation: ["Apply risk mitigation strategy: #{mitigation.type}"]
    }
  end

  defp calculate_progress(repo_plan) do
    case repo_plan.status do
      :draft -> 0.0
      :analyzed -> 0.3
      :sequenced -> 0.5
      :validated -> 0.7
      :ready -> 0.8
      :executing -> 0.9
      :completed -> 1.0
      :failed -> 0.0
    end
  end

  defp get_current_phase(repo_plan) do
    case repo_plan.status do
      :draft -> "Initial planning"
      :analyzed -> "Repository analysis complete"
      :sequenced -> "Change sequence planned"
      :validated -> "Plan validation complete"
      :ready -> "Ready for execution"
      :executing -> "Executing changes"
      :completed -> "All changes completed"
      :failed -> "Execution failed"
    end
  end

  defp get_next_actions(repo_plan) do
    case repo_plan.status do
      :draft -> ["Complete repository analysis", "Define change requests"]
      :analyzed -> ["Create change sequence", "Analyze impact"]
      :sequenced -> ["Validate plan", "Review risk assessment"]
      :validated -> ["Convert to execution plan", "Prepare for execution"]
      :ready -> ["Execute plan", "Monitor progress"]
      :executing -> ["Monitor execution", "Handle any issues"]
      :completed -> ["Review results", "Document lessons learned"]
      :failed -> ["Analyze failure", "Plan recovery or rollback"]
    end
  end

  defp get_current_issues(_repo_plan) do
    # Would analyze current state for issues
    []
  end

  defp create_all_tasks(task_specs) do
    # In a real implementation, this would create Task resources
    # For now, just return success
    {:ok, task_specs}
  end

  defp setup_task_dependencies(_tasks, _phases) do
    # Would set up task dependencies based on phase dependencies
    :ok
  end

  defp determine_task_complexity(phase, changes) do
    # Base complexity on number of files and breaking changes
    file_count = length(phase.files)
    breaking_count = Enum.count(changes, & &1.breaking)
    
    cond do
      breaking_count > 0 or file_count > 20 -> :very_complex
      file_count > 10 -> :complex
      file_count > 5 -> :medium
      true -> :simple
    end
  end

  defp build_success_criteria(_phase, changes) do
    [
      "All files in phase compile successfully",
      "No breaking test failures",
      "All change validation rules pass"
    ] ++ Enum.map(changes, &"Change '#{&1.name}' completes successfully")
  end

  defp build_validation_rules(phase) do
    [
      %{type: :compilation_check, required: true},
      %{type: :test_execution, required: phase.validation_required}
    ]
  end

  defp estimate_phase_duration(phase) do
    # Simple duration estimation
    base_minutes = length(phase.files) * 2
    Duration.new!(minute: base_minutes)
  end

  defp generate_plan_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end