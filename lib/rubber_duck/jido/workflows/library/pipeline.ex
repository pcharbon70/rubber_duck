defmodule RubberDuck.Jido.Workflows.Library.Pipeline do
  @moduledoc """
  Sequential processing pipeline workflow.
  
  This workflow processes data through a series of transformation steps,
  with each step potentially using a different agent based on capabilities.
  
  ## Required Inputs
  
  - `:data` - Initial data to process
  - `:steps` - List of processing steps, each with:
    - `:name` - Step identifier
    - `:capability` - Required agent capability
    - `:function` - Transformation function
  
  ## Optional Inputs
  
  - `:checkpoint_after` - List of step names to checkpoint after
  - `:parallel_steps` - Steps that can run in parallel
  - `:timeout` - Timeout per step in ms (default: 30000)
  
  ## Example
  
      inputs = %{
        data: "raw text data",
        steps: [
          %{name: :tokenize, capability: :nlp, function: &Tokenizer.tokenize/1},
          %{name: :analyze, capability: :nlp, function: &Analyzer.analyze/1},
          %{name: :summarize, capability: :llm, function: &Summarizer.summarize/1}
        ],
        checkpoint_after: [:analyze]
      }
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{SelectAgent, ExecuteAgentAction}
  alias RubberDuck.Jido.Agents.WorkflowPersistenceAsh, as: WorkflowPersistence
  
  input :data
  input :stages
  
  step :validate_pipeline do
    argument :stages, input(:stages)
    argument :data, input(:data)
    
    run fn arguments, _context, _options ->
      with :ok <- validate_steps(arguments.stages),
           :ok <- validate_data(arguments.data) do
        {:ok, %{
          stages: arguments.stages,
          step_count: length(arguments.stages)
        }}
      end
    end
  end
  
  step :initialize_pipeline do
    argument :data, input(:data)
    
    run fn arguments, _context, _options ->
      {:ok, %{
        current_data: arguments.data,
        workflow_id: arguments[:workflow_id] || generate_id(),
        completed_steps: [],
        step_results: %{}
      }}
    end
  end
  
  # Dynamic step generation would happen here
  # For demonstration, we'll use a simplified approach
  step :execute_pipeline do
    argument :pipeline_state, result(:initialize_pipeline)
    argument :stages, input(:stages)
    
    run fn arguments, context, _options ->
      execute_steps(
        arguments.steps,
        arguments.pipeline_state,
        arguments[:checkpoint_after] || [],
        arguments[:timeout] || 30_000,
        context
      )
    end
  end
  
  step :finalize_result do
    argument :pipeline_result, result(:execute_pipeline)
    
    run fn arguments, _context, _options ->
      {:ok, arguments.pipeline_result.current_data}
    end
  end
  
  return :finalize_result
  
  # Private functions
  
  defp execute_steps([], state, _checkpoints, _timeout, _context) do
    {:ok, state}
  end
  
  defp execute_steps([step | remaining], state, checkpoints, timeout, context) do
    with {:ok, agent_id} <- select_agent_for_step(step),
         {:ok, result} <- execute_step(agent_id, step, state.current_data, timeout),
         {:ok, new_state} <- update_pipeline_state(state, step, result),
         :ok <- maybe_checkpoint(new_state, step, checkpoints, context) do
      
      execute_steps(remaining, new_state, checkpoints, timeout, context)
    else
      {:error, reason} ->
        {:error, {:pipeline_failed, step.name, reason}}
    end
  end
  
  defp select_agent_for_step(step) do
    case SelectAgent.run(
      %{
        criteria: {:capability, step.capability},
        strategy: :least_loaded
      },
      %{},
      []
    ) do
      {:ok, agent_id} when is_binary(agent_id) -> {:ok, agent_id}
      {:ok, [agent_id | _]} -> {:ok, agent_id}
      {:error, reason} -> {:error, {:agent_selection_failed, reason}}
    end
  end
  
  defp execute_step(agent_id, step, data, timeout) do
    action = %{
      type: :transform,
      step_name: step.name,
      function: step.function,
      data: data
    }
    
    ExecuteAgentAction.run(
      %{
        agent_id: agent_id,
        action: action,
        params: %{}
      },
      %{},
      timeout: timeout
    )
  end
  
  defp update_pipeline_state(state, step, result) do
    new_state = %{state |
      current_data: result,
      completed_steps: state.completed_steps ++ [step.name],
      step_results: Map.put(state.step_results, step.name, result)
    }
    
    {:ok, new_state}
  end
  
  defp maybe_checkpoint(state, step, checkpoints, context) do
    if step.name in checkpoints do
      case WorkflowPersistence.save_checkpoint(
        context[:workflow_id] || state.workflow_id,
        Atom.to_string(step.name),
        state
      ) do
        {:ok, _} -> :ok
        {:error, _} -> :ok  # Don't fail on checkpoint errors
      end
    else
      :ok
    end
  end
  
  defp validate_steps(steps) when is_list(steps) do
    if Enum.all?(steps, &valid_step?/1) do
      :ok
    else
      {:error, :invalid_step_format}
    end
  end
  defp validate_steps(_), do: {:error, :steps_must_be_list}
  
  defp valid_step?(%{name: name, capability: cap, function: fun})
       when is_atom(name) and is_atom(cap) and is_function(fun, 1) do
    true
  end
  defp valid_step?(_), do: false
  
  defp validate_data(_), do: :ok
  
  defp generate_id do
    "pipeline_" <> :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  @doc false
  def required_inputs do
    [:data, :steps]
  end
  
  @doc false
  def available_options do
    [
      checkpoint_after: "List of step names after which to create checkpoints",
      parallel_steps: "Groups of steps that can execute in parallel",
      timeout: "Timeout per step in milliseconds"
    ]
  end
end