defmodule RubberDuck.Workflows.DynamicBuilder do
  @moduledoc """
  Dynamically constructs workflows at runtime based on task analysis.

  Uses the Reactor.Builder API to create workflows that adapt to:
  - Task complexity and requirements
  - Available resources
  - Optimization strategies
  - Historical performance data
  """

  require Logger

  alias RubberDuck.Workflows.{TemplateRegistry, AgentSteps}

  @type task :: map()
  @type analysis_result :: map()
  @type optimization_strategy :: :speed | :resource | :balanced
  @type build_opts :: [
          use_template: boolean(),
          template: map() | nil,
          optimization_strategy: optimization_strategy(),
          include_resource_management: boolean(),
          customization: map()
        ]

  @doc """
  Builds a dynamic workflow based on task and analysis results.
  """
  @spec build(task(), analysis_result(), build_opts()) :: {:ok, Reactor.t()} | {:error, term()}
  def build(task, analysis, opts \\ []) do
    with :ok <- validate_inputs(task, analysis),
         {:ok, reactor} <- initialize_reactor(),
         {:ok, reactor} <- add_dynamic_inputs(reactor, task),
         {:ok, reactor} <- build_workflow_structure(reactor, task, analysis, opts),
         {:ok, reactor} <- maybe_add_resource_management(reactor, analysis, opts),
         {:ok, reactor} <- maybe_apply_optimizations(reactor, opts),
         {:ok, reactor} <- finalize_workflow(reactor) do
      {:ok, reactor}
    else
      {:error, reason} = error ->
        Logger.error("Failed to build dynamic workflow: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Adds inputs to the reactor based on task fields.
  """
  @spec add_dynamic_inputs(Reactor.t(), task()) :: {:ok, Reactor.t()} | {:error, term()}
  def add_dynamic_inputs(reactor, task) when is_map(task) do
    # Extract all top-level keys as potential inputs
    input_keys = Map.keys(task) -- [:type, :id, :metadata]

    result =
      Enum.reduce_while(input_keys, {:ok, reactor}, fn key, {:ok, acc} ->
        case Reactor.Builder.add_input(acc, key) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, _} = success -> success
      error -> error
    end
  end

  def add_dynamic_inputs(reactor, _), do: {:ok, reactor}

  @doc """
  Adds steps based on complexity analysis.
  """
  @spec add_steps_by_complexity(Reactor.t(), analysis_result()) :: {:ok, Reactor.t()} | {:error, term()}
  def add_steps_by_complexity(reactor, analysis) do
    cond do
      # Use template if suggested
      template = get_suggested_template(analysis) ->
        add_template_steps(reactor, template, analysis)

      # Build custom workflow based on required agents
      agents = get_required_agents(analysis) ->
        add_agent_steps(reactor, agents, analysis)

      # Fallback to simple workflow
      true ->
        add_simple_workflow(reactor)
    end
  end

  @doc """
  Adds resource management steps.
  """
  @spec add_resource_management(Reactor.t(), map()) :: {:ok, Reactor.t()} | {:error, term()}
  def add_resource_management(reactor, requirements) do
    with {:ok, reactor} <- add_agent_allocation_step(reactor, requirements),
         {:ok, reactor} <- maybe_add_monitoring_step(reactor, requirements) do
      {:ok, reactor}
    end
  end

  @doc """
  Applies optimization strategies to the workflow.
  """
  @spec apply_optimizations(Reactor.t(), optimization_strategy()) :: {:ok, Reactor.t()} | {:error, term()}
  def apply_optimizations(reactor, strategy) do
    case strategy do
      :speed -> optimize_for_speed(reactor)
      :resource -> optimize_for_resources(reactor)
      :balanced -> apply_balanced_optimization(reactor)
      _ -> {:ok, reactor}
    end
  end

  @doc """
  Finalizes the workflow by setting return values and metadata.
  """
  @spec finalize_workflow(Reactor.t()) :: {:ok, Reactor.t()} | {:error, term()}
  def finalize_workflow(reactor) do
    # Get all steps to find the last one
    case get_reactor_steps(reactor) do
      [] ->
        # Empty workflow, just return the reactor
        {:ok, reactor}

      steps ->
        # Find the last step that should be the return value
        last_step = find_terminal_step(steps)

        case Reactor.Builder.return(reactor, last_step) do
          {:ok, finalized} -> {:ok, finalized}
          # Fallback if return fails
          {:error, _} -> {:ok, reactor}
        end
    end
  end

  # Private functions

  defp validate_inputs(nil, _), do: {:error, :invalid_task}
  defp validate_inputs(_, nil), do: {:error, :invalid_analysis}
  defp validate_inputs(task, analysis) when is_map(task) and is_map(analysis), do: :ok
  defp validate_inputs(_, _), do: {:error, :invalid_inputs}

  defp initialize_reactor do
    {:ok, Reactor.Builder.new()}
  end

  defp build_workflow_structure(reactor, task, analysis, opts) do
    cond do
      opts[:use_template] && opts[:template] ->
        build_from_template(reactor, opts[:template], task, analysis, opts)

      opts[:use_template] ->
        build_from_suggested_template(reactor, task, analysis, opts)

      true ->
        build_custom_workflow(reactor, task, analysis, opts)
    end
  end

  defp build_from_template(reactor, template, _task, analysis, opts) do
    # Apply customization to template
    customized =
      if custom = opts[:customization] do
        TemplateRegistry.apply_parameters(template, custom)
      else
        template
      end

    # Add template steps to reactor
    add_template_steps(reactor, customized, analysis)
  end

  defp build_from_suggested_template(reactor, _task, analysis, opts) do
    case get_suggested_template(analysis) do
      nil ->
        build_custom_workflow(reactor, nil, analysis, opts)

      template ->
        build_from_template(reactor, template, nil, analysis, opts)
    end
  end

  defp build_custom_workflow(reactor, _task, analysis, _opts) do
    # Build workflow based on required agents
    agents = get_required_agents(analysis)
    add_agent_steps(reactor, agents, analysis)
  end

  defp get_suggested_template(analysis) do
    case analysis[:suggested_workflow_type] do
      :simple_analysis -> TemplateRegistry.get_by_name(:simple_analysis)
      :deep_analysis -> TemplateRegistry.get_by_name(:deep_analysis)
      :generation_pipeline -> TemplateRegistry.get_by_name(:generation_pipeline)
      :simple_refactoring -> TemplateRegistry.get_by_name(:simple_refactoring)
      :complex_refactoring -> TemplateRegistry.get_by_name(:complex_refactoring)
      :review_pipeline -> TemplateRegistry.get_by_name(:review_pipeline)
      _ -> nil
    end
  end

  defp get_required_agents(analysis) do
    get_in(analysis, [:resource_requirements, :agents]) || []
  end

  defp add_template_steps(reactor, template, analysis) do
    parallelization = Map.get(analysis, :parallelization_strategy, :sequential)

    # Group steps by dependencies for proper ordering
    step_groups = group_steps_by_dependencies(template.steps)

    # Add each group of steps
    Enum.reduce_while(step_groups, {:ok, reactor}, fn group, {:ok, acc} ->
      case add_step_group(acc, group, parallelization) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end

  defp add_agent_steps(reactor, agents, analysis) do
    parallelization = Map.get(analysis, :parallelization_strategy, :sequential)

    # Create steps for each agent
    steps =
      Enum.map(agents, fn agent ->
        %{
          name: :"#{agent}_task",
          type: agent,
          agent: agent,
          config: %{},
          depends_on: []
        }
      end)

    # Add steps based on parallelization strategy
    case parallelization do
      :sequential ->
        add_sequential_steps(reactor, steps)

      :parallel_analysis ->
        if :analysis in agents do
          add_parallel_analysis_steps(reactor, steps)
        else
          add_sequential_steps(reactor, steps)
        end

      :pipeline ->
        add_pipeline_steps(reactor, steps)

      _ ->
        add_sequential_steps(reactor, steps)
    end
  end

  defp add_simple_workflow(reactor) do
    # Add a single analysis step as fallback
    Reactor.Builder.add_step(
      reactor,
      :simple_analysis,
      {AgentSteps, :execute_agent_task},
      [
        %Reactor.Argument{
          name: :agent_id,
          source: %Reactor.Template.Value{value: "analysis_default"}
        },
        %Reactor.Argument{
          name: :task,
          source: %Reactor.Template.Value{value: {:analyze, %{}}}
        }
      ]
    )
  end

  defp add_agent_allocation_step(reactor, requirements) do
    agents_needed = requirements[:agents] || []

    Reactor.Builder.add_step(
      reactor,
      :allocate_agents,
      {AgentSteps, :ensure_agents},
      [
        %Reactor.Argument{
          name: :required_agents,
          source: %Reactor.Template.Value{value: agents_needed}
        },
        %Reactor.Argument{
          name: :requirements,
          source: %Reactor.Template.Value{value: requirements}
        }
      ]
    )
  end

  defp maybe_add_monitoring_step(reactor, requirements) do
    if requirements[:memory] == :high || length(requirements[:agents] || []) > 3 do
      Reactor.Builder.add_step(
        reactor,
        :monitor_resources,
        {AgentSteps, :monitor_resources},
        [
          %Reactor.Argument{
            name: :thresholds,
            source: %Reactor.Template.Value{
              value: %{
                memory: :high,
                agent_count: length(requirements[:agents] || [])
              }
            }
          }
        ]
      )
    else
      {:ok, reactor}
    end
  end

  defp maybe_add_resource_management(reactor, analysis, opts) do
    if opts[:include_resource_management] do
      requirements = analysis[:resource_requirements] || %{}
      add_resource_management(reactor, requirements)
    else
      {:ok, reactor}
    end
  end

  defp maybe_apply_optimizations(reactor, opts) do
    if strategy = opts[:optimization_strategy] do
      apply_optimizations(reactor, strategy)
    else
      {:ok, reactor}
    end
  end

  defp optimize_for_speed(reactor) do
    # This would modify step configurations to maximize parallelization
    # For now, return as-is since Reactor handles parallelization automatically
    {:ok, reactor}
  end

  defp optimize_for_resources(reactor) do
    # This would modify step configurations to minimize resource usage
    # Could add throttling or sequential execution hints
    {:ok, reactor}
  end

  defp apply_balanced_optimization(reactor) do
    # Balance between speed and resource usage
    {:ok, reactor}
  end

  defp group_steps_by_dependencies(steps) do
    # Group steps that can run in parallel
    steps
    |> Enum.group_by(fn step ->
      length(Map.get(step, :depends_on, []))
    end)
    |> Enum.sort_by(fn {dep_count, _} -> dep_count end)
    |> Enum.map(fn {_count, group} -> group end)
  end

  defp add_step_group(reactor, steps, _parallelization) do
    Enum.reduce_while(steps, {:ok, reactor}, fn step, {:ok, acc} ->
      case add_single_step(acc, step) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end

  defp add_single_step(reactor, step) do
    arguments = build_step_arguments(step)

    Reactor.Builder.add_step(
      reactor,
      step.name || :"step_#{System.unique_integer([:positive])}",
      {AgentSteps, :execute_agent_task},
      arguments
    )
  end

  defp build_step_arguments(step) do
    [
      %Reactor.Argument{
        name: :agent_type,
        source: %Reactor.Template.Value{value: step.agent}
      },
      %Reactor.Argument{
        name: :task,
        source: %Reactor.Template.Value{value: {step.type, step.config}}
      }
    ] ++ build_dependency_arguments(step)
  end

  defp build_dependency_arguments(step) do
    case Map.get(step, :depends_on, []) do
      [] ->
        []

      deps ->
        [
          %Reactor.Argument{
            name: :dependencies,
            source: %Reactor.Template.Value{value: deps}
          }
        ]
    end
  end

  defp add_sequential_steps(reactor, steps) do
    {reactor, _prev} =
      Enum.reduce(steps, {reactor, nil}, fn step, {acc, prev_name} ->
        # Update step dependencies for sequential execution
        updated_step =
          if prev_name do
            Map.update(step, :depends_on, [prev_name], &(&1 ++ [prev_name]))
          else
            step
          end

        case add_single_step(acc, updated_step) do
          {:ok, updated} -> {updated, step.name}
          _ -> {acc, prev_name}
        end
      end)

    {:ok, reactor}
  end

  defp add_parallel_analysis_steps(reactor, steps) do
    # Separate analysis steps from others
    {analysis_steps, other_steps} = Enum.split_with(steps, &(&1.type == :analysis))

    # Add analysis steps in parallel (no dependencies between them)
    reactor =
      Enum.reduce(analysis_steps, reactor, fn step, acc ->
        case add_single_step(acc, step) do
          {:ok, updated} -> updated
          _ -> acc
        end
      end)

    # Add aggregation step
    analysis_names = Enum.map(analysis_steps, & &1.name)

    reactor =
      case Reactor.Builder.add_step(
             reactor,
             :aggregate_analysis,
             {AgentSteps, :aggregate_agent_results},
             [
               %Reactor.Argument{
                 name: :results,
                 source: %Reactor.Template.Value{value: analysis_names}
               },
               %Reactor.Argument{
                 name: :strategy,
                 source: %Reactor.Template.Value{value: :merge}
               }
             ]
           ) do
        {:ok, updated} -> updated
        _ -> reactor
      end

    # Add remaining steps sequentially after aggregation
    if length(other_steps) > 0 do
      other_with_deps =
        Enum.map(other_steps, fn step ->
          Map.put(step, :depends_on, [:aggregate_analysis])
        end)

      add_sequential_steps(reactor, other_with_deps)
    else
      {:ok, reactor}
    end
  end

  defp add_pipeline_steps(reactor, steps) do
    # For pipeline, each step depends on the previous one
    add_sequential_steps(reactor, steps)
  end

  defp get_reactor_steps(_reactor) do
    # This is a simplified version - in reality we'd need to introspect the reactor
    # For now, we'll track steps as we add them
    # In a real implementation, Reactor.Builder would provide a way to query steps
    []
  end

  defp find_terminal_step(_steps) do
    # Find step with no other steps depending on it
    # For now, return the last step name we generated
    :final_step
  end
end
