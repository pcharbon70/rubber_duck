defmodule RubberDuck.Jido.Workflows.CompositeWorkflow do
  @moduledoc """
  A composite workflow that orchestrates multiple sub-workflows.
  
  This workflow demonstrates:
  - Workflow composition using Reactor's compose step
  - Conditional workflow execution
  - Dynamic workflow selection
  - Cross-workflow state management
  
  ## Inputs
  
  - `:request_type` - Type of request (:simple, :complex, :batch)
  - `:request_data` - The actual request data
  - `:options` - Additional options for workflow execution
  
  ## Example
  
      {:ok, result} = WorkflowCoordinator.execute_workflow(
        CompositeWorkflow,
        %{
          request_type: :complex,
          request_data: %{items: [1, 2, 3], priority: :high},
          options: %{parallel: true}
        }
      )
  """
  
  use Reactor
  require Logger
  
  alias RubberDuck.Jido.Workflows.{SimplePipeline, ScatterGather, TransactionalWorkflow, ValidationWorkflow}
  
  input :request_type
  input :request_data
  input :options do
    transform &(&1 || %{})
  end
  
  # Analyze request to determine workflow strategy
  step :analyze_request do
    argument :type, input(:request_type)
    argument :data, input(:request_data)
    
    run fn arguments ->
      strategy = case arguments.type do
        :simple -> :pipeline
        :complex -> :transactional
        :batch -> :scatter_gather
        _ -> :unknown
      end
      
      complexity = calculate_complexity(arguments.data)
      
      {:ok, %{
        strategy: strategy,
        complexity: complexity,
        requires_validation: complexity > 5
      }}
    end
  end
  
  # Optional validation sub-workflow
  switch :validate_if_needed do
    on result(:analyze_request)
    
    matches? &(&1.requires_validation) do
      compose :validation, ValidationWorkflow do
        argument :data, input(:request_data)
      end
    end
    
    default do
      step :skip_validation do
        run fn _args -> {:ok, :validation_skipped} end
      end
    end
  end
  
  # Main processing based on strategy
  switch :process_request do
    on result(:analyze_request)
    
    # Simple pipeline processing
    matches? &(&1.strategy == :pipeline) do
      compose :pipeline_processing, SimplePipeline do
        argument :data, input(:request_data)
        argument :pipeline_config do
          source input(:options)
          transform &Map.get(&1, :pipeline_config, %{steps: [:validate, :transform, :store]})
        end
      end
    end
    
    # Scatter-gather for batch processing
    matches? &(&1.strategy == :scatter_gather) do
      compose :batch_processing, ScatterGather do
        argument :data do
          source input(:request_data)
          transform &(&1.items || [])
        end
        argument :worker_tag do
          source input(:options)
          transform &(&1.worker_tag || :batch_processor)
        end
        argument :aggregation_strategy do
          source input(:options)
          transform &(&1.aggregation || :partial)
        end
      end
    end
    
    # Transactional processing for complex requests
    matches? &(&1.strategy == :transactional) do
      compose :transaction_processing, TransactionalWorkflow do
        argument :transaction_data, input(:request_data)
        argument :compensation_strategy do
          source input(:options)
          transform &(&1.compensation || :compensate)
        end
      end
    end
    
    # Unknown request type
    default do
      step :handle_unknown do
        run fn _args ->
          {:error, :unknown_request_type}
        end
      end
    end
  end
  
  # Post-processing and cleanup
  step :post_process do
    argument :main_result, result(:process_request)
    argument :analysis, result(:analyze_request)
    argument :validation, result(:validate_if_needed)
    
    run fn arguments ->
      # Combine results from different stages
      result = %{
        status: :completed,
        strategy_used: arguments.analysis.strategy,
        complexity: arguments.analysis.complexity,
        validation_performed: arguments.validation != :validation_skipped,
        result: arguments.main_result
      }
      
      {:ok, result}
    end
  end
  
  # Notify completion
  step :notify_completion do
    argument :result, result(:post_process)
    
    run fn arguments ->
      # In a real implementation, this would send notifications
      Logger.info("Workflow completed: #{inspect(arguments.result.status)}")
      {:ok, :notified}
    end
    
    async? true  # Run notification asynchronously
  end
  
  # Return the post-processed result
  return :post_process
  
  # Helper functions
  defp calculate_complexity(data) when is_map(data) do
    # Simple complexity calculation based on data size
    map_size(data) + 
      (Map.get(data, :items, []) |> length()) +
      (if Map.get(data, :priority) == :high, do: 3, else: 0)
  end
  
  defp calculate_complexity(_), do: 1
end

