defmodule RubberDuck.Workflows.Executor do
  @moduledoc """
  Executes workflows using the Reactor framework.

  Handles:
  - Workflow execution lifecycle
  - Progress tracking
  - Error handling and compensation
  - Result collection
  """

  use GenServer

  require Logger

  alias RubberDuck.Workflows.{Registry, Cache, Metrics}

  # 1 minute
  @default_timeout 60_000

  # Client API

  @doc """
  Starts the workflow executor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a workflow synchronously.
  """
  def run(workflow, input \\ %{}, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(__MODULE__, {:run, workflow, input, opts}, timeout)
  end

  @doc """
  Executes a workflow asynchronously.
  """
  def run_async(workflow, input \\ %{}, opts \\ []) do
    GenServer.cast(__MODULE__, {:run_async, workflow, input, opts})
  end

  @doc """
  Gets the status of a running workflow.
  """
  def get_status(workflow_id) do
    GenServer.call(__MODULE__, {:get_status, workflow_id})
  end

  @doc """
  Cancels a running workflow.
  """
  def cancel(workflow_id, reason \\ :user_cancelled) do
    GenServer.call(__MODULE__, {:cancel, workflow_id, reason})
  end

  @doc """
  Lists running workflows.
  """
  def list_running do
    GenServer.call(__MODULE__, :list_running)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      running_workflows: %{},
      completed_workflows: %{},
      workflow_counter: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:run, workflow, input, opts}, from, state) do
    workflow_id = generate_workflow_id(state)

    # Start workflow execution
    task =
      Task.async(fn ->
        execute_workflow(workflow_id, workflow, input, opts)
      end)

    # Track running workflow
    workflow_info = %{
      id: workflow_id,
      workflow: workflow,
      input: input,
      opts: opts,
      task: task,
      started_at: DateTime.utc_now(),
      status: :running,
      from: from
    }

    new_state = %{
      state
      | running_workflows: Map.put(state.running_workflows, workflow_id, workflow_info),
        workflow_counter: state.workflow_counter + 1
    }

    # We'll reply when the task completes
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_status, workflow_id}, _from, state) do
    status =
      case Map.get(state.running_workflows, workflow_id) do
        nil ->
          case Map.get(state.completed_workflows, workflow_id) do
            nil -> {:error, :not_found}
            info -> {:ok, info.status}
          end

        info ->
          {:ok, info.status}
      end

    {:reply, status, state}
  end

  @impl true
  def handle_call({:cancel, workflow_id, reason}, _from, state) do
    case Map.get(state.running_workflows, workflow_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      workflow_info ->
        # Cancel the task
        Task.shutdown(workflow_info.task, :brutal_kill)

        # Update status
        cancelled_info = %{workflow_info | status: :cancelled, cancelled_at: DateTime.utc_now(), cancel_reason: reason}

        # Move to completed
        new_state = %{
          state
          | running_workflows: Map.delete(state.running_workflows, workflow_id),
            completed_workflows: Map.put(state.completed_workflows, workflow_id, cancelled_info)
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_running, _from, state) do
    running =
      state.running_workflows
      |> Map.values()
      |> Enum.map(fn info ->
        %{
          id: info.id,
          workflow: workflow_name(info.workflow),
          started_at: info.started_at,
          status: info.status
        }
      end)

    {:reply, running, state}
  end

  @impl true
  def handle_cast({:run_async, workflow, input, opts}, state) do
    workflow_id = generate_workflow_id(state)

    # Start workflow execution without tracking the caller
    Task.start(fn ->
      result = execute_workflow(workflow_id, workflow, input, opts)

      # Send result to any registered handlers
      if handler = opts[:on_complete] do
        handler.(result)
      end
    end)

    new_state = %{state | workflow_counter: state.workflow_counter + 1}

    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Handle task completion
    case find_workflow_by_task_ref(state.running_workflows, ref) do
      {workflow_id, workflow_info} ->
        # Reply to original caller if this was a sync call
        if workflow_info.from do
          GenServer.reply(workflow_info.from, result)
        end

        # Update workflow status
        completed_info = %{
          workflow_info
          | status: get_status_from_result(result),
            completed_at: DateTime.utc_now(),
            result: result
        }

        # Move to completed
        new_state = %{
          state
          | running_workflows: Map.delete(state.running_workflows, workflow_id),
            completed_workflows: Map.put(state.completed_workflows, workflow_id, completed_info)
        }

        # Emit metrics
        Metrics.record_workflow_completion(workflow_id, completed_info)

        {:noreply, new_state}

      nil ->
        # Unknown task ref, ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task crashed, handled by task ref message above
    {:noreply, state}
  end

  # Private functions

  defp execute_workflow(workflow_id, workflow, input, opts) do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Resolve workflow module
      workflow_module = resolve_workflow(workflow)

      # Get workflow steps
      steps = workflow_module.steps()

      # Build Reactor
      reactor = Reactor.new(steps)

      # Check cache if enabled
      result =
        if opts[:use_cache] do
          cache_key = Cache.generate_key(workflow_module, input)

          case Cache.get(cache_key) do
            {:ok, cached_result} ->
              Logger.debug("Using cached result for workflow #{workflow_id}")
              cached_result

            :miss ->
              # Execute and cache
              result = Reactor.run(reactor, input, context: build_context(workflow_id, opts))
              Cache.put(cache_key, result, opts[:cache_ttl])
              result
          end
        else
          # Execute without cache
          Reactor.run(reactor, input, context: build_context(workflow_id, opts))
        end

      duration = System.monotonic_time(:millisecond) - start_time

      # Record metrics
      Metrics.record_workflow_execution(workflow_id, workflow_module, duration, :success)

      {:ok, result}
    rescue
      e ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.error("Workflow #{workflow_id} failed: #{inspect(e)}")

        # Record metrics
        Metrics.record_workflow_execution(workflow_id, workflow, duration, :failure)

        {:error, e}
    end
  end

  defp resolve_workflow(workflow) when is_atom(workflow), do: workflow

  defp resolve_workflow(workflow_name) when is_binary(workflow_name) do
    case Registry.lookup(workflow_name) do
      {:ok, info} -> info.module
      {:error, _} -> raise "Unknown workflow: #{workflow_name}"
    end
  end

  defp build_context(workflow_id, opts) do
    %{
      workflow_id: workflow_id,
      trace_id: opts[:trace_id] || Ash.UUID.generate(),
      metadata: opts[:metadata] || %{},
      logger: opts[:logger] || Logger
    }
  end

  defp generate_workflow_id(state) do
    "wf_#{state.workflow_counter}_#{System.unique_integer([:positive])}"
  end

  defp workflow_name(workflow) when is_atom(workflow), do: workflow |> to_string()
  defp workflow_name(workflow) when is_binary(workflow), do: workflow

  defp find_workflow_by_task_ref(workflows, ref) do
    Enum.find_value(workflows, fn {id, info} ->
      if info.task.ref == ref, do: {id, info}
    end)
  end

  defp get_status_from_result({:ok, _}), do: :completed
  defp get_status_from_result({:error, _}), do: :failed
end
