defmodule RubberDuck.Interface.CLI.Streaming do
  @moduledoc """
  Real-time streaming support for CLI responses.
  
  This module handles streaming AI responses in real-time, providing:
  - Character-by-character streaming display
  - Word-by-word streaming with natural pauses
  - Chunk-based streaming for large responses
  - Rate limiting and backpressure handling
  - Stream interruption and cancellation
  - Stream buffering and replay
  
  ## Features
  
  - **Real-time Display**: Stream text as it's generated
  - **Natural Pacing**: Configurable timing for human-like display
  - **Backpressure Handling**: Manage fast producers with slow consumers
  - **Stream Control**: Pause, resume, and cancel streams
  - **Error Recovery**: Handle stream interruptions gracefully
  - **Buffering**: Optional buffering for replay and processing
  - **Progress Feedback**: Integration with progress indicators
  """

  use GenServer

  alias RubberDuck.Interface.CLI.{ResponseFormatter, ProgressIndicators}

  require Logger

  @type stream_id :: String.t() | atom()
  @type stream_mode :: :character | :word | :chunk | :line
  @type stream_state :: :idle | :streaming | :paused | :completed | :error | :cancelled
  @type stream_options :: [
    mode: stream_mode(),
    rate: pos_integer(),
    buffer_size: pos_integer(),
    auto_scroll: boolean(),
    show_progress: boolean(),
    format: boolean()
  ]

  @type stream_info :: %{
    id: stream_id(),
    state: stream_state(),
    mode: stream_mode(),
    buffer: String.t(),
    position: non_neg_integer(),
    total_size: non_neg_integer() | nil,
    rate: pos_integer(),
    start_time: integer(),
    last_update: integer(),
    config: map(),
    producer_pid: pid() | nil,
    consumer_pid: pid() | nil
  }

  # Default configuration
  @default_config %{
    character_rate: 50,    # characters per second
    word_rate: 10,         # words per second  
    chunk_rate: 5,         # chunks per second
    line_rate: 2,          # lines per second
    buffer_size: 8192,     # bytes
    auto_scroll: true,
    show_progress: true,
    format_output: true,
    pause_on_punctuation: true,
    punctuation_delay: 200  # milliseconds
  }

  @doc """
  Start the streaming manager.
  """
  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Start streaming text to the terminal.
  """
  def start_stream(id, text, opts \\ []) do
    GenServer.call(__MODULE__, {:start_stream, id, text, opts})
  end

  @doc """
  Start streaming from a data source (GenServer, Task, etc.).
  """
  def start_producer_stream(id, producer_pid, opts \\ []) do
    GenServer.call(__MODULE__, {:start_producer_stream, id, producer_pid, opts})
  end

  @doc """
  Add data to an existing stream.
  """
  def stream_data(id, data) do
    GenServer.call(__MODULE__, {:stream_data, id, data})
  end

  @doc """
  Pause a stream.
  """
  def pause_stream(id) do
    GenServer.call(__MODULE__, {:pause_stream, id})
  end

  @doc """
  Resume a paused stream.
  """
  def resume_stream(id) do
    GenServer.call(__MODULE__, {:resume_stream, id})
  end

  @doc """
  Cancel a stream.
  """
  def cancel_stream(id) do
    GenServer.call(__MODULE__, {:cancel_stream, id})
  end

  @doc """
  Complete a stream.
  """
  def complete_stream(id) do
    GenServer.call(__MODULE__, {:complete_stream, id})
  end

  @doc """
  Get stream status.
  """
  def get_stream_status(id) do
    GenServer.call(__MODULE__, {:get_stream_status, id})
  end

  @doc """
  List all active streams.
  """
  def list_streams do
    GenServer.call(__MODULE__, :list_streams)
  end

  @doc """
  Stream text with a simple API (blocks until complete).
  """
  def stream_text(text, opts \\ []) do
    id = Keyword.get(opts, :id, :simple_stream)
    mode = Keyword.get(opts, :mode, :character)
    rate = Keyword.get(opts, :rate, get_default_rate(mode))
    
    case start_stream(id, text, Keyword.put(opts, :rate, rate)) do
      :ok ->
        wait_for_stream_completion(id)
      error ->
        error
    end
  end

  @doc """
  Stream text word by word with natural timing.
  """
  def stream_natural(text, opts \\ []) do
    opts = Keyword.merge([mode: :word, rate: 8, pause_on_punctuation: true], opts)
    stream_text(text, opts)
  end

  @doc """
  Stream text character by character like typing.
  """
  def stream_typing(text, opts \\ []) do
    opts = Keyword.merge([mode: :character, rate: 50], opts)
    stream_text(text, opts)
  end

  # GenServer implementation

  @impl true
  def init(config) do
    merged_config = Map.merge(@default_config, config)
    
    state = %{
      streams: %{},
      config: merged_config,
      stream_counter: 0
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:start_stream, id, text, opts}, _from, state) do
    if Map.has_key?(state.streams, id) do
      {:reply, {:error, :stream_exists}, state}
    else
      stream_info = create_stream_info(id, text, opts, state.config)
      new_state = %{state | streams: Map.put(state.streams, id, stream_info)}
      
      # Start streaming process
      start_streaming_process(stream_info)
      
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:start_producer_stream, id, producer_pid, opts}, _from, state) do
    if Map.has_key?(state.streams, id) do
      {:reply, {:error, :stream_exists}, state}
    else
      stream_info = create_producer_stream_info(id, producer_pid, opts, state.config)
      new_state = %{state | streams: Map.put(state.streams, id, stream_info)}
      
      # Setup producer monitoring
      setup_producer_monitoring(stream_info)
      
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:stream_data, id, data}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      stream_info ->
        updated_stream = append_to_stream_buffer(stream_info, data)
        new_state = %{state | streams: Map.put(state.streams, id, updated_stream)}
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:pause_stream, id}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      stream_info ->
        updated_stream = %{stream_info | state: :paused}
        new_state = %{state | streams: Map.put(state.streams, id, updated_stream)}
        
        send_stream_control(stream_info, :pause)
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:resume_stream, id}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      %{state: :paused} = stream_info ->
        updated_stream = %{stream_info | state: :streaming}
        new_state = %{state | streams: Map.put(state.streams, id, updated_stream)}
        
        send_stream_control(stream_info, :resume)
        
        {:reply, :ok, new_state}
        
      stream_info ->
        {:reply, {:error, {:invalid_state, stream_info.state}}, state}
    end
  end

  def handle_call({:cancel_stream, id}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      stream_info ->
        cleanup_stream(stream_info)
        new_state = %{state | streams: Map.delete(state.streams, id)}
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:complete_stream, id}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      stream_info ->
        # Mark as completed and cleanup
        complete_stream_display(stream_info)
        cleanup_stream(stream_info)
        new_state = %{state | streams: Map.delete(state.streams, id)}
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_stream_status, id}, _from, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}
        
      stream_info ->
        status = extract_stream_status(stream_info)
        {:reply, {:ok, status}, state}
    end
  end

  def handle_call(:list_streams, _from, state) do
    stream_list = state.streams
    |> Map.values()
    |> Enum.map(&extract_stream_status/1)
    
    {:reply, stream_list, state}
  end

  @impl true
  def handle_info({:stream_chunk, id, chunk}, state) do
    case Map.get(state.streams, id) do
      nil ->
        Logger.warning("Received chunk for unknown stream: #{id}")
        {:noreply, state}
        
      stream_info ->
        display_stream_chunk(chunk, stream_info)
        
        # Update stream position
        new_position = stream_info.position + byte_size(chunk)
        updated_stream = %{stream_info | 
          position: new_position,
          last_update: System.monotonic_time(:millisecond)
        }
        
        new_state = %{state | streams: Map.put(state.streams, id, updated_stream)}
        
        {:noreply, new_state}
    end
  end

  def handle_info({:stream_complete, id}, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:noreply, state}
        
      stream_info ->
        complete_stream_display(stream_info)
        cleanup_stream(stream_info)
        new_state = %{state | streams: Map.delete(state.streams, id)}
        
        {:noreply, new_state}
    end
  end

  def handle_info({:stream_error, id, reason}, state) do
    case Map.get(state.streams, id) do
      nil ->
        {:noreply, state}
        
      stream_info ->
        handle_stream_error(stream_info, reason)
        cleanup_stream(stream_info)
        new_state = %{state | streams: Map.delete(state.streams, id)}
        
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle producer process exit
    stream_with_producer = state.streams
    |> Enum.find(fn {_id, stream} -> stream.producer_pid == pid end)
    
    case stream_with_producer do
      {id, stream_info} ->
        Logger.warning("Stream producer #{id} exited: #{inspect(reason)}")
        handle_stream_error(stream_info, {:producer_exit, reason})
        new_state = %{state | streams: Map.delete(state.streams, id)}
        {:noreply, new_state}
        
      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Stream creation and management

  defp create_stream_info(id, text, opts, config) do
    mode = Keyword.get(opts, :mode, :character)
    rate = Keyword.get(opts, :rate, get_default_rate(mode))
    
    %{
      id: id,
      state: :streaming,
      mode: mode,
      buffer: text,
      position: 0,
      total_size: byte_size(text),
      rate: rate,
      start_time: System.monotonic_time(:millisecond),
      last_update: System.monotonic_time(:millisecond),
      config: Map.merge(config, Map.new(opts)),
      producer_pid: nil,
      consumer_pid: nil
    }
  end

  defp create_producer_stream_info(id, producer_pid, opts, config) do
    mode = Keyword.get(opts, :mode, :chunk)
    rate = Keyword.get(opts, :rate, get_default_rate(mode))
    
    %{
      id: id,
      state: :streaming,
      mode: mode,
      buffer: "",
      position: 0,
      total_size: nil,
      rate: rate,
      start_time: System.monotonic_time(:millisecond),
      last_update: System.monotonic_time(:millisecond),
      config: Map.merge(config, Map.new(opts)),
      producer_pid: producer_pid,
      consumer_pid: nil
    }
  end

  defp start_streaming_process(stream_info) do
    # Start a process to handle streaming
    consumer_pid = spawn_link(fn ->
      stream_consumer_loop(stream_info)
    end)
    
    # Update the stream info with consumer PID
    # This would be done via a GenServer call in production
    send(self(), {:update_consumer, stream_info.id, consumer_pid})
  end

  defp stream_consumer_loop(stream_info) do
    case stream_info.mode do
      :character -> stream_by_character(stream_info)
      :word -> stream_by_word(stream_info)
      :chunk -> stream_by_chunk(stream_info)
      :line -> stream_by_line(stream_info)
    end
  end

  defp stream_by_character(stream_info) do
    delay = calculate_delay(stream_info.rate)
    
    stream_info.buffer
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.each(fn {char, index} ->
      if stream_info.state == :streaming do
        display_character(char, stream_info)
        
        # Add extra delay for punctuation if configured
        actual_delay = if should_pause_for_punctuation?(char, stream_info) do
          delay + stream_info.config.punctuation_delay
        else
          delay
        end
        
        Process.sleep(actual_delay)
        
        # Send progress update
        send(self(), {:stream_chunk, stream_info.id, char})
      end
    end)
    
    send(self(), {:stream_complete, stream_info.id})
  end

  defp stream_by_word(stream_info) do
    delay = calculate_delay(stream_info.rate)
    
    stream_info.buffer
    |> String.split(~r/\s+/)
    |> Enum.each(fn word ->
      if stream_info.state == :streaming do
        display_word(word <> " ", stream_info)
        Process.sleep(delay)
        
        send(self(), {:stream_chunk, stream_info.id, word <> " "})
      end
    end)
    
    send(self(), {:stream_complete, stream_info.id})
  end

  defp stream_by_chunk(stream_info) do
    delay = calculate_delay(stream_info.rate)
    chunk_size = stream_info.config[:chunk_size] || 100
    
    stream_info.buffer
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size)
    |> Enum.each(fn chunk_chars ->
      if stream_info.state == :streaming do
        chunk = Enum.join(chunk_chars)
        display_chunk(chunk, stream_info)
        Process.sleep(delay)
        
        send(self(), {:stream_chunk, stream_info.id, chunk})
      end
    end)
    
    send(self(), {:stream_complete, stream_info.id})
  end

  defp stream_by_line(stream_info) do
    delay = calculate_delay(stream_info.rate)
    
    stream_info.buffer
    |> String.split("\n")
    |> Enum.each(fn line ->
      if stream_info.state == :streaming do
        display_line(line <> "\n", stream_info)
        Process.sleep(delay)
        
        send(self(), {:stream_chunk, stream_info.id, line <> "\n"})
      end
    end)
    
    send(self(), {:stream_complete, stream_info.id})
  end

  # Display functions

  defp display_character(char, stream_info) do
    if stream_info.config.format_output do
      formatted = ResponseFormatter.highlight_code(char, nil, stream_info.config)
      IO.write(formatted)
    else
      IO.write(char)
    end
  end

  defp display_word(word, stream_info) do
    if stream_info.config.format_output do
      formatted = ResponseFormatter.highlight_code(word, nil, stream_info.config)
      IO.write(formatted)
    else
      IO.write(word)
    end
  end

  defp display_chunk(chunk, stream_info) do
    if stream_info.config.format_output do
      formatted = ResponseFormatter.highlight_code(chunk, nil, stream_info.config)
      IO.write(formatted)
    else
      IO.write(chunk)
    end
  end

  defp display_line(line, stream_info) do
    if stream_info.config.format_output do
      formatted = ResponseFormatter.highlight_code(line, nil, stream_info.config)
      IO.write(formatted)
    else
      IO.write(line)
    end
  end

  defp display_stream_chunk(chunk, stream_info) do
    case ResponseFormatter.format_stream(chunk, nil, stream_info.config) do
      {:ok, formatted} -> IO.write(formatted)
      {:error, _} -> IO.write(chunk)
    end
  end

  defp complete_stream_display(stream_info) do
    if stream_info.config.show_progress do
      ProgressIndicators.complete_progress(stream_info.id, "Stream completed")
    end
    
    # Add final newline if needed
    IO.write("\n")
  end

  defp handle_stream_error(stream_info, reason) do
    error_msg = "Stream error: #{inspect(reason)}"
    
    if stream_info.config.show_progress do
      ProgressIndicators.error_progress(stream_info.id, error_msg)
    else
      IO.puts(:stderr, error_msg)
    end
  end

  # Utility functions

  defp get_default_rate(:character), do: 50
  defp get_default_rate(:word), do: 10
  defp get_default_rate(:chunk), do: 5
  defp get_default_rate(:line), do: 2

  defp calculate_delay(rate) when rate > 0 do
    div(1000, rate)
  end
  defp calculate_delay(_), do: 100

  defp should_pause_for_punctuation?(char, stream_info) do
    stream_info.config.pause_on_punctuation and char in [".", "!", "?", ";"]
  end

  defp append_to_stream_buffer(stream_info, data) do
    %{stream_info | buffer: stream_info.buffer <> data}
  end

  defp send_stream_control(stream_info, command) do
    if stream_info.consumer_pid do
      send(stream_info.consumer_pid, {:control, command})
    end
  end

  defp setup_producer_monitoring(stream_info) do
    if stream_info.producer_pid do
      Process.monitor(stream_info.producer_pid)
    end
  end

  defp cleanup_stream(stream_info) do
    if stream_info.consumer_pid do
      Process.exit(stream_info.consumer_pid, :normal)
    end
    
    if stream_info.config.show_progress do
      ProgressIndicators.cancel_progress(stream_info.id)
    end
  end

  defp extract_stream_status(stream_info) do
    elapsed = System.monotonic_time(:millisecond) - stream_info.start_time
    
    progress = if stream_info.total_size do
      stream_info.position / stream_info.total_size * 100
    else
      nil
    end
    
    %{
      id: stream_info.id,
      state: stream_info.state,
      mode: stream_info.mode,
      progress: progress,
      position: stream_info.position,
      total_size: stream_info.total_size,
      elapsed_ms: elapsed,
      rate: calculate_current_rate(stream_info, elapsed)
    }
  end

  defp calculate_current_rate(stream_info, elapsed_ms) do
    if elapsed_ms > 0 and stream_info.position > 0 do
      stream_info.position / elapsed_ms * 1000  # items per second
    else
      0
    end
  end

  defp wait_for_stream_completion(id) do
    receive do
      {:stream_complete, ^id} -> :ok
      {:stream_error, ^id, reason} -> {:error, reason}
    after
      30_000 -> {:error, :timeout}
    end
  end
end