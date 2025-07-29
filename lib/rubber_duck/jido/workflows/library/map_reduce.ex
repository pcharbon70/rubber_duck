defmodule RubberDuck.Jido.Workflows.Library.MapReduce do
  @moduledoc """
  Distributed map-reduce workflow pattern.
  
  This workflow distributes data across multiple agents for parallel processing
  (map phase) and then aggregates the results (reduce phase).
  
  ## Required Inputs
  
  - `:data` - List of items to process
  - `:map_fn` - Function to apply to each item
  - `:reduce_fn` - Function to aggregate results
  
  ## Optional Inputs
  
  - `:batch_size` - Number of items per agent (default: 10)
  - `:agent_count` - Number of agents to use (default: auto)
  - `:timeout` - Timeout per operation in ms (default: 30000)
  
  ## Example
  
      inputs = %{
        data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        map_fn: fn x -> x * x end,
        reduce_fn: fn results -> Enum.sum(results) end,
        batch_size: 3
      }
      
      {:ok, result} = RubberDuck.Jido.Workflows.Library.run_workflow(:map_reduce, inputs)
      # result => 385 (sum of squares)
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{SelectAgent, ExecuteAgentAction}
  
  input :data
  input :map_action  
  input :reduce_action
  input :chunk_size
  
  step :validate_inputs do
    argument :data, input(:data)
    argument :map_action, input(:map_action)
    argument :reduce_action, input(:reduce_action)
    
    run fn %{data: data, map_action: map_action, reduce_action: reduce_action} ->
      with :ok <- validate_data(data),
           :ok <- validate_action(map_action),
           :ok <- validate_action(reduce_action) do
        {:ok, :valid}
      else
        {:error, reason} -> {:error, {:validation_failed, reason}}
      end
    end
  end
  
  step :partition_data do
    argument :data, input(:data)
    argument :batch_size, input(:chunk_size)
    
    run fn %{data: data, chunk_size: chunk_size} ->
      batch_size = chunk_size || 10
      batches = Enum.chunk_every(data, batch_size)
      
      {:ok, %{
        batches: batches,
        batch_count: length(batches)
      }}
    end
  end
  
  step :select_map_agents, SelectAgent do
    argument :capabilities, value([:computation])
    argument :strategy, value(:round_robin)
  end
  
  step :distribute_map_tasks do
    argument :batches, result(:partition_data, [:batches])
    argument :agents, result(:select_map_agents)
    argument :map_action, input(:map_action)
    
    run fn %{batches: batches, agents: agents, map_action: map_action} ->
      # Create tasks for each batch-agent pair
      tasks = batches
      |> Enum.zip(Stream.cycle(agents))
      |> Enum.map(fn {batch, agent_id} ->
        %{
          agent_id: agent_id,
          batch: batch,
          map_action: map_action
        }
      end)
      
      {:ok, tasks}
    end
  end
  
  step :execute_map_phase do
    argument :tasks, result(:distribute_map_tasks)
    
    run fn %{tasks: tasks} ->
      timeout = 30_000
      
      # Execute map tasks in parallel
      results = tasks
      |> Task.async_stream(
        fn task ->
          params = %{
            data: task.batch
          }
          
          case ExecuteAgentAction.run(
            %{agent_id: task.agent_id, action: task.map_action, params: params},
            %{},
            timeout: timeout
          ) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, {task.agent_id, reason}}
          end
        end,
        max_concurrency: 10,
        timeout: timeout + 1000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
      end)
      
      # Check for errors
      errors = Enum.filter(results, &match?({:error, _}, &1))
      
      if Enum.empty?(errors) do
        mapped_results = Enum.flat_map(results, fn {:ok, result} -> result end)
        {:ok, mapped_results}
      else
        {:error, {:map_phase_failed, errors}}
      end
    end
  end
  
  step :select_reduce_agent, SelectAgent do
    argument :capabilities, value([:aggregation])
    argument :strategy, value(:least_loaded)
  end
  
  step :execute_reduce_phase, ExecuteAgentAction do
    argument :agent_id, result(:select_reduce_agent)
    argument :action, input(:reduce_action)
    argument :params, value(%{data: result(:execute_map_phase)})
  end
  
  return :execute_reduce_phase
  
  # Helper functions
  
  defp validate_data(data) when is_list(data), do: :ok
  defp validate_data(_), do: {:error, :data_must_be_list}
  
  defp validate_action(action) when is_atom(action), do: :ok
  defp validate_action(_), do: {:error, :action_must_be_atom}
  
  @doc false
  def required_inputs do
    [:data, :map_action, :reduce_action]
  end
  
  @doc false
  def available_options do
    [
      batch_size: "Number of items per agent batch",
      agent_count: "Number of agents to use",
      timeout: "Timeout per operation in milliseconds"
    ]
  end
end