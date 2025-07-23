defmodule RubberDuck.Planning.Execution.PlanAdjuster do
  @moduledoc """
  Dynamically adjusts plans based on observations during ReAct execution.

  The PlanAdjuster analyzes observations and can modify the execution plan
  to optimize performance, handle failures, or adapt to changing conditions.
  """

  alias RubberDuck.Planning.Plan
  alias RubberDuck.LLM.Service, as: LLM

  require Logger

  @type adjustment :: {:ok, Plan.t()} | :no_adjustment_needed | {:error, term()}

  @doc """
  Analyzes observations and potentially adjusts the plan.
  """
  @spec analyze_and_adjust(Plan.t(), map(), map()) :: adjustment()
  def analyze_and_adjust(%Plan{} = plan, observation, execution_state) do
    Logger.debug("Analyzing observation for potential plan adjustment")

    # Determine if adjustment is needed
    case should_adjust_plan?(observation, execution_state) do
      {true, reason} ->
        perform_adjustment(plan, observation, execution_state, reason)

      false ->
        :no_adjustment_needed
    end
  end

  defp should_adjust_plan?(observation, execution_state) do
    conditions = [
      check_failure_threshold(observation, execution_state),
      check_performance_degradation(observation),
      check_resource_constraints(observation),
      check_anomalies(observation),
      check_insights_requiring_adjustment(observation)
    ]

    Enum.find(conditions, {false, nil}, fn {should_adjust, _} -> should_adjust end)
  end

  defp check_failure_threshold(_observation, execution_state) do
    failure_rate = calculate_failure_rate(execution_state)

    # 30% failure threshold
    if failure_rate > 0.3 do
      {true, :high_failure_rate}
    else
      {false, nil}
    end
  end

  defp check_performance_degradation(%{metrics: metrics}) do
    case metrics do
      %{execution_time: time} when is_integer(time) and time > 300_000 ->
        {true, :slow_execution}

      _ ->
        {false, nil}
    end
  end

  defp check_resource_constraints(%{anomalies: anomalies}) do
    resource_anomaly =
      Enum.find(anomalies, fn
        %{type: :high_memory_usage} -> true
        %{type: :high_cpu_usage} -> true
        _ -> false
      end)

    if resource_anomaly do
      {true, {:resource_constraint, resource_anomaly.type}}
    else
      {false, nil}
    end
  end

  defp check_anomalies(%{anomalies: anomalies}) do
    critical_anomaly =
      Enum.find(anomalies, fn
        %{severity: :error} -> true
        %{type: :repeated_failures} -> true
        _ -> false
      end)

    if critical_anomaly do
      {true, {:critical_anomaly, critical_anomaly.type}}
    else
      {false, nil}
    end
  end

  defp check_insights_requiring_adjustment(%{insights: insights}) do
    adjustment_keywords = ["reconsider", "alternative", "optimize", "restructure"]

    requires_adjustment =
      Enum.any?(insights, fn insight ->
        Enum.any?(adjustment_keywords, &String.contains?(String.downcase(insight), &1))
      end)

    if requires_adjustment do
      {true, :insight_based_adjustment}
    else
      {false, nil}
    end
  end

  defp perform_adjustment(plan, observation, execution_state, reason) do
    Logger.info("Adjusting plan due to: #{inspect(reason)}")

    adjustment_strategy = determine_adjustment_strategy(reason, observation)

    case apply_adjustment_strategy(plan, adjustment_strategy, observation, execution_state) do
      {:ok, adjusted_plan} ->
        validate_adjusted_plan(adjusted_plan, plan)

      error ->
        error
    end
  end

  defp determine_adjustment_strategy(reason, observation) do
    case reason do
      :high_failure_rate ->
        :simplify_tasks

      :slow_execution ->
        :parallelize_tasks

      {:resource_constraint, :high_memory_usage} ->
        :reduce_batch_sizes

      {:resource_constraint, :high_cpu_usage} ->
        :add_throttling

      {:critical_anomaly, :repeated_failures} ->
        :skip_or_replace_failing_tasks

      :insight_based_adjustment ->
        determine_insight_strategy(observation.insights)

      _ ->
        :general_optimization
    end
  end

  defp determine_insight_strategy(insights) do
    cond do
      Enum.any?(insights, &String.contains?(&1, "optimization")) ->
        :optimize_execution

      Enum.any?(insights, &String.contains?(&1, "alternative")) ->
        :use_alternative_approach

      true ->
        :general_optimization
    end
  end

  defp apply_adjustment_strategy(plan, strategy, observation, execution_state) do
    case strategy do
      :simplify_tasks ->
        simplify_remaining_tasks(plan, execution_state)

      :parallelize_tasks ->
        parallelize_independent_tasks(plan, execution_state)

      :reduce_batch_sizes ->
        adjust_batch_parameters(plan, smaller: true)

      :add_throttling ->
        add_rate_limiting(plan)

      :skip_or_replace_failing_tasks ->
        handle_failing_tasks(plan, observation, execution_state)

      :optimize_execution ->
        optimize_task_execution(plan, execution_state)

      :use_alternative_approach ->
        generate_alternative_approach(plan, observation, execution_state)

      _ ->
        general_optimization(plan, execution_state)
    end
  end

  defp simplify_remaining_tasks(plan, execution_state) do
    remaining_tasks = get_remaining_tasks(plan, execution_state)

    simplified_tasks =
      Enum.map(remaining_tasks, fn task ->
        simplify_task(task)
      end)

    updated_plan = update_plan_tasks(plan, simplified_tasks)
    {:ok, updated_plan}
  end

  defp simplify_task(task) do
    %{
      task
      | complexity: downgrade_complexity(task.complexity),
        metadata: Map.put(task.metadata || %{}, :simplified, true)
    }
  end

  defp downgrade_complexity(:very_complex), do: :complex
  defp downgrade_complexity(:complex), do: :medium
  defp downgrade_complexity(:medium), do: :simple
  defp downgrade_complexity(other), do: other

  defp parallelize_independent_tasks(plan, execution_state) do
    remaining_tasks = get_remaining_tasks(plan, execution_state)

    # Identify tasks that can run in parallel
    parallel_groups = identify_parallel_groups(remaining_tasks)

    # Update task metadata to indicate parallel execution
    updated_tasks =
      Enum.flat_map(parallel_groups, fn group ->
        Enum.map(group, fn task ->
          %{
            task
            | metadata:
                Map.merge(task.metadata || %{}, %{
                  parallel_group: group_id(group),
                  max_parallel: length(group)
                })
          }
        end)
      end)

    updated_plan = update_plan_tasks(plan, updated_tasks)
    {:ok, updated_plan}
  end

  defp identify_parallel_groups(tasks) do
    # Group tasks by their dependencies
    # Tasks with no shared dependencies can run in parallel
    tasks
    |> Enum.group_by(fn task ->
      MapSet.new(task.dependencies || [])
    end)
    |> Map.values()
  end

  defp group_id(group) do
    group
    |> Enum.map(& &1.id)
    |> Enum.sort()
    |> Enum.join("_")
    |> then(&"group_#{&1}")
  end

  defp adjust_batch_parameters(plan, smaller: true) do
    updated_tasks =
      plan.tasks
      |> Enum.map(fn task ->
        case task.metadata[:batch_size] do
          nil ->
            task

          current_size ->
            new_size = max(1, div(current_size, 2))
            %{task | metadata: Map.put(task.metadata, :batch_size, new_size)}
        end
      end)

    updated_plan = update_plan_tasks(plan, updated_tasks)
    {:ok, updated_plan}
  end

  defp add_rate_limiting(plan) do
    updated_metadata =
      Map.merge(plan.metadata || %{}, %{
        rate_limit: %{
          max_concurrent_tasks: 2,
          # 1 second
          delay_between_tasks: 1000
        }
      })

    {:ok, %{plan | metadata: updated_metadata}}
  end

  defp handle_failing_tasks(plan, observation, _execution_state) do
    failing_task_id = observation.task_id

    # Find alternative or skip
    case find_alternative_task(plan, failing_task_id) do
      {:ok, alternative} ->
        replace_task_in_plan(plan, failing_task_id, alternative)

      :no_alternative ->
        mark_task_as_optional(plan, failing_task_id)
    end
  end

  defp find_alternative_task(plan, task_id) do
    task = Enum.find(plan.tasks, &(&1.id == task_id))

    if task && task.metadata[:alternatives] do
      {:ok, create_alternative_task(task)}
    else
      :no_alternative
    end
  end

  defp create_alternative_task(original_task) do
    %{
      original_task
      | id: "#{original_task.id}_alt",
        name: "#{original_task.name} (Alternative)",
        metadata: Map.put(original_task.metadata, :is_alternative, true)
    }
  end

  defp replace_task_in_plan(plan, old_task_id, new_task) do
    updated_tasks =
      plan.tasks
      |> Enum.map(fn task ->
        if task.id == old_task_id do
          new_task
        else
          # Update dependencies
          %{task | dependencies: update_dependencies(task.dependencies, old_task_id, new_task.id)}
        end
      end)

    {:ok, update_plan_tasks(plan, updated_tasks)}
  end

  defp update_dependencies(nil, _, _), do: nil

  defp update_dependencies(deps, old_id, new_id) do
    Enum.map(deps, fn dep ->
      if dep == old_id, do: new_id, else: dep
    end)
  end

  defp mark_task_as_optional(plan, task_id) do
    updated_tasks =
      plan.tasks
      |> Enum.map(fn task ->
        if task.id == task_id do
          %{task | metadata: Map.put(task.metadata || %{}, :optional, true)}
        else
          task
        end
      end)

    {:ok, update_plan_tasks(plan, updated_tasks)}
  end

  defp optimize_task_execution(plan, execution_state) do
    # Use LLM to suggest optimizations
    optimization_prompt = build_optimization_prompt(plan, execution_state)

    case LLM.completion(model: "gpt-3.5-turbo", messages: [%{role: "user", content: optimization_prompt}]) do
      {:ok, suggestions} ->
        apply_optimization_suggestions(plan, suggestions)

      {:error, _} ->
        # Fallback to basic optimization
        general_optimization(plan, execution_state)
    end
  end

  defp build_optimization_prompt(plan, execution_state) do
    """
    Analyze this execution plan and suggest optimizations:

    Plan: #{plan.name}
    Total tasks: #{length(plan.tasks)}
    Completed: #{MapSet.size(execution_state.completed_tasks)}
    Failed: #{MapSet.size(execution_state.failed_tasks)}

    Current issues:
    - Slow execution times
    - Some tasks are failing

    Suggest specific optimizations for task ordering, parallelization, or simplification.
    """
  end

  defp apply_optimization_suggestions(plan, _suggestions) do
    # Parse and apply LLM suggestions
    # This is a simplified implementation
    {:ok, plan}
  end

  defp generate_alternative_approach(plan, observation, execution_state) do
    # Generate a completely new approach using LLM
    prompt = build_alternative_approach_prompt(plan, observation, execution_state)

    case LLM.completion(model: "gpt-4", messages: [%{role: "user", content: prompt}]) do
      {:ok, alternative_plan_description} ->
        create_alternative_plan(plan, alternative_plan_description)

      {:error, _} ->
        # Fallback to simplification
        simplify_remaining_tasks(plan, execution_state)
    end
  end

  defp build_alternative_approach_prompt(plan, observation, _execution_state) do
    """
    The current plan is experiencing issues:

    Plan: #{plan.name}
    Failed task: #{observation.task_id}
    Issues: #{inspect(observation.anomalies)}

    Suggest an alternative approach to achieve the same goal.
    Focus on reliability and simplicity.
    """
  end

  defp create_alternative_plan(original_plan, description) do
    # This would parse the LLM response and create new tasks
    # For now, return the original plan with a flag
    {:ok, %{original_plan | metadata: Map.put(original_plan.metadata || %{}, :alternative_approach, description)}}
  end

  defp general_optimization(plan, execution_state) do
    # Apply general optimizations
    optimizations = [
      &remove_completed_dependencies/2,
      &consolidate_similar_tasks/2,
      &adjust_task_priorities/2
    ]

    optimized_plan =
      Enum.reduce(optimizations, plan, fn opt_fn, current_plan ->
        case opt_fn.(current_plan, execution_state) do
          {:ok, updated_plan} -> updated_plan
          _ -> current_plan
        end
      end)

    {:ok, optimized_plan}
  end

  defp remove_completed_dependencies(plan, execution_state) do
    updated_tasks =
      plan.tasks
      |> Enum.map(fn task ->
        cleaned_deps = clean_dependencies(task.dependencies, execution_state.completed_tasks)
        %{task | dependencies: cleaned_deps}
      end)

    {:ok, update_plan_tasks(plan, updated_tasks)}
  end

  defp clean_dependencies(nil, _), do: nil

  defp clean_dependencies(deps, completed_tasks) do
    Enum.reject(deps, &MapSet.member?(completed_tasks, &1))
  end

  defp consolidate_similar_tasks(plan, _execution_state) do
    # Group similar tasks that can be batched
    # This is a placeholder for more sophisticated logic
    {:ok, plan}
  end

  defp adjust_task_priorities(plan, _execution_state) do
    # Adjust priorities based on current state
    # Higher priority for tasks that unblock others
    {:ok, plan}
  end

  defp validate_adjusted_plan(adjusted_plan, original_plan) do
    # Ensure the adjusted plan is valid and achieves the same goal
    if valid_adjustment?(adjusted_plan, original_plan) do
      {:ok, adjusted_plan}
    else
      {:error, :invalid_adjustment}
    end
  end

  defp valid_adjustment?(adjusted_plan, original_plan) do
    # Basic validation
    adjusted_plan.id == original_plan.id &&
      adjusted_plan.name == original_plan.name &&
      length(adjusted_plan.tasks) > 0
  end

  # Helper functions

  defp calculate_failure_rate(execution_state) do
    total = MapSet.size(execution_state.completed_tasks) + MapSet.size(execution_state.failed_tasks)

    if total > 0 do
      MapSet.size(execution_state.failed_tasks) / total
    else
      0.0
    end
  end

  defp get_remaining_tasks(plan, execution_state) do
    completed_ids = execution_state.completed_tasks
    failed_ids = execution_state.failed_tasks

    Enum.reject(plan.tasks, fn task ->
      MapSet.member?(completed_ids, task.id) ||
        MapSet.member?(failed_ids, task.id)
    end)
  end

  defp update_plan_tasks(plan, updated_tasks) do
    # Merge updated tasks back into the plan
    task_map = Map.new(updated_tasks, &{&1.id, &1})

    all_tasks =
      Enum.map(plan.tasks, fn task ->
        Map.get(task_map, task.id, task)
      end)

    %{plan | tasks: all_tasks}
  end
end
