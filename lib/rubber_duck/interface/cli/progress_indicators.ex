defmodule RubberDuck.Interface.CLI.ProgressIndicators do
  @moduledoc """
  Progress indicators and visual feedback for CLI operations.
  
  This module provides various types of progress indicators for long-running
  operations in the CLI interface, including:
  
  - Spinners for indeterminate progress
  - Progress bars for determinate progress  
  - Streaming text display
  - Status indicators
  - Multi-line progress tracking
  
  ## Features
  
  - **Animated Spinners**: Multiple spinner styles for different contexts
  - **Progress Bars**: Percentage and visual progress tracking
  - **Streaming Display**: Real-time text streaming with rate limiting
  - **Status Updates**: Color-coded status indicators
  - **Multi-task Progress**: Track multiple operations simultaneously
  - **Terminal Integration**: Respects terminal capabilities and size
  - **Graceful Degradation**: Falls back for non-interactive terminals
  """

  use GenServer

  require Logger

  @type progress_type :: :spinner | :bar | :stream | :status | :multi
  @type progress_id :: String.t() | atom()
  @type progress_state :: %{
    id: progress_id(),
    type: progress_type(),
    message: String.t(),
    current: number(),
    total: number() | nil,
    status: :running | :completed | :error | :cancelled,
    start_time: integer(),
    last_update: integer(),
    config: map()
  }

  # Spinner frame sets
  @spinners %{
    dots: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    line: ["-", "\\", "|", "/"],
    arrow: ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"],
    bounce: ["⠁", "⠂", "⠄", "⠂"],
    pulse: ["⠈", "⠉", "⠋", "⠓", "⠂", "⠂", "⠒", "⠲", "⠴", "⠤", "⠄", "⠄", "⠤", "⠴", "⠲", "⠒"],
    duck: ["🦆", "🐥", "🦆", "🐥"]
  }

  # Progress bar styles
  @progress_styles %{
    classic: %{filled: "█", empty: "░", brackets: ["[", "]"]},
    modern: %{filled: "━", empty: "┅", brackets: ["", ""]},
    dots: %{filled: "●", empty: "○", brackets: ["", ""]},
    blocks: %{filled: "▓", empty: "░", brackets: ["▕", "▏"]}
  }

  # ANSI escape codes
  @ansi %{
    hide_cursor: "\e[?25l",
    show_cursor: "\e[?25h",
    save_position: "\e[s",
    restore_position: "\e[u",
    clear_line: "\e[2K",
    move_up: "\e[1A",
    move_down: "\e[1B"
  }

  @doc """
  Start the progress indicators manager.
  """
  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Create a new progress indicator.
  """
  def start_progress(id, type, message, opts \\ []) do
    GenServer.call(__MODULE__, {:start_progress, id, type, message, opts})
  end

  @doc """
  Update progress indicator.
  """
  def update_progress(id, current, opts \\ []) do
    GenServer.call(__MODULE__, {:update_progress, id, current, opts})
  end

  @doc """
  Update progress message.
  """
  def update_message(id, message) do
    GenServer.call(__MODULE__, {:update_message, id, message})
  end

  @doc """
  Complete a progress indicator.
  """
  def complete_progress(id, final_message \\ nil) do
    GenServer.call(__MODULE__, {:complete_progress, id, final_message})
  end

  @doc """
  Mark progress as error.
  """
  def error_progress(id, error_message \\ nil) do
    GenServer.call(__MODULE__, {:error_progress, id, error_message})
  end

  @doc """
  Cancel a progress indicator.
  """
  def cancel_progress(id) do
    GenServer.call(__MODULE__, {:cancel_progress, id})
  end

  @doc """
  Clear all progress indicators.
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  @doc """
  Stream text with progress indication.
  """
  def stream_text(text, opts \\ []) do
    id = Keyword.get(opts, :id, :stream)
    rate = Keyword.get(opts, :rate, 50)  # characters per second
    
    start_progress(id, :stream, "Streaming response...", opts)
    
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.each(fn {char, index} ->
      IO.write(char)
      
      # Update progress periodically
      if rem(index, 10) == 0 do
        progress = (index + 1) / String.length(text) * 100
        update_progress(id, progress, message: "Streaming... #{round(progress)}%")
      end
      
      # Rate limiting
      if rate > 0 do
        Process.sleep(div(1000, rate))
      end
    end)
    
    complete_progress(id, "Stream complete")
  end

  @doc """
  Show a simple spinner for a task.
  """
  def with_spinner(message, fun, opts \\ []) do
    id = Keyword.get(opts, :id, :spinner)
    style = Keyword.get(opts, :style, :dots)
    
    start_progress(id, :spinner, message, style: style)
    
    try do
      result = fun.()
      complete_progress(id, "✓ #{message}")
      result
    rescue
      error ->
        error_progress(id, "✗ #{message} - #{Exception.message(error)}")
        reraise error, __STACKTRACE__
    catch
      :exit, reason ->
        error_progress(id, "✗ #{message} - Process exited: #{inspect(reason)}")
        exit(reason)
    end
  end

  @doc """
  Show a progress bar for a task with known steps.
  """
  def with_progress_bar(message, total, fun, opts \\ []) do
    id = Keyword.get(opts, :id, :progress_bar)
    
    start_progress(id, :bar, message, total: total)
    
    try do
      result = fun.(fn current -> 
        update_progress(id, current)
      end)
      
      complete_progress(id, "✓ #{message}")
      result
    rescue
      error ->
        error_progress(id, "✗ #{message} - #{Exception.message(error)}")
        reraise error, __STACKTRACE__
    end
  end

  # GenServer implementation

  @impl true
  def init(config) do
    state = %{
      progress_items: %{},
      config: config,
      terminal_size: get_terminal_size(),
      animation_pid: nil,
      is_tty: is_interactive_terminal()
    }
    
    if state.is_tty do
      IO.write(@ansi.hide_cursor)
    end
    
    {:ok, state}
  end

  @impl true
  def handle_call({:start_progress, id, type, message, opts}, _from, state) do
    progress = %{
      id: id,
      type: type,
      message: message,
      current: 0,
      total: Keyword.get(opts, :total),
      status: :running,
      start_time: System.monotonic_time(:millisecond),
      last_update: System.monotonic_time(:millisecond),
      config: Map.merge(state.config, Map.new(opts))
    }
    
    new_state = %{state | progress_items: Map.put(state.progress_items, id, progress)}
    
    # Start animation if this is the first progress item
    new_state = maybe_start_animation(new_state)
    
    render_progress(new_state)
    
    {:reply, :ok, new_state}
  end

  def handle_call({:update_progress, id, current, opts}, _from, state) do
    case Map.get(state.progress_items, id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      progress ->
        updated_progress = progress
        |> Map.put(:current, current)
        |> Map.put(:last_update, System.monotonic_time(:millisecond))
        
        # Update message if provided
        updated_progress = case Keyword.get(opts, :message) do
          nil -> updated_progress
          new_message -> Map.put(updated_progress, :message, new_message)
        end
        
        new_state = %{state | 
          progress_items: Map.put(state.progress_items, id, updated_progress)
        }
        
        render_progress(new_state)
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_message, id, message}, _from, state) do
    case Map.get(state.progress_items, id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      progress ->
        updated_progress = Map.put(progress, :message, message)
        new_state = %{state | 
          progress_items: Map.put(state.progress_items, id, updated_progress)
        }
        
        render_progress(new_state)
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:complete_progress, id, final_message}, _from, state) do
    case Map.get(state.progress_items, id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      progress ->
        final_msg = final_message || "✓ #{progress.message}"
        
        # Show completion message
        if state.is_tty do
          clear_progress_line(state)
          IO.puts(colorize(final_msg, :green, state.config))
        else
          IO.puts(final_msg)
        end
        
        new_state = %{state | 
          progress_items: Map.delete(state.progress_items, id)
        }
        
        # Stop animation if no more progress items
        new_state = maybe_stop_animation(new_state)
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:error_progress, id, error_message}, _from, state) do
    case Map.get(state.progress_items, id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      progress ->
        error_msg = error_message || "✗ #{progress.message}"
        
        # Show error message
        if state.is_tty do
          clear_progress_line(state)
          IO.puts(colorize(error_msg, :red, state.config))
        else
          IO.puts(error_msg)
        end
        
        new_state = %{state | 
          progress_items: Map.delete(state.progress_items, id)
        }
        
        # Stop animation if no more progress items
        new_state = maybe_stop_animation(new_state)
        
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:cancel_progress, id}, _from, state) do
    new_state = %{state | progress_items: Map.delete(state.progress_items, id)}
    new_state = maybe_stop_animation(new_state)
    render_progress(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:clear_all, _from, state) do
    if state.is_tty do
      clear_all_progress_lines(state)
      IO.write(@ansi.show_cursor)
    end
    
    new_state = %{state | progress_items: %{}}
    new_state = maybe_stop_animation(new_state)
    
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:animate, state) do
    render_progress(state)
    
    # Schedule next animation frame
    if not Enum.empty?(state.progress_items) do
      Process.send_after(self(), :animate, 100)
    end
    
    {:noreply, state}
  end

  def handle_info({:terminal_resize, new_size}, state) do
    new_state = %{state | terminal_size: new_size}
    render_progress(new_state)
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.is_tty do
      clear_all_progress_lines(state)
      IO.write(@ansi.show_cursor)
    end
    :ok
  end

  # Rendering functions

  defp render_progress(state) do
    if state.is_tty and not Enum.empty?(state.progress_items) do
      clear_progress_area(state)
      
      state.progress_items
      |> Map.values()
      |> Enum.sort_by(& &1.start_time)
      |> Enum.each(&render_progress_item(&1, state))
      
      # Move cursor back up if multiple items
      item_count = map_size(state.progress_items)
      if item_count > 1 do
        IO.write(String.duplicate(@ansi.move_up, item_count - 1))
      end
    end
  end

  defp render_progress_item(progress, state) do
    line = case progress.type do
      :spinner -> render_spinner(progress, state)
      :bar -> render_progress_bar(progress, state)
      :stream -> render_stream_progress(progress, state)
      :status -> render_status(progress, state)
      _ -> "#{progress.message}"
    end
    
    # Truncate line to terminal width
    {_, width} = state.terminal_size
    truncated_line = String.slice(line, 0, width - 1)
    
    IO.write("\r#{@ansi.clear_line}#{truncated_line}")
    
    # Move to next line if multiple progress items
    if map_size(state.progress_items) > 1 do
      IO.write("\n")
    end
  end

  defp render_spinner(progress, state) do
    style = progress.config[:style] || :dots
    frames = Map.get(@spinners, style, @spinners.dots)
    
    # Calculate frame based on time
    frame_index = div(System.monotonic_time(:millisecond) - progress.start_time, 100)
    frame = Enum.at(frames, rem(frame_index, length(frames)))
    
    spinner_text = colorize(frame, :cyan, state.config)
    message_text = progress.message
    
    elapsed = format_elapsed_time(progress.start_time)
    
    "#{spinner_text} #{message_text} #{colorize("(#{elapsed})", :dim, state.config)}"
  end

  defp render_progress_bar(progress, state) do
    style_name = progress.config[:style] || :classic
    style = Map.get(@progress_styles, style_name, @progress_styles.classic)
    
    {_, width} = state.terminal_size
    
    # Calculate progress percentage
    percentage = if progress.total && progress.total > 0 do
      min(progress.current / progress.total * 100, 100)
    else
      0
    end
    
    # Calculate bar width (leave space for text)
    message_space = String.length(progress.message) + 20
    bar_width = max(width - message_space, 10)
    
    filled_width = round(bar_width * percentage / 100)
    empty_width = bar_width - filled_width
    
    filled_part = String.duplicate(style.filled, filled_width)
    empty_part = String.duplicate(style.empty, empty_width)
    
    bar = "#{style.brackets |> List.first()}#{filled_part}#{empty_part}#{style.brackets |> List.last()}"
    percentage_text = "#{Float.round(percentage, 1)}%"
    
    elapsed = format_elapsed_time(progress.start_time)
    
    bar_colored = colorize(bar, :cyan, state.config)
    percentage_colored = colorize(percentage_text, :yellow, state.config)
    elapsed_colored = colorize("(#{elapsed})", :dim, state.config)
    
    "#{progress.message} #{bar_colored} #{percentage_colored} #{elapsed_colored}"
  end

  defp render_stream_progress(progress, state) do
    # For streaming, show current position/speed
    elapsed_ms = System.monotonic_time(:millisecond) - progress.start_time
    rate = if elapsed_ms > 0, do: progress.current / elapsed_ms * 1000, else: 0
    
    rate_text = cond do
      rate > 1000 -> "#{Float.round(rate / 1000, 1)}k/s"
      rate > 1 -> "#{Float.round(rate, 1)}/s"
      true -> "#{Float.round(rate, 2)}/s"
    end
    
    dots = String.duplicate(".", rem(div(elapsed_ms, 500), 4))
    
    stream_indicator = colorize("⟳", :cyan, state.config)
    rate_colored = colorize(rate_text, :yellow, state.config)
    
    "#{stream_indicator} #{progress.message}#{dots} #{rate_colored}"
  end

  defp render_status(progress, state) do
    status_icon = case progress.status do
      :running -> colorize("●", :blue, state.config)
      :completed -> colorize("✓", :green, state.config)
      :error -> colorize("✗", :red, state.config)
      :cancelled -> colorize("○", :dim, state.config)
    end
    
    elapsed = format_elapsed_time(progress.start_time)
    elapsed_colored = colorize("(#{elapsed})", :dim, state.config)
    
    "#{status_icon} #{progress.message} #{elapsed_colored}"
  end

  # Animation management

  defp maybe_start_animation(state) do
    if state.animation_pid == nil and not Enum.empty?(state.progress_items) do
      Process.send_after(self(), :animate, 100)
      %{state | animation_pid: :started}
    else
      state
    end
  end

  defp maybe_stop_animation(state) do
    if Enum.empty?(state.progress_items) do
      %{state | animation_pid: nil}
    else
      state
    end
  end

  # Terminal control functions

  defp clear_progress_line(_state) do
    IO.write("\r#{@ansi.clear_line}")
  end

  defp clear_progress_area(state) do
    # Clear current line
    IO.write("\r#{@ansi.clear_line}")
  end

  defp clear_all_progress_lines(state) do
    item_count = map_size(state.progress_items)
    
    # Clear each line
    for _i <- 1..item_count do
      IO.write("#{@ansi.clear_line}\n")
    end
    
    # Move cursor back up
    if item_count > 0 do
      IO.write(String.duplicate(@ansi.move_up, item_count))
    end
  end

  # Utility functions

  defp get_terminal_size do
    case System.cmd("stty", ["size"], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(String.trim(output)) do
          [rows, cols] ->
            {String.to_integer(rows), String.to_integer(cols)}
          _ ->
            {24, 80}
        end
      _ ->
        {24, 80}
    end
  rescue
    _ -> {24, 80}
  end

  defp is_interactive_terminal do
    # Check if stdout is a TTY
    case System.cmd("test", ["-t", "1"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp format_elapsed_time(start_time) do
    elapsed_ms = System.monotonic_time(:millisecond) - start_time
    
    cond do
      elapsed_ms < 1000 -> "#{elapsed_ms}ms"
      elapsed_ms < 60_000 -> "#{Float.round(elapsed_ms / 1000, 1)}s"
      elapsed_ms < 3_600_000 -> 
        minutes = div(elapsed_ms, 60_000)
        seconds = rem(div(elapsed_ms, 1000), 60)
        "#{minutes}m #{seconds}s"
      true ->
        hours = div(elapsed_ms, 3_600_000)
        minutes = rem(div(elapsed_ms, 60_000), 60)
        "#{hours}h #{minutes}m"
    end
  end

  defp colorize(text, color, config) do
    if config[:colors] != false do
      case color do
        :cyan -> "\e[36m#{text}\e[0m"
        :green -> "\e[32m#{text}\e[0m"
        :yellow -> "\e[33m#{text}\e[0m"
        :red -> "\e[31m#{text}\e[0m"
        :blue -> "\e[34m#{text}\e[0m"
        :dim -> "\e[2m#{text}\e[0m"
        _ -> text
      end
    else
      text
    end
  end
end