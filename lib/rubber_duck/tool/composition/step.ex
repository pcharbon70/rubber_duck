defmodule RubberDuck.Tool.Composition.Step do
  @moduledoc """
  Reactor step implementation for tool composition workflows.

  This module wraps tool execution in a Reactor step, providing:
  - Integration with RubberDuck's tool execution system
  - Error handling and compensation
  - Data transformation between steps
  - Telemetry and monitoring
  """

  use RubberDuck.Workflows.Step

  alias RubberDuck.Tool.Validator

  require Logger

  @doc """
  Executes a tool within a Reactor step.

  The step receives the tool module, parameters, and any input from previous steps.
  It handles data transformation, validation, and error recovery.

  ## Arguments

  - `tool_module` - The tool module to execute
  - `base_params` - Base parameters for the tool
  - `input` - Input from previous steps (optional)
  - `condition_result` - Result from condition step (for conditional workflows)
  - Additional arguments based on workflow configuration

  ## Context

  - `workflow_id` - Unique identifier for the workflow
  - `trace_id` - Trace identifier for debugging
  - `user_id` - User identifier for audit trail
  - Additional context from workflow execution
  """
  @impl true
  def run(arguments, context) do
    # Extract tool configuration
    case context[:options] do
      [tool_module, base_params] ->
        run_with_tool(tool_module, base_params, arguments, context)

      _ ->
        {:error, {:tool_exception, %MatchError{term: "Missing tool configuration in context"}}}
    end
  end

  defp run_with_tool(tool_module, base_params, arguments, context) do
    # Merge input data with base parameters
    merged_params = merge_step_parameters(base_params, arguments, context)

    # Validate parameters
    case validate_parameters(tool_module, merged_params) do
      {:ok, validated_params} ->
        # Execute the tool with monitoring
        execute_tool_with_monitoring(tool_module, validated_params, context)

      {:error, validation_error} ->
        Logger.error("Parameter validation failed for #{tool_module}: #{inspect(validation_error)}")
        {:error, {:validation_failed, validation_error}}
    end
  end

  @doc """
  Compensates for a failed step execution.

  This is called when a step fails and needs to be rolled back.
  The compensation logic depends on the tool and the nature of the failure.
  """
  @impl true
  def compensate(arguments, result, context) do
    case context[:options] do
      [tool_module, _base_params] ->
        compensate_with_tool(tool_module, arguments, result, context)

      _ ->
        Logger.warning("No tool configuration found for compensation")
        :ok
    end
  end

  defp compensate_with_tool(tool_module, arguments, result, context) do
    Logger.info("Compensating for failed step: #{tool_module}")

    # Check if tool supports compensation
    if function_exported?(tool_module, :compensate, 3) do
      try do
        tool_module.compensate(arguments, result, context)
      rescue
        error ->
          Logger.error("Compensation failed for #{tool_module}: #{inspect(error)}")
          {:error, {:compensation_failed, error}}
      end
    else
      # Default compensation - log the failure
      Logger.warning("No compensation available for #{tool_module}")
      :ok
    end
  end

  # Private helper functions

  defp merge_step_parameters(base_params, arguments, context) do
    # Start with base parameters
    merged = Map.new(base_params)

    # Add input from previous steps
    merged =
      case Map.get(arguments, :input) do
        nil -> merged
        input -> Map.put(merged, :input, input)
      end

    # Add condition result for conditional workflows
    merged =
      case Map.get(arguments, :condition_result) do
        nil -> merged
        condition_result -> Map.put(merged, :condition_result, condition_result)
      end

    # Add any other arguments from the workflow
    merged = Map.merge(merged, Map.drop(arguments, [:input, :condition_result]))

    # Add context information
    merged = Map.put(merged, :context, context)

    merged
  end

  defp validate_parameters(tool_module, params) do
    if function_exported?(tool_module, :validate_parameters, 1) do
      tool_module.validate_parameters(params)
    else
      # Use global validator if available and tool supports it
      if function_exported?(Validator, :validate_parameters, 2) and
           function_exported?(tool_module, :__tool__, 1) do
        Validator.validate_parameters(tool_module, params)
      else
        # No validation available - proceed with params
        {:ok, params}
      end
    end
  end

  defp execute_tool_with_monitoring(tool_module, params, context) do
    workflow_id = Map.get(context, :workflow_id, "unknown")
    step_name = Map.get(context, :step_name, "unknown")

    # Start timing
    start_time = System.monotonic_time()

    # Emit start telemetry
    :telemetry.execute(
      [:rubber_duck, :tool, :composition, :step_start],
      %{count: 1},
      %{
        workflow_id: workflow_id,
        step_name: step_name,
        tool_module: tool_module
      }
    )

    try do
      # Execute the tool
      result =
        case function_exported?(tool_module, :execute, 2) do
          true ->
            tool_module.execute(params, context)

          false ->
            # Try single-arity execute
            if function_exported?(tool_module, :execute, 1) do
              tool_module.execute(params)
            else
              {:error, {:tool_error, "Tool #{tool_module} does not implement execute/1 or execute/2"}}
            end
        end

      # Calculate duration
      duration = System.monotonic_time() - start_time

      # Emit completion telemetry
      case result do
        {:ok, _} ->
          :telemetry.execute(
            [:rubber_duck, :tool, :composition, :step_success],
            %{count: 1, duration: duration},
            %{
              workflow_id: workflow_id,
              step_name: step_name,
              tool_module: tool_module
            }
          )

        {:error, _} ->
          :telemetry.execute(
            [:rubber_duck, :tool, :composition, :step_error],
            %{count: 1, duration: duration},
            %{
              workflow_id: workflow_id,
              step_name: step_name,
              tool_module: tool_module
            }
          )
      end

      result
    rescue
      error ->
        # Calculate duration
        duration = System.monotonic_time() - start_time

        # Emit exception telemetry
        :telemetry.execute(
          [:rubber_duck, :tool, :composition, :step_exception],
          %{count: 1, duration: duration},
          %{
            workflow_id: workflow_id,
            step_name: step_name,
            tool_module: tool_module,
            error: inspect(error)
          }
        )

        Logger.error("Tool execution failed with exception: #{inspect(error)}")
        {:error, {:tool_exception, error}}
    end
  end
end
