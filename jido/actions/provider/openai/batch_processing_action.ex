defmodule RubberDuck.Jido.Actions.Provider.OpenAI.BatchProcessingAction do
  @moduledoc """
  Action for handling OpenAI batch processing requests efficiently.

  This action manages batch operations for OpenAI API calls, including
  request batching, parallel processing, rate limiting coordination,
  result aggregation, and optimized resource utilization for high-volume
  operations.

  ## Parameters

  - `operation` - Batch operation type (required: :process, :schedule, :monitor, :optimize)
  - `requests` - List of requests to process in batch (required for :process)
  - `batch_size` - Number of requests per batch (default: 10)
  - `concurrency_limit` - Maximum concurrent batches (default: 3)
  - `processing_strategy` - How to process batches (default: :parallel)
  - `retry_strategy` - How to handle failed requests (default: :exponential_backoff)
  - `aggregation_mode` - How to combine results (default: :preserve_order)
  - `timeout_ms` - Overall timeout for batch processing (default: 300000)

  ## Returns

  - `{:ok, result}` - Batch processing completed successfully
  - `{:error, reason}` - Batch processing failed

  ## Example

      params = %{
        operation: :process,
        requests: [
          %{messages: [...], model: "gpt-4"},
          %{messages: [...], model: "gpt-3.5-turbo"},
          # ... more requests
        ],
        batch_size: 5,
        concurrency_limit: 2,
        processing_strategy: :parallel,
        retry_strategy: :exponential_backoff
      }

      {:ok, result} = BatchProcessingAction.run(params, context)
  """

  use Jido.Action,
    name: "batch_processing",
    description: "Handle OpenAI batch processing requests efficiently",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Batch operation (process, schedule, monitor, optimize, cancel)"
      ],
      requests: [
        type: :list,
        default: [],
        doc: "List of requests to process in batch"
      ],
      batch_size: [
        type: :integer,
        default: 10,
        doc: "Number of requests per batch"
      ],
      concurrency_limit: [
        type: :integer,
        default: 3,
        doc: "Maximum concurrent batches"
      ],
      processing_strategy: [
        type: :atom,
        default: :parallel,
        doc: "Processing strategy (parallel, sequential, adaptive, priority_based)"
      ],
      retry_strategy: [
        type: :atom,
        default: :exponential_backoff,
        doc: "Retry strategy (none, exponential_backoff, linear_backoff, immediate)"
      ],
      aggregation_mode: [
        type: :atom,
        default: :preserve_order,
        doc: "Result aggregation (preserve_order, completion_order, grouped)"
      ],
      timeout_ms: [
        type: :integer,
        default: 300000,
        doc: "Overall timeout for batch processing in milliseconds"
      ],
      priority_weights: [
        type: :map,
        default: %{},
        doc: "Priority weights for different request types"
      ],
      batch_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for the batch operation"
      ],
      rate_limit_config: [
        type: :map,
        default: %{},
        doc: "Rate limiting configuration for batch processing"
      ]
    ]

  require Logger

  @valid_operations [:process, :schedule, :monitor, :optimize, :cancel, :status]
  @valid_processing_strategies [:parallel, :sequential, :adaptive, :priority_based]
  @valid_retry_strategies [:none, :exponential_backoff, :linear_backoff, :immediate]
  @valid_aggregation_modes [:preserve_order, :completion_order, :grouped]
  @max_batch_size 100
  @max_concurrency_limit 10
  @max_timeout_ms 3_600_000  # 1 hour
  @default_retry_attempts 3

  @impl true
  def run(params, context) do
    Logger.info("Executing batch processing: #{params.operation} with #{length(params.requests)} requests")

    with {:ok, validated_params} <- validate_batch_parameters(params),
         {:ok, result} <- execute_batch_operation(validated_params, context) do
      
      emit_batch_completed_signal(params.operation, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Batch processing failed: #{inspect(reason)}")
        emit_batch_error_signal(params.operation, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_batch_parameters(params) do
    with {:ok, _} <- validate_operation(params.operation),
         {:ok, _} <- validate_processing_strategy(params.processing_strategy),
         {:ok, _} <- validate_retry_strategy(params.retry_strategy),
         {:ok, _} <- validate_aggregation_mode(params.aggregation_mode),
         {:ok, _} <- validate_batch_size(params.batch_size),
         {:ok, _} <- validate_concurrency_limit(params.concurrency_limit),
         {:ok, _} <- validate_timeout(params.timeout_ms),
         {:ok, _} <- validate_requests_for_operation(params.requests, params.operation) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_operation(operation) do
    if operation in @valid_operations do
      {:ok, operation}
    else
      {:error, {:invalid_operation, operation, @valid_operations}}
    end
  end

  defp validate_processing_strategy(strategy) do
    if strategy in @valid_processing_strategies do
      {:ok, strategy}
    else
      {:error, {:invalid_processing_strategy, strategy, @valid_processing_strategies}}
    end
  end

  defp validate_retry_strategy(strategy) do
    if strategy in @valid_retry_strategies do
      {:ok, strategy}
    else
      {:error, {:invalid_retry_strategy, strategy, @valid_retry_strategies}}
    end
  end

  defp validate_aggregation_mode(mode) do
    if mode in @valid_aggregation_modes do
      {:ok, mode}
    else
      {:error, {:invalid_aggregation_mode, mode, @valid_aggregation_modes}}
    end
  end

  defp validate_batch_size(batch_size) do
    if is_integer(batch_size) and batch_size > 0 and batch_size <= @max_batch_size do
      {:ok, batch_size}
    else
      {:error, {:invalid_batch_size, batch_size, @max_batch_size}}
    end
  end

  defp validate_concurrency_limit(limit) do
    if is_integer(limit) and limit > 0 and limit <= @max_concurrency_limit do
      {:ok, limit}
    else
      {:error, {:invalid_concurrency_limit, limit, @max_concurrency_limit}}
    end
  end

  defp validate_timeout(timeout_ms) do
    if is_integer(timeout_ms) and timeout_ms > 0 and timeout_ms <= @max_timeout_ms do
      {:ok, timeout_ms}
    else
      {:error, {:invalid_timeout, timeout_ms, @max_timeout_ms}}
    end
  end

  defp validate_requests_for_operation(requests, operation) when operation in [:process, :schedule] do
    if is_list(requests) and length(requests) > 0 do
      case validate_request_format(requests) do
        {:ok, _} -> {:ok, requests}
        error -> error
      end
    else
      {:error, {:requests_required_for_operation, operation}}
    end
  end
  defp validate_requests_for_operation(_requests, _operation), do: {:ok, :not_required}

  defp validate_request_format(requests) do
    invalid_requests = Enum.with_index(requests)
    |> Enum.filter(fn {request, _index} ->
      not valid_request_structure?(request)
    end)
    
    if Enum.empty?(invalid_requests) do
      {:ok, :valid}
    else
      invalid_indices = Enum.map(invalid_requests, &elem(&1, 1))
      {:error, {:invalid_request_format, invalid_indices}}
    end
  end

  defp valid_request_structure?(request) do
    # Basic request validation - should have messages and model
    Map.has_key?(request, :messages) and 
    Map.has_key?(request, :model) and
    is_list(request.messages) and
    is_binary(request.model)
  end

  # Operation execution

  defp execute_batch_operation(params, context) do
    case params.operation do
      :process -> process_batch_requests(params, context)
      :schedule -> schedule_batch_processing(params, context)
      :monitor -> monitor_batch_progress(params, context)
      :optimize -> optimize_batch_processing(params, context)
      :cancel -> cancel_batch_processing(params, context)
      :status -> get_batch_status(params, context)
    end
  end

  # Batch processing

  defp process_batch_requests(params, context) do
    batch_id = params.batch_id || generate_batch_id()
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, optimized_config} <- optimize_batch_configuration(params),
         {:ok, batches} <- create_request_batches(params.requests, optimized_config),
         {:ok, processing_plan} <- create_processing_plan(batches, optimized_config),
         {:ok, results} <- execute_processing_plan(processing_plan, optimized_config, context) do
      
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time
      
      result = %{
        operation: :process,
        batch_id: batch_id,
        total_requests: length(params.requests),
        successful_requests: count_successful_results(results),
        failed_requests: count_failed_results(results),
        results: aggregate_results(results, optimized_config.aggregation_mode),
        processing_statistics: %{
          total_duration_ms: duration_ms,
          average_request_time: calculate_average_request_time(results),
          batches_processed: length(batches),
          concurrency_utilized: optimized_config.concurrency_limit,
          retry_attempts: count_retry_attempts(results)
        },
        performance_metrics: calculate_performance_metrics(results, duration_ms),
        optimization_applied: optimized_config.optimizations_applied || []
      }
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_batch_id() do
    "batch_" <> (System.unique_integer([:positive]) |> Integer.to_string())
  end

  defp optimize_batch_configuration(params) do
    base_config = %{
      batch_size: params.batch_size,
      concurrency_limit: params.concurrency_limit,
      processing_strategy: params.processing_strategy,
      retry_strategy: params.retry_strategy,
      aggregation_mode: params.aggregation_mode,
      timeout_ms: params.timeout_ms,
      rate_limit_config: params.rate_limit_config,
      optimizations_applied: []
    }
    
    # Apply optimizations based on request characteristics
    optimized_config = base_config
    |> optimize_batch_size_for_requests(params.requests)
    |> optimize_concurrency_for_load(params.requests)
    |> optimize_strategy_for_request_types(params.requests)
    
    {:ok, optimized_config}
  end

  defp optimize_batch_size_for_requests(config, requests) do
    avg_request_complexity = calculate_average_request_complexity(requests)
    
    optimized_batch_size = cond do
      avg_request_complexity > 8.0 ->
        # Complex requests - smaller batches
        max(div(config.batch_size, 2), 1)
      
      avg_request_complexity < 3.0 ->
        # Simple requests - larger batches
        min(config.batch_size * 2, @max_batch_size)
      
      true ->
        config.batch_size
    end
    
    optimizations = if optimized_batch_size != config.batch_size do
      ["Batch size optimized for request complexity" | config.optimizations_applied]
    else
      config.optimizations_applied
    end
    
    %{config | 
      batch_size: optimized_batch_size,
      optimizations_applied: optimizations
    }
  end

  defp calculate_average_request_complexity(requests) do
    if length(requests) == 0 do
      1.0
    else
      total_complexity = Enum.reduce(requests, 0.0, fn request, acc ->
        acc + estimate_request_complexity(request)
      end)
      
      total_complexity / length(requests)
    end
  end

  defp estimate_request_complexity(request) do
    # Simple complexity estimation based on request characteristics
    base_complexity = 1.0
    
    # Message count factor
    message_count = length(request.messages || [])
    message_factor = min(message_count / 5.0, 3.0)
    
    # Content length factor
    total_content_length = Enum.reduce(request.messages || [], 0, fn message, acc ->
      content = message[:content] || message["content"] || ""
      acc + String.length(content)
    end)
    content_factor = min(total_content_length / 5000.0, 3.0)
    
    # Model complexity factor
    model_factor = case request.model do
      "gpt-4" <> _ -> 2.0
      "gpt-3.5" <> _ -> 1.0
      _ -> 1.5
    end
    
    base_complexity + message_factor + content_factor + model_factor
  end

  defp optimize_concurrency_for_load(config, requests) do
    request_count = length(requests)
    
    optimized_concurrency = cond do
      request_count < 10 ->
        # Small batches don't need high concurrency
        min(config.concurrency_limit, 2)
      
      request_count > 100 ->
        # Large batches benefit from higher concurrency
        min(config.concurrency_limit + 2, @max_concurrency_limit)
      
      true ->
        config.concurrency_limit
    end
    
    optimizations = if optimized_concurrency != config.concurrency_limit do
      ["Concurrency optimized for request count" | config.optimizations_applied]
    else
      config.optimizations_applied
    end
    
    %{config |
      concurrency_limit: optimized_concurrency,
      optimizations_applied: optimizations
    }
  end

  defp optimize_strategy_for_request_types(config, requests) do
    # Analyze request types to determine optimal strategy
    has_mixed_models = has_mixed_model_types?(requests)
    has_high_priority = has_priority_requests?(requests)
    
    optimized_strategy = cond do
      has_high_priority and config.processing_strategy == :parallel ->
        :priority_based
      
      has_mixed_models and config.processing_strategy == :parallel ->
        :adaptive
      
      true ->
        config.processing_strategy
    end
    
    optimizations = if optimized_strategy != config.processing_strategy do
      ["Processing strategy optimized for request characteristics" | config.optimizations_applied]
    else
      config.optimizations_applied
    end
    
    %{config |
      processing_strategy: optimized_strategy,
      optimizations_applied: optimizations
    }
  end

  defp has_mixed_model_types?(requests) do
    models = requests |> Enum.map(& &1.model) |> Enum.uniq()
    length(models) > 1
  end

  defp has_priority_requests?(requests) do
    Enum.any?(requests, fn request ->
      Map.has_key?(request, :priority) and request.priority in [:high, :urgent]
    end)
  end

  defp create_request_batches(requests, config) do
    # Create batches based on strategy
    batches = case config.processing_strategy do
      :priority_based -> create_priority_based_batches(requests, config.batch_size)
      :adaptive -> create_adaptive_batches(requests, config.batch_size)
      _ -> create_simple_batches(requests, config.batch_size)
    end
    
    {:ok, batches}
  end

  defp create_simple_batches(requests, batch_size) do
    requests
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index(1)
    |> Enum.map(fn {batch_requests, batch_number} ->
      %{
        batch_id: "batch_#{batch_number}",
        requests: batch_requests,
        priority: :normal,
        estimated_duration: estimate_batch_duration(batch_requests)
      }
    end)
  end

  defp create_priority_based_batches(requests, batch_size) do
    # Group requests by priority first
    prioritized_requests = requests
    |> Enum.group_by(fn request ->
      Map.get(request, :priority, :normal)
    end)
    
    # Create batches for each priority level
    all_batches = []
    
    # High priority batches first
    high_priority = Map.get(prioritized_requests, :high, [])
    high_batches = create_simple_batches(high_priority, batch_size)
    |> Enum.map(fn batch -> %{batch | priority: :high} end)
    
    # Normal priority batches
    normal_priority = Map.get(prioritized_requests, :normal, [])
    normal_batches = create_simple_batches(normal_priority, batch_size)
    
    # Low priority batches last
    low_priority = Map.get(prioritized_requests, :low, [])
    low_batches = create_simple_batches(low_priority, batch_size)
    |> Enum.map(fn batch -> %{batch | priority: :low} end)
    
    high_batches ++ normal_batches ++ low_batches
  end

  defp create_adaptive_batches(requests, base_batch_size) do
    # Group requests by model for better batching
    grouped_by_model = Enum.group_by(requests, & &1.model)
    
    Enum.flat_map(grouped_by_model, fn {model, model_requests} ->
      # Adjust batch size based on model characteristics
      adjusted_batch_size = case model do
        "gpt-4" <> _ -> max(div(base_batch_size, 2), 1)  # Smaller batches for GPT-4
        "gpt-3.5" <> _ -> min(base_batch_size * 2, @max_batch_size)  # Larger batches for GPT-3.5
        _ -> base_batch_size
      end
      
      create_simple_batches(model_requests, adjusted_batch_size)
      |> Enum.map(fn batch ->
        %{batch | batch_id: "#{model}_#{batch.batch_id}"}
      end)
    end)
  end

  defp estimate_batch_duration(batch_requests) do
    # Simple estimation based on request complexity
    total_complexity = Enum.reduce(batch_requests, 0.0, fn request, acc ->
      acc + estimate_request_complexity(request)
    end)
    
    # Rough estimate: 1 second per complexity unit
    round(total_complexity * 1000)
  end

  defp create_processing_plan(batches, config) do
    plan = %{
      batches: batches,
      concurrency_limit: config.concurrency_limit,
      processing_strategy: config.processing_strategy,
      retry_strategy: config.retry_strategy,
      total_batches: length(batches),
      estimated_total_duration: Enum.reduce(batches, 0, &(&1.estimated_duration + &2))
    }
    
    {:ok, plan}
  end

  defp execute_processing_plan(plan, config, context) do
    case config.processing_strategy do
      :sequential -> execute_sequential_processing(plan, config, context)
      :parallel -> execute_parallel_processing(plan, config, context)
      :adaptive -> execute_adaptive_processing(plan, config, context)
      :priority_based -> execute_priority_based_processing(plan, config, context)
    end
  end

  defp execute_sequential_processing(plan, config, context) do
    results = Enum.reduce(plan.batches, [], fn batch, acc ->
      case process_single_batch(batch, config, context) do
        {:ok, batch_result} ->
          [batch_result | acc]
        
        {:error, reason} ->
          # Handle batch failure based on retry strategy
          case handle_batch_failure(batch, reason, config, context) do
            {:ok, retry_result} -> [retry_result | acc]
            {:error, _} -> [create_failed_batch_result(batch, reason) | acc]
          end
      end
    end)
    
    {:ok, Enum.reverse(results)}
  end

  defp execute_parallel_processing(plan, config, context) do
    # Process batches in parallel with concurrency limit
    plan.batches
    |> Enum.chunk_every(config.concurrency_limit)
    |> Enum.reduce([], fn batch_chunk, acc ->
      # Process chunk in parallel
      chunk_results = batch_chunk
      |> Task.async_stream(fn batch ->
        process_single_batch(batch, config, context)
      end, timeout: config.timeout_ms, max_concurrency: config.concurrency_limit)
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, reason}} -> create_failed_batch_result(nil, reason)
        {:exit, reason} -> create_failed_batch_result(nil, {:exit, reason})
      end)
      
      acc ++ chunk_results
    end)
    |> then(&{:ok, &1})
  end

  defp execute_adaptive_processing(plan, config, context) do
    # Start with parallel processing, adapt based on performance
    initial_results = []
    remaining_batches = plan.batches
    
    adaptive_results = process_batches_adaptively(remaining_batches, config, context, initial_results)
    
    {:ok, adaptive_results}
  end

  defp process_batches_adaptively([], _config, _context, results), do: Enum.reverse(results)
  defp process_batches_adaptively(batches, config, context, results) do
    # Take a chunk based on current performance
    current_concurrency = determine_adaptive_concurrency(results, config)
    {current_chunk, remaining} = Enum.split(batches, current_concurrency)
    
    # Process current chunk
    chunk_results = current_chunk
    |> Task.async_stream(fn batch ->
      process_single_batch(batch, config, context)
    end, timeout: config.timeout_ms, max_concurrency: current_concurrency)
    |> Enum.map(fn
      {:ok, {:ok, result}} -> result
      {:ok, {:error, reason}} -> create_failed_batch_result(nil, reason)
      {:exit, reason} -> create_failed_batch_result(nil, {:exit, reason})
    end)
    
    # Continue with remaining batches
    process_batches_adaptively(remaining, config, context, chunk_results ++ results)
  end

  defp determine_adaptive_concurrency(results, config) do
    if length(results) < 3 do
      # Not enough data, use default
      config.concurrency_limit
    else
      # Analyze recent performance
      recent_results = Enum.take(results, 3)
      success_rate = count_successful_results(recent_results) / length(recent_results)
      
      if success_rate > 0.8 do
        # High success rate, increase concurrency
        min(config.concurrency_limit + 1, @max_concurrency_limit)
      else
        # Lower success rate, decrease concurrency
        max(config.concurrency_limit - 1, 1)
      end
    end
  end

  defp execute_priority_based_processing(plan, config, context) do
    # Group batches by priority
    batches_by_priority = Enum.group_by(plan.batches, & &1.priority)
    
    # Process high priority first, then normal, then low
    priority_order = [:high, :normal, :low]
    
    results = Enum.reduce(priority_order, [], fn priority, acc ->
      priority_batches = Map.get(batches_by_priority, priority, [])
      
      if length(priority_batches) > 0 do
        {:ok, priority_results} = execute_parallel_processing(
          %{plan | batches: priority_batches}, 
          config, 
          context
        )
        
        acc ++ priority_results
      else
        acc
      end
    end)
    
    {:ok, results}
  end

  defp process_single_batch(batch, config, context) do
    start_time = System.monotonic_time(:millisecond)
    
    # Process all requests in the batch
    request_results = batch.requests
    |> Task.async_stream(fn request ->
      process_single_request(request, config, context)
    end, timeout: config.timeout_ms)
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:request_timeout, reason}}
    end)
    
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    
    batch_result = %{
      batch_id: batch.batch_id,
      total_requests: length(batch.requests),
      successful_requests: count_successful_results(request_results),
      failed_requests: count_failed_results(request_results),
      results: request_results,
      processing_time_ms: duration_ms,
      priority: batch.priority,
      status: if(count_failed_results(request_results) == 0, do: :success, else: :partial_success)
    }
    
    {:ok, batch_result}
  end

  defp process_single_request(request, config, context) do
    # TODO: Make actual OpenAI API call
    # For now, simulate request processing
    
    complexity = estimate_request_complexity(request)
    processing_time = round(complexity * 500)  # Simulate processing time
    
    # Simulate random failures for testing retry logic
    if :rand.uniform() < 0.05 do  # 5% failure rate
      {:error, :simulated_api_error}
    else
      :timer.sleep(processing_time)
      
      {:ok, %{
        request_id: generate_request_id(),
        model: request.model,
        response: "Simulated response for request",
        usage: %{
          prompt_tokens: estimate_prompt_tokens(request.messages),
          completion_tokens: 50,
          total_tokens: estimate_prompt_tokens(request.messages) + 50
        },
        processing_time_ms: processing_time,
        timestamp: DateTime.utc_now()
      }}
    end
  end

  defp generate_request_id() do
    "req_" <> (System.unique_integer([:positive]) |> Integer.to_string())
  end

  defp estimate_prompt_tokens(messages) do
    total_chars = Enum.reduce(messages, 0, fn message, acc ->
      content = message[:content] || message["content"] || ""
      acc + String.length(content)
    end)
    
    div(total_chars, 4)
  end

  defp handle_batch_failure(batch, reason, config, context) do
    case config.retry_strategy do
      :none ->
        {:error, reason}
      
      :immediate ->
        process_single_batch(batch, config, context)
      
      :exponential_backoff ->
        :timer.sleep(1000)  # Simple backoff
        process_single_batch(batch, config, context)
      
      :linear_backoff ->
        :timer.sleep(500)   # Linear backoff
        process_single_batch(batch, config, context)
    end
  end

  defp create_failed_batch_result(batch, reason) do
    batch_id = if batch, do: batch.batch_id, else: "unknown_batch"
    
    %{
      batch_id: batch_id,
      status: :failed,
      error: reason,
      total_requests: if(batch, do: length(batch.requests), else: 0),
      successful_requests: 0,
      failed_requests: if(batch, do: length(batch.requests), else: 0),
      results: [],
      processing_time_ms: 0
    }
  end

  # Result aggregation and analysis

  defp count_successful_results(results) do
    Enum.count(results, fn result ->
      case result do
        %{status: :success} -> true
        %{status: :partial_success} -> true
        {:ok, _} -> true
        _ -> false
      end
    end)
  end

  defp count_failed_results(results) do
    length(results) - count_successful_results(results)
  end

  defp aggregate_results(results, aggregation_mode) do
    case aggregation_mode do
      :preserve_order -> aggregate_preserve_order(results)
      :completion_order -> aggregate_completion_order(results)
      :grouped -> aggregate_grouped(results)
    end
  end

  defp aggregate_preserve_order(results) do
    # Flatten all batch results maintaining original request order
    Enum.flat_map(results, fn batch_result ->
      case batch_result.results do
        list when is_list(list) -> list
        single_result -> [single_result]
      end
    end)
  end

  defp aggregate_completion_order(results) do
    # Sort by completion timestamp
    all_results = aggregate_preserve_order(results)
    
    Enum.sort_by(all_results, fn result ->
      case result do
        {:ok, response} -> response[:timestamp] || DateTime.utc_now()
        %{timestamp: timestamp} -> timestamp
        _ -> DateTime.utc_now()
      end
    end)
  end

  defp aggregate_grouped(results) do
    # Group results by status
    all_results = aggregate_preserve_order(results)
    
    %{
      successful: Enum.filter(all_results, &match?({:ok, _}, &1)),
      failed: Enum.filter(all_results, &match?({:error, _}, &1)),
      total: length(all_results)
    }
  end

  defp calculate_average_request_time(results) do
    all_results = aggregate_preserve_order(results)
    
    if length(all_results) == 0 do
      0
    else
      total_time = Enum.reduce(all_results, 0, fn result, acc ->
        processing_time = case result do
          {:ok, response} -> response[:processing_time_ms] || 0
          %{processing_time_ms: time} -> time
          _ -> 0
        end
        acc + processing_time
      end)
      
      total_time / length(all_results)
    end
  end

  defp count_retry_attempts(results) do
    # Count total retry attempts across all batches
    Enum.reduce(results, 0, fn batch_result, acc ->
      retries = Map.get(batch_result, :retry_attempts, 0)
      acc + retries
    end)
  end

  defp calculate_performance_metrics(results, total_duration_ms) do
    total_requests = Enum.reduce(results, 0, & &1.total_requests + &2)
    successful_requests = Enum.reduce(results, 0, & &1.successful_requests + &2)
    
    %{
      throughput_requests_per_second: if(total_duration_ms > 0, do: total_requests / (total_duration_ms / 1000), else: 0),
      success_rate: if(total_requests > 0, do: successful_requests / total_requests, else: 0),
      average_batch_size: if(length(results) > 0, do: total_requests / length(results), else: 0),
      total_processing_efficiency: calculate_processing_efficiency(results, total_duration_ms)
    }
  end

  defp calculate_processing_efficiency(results, total_duration_ms) do
    # Efficiency = (actual processing time) / (total elapsed time)
    total_processing_time = Enum.reduce(results, 0, & &1.processing_time_ms + &2)
    
    if total_duration_ms > 0 do
      total_processing_time / total_duration_ms
    else
      0
    end
  end

  # Batch scheduling

  defp schedule_batch_processing(params, context) do
    batch_id = params.batch_id || generate_batch_id()
    
    schedule_config = %{
      batch_id: batch_id,
      requests: params.requests,
      batch_size: params.batch_size,
      concurrency_limit: params.concurrency_limit,
      processing_strategy: params.processing_strategy,
      scheduled_at: DateTime.utc_now(),
      status: :scheduled,
      estimated_completion: estimate_completion_time(params)
    }
    
    # TODO: Store schedule in actual scheduler/queue
    Logger.info("Scheduled batch #{batch_id} with #{length(params.requests)} requests")
    
    result = %{
      operation: :schedule,
      batch_id: batch_id,
      scheduled_at: schedule_config.scheduled_at,
      estimated_completion: schedule_config.estimated_completion,
      total_requests: length(params.requests),
      status: :scheduled
    }
    
    {:ok, result}
  end

  defp estimate_completion_time(params) do
    avg_complexity = calculate_average_request_complexity(params.requests)
    total_requests = length(params.requests)
    
    # Rough estimation
    estimated_seconds = (total_requests * avg_complexity * 2) / params.concurrency_limit
    
    DateTime.utc_now() |> DateTime.add(round(estimated_seconds), :second)
  end

  # Batch monitoring

  defp monitor_batch_progress(params, context) do
    batch_id = params.batch_id
    
    if batch_id do
      # TODO: Get actual batch status from monitoring system
      # For now, return mock monitoring data
      
      result = %{
        operation: :monitor,
        batch_id: batch_id,
        current_status: :processing,
        progress: %{
          completed_requests: 45,
          total_requests: 100,
          completion_percentage: 45.0,
          estimated_remaining_time_ms: 30000
        },
        performance_stats: %{
          current_throughput: 2.5,
          average_response_time_ms: 1500,
          error_rate: 0.02
        },
        resource_utilization: %{
          cpu_usage: 0.75,
          memory_usage: 0.60,
          active_workers: 3
        }
      }
      
      {:ok, result}
    else
      {:error, :batch_id_required}
    end
  end

  # Batch optimization

  defp optimize_batch_processing(params, context) do
    requests = params.requests
    
    # Analyze current configuration and suggest optimizations
    analysis = %{
      current_config: %{
        batch_size: params.batch_size,
        concurrency_limit: params.concurrency_limit,
        processing_strategy: params.processing_strategy
      },
      request_analysis: analyze_request_characteristics(requests),
      optimization_recommendations: generate_optimization_recommendations(requests, params),
      estimated_improvements: estimate_optimization_impact(requests, params)
    }
    
    result = %{
      operation: :optimize,
      current_configuration: analysis.current_config,
      request_analysis: analysis.request_analysis,
      recommendations: analysis.optimization_recommendations,
      estimated_improvements: analysis.estimated_improvements
    }
    
    {:ok, result}
  end

  defp analyze_request_characteristics(requests) do
    %{
      total_requests: length(requests),
      average_complexity: calculate_average_request_complexity(requests),
      model_distribution: analyze_model_distribution(requests),
      size_distribution: analyze_size_distribution(requests),
      priority_distribution: analyze_priority_distribution(requests)
    }
  end

  defp analyze_model_distribution(requests) do
    requests
    |> Enum.group_by(& &1.model)
    |> Enum.map(fn {model, model_requests} ->
      {model, length(model_requests)}
    end)
    |> Enum.into(%{})
  end

  defp analyze_size_distribution(requests) do
    sizes = Enum.map(requests, fn request ->
      total_chars = Enum.reduce(request.messages, 0, fn message, acc ->
        content = message[:content] || message["content"] || ""
        acc + String.length(content)
      end)
      
      cond do
        total_chars < 1000 -> :small
        total_chars < 5000 -> :medium
        total_chars < 15000 -> :large
        true -> :very_large
      end
    end)
    
    Enum.frequencies(sizes)
  end

  defp analyze_priority_distribution(requests) do
    priorities = Enum.map(requests, &Map.get(&1, :priority, :normal))
    Enum.frequencies(priorities)
  end

  defp generate_optimization_recommendations(requests, params) do
    recommendations = []
    
    # Batch size recommendations
    avg_complexity = calculate_average_request_complexity(requests)
    
    recommendations = if avg_complexity > 6.0 and params.batch_size > 5 do
      ["Reduce batch size to 3-5 for complex requests" | recommendations]
    else
      recommendations
    end
    
    recommendations = if avg_complexity < 3.0 and params.batch_size < 20 do
      ["Increase batch size to 15-25 for simple requests" | recommendations]
    else
      recommendations
    end
    
    # Concurrency recommendations
    request_count = length(requests)
    
    recommendations = if request_count > 100 and params.concurrency_limit < 5 do
      ["Increase concurrency limit to 5-8 for large batches" | recommendations]
    else
      recommendations
    end
    
    # Strategy recommendations
    model_diversity = length(Map.keys(analyze_model_distribution(requests)))
    
    recommendations = if model_diversity > 2 and params.processing_strategy == :parallel do
      ["Consider adaptive strategy for mixed model types" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  defp estimate_optimization_impact(requests, params) do
    current_estimated_time = estimate_current_processing_time(requests, params)
    optimized_estimated_time = estimate_optimized_processing_time(requests, params)
    
    %{
      current_estimated_duration_ms: current_estimated_time,
      optimized_estimated_duration_ms: optimized_estimated_time,
      estimated_time_savings_ms: current_estimated_time - optimized_estimated_time,
      estimated_improvement_percentage: if(current_estimated_time > 0, 
        do: (current_estimated_time - optimized_estimated_time) / current_estimated_time * 100, 
        else: 0)
    }
  end

  defp estimate_current_processing_time(requests, params) do
    avg_complexity = calculate_average_request_complexity(requests)
    total_requests = length(requests)
    
    # Simple estimation
    round((total_requests * avg_complexity * 1000) / params.concurrency_limit)
  end

  defp estimate_optimized_processing_time(requests, params) do
    # Apply optimizations and estimate new time
    optimized_batch_size = calculate_optimal_batch_size(requests)
    optimized_concurrency = calculate_optimal_concurrency(requests, params.concurrency_limit)
    
    avg_complexity = calculate_average_request_complexity(requests)
    total_requests = length(requests)
    
    # Optimized estimation
    efficiency_factor = 1.2  # Assume 20% efficiency gain from optimizations
    
    round((total_requests * avg_complexity * 1000) / (optimized_concurrency * efficiency_factor))
  end

  defp calculate_optimal_batch_size(requests) do
    avg_complexity = calculate_average_request_complexity(requests)
    
    cond do
      avg_complexity > 8.0 -> 3
      avg_complexity > 5.0 -> 5
      avg_complexity > 3.0 -> 10
      true -> 20
    end
  end

  defp calculate_optimal_concurrency(requests, current_limit) do
    request_count = length(requests)
    
    optimal = cond do
      request_count < 10 -> 2
      request_count < 50 -> 4
      request_count < 200 -> 6
      true -> 8
    end
    
    min(optimal, @max_concurrency_limit)
  end

  # Batch cancellation

  defp cancel_batch_processing(params, context) do
    batch_id = params.batch_id
    
    if batch_id do
      # TODO: Implement actual batch cancellation
      Logger.info("Cancelling batch #{batch_id}")
      
      result = %{
        operation: :cancel,
        batch_id: batch_id,
        cancelled_at: DateTime.utc_now(),
        status: :cancelled
      }
      
      {:ok, result}
    else
      {:error, :batch_id_required}
    end
  end

  # Batch status

  defp get_batch_status(params, context) do
    batch_id = params.batch_id
    
    if batch_id do
      # TODO: Get actual batch status
      
      result = %{
        operation: :status,
        batch_id: batch_id,
        status: :completed,
        created_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        completed_at: DateTime.utc_now(),
        total_requests: 50,
        successful_requests: 48,
        failed_requests: 2,
        processing_duration_ms: 45000
      }
      
      {:ok, result}
    else
      {:error, :batch_id_required}
    end
  end

  # Signal emission

  defp emit_batch_completed_signal(operation, result) do
    # TODO: Emit actual signal
    Logger.debug("Batch #{operation} completed: #{inspect(Map.keys(result))}")
  end

  defp emit_batch_error_signal(operation, reason) do
    # TODO: Emit actual signal
    Logger.debug("Batch #{operation} failed: #{inspect(reason)}")
  end
end