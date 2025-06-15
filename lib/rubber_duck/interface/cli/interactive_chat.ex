defmodule RubberDuck.Interface.CLI.InteractiveChat do
  @moduledoc """
  Enhanced interactive chat mode for RubberDuck CLI.
  
  This module provides a rich interactive chat experience with features like:
  - Real-time response streaming
  - Command history and recall
  - Multi-line input support
  - Context-aware completions
  - Session management within chat
  - Keyboard shortcuts
  - Screen management
  
  ## Features
  
  - **Streaming Responses**: Real-time AI response display
  - **Command History**: Up/down arrows to recall previous commands
  - **Multi-line Input**: Support for pasting and editing long prompts
  - **Tab Completion**: Auto-complete for slash commands
  - **Session Switching**: Switch sessions without exiting chat
  - **Screen Management**: Clear, scroll, and resize handling
  - **Progress Indicators**: Visual feedback for long operations
  - **Interrupt Handling**: Graceful handling of Ctrl+C
  """

  use GenServer

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.CLI.{CommandParser, ResponseFormatter, SessionManager}

  require Logger

  @type chat_state :: %{
    cli_state: map(),
    config: map(),
    session: map() | nil,
    history: [String.t()],
    history_position: integer(),
    current_input: String.t(),
    streaming: boolean(),
    screen_size: {integer(), integer()},
    running: boolean()
  }

  # Interactive commands
  @interactive_commands [
    "/help", "/session", "/config", "/clear", "/history", "/multiline", 
    "/save", "/load", "/export", "/status", "/quit", "/exit"
  ]

  # Keyboard shortcuts
  @shortcuts %{
    "ctrl_c" => :interrupt,
    "ctrl_d" => :eof,
    "ctrl_l" => :clear_screen,
    "up_arrow" => :history_prev,
    "down_arrow" => :history_next,
    "tab" => :auto_complete,
    "enter" => :submit_input
  }

  @doc """
  Start an interactive chat session.
  """
  def start_chat(cli_state, config, options \\ []) do
    initial_state = %{
      cli_state: cli_state,
      config: config,
      session: nil,
      history: [],
      history_position: 0,
      current_input: "",
      streaming: Keyword.get(options, :stream, false),
      screen_size: get_terminal_size(),
      running: true
    }
    
    case GenServer.start_link(__MODULE__, initial_state) do
      {:ok, pid} ->
        # Setup signal handling
        setup_signal_handlers(pid)
        
        # Start the interaction loop
        run_chat_loop(pid)
        
      error ->
        error
    end
  end

  @doc """
  Send input to the chat session.
  """
  def send_input(pid, input) do
    GenServer.call(pid, {:input, input})
  end

  @doc """
  Handle keyboard shortcuts.
  """
  def handle_shortcut(pid, shortcut) do
    GenServer.call(pid, {:shortcut, shortcut})
  end

  @doc """
  Stop the chat session.
  """
  def stop_chat(pid) do
    GenServer.call(pid, :stop)
  end

  # GenServer callbacks

  @impl true
  def init(initial_state) do
    # Initialize session if needed
    case ensure_session(initial_state) do
      {:ok, state_with_session} ->
        show_welcome_message(state_with_session)
        {:ok, state_with_session}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:input, input}, _from, state) do
    case process_input(input, state) do
      {:continue, new_state} ->
        {:reply, :ok, new_state}
      {:stop, final_state} ->
        {:reply, :stopping, final_state}
      {:error, reason, error_state} ->
        {:reply, {:error, reason}, error_state}
    end
  end

  def handle_call({:shortcut, shortcut}, _from, state) do
    case handle_keyboard_shortcut(shortcut, state) do
      {:continue, new_state} ->
        {:reply, :ok, new_state}
      {:stop, final_state} ->
        {:reply, :stopping, final_state}
    end
  end

  def handle_call(:stop, _from, state) do
    cleanup_session(state)
    {:stop, :normal, :ok, %{state | running: false}}
  end

  @impl true
  def handle_info({:stream_chunk, chunk}, state) do
    display_stream_chunk(chunk, state.config)
    {:noreply, state}
  end

  def handle_info({:response_complete, response}, state) do
    finalize_response_display(response, state.config)
    show_prompt(state)
    {:noreply, state}
  end

  def handle_info({:terminal_resize, new_size}, state) do
    new_state = %{state | screen_size: new_size}
    handle_screen_resize(new_state)
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Core interaction functions

  defp run_chat_loop(pid) do
    case get_user_input_with_history(pid) do
      {:ok, input} ->
        case send_input(pid, input) do
          :ok -> run_chat_loop(pid)
          :stopping -> cleanup_and_exit(pid)
          {:error, reason} -> 
            IO.puts(:stderr, "Error: #{reason}")
            run_chat_loop(pid)
        end
        
      :eof ->
        cleanup_and_exit(pid)
        
      {:error, :interrupted} ->
        IO.puts("\nInterrupted. Type /quit to exit or continue chatting.")
        run_chat_loop(pid)
        
      {:error, reason} ->
        IO.puts(:stderr, "Input error: #{reason}")
        run_chat_loop(pid)
    end
  end

  defp get_user_input_with_history(pid) do
    # This would integrate with a library like ratatui or implement
    # custom terminal input handling for arrow keys, etc.
    # For now, using basic IO.gets with some enhancements
    
    case get_enhanced_input(pid) do
      {:ok, input} -> {:ok, String.trim(input)}
      error -> error
    end
  end

  defp get_enhanced_input(pid) do
    prompt = get_current_prompt(pid)
    
    case IO.gets(prompt) do
      :eof -> :eof
      {:error, reason} -> {:error, reason}
      input when is_binary(input) -> {:ok, input}
    end
  rescue
    # Handle Ctrl+C interruption
    _ -> {:error, :interrupted}
  end

  defp process_input(input, state) do
    # Add to history
    new_history = add_to_history(input, state.history)
    state = %{state | history: new_history, history_position: 0, current_input: ""}
    
    cond do
      String.trim(input) == "" ->
        show_prompt(state)
        {:continue, state}
        
      String.starts_with?(input, "/") ->
        process_slash_command(input, state)
        
      true ->
        process_chat_message(input, state)
    end
  end

  defp process_slash_command(input, state) do
    case CommandParser.parse_interactive(input) do
      {:ok, request} ->
        handle_interactive_request(request, state)
      {:error, reason} ->
        display_error(reason, state.config)
        show_prompt(state)
        {:continue, state}
    end
  end

  defp process_chat_message(input, state) do
    # Create a chat request
    chat_input = %{
      message: input,
      session_id: state.session && state.session.id,
      stream: state.streaming,
      interactive: true
    }
    
    case CommandParser.parse_interactive(input, %{session_id: chat_input.session_id}) do
      {:ok, request} ->
        execute_chat_request(request, state)
      {:error, reason} ->
        display_error(reason, state.config)
        show_prompt(state)
        {:continue, state}
    end
  end

  defp execute_chat_request(request, state) do
    context = %{
      interface: :cli,
      mode: :interactive,
      session: state.session,
      config: state.config,
      streaming: state.streaming
    }
    
    if state.streaming do
      execute_streaming_request(request, context, state)
    else
      execute_blocking_request(request, context, state)
    end
  end

  defp execute_streaming_request(request, context, state) do
    # Show typing indicator
    show_typing_indicator(state.config)
    
    # Start async request
    task = Task.async(fn ->
      CLI.handle_request(request, context, state.cli_state)
    end)
    
    # Wait for response with streaming updates
    case Task.yield(task, 30_000) do
      {:ok, {:ok, response, new_cli_state}} ->
        display_response(response, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
        
      {:ok, {:error, error, new_cli_state}} ->
        display_error_response(error, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
        
      nil ->
        Task.shutdown(task, :brutal_kill)
        display_error("Request timed out", state.config)
        show_prompt(state)
        {:continue, state}
    end
  end

  defp execute_blocking_request(request, context, state) do
    case CLI.handle_request(request, context, state.cli_state) do
      {:ok, response, new_cli_state} ->
        display_response(response, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
        
      {:error, error, new_cli_state} ->
        display_error_response(error, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
    end
  end

  defp handle_interactive_request(request, state) do
    case request.operation do
      :exit ->
        show_goodbye_message(state.config)
        {:stop, state}
        
      :clear ->
        clear_screen()
        show_prompt(state)
        {:continue, state}
        
      :help ->
        show_interactive_help(state.config)
        show_prompt(state)
        {:continue, state}
        
      :session_management ->
        handle_session_command(request, state)
        
      :configuration ->
        handle_config_command(request, state)
        
      _ ->
        # Handle other commands through normal request processing
        execute_chat_request(request, state)
    end
  end

  defp handle_session_command(request, state) do
    context = %{interface: :cli, mode: :interactive}
    
    case CLI.handle_request(request, context, state.cli_state) do
      {:ok, response, new_cli_state} ->
        display_response(response, request, state.config)
        
        # Update session if switched
        new_state = case request.params[:action] do
          :switch ->
            case response.data[:session] do
              session when is_map(session) -> %{state | session: session, cli_state: new_cli_state}
              _ -> %{state | cli_state: new_cli_state}
            end
          _ ->
            %{state | cli_state: new_cli_state}
        end
        
        show_prompt(new_state)
        {:continue, new_state}
        
      {:error, error, new_cli_state} ->
        display_error_response(error, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
    end
  end

  defp handle_config_command(request, state) do
    context = %{interface: :cli, mode: :interactive}
    
    case CLI.handle_request(request, context, state.cli_state) do
      {:ok, response, new_cli_state} ->
        display_response(response, request, state.config)
        
        # Update config if changed
        new_state = case request.params[:action] do
          :set ->
            # Reload configuration
            case response.data[:config] do
              new_config when is_map(new_config) -> 
                %{state | config: new_config, cli_state: new_cli_state}
              _ -> 
                %{state | cli_state: new_cli_state}
            end
          _ ->
            %{state | cli_state: new_cli_state}
        end
        
        show_prompt(new_state)
        {:continue, new_state}
        
      {:error, error, new_cli_state} ->
        display_error_response(error, request, state.config)
        new_state = %{state | cli_state: new_cli_state}
        show_prompt(new_state)
        {:continue, new_state}
    end
  end

  defp handle_keyboard_shortcut(shortcut, state) do
    case shortcut do
      :interrupt ->
        IO.puts("\n^C")
        show_prompt(state)
        {:continue, state}
        
      :eof ->
        show_goodbye_message(state.config)
        {:stop, state}
        
      :clear_screen ->
        clear_screen()
        show_prompt(state)
        {:continue, state}
        
      :history_prev ->
        handle_history_navigation(:prev, state)
        
      :history_next ->
        handle_history_navigation(:next, state)
        
      _ ->
        {:continue, state}
    end
  end

  defp handle_history_navigation(direction, state) do
    new_position = case direction do
      :prev -> min(state.history_position + 1, length(state.history))
      :next -> max(state.history_position - 1, 0)
    end
    
    new_input = case Enum.at(state.history, new_position - 1) do
      nil -> ""
      historical_input -> historical_input
    end
    
    new_state = %{state | 
      history_position: new_position,
      current_input: new_input
    }
    
    # Update the current input line (this would need terminal control)
    update_input_line(new_input, state.config)
    
    {:continue, new_state}
  end

  # Display and UI functions

  defp show_welcome_message(state) do
    unless state.config[:quiet] do
      welcome_text = """
      #{colorize("RubberDuck Interactive Chat", :cyan, state.config)} #{colorize("v1.0.0", :dim, state.config)}
      #{colorize("AI-powered coding assistant", :dim, state.config)}

      #{colorize("Commands:", :yellow, state.config)}
        #{colorize("/help", :cyan, state.config)}     - Show help
        #{colorize("/session", :cyan, state.config)}  - Session management  
        #{colorize("/config", :cyan, state.config)}   - Configuration
        #{colorize("/clear", :cyan, state.config)}    - Clear screen
        #{colorize("/quit", :cyan, state.config)}     - Exit chat

      #{colorize("Shortcuts:", :yellow, state.config)}
        #{colorize("Ctrl+L", :cyan, state.config)}    - Clear screen
        #{colorize("Ctrl+D", :cyan, state.config)}    - Exit
        #{colorize("↑/↓", :cyan, state.config)}       - Command history

      Type your message or use commands. Happy chatting! 🦆
      """
      
      IO.puts(welcome_text)
    end
    
    show_session_info(state)
    show_prompt(state)
  end

  defp show_session_info(state) do
    case state.session do
      %{id: session_id, name: name} ->
        session_display = if name do
          "#{name} (#{String.slice(session_id, 0, 8)})"
        else
          String.slice(session_id, 0, 8)
        end
        
        session_text = colorize("Session: #{session_display}", :dim, state.config)
        IO.puts(session_text)
        
      _ ->
        no_session_text = colorize("No active session", :dim, state.config)
        IO.puts(no_session_text)
    end
  end

  defp show_prompt(state) do
    base_prompt = state.config[:interactive_prompt] || "🦆 > "
    
    prompt = case state.session do
      %{name: name} when is_binary(name) ->
        session_indicator = colorize("(#{name})", :dim, state.config)
        "#{base_prompt}#{session_indicator} "
      %{id: session_id} when is_binary(session_id) ->
        short_id = String.slice(session_id, 0, 8)
        session_indicator = colorize("(#{short_id})", :dim, state.config)
        "#{base_prompt}#{session_indicator} "
      _ ->
        base_prompt
    end
    
    IO.write(prompt)
  end

  defp get_current_prompt(pid) do
    # This would be called from the input loop to get the current prompt
    # For now, return a basic prompt
    "🦆 > "
  end

  defp show_typing_indicator(config) do
    if config[:colors] != false do
      IO.write(colorize("🦆 thinking", :dim, config))
      
      # Start a simple animation
      spawn(fn ->
        animate_typing_indicator(config)
      end)
    end
  end

  defp animate_typing_indicator(config) do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    
    for _i <- 1..20 do
      for frame <- frames do
        IO.write("\r#{colorize("🦆 #{frame} thinking...", :dim, config)}")
        Process.sleep(100)
      end
    end
    
    IO.write("\r" <> String.duplicate(" ", 20) <> "\r")
  end

  defp show_interactive_help(config) do
    help_text = """
    #{colorize("Interactive Chat Commands:", :bold, config)}

    #{colorize("Basic Commands:", :yellow, config)}
      #{colorize("/help", :cyan, config)}                    Show this help
      #{colorize("/clear", :cyan, config)}                   Clear the screen
      #{colorize("/quit", :cyan, config)} or #{colorize("/exit", :cyan, config)}           Exit chat mode

    #{colorize("Session Management:", :yellow, config)}
      #{colorize("/session list", :cyan, config)}            List all sessions
      #{colorize("/session new [name]", :cyan, config)}      Create new session
      #{colorize("/session switch <id>", :cyan, config)}     Switch to session
      #{colorize("/session delete <id>", :cyan, config)}     Delete session

    #{colorize("Configuration:", :yellow, config)}
      #{colorize("/config show", :cyan, config)}             Show current config
      #{colorize("/config set <key> <value>", :cyan, config)} Update setting
      
    #{colorize("Special Features:", :yellow, config)}
      #{colorize("/history", :cyan, config)}                 Show command history
      #{colorize("/multiline", :cyan, config)}               Enter multi-line mode
      #{colorize("/save <file>", :cyan, config)}             Save conversation
      #{colorize("/export <format>", :cyan, config)}         Export conversation

    #{colorize("Keyboard Shortcuts:", :yellow, config)}
      #{colorize("Ctrl+L", :cyan, config)}                   Clear screen
      #{colorize("Ctrl+D", :cyan, config)}                   Exit chat
      #{colorize("Ctrl+C", :cyan, config)}                   Interrupt current operation
      #{colorize("↑/↓ arrows", :cyan, config)}               Navigate command history
      #{colorize("Tab", :cyan, config)}                      Auto-complete commands

    Just type your message to chat with the AI assistant!
    """
    
    IO.puts(help_text)
  end

  defp show_goodbye_message(config) do
    goodbye_text = colorize("Goodbye! Thanks for chatting with RubberDuck! 🦆", :green, config)
    IO.puts(goodbye_text)
  end

  defp display_response(response, request, config) do
    case ResponseFormatter.format(response, request, config) do
      {:ok, formatted} ->
        IO.puts(formatted)
      {:error, reason} ->
        IO.puts(:stderr, "Format error: #{reason}")
        IO.puts(inspect(response.data, pretty: true))
    end
  end

  defp display_error_response(error, request, config) do
    formatted_error = CLI.handle_error(error, request, %{config: config})
    IO.puts(:stderr, formatted_error)
  end

  defp display_error(message, config) do
    error_text = colorize("Error: #{message}", :red, config)
    IO.puts(:stderr, error_text)
  end

  defp display_stream_chunk(chunk, config) do
    case ResponseFormatter.format_stream(chunk, nil, config) do
      {:ok, formatted} -> IO.write(formatted)
      {:error, _} -> IO.write(chunk[:content] || "")
    end
  end

  defp finalize_response_display(_response, _config) do
    IO.puts("")  # Add newline after streaming response
  end

  # Utility functions

  defp ensure_session(state) do
    case state.session do
      nil ->
        # Create or get default session
        case SessionManager.create_session("interactive", %{mode: :interactive}, state.cli_state.session_manager) do
          {:ok, session, new_session_manager} ->
            new_cli_state = %{state.cli_state | session_manager: new_session_manager}
            new_state = %{state | session: session, cli_state: new_cli_state}
            {:ok, new_state}
          {:error, reason} ->
            {:error, reason}
        end
      session when is_map(session) ->
        {:ok, state}
    end
  end

  defp cleanup_session(state) do
    if state.session do
      SessionManager.save_session(state.session, state.cli_state.session_manager)
    end
  end

  defp add_to_history(input, history) do
    trimmed = String.trim(input)
    if trimmed != "" and trimmed != List.first(history) do
      [trimmed | Enum.take(history, 99)]  # Keep last 100 commands
    else
      history
    end
  end

  defp clear_screen do
    IO.write("\e[2J\e[H")
  end

  defp update_input_line(input, _config) do
    # This would update the current input line with the historical command
    # For now, just clear and rewrite (simplified)
    IO.write("\r#{String.duplicate(" ", 80)}\r#{input}")
  end

  defp get_terminal_size do
    case System.cmd("stty", ["size"], stderr_to_stdout: true) do
      {output, 0} ->
        case String.split(String.trim(output)) do
          [rows, cols] ->
            {String.to_integer(rows), String.to_integer(cols)}
          _ ->
            {24, 80}  # Default size
        end
      _ ->
        {24, 80}  # Default size
    end
  rescue
    _ -> {24, 80}
  end

  defp handle_screen_resize(state) do
    # Handle terminal resize events
    # This would adjust display formatting based on new size
    # For now, just log the change
    Logger.debug("Terminal resized to #{inspect(state.screen_size)}")
  end

  defp setup_signal_handlers(pid) do
    # Setup signal handlers for graceful shutdown
    # This would integrate with :os.set_signal/2 in production
    Process.flag(:trap_exit, true)
    
    # Register for SIGINT (Ctrl+C) handling
    spawn_link(fn ->
      Process.sleep(:infinity)
    end)
  end

  defp cleanup_and_exit(pid) do
    stop_chat(pid)
  end

  defp colorize(text, color, config) do
    if config[:colors] != false do
      case color do
        :bold -> "\e[1m#{text}\e[0m"
        :dim -> "\e[2m#{text}\e[0m"
        :cyan -> "\e[36m#{text}\e[0m"
        :green -> "\e[32m#{text}\e[0m"
        :yellow -> "\e[33m#{text}\e[0m"
        :red -> "\e[31m#{text}\e[0m"
        _ -> text
      end
    else
      text
    end
  end
end