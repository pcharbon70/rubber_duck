defmodule RubberDuck.Jido.Workflows.ScatterGather do
  @moduledoc """
  A scatter-gather workflow that distributes work across multiple agents.
  
  This workflow demonstrates:
  - Parallel agent execution using map
  - Dynamic agent selection
  - Result aggregation
  - Partial failure handling
  
  ## Inputs
  
  - `:data` - List of items to process
  - `:worker_tag` - Tag to identify worker agents
  - `:aggregation_strategy` - How to aggregate results (:all, :partial)
  
  ## Example
  
      {:ok, results} = WorkflowCoordinator.execute_workflow(
        ScatterGather,
        %{
          data: [chunk1, chunk2, chunk3],
          worker_tag: :data_processor,
          aggregation_strategy: :partial
        }
      )
  """
  
  use Reactor
  
  alias RubberDuck.Jido.Steps.{ExecuteAgentAction, SelectAgent}
  
  input :data
  input :worker_tag
  input :aggregation_strategy do
    transform &(&1 || :all)
  end
  
  # Create a pool of workers if needed
  step :ensure_workers do
    argument :tag, input(:worker_tag)
    argument :required_count do
      source input(:data)
      transform &length/1
    end
    
    run fn arguments ->
      agents = RubberDuck.Jido.Agents.Registry.find_by_tag(arguments.tag)
      
      if length(agents) >= arguments.required_count do
        {:ok, :sufficient_workers}
      else
        # In a real implementation, we might spawn more workers here
        {:ok, :using_available_workers}
      end
    end
  end
  
  # Process each data chunk in parallel
  map :process_chunks do
    source input(:data)
    
    # Select a worker for this chunk
    step :select_worker, SelectAgent do
      argument :criteria do
        source input(:worker_tag)
        transform &{:tag, &1}
      end
      argument :strategy, value(:least_loaded)
    end
    
    # Execute processing on the selected worker
    step :process, ExecuteAgentAction do
      argument :agent_id, result(:select_worker)
      argument :action, value(RubberDuck.Actions.ProcessChunkAction)
      argument :params do
        source element(:process_chunks)
        transform &%{chunk: &1, index: Process.get(:chunk_index, 0)}
      end
    end
    
    # Return the process result
    return :process
  end
  
  # Aggregate results based on strategy
  step :aggregate_results do
    argument :results, result(:process_chunks)
    argument :strategy, input(:aggregation_strategy)
    
    run fn arguments ->
      case arguments.strategy do
        :all ->
          # Require all chunks to succeed
          if Enum.all?(arguments.results, &match?({:ok, _}, &1)) do
            successful = Enum.map(arguments.results, fn {:ok, result} -> result end)
            {:ok, %{status: :complete, results: successful}}
          else
            errors = Enum.filter(arguments.results, &match?({:error, _}, &1))
            {:error, {:partial_failure, errors}}
          end
          
        :partial ->
          # Accept partial results
          {successful, failed} = Enum.split_with(arguments.results, &match?({:ok, _}, &1))
          successful_results = Enum.map(successful, fn {:ok, result} -> result end)
          
          {:ok, %{
            status: :partial,
            successful: length(successful),
            failed: length(failed),
            results: successful_results
          }}
      end
    end
  end
  
  # Return aggregated results
  return :aggregate_results
  
  # Middleware for telemetry
  middlewares do
    middleware Reactor.Middleware.Telemetry
  end
end