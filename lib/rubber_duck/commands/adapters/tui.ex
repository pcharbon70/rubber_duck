defmodule RubberDuck.Commands.Adapters.TUI do
  @moduledoc """
  TUI (Terminal User Interface) adapter for the unified command system.
  
  Provides an interface for terminal-based user interfaces to interact with
  the command processor, handling input parsing and output formatting for
  terminal display.
  """

  alias RubberDuck.Commands.{Parser, Processor, Command, Context}

  @doc """
  Execute a TUI command with the given input.
  
  ## Parameters
  - `input` - String input from the TUI (e.g., user typed command)
  - `session` - TUI session information
  
  ## Returns
  - `{:ok, formatted_result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  def execute(input, session) when is_binary(input) do
    with {:ok, context} <- build_context(session),
         {:ok, command} <- Parser.parse(input, :tui, context),
         {:ok, result} <- Processor.execute(command) do
      {:ok, result}
    end
  end

  @doc """
  Execute a TUI command asynchronously.
  
  Returns a request ID for tracking the async execution.
  """
  def execute_async(input, session) when is_binary(input) do
    with {:ok, context} <- build_context(session),
         {:ok, command} <- Parser.parse(input, :tui, context),
         {:ok, result} <- Processor.execute_async(command) do
      {:ok, result}
    end
  end

  @doc """
  Parse TUI input into a Command struct without executing.
  """
  def parse(input, session) when is_binary(input) do
    with {:ok, context} <- build_context(session),
         {:ok, command} <- Parser.parse(input, :tui, context) do
      {:ok, command}
    end
  end

  @doc """
  Get the status of an async command execution.
  """
  def get_status(request_id) do
    Processor.get_status(request_id)
  end

  @doc """
  Cancel an async command execution.
  """
  def cancel(request_id) do
    Processor.cancel(request_id)
  end

  @doc """
  Format command result for terminal display.
  
  Applies terminal-specific formatting like colors and layout.
  """
  def format_for_terminal(result, options \\ []) do
    colors_enabled = Keyword.get(options, :colors, true)
    max_width = Keyword.get(options, :max_width, 80)
    
    case result do
      {:ok, data} when is_binary(data) ->
        wrap_text(data, max_width)
        
      {:ok, data} when is_map(data) ->
        format_map_for_terminal(data, colors_enabled, max_width)
        
      {:ok, data} when is_list(data) ->
        format_list_for_terminal(data, colors_enabled, max_width)
        
      {:error, reason} ->
        format_error_for_terminal(reason, colors_enabled)
    end
  end

  @doc """
  Build a progress indicator for long-running commands.
  """
  def build_progress_indicator(request_id, options \\ []) do
    case get_status(request_id) do
      {:ok, %{status: :running, progress: progress}} ->
        build_progress_bar(progress, options)
        
      {:ok, %{status: :completed}} ->
        build_progress_bar(100, options)
        
      {:ok, %{status: :failed}} ->
        format_error_for_terminal("Command failed", Keyword.get(options, :colors, true))
        
      _ ->
        "Status unknown"
    end
  end

  @doc """
  Create an interactive command prompt for TUI.
  """
  def create_prompt(session, options \\ []) do
    user_id = Map.get(session, :user_id, "user")
    project = Map.get(session, :project_id, "project")
    colors_enabled = Keyword.get(options, :colors, true)
    
    if colors_enabled do
      IO.ANSI.green() <> "#{user_id}@#{project}" <> IO.ANSI.reset() <> " $ "
    else
      "#{user_id}@#{project} $ "
    end
  end

  @doc """
  Validate and autocomplete TUI input.
  
  Provides command suggestions and validates syntax.
  """
  def autocomplete(partial_input, session) do
    # Simple autocomplete based on available commands
    available_commands = [:health, :analyze, :generate, :complete, :refactor, :test, :llm]
    
    words = String.split(partial_input)
    
    case words do
      [] ->
        Enum.map(available_commands, &to_string/1)
        
      [partial_command] ->
        available_commands
        |> Enum.map(&to_string/1)
        |> Enum.filter(&String.starts_with?(&1, partial_command))
        
      [command | _rest] ->
        # Could provide subcommand or option completion here
        []
    end
  end

  # Private functions

  defp build_context(session) do
    context_data = %{
      user_id: Map.get(session, :user_id, "tui_user"),
      project_id: Map.get(session, :project_id),
      conversation_id: Map.get(session, :conversation_id),
      session_id: Map.get(session, :session_id, generate_session_id()),
      permissions: Map.get(session, :permissions, [:read, :write, :execute]),
      metadata: %{
        transport: "tui",
        terminal_width: Map.get(session, :terminal_width, 80),
        terminal_height: Map.get(session, :terminal_height, 24),
        colors_supported: Map.get(session, :colors_supported, true)
      }
    }
    
    Context.new(context_data)
  end

  defp generate_session_id do
    "tui_session_#{System.system_time(:millisecond)}_#{:rand.uniform(1000)}"
  end

  defp wrap_text(text, max_width) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, max_width))
    |> Enum.join("\n")
  end

  defp wrap_line(line, max_width) when byte_size(line) <= max_width do
    [line]
  end
  defp wrap_line(line, max_width) do
    {wrapped, rest} = String.split_at(line, max_width)
    [wrapped | wrap_line(rest, max_width)]
  end

  defp format_map_for_terminal(data, colors_enabled, max_width) do
    data
    |> Enum.map(fn {key, value} ->
      key_str = if colors_enabled do
        IO.ANSI.blue() <> to_string(key) <> IO.ANSI.reset()
      else
        to_string(key)
      end
      
      value_str = format_value_for_terminal(value, colors_enabled)
      "#{key_str}: #{value_str}"
    end)
    |> Enum.join("\n")
    |> wrap_text(max_width)
  end

  defp format_list_for_terminal(data, colors_enabled, max_width) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      prefix = if colors_enabled do
        IO.ANSI.yellow() <> "#{index + 1}." <> IO.ANSI.reset()
      else
        "#{index + 1}."
      end
      
      item_str = format_value_for_terminal(item, colors_enabled)
      "#{prefix} #{item_str}"
    end)
    |> Enum.join("\n")
    |> wrap_text(max_width)
  end

  defp format_value_for_terminal(value, colors_enabled) when is_map(value) do
    format_map_for_terminal(value, colors_enabled, 60)
  end
  defp format_value_for_terminal(value, _colors_enabled) when is_binary(value) do
    value
  end
  defp format_value_for_terminal(value, _colors_enabled) do
    inspect(value, pretty: true)
  end

  defp format_error_for_terminal(reason, colors_enabled) do
    error_text = "Error: #{reason}"
    
    if colors_enabled do
      IO.ANSI.red() <> error_text <> IO.ANSI.reset()
    else
      error_text
    end
  end

  defp build_progress_bar(progress, options) do
    width = Keyword.get(options, :width, 40)
    colors_enabled = Keyword.get(options, :colors, true)
    
    filled = round(progress * width / 100)
    empty = width - filled
    
    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    
    if colors_enabled do
      IO.ANSI.green() <> bar <> IO.ANSI.reset() <> " #{progress}%"
    else
      bar <> " #{progress}%"
    end
  end
end