defmodule RubberDuck.Jido.Runtime do
  @moduledoc """
  Runtime executor for Jido agents.
  
  This module handles the execution of actions on agents, managing:
  - Action validation and execution
  - State transitions
  - Error handling
  - Lifecycle callbacks
  """
  
  require Logger
  
  @doc """
  Executes an action on an agent.
  
  Handles the complete execution lifecycle:
  1. Pre-execution callbacks
  2. Action validation
  3. Action execution
  4. Post-execution callbacks
  5. Error handling
  """
  @spec execute(map(), module(), map()) :: {:ok, term(), map()} | {:error, term()}
  def execute(agent, action_module, params \\ %{}) do
    start_time = System.monotonic_time(:microsecond)
    
    with {:ok, agent} <- call_before_run(agent),
         {:ok, validated_params} <- validate_action_params(action_module, params),
         {:ok, result, updated_agent} <- run_action(agent, action_module, validated_params),
         {:ok, final_agent} <- call_after_run(updated_agent, result, action_module) do
      
      # Record execution time
      duration = System.monotonic_time(:microsecond) - start_time
      
      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :jido, :runtime, :execute],
        %{duration: duration},
        %{
          agent_id: agent.id,
          action: action_module,
          success: true
        }
      )
      
      {:ok, result, final_agent}
    else
      {:error, reason} = error ->
        # Call error handler
        {:ok, agent} = call_on_error(agent, reason)
        
        # Emit error telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :runtime, :error],
          %{count: 1},
          %{
            agent_id: agent.id,
            action: action_module,
            error: reason
          }
        )
        
        error
    end
  end
  
  @doc """
  Gets runtime status and metrics.
  """
  @spec status() :: map()
  def status do
    %{
      workers: get_worker_status(),
      queue_size: 0, # TODO: Implement action queue
      executions: get_execution_stats()
    }
  end
  
  # Private functions
  
  defp call_before_run(agent) do
    if function_exported?(agent.module, :on_before_run, 1) do
      agent.module.on_before_run(agent)
    else
      {:ok, agent}
    end
  end
  
  defp call_after_run(agent, result, action_module) do
    metadata = %{
      action: action_module,
      timestamp: DateTime.utc_now()
    }
    
    if function_exported?(agent.module, :on_after_run, 3) do
      agent.module.on_after_run(agent, {:ok, result}, metadata)
    else
      {:ok, agent}
    end
  end
  
  defp call_on_error(agent, error) do
    if function_exported?(agent.module, :on_error, 2) do
      agent.module.on_error(agent, error)
    else
      {:ok, agent}
    end
  end
  
  defp validate_action_params(action_module, params) do
    # Check if action module has schema
    if function_exported?(action_module, :__schema__, 0) do
      schema = action_module.__schema__()
      validate_params(params, schema[:schema] || [])
    else
      {:ok, params}
    end
  end
  
  defp validate_params(params, schema) do
    # Simple validation for now
    # TODO: Use NimbleOptions or similar
    errors = Enum.reduce(schema, [], fn {field, opts}, errors ->
      if opts[:required] && !Map.has_key?(params, field) do
        [{field, "is required"} | errors]
      else
        errors
      end
    end)
    
    case errors do
      [] -> {:ok, params}
      errors -> {:error, {:validation_failed, errors}}
    end
  end
  
  defp run_action(agent, action_module, params) do
    # Build context for action
    context = %{
      agent: agent,
      timestamp: DateTime.utc_now()
    }
    
    # Execute the action
    try do
      case action_module.run(params, context) do
        {:ok, result, %{agent: updated_agent}} ->
          # Update agent metadata
          updated_agent = update_agent_metadata(updated_agent)
          {:ok, result, updated_agent}
          
        {:ok, result} ->
          # Action didn't update agent
          {:ok, result, agent}
          
        {:error, _reason} = error ->
          error
          
        other ->
          {:error, {:invalid_action_result, other}}
      end
    rescue
      exception ->
        Logger.error("Action execution failed: #{inspect(exception)}")
        {:error, {:action_crashed, exception}}
    end
  end
  
  defp update_agent_metadata(agent) do
    agent
    |> put_in([:metadata, :updated_at], DateTime.utc_now())
    |> update_in([:metadata, :version], &(&1 + 1))
  end
  
  defp get_worker_status do
    # Placeholder for worker pool status
    %{
      available: 10,
      busy: 0,
      total: 10
    }
  end
  
  defp get_execution_stats do
    # Placeholder for execution statistics
    %{
      total: 0,
      successful: 0,
      failed: 0,
      average_duration_ms: 0
    }
  end
end