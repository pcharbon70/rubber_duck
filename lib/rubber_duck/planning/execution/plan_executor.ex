defmodule RubberDuck.Planning.Execution.PlanExecutor do
  @moduledoc """
  GenServer for executing plans using the ReAct (Reasoning-Acting) framework.

  The PlanExecutor manages the execution lifecycle of plans and tasks,
  coordinating the ReAct loop of Thought → Action → Observation → Adjustment.

  ## Features

  - Dynamic plan execution with reasoning
  - Concurrent task execution with dependency management
  - Real-time monitoring and progress tracking
  - Failure recovery and rollback capabilities
  - Integration with workflow engine and critics
  """

  use GenServer
  require Logger

  alias RubberDuck.Planning.Plan

  alias RubberDuck.Planning.Execution.{
    ThoughtGenerator,
    ActionExecutor,
    ObservationCollector,
    PlanAdjuster,
    ExecutionState,
    History
  }

  alias RubberDuck.Status

  # 5 minutes
  @default_timeout 300_000
  # 1 minute
  @checkpoint_interval 60_000

  # Client API

  @doc """
  Starts a new plan executor process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:execution_id]))
  end

  @doc """
  Executes a plan with the given options.
  """
  def execute_plan(executor, plan, opts \\ []) do
    GenServer.call(executor, {:execute_plan, plan, opts}, execution_timeout(opts))
  end

  @doc """
  Gets the current execution state.
  """
  def get_state(executor) do
    GenServer.call(executor, :get_state)
  end

  @doc """
  Pauses the execution.
  """
  def pause(executor) do
    GenServer.call(executor, :pause)
  end

  @doc """
  Resumes a paused execution.
  """
  def resume(executor) do
    GenServer.call(executor, :resume)
  end

  @doc """
  Cancels the execution.
  """
  def cancel(executor, reason \\ :user_cancelled) do
    GenServer.call(executor, {:cancel, reason})
  end

  @doc """
  Triggers a rollback to a previous checkpoint.
  """
  def rollback(executor, checkpoint_id) do
    GenServer.call(executor, {:rollback, checkpoint_id})
  end

  @doc """
  Gets the execution history.
  """
  def get_history(executor) do
    GenServer.call(executor, :get_history)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    execution_id = Keyword.get(opts, :execution_id, generate_execution_id())

    state = %{
      execution_id: execution_id,
      status: :initialized,
      plan: nil,
      current_tasks: %{},
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      execution_state: ExecutionState.new(execution_id),
      history: History.new(),
      options: opts,
      checkpoints: [],
      monitors: %{},
      start_time: nil,
      end_time: nil
    }

    # Schedule periodic checkpointing
    schedule_checkpoint()

    {:ok, state}
  end

  @impl true
  def handle_call({:execute_plan, plan, opts}, from, state) do
    Logger.info("Starting execution of plan #{plan.id}")

    # Initialize execution
    state = %{
      state
      | plan: plan,
        status: :running,
        start_time: DateTime.utc_now(),
        options: Keyword.merge(state.options, opts)
    }

    # Start execution in a separate process to avoid blocking
    Elixir.Task.start_link(fn ->
      result = execute_plan_async(state)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, build_execution_state(state), state}
  end

  def handle_call(:pause, _from, %{status: :running} = state) do
    Logger.info("Pausing execution #{state.execution_id}")
    state = %{state | status: :paused}
    broadcast_status_update(state)
    {:reply, :ok, state}
  end

  def handle_call(:pause, _from, state) do
    {:reply, {:error, "Cannot pause execution in #{state.status} state"}, state}
  end

  def handle_call(:resume, _from, %{status: :paused} = state) do
    Logger.info("Resuming execution #{state.execution_id}")
    state = %{state | status: :running}
    broadcast_status_update(state)
    continue_execution(state)
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    {:reply, {:error, "Cannot resume execution in #{state.status} state"}, state}
  end

  def handle_call({:cancel, reason}, _from, state) do
    Logger.info("Cancelling execution #{state.execution_id}: #{reason}")
    state = cancel_execution(state, reason)
    {:reply, :ok, state}
  end

  def handle_call({:rollback, checkpoint_id}, _from, state) do
    case perform_rollback(state, checkpoint_id) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_history, _from, state) do
    {:reply, History.export(state.history), state}
  end

  @impl true
  def handle_info(:checkpoint, state) do
    state = create_checkpoint(state)
    schedule_checkpoint()
    {:noreply, state}
  end

  def handle_info({:task_completed, task_id, result}, state) do
    state = handle_task_completion(state, task_id, result)
    {:noreply, state}
  end

  def handle_info({:task_failed, task_id, error}, state) do
    state = handle_task_failure(state, task_id, error)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    state = handle_process_down(state, ref, reason)
    {:noreply, state}
  end

  # Private Functions

  defp execute_plan_async(state) do
    try do
      # Load tasks for the plan
      tasks = load_plan_tasks(state.plan)

      # Initialize execution state
      state = %{state | execution_state: ExecutionState.initialize(state.execution_state, tasks)}

      # Start the ReAct loop
      final_state = react_loop(state, tasks)

      # Return execution result
      build_execution_result(final_state)
    rescue
      error ->
        Logger.error("Execution failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp react_loop(state, tasks) do
    case state.status do
      :running ->
        # Get next executable tasks
        executable_tasks = get_executable_tasks(state, tasks)

        if Enum.empty?(executable_tasks) and all_tasks_completed?(state, tasks) do
          # All tasks completed
          complete_execution(state, :success)
        else
          # Execute ReAct cycle for each executable task
          state =
            Enum.reduce(executable_tasks, state, fn task, acc_state ->
              if acc_state.status == :running do
                execute_react_cycle(acc_state, task)
              else
                acc_state
              end
            end)

          # Continue loop after a short delay
          Process.sleep(100)
          react_loop(state, tasks)
        end

      :paused ->
        # Wait until resumed
        Process.sleep(1000)
        react_loop(state, tasks)

      _ ->
        # Execution stopped
        state
    end
  end

  defp execute_react_cycle(state, task) do
    Logger.debug("Executing ReAct cycle for task #{task.id}")

    # 1. Thought: Analyze the task and current state
    thought = ThoughtGenerator.generate_thought(task, state)
    state = record_thought(state, task, thought)

    # 2. Action: Execute the task based on the thought
    case ActionExecutor.execute_action(task, thought, state) do
      {:ok, action_ref} ->
        _updated_state = track_task_execution(state, task, action_ref)

      {:error, reason} ->
        handle_task_failure(state, task.id, reason)
    end
  end

  defp get_executable_tasks(state, tasks) do
    tasks
    |> Enum.filter(fn task ->
      task_id = task.id

      # Task must not be completed or failed
      # All dependencies must be completed
      not MapSet.member?(state.completed_tasks, task_id) and
        not MapSet.member?(state.failed_tasks, task_id) and
        not Map.has_key?(state.current_tasks, task_id) and
        all_dependencies_met?(task, state.completed_tasks)
    end)
    |> Enum.take(max_concurrent_tasks(state))
  end

  defp all_dependencies_met?(%{dependencies: nil}, _), do: true
  defp all_dependencies_met?(%{dependencies: []}, _), do: true

  defp all_dependencies_met?(%{dependencies: deps}, completed_tasks) do
    Enum.all?(deps, &MapSet.member?(completed_tasks, &1))
  end

  defp all_tasks_completed?(state, tasks) do
    task_ids = MapSet.new(tasks, & &1.id)
    MapSet.equal?(state.completed_tasks, task_ids)
  end

  defp handle_task_completion(state, task_id, result) do
    Logger.info("Task #{task_id} completed successfully")

    # 3. Observation: Collect and analyze results
    observation = ObservationCollector.collect_observation(task_id, result, state)
    state = record_observation(state, task_id, observation)

    # 4. Adjust: Potentially adjust the plan based on observations
    case PlanAdjuster.analyze_and_adjust(state.plan, observation, state) do
      {:ok, adjusted_plan} ->
        _updated_state = %{state | plan: adjusted_plan}
        Logger.info("Plan adjusted based on task #{task_id} results")

      :no_adjustment_needed ->
        :ok
    end

    # Update state
    %{
      state
      | completed_tasks: MapSet.put(state.completed_tasks, task_id),
        current_tasks: Map.delete(state.current_tasks, task_id)
    }
    |> broadcast_progress_update()
  end

  defp handle_task_failure(state, task_id, error) do
    Logger.error("Task #{task_id} failed: #{inspect(error)}")

    # Record failure
    state = record_failure(state, task_id, error)

    # Attempt recovery
    case apply_recovery_strategy(state, task_id, error) do
      {:retry, new_state} ->
        Logger.info("Retrying task #{task_id}")
        new_state

      {:skip, skip_state} ->
        Logger.warning("Skipping failed task #{task_id}")

        %{
          skip_state
          | failed_tasks: MapSet.put(skip_state.failed_tasks, task_id),
            current_tasks: Map.delete(skip_state.current_tasks, task_id)
        }

      {:abort, new_state} ->
        Logger.error("Aborting execution due to task #{task_id} failure")
        cancel_execution(new_state, {:task_failed, task_id})
    end
  end

  defp apply_recovery_strategy(state, task_id, _error) do
    # TODO: Implement sophisticated recovery strategies
    # For now, simple retry logic
    retry_count = get_retry_count(state, task_id)
    max_retries = get_in(state.options, [:max_retries]) || 3

    cond do
      retry_count < max_retries ->
        {:retry, increment_retry_count(state, task_id)}

      # Allow some skip attempts
      retry_count < max_retries + 2 ->
        {:skip, state}

      true ->
        {:abort, state}
    end
  end

  defp complete_execution(state, result) do
    Logger.info("Execution #{state.execution_id} completed: #{result}")

    %{state | status: :completed, end_time: DateTime.utc_now()}
    |> broadcast_completion(result)
  end

  defp cancel_execution(state, reason) do
    # TODO: Implement proper cleanup and rollback
    %{state | status: :cancelled, end_time: DateTime.utc_now()}
    |> broadcast_cancellation(reason)
  end

  defp create_checkpoint(state) do
    checkpoint = %{
      id: generate_checkpoint_id(),
      timestamp: DateTime.utc_now(),
      state: ExecutionState.snapshot(state.execution_state),
      completed_tasks: state.completed_tasks,
      failed_tasks: state.failed_tasks
    }

    %{state | checkpoints: [checkpoint | state.checkpoints]}
  end

  defp perform_rollback(state, checkpoint_id) do
    case Enum.find(state.checkpoints, &(&1.id == checkpoint_id)) do
      nil ->
        {:error, "Checkpoint not found"}

      checkpoint ->
        # TODO: Implement actual rollback logic
        {:ok, restore_from_checkpoint(state, checkpoint)}
    end
  end

  # Helper functions

  defp via_tuple(execution_id) do
    {:via, Registry, {RubberDuck.ExecutorRegistry, execution_id}}
  end

  defp generate_execution_id do
    "exec_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp generate_checkpoint_id do
    "ckpt_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp execution_timeout(opts) do
    Keyword.get(opts, :timeout, @default_timeout)
  end

  defp max_concurrent_tasks(state) do
    get_in(state.options, [:max_concurrent_tasks]) || 5
  end

  defp schedule_checkpoint do
    Process.send_after(self(), :checkpoint, @checkpoint_interval)
  end

  defp load_plan_tasks(%Plan{} = _plan) do
    # TODO: Load tasks from plan
    # For now, return empty list
    []
  end

  defp track_task_execution(state, task, action_ref) do
    # Monitor the action process
    monitor_ref = Process.monitor(action_ref)

    %{
      state
      | current_tasks: Map.put(state.current_tasks, task.id, action_ref),
        monitors: Map.put(state.monitors, monitor_ref, task.id)
    }
  end

  defp handle_process_down(state, ref, reason) do
    case Map.get(state.monitors, ref) do
      nil ->
        state

      task_id ->
        handle_task_failure(state, task_id, {:process_died, reason})
    end
  end

  defp get_retry_count(state, task_id) do
    History.get_retry_count(state.history, task_id)
  end

  defp increment_retry_count(state, task_id) do
    %{state | history: History.increment_retry(state.history, task_id)}
  end

  defp record_thought(state, task, thought) do
    %{state | history: History.record_thought(state.history, task.id, thought)}
  end

  defp record_observation(state, task_id, observation) do
    %{state | history: History.record_observation(state.history, task_id, observation)}
  end

  defp record_failure(state, task_id, error) do
    %{state | history: History.record_failure(state.history, task_id, error)}
  end

  defp restore_from_checkpoint(state, checkpoint) do
    %{
      state
      | execution_state: ExecutionState.restore(state.execution_state, checkpoint.state),
        completed_tasks: checkpoint.completed_tasks,
        failed_tasks: checkpoint.failed_tasks
    }
  end

  defp continue_execution(state) do
    # TODO: Resume execution from current state
    state
  end

  # Status broadcasting

  defp broadcast_status_update(state) do
    Status.broadcast(
      "execution:#{state.execution_id}",
      :status_changed,
      %{status: state.status}
    )

    state
  end

  defp broadcast_progress_update(state) do
    Status.broadcast(
      "execution:#{state.execution_id}",
      :progress_update,
      build_progress_info(state)
    )

    state
  end

  defp broadcast_completion(state, result) do
    Status.broadcast(
      "execution:#{state.execution_id}",
      :execution_completed,
      %{result: result, state: build_execution_state(state)}
    )

    state
  end

  defp broadcast_cancellation(state, reason) do
    Status.broadcast(
      "execution:#{state.execution_id}",
      :execution_cancelled,
      %{reason: reason, state: build_execution_state(state)}
    )

    state
  end

  defp build_execution_state(state) do
    %{
      execution_id: state.execution_id,
      status: state.status,
      plan_id: state.plan && state.plan.id,
      progress: build_progress_info(state),
      start_time: state.start_time,
      end_time: state.end_time,
      checkpoints: length(state.checkpoints)
    }
  end

  defp build_progress_info(state) do
    total_tasks = if state.plan, do: length(load_plan_tasks(state.plan)), else: 0

    %{
      total_tasks: total_tasks,
      completed_tasks: MapSet.size(state.completed_tasks),
      failed_tasks: MapSet.size(state.failed_tasks),
      current_tasks: map_size(state.current_tasks),
      completion_percentage: calculate_completion_percentage(state, total_tasks)
    }
  end

  defp calculate_completion_percentage(state, total_tasks) when total_tasks > 0 do
    completed = MapSet.size(state.completed_tasks)
    Float.round(completed / total_tasks * 100, 1)
  end

  defp calculate_completion_percentage(_, _), do: 0.0

  defp build_execution_result(state) do
    {:ok,
     %{
       execution_id: state.execution_id,
       status: state.status,
       completed_tasks: MapSet.to_list(state.completed_tasks),
       failed_tasks: MapSet.to_list(state.failed_tasks),
       duration: calculate_duration(state),
       checkpoints: length(state.checkpoints),
       history: History.summary(state.history)
     }}
  end

  defp calculate_duration(%{start_time: start, end_time: end_time}) when not is_nil(start) do
    end_time = end_time || DateTime.utc_now()
    DateTime.diff(end_time, start, :second)
  end

  defp calculate_duration(_), do: 0
end
