defmodule RubberDuck.Jido.Actions.Workflow.FanoutAction do
  @moduledoc """
  Fanout action for parallel broadcast execution with Jido signal coordination.
  
  This action broadcasts the same input to multiple actions in parallel, collecting
  all results. It supports different aggregation strategies, timeout handling,
  and signal-based coordination.
  
  ## Example
  
      params = %{
        targets: [
          %{action: NotifySlackAction, params: %{channel: "#alerts"}},
          %{action: LogToFileAction, params: %{file: "alerts.log"}},
          %{action: SendEmailAction, params: %{to: "admin@example.com"}}
        ],
        input_data: %{alert: "System critical", level: :error},
        aggregation: :all_success  # :all_success, :any_success, :collect_all
      }
      
      {:ok, result} = FanoutAction.run(params, context)
  """
  
  use Jido.Action,
    name: "fanout",
    description: "Broadcasts to multiple actions in parallel",
    schema: [
      targets: [
        type: {:list, :map},
        required: true,
        doc: "List of target actions to execute in parallel"
      ],
      input_data: [
        type: :any,
        default: %{},
        doc: "Data to broadcast to all targets"
      ],
      aggregation: [
        type: :atom,
        default: :collect_all,
        values: [:all_success, :any_success, :collect_all, :race],
        doc: "How to aggregate results from parallel execution"
      ],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Maximum time to wait for all targets in milliseconds"
      ],
      max_concurrency: [
        type: :pos_integer,
        default: 10,
        doc: "Maximum number of concurrent executions"
      ],
      emit_target_signals: [
        type: :boolean,
        default: true,
        doc: "Whether to emit signals for each target execution"
      ],
      fanout_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this fanout execution"
      ]
    ]
  
  require Logger
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  @impl true
  def run(params, context) do
    fanout_id = params.fanout_id || "fanout_#{System.unique_integer([:positive])}"
    
    Logger.info("Starting fanout execution: #{fanout_id} to #{length(params.targets)} targets")
    
    # Emit fanout start signal
    emit_fanout_signal("fanout.started", fanout_id, %{
      targets_count: length(params.targets),
      aggregation: params.aggregation,
      input_data: params.input_data
    }, context.agent)
    
    # Execute fanout based on concurrency settings
    start_time = System.monotonic_time(:millisecond)
    
    results = if params.max_concurrency >= length(params.targets) do
      # Execute all in parallel
      execute_all_parallel(params.targets, params.input_data, context, fanout_id, params)
    else
      # Execute in batches
      execute_batched(params.targets, params.input_data, context, fanout_id, params)
    end
    
    duration = System.monotonic_time(:millisecond) - start_time
    
    # Aggregate results based on strategy
    case aggregate_results(results, params.aggregation) do
      {:ok, aggregated} ->
        # Emit fanout completion signal
        emit_fanout_signal("fanout.completed", fanout_id, %{
          targets_executed: length(params.targets),
          successful: count_successful(results),
          failed: count_failed(results),
          duration: duration,
          aggregation: params.aggregation
        }, context.agent)
        
        {:ok, %{
          fanout_id: fanout_id,
          aggregation: params.aggregation,
          targets_executed: length(params.targets),
          successful: count_successful(results),
          failed: count_failed(results),
          duration: duration,
          results: aggregated
        }, %{agent: context.agent}}
        
      {:error, reason} ->
        # Emit fanout failure signal
        emit_fanout_signal("fanout.failed", fanout_id, %{
          error: reason,
          partial_results: results,
          duration: duration
        }, context.agent)
        
        {:error, %{
          fanout_id: fanout_id,
          error: reason,
          partial_results: results
        }}
    end
  end
  
  # Private functions
  
  defp execute_all_parallel(targets, input_data, context, fanout_id, params) do
    targets
    |> Enum.with_index(1)
    |> Enum.map(fn {target, index} ->
      Task.async(fn ->
        execute_target(target, index, input_data, context, fanout_id, params)
      end)
    end)
    |> wait_for_tasks(params.timeout, params.aggregation)
  end
  
  defp execute_batched(targets, input_data, context, fanout_id, params) do
    targets
    |> Enum.with_index(1)
    |> Enum.chunk_every(params.max_concurrency)
    |> Enum.flat_map(fn batch ->
      batch
      |> Enum.map(fn {target, index} ->
        Task.async(fn ->
          execute_target(target, index, input_data, context, fanout_id, params)
        end)
      end)
      |> wait_for_tasks(params.timeout, params.aggregation)
    end)
  end
  
  defp execute_target(target, index, input_data, context, fanout_id, params) do
    target_id = "#{fanout_id}_target_#{index}"
    
    Logger.debug("Executing fanout target #{index}: #{inspect(target.action)}")
    
    # Build target parameters
    target_params = Map.merge(
      Map.get(target, :params, %{}),
      %{input_data: input_data}
    )
    
    # Execute the target action
    start_time = System.monotonic_time(:millisecond)
    
    result = try do
      case target.action.run(target_params, context) do
        {:ok, result, _updated_context} ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Emit target success signal if enabled
          if params.emit_target_signals do
            emit_target_signal("fanout.target.completed", target_id, %{
              target_index: index,
              action: target.action,
              duration: duration
            }, context.agent)
          end
          
          %{
            target_index: index,
            action: target.action,
            status: :success,
            result: result,
            duration: duration
          }
          
        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Emit target failure signal if enabled
          if params.emit_target_signals do
            emit_target_signal("fanout.target.failed", target_id, %{
              target_index: index,
              action: target.action,
              error: reason,
              duration: duration
            }, context.agent)
          end
          
          %{
            target_index: index,
            action: target.action,
            status: :error,
            error: reason,
            duration: duration
          }
      end
    rescue
      error ->
        Logger.error("Fanout target crashed: #{inspect(error)}")
        
        %{
          target_index: index,
          action: target.action,
          status: :crashed,
          error: error,
          duration: System.monotonic_time(:millisecond) - start_time
        }
    end
    
    result
  end
  
  defp wait_for_tasks(tasks, timeout, :race) do
    # Return first completed task
    case Task.yield_many(tasks, timeout) do
      [] -> []
      results ->
        results
        |> Enum.find(fn {_task, result} -> result != nil end)
        |> case do
          {_task, {:ok, result}} -> [result]
          _ -> []
        end
    end
  end
  
  defp wait_for_tasks(tasks, timeout, _aggregation) do
    # Wait for all tasks up to timeout
    tasks
    |> Task.yield_many(timeout)
    |> Enum.map(fn
      {task, {:ok, result}} -> 
        result
      {task, {:exit, reason}} -> 
        %{status: :crashed, error: {:exit, reason}}
      {task, nil} ->
        Task.shutdown(task, :brutal_kill)
        %{status: :timeout, error: :timeout}
    end)
  end
  
  defp aggregate_results(results, :all_success) do
    if Enum.all?(results, fn r -> r.status == :success end) do
      {:ok, Enum.map(results, fn r -> r.result end)}
    else
      errors = results
        |> Enum.filter(fn r -> r.status != :success end)
        |> Enum.map(fn r -> {r.action, r.error} end)
      {:error, {:not_all_successful, errors}}
    end
  end
  
  defp aggregate_results(results, :any_success) do
    successful = Enum.filter(results, fn r -> r.status == :success end)
    if Enum.any?(successful) do
      {:ok, Enum.map(successful, fn r -> r.result end)}
    else
      {:error, :none_successful}
    end
  end
  
  defp aggregate_results(results, :race) do
    # Return first result (already filtered by wait_for_tasks)
    case results do
      [result | _] when result.status == :success -> {:ok, result.result}
      [result | _] -> {:error, result.error}
      [] -> {:error, :no_results}
    end
  end
  
  defp aggregate_results(results, :collect_all) do
    # Return all results regardless of status
    {:ok, results}
  end
  
  defp count_successful(results) do
    Enum.count(results, fn r -> r.status == :success end)
  end
  
  defp count_failed(results) do
    Enum.count(results, fn r -> r.status != :success end)
  end
  
  defp emit_fanout_signal(type, fanout_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :fanout_id, fanout_id),
      source: "fanout:#{fanout_id}"
    }, %{agent: agent})
  end
  
  defp emit_target_signal(type, target_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :target_id, target_id),
      source: "fanout_target:#{target_id}"
    }, %{agent: agent})
  end
end