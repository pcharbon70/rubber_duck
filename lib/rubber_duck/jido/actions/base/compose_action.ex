defmodule RubberDuck.Jido.Actions.Base.ComposeAction do
  @moduledoc """
  Base action for composing multiple actions into a single execution flow.
  
  This action allows chaining multiple actions together, passing the
  agent state from one action to the next. It supports error handling,
  conditional execution, and result aggregation.
  """
  
  use Jido.Action,
    name: "compose",
    description: "Composes multiple actions into a single execution flow",
    schema: [
      actions: [
        type: {:list, :map},
        required: true,
        doc: "List of action definitions to execute in sequence"
      ],
      stop_on_error: [
        type: :boolean,
        default: true,
        doc: "Whether to stop execution on first error"
      ],
      parallel: [
        type: :boolean,
        default: false,
        doc: "Execute actions in parallel (when possible)"
      ],
      aggregate_results: [
        type: :boolean,
        default: true,
        doc: "Collect all action results"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    actions = params.actions
    stop_on_error? = params.stop_on_error != false
    parallel? = params.parallel
    aggregate? = params.aggregate_results != false
    
    if parallel? do
      run_parallel(actions, context, stop_on_error?, aggregate?)
    else
      run_sequential(actions, context, stop_on_error?, aggregate?)
    end
  end
  
  # Private functions
  
  defp run_sequential(actions, context, stop_on_error?, aggregate?) do
    initial_acc = %{
      agent: context.agent,
      results: [],
      errors: [],
      executed_count: 0
    }
    
    final_acc = Enum.reduce_while(actions, initial_acc, fn action_def, acc ->
      case execute_action(action_def, %{context | agent: acc.agent}) do
        {:ok, result, %{agent: updated_agent}} ->
          new_acc = %{acc |
            agent: updated_agent,
            results: if(aggregate?, do: acc.results ++ [result], else: acc.results),
            executed_count: acc.executed_count + 1
          }
          {:cont, new_acc}
          
        {:error, reason} ->
          new_acc = %{acc |
            errors: acc.errors ++ [{action_def.action, reason}],
            executed_count: acc.executed_count + 1
          }
          
          if stop_on_error? do
            {:halt, new_acc}
          else
            {:cont, new_acc}
          end
      end
    end)
    
    if Enum.empty?(final_acc.errors) do
      {:ok, %{
        executed: final_acc.executed_count,
        results: final_acc.results
      }, %{agent: final_acc.agent}}
    else
      if stop_on_error? do
        {:error, hd(final_acc.errors)}
      else
        {:ok, %{
          executed: final_acc.executed_count,
          results: final_acc.results,
          errors: final_acc.errors
        }, %{agent: final_acc.agent}}
      end
    end
  end
  
  defp run_parallel(actions, context, _stop_on_error?, aggregate?) do
    # Note: Parallel execution doesn't update agent state between actions
    # Each action gets the original agent state
    
    tasks = Enum.map(actions, fn action_def ->
      Task.async(fn ->
        case execute_action(action_def, context) do
          {:ok, result, _} -> {:ok, result}
          {:error, reason} -> {:error, {action_def.action, reason}}
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    
    {successes, errors} = Enum.split_with(results, &match?({:ok, _}, &1))
    
    if Enum.empty?(errors) do
      final_results = if aggregate? do
        Enum.map(successes, fn {:ok, result} -> result end)
      else
        []
      end
      
      {:ok, %{
        executed: length(actions),
        results: final_results,
        parallel: true
      }, %{agent: context.agent}}
    else
      {:error, {:parallel_execution_failed, Enum.map(errors, fn {:error, e} -> e end)}}
    end
  end
  
  defp execute_action(action_def, context) do
    action_module = action_def.action
    params = action_def.params || %{}
    
    # Support conditional execution
    if should_execute?(action_def, context) do
      Logger.debug("Executing action: #{inspect(action_module)}")
      action_module.run(params, context)
    else
      Logger.debug("Skipping action: #{inspect(action_module)} (condition not met)")
      {:ok, %{skipped: true}, %{agent: context.agent}}
    end
  end
  
  defp should_execute?(%{condition: condition_fn}, context) when is_function(condition_fn, 1) do
    condition_fn.(context)
  end
  
  defp should_execute?(_action_def, _context), do: true
end