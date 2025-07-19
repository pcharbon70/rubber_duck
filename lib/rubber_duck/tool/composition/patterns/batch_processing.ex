defmodule RubberDuck.Tool.Composition.Patterns.BatchProcessing do
  @moduledoc """
  A batch processing pattern for handling large datasets.

  This workflow pattern implements batch processing with:
  - Input data partitioning
  - Parallel batch processing
  - Result aggregation
  - Error handling for partial batch failures
  - Progress tracking and reporting
  """

  use RubberDuck.Workflows.Workflow

  workflow do
    # Step 1: Partition input data into batches
    step :partition_data do
      run RubberDuck.Tool.Composition.Step
      argument :input_data, input(:data)
      argument :batch_size, input(:batch_size)
      argument :partition_strategy, input(:partition_strategy)
      max_retries 2
    end

    # Step 2: Process each batch in parallel
    # This step will be dynamically expanded based on the number of partitions
    step :process_batches do
      run RubberDuck.Tool.Composition.Step
      argument :partitions, result(:partition_data)
      argument :processing_config, input(:processing_config)
      argument :max_concurrent_batches, input(:max_concurrent_batches)
      max_retries 2
      # Longer timeout for batch processing
      timeout 120_000
    end

    # Step 3: Validate processed batches
    step :validate_batches do
      run RubberDuck.Tool.Composition.Step
      argument :processed_batches, result(:process_batches)
      argument :validation_rules, input(:validation_rules)
      max_retries 2
    end

    # Step 4: Handle any failed batches
    step :handle_failed_batches do
      run RubberDuck.Tool.Composition.Step
      argument :batch_results, result(:validate_batches)
      argument :retry_config, input(:retry_config)
      argument :failure_strategy, input(:failure_strategy)
      max_retries 3
    end

    # Step 5: Aggregate successful batch results
    step :aggregate_batch_results do
      run RubberDuck.Tool.Composition.Step
      argument :processed_batches, result(:handle_failed_batches)
      argument :aggregation_config, input(:aggregation_config)
      max_retries 2
    end

    # Step 6: Apply post-processing transformations
    step :post_process_results do
      run RubberDuck.Tool.Composition.Step
      argument :aggregated_data, result(:aggregate_batch_results)
      argument :transformations, input(:post_processing_transformations)
      max_retries 2
    end

    # Step 7: Generate processing summary and metrics
    step :generate_processing_summary do
      run RubberDuck.Tool.Composition.Step
      argument :final_data, result(:post_process_results)

      argument :metrics, %{
        partitions: result(:partition_data),
        processed_batches: result(:process_batches),
        validated_batches: result(:validate_batches),
        failed_batches: result(:handle_failed_batches),
        aggregated_results: result(:aggregate_batch_results)
      }

      argument :summary_config, input(:summary_config)
      max_retries 1
    end

    # Step 8: Store results and cleanup
    step :store_and_cleanup do
      run RubberDuck.Tool.Composition.Step
      argument :final_data, result(:post_process_results)
      argument :summary, result(:generate_processing_summary)
      argument :storage_config, input(:storage_config)
      argument :cleanup_config, input(:cleanup_config)
      max_retries 3
      # Compensate by cleaning up partial results
      compensate RubberDuck.Tool.Composition.Step
    end

    # Final step - the summary will be the workflow result
  end
end
