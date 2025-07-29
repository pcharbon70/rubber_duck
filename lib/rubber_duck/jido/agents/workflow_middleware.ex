defmodule RubberDuck.Jido.Agents.WorkflowMiddleware do
  @moduledoc """
  Custom Reactor middleware for integrating workflows with the agent telemetry system.
  
  This middleware:
  - Emits telemetry events for workflow and step execution
  - Tracks agent interactions within workflows
  - Collects performance metrics
  - Provides debugging information
  """
  
  use Reactor.Middleware
  
  alias RubberDuck.Jido.Agents.Metrics
  
  @impl true
  def init(context) do
    # Initialize middleware state
    state = %{
      workflow_id: context[:workflow_id] || generate_id(),
      start_time: System.monotonic_time(:microsecond),
      step_timings: %{},
      agent_interactions: []
    }
    
    # Emit workflow start event
    :telemetry.execute(
      [:rubber_duck, :workflow, :middleware, :init],
      %{count: 1},
      %{workflow_id: state.workflow_id}
    )
    
    {:ok, Map.put(context, :middleware_state, state)}
  end
  
  @impl true
  def event({:start_step, step}, context, _) do
    state = context.middleware_state
    step_id = step_identifier(step)
    
    # Track step start time
    new_state = put_in(state.step_timings[step_id], %{
      start: System.monotonic_time(:microsecond),
      step_name: step.name,
      step_impl: step.impl
    })
    
    # Emit step start event
    :telemetry.execute(
      [:rubber_duck, :workflow, :step, :start],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        step_type: step_type(step),
        async: step.async?
      }
    )
    
    {:ok, Map.put(context, :middleware_state, new_state)}
  end
  
  @impl true
  def event({:complete_step, step, result}, context, _) do
    state = context.middleware_state
    step_id = step_identifier(step)
    
    # Calculate step duration
    timing = state.step_timings[step_id]
    duration = System.monotonic_time(:microsecond) - timing.start
    
    # Update state
    new_timing = Map.put(timing, :duration, duration)
    new_state = put_in(state.step_timings[step_id], new_timing)
    
    # Track agent interactions
    new_state = if is_agent_step?(step) do
      interaction = extract_agent_interaction(step, result)
      update_in(new_state.agent_interactions, &[interaction | &1])
    else
      new_state
    end
    
    # Emit step complete event
    :telemetry.execute(
      [:rubber_duck, :workflow, :step, :complete],
      %{duration: duration},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        step_type: step_type(step),
        success: match?({:ok, _}, result),
        agent_interaction: is_agent_step?(step)
      }
    )
    
    # Record metrics
    if is_agent_step?(step) do
      Metrics.record_action(
        new_state.agent_interactions |> List.first() |> Map.get(:agent_id),
        step.name,
        duration,
        if(match?({:ok, _}, result), do: :success, else: :error)
      )
    end
    
    {:ok, Map.put(context, :middleware_state, new_state)}
  end
  
  @impl true
  def event({:error_step, step, errors}, context, _) do
    state = context.middleware_state
    step_id = step_identifier(step)
    
    # Calculate step duration if we have timing
    duration = case state.step_timings[step_id] do
      %{start: start} -> System.monotonic_time(:microsecond) - start
      _ -> 0
    end
    
    # Emit error event
    :telemetry.execute(
      [:rubber_duck, :workflow, :step, :error],
      %{duration: duration, error_count: length(errors)},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        step_type: step_type(step),
        errors: errors
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event({:retry_step, step, error}, context, _) do
    state = context.middleware_state
    
    # Emit retry event
    :telemetry.execute(
      [:rubber_duck, :workflow, :step, :retry],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        step_type: step_type(step),
        error: error
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event({:compensate_start, step, error}, context, _) do
    state = context.middleware_state
    
    # Emit compensation start event
    :telemetry.execute(
      [:rubber_duck, :workflow, :compensation, :start],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        error: error
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event({:compensate_complete, step, result}, context, _) do
    state = context.middleware_state
    
    # Emit compensation complete event
    :telemetry.execute(
      [:rubber_duck, :workflow, :compensation, :complete],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        success: result == :ok
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event({:undo_start, step, value}, context, _) do
    state = context.middleware_state
    
    # Emit undo start event
    :telemetry.execute(
      [:rubber_duck, :workflow, :undo, :start],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        value: inspect(value, limit: 50)
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event({:undo_complete, step, result}, context, _) do
    state = context.middleware_state
    
    # Emit undo complete event
    :telemetry.execute(
      [:rubber_duck, :workflow, :undo, :complete],
      %{count: 1},
      %{
        workflow_id: state.workflow_id,
        step_name: step.name,
        success: result == :ok
      }
    )
    
    {:ok, context}
  end
  
  @impl true
  def event(_event, context, _) do
    # Ignore other events
    {:ok, context}
  end
  
  @impl true
  def complete(result, context) do
    state = context.middleware_state
    duration = System.monotonic_time(:microsecond) - state.start_time
    
    # Calculate statistics
    step_stats = calculate_step_stats(state.step_timings)
    agent_stats = calculate_agent_stats(state.agent_interactions)
    
    # Emit workflow complete event
    :telemetry.execute(
      [:rubber_duck, :workflow, :complete],
      Map.merge(%{duration: duration}, step_stats),
      %{
        workflow_id: state.workflow_id,
        success: match?({:ok, _}, result),
        total_steps: map_size(state.step_timings),
        agent_interactions: length(state.agent_interactions),
        agent_stats: agent_stats
      }
    )
    
    {:ok, result}
  end
  
  @impl true
  def error(errors, context) do
    state = context.middleware_state
    duration = System.monotonic_time(:microsecond) - state.start_time
    
    # Emit workflow error event
    :telemetry.execute(
      [:rubber_duck, :workflow, :error],
      %{duration: duration, error_count: length(errors)},
      %{
        workflow_id: state.workflow_id,
        errors: errors,
        completed_steps: map_size(state.step_timings)
      }
    )
    
    :ok
  end
  
  @impl true
  def halt(context) do
    state = context.middleware_state
    duration = System.monotonic_time(:microsecond) - state.start_time
    
    # Emit workflow halt event
    :telemetry.execute(
      [:rubber_duck, :workflow, :halt],
      %{duration: duration},
      %{
        workflow_id: state.workflow_id,
        completed_steps: map_size(state.step_timings),
        agent_interactions: length(state.agent_interactions)
      }
    )
    
    :ok
  end
  
  # Private functions
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp step_identifier(step) do
    "#{step.name}_#{:erlang.phash2(step)}"
  end
  
  defp step_type(step) do
    cond do
      is_agent_step?(step) -> :agent
      match?(%{impl: {_, :map, _}}, step) -> :map
      match?(%{impl: {_, :compose, _}}, step) -> :compose
      match?(%{impl: {_, :switch, _}}, step) -> :switch
      true -> :regular
    end
  end
  
  defp is_agent_step?(step) do
    case step.impl do
      {module, _, _} ->
        module in [
          RubberDuck.Jido.Steps.ExecuteAgentAction,
          RubberDuck.Jido.Steps.SelectAgent,
          RubberDuck.Jido.Steps.SendAgentSignal,
          RubberDuck.Jido.Steps.WaitForAgentResponse
        ]
      _ -> false
    end
  end
  
  defp extract_agent_interaction(step, result) do
    # Extract agent information from step arguments and result
    %{
      step_name: step.name,
      agent_id: get_agent_id(step, result),
      timestamp: System.system_time(:microsecond),
      success: match?({:ok, _}, result)
    }
  end
  
  defp get_agent_id(step, result) do
    # Try to extract agent_id from various sources
    cond do
      Map.has_key?(step.arguments, :agent_id) ->
        step.arguments.agent_id
        
      is_tuple(result) and tuple_size(result) == 2 and 
        elem(result, 0) == :ok and is_binary(elem(result, 1)) ->
        elem(result, 1)
        
      true ->
        "unknown"
    end
  end
  
  defp calculate_step_stats(step_timings) do
    durations = step_timings
    |> Map.values()
    |> Enum.map(& &1[:duration])
    |> Enum.filter(&is_number/1)
    
    if Enum.empty?(durations) do
      %{
        total_step_time: 0,
        avg_step_time: 0,
        max_step_time: 0,
        min_step_time: 0
      }
    else
      %{
        total_step_time: Enum.sum(durations),
        avg_step_time: Enum.sum(durations) / length(durations),
        max_step_time: Enum.max(durations),
        min_step_time: Enum.min(durations)
      }
    end
  end
  
  defp calculate_agent_stats(interactions) do
    by_agent = Enum.group_by(interactions, & &1.agent_id)
    
    Enum.map(by_agent, fn {agent_id, agent_interactions} ->
      success_count = Enum.count(agent_interactions, & &1.success)
      total = length(agent_interactions)
      
      {agent_id, %{
        total_interactions: total,
        success_count: success_count,
        error_count: total - success_count,
        success_rate: if(total > 0, do: success_count / total, else: 0)
      }}
    end)
    |> Map.new()
  end
end