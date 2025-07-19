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

  alias RubberDuck.Workflows.{Registry, Cache, Metrics, ComplexityAnalyzer, DynamicBuilder}
  alias RubberDuck.Status

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

  @doc """
  Executes a workflow directly without going through GenServer.

  This is used by the hybrid workflow architecture for direct execution.
  """
  def execute_workflow(workflow_name, input, context, opts) do
    workflow_id = "hybrid_#{Ash.UUID.generate()}"

    # Build a merged context
    full_context =
      Map.merge(context, %{
        workflow_id: workflow_id,
        trace_id: opts[:trace_id] || Ash.UUID.generate(),
        metadata: opts[:metadata] || %{}
      })

    # Execute the workflow privately
    execute_workflow_internal(workflow_id, workflow_name, input, Keyword.put(opts, :context, full_context))
  end

  @doc """
  Executes a dynamic workflow generated from a task description.

  The task will be analyzed for complexity and a workflow will be
  dynamically generated and executed.
  """
  def run_dynamic(task, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(__MODULE__, {:run_dynamic, task, opts}, timeout)
  end

  @doc """
  Executes a dynamic workflow asynchronously.
  """
  def run_dynamic_async(task, opts \\ []) do
    GenServer.cast(__MODULE__, {:run_dynamic_async, task, opts})
  end

  @doc """
  Executes a workflow with monitoring and detailed metrics collection.

  Returns both the result and detailed execution metrics including:
  - Step timings
  - Resource adjustments
  - Memory usage
  - Performance data
  """
  def run_with_monitoring(workflow, input \\ %{}, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    GenServer.call(__MODULE__, {:run_with_monitoring, workflow, input, opts}, timeout)
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
        execute_workflow_internal(workflow_id, workflow, input, opts)
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
      from: from,
      type: :static
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
  def handle_call({:run_dynamic, task, opts}, from, state) do
    workflow_id = generate_workflow_id(state)

    # Start dynamic workflow execution
    execution_task =
      Task.async(fn ->
        execute_dynamic_workflow(workflow_id, task, opts)
      end)

    # Track running workflow
    workflow_info = %{
      id: workflow_id,
      workflow: :dynamic,
      input: task,
      opts: opts,
      task: execution_task,
      started_at: DateTime.utc_now(),
      status: :running,
      from: from,
      type: :dynamic
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
  def handle_call({:run_with_monitoring, workflow, input, opts}, from, state) do
    workflow_id = generate_workflow_id(state)

    # Start workflow execution with monitoring
    execution_task =
      Task.async(fn ->
        execute_workflow_with_monitoring(workflow_id, workflow, input, opts)
      end)

    # Track running workflow
    workflow_info = %{
      id: workflow_id,
      workflow: workflow,
      input: input,
      opts: opts,
      task: execution_task,
      started_at: DateTime.utc_now(),
      status: :running,
      from: from,
      type: :monitored,
      monitoring: true
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
      result = execute_workflow_internal(workflow_id, workflow, input, opts)

      # Send result to any registered handlers
      if handler = opts[:on_complete] do
        handler.(result)
      end
    end)

    new_state = %{state | workflow_counter: state.workflow_counter + 1}

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:run_dynamic_async, task, opts}, state) do
    workflow_id = generate_workflow_id(state)

    # Start dynamic workflow execution without tracking the caller
    Task.start(fn ->
      result = execute_dynamic_workflow(workflow_id, task, opts)

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

  defp execute_workflow_internal(workflow_id, workflow, input, opts) do
    start_time = System.monotonic_time(:millisecond)
    conversation_id = opts[:conversation_id] || get_in(opts, [:context, :conversation_id])
    
    # Get workflow name early so it's available in rescue block
    workflow_name = workflow_name(workflow)

    try do
      # Resolve workflow module
      workflow_module = resolve_workflow(workflow)

      # Send workflow start status
      Status.workflow(
        conversation_id,
        "Starting workflow: #{workflow_name}",
        Status.build_workflow_metadata(workflow_name, 0, 0, %{
          workflow_id: workflow_id,
          stage: "initialization"
        })
      )

      # Get workflow steps
      steps = workflow_module.steps()
      total_steps = length(steps)

      # Build Reactor using Builder API
      reactor = build_reactor(steps, input)

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

      # Send completion status
      Status.with_timing(
        conversation_id,
        :workflow,
        "Completed workflow: #{workflow_name}",
        start_time,
        Status.build_workflow_metadata(workflow_name, total_steps, total_steps, %{
          workflow_id: workflow_id,
          stage: "completed",
          cache_hit: opts[:use_cache] && result != :miss
        })
      )

      # Record metrics
      Metrics.record_workflow_execution(workflow_id, workflow_module, duration, :success)

      {:ok, result}
    rescue
      e ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.error("Workflow #{workflow_id} failed: #{inspect(e)}")

        # Send error status
        Status.error(
          conversation_id,
          "Workflow failed: #{workflow_name}",
          Status.build_error_metadata(:workflow_error, Exception.message(e), %{
            workflow_id: workflow_id,
            workflow_name: workflow_name,
            duration_ms: duration
          })
        )

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

  # Build a reactor using the correct Builder API
  defp build_reactor(steps, input) do
    # Start with empty reactor
    reactor = Reactor.Builder.new()

    # Add input arguments if provided
    reactor =
      if is_map(input) do
        Enum.reduce(input, reactor, fn {key, _value}, acc ->
          case Reactor.Builder.add_input(acc, key) do
            {:ok, updated_reactor} -> updated_reactor
            # Skip invalid inputs
            {:error, _} -> acc
          end
        end)
      else
        case Reactor.Builder.add_input(reactor, :input) do
          {:ok, updated_reactor} -> updated_reactor
          {:error, _} -> reactor
        end
      end

    # Add steps to the reactor
    reactor =
      Enum.reduce(steps, reactor, fn step, acc ->
        case Reactor.Builder.add_step(acc, step.name, step.impl, step.arguments || []) do
          {:ok, updated_reactor} -> updated_reactor
          # Skip invalid steps
          {:error, _} -> acc
        end
      end)

    # Set return value to the last step if steps exist
    if length(steps) > 0 do
      last_step = List.last(steps)

      case Reactor.Builder.return(reactor, last_step.name) do
        {:ok, final_reactor} -> final_reactor
        {:error, _} -> reactor
      end
    else
      reactor
    end
  end

  # Dynamic workflow execution
  defp execute_workflow_with_monitoring(workflow_id, workflow, input, opts) do
    start_time = System.monotonic_time(:millisecond)
    initial_memory = :erlang.memory(:total)

    # Track step timings
    _step_timings = []
    _resource_adjustments = []

    # Enhanced context with monitoring hooks
    monitoring_context = %{
      on_step_start: fn step_name ->
        send(self(), {:step_start, step_name, System.monotonic_time(:millisecond)})
      end,
      on_step_complete: fn step_name, duration ->
        send(self(), {:step_complete, step_name, duration})
      end,
      on_resource_adjustment: fn adjustment ->
        send(self(), {:resource_adjustment, adjustment})
      end
    }

    # Merge monitoring context with options
    enhanced_opts = Keyword.update(opts, :context, monitoring_context, &Map.merge(&1, monitoring_context))

    # Execute workflow with monitoring
    {result, monitoring_data} =
      Task.async(fn ->
        # Run in a separate process to collect monitoring data
        parent = self()

        Task.async(fn ->
          # Execute the workflow
          workflow_result = execute_workflow_internal(workflow_id, workflow, input, enhanced_opts)
          send(parent, {:workflow_result, workflow_result})
        end)

        # Collect monitoring data
        collect_monitoring_data([], [], start_time)
      end)
      |> Task.await(opts[:timeout] || @default_timeout)

    end_time = System.monotonic_time(:millisecond)
    final_memory = :erlang.memory(:total)

    # Build comprehensive result
    case result do
      {:ok, workflow_result} ->
        {:ok,
         %{
           result: workflow_result,
           step_timings: monitoring_data.step_timings,
           resource_adjustments: monitoring_data.resource_adjustments,
           metadata: %{
             workflow_id: workflow_id,
             total_duration: end_time - start_time,
             memory_delta: final_memory - initial_memory,
             monitored: true
           }
         }}

      {:error, _} = error ->
        error
    end
  end

  defp collect_monitoring_data(step_timings, resource_adjustments, start_time) do
    receive do
      {:step_start, step_name, timestamp} ->
        updated_timings = [{step_name, timestamp - start_time} | step_timings]
        collect_monitoring_data(updated_timings, resource_adjustments, start_time)

      {:step_complete, step_name, duration} ->
        updated_timings = [{step_name, duration} | step_timings]
        collect_monitoring_data(updated_timings, resource_adjustments, start_time)

      {:resource_adjustment, adjustment} ->
        updated_adjustments = [adjustment | resource_adjustments]
        collect_monitoring_data(step_timings, updated_adjustments, start_time)

      {:workflow_result, result} ->
        {result,
         %{
           step_timings: Enum.reverse(step_timings),
           resource_adjustments: Enum.reverse(resource_adjustments)
         }}
    after
      60_000 ->
        {{:error, :timeout},
         %{
           step_timings: Enum.reverse(step_timings),
           resource_adjustments: Enum.reverse(resource_adjustments)
         }}
    end
  end

  defp execute_dynamic_workflow(workflow_id, task, opts) do
    start_time = System.monotonic_time(:millisecond)

    try do
      Logger.info("Starting dynamic workflow generation for #{workflow_id}")

      # Analyze task complexity
      historical_data = opts[:historical_data]
      analysis = ComplexityAnalyzer.analyze(task, historical_data)

      Logger.debug("Task analysis for #{workflow_id}: #{inspect(analysis)}")

      # Build dynamic workflow
      build_opts = [
        use_template: opts[:use_template] != false,
        optimization_strategy: opts[:optimization_strategy] || :balanced,
        include_resource_management: opts[:include_resource_management] || false,
        customization: opts[:customization] || %{}
      ]

      case DynamicBuilder.build(task, analysis, build_opts) do
        {:ok, reactor} ->
          # Execute the dynamically built workflow
          Logger.info("Executing dynamic workflow #{workflow_id}")

          # Convert task to input map
          input = task_to_input(task)

          result = Reactor.run(reactor, input, context: build_dynamic_context(workflow_id, task, analysis, opts))

          duration = System.monotonic_time(:millisecond) - start_time

          # Record metrics for dynamic workflow
          Metrics.record_workflow_execution(workflow_id, :dynamic_workflow, duration, :success)

          Logger.info("Dynamic workflow #{workflow_id} completed successfully in #{duration}ms")

          # Store successful pattern for future reuse
          if opts[:cache_pattern] do
            cache_successful_pattern(task, analysis, build_opts, duration)
          end

          {:ok, result}

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          Logger.error("Failed to build dynamic workflow #{workflow_id}: #{inspect(reason)}")

          Metrics.record_workflow_execution(workflow_id, :dynamic_workflow, duration, :build_failure)

          {:error, {:workflow_build_failed, reason}}
      end
    rescue
      e ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.error("Dynamic workflow #{workflow_id} failed: #{inspect(e)}")

        # Record metrics
        Metrics.record_workflow_execution(workflow_id, :dynamic_workflow, duration, :failure)

        {:error, e}
    end
  end

  defp task_to_input(task) when is_map(task) do
    # Convert task fields to reactor inputs
    task
    |> Map.drop([:type, :id, :metadata])
    |> Enum.into(%{})
  end

  defp task_to_input(task), do: %{input: task}

  defp build_dynamic_context(workflow_id, task, analysis, opts) do
    %{
      workflow_id: workflow_id,
      trace_id: opts[:trace_id] || Ash.UUID.generate(),
      workflow_type: :dynamic,
      task_type: Map.get(task, :type, :unknown),
      complexity_score: Map.get(analysis, :complexity_score, 5),
      resource_requirements: Map.get(analysis, :resource_requirements, %{}),
      optimization_strategy: opts[:optimization_strategy] || :balanced,
      metadata: opts[:metadata] || %{},
      logger: opts[:logger] || Logger
    }
  end

  defp cache_successful_pattern(task, analysis, build_opts, duration) do
    # Store the successful pattern for future similar tasks
    pattern = %{
      task_signature: generate_task_signature(task),
      analysis_result: analysis,
      build_options: build_opts,
      performance: %{
        duration: duration,
        success: true
      },
      timestamp: DateTime.utc_now()
    }

    # In a real implementation, this would store to a persistent cache
    # For now, we'll just log it
    Logger.debug("Caching successful workflow pattern: #{inspect(pattern)}")
  end

  defp generate_task_signature(task) do
    # Generate a signature for the task to identify similar tasks
    %{
      type: Map.get(task, :type),
      complexity_indicators: %{
        has_targets: Map.has_key?(task, :targets) || Map.has_key?(task, :target),
        has_options: Map.has_key?(task, :options),
        has_code: Map.has_key?(task, :code)
      }
    }
  end
end
