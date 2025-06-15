defmodule RubberDuck.Interface.CLI.CommandParser do
  @moduledoc """
  Parses command-line arguments and converts them to standardized request format.
  
  This module handles parsing of CLI commands, flags, and arguments, converting
  them into the standardized request format expected by the InterfaceBehaviour.
  
  ## Supported Command Formats
  
      # Direct commands
      mix rubber_duck.ask "question" --model gpt-4 --session my-session
      mix rubber_duck.complete "code" --language python --max-tokens 100
      mix rubber_duck.analyze "content" --format json
      
      # Session commands
      mix rubber_duck.session.new project-name
      mix rubber_duck.session.switch session-id
      
      # Interactive mode
      mix rubber_duck.chat --stream --model claude
  """

  alias RubberDuck.Interface.Behaviour

  @type parse_result :: {:ok, Behaviour.request()} | {:error, String.t()}
  @type args :: [String.t()]
  @type options :: keyword()

  @doc """
  Parse command-line arguments into a standardized request.
  
  ## Parameters
  - `command` - The command name (e.g., "ask", "chat", "complete")
  - `args` - List of command-line arguments
  - `options` - Additional parsing options
  
  ## Returns
  - `{:ok, request}` - Successfully parsed request
  - `{:error, reason}` - Parsing failed with reason
  """
  def parse(command, args, options \\ []) do
    try do
      case command do
        "ask" -> parse_ask_command(args, options)
        "complete" -> parse_complete_command(args, options)
        "analyze" -> parse_analyze_command(args, options)
        "chat" -> parse_chat_command(args, options)
        "session." <> session_cmd -> parse_session_command(session_cmd, args, options)
        "config." <> config_cmd -> parse_config_command(config_cmd, args, options)
        "help" -> parse_help_command(args, options)
        "version" -> parse_version_command(args, options)
        "status" -> parse_status_command(args, options)
        _ -> {:error, "Unknown command: #{command}"}
      end
    rescue
      error -> {:error, "Parse error: #{Exception.message(error)}"}
    end
  end

  @doc """
  Parse arguments for interactive mode commands.
  
  Used when parsing user input in interactive chat mode.
  """
  def parse_interactive(input, context \\ %{}) do
    input = String.trim(input)
    
    cond do
      String.starts_with?(input, "/") ->
        # Handle slash commands
        parse_slash_command(input, context)
      
      String.trim(input) == "" ->
        {:error, "Empty input"}
      
      true ->
        # Regular chat message
        request = create_request(:chat, %{
          message: input,
          interactive: true,
          session_id: Map.get(context, :session_id)
        })
        {:ok, request}
    end
  end

  @doc """
  Validate parsed arguments against command requirements.
  """
  def validate_args(command, parsed_args) do
    case command do
      :ask -> validate_ask_args(parsed_args)
      :complete -> validate_complete_args(parsed_args)
      :analyze -> validate_analyze_args(parsed_args)
      :chat -> validate_chat_args(parsed_args)
      _ -> :ok
    end
  end

  @doc """
  Extract help information for a command.
  """
  def command_help(command) do
    case command do
      "ask" -> ask_help()
      "complete" -> complete_help()
      "analyze" -> analyze_help()
      "chat" -> chat_help()
      "session" -> session_help()
      "config" -> config_help()
      _ -> "Unknown command: #{command}"
    end
  end

  # Private parsing functions

  defp parse_ask_command(args, options) do
    {parsed_args, question} = extract_question_and_flags(args)
    
    if String.trim(question) == "" do
      {:error, "Question is required. Usage: mix rubber_duck.ask \"your question\""}
    else
      params = %{
        message: question,
        model: get_flag(parsed_args, :model),
        session_id: get_flag(parsed_args, :session),
        format: get_flag(parsed_args, :format, "text"),
        temperature: parse_float(get_flag(parsed_args, :temperature)),
        max_tokens: parse_integer(get_flag(parsed_args, :max_tokens))
      }
      |> remove_nil_values()
      
      request = create_request(:chat, params, options)
      {:ok, request}
    end
  end

  defp parse_complete_command(args, options) do
    {parsed_args, prompt} = extract_question_and_flags(args)
    
    if String.trim(prompt) == "" do
      {:error, "Prompt is required. Usage: mix rubber_duck.complete \"code to complete\""}
    else
      params = %{
        prompt: prompt,
        language: get_flag(parsed_args, :language),
        model: get_flag(parsed_args, :model),
        session_id: get_flag(parsed_args, :session),
        max_tokens: parse_integer(get_flag(parsed_args, :max_tokens)),
        temperature: parse_float(get_flag(parsed_args, :temperature))
      }
      |> remove_nil_values()
      
      request = create_request(:complete, params, options)
      {:ok, request}
    end
  end

  defp parse_analyze_command(args, options) do
    {parsed_args, content} = extract_question_and_flags(args)
    
    # Check for file input
    content = case get_flag(parsed_args, :input) do
      nil -> content
      file_path -> 
        case File.read(file_path) do
          {:ok, file_content} -> file_content
          {:error, reason} -> 
            return {:error, "Cannot read file #{file_path}: #{reason}"}
        end
    end
    
    if String.trim(content) == "" do
      {:error, "Content is required. Usage: mix rubber_duck.analyze \"content\" or --input file.txt"}
    else
      params = %{
        content: content,
        type: get_flag(parsed_args, :type),
        format: get_flag(parsed_args, :format, "text"),
        language: get_flag(parsed_args, :language),
        output: get_flag(parsed_args, :output)
      }
      |> remove_nil_values()
      
      request = create_request(:analyze, params, options)
      {:ok, request}
    end
  end

  defp parse_chat_command(args, options) do
    parsed_args = parse_flags(args)
    
    params = %{
      interactive: true,
      stream: has_flag?(parsed_args, :stream),
      model: get_flag(parsed_args, :model),
      session_id: get_flag(parsed_args, :session),
      temperature: parse_float(get_flag(parsed_args, :temperature)),
      max_tokens: parse_integer(get_flag(parsed_args, :max_tokens))
    }
    |> remove_nil_values()
    
    request = create_request(:chat, params, options)
    {:ok, request}
  end

  defp parse_session_command(subcmd, args, options) do
    case subcmd do
      "list" ->
        request = create_request(:session_management, %{action: :list}, options)
        {:ok, request}
        
      "new" ->
        name = case args do
          [name | _] -> name
          [] -> nil
        end
        
        params = %{action: :new}
        params = if name, do: Map.put(params, :name, name), else: params
        
        request = create_request(:session_management, params, options)
        {:ok, request}
        
      "switch" ->
        case args do
          [session_id | _] ->
            params = %{action: :switch, session_id: session_id}
            request = create_request(:session_management, params, options)
            {:ok, request}
          [] ->
            {:error, "Session ID is required. Usage: mix rubber_duck.session.switch <session-id>"}
        end
        
      "delete" ->
        case args do
          [session_id | _] ->
            params = %{action: :delete, session_id: session_id}
            request = create_request(:session_management, params, options)
            {:ok, request}
          [] ->
            {:error, "Session ID is required. Usage: mix rubber_duck.session.delete <session-id>"}
        end
        
      _ ->
        {:error, "Unknown session command: #{subcmd}. Available: list, new, switch, delete"}
    end
  end

  defp parse_config_command(subcmd, args, options) do
    case subcmd do
      "show" ->
        request = create_request(:configuration, %{action: :show}, options)
        {:ok, request}
        
      "set" ->
        case args do
          [key, value | _] ->
            params = %{action: :set, key: key, value: parse_config_value(value)}
            request = create_request(:configuration, params, options)
            {:ok, request}
          _ ->
            {:error, "Key and value required. Usage: mix rubber_duck.config.set <key> <value>"}
        end
        
      "reset" ->
        request = create_request(:configuration, %{action: :reset}, options)
        {:ok, request}
        
      _ ->
        {:error, "Unknown config command: #{subcmd}. Available: show, set, reset"}
    end
  end

  defp parse_help_command(args, options) do
    topic = case args do
      [topic | _] -> String.to_atom(topic)
      [] -> :general
    end
    
    params = %{topic: topic}
    request = create_request(:help, params, options)
    {:ok, request}
  end

  defp parse_version_command(_args, options) do
    request = create_request(:version, %{}, options)
    {:ok, request}
  end

  defp parse_status_command(_args, options) do
    request = create_request(:status, %{}, options)
    {:ok, request}
  end

  defp parse_slash_command(input, context) do
    # Remove leading slash and split into command and args
    [cmd | args] = input |> String.slice(1..-1) |> String.split(" ", trim: true)
    
    case cmd do
      "help" ->
        request = create_request(:help, %{topic: :interactive})
        {:ok, request}
        
      "session" ->
        action = case args do
          ["list"] -> :list
          ["new" | name_parts] -> 
            name = Enum.join(name_parts, " ")
            {:new, name}
          ["switch", id] -> {:switch, id}
          ["delete", id] -> {:delete, id}
          _ -> :list
        end
        
        params = case action do
          :list -> %{action: :list}
          {:new, name} -> %{action: :new, name: name}
          {:switch, id} -> %{action: :switch, session_id: id}
          {:delete, id} -> %{action: :delete, session_id: id}
        end
        
        request = create_request(:session_management, params)
        {:ok, request}
        
      "config" ->
        action = case args do
          ["show"] -> %{action: :show}
          ["set", key, value] -> %{action: :set, key: key, value: parse_config_value(value)}
          ["reset"] -> %{action: :reset}
          _ -> %{action: :show}
        end
        
        request = create_request(:configuration, action)
        {:ok, request}
        
      "clear" ->
        request = create_request(:clear, %{})
        {:ok, request}
        
      "exit" ->
        request = create_request(:exit, %{})
        {:ok, request}
        
      _ ->
        {:error, "Unknown command: /#{cmd}. Type /help for available commands."}
    end
  end

  # Helper functions

  defp extract_question_and_flags(args) do
    # Find flags and separate from question/content
    {flags, non_flags} = Enum.split_with(args, &String.starts_with?(&1, "--"))
    
    parsed_flags = parse_flags(flags)
    question = Enum.join(non_flags, " ")
    
    {parsed_flags, question}
  end

  defp parse_flags(args) do
    args
    |> Enum.filter(&String.starts_with?(&1, "--"))
    |> Enum.chunk_every(2, 1, [:no_value])
    |> Enum.map(&parse_flag/1)
    |> Enum.into(%{})
  end

  defp parse_flag([flag]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, true}
  end

  defp parse_flag([flag, :no_value]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, true}
  end

  defp parse_flag([flag, value]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, value}
  end

  defp get_flag(parsed_args, key, default \\ nil) do
    Map.get(parsed_args, key, default)
  end

  defp has_flag?(parsed_args, key) do
    Map.get(parsed_args, key, false) == true
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp parse_config_value(value) do
    cond do
      value in ["true", "yes", "on", "1"] -> true
      value in ["false", "no", "off", "0"] -> false
      String.match?(value, ~r/^\d+$/) -> String.to_integer(value)
      String.match?(value, ~r/^\d+\.\d+$/) -> String.to_float(value)
      true -> value
    end
  end

  defp remove_nil_values(map) do
    Enum.reject(map, fn {_k, v} -> is_nil(v) end) |> Map.new()
  end

  defp create_request(operation, params, options \\ []) do
    %{
      id: Behaviour.generate_request_id(),
      operation: operation,
      params: params,
      interface: :cli,
      timestamp: DateTime.utc_now(),
      priority: Keyword.get(options, :priority, :normal)
    }
  end

  # Validation functions

  defp validate_ask_args(params) do
    case Map.get(params, :message) do
      nil -> {:error, "Message is required"}
      msg when is_binary(msg) and byte_size(String.trim(msg)) > 0 -> :ok
      _ -> {:error, "Message must be a non-empty string"}
    end
  end

  defp validate_complete_args(params) do
    case Map.get(params, :prompt) do
      nil -> {:error, "Prompt is required"}
      prompt when is_binary(prompt) and byte_size(String.trim(prompt)) > 0 -> :ok
      _ -> {:error, "Prompt must be a non-empty string"}
    end
  end

  defp validate_analyze_args(params) do
    case Map.get(params, :content) do
      nil -> {:error, "Content is required"}
      content when is_binary(content) and byte_size(String.trim(content)) > 0 -> :ok
      _ -> {:error, "Content must be a non-empty string"}
    end
  end

  defp validate_chat_args(_params) do
    # Chat args are generally optional
    :ok
  end

  # Help text functions

  defp ask_help do
    """
    mix rubber_duck.ask - Ask the AI assistant a question

    USAGE:
        mix rubber_duck.ask "your question" [options]

    OPTIONS:
        --model <name>          Select AI model (gpt-4, claude, etc.)
        --session <id>          Use specific session
        --format <format>       Output format (text, json)
        --temperature <float>   Model temperature (0.0-2.0)
        --max-tokens <int>      Maximum response tokens

    EXAMPLES:
        mix rubber_duck.ask "How do I sort a list in Python?"
        mix rubber_duck.ask "Explain recursion" --model gpt-4
        mix rubber_duck.ask "What is OOP?" --format json --session my-session
    """
  end

  defp complete_help do
    """
    mix rubber_duck.complete - Complete code or text

    USAGE:
        mix rubber_duck.complete "code to complete" [options]

    OPTIONS:
        --language <lang>       Programming language hint
        --model <name>          Select AI model
        --session <id>          Use specific session
        --max-tokens <int>      Maximum completion tokens
        --temperature <float>   Model temperature

    EXAMPLES:
        mix rubber_duck.complete "def fibonacci(n):" --language python
        mix rubber_duck.complete "SELECT * FROM users" --language sql
        mix rubber_duck.complete "function add(" --language javascript
    """
  end

  defp analyze_help do
    """
    mix rubber_duck.analyze - Analyze content for insights

    USAGE:
        mix rubber_duck.analyze "content" [options]
        mix rubber_duck.analyze --input file.txt [options]

    OPTIONS:
        --input <file>          Read content from file
        --output <file>         Write results to file
        --type <type>           Analysis type (code, text, query)
        --format <format>       Output format (text, json)
        --language <lang>       Language hint for code analysis

    EXAMPLES:
        mix rubber_duck.analyze "def factorial(n): return 1 if n <= 1 else n * factorial(n-1)"
        mix rubber_duck.analyze --input code.py --format json
        mix rubber_duck.analyze "This is a sample text" --type text
    """
  end

  defp chat_help do
    """
    mix rubber_duck.chat - Start interactive chat mode

    USAGE:
        mix rubber_duck.chat [options]

    OPTIONS:
        --stream                Enable streaming responses
        --model <name>          Select AI model
        --session <id>          Use specific session
        --temperature <float>   Model temperature
        --max-tokens <int>      Maximum response tokens

    INTERACTIVE COMMANDS:
        /help                   Show interactive help
        /session list           List sessions
        /session new [name]     Create new session
        /session switch <id>    Switch session
        /config show            Show configuration
        /clear                  Clear screen
        /exit                   Exit chat mode

    EXAMPLES:
        mix rubber_duck.chat
        mix rubber_duck.chat --model gpt-4 --stream
        mix rubber_duck.chat --session my-project
    """
  end

  defp session_help do
    """
    Session management commands:

        mix rubber_duck.session.list           List all sessions
        mix rubber_duck.session.new [name]     Create new session
        mix rubber_duck.session.switch <id>    Switch to session
        mix rubber_duck.session.delete <id>    Delete session

    EXAMPLES:
        mix rubber_duck.session.new "python-project"
        mix rubber_duck.session.list
        mix rubber_duck.session.switch python-project
    """
  end

  defp config_help do
    """
    Configuration management commands:

        mix rubber_duck.config.show            Show current config
        mix rubber_duck.config.set <key> <val> Set configuration
        mix rubber_duck.config.reset           Reset to defaults

    EXAMPLES:
        mix rubber_duck.config.set colors false
        mix rubber_duck.config.set model gpt-4
        mix rubber_duck.config.show
    """
  end
end