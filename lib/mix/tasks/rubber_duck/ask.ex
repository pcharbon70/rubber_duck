defmodule Mix.Tasks.RubberDuck.Ask do
  @moduledoc """
  Ask RubberDuck AI assistant a direct question.

  ## Usage

      mix rubber_duck.ask <question> [options]

  ## Arguments

    * `question` - The question to ask (required, wrap in quotes if it contains spaces)

  ## Options

    * `--model <name>` - Select AI model (default from config)
    * `--session <id>` - Use specific session ID
    * `--format <format>` - Output format: text, json (default: text)
    * `--temperature <float>` - Model temperature (0.0-2.0)
    * `--max-tokens <int>` - Maximum response tokens
    * `--verbose` - Include metadata in response
    * `--quiet` - Minimal output (response only)
    * `--config <file>` - Use custom config file
    * `--timeout <seconds>` - Request timeout

  ## Examples

      # Basic question
      mix rubber_duck.ask "How do I sort a list in Python?"

      # Use specific model
      mix rubber_duck.ask "Explain recursion" --model gpt-4

      # JSON output with session
      mix rubber_duck.ask "What is functional programming?" --format json --session my-session

      # Verbose output with metadata
      mix rubber_duck.ask "Best practices for Elixir" --verbose

      # Creative response
      mix rubber_duck.ask "Write a poem about coding" --temperature 1.2
  """

  use Mix.Task

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.CLI.{CommandParser, ResponseFormatter, ConfigManager}

  @shortdoc "Ask RubberDuck AI a direct question"

  @switches [
    model: :string,
    session: :string,
    format: :string,
    temperature: :float,
    max_tokens: :integer,
    verbose: :boolean,
    quiet: :boolean,
    config: :string,
    timeout: :integer,
    help: :boolean
  ]

  @aliases [
    m: :model,
    s: :session,
    f: :format,
    t: :temperature,
    v: :verbose,
    q: :quiet,
    h: :help
  ]

  def run(args) do
    {options, remaining_args, invalid} = OptionParser.parse(args, 
      switches: @switches, 
      aliases: @aliases
    )

    cond do
      options[:help] ->
        show_help()
        
      not Enum.empty?(invalid) ->
        show_invalid_options(invalid)
        exit({:shutdown, 1})
        
      Enum.empty?(remaining_args) ->
        show_missing_question()
        exit({:shutdown, 1})
        
      true ->
        question = Enum.join(remaining_args, " ")
        ask_question(question, options)
    end
  end

  defp ask_question(question, options) do
    # Load configuration
    config_overrides = extract_config_overrides(options)
    
    case ConfigManager.load_config(config_overrides) do
      {:ok, config} ->
        process_question(question, config, options)
      {:error, reason} ->
        Mix.shell().error("Configuration error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp process_question(question, config, options) do
    # Initialize CLI adapter
    case CLI.init(config: config) do
      {:ok, cli_state} ->
        execute_ask_request(question, cli_state, config, options)
      {:error, reason} ->
        Mix.shell().error("Failed to initialize CLI adapter: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp execute_ask_request(question, cli_state, config, options) do
    # Parse the ask command
    command_args = [question] ++ build_command_flags(options)
    
    case CommandParser.parse("ask", command_args) do
      {:ok, request} ->
        handle_ask_request(request, cli_state, config, options)
      {:error, reason} ->
        Mix.shell().error("Invalid request: #{reason}")
        show_usage_hint()
        exit({:shutdown, 1})
    end
  end

  defp handle_ask_request(request, cli_state, config, options) do
    context = build_request_context(config, options)
    
    # Add timeout handling
    timeout = get_timeout(options, config)
    
    try do
      case CLI.handle_request(request, context, cli_state) do
        {:ok, response, _new_state} ->
          display_success_response(response, request, config, options)
          
        {:error, error, _new_state} ->
          display_error_response(error, request, config, options)
          exit({:shutdown, 1})
      end
    catch
      :exit, {:timeout, _} ->
        Mix.shell().error("Request timed out after #{timeout}ms")
        exit({:shutdown, 1})
    end
  end

  defp display_success_response(response, request, config, options) do
    # Format the response
    case ResponseFormatter.format(response, request, config) do
      {:ok, formatted} ->
        output_response(formatted, response, config, options)
      {:error, reason} ->
        Mix.shell().error("Format error: #{reason}")
        # Fallback to raw output
        Mix.shell().info(inspect(response.data, pretty: true))
    end
  end

  defp output_response(formatted, response, config, options) do
    cond do
      options[:format] == "json" ->
        output_json_response(response, options)
        
      options[:quiet] ->
        # Extract just the message content
        message = extract_message_content(response)
        Mix.shell().info(message)
        
      options[:verbose] ->
        # Include metadata
        Mix.shell().info(formatted)
        show_response_metadata(response, config)
        
      true ->
        # Standard output
        Mix.shell().info(formatted)
    end
  end

  defp output_json_response(response, options) do
    json_data = if options[:verbose] do
      response
    else
      # Simplified JSON output
      %{
        message: extract_message_content(response),
        status: response.status,
        timestamp: response.metadata[:timestamp]
      }
    end
    
    case Jason.encode(json_data, pretty: true) do
      {:ok, json} -> Mix.shell().info(json)
      {:error, reason} -> Mix.shell().error("JSON encoding error: #{reason}")
    end
  end

  defp display_error_response(error, request, config, options) do
    if options[:format] == "json" do
      error_json = %{
        error: error.type,
        message: error.message,
        status: "error"
      }
      
      case Jason.encode(error_json, pretty: true) do
        {:ok, json} -> Mix.shell().error(json)
        {:error, _} -> Mix.shell().error("Error: #{error.message}")
      end
    else
      formatted_error = CLI.handle_error(error, request, %{config: config})
      Mix.shell().error(formatted_error)
    end
  end

  defp show_response_metadata(response, config) do
    metadata = response.metadata || %{}
    
    metadata_lines = [
      "",
      colorize("Response Metadata:", :dim, config)
    ]
    
    metadata_lines = if metadata[:processing_time] do
      time_ms = metadata.processing_time
      [colorize("Processing time: #{time_ms}ms", :dim, config) | metadata_lines]
    else
      metadata_lines
    end
    
    metadata_lines = if metadata[:tokens_used] do
      tokens = metadata.tokens_used
      [colorize("Tokens used: #{tokens}", :dim, config) | metadata_lines]
    else
      metadata_lines
    end
    
    metadata_lines = if metadata[:model_used] do
      model = metadata.model_used
      [colorize("Model: #{model}", :dim, config) | metadata_lines]
    else
      metadata_lines
    end
    
    Enum.reverse(metadata_lines)
    |> Enum.each(&Mix.shell().info/1)
  end

  defp extract_message_content(response) do
    case response.data do
      %{message: message} when is_binary(message) -> message
      %{content: content} when is_binary(content) -> content
      %{result: result} when is_binary(result) -> result
      data when is_binary(data) -> data
      data -> inspect(data, pretty: true)
    end
  end

  defp build_command_flags(options) do
    flags = []
    
    flags = if options[:model], do: ["--model", options[:model] | flags], else: flags
    flags = if options[:session], do: ["--session", options[:session] | flags], else: flags
    flags = if options[:format], do: ["--format", options[:format] | flags], else: flags
    flags = if options[:temperature], do: ["--temperature", to_string(options[:temperature]) | flags], else: flags
    flags = if options[:max_tokens], do: ["--max-tokens", to_string(options[:max_tokens]) | flags], else: flags
    
    Enum.reverse(flags)
  end

  defp build_request_context(config, options) do
    %{
      interface: :cli,
      mode: :direct,
      config: config,
      timeout: get_timeout(options, config)
    }
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

  defp get_timeout(options, config) do
    cond do
      options[:timeout] -> options[:timeout] * 1000  # Convert seconds to milliseconds
      config[:timeout] -> config[:timeout]
      true -> 30_000  # Default 30 seconds
    end
  end

  defp colorize(text, color, config) do
    if config[:colors] != false do
      case color do
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

  defp show_invalid_options(invalid) do
    invalid_flags = Enum.map(invalid, fn {flag, _} -> "--#{flag}" end) |> Enum.join(", ")
    Mix.shell().error("Invalid options: #{invalid_flags}")
    show_usage_hint()
  end

  defp show_missing_question do
    Mix.shell().error("Missing required argument: question")
    show_usage_hint()
  end

  defp show_usage_hint do
    Mix.shell().info("Usage: mix rubber_duck.ask <question> [options]")
    Mix.shell().info("Run 'mix help rubber_duck.ask' for detailed help")
  end
end