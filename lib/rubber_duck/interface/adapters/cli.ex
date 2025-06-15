defmodule RubberDuck.Interface.Adapters.CLI do
  @moduledoc """
  Command-Line Interface adapter for RubberDuck.
  
  This adapter provides a terminal-based interface for interacting with the
  RubberDuck AI assistant. It supports both interactive and non-interactive
  modes, session management, and comprehensive configuration options.
  
  ## Features
  
  - Interactive chat mode with real-time responses
  - Non-interactive commands for scripting and automation
  - Session management and persistence
  - Configuration management and profiles
  - Progress indicators for long-running operations
  - Syntax highlighting and formatted output
  - Error handling with helpful suggestions
  
  ## Usage
  
      # Interactive mode
      mix rubber_duck.chat
      
      # Direct commands
      mix rubber_duck.ask "Your question"
      mix rubber_duck.complete "Code to complete"
      
      # Session management
      mix rubber_duck.session.new
      mix rubber_duck.session.list
  """

  use RubberDuck.Interface.Adapters.Base

  alias RubberDuck.Interface.CLI.{CommandParser, ResponseFormatter, SessionManager, ConfigManager}
  alias RubberDuck.Interface.{Behaviour, ErrorHandler}

  require Logger

  @behaviour RubberDuck.Interface.Behaviour

  # CLI-specific configuration
  @default_config %{
    interactive_prompt: "🦆 > ",
    user_prompt: "You: ",
    colors: true,
    syntax_highlight: true,
    timestamps: false,
    format: :text,
    pager: "less",
    editor: System.get_env("EDITOR") || "vim"
  }

  @doc """
  Initialize the CLI adapter with configuration.
  """
  @impl true
  def init(opts) do
    config = opts
    |> Keyword.get(:config, %{})
    |> Map.merge(@default_config)

    # Initialize CLI-specific state
    state = %{
      config: config,
      sessions: %{},
      current_session: nil,
      command_history: [],
      start_time: System.monotonic_time(:millisecond),
      request_count: 0,
      error_count: 0,
      metrics: %{},
      circuit_breaker: %{
        failure_count: 0,
        last_failure: nil,
        state: :closed
      }
    }

    # Initialize session manager
    case SessionManager.init(config) do
      {:ok, session_state} ->
        new_state = Map.put(state, :session_manager, session_state)
        {:ok, new_state}
      {:error, reason} ->
        {:error, {:session_manager_init_failed, reason}}
    end
  end

  @doc """
  Handle incoming CLI requests.
  """
  @impl true
  def handle_request(request, context, state) do
    # Use the base adapter middleware for common functionality
    handle_request_with_middleware(request, context, state, &process_cli_request/3)
  end

  @doc """
  Format response for CLI output.
  """
  @impl true
  def format_response(response, request, state) do
    case ResponseFormatter.format(response, request, state.config) do
      {:ok, formatted} -> {:ok, formatted}
      {:error, reason} -> {:error, {:format_error, reason}}
    end
  end

  @doc """
  Handle CLI-specific errors.
  """
  @impl true
  def handle_error(error, request, state) do
    ErrorHandler.transform_error(error, :cli, [
      colorize: state.config.colors,
      include_suggestions: true,
      include_help: true
    ])
  end

  @doc """
  Return CLI-specific capabilities.
  """
  @impl true
  def capabilities do
    [
      :chat,
      :complete,
      :analyze,
      :file_upload,
      :file_download,
      :session_management,
      :history,
      :export,
      :health_check,
      :interactive_mode,
      :batch_processing,
      :configuration_management,
      :plugin_system
    ]
  end

  @doc """
  Validate CLI request format.
  """
  @impl true
  def validate_request(request) do
    # Basic validation from base adapter
    case super(request) do
      :ok -> validate_cli_specific(request)
      error -> error
    end
  end

  @doc """
  Shutdown the CLI adapter.
  """
  @impl true
  def shutdown(reason, state) do
    # Save session state if needed
    if state.current_session do
      SessionManager.save_session(state.current_session, state.session_manager)
    end

    # Call parent shutdown for metrics
    super(reason, state)
  end

  # CLI-specific request processing
  defp process_cli_request(request, context, state) do
    case request.operation do
      :chat -> handle_chat_request(request, context, state)
      :complete -> handle_completion_request(request, context, state)
      :analyze -> handle_analysis_request(request, context, state)
      :session_management -> handle_session_request(request, context, state)
      :configuration -> handle_config_request(request, context, state)
      :help -> handle_help_request(request, context, state)
      :status -> handle_status_request(request, context, state)
      operation -> 
        error = Behaviour.error(:unsupported_operation, "Operation '#{operation}' not supported in CLI")
        {:error, error, state}
    end
  end

  defp handle_chat_request(request, context, state) do
    params = request.params

    # Get or create session
    {session, new_state} = ensure_session(params, context, state)

    # Process the chat message
    chat_params = %{
      message: Map.get(params, :message, ""),
      session_id: session.id,
      stream: Map.get(params, :stream, false),
      model: Map.get(params, :model),
      temperature: Map.get(params, :temperature),
      max_tokens: Map.get(params, :max_tokens)
    }

    # Create standardized request for business logic
    business_request = %{
      id: request.id,
      operation: :chat,
      params: chat_params,
      context: context,
      interface: :cli,
      timestamp: DateTime.utc_now()
    }

    # For now, create a mock response (in real implementation, this would route to business logic)
    response_data = %{
      message: "Hello! I'm RubberDuck CLI. Your message was: '#{chat_params.message}'",
      session_id: session.id,
      model_used: chat_params.model || "default",
      timestamp: DateTime.utc_now()
    }

    response = Behaviour.success_response(request.id, response_data, %{
      session: session.id,
      processing_time: 150,
      tokens_used: 25
    })

    {:ok, response, new_state}
  end

  defp handle_completion_request(request, context, state) do
    params = request.params
    prompt = Map.get(params, :prompt, "")
    
    if String.trim(prompt) == "" do
      error = Behaviour.error(:validation_error, "Completion prompt cannot be empty")
      {:error, error, state}
    else
      # Mock completion response
      completion = case String.trim(prompt) do
        "def fibonacci(n):" -> 
          """
          def fibonacci(n):
              if n <= 1:
                  return n
              return fibonacci(n-1) + fibonacci(n-2)
          """
        "SELECT * FROM users" ->
          "SELECT * FROM users WHERE active = true ORDER BY created_at DESC;"
        _ ->
          "# Completed: #{prompt}\n# This is a mock completion"
      end

      response_data = %{
        completion: completion,
        confidence: 0.85,
        language: detect_language(prompt),
        suggestions: []
      }

      response = Behaviour.success_response(request.id, response_data)
      {:ok, response, state}
    end
  end

  defp handle_analysis_request(request, context, state) do
    params = request.params
    content = Map.get(params, :content, "")
    
    # Mock analysis
    analysis = %{
      content_type: detect_content_type(content),
      language: detect_language(content),
      complexity: "medium",
      word_count: String.split(content) |> length(),
      suggestions: [
        "Consider adding more comments",
        "Function could be simplified"
      ],
      metrics: %{
        readability: 0.75,
        maintainability: 0.80
      }
    }

    response = Behaviour.success_response(request.id, analysis)
    {:ok, response, state}
  end

  defp handle_session_request(request, context, state) do
    params = request.params
    action = Map.get(params, :action, :list)

    case action do
      :list ->
        sessions = SessionManager.list_sessions(state.session_manager)
        response = Behaviour.success_response(request.id, %{sessions: sessions})
        {:ok, response, state}

      :new ->
        name = Map.get(params, :name, "session_#{System.unique_integer()}")
        case SessionManager.create_session(name, context, state.session_manager) do
          {:ok, session, new_session_state} ->
            new_state = %{state | session_manager: new_session_state, current_session: session}
            response = Behaviour.success_response(request.id, %{session: session})
            {:ok, response, new_state}
          {:error, reason} ->
            error = Behaviour.error(:internal_error, "Failed to create session: #{reason}")
            {:error, error, state}
        end

      :switch ->
        session_id = Map.get(params, :session_id)
        case SessionManager.get_session(session_id, state.session_manager) do
          {:ok, session} ->
            new_state = %{state | current_session: session}
            response = Behaviour.success_response(request.id, %{session: session})
            {:ok, response, new_state}
          {:error, reason} ->
            error = Behaviour.error(:not_found, "Session not found: #{reason}")
            {:error, error, state}
        end

      :delete ->
        session_id = Map.get(params, :session_id)
        case SessionManager.delete_session(session_id, state.session_manager) do
          {:ok, new_session_state} ->
            new_state = %{state | session_manager: new_session_state}
            if state.current_session && state.current_session.id == session_id do
              new_state = %{new_state | current_session: nil}
            end
            response = Behaviour.success_response(request.id, %{deleted: session_id})
            {:ok, response, new_state}
          {:error, reason} ->
            error = Behaviour.error(:not_found, "Cannot delete session: #{reason}")
            {:error, error, state}
        end

      _ ->
        error = Behaviour.error(:validation_error, "Unknown session action: #{action}")
        {:error, error, state}
    end
  end

  defp handle_config_request(request, context, state) do
    params = request.params
    action = Map.get(params, :action, :show)

    case action do
      :show ->
        config = ConfigManager.get_config(state.config)
        response = Behaviour.success_response(request.id, %{config: config})
        {:ok, response, state}

      :set ->
        key = Map.get(params, :key)
        value = Map.get(params, :value)
        
        case ConfigManager.set_config(key, value, state.config) do
          {:ok, new_config} ->
            new_state = %{state | config: new_config}
            response = Behaviour.success_response(request.id, %{updated: %{key => value}})
            {:ok, response, new_state}
          {:error, reason} ->
            error = Behaviour.error(:validation_error, "Configuration error: #{reason}")
            {:error, error, state}
        end

      :reset ->
        new_state = %{state | config: @default_config}
        response = Behaviour.success_response(request.id, %{config: @default_config})
        {:ok, response, new_state}

      _ ->
        error = Behaviour.error(:validation_error, "Unknown config action: #{action}")
        {:error, error, state}
    end
  end

  defp handle_help_request(request, _context, state) do
    params = request.params
    topic = Map.get(params, :topic, :general)

    help_content = case topic do
      :general -> get_general_help()
      :commands -> get_commands_help()
      :session -> get_session_help()
      :config -> get_config_help()
      _ -> "Unknown help topic: #{topic}"
    end

    response = Behaviour.success_response(request.id, %{help: help_content, topic: topic})
    {:ok, response, state}
  end

  defp handle_status_request(request, _context, state) do
    {health_status, health_metadata} = health_check(state)
    
    status = %{
      adapter: :cli,
      health: health_status,
      sessions: map_size(state.sessions),
      current_session: state.current_session && state.current_session.id,
      uptime: System.monotonic_time(:millisecond) - state.start_time,
      requests_processed: state.request_count,
      errors: state.error_count,
      config: %{
        colors_enabled: state.config.colors,
        syntax_highlighting: state.config.syntax_highlight,
        format: state.config.format
      },
      metadata: health_metadata
    }

    response = Behaviour.success_response(request.id, status)
    {:ok, response, state}
  end

  # Helper functions

  defp validate_cli_specific(request) do
    case request.operation do
      :chat ->
        validate_chat_params(request.params)
      :complete ->
        validate_completion_params(request.params)
      :analyze ->
        validate_analysis_params(request.params)
      _ ->
        :ok
    end
  end

  defp validate_chat_params(params) do
    message = Map.get(params, :message, "")
    
    cond do
      String.trim(message) == "" and not Map.get(params, :interactive, false) ->
        {:error, ["Chat message cannot be empty for non-interactive mode"]}
      true ->
        :ok
    end
  end

  defp validate_completion_params(params) do
    prompt = Map.get(params, :prompt, "")
    
    if String.trim(prompt) == "" do
      {:error, ["Completion prompt cannot be empty"]}
    else
      :ok
    end
  end

  defp validate_analysis_params(params) do
    content = Map.get(params, :content, "")
    
    if String.trim(content) == "" do
      {:error, ["Analysis content cannot be empty"]}
    else
      :ok
    end
  end

  defp ensure_session(params, context, state) do
    case Map.get(params, :session_id) || (state.current_session && state.current_session.id) do
      nil ->
        # Create default session
        case SessionManager.create_session("default", context, state.session_manager) do
          {:ok, session, new_session_state} ->
            new_state = %{state | session_manager: new_session_state, current_session: session}
            {session, new_state}
          {:error, _reason} ->
            # Fallback to in-memory session
            session = %{
              id: "fallback_#{System.unique_integer()}",
              name: "fallback",
              created_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }
            {session, state}
        end

      session_id ->
        case SessionManager.get_session(session_id, state.session_manager) do
          {:ok, session} -> {session, state}
          {:error, _} ->
            # Use current session or create fallback
            session = state.current_session || %{
              id: session_id,
              name: "recovered",
              created_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }
            {session, state}
        end
    end
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, "def ") and String.contains?(content, ":") -> "python"
      String.contains?(content, "function ") -> "javascript"
      String.contains?(content, "SELECT ") or String.contains?(content, "FROM ") -> "sql"
      String.contains?(content, "defmodule ") -> "elixir"
      String.contains?(content, "#include") -> "c"
      true -> "text"
    end
  end

  defp detect_content_type(content) do
    cond do
      String.contains?(content, "def ") -> "code"
      String.contains?(content, "SELECT ") -> "query"
      String.match?(content, ~r/^[A-Z].*\?$/) -> "question"
      true -> "text"
    end
  end

  defp get_general_help do
    """
    RubberDuck CLI - AI Assistant Command Line Interface

    USAGE:
        mix rubber_duck.<command> [options]

    COMMON COMMANDS:
        chat                Start interactive chat mode
        ask <question>      Ask a direct question
        complete <prompt>   Complete code or text
        analyze <content>   Analyze content

    SESSION COMMANDS:
        session.list        List all sessions
        session.new [name]  Create new session
        session.switch <id> Switch to session
        session.delete <id> Delete session

    CONFIG COMMANDS:
        config.show         Show current configuration
        config.set <k> <v>  Set configuration value
        config.reset        Reset to defaults

    UTILITY COMMANDS:
        help [topic]        Show help (topics: commands, session, config)
        version             Show version information
        status              Show system status

    For more help: mix rubber_duck.help <topic>
    """
  end

  defp get_commands_help do
    """
    COMMAND REFERENCE:

    CHAT COMMANDS:
        mix rubber_duck.chat
            Start interactive chat mode

        mix rubber_duck.ask "question"
            Ask a direct question
            Options: --model, --format, --session

        mix rubber_duck.complete "code"
            Complete code or text
            Options: --language, --max-tokens

        mix rubber_duck.analyze "content"
            Analyze content for insights
            Options: --type, --format

    GLOBAL OPTIONS:
        --session <id>      Use specific session
        --model <name>      Select AI model
        --format <format>   Output format (text, json)
        --verbose           Verbose output
        --quiet             Minimal output
        --config <file>     Use config file

    EXAMPLES:
        mix rubber_duck.ask "How do I sort a list in Python?"
        mix rubber_duck.complete "def fibonacci(n):" --language python
        mix rubber_duck.chat --session my-session
    """
  end

  defp get_session_help do
    """
    SESSION MANAGEMENT:

    Sessions allow you to maintain conversation context and history.

    COMMANDS:
        mix rubber_duck.session.list
            List all available sessions

        mix rubber_duck.session.new [name]
            Create a new session with optional name

        mix rubber_duck.session.switch <id>
            Switch to an existing session

        mix rubber_duck.session.delete <id>
            Delete a session and its history

    EXAMPLES:
        mix rubber_duck.session.new "python-project"
        mix rubber_duck.session.switch python-project
        mix rubber_duck.chat  # Uses current session

    Sessions are automatically saved and can be resumed later.
    """
  end

  defp get_config_help do
    """
    CONFIGURATION:

    Customize CLI behavior and preferences.

    COMMANDS:
        mix rubber_duck.config.show
            Display current configuration

        mix rubber_duck.config.set <key> <value>
            Set a configuration value

        mix rubber_duck.config.reset
            Reset all settings to defaults

    CONFIGURATION OPTIONS:
        colors              Enable/disable colored output (true/false)
        syntax_highlight    Enable syntax highlighting (true/false)
        format              Default output format (text/json)
        interactive_prompt  Chat prompt (default: "🦆 > ")
        model               Default AI model

    EXAMPLES:
        mix rubber_duck.config.set colors false
        mix rubber_duck.config.set model gpt-4
        mix rubber_duck.config.set format json
    """
  end
end