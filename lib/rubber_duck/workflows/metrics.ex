defmodule RubberDuck.Workflows.Metrics do
  @moduledoc """
  Metrics collection and reporting for workflows.

  Integrates with Telemetry to provide:
  - Execution time tracking
  - Success/failure rates
  - Resource usage metrics
  - Custom business metrics
  """

  require Logger

  @workflow_started [:rubber_duck, :workflow, :started]
  @workflow_completed [:rubber_duck, :workflow, :completed]
  @workflow_failed [:rubber_duck, :workflow, :failed]
  @step_started [:rubber_duck, :workflow, :step, :started]
  @step_completed [:rubber_duck, :workflow, :step, :completed]
  @step_failed [:rubber_duck, :workflow, :step, :failed]

  @doc """
  Records the start of a workflow execution.
  """
  def record_workflow_start(workflow_id, workflow_name, input_size \\ 0) do
    metadata = %{
      workflow_id: workflow_id,
      workflow_name: workflow_name,
      input_size: input_size
    }

    measurements = %{
      system_time: System.system_time()
    }

    :telemetry.execute(@workflow_started, measurements, metadata)
  end

  @doc """
  Records the completion of a workflow execution.
  """
  def record_workflow_completion(workflow_id, workflow_info) do
    duration = calculate_duration(workflow_info.started_at, workflow_info.completed_at)

    metadata = %{
      workflow_id: workflow_id,
      workflow_name: get_workflow_name(workflow_info.workflow),
      status: workflow_info.status,
      step_count: count_steps(workflow_info)
    }

    measurements = %{
      duration: duration,
      system_time: System.system_time()
    }

    event =
      if workflow_info.status == :completed do
        @workflow_completed
      else
        @workflow_failed
      end

    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Records workflow execution with detailed metrics.
  """
  def record_workflow_execution(workflow_id, workflow, duration, status) do
    metadata = %{
      workflow_id: workflow_id,
      workflow_name: get_workflow_name(workflow),
      status: status
    }

    measurements = %{
      duration: duration,
      system_time: System.system_time()
    }

    event =
      if status == :success do
        @workflow_completed
      else
        @workflow_failed
      end

    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Records the start of a step execution.
  """
  def record_step_start(workflow_id, step_name) do
    metadata = %{
      workflow_id: workflow_id,
      step_name: step_name
    }

    measurements = %{
      system_time: System.system_time()
    }

    :telemetry.execute(@step_started, measurements, metadata)
  end

  @doc """
  Records the completion of a step execution.
  """
  def record_step_completion(workflow_id, step_name, duration, status) do
    metadata = %{
      workflow_id: workflow_id,
      step_name: step_name,
      status: status
    }

    measurements = %{
      duration: duration,
      system_time: System.system_time()
    }

    event =
      if status == :success do
        @step_completed
      else
        @step_failed
      end

    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Attaches default handlers for workflow metrics.
  """
  def attach_default_handlers do
    handlers = [
      {[:rubber_duck, :workflow, :started], &handle_workflow_started/4},
      {[:rubber_duck, :workflow, :completed], &handle_workflow_completed/4},
      {[:rubber_duck, :workflow, :failed], &handle_workflow_failed/4},
      {[:rubber_duck, :workflow, :step, :started], &handle_step_started/4},
      {[:rubber_duck, :workflow, :step, :completed], &handle_step_completed/4},
      {[:rubber_duck, :workflow, :step, :failed], &handle_step_failed/4}
    ]

    Enum.each(handlers, fn {event, handler} ->
      handler_id = "#{__MODULE__}-#{Enum.join(event, "-")}"

      :telemetry.attach(
        handler_id,
        event,
        handler,
        nil
      )
    end)
  end

  @doc """
  Creates a custom metric for business-specific measurements.
  """
  def record_custom_metric(workflow_id, metric_name, value, metadata \\ %{}) do
    base_metadata = %{
      workflow_id: workflow_id,
      metric_name: metric_name
    }

    measurements = %{
      value: value,
      system_time: System.system_time()
    }

    :telemetry.execute(
      [:rubber_duck, :workflow, :custom, metric_name],
      measurements,
      Map.merge(base_metadata, metadata)
    )
  end

  # Handler implementations

  defp handle_workflow_started(_event, _measurements, metadata, _config) do
    Logger.info("Workflow started",
      workflow_id: metadata.workflow_id,
      workflow_name: metadata.workflow_name,
      input_size: metadata.input_size
    )
  end

  defp handle_workflow_completed(_event, measurements, metadata, _config) do
    Logger.info("Workflow completed",
      workflow_id: metadata.workflow_id,
      workflow_name: metadata.workflow_name,
      duration_ms: measurements.duration,
      step_count: metadata.step_count
    )
  end

  defp handle_workflow_failed(_event, measurements, metadata, _config) do
    Logger.error("Workflow failed",
      workflow_id: metadata.workflow_id,
      workflow_name: metadata.workflow_name,
      duration_ms: measurements.duration
    )
  end

  defp handle_step_started(_event, _measurements, metadata, _config) do
    Logger.debug("Step started",
      workflow_id: metadata.workflow_id,
      step_name: metadata.step_name
    )
  end

  defp handle_step_completed(_event, measurements, metadata, _config) do
    Logger.debug("Step completed",
      workflow_id: metadata.workflow_id,
      step_name: metadata.step_name,
      duration_ms: measurements.duration
    )
  end

  defp handle_step_failed(_event, measurements, metadata, _config) do
    Logger.warning("Step failed",
      workflow_id: metadata.workflow_id,
      step_name: metadata.step_name,
      duration_ms: measurements.duration
    )
  end

  # Private helpers

  defp get_workflow_name(workflow) when is_atom(workflow) do
    workflow |> to_string() |> String.split(".") |> List.last()
  end

  defp get_workflow_name(workflow) when is_binary(workflow), do: workflow

  defp get_workflow_name(%{name: name}), do: to_string(name)

  defp calculate_duration(started_at, completed_at) do
    DateTime.diff(completed_at, started_at, :millisecond)
  end

  defp count_steps(workflow_info) do
    case workflow_info do
      %{result: %{results: results}} -> map_size(results)
      _ -> 0
    end
  end

  defmodule Aggregator do
    @moduledoc """
    Aggregates workflow metrics for reporting and analysis.
    """

    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def get_stats(workflow_name \\ nil) do
      GenServer.call(__MODULE__, {:get_stats, workflow_name})
    end

    @impl true
    def init(_opts) do
      state = %{
        workflows: %{},
        global: %{
          total_executions: 0,
          successful_executions: 0,
          failed_executions: 0,
          total_duration: 0
        }
      }

      # Subscribe to telemetry events
      :telemetry.attach_many(
        "#{__MODULE__}-aggregator",
        [
          [:rubber_duck, :workflow, :completed],
          [:rubber_duck, :workflow, :failed]
        ],
        &handle_event/4,
        nil
      )

      {:ok, state}
    end

    @impl true
    def handle_call({:get_stats, workflow_name}, _from, state) do
      stats =
        if workflow_name do
          Map.get(state.workflows, workflow_name, empty_stats())
        else
          state.global
        end

      {:reply, stats, state}
    end

    defp handle_event([:rubber_duck, :workflow, status], measurements, metadata, _config) do
      GenServer.cast(__MODULE__, {:update_stats, status, measurements, metadata})
    end

    defp empty_stats do
      %{
        total_executions: 0,
        successful_executions: 0,
        failed_executions: 0,
        total_duration: 0,
        average_duration: 0
      }
    end
  end
end
