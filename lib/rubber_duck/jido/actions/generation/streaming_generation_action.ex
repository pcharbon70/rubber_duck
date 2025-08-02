defmodule RubberDuck.Jido.Actions.Generation.StreamingGenerationAction do
  @moduledoc """
  Action for streaming code generation with real-time progress updates.

  This action provides streaming code generation capabilities, emitting
  progress signals during the generation process to enable real-time
  feedback and interaction.

  ## Parameters

  - `prompt` - Natural language description of code to generate (required)
  - `language` - Target programming language (default: :elixir)
  - `streaming_id` - Unique identifier for this streaming session (auto-generated)
  - `context` - Additional context for generation
  - `chunk_size` - Size of generation chunks (default: 100)
  - `progress_callback` - Optional callback for progress updates

  ## Returns

  - `{:ok, result}` - Streaming started successfully with session info
  - `{:error, reason}` - Streaming failed to start

  ## Signals Emitted

  - `generation.streaming.started` - Streaming session started
  - `generation.streaming.progress` - Progress update with partial code
  - `generation.streaming.chunk` - New code chunk available
  - `generation.streaming.completed` - Generation completed
  - `generation.streaming.error` - Error occurred during streaming

  ## Example

      params = %{
        prompt: "Create a comprehensive user management system",
        language: :elixir,
        streaming_id: "stream_123"
      }

      {:ok, result} = StreamingGenerationAction.run(params, context)
  """

  use Jido.Action,
    name: "streaming_generation",
    description: "Stream code generation with real-time progress",
    schema: [
      prompt: [
        type: :string,
        required: true,
        doc: "Natural language description of code to generate"
      ],
      language: [
        type: :atom,
        default: :elixir,
        doc: "Target programming language"
      ],
      streaming_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for streaming session (auto-generated if nil)"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional context for generation"
      ],
      chunk_size: [
        type: :integer,
        default: 100,
        doc: "Size of generation chunks in characters"
      ],
      max_chunks: [
        type: :integer,
        default: 50,
        doc: "Maximum number of chunks to generate"
      ],
      progress_callback: [
        type: {:or, [:function, :nil]},
        default: nil,
        doc: "Optional callback for progress updates"
      ]
    ]

  require Logger

  alias RubberDuck.Engines.Generation, as: GenerationEngine
  alias Jido.Signal

  @impl true
  def run(params, context) do
    streaming_id = params.streaming_id || generate_streaming_id()
    
    Logger.info("Starting streaming generation session: #{streaming_id}")

    # Emit started signal
    emit_signal(:started, streaming_id, %{
      prompt: params.prompt,
      language: params.language,
      estimated_chunks: estimate_chunks(params.prompt, params.chunk_size)
    })

    # Start streaming generation process
    case start_streaming_generation(params, streaming_id, context) do
      {:ok, generation_result} ->
        result = %{
          streaming_id: streaming_id,
          status: :completed,
          total_chunks: generation_result.chunk_count,
          generated_code: generation_result.final_code,
          metadata: %{
            started_at: DateTime.utc_now(),
            completed_at: generation_result.completed_at,
            duration_ms: generation_result.duration_ms,
            language: params.language
          }
        }

        emit_signal(:completed, streaming_id, result)
        {:ok, result}

      {:error, reason} ->
        emit_signal(:error, streaming_id, %{
          error: reason,
          failed_at: DateTime.utc_now()
        })
        {:error, reason}
    end
  end

  # Private functions

  defp generate_streaming_id do
    "stream_" <> 
    (:crypto.strong_rand_bytes(8) |> Base.encode64() |> String.replace(~r/[^a-zA-Z0-9]/, ""))
  end

  defp estimate_chunks(prompt, chunk_size) do
    # Rough estimation based on prompt complexity
    base_estimate = String.length(prompt) * 3  # Assume 3x expansion
    max(1, div(base_estimate, chunk_size))
  end

  defp start_streaming_generation(params, streaming_id, context) do
    start_time = DateTime.utc_now()
    
    # Simulate streaming by breaking generation into chunks
    case generate_with_chunking(params, streaming_id, context) do
      {:ok, chunks} ->
        final_code = Enum.join(chunks, "")
        end_time = DateTime.utc_now()
        duration_ms = DateTime.diff(end_time, start_time, :millisecond)

        result = %{
          final_code: final_code,
          chunk_count: length(chunks),
          completed_at: end_time,
          duration_ms: duration_ms
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_with_chunking(params, streaming_id, context) do
    # For now, simulate chunked generation
    # In a real implementation, this would interface with streaming LLM APIs
    
    case generate_full_code(params, context) do
      {:ok, full_code} ->
        chunks = break_into_chunks(full_code, params.chunk_size)
        
        # Emit each chunk with progress
        chunks
        |> Enum.with_index(1)
        |> Enum.each(fn {chunk, index} ->
          progress = index / length(chunks) * 100
          
          emit_signal(:chunk, streaming_id, %{
            chunk_index: index,
            chunk_content: chunk,
            progress_percent: progress,
            total_chunks: length(chunks)
          })
          
          emit_signal(:progress, streaming_id, %{
            progress_percent: progress,
            chunks_completed: index,
            total_chunks: length(chunks),
            current_chunk_size: String.length(chunk)
          })
          
          # Simulate processing delay
          Process.sleep(100)
        end)
        
        {:ok, chunks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_full_code(params, context) do
    # Use the standard generation engine
    case GenerationEngine.execute(
           %{
             prompt: params.prompt,
             language: params.language,
             context: params.context,
             user_preferences: Map.get(context, :user_preferences, %{})
           },
           build_llm_config()
         ) do
      {:ok, result} ->
        {:ok, result.code}

      {:error, reason} ->
        Logger.error("Full code generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp break_into_chunks(code, chunk_size) do
    # Break code into logical chunks (prefer line boundaries)
    lines = String.split(code, "\n")
    
    lines
    |> Enum.reduce({[], "", 0}, fn line, {chunks, current_chunk, current_size} ->
      line_with_newline = line <> "\n"
      new_size = current_size + String.length(line_with_newline)
      
      if new_size >= chunk_size and current_chunk != "" do
        # Start new chunk
        {[current_chunk | chunks], line_with_newline, String.length(line_with_newline)}
      else
        # Add to current chunk
        {chunks, current_chunk <> line_with_newline, new_size}
      end
    end)
    |> case do
      {chunks, "", _} -> Enum.reverse(chunks)
      {chunks, final_chunk, _} -> Enum.reverse([final_chunk | chunks])
    end
  end

  defp emit_signal(type, streaming_id, data) do
    signal_type = "generation.streaming.#{type}"
    
    signal_data = Map.merge(data, %{
      streaming_id: streaming_id,
      timestamp: DateTime.utc_now()
    })

    signal = Signal.new!(%{
      type: signal_type,
      source: "streaming_generation_action",
      data: signal_data
    })

    # Emit signal to the bus
    case Signal.Bus.publish(signal) do
      :ok ->
        Logger.debug("Emitted signal: #{signal_type} for session #{streaming_id}")
        :ok
      
      {:error, reason} ->
        Logger.warning("Failed to emit signal #{signal_type}: #{inspect(reason)}")
        :error
    end
  end

  defp build_llm_config do
    %{
      provider: :openai,
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 2048,
      stream: true  # Enable streaming if supported
    }
  end
end