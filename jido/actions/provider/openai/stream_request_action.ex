defmodule RubberDuck.Jido.Actions.Provider.OpenAI.StreamRequestAction do
  @moduledoc """
  Action for handling OpenAI streaming completion requests.

  This action manages real-time streaming responses from OpenAI models,
  including chunk processing, connection management, error handling,
  and real-time result accumulation for chat completions and text generation.

  ## Parameters

  - `request_id` - Unique identifier for the streaming request (required)
  - `messages` - List of conversation messages (required)
  - `model` - OpenAI model to use (required)
  - `stream_mode` - Type of streaming (default: :chat_completion)
  - `chunk_handler` - How to handle incoming chunks (default: :accumulate)
  - `buffer_size` - Size of internal buffer (default: 8192)
  - `timeout_ms` - Request timeout in milliseconds (default: 60000)
  - `max_tokens` - Maximum tokens to generate (default: nil)

  ## Returns

  - `{:ok, result}` - Streaming request completed successfully
  - `{:error, reason}` - Streaming request failed

  ## Example

      params = %{
        request_id: "stream_req_123",
        messages: [
          %{role: "user", content: "Write a story about..."}
        ],
        model: "gpt-4",
        stream_mode: :chat_completion,
        chunk_handler: :real_time,
        timeout_ms: 30000
      }

      {:ok, result} = StreamRequestAction.run(params, context)
  """

  use Jido.Action,
    name: "stream_request",
    description: "Handle OpenAI streaming completion requests",
    schema: [
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the streaming request"
      ],
      messages: [
        type: :list,
        required: true,
        doc: "List of conversation messages"
      ],
      model: [
        type: :string,
        required: true,
        doc: "OpenAI model to use for generation"
      ],
      stream_mode: [
        type: :atom,
        default: :chat_completion,
        doc: "Type of streaming (chat_completion, text_completion, function_calling)"
      ],
      chunk_handler: [
        type: :atom,
        default: :accumulate,
        doc: "How to handle chunks (accumulate, real_time, callback, buffered)"
      ],
      buffer_size: [
        type: :integer,
        default: 8192,
        doc: "Size of internal buffer in bytes"
      ],
      timeout_ms: [
        type: :integer,
        default: 60000,
        doc: "Request timeout in milliseconds"
      ],
      max_tokens: [
        type: :integer,
        default: nil,
        doc: "Maximum tokens to generate"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Sampling temperature"
      ],
      stream_options: [
        type: :map,
        default: %{},
        doc: "Additional streaming options"
      ],
      callback_pid: [
        type: :pid,
        default: nil,
        doc: "Process to send real-time updates to"
      ],
      include_usage: [
        type: :boolean,
        default: true,
        doc: "Whether to include token usage in final response"
      ]
    ]

  require Logger

  @valid_stream_modes [:chat_completion, :text_completion, :function_calling, :embeddings]
  @valid_chunk_handlers [:accumulate, :real_time, :callback, :buffered]
  @valid_models ["gpt-4", "gpt-4-turbo", "gpt-4o", "gpt-3.5-turbo", "gpt-3.5-turbo-16k"]
  @default_buffer_size 8192
  @max_timeout_ms 300_000  # 5 minutes
  @chunk_timeout_ms 5000   # 5 seconds between chunks

  @impl true
  def run(params, context) do
    Logger.info("Starting streaming request: #{params.request_id} with model #{params.model}")

    with {:ok, validated_params} <- validate_stream_parameters(params),
         {:ok, stream_config} <- prepare_stream_configuration(validated_params),
         {:ok, result} <- execute_streaming_request(stream_config, context) do
      
      emit_stream_completed_signal(params.request_id, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Streaming request failed: #{inspect(reason)}")
        emit_stream_error_signal(params.request_id, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_stream_parameters(params) do
    with {:ok, _} <- validate_model(params.model),
         {:ok, _} <- validate_stream_mode(params.stream_mode),
         {:ok, _} <- validate_chunk_handler(params.chunk_handler),
         {:ok, _} <- validate_messages(params.messages),
         {:ok, _} <- validate_timeout(params.timeout_ms),
         {:ok, _} <- validate_buffer_size(params.buffer_size) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_model(model) do
    if model in @valid_models do
      {:ok, model}
    else
      {:error, {:invalid_model, model, @valid_models}}
    end
  end

  defp validate_stream_mode(mode) do
    if mode in @valid_stream_modes do
      {:ok, mode}
    else
      {:error, {:invalid_stream_mode, mode, @valid_stream_modes}}
    end
  end

  defp validate_chunk_handler(handler) do
    if handler in @valid_chunk_handlers do
      {:ok, handler}
    else
      {:error, {:invalid_chunk_handler, handler, @valid_chunk_handlers}}
    end
  end

  defp validate_messages(messages) when is_list(messages) do
    if length(messages) > 0 do
      case validate_message_format(messages) do
        {:ok, _} -> {:ok, messages}
        error -> error
      end
    else
      {:error, :empty_messages_list}
    end
  end
  defp validate_messages(_), do: {:error, :messages_must_be_list}

  defp validate_message_format(messages) do
    invalid_messages = Enum.with_index(messages)
    |> Enum.filter(fn {message, _index} ->
      not valid_message_structure?(message)
    end)
    
    if Enum.empty?(invalid_messages) do
      {:ok, :valid}
    else
      invalid_indices = Enum.map(invalid_messages, &elem(&1, 1))
      {:error, {:invalid_message_format, invalid_indices}}
    end
  end

  defp valid_message_structure?(message) do
    Map.has_key?(message, :role) and 
    Map.has_key?(message, :content) and
    message.role in ["system", "user", "assistant", "function"] and
    is_binary(message.content)
  end

  defp validate_timeout(timeout_ms) do
    if is_integer(timeout_ms) and timeout_ms > 0 and timeout_ms <= @max_timeout_ms do
      {:ok, timeout_ms}
    else
      {:error, {:invalid_timeout, timeout_ms, @max_timeout_ms}}
    end
  end

  defp validate_buffer_size(buffer_size) do
    if is_integer(buffer_size) and buffer_size > 0 and buffer_size <= 65536 do
      {:ok, buffer_size}
    else
      {:error, {:invalid_buffer_size, buffer_size}}
    end
  end

  # Stream configuration

  defp prepare_stream_configuration(params) do
    config = %{
      request_id: params.request_id,
      messages: params.messages,
      model: params.model,
      stream_mode: params.stream_mode,
      chunk_handler: params.chunk_handler,
      buffer_size: params.buffer_size,
      timeout_ms: params.timeout_ms,
      callback_pid: params.callback_pid,
      
      # OpenAI API parameters
      api_params: build_api_parameters(params),
      
      # Streaming state
      stream_state: %{
        accumulated_content: "",
        chunks_received: 0,
        total_tokens: 0,
        start_time: System.monotonic_time(:millisecond),
        last_chunk_time: nil,
        buffer: "",
        function_calls: [],
        completion_reason: nil
      },
      
      # Configuration
      stream_options: Map.merge(%{
        include_usage: params.include_usage,
        chunk_timeout: @chunk_timeout_ms
      }, params.stream_options)
    }
    
    {:ok, config}
  end

  defp build_api_parameters(params) do
    base_params = %{
      model: params.model,
      messages: params.messages,
      stream: true,
      stream_options: %{include_usage: params.include_usage}
    }
    
    # Add optional parameters
    optional_params = [
      {:max_tokens, params.max_tokens},
      {:temperature, params.temperature}
    ]
    |> Enum.filter(fn {_key, value} -> not is_nil(value) end)
    |> Enum.into(%{})
    
    Map.merge(base_params, optional_params)
  end

  # Stream execution

  defp execute_streaming_request(config, context) do
    case config.chunk_handler do
      :accumulate -> execute_accumulating_stream(config, context)
      :real_time -> execute_real_time_stream(config, context)
      :callback -> execute_callback_stream(config, context)
      :buffered -> execute_buffered_stream(config, context)
    end
  end

  # Accumulating stream - collect all chunks and return final result

  defp execute_accumulating_stream(config, context) do
    stream_pid = spawn_link(fn -> accumulating_stream_process(config, self()) end)
    
    receive do
      {:stream_completed, result} ->
        result = process_final_result(result, config)
        {:ok, result}
        
      {:stream_error, reason} ->
        {:error, reason}
        
      {:stream_timeout} ->
        Process.exit(stream_pid, :kill)
        {:error, :stream_timeout}
        
    after config.timeout_ms ->
      Process.exit(stream_pid, :kill)
      {:error, :request_timeout}
    end
  end

  defp accumulating_stream_process(config, parent_pid) do
    case initiate_openai_stream(config) do
      {:ok, stream_ref} ->
        state = config.stream_state
        
        case accumulate_stream_chunks(stream_ref, state, config) do
          {:ok, final_state} ->
            send(parent_pid, {:stream_completed, final_state})
            
          {:error, reason} ->
            send(parent_pid, {:stream_error, reason})
        end
        
      {:error, reason} ->
        send(parent_pid, {:stream_error, reason})
    end
  end

  defp initiate_openai_stream(config) do
    # TODO: Make actual OpenAI API call
    # For now, simulate stream initialization
    Logger.debug("Initiating OpenAI stream for request: #{config.request_id}")
    
    # Mock stream reference
    stream_ref = %{
      request_id: config.request_id,
      model: config.model,
      started_at: DateTime.utc_now()
    }
    
    {:ok, stream_ref}
  end

  defp accumulate_stream_chunks(stream_ref, state, config) do
    # TODO: Process actual OpenAI stream chunks
    # For now, simulate streaming with mock data
    
    mock_chunks = generate_mock_stream_chunks(config)
    
    final_state = Enum.reduce(mock_chunks, state, fn chunk, acc_state ->
      process_stream_chunk(chunk, acc_state, config)
    end)
    
    {:ok, final_state}
  end

  defp generate_mock_stream_chunks(config) do
    # Generate realistic mock streaming chunks
    base_content = "This is a simulated streaming response for request #{config.request_id}. "
    words = String.split(base_content, " ")
    
    chunks = Enum.with_index(words, 1)
    |> Enum.map(fn {word, index} ->
      %{
        id: "chatcmpl-#{config.request_id}-chunk-#{index}",
        object: "chat.completion.chunk",
        created: DateTime.utc_now() |> DateTime.to_unix(),
        model: config.model,
        choices: [
          %{
            index: 0,
            delta: %{
              content: if(index == 1, do: word, else: " #{word}")
            },
            finish_reason: nil
          }
        ]
      }
    end)
    
    # Add final chunk with finish reason
    final_chunk = %{
      id: "chatcmpl-#{config.request_id}-final",
      object: "chat.completion.chunk",
      created: DateTime.utc_now() |> DateTime.to_unix(),
      model: config.model,
      choices: [
        %{
          index: 0,
          delta: %{},
          finish_reason: "stop"
        }
      ],
      usage: %{
        prompt_tokens: estimate_prompt_tokens(config.messages),
        completion_tokens: length(words),
        total_tokens: estimate_prompt_tokens(config.messages) + length(words)
      }
    }
    
    chunks ++ [final_chunk]
  end

  defp estimate_prompt_tokens(messages) do
    # Simple estimation: ~4 characters per token
    total_chars = Enum.reduce(messages, 0, fn message, acc ->
      acc + String.length(message.content)
    end)
    
    div(total_chars, 4)
  end

  defp process_stream_chunk(chunk, state, config) do
    now = System.monotonic_time(:millisecond)
    
    updated_state = %{state |
      chunks_received: state.chunks_received + 1,
      last_chunk_time: now
    }
    
    # Process chunk based on type
    case chunk.choices do
      [%{delta: %{content: content}} | _] when is_binary(content) ->
        %{updated_state |
          accumulated_content: updated_state.accumulated_content <> content
        }
        
      [%{delta: %{function_call: function_call}} | _] when not is_nil(function_call) ->
        %{updated_state |
          function_calls: [function_call | updated_state.function_calls]
        }
        
      [%{finish_reason: reason} | _] when not is_nil(reason) ->
        %{updated_state |
          completion_reason: reason,
          total_tokens: extract_token_usage(chunk)
        }
        
      _ ->
        # Handle other chunk types or malformed chunks
        updated_state
    end
  end

  defp extract_token_usage(chunk) do
    case chunk[:usage] do
      %{total_tokens: total} -> total
      _ -> 0
    end
  end

  # Real-time stream - send chunks as they arrive

  defp execute_real_time_stream(config, context) do
    case config.callback_pid do
      nil ->
        {:error, :callback_pid_required_for_real_time}
        
      callback_pid ->
        stream_pid = spawn_link(fn -> 
          real_time_stream_process(config, callback_pid, self()) 
        end)
        
        receive do
          {:stream_completed, result} ->
            {:ok, result}
            
          {:stream_error, reason} ->
            {:error, reason}
            
        after config.timeout_ms ->
          Process.exit(stream_pid, :kill)
          {:error, :request_timeout}
        end
    end
  end

  defp real_time_stream_process(config, callback_pid, parent_pid) do
    case initiate_openai_stream(config) do
      {:ok, stream_ref} ->
        state = config.stream_state
        
        case process_real_time_chunks(stream_ref, state, config, callback_pid) do
          {:ok, final_state} ->
            send(parent_pid, {:stream_completed, final_state})
            
          {:error, reason} ->
            send(parent_pid, {:stream_error, reason})
        end
        
      {:error, reason} ->
        send(parent_pid, {:stream_error, reason})
    end
  end

  defp process_real_time_chunks(stream_ref, state, config, callback_pid) do
    mock_chunks = generate_mock_stream_chunks(config)
    
    final_state = Enum.reduce(mock_chunks, state, fn chunk, acc_state ->
      updated_state = process_stream_chunk(chunk, acc_state, config)
      
      # Send real-time update to callback
      send(callback_pid, {
        :stream_chunk, 
        config.request_id, 
        %{
          chunk: chunk,
          accumulated_content: updated_state.accumulated_content,
          chunks_received: updated_state.chunks_received
        }
      })
      
      # Small delay to simulate real streaming
      :timer.sleep(50)
      
      updated_state
    end)
    
    {:ok, final_state}
  end

  # Callback stream - use provided callback function

  defp execute_callback_stream(config, context) do
    callback_function = config.stream_options[:callback_function]
    
    case callback_function do
      nil ->
        {:error, :callback_function_required}
        
      callback when is_function(callback, 2) ->
        execute_callback_stream_with_function(config, callback, context)
        
      _ ->
        {:error, :invalid_callback_function}
    end
  end

  defp execute_callback_stream_with_function(config, callback, context) do
    case initiate_openai_stream(config) do
      {:ok, stream_ref} ->
        state = config.stream_state
        mock_chunks = generate_mock_stream_chunks(config)
        
        final_state = Enum.reduce(mock_chunks, state, fn chunk, acc_state ->
          updated_state = process_stream_chunk(chunk, acc_state, config)
          
          # Call the callback function
          try do
            callback.(chunk, updated_state)
          rescue
            error ->
              Logger.error("Callback function error: #{Exception.message(error)}")
          end
          
          updated_state
        end)
        
        result = process_final_result(final_state, config)
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Buffered stream - collect chunks in buffer and send in batches

  defp execute_buffered_stream(config, context) do
    buffer_threshold = config.stream_options[:buffer_threshold] || 5
    
    case initiate_openai_stream(config) do
      {:ok, stream_ref} ->
        state = config.stream_state
        mock_chunks = generate_mock_stream_chunks(config)
        
        {final_state, _buffer} = Enum.reduce(mock_chunks, {state, []}, fn chunk, {acc_state, buffer} ->
          updated_state = process_stream_chunk(chunk, acc_state, config)
          new_buffer = [chunk | buffer]
          
          if length(new_buffer) >= buffer_threshold do
            # Process buffer
            process_chunk_buffer(Enum.reverse(new_buffer), config)
            {updated_state, []}
          else
            {updated_state, new_buffer}
          end
        end)
        
        result = process_final_result(final_state, config)
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_chunk_buffer(chunks, config) do
    Logger.debug("Processing buffer of #{length(chunks)} chunks for #{config.request_id}")
    
    # Send buffer to callback if available
    if config.callback_pid do
      send(config.callback_pid, {:chunk_buffer, config.request_id, chunks})
    end
  end

  # Result processing

  defp process_final_result(final_state, config) do
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - final_state.start_time
    
    %{
      request_id: config.request_id,
      model: config.model,
      stream_mode: config.stream_mode,
      chunk_handler: config.chunk_handler,
      
      # Content results
      content: final_state.accumulated_content,
      function_calls: Enum.reverse(final_state.function_calls),
      completion_reason: final_state.completion_reason,
      
      # Stream statistics
      statistics: %{
        chunks_received: final_state.chunks_received,
        total_tokens: final_state.total_tokens,
        duration_ms: duration_ms,
        average_chunk_interval: if(final_state.chunks_received > 1, 
          do: duration_ms / (final_state.chunks_received - 1), 
          else: 0),
        tokens_per_second: if(duration_ms > 0, 
          do: final_state.total_tokens / (duration_ms / 1000), 
          else: 0)
      },
      
      # Metadata
      metadata: %{
        completed_at: DateTime.utc_now(),
        buffer_size_used: config.buffer_size,
        timeout_configured: config.timeout_ms,
        include_usage: config.stream_options.include_usage
      }
    }
  end

  # Stream monitoring and health

  def monitor_stream_health(stream_config) do
    %{
      stream_id: stream_config.request_id,
      health_status: assess_stream_health(stream_config),
      performance_metrics: calculate_stream_metrics(stream_config),
      recommendations: generate_stream_recommendations(stream_config)
    }
  end

  defp assess_stream_health(config) do
    current_time = System.monotonic_time(:millisecond)
    
    cond do
      is_nil(config.stream_state.last_chunk_time) ->
        :initializing
        
      current_time - config.stream_state.last_chunk_time > @chunk_timeout_ms ->
        :stalled
        
      config.stream_state.chunks_received > 0 ->
        :healthy
        
      true ->
        :unknown
    end
  end

  defp calculate_stream_metrics(config) do
    state = config.stream_state
    current_time = System.monotonic_time(:millisecond)
    
    duration = if state.start_time, do: current_time - state.start_time, else: 0
    
    %{
      uptime_ms: duration,
      chunks_per_second: if(duration > 0, do: state.chunks_received / (duration / 1000), else: 0),
      content_length: String.length(state.accumulated_content),
      average_chunk_size: if(state.chunks_received > 0, 
        do: String.length(state.accumulated_content) / state.chunks_received, 
        else: 0),
      buffer_utilization: 0.0  # Would calculate actual buffer usage
    }
  end

  defp generate_stream_recommendations(config) do
    metrics = calculate_stream_metrics(config)
    recommendations = []
    
    recommendations = if metrics.chunks_per_second > 100 do
      ["Consider increasing buffer size for high-frequency streams" | recommendations]
    else
      recommendations
    end
    
    recommendations = if metrics.average_chunk_size > 1000 do
      ["Large chunks detected, consider optimizing chunk handling" | recommendations]
    else
      recommendations
    end
    
    recommendations = if config.timeout_ms > 120_000 do
      ["Very long timeout configured, consider reducing for better resource management" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  # Stream utilities

  def estimate_stream_duration(messages, model) do
    # Estimate how long streaming might take based on input
    input_tokens = estimate_prompt_tokens(messages)
    
    # Rough estimates based on model
    tokens_per_second = case model do
      "gpt-4" -> 30
      "gpt-4-turbo" -> 50
      "gpt-4o" -> 80
      "gpt-3.5-turbo" -> 100
      _ -> 50
    end
    
    # Estimate output tokens (rough heuristic)
    estimated_output_tokens = min(input_tokens * 2, 4000)
    
    estimated_seconds = estimated_output_tokens / tokens_per_second
    round(estimated_seconds * 1000)  # Return in milliseconds
  end

  def optimize_stream_config(base_config, optimization_goals) do
    optimized_config = base_config
    
    optimized_config = if :low_latency in optimization_goals do
      %{optimized_config | 
        buffer_size: div(optimized_config.buffer_size, 2),
        chunk_handler: :real_time
      }
    else
      optimized_config
    end
    
    optimized_config = if :high_throughput in optimization_goals do
      %{optimized_config |
        buffer_size: optimized_config.buffer_size * 2,
        chunk_handler: :buffered
      }
    else
      optimized_config
    end
    
    optimized_config = if :reliability in optimization_goals do
      %{optimized_config |
        timeout_ms: min(optimized_config.timeout_ms * 2, @max_timeout_ms)
      }
    else
      optimized_config
    end
    
    optimized_config
  end

  # Signal emission

  defp emit_stream_completed_signal(request_id, result) do
    # TODO: Emit actual signal
    Logger.debug("Stream completed: #{request_id}, #{result.statistics.chunks_received} chunks")
  end

  defp emit_stream_error_signal(request_id, reason) do
    # TODO: Emit actual signal
    Logger.debug("Stream failed: #{request_id}, reason: #{inspect(reason)}")
  end
end