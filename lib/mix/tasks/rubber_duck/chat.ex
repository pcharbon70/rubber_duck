defmodule Mix.Tasks.RubberDuck.Chat do
  @moduledoc """
  Start an interactive chat session with RubberDuck AI assistant.

  ## Usage

      mix rubber_duck.chat [options]

  ## Options

    * `--stream` - Enable streaming responses (real-time output)
    * `--model <name>` - Select AI model (default from config)
    * `--session <id>` - Use specific session ID
    * `--temperature <float>` - Model temperature (0.0-2.0)
    * `--max-tokens <int>` - Maximum response tokens
    * `--config <file>` - Use custom config file
    * `--verbose` - Enable verbose output
    * `--quiet` - Minimal output mode

  ## Interactive Commands

  Once in chat mode, you can use these slash commands:

    * `/help` - Show interactive help
    * `/session list` - List all sessions
    * `/session new [name]` - Create new session
    * `/session switch <id>` - Switch to different session
    * `/config show` - Show current configuration
    * `/config set <key> <value>` - Update configuration
    * `/clear` - Clear the screen
    * `/exit` - Exit chat mode

  ## Examples

      # Start basic chat
      mix rubber_duck.chat

      # Chat with streaming enabled
      mix rubber_duck.chat --stream

      # Use specific model and session
      mix rubber_duck.chat --model gpt-4 --session my-project

      # Verbose mode for debugging
      mix rubber_duck.chat --verbose
  """

  use Mix.Task

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.CLI.{CommandParser, ResponseFormatter, ConfigManager}

  @shortdoc "Start interactive chat with RubberDuck AI"

  @switches [
    stream: :boolean,
    model: :string,
    session: :string,
    temperature: :float,
    max_tokens: :integer,
    config: :string,
    verbose: :boolean,
    quiet: :boolean,
    help: :boolean
  ]

  @aliases [
    s: :stream,
    m: :model,
    t: :temperature,
    v: :verbose,
    q: :quiet,
    h: :help
  ]

  def run(args) do
    {options, _remaining_args, _invalid} = OptionParser.parse(args, 
      switches: @switches, 
      aliases: @aliases
    )

    if options[:help] do
      show_help()
    else
      start_chat_session(options)
    end
  end

  defp start_chat_session(options) do
    # Load configuration
    config_overrides = extract_config_overrides(options)
    
    case ConfigManager.load_config(config_overrides) do
      {:ok, config} ->
        run_interactive_chat(config, options)
      {:error, reason} ->
        Mix.shell().error("Configuration error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp run_interactive_chat(config, options) do
    # Start the CLI adapter
    case CLI.init(config: config) do
      {:ok, cli_state} ->
        # Show welcome message
        show_welcome_message(config, options)
        
        # Parse chat command
        case CommandParser.parse("chat", [], config: config) do
          {:ok, chat_request} ->
            # Start interactive loop
            interactive_loop(cli_state, config, chat_request)
          {:error, reason} ->
            Mix.shell().error("Failed to initialize chat: #{reason}")
            exit({:shutdown, 1})
        end
        
      {:error, reason} ->
        Mix.shell().error("Failed to initialize CLI adapter: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp interactive_loop(cli_state, config, initial_request) do
    # Set up signal handling for graceful exit
    Process.flag(:trap_exit, true)
    
    # Handle the initial chat request to establish session
    {updated_state, session_info} = handle_initial_request(cli_state, initial_request)
    
    # Main interaction loop
    loop_state = %{
      cli_state: updated_state,
      config: config,
      session: session_info,
      running: true
    }
    
    interaction_loop(loop_state)
  end

  defp interaction_loop(%{running: false}), do: :ok
  defp interaction_loop(loop_state) do
    # Show prompt
    prompt = get_prompt(loop_state.config, loop_state.session)
    
    case get_user_input(prompt) do
      :eof ->
        # Ctrl+D pressed
        show_goodbye_message(loop_state.config)
        
      {:ok, input} ->
        case handle_user_input(input, loop_state) do
          {:continue, new_loop_state} ->
            interaction_loop(new_loop_state)
          {:exit, _final_state} ->
            show_goodbye_message(loop_state.config)
        end
        
      {:error, reason} ->
        Mix.shell().error("Input error: #{reason}")
        interaction_loop(loop_state)
    end
  end

  defp handle_user_input(input, loop_state) do
    case CommandParser.parse_interactive(input) do
      {:ok, request} ->
        process_interactive_request(request, loop_state)
      {:error, reason} ->
        show_error(reason, loop_state.config)
        {:continue, loop_state}
    end
  end

  defp process_interactive_request(request, loop_state) do
    case request.operation do
      :exit ->
        {:exit, loop_state}
        
      :clear ->
        clear_screen()
        {:continue, loop_state}
        
      _ ->
        # Process request through CLI adapter
        context = build_request_context(loop_state)
        
        case CLI.handle_request(request, context, loop_state.cli_state) do
          {:ok, response, new_cli_state} ->
            # Format and display response
            display_response(response, request, loop_state.config)
            
            # Update loop state
            new_loop_state = %{loop_state | cli_state: new_cli_state}
            {:continue, new_loop_state}
            
          {:error, error, new_cli_state} ->
            # Display error
            display_error(error, request, loop_state.config)
            
            # Update loop state
            new_loop_state = %{loop_state | cli_state: new_cli_state}
            {:continue, new_loop_state}
        end
    end
  end

  defp handle_initial_request(cli_state, request) do
    context = %{interface: :cli, mode: :interactive}
    
    case CLI.handle_request(request, context, cli_state) do
      {:ok, response, new_state} ->
        session_info = extract_session_info(response)
        {new_state, session_info}
      {:error, _error, new_state} ->
        {new_state, nil}
    end
  end

  defp show_welcome_message(config, options) do
    unless options[:quiet] do
      welcome_text = """
      #{colorize("RubberDuck CLI", :cyan, config)} #{colorize("v1.0.0", :dim, config)}
      #{colorize("AI-powered coding assistant", :dim, config)}

      Type your question or use slash commands. Type #{colorize("/help", :yellow, config)} for assistance.
      Press #{colorize("Ctrl+D", :dim, config)} or type #{colorize("/exit", :yellow, config)} to quit.
      """
      
      Mix.shell().info(welcome_text)
    end
  end

  defp show_goodbye_message(config) do
    goodbye_text = colorize("Goodbye! Session saved.", :green, config)
    Mix.shell().info(goodbye_text)
  end

  defp get_prompt(config, session_info) do
    base_prompt = config.interactive_prompt || "🦆 > "
    
    case session_info do
      %{id: session_id} when is_binary(session_id) ->
        session_indicator = colorize("(#{String.slice(session_id, 0, 8)})", :dim, config)
        "#{base_prompt}#{session_indicator} "
      _ ->
        base_prompt
    end
  end

  defp get_user_input(prompt) do
    case IO.gets(prompt) do
      :eof -> :eof
      {:error, reason} -> {:error, reason}
      data when is_binary(data) -> {:ok, String.trim(data)}
    end
  end

  defp display_response(response, request, config) do
    case ResponseFormatter.format(response, request, config) do
      {:ok, formatted} ->
        Mix.shell().info(formatted)
      {:error, reason} ->
        Mix.shell().error("Format error: #{reason}")
        Mix.shell().info(inspect(response.data, pretty: true))
    end
  end

  defp display_error(error, request, config) do
    formatted_error = CLI.handle_error(error, request, %{config: config})
    Mix.shell().error(formatted_error)
  end

  defp show_error(message, config) do
    error_text = colorize("Error: #{message}", :red, config)
    Mix.shell().error(error_text)
  end

  defp clear_screen do
    IO.write("\e[2J\e[H")
  end

  defp build_request_context(loop_state) do
    %{
      interface: :cli,
      mode: :interactive,
      session: loop_state.session,
      config: loop_state.config
    }
  end

  defp extract_session_info(response) do
    case response.data do
      %{session_id: session_id} -> %{id: session_id}
      %{session: session} when is_map(session) -> session
      _ -> nil
    end
  end

  defp extract_config_overrides(options) do
    config_map = %{}
    
    config_map = if options[:model], do: Map.put(config_map, :model, options[:model]), else: config_map
    config_map = if options[:temperature], do: Map.put(config_map, :temperature, options[:temperature]), else: config_map
    config_map = if options[:max_tokens], do: Map.put(config_map, :max_tokens, options[:max_tokens]), else: config_map
    config_map = if options[:verbose], do: Map.put(config_map, :verbose, true), else: config_map
    config_map = if options[:quiet], do: Map.put(config_map, :quiet, true), else: config_map
    
    config_map
  end

  defp colorize(text, color, config) do
    if config[:colors] != false do
      case color do
        :cyan -> "\e[36m#{text}\e[0m"
        :green -> "\e[32m#{text}\e[0m"
        :yellow -> "\e[33m#{text}\e[0m"
        :red -> "\e[31m#{text}\e[0m"
        :dim -> "\e[2m#{text}\e[0m"
        _ -> text
      end
    else
      text
    end
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end