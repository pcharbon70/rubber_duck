defmodule RubberDuck.Planning.Execution.ActionExecutor do
  @moduledoc """
  Executes actions based on thoughts in the ReAct framework.

  The ActionExecutor takes thoughts from the ThoughtGenerator and
  executes the corresponding actions using the appropriate engines,
  workflows, or tools.
  """

  alias RubberDuck.Planning.Task
  alias RubberDuck.Workflows.Executor
  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.Tool.Executor, as: ToolExecutor

  require Logger

  @type action_result :: {:ok, pid()} | {:error, term()}

  @doc """
  Executes an action based on the provided thought.
  Returns a reference to the executing process.
  """
  @spec execute_action(Task.t(), map(), map()) :: action_result()
  def execute_action(%Task{} = task, thought, execution_state) do
    Logger.info("Executing action for task #{task.id} with approach: #{thought.approach}")

    try do
      case thought.approach do
        :direct_execution ->
          execute_direct(task, thought, execution_state)

        :careful_execution ->
          execute_with_care(task, thought, execution_state)

        :validate_then_execute ->
          execute_with_validation(task, thought, execution_state)

        :execute_with_extended_timeout ->
          execute_with_timeout_adjustment(task, thought, execution_state)

        :wait_and_retry ->
          execute_with_delay(task, thought, execution_state)

        :fix_and_retry ->
          execute_with_fixes(task, thought, execution_state)

        :retry_with_modifications ->
          execute_with_modifications(task, thought, execution_state)

        _ ->
          execute_standard(task, thought, execution_state)
      end
    rescue
      error ->
        Logger.error("Action execution failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp execute_direct(task, thought, execution_state) do
    Logger.debug("Direct execution of task #{task.id}")

    # Determine execution method
    cond do
      has_workflow?(task) ->
        execute_via_workflow(task, build_workflow_input(task, thought, execution_state))

      has_engine?(task) ->
        execute_via_engine(task, build_engine_input(task, thought, execution_state))

      has_tool?(task) ->
        execute_via_tool(task, build_tool_input(task, thought, execution_state))

      true ->
        execute_generic(task, thought, execution_state)
    end
  end

  defp execute_with_care(task, thought, execution_state) do
    Logger.debug("Careful execution of task #{task.id}")

    # Add extra monitoring and validation
    opts = [
      monitor: true,
      validate_inputs: true,
      validate_outputs: true,
      checkpoint_enabled: true,
      timeout: extended_timeout(task)
    ]

    execute_with_options(task, thought, execution_state, opts)
  end

  defp execute_with_validation(task, thought, execution_state) do
    Logger.debug("Validating before execution of task #{task.id}")

    # Validate dependencies and prerequisites
    case validate_prerequisites(task, execution_state) do
      :ok ->
        execute_direct(task, thought, execution_state)

      {:error, reason} = error ->
        Logger.error("Validation failed for task #{task.id}: #{inspect(reason)}")
        error
    end
  end

  defp execute_with_timeout_adjustment(task, thought, execution_state) do
    Logger.debug("Executing task #{task.id} with extended timeout")

    # Double the timeout for retry attempts
    current_timeout = get_task_timeout(task)
    opts = [timeout: current_timeout * 2]

    execute_with_options(task, thought, execution_state, opts)
  end

  defp execute_with_delay(task, thought, execution_state) do
    Logger.debug("Delaying execution of task #{task.id}")

    # Wait before retrying
    delay = calculate_retry_delay(task, execution_state)
    Process.sleep(delay)

    execute_direct(task, thought, execution_state)
  end

  defp execute_with_fixes(task, thought, execution_state) do
    Logger.debug("Applying fixes before execution of task #{task.id}")

    # Apply fixes based on previous failures
    fixed_input = apply_fixes(task, thought, execution_state)

    execute_with_modified_input(task, thought, execution_state, fixed_input)
  end

  defp execute_with_modifications(task, thought, execution_state) do
    Logger.debug("Executing task #{task.id} with modifications")

    # Modify execution strategy based on previous attempts
    modifications = determine_modifications(task, execution_state)

    execute_with_options(task, thought, execution_state, modifications)
  end

  defp execute_standard(task, thought, execution_state) do
    Logger.debug("Standard execution of task #{task.id}")
    execute_direct(task, thought, execution_state)
  end

  # Execution methods

  defp execute_via_workflow(task, input) do
    Logger.debug("Executing task #{task.id} via workflow")

    workflow_module = get_workflow_module(task)

    case Executor.execute_workflow(workflow_module, input, %{}, %{}) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        error
    end
  end

  defp execute_via_engine(task, input) do
    Logger.debug("Executing task #{task.id} via engine")

    engine_name = get_engine_name(task)

    case EngineManager.execute(engine_name, input) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        error
    end
  end

  defp execute_via_tool(task, input) do
    Logger.debug("Executing task #{task.id} via tool")

    tool_name = get_tool_name(task)

    # Start async tool execution
    pid =
      spawn_link(fn ->
        result = ToolExecutor.execute(tool_name, input, %{})
        send(self(), {:tool_result, task.id, result})
      end)

    {:ok, pid}
  end

  defp execute_generic(task, _thought, _execution_state) do
    Logger.debug("Generic execution of task #{task.id}")

    # Start a generic task executor process
    pid =
      spawn_link(fn ->
        # Simulate task execution
        Process.sleep(1000)

        # Send completion message
        send(self(), {:task_completed, task.id, %{status: :success}})
      end)

    {:ok, pid}
  end

  defp execute_with_options(task, thought, execution_state, opts) do
    # Merge options with default execution
    input = build_execution_input(task, thought, execution_state)
    input_with_opts = Map.put(input, :options, opts)

    execute_direct(%{task | metadata: input_with_opts}, thought, execution_state)
  end

  defp execute_with_modified_input(task, thought, execution_state, modified_input) do
    # Replace the standard input with modified version
    task_with_input = %{task | metadata: Map.put(task.metadata || %{}, :input, modified_input)}
    execute_direct(task_with_input, thought, execution_state)
  end

  # Helper functions

  defp has_workflow?(%{metadata: %{workflow: _}}), do: true
  defp has_workflow?(%{execution_type: :workflow}), do: true
  defp has_workflow?(_), do: false

  defp has_engine?(%{metadata: %{engine: _}}), do: true
  defp has_engine?(%{execution_type: :engine}), do: true
  defp has_engine?(_), do: false

  defp has_tool?(%{metadata: %{tool: _}}), do: true
  defp has_tool?(%{execution_type: :tool}), do: true
  defp has_tool?(_), do: false

  defp get_workflow_module(%{metadata: %{workflow: module}}), do: module
  defp get_workflow_module(%{workflow_module: module}), do: module
  defp get_workflow_module(_), do: RubberDuck.Workflows.GenericWorkflow

  defp get_engine_name(%{metadata: %{engine: name}}), do: name
  defp get_engine_name(%{engine_name: name}), do: name
  defp get_engine_name(_), do: :default_engine

  defp get_tool_name(%{metadata: %{tool: name}}), do: name
  defp get_tool_name(%{tool_name: name}), do: name
  defp get_tool_name(_), do: :generic_tool

  defp build_workflow_input(task, thought, execution_state) do
    %{
      task_id: task.id,
      task_data: extract_task_data(task),
      thought: thought,
      context: build_execution_context(execution_state)
    }
  end

  defp build_engine_input(task, thought, execution_state) do
    %{
      query: task.description,
      metadata: %{
        task_id: task.id,
        thought: thought,
        context: build_execution_context(execution_state)
      }
    }
  end

  defp build_tool_input(task, thought, _execution_state) do
    %{
      action: determine_tool_action(task),
      parameters: extract_tool_parameters(task),
      metadata: %{
        task_id: task.id,
        thought_confidence: thought.confidence
      }
    }
  end

  defp build_execution_input(task, thought, execution_state) do
    %{
      task: task,
      thought: thought,
      state: execution_state
    }
  end

  defp build_execution_context(execution_state) do
    %{
      completed_tasks: MapSet.to_list(execution_state.completed_tasks),
      current_phase: determine_execution_phase(execution_state),
      resource_status: get_resource_status(execution_state)
    }
  end

  defp extract_task_data(%{metadata: %{data: data}}), do: data
  defp extract_task_data(%{data: data}), do: data
  defp extract_task_data(task), do: Map.from_struct(task)

  defp determine_tool_action(%{metadata: %{action: action}}), do: action
  defp determine_tool_action(%{name: name}), do: String.to_atom(name)
  defp determine_tool_action(_), do: :execute

  defp extract_tool_parameters(%{metadata: %{parameters: params}}), do: params
  defp extract_tool_parameters(%{parameters: params}), do: params
  defp extract_tool_parameters(_), do: %{}

  defp validate_prerequisites(task, execution_state) do
    validators = [
      &validate_dependencies_completed(&1, &2),
      &validate_resources_available(&1, &2),
      &validate_no_conflicts(&1, &2)
    ]

    Enum.reduce_while(validators, :ok, fn validator, _acc ->
      case validator.(task, execution_state) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_dependencies_completed(%{dependencies: nil}, _), do: :ok
  defp validate_dependencies_completed(%{dependencies: []}, _), do: :ok

  defp validate_dependencies_completed(%{dependencies: deps}, execution_state) do
    incomplete = Enum.reject(deps, &MapSet.member?(execution_state.completed_tasks, &1))

    if Enum.empty?(incomplete) do
      :ok
    else
      {:error, {:incomplete_dependencies, incomplete}}
    end
  end

  defp validate_resources_available(_task, _execution_state) do
    # TODO: Implement resource validation
    :ok
  end

  defp validate_no_conflicts(_task, _execution_state) do
    # TODO: Implement conflict detection
    :ok
  end

  # 10 minutes
  defp extended_timeout(%{complexity: :very_complex}), do: 600_000
  # 5 minutes
  defp extended_timeout(%{complexity: :complex}), do: 300_000
  # 2 minutes
  defp extended_timeout(_), do: 120_000

  defp get_task_timeout(task) do
    task.metadata[:timeout] || extended_timeout(task)
  end

  defp calculate_retry_delay(task, execution_state) do
    retry_count = get_retry_count(execution_state, task.id)
    # 1 second
    base_delay = 1000

    # Exponential backoff with jitter
    delay = base_delay * :math.pow(2, retry_count)
    jitter = :rand.uniform(500)

    # Max 30 seconds
    trunc(min(delay + jitter, 30_000))
  end

  defp get_retry_count(execution_state, task_id) do
    execution_state.history
    |> Map.get(:retries, %{})
    |> Map.get(task_id, 0)
  end

  defp apply_fixes(task, _thought, execution_state) do
    last_failure = get_last_failure(execution_state, task.id)

    case last_failure do
      %{reason: :invalid_input, details: details} ->
        fix_invalid_input(task, details)

      %{reason: :missing_data, details: details} ->
        add_missing_data(task, details)

      _ ->
        # No specific fixes, return original input
        extract_task_data(task)
    end
  end

  defp get_last_failure(execution_state, task_id) do
    execution_state.history
    |> Map.get(:failures, %{})
    |> Map.get(task_id, [])
    |> List.first()
  end

  defp fix_invalid_input(task, details) do
    # Apply input corrections based on failure details
    input = extract_task_data(task)

    Enum.reduce(details[:invalid_fields] || [], input, fn field, acc ->
      Map.put(acc, field, sanitize_field_value(field, Map.get(acc, field)))
    end)
  end

  defp add_missing_data(task, details) do
    # Add missing required data
    input = extract_task_data(task)

    Enum.reduce(details[:missing_fields] || [], input, fn field, acc ->
      Map.put(acc, field, get_default_value(field))
    end)
  end

  defp sanitize_field_value(field, value) do
    # Field-specific sanitization logic
    case field do
      :timeout when is_integer(value) -> max(value, 1000)
      :retries when is_integer(value) -> min(max(value, 0), 10)
      _ -> value
    end
  end

  defp get_default_value(field) do
    # Field-specific default values
    case field do
      :timeout -> 60_000
      :retries -> 3
      :priority -> :normal
      _ -> nil
    end
  end

  defp determine_modifications(task, execution_state) do
    attempts = get_attempt_count(execution_state, task.id)

    base_opts = [
      monitor: true,
      checkpoint_enabled: attempts > 1
    ]

    # Add modifications based on attempt count
    cond do
      attempts > 3 ->
        base_opts ++ [fallback_mode: true, simplified_execution: true]

      attempts > 1 ->
        base_opts ++ [verbose_logging: true, debug_mode: true]

      true ->
        base_opts
    end
  end

  defp get_attempt_count(execution_state, task_id) do
    execution_state.history
    |> Map.get(:attempts, %{})
    |> Map.get(task_id, [])
    |> length()
  end

  defp determine_execution_phase(execution_state) do
    total = MapSet.size(execution_state.all_tasks || MapSet.new())
    completed = MapSet.size(execution_state.completed_tasks)

    percentage = if total > 0, do: completed / total, else: 0

    cond do
      percentage < 0.25 -> :initial
      percentage < 0.75 -> :middle
      percentage < 0.95 -> :final
      true -> :completion
    end
  end

  defp get_resource_status(_execution_state) do
    # TODO: Implement actual resource monitoring
    %{
      cpu: :normal,
      memory: :normal,
      io: :normal
    }
  end
end
