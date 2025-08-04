defmodule RubberDuck.Jido.Actions.Workflow.PipelineAction do
  @moduledoc """
  Pipeline action for sequential data transformation with proper Jido signal coordination.
  
  This action executes a series of actions in sequence, piping the output of each
  action as input to the next. It supports signal-based coordination, error handling,
  and transformation functions between stages.
  
  ## Example
  
      params = %{
        stages: [
          %{action: ValidateDataAction, params: %{schema: :user}},
          %{action: TransformDataAction, transform: &normalize_user/1},
          %{action: SaveDataAction, params: %{table: :users}}
        ],
        initial_data: %{name: "John", email: "john@example.com"}
      }
      
      {:ok, result} = PipelineAction.run(params, context)
  """
  
  use Jido.Action,
    name: "pipeline",
    description: "Executes actions in sequence with data piping",
    schema: [
      stages: [
        type: {:list, :map},
        required: true,
        doc: "List of pipeline stages with actions and optional transformations"
      ],
      initial_data: [
        type: :any,
        default: %{},
        doc: "Initial data to pass to first stage"
      ],
      stop_on_error: [
        type: :boolean,
        default: true,
        doc: "Whether to stop pipeline on first error"
      ],
      emit_stage_signals: [
        type: :boolean,
        default: true,
        doc: "Whether to emit signals for each stage completion"
      ],
      pipeline_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this pipeline execution"
      ]
    ]
  
  require Logger
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  @impl true
  def run(params, context) do
    pipeline_id = params.pipeline_id || "pipeline_#{System.unique_integer([:positive])}"
    
    Logger.info("Starting pipeline execution: #{pipeline_id}")
    
    # Emit pipeline start signal
    emit_pipeline_signal("pipeline.started", pipeline_id, %{
      stages_count: length(params.stages),
      initial_data: params.initial_data
    }, context.agent)
    
    # Execute pipeline stages
    result = execute_pipeline(
      params.stages,
      params.initial_data,
      context,
      %{
        pipeline_id: pipeline_id,
        stop_on_error: params.stop_on_error,
        emit_signals: params.emit_stage_signals,
        stage_index: 0,
        results: []
      }
    )
    
    case result do
      {:ok, final_data, execution_state} ->
        # Emit pipeline completion signal
        emit_pipeline_signal("pipeline.completed", pipeline_id, %{
          stages_executed: execution_state.stage_index,
          final_data: final_data,
          duration: calculate_duration(execution_state)
        }, execution_state.agent)
        
        {:ok, %{
          pipeline_id: pipeline_id,
          stages_executed: execution_state.stage_index,
          final_data: final_data,
          stage_results: Enum.reverse(execution_state.results)
        }, %{agent: execution_state.agent}}
        
      {:error, reason, execution_state} ->
        # Emit pipeline failure signal
        emit_pipeline_signal("pipeline.failed", pipeline_id, %{
          failed_at_stage: execution_state.stage_index,
          error: reason,
          partial_results: Enum.reverse(execution_state.results)
        }, execution_state.agent)
        
        {:error, %{
          pipeline_id: pipeline_id,
          failed_at_stage: execution_state.stage_index,
          error: reason,
          partial_results: Enum.reverse(execution_state.results)
        }}
    end
  end
  
  # Private functions
  
  defp execute_pipeline([], data, _context, state) do
    {:ok, data, state}
  end
  
  defp execute_pipeline([stage | rest], data, context, state) do
    stage_index = state.stage_index + 1
    stage_id = "#{state.pipeline_id}_stage_#{stage_index}"
    
    Logger.debug("Executing pipeline stage #{stage_index}: #{inspect(stage.action)}")
    
    # Apply pre-stage transformation if specified
    transformed_data = if Map.has_key?(stage, :transform) && is_function(stage.transform) do
      stage.transform.(data)
    else
      data
    end
    
    # Build stage parameters
    stage_params = Map.merge(
      Map.get(stage, :params, %{}),
      %{input_data: transformed_data}
    )
    
    # Execute the stage action
    start_time = System.monotonic_time(:millisecond)
    
    case execute_stage_action(stage.action, stage_params, %{context | agent: state.agent}) do
      {:ok, result, %{agent: updated_agent}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Extract output data (support different result formats)
        output_data = extract_output_data(result)
        
        # Update state with results
        stage_result = %{
          stage: stage_index,
          action: stage.action,
          input: transformed_data,
          output: output_data,
          duration: duration
        }
        
        new_state = %{state |
          agent: updated_agent,
          stage_index: stage_index,
          results: [stage_result | state.results]
        }
        
        # Emit stage completion signal if enabled
        if state.emit_signals do
          emit_stage_signal("pipeline.stage.completed", stage_id, stage_result, updated_agent)
        end
        
        # Continue with next stage
        execute_pipeline(rest, output_data, context, new_state)
        
      {:error, reason} ->
        new_state = %{state |
          stage_index: stage_index
        }
        
        # Emit stage failure signal if enabled
        if state.emit_signals do
          emit_stage_signal("pipeline.stage.failed", stage_id, %{
            stage: stage_index,
            action: stage.action,
            error: reason
          }, state.agent)
        end
        
        if state.stop_on_error do
          {:error, reason, new_state}
        else
          # Continue with error as data
          execute_pipeline(rest, {:error, reason}, context, new_state)
        end
    end
  end
  
  defp execute_stage_action(action_module, params, context) do
    try do
      action_module.run(params, context)
    rescue
      error ->
        Logger.error("Pipeline stage crashed: #{inspect(error)}")
        {:error, {:stage_crashed, error}}
    end
  end
  
  defp extract_output_data(%{data: data}), do: data
  defp extract_output_data(%{result: result}), do: result
  defp extract_output_data(%{output: output}), do: output
  defp extract_output_data(%{output_data: output_data}), do: output_data
  defp extract_output_data(%{final_data: final_data}), do: final_data
  defp extract_output_data(result) when is_map(result), do: result
  defp extract_output_data(result), do: result
  
  defp emit_pipeline_signal(type, pipeline_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :pipeline_id, pipeline_id),
      source: "pipeline:#{pipeline_id}"
    }, %{agent: agent})
  end
  
  defp emit_stage_signal(type, stage_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :stage_id, stage_id),
      source: "pipeline_stage:#{stage_id}"
    }, %{agent: agent})
  end
  
  defp calculate_duration(state) do
    # Sum up all stage durations
    state.results
    |> Enum.map(fn result -> Map.get(result, :duration, 0) end)
    |> Enum.sum()
  end
end