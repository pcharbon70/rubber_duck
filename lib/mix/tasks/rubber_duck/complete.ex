defmodule Mix.Tasks.RubberDuck.Complete do
  @moduledoc """
  Complete code or text using RubberDuck AI assistant.

  ## Usage

      mix rubber_duck.complete <prompt> [options]

  ## Arguments

    * `prompt` - Code or text to complete (required, wrap in quotes if it contains spaces)

  ## Options

    * `--language <lang>` - Programming language hint (python, javascript, elixir, etc.)
    * `--model <name>` - Select AI model (default from config)
    * `--session <id>` - Use specific session ID
    * `--max-tokens <int>` - Maximum completion tokens (default: 500)
    * `--temperature <float>` - Model temperature (0.0-2.0, default: 0.3)
    * `--format <format>` - Output format: text, json (default: text)
    * `--input <file>` - Read prompt from file instead of argument
    * `--output <file>` - Write completion to file
    * `--append` - Append to output file instead of overwriting
    * `--verbose` - Include metadata in response
    * `--quiet` - Minimal output (completion only)
    * `--config <file>` - Use custom config file

  ## Examples

      # Complete Python function
      mix rubber_duck.complete "def fibonacci(n):" --language python

      # Complete with specific model
      mix rubber_duck.complete "SELECT * FROM users" --language sql --model gpt-4

      # Complete from file and save to file
      mix rubber_duck.complete --input incomplete.py --output completed.py --language python

      # Creative completion with higher temperature
      mix rubber_duck.complete "Once upon a time" --temperature 1.0

      # JSON output for integration with other tools
      mix rubber_duck.complete "function add(" --language javascript --format json
  """

  use Mix.Task

  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.CLI.{CommandParser, ResponseFormatter, ConfigManager}
  alias RubberDuck.CodingAssistant.FileSizeManager

  @shortdoc "Complete code or text with RubberDuck AI"

  @switches [
    language: :string,
    model: :string,
    session: :string,
    max_tokens: :integer,
    temperature: :float,
    format: :string,
    input: :string,
    output: :string,
    append: :boolean,
    verbose: :boolean,
    quiet: :boolean,
    config: :string,
    help: :boolean,
    force_streaming: :boolean,
    auto_stream: :boolean,
    auto_confirm: :boolean,
    max_file_size: :string
  ]

  @aliases [
    l: :language,
    m: :model,
    s: :session,
    t: :temperature,
    f: :format,
    i: :input,
    o: :output,
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
        
      options[:input] ->
        complete_from_file(options[:input], options)
        
      Enum.empty?(remaining_args) ->
        show_missing_prompt()
        exit({:shutdown, 1})
        
      true ->
        prompt = Enum.join(remaining_args, " ")
        complete_prompt(prompt, options)
    end
  end

  defp complete_from_file(input_file, options) do
    case File.read(input_file) do
      {:ok, content} ->
        # Check file size before processing
        case validate_file_size_for_completion(content, input_file, options) do
          :ok ->
            complete_prompt(content, options)
          {:stream_recommended, strategy} ->
            handle_large_file_completion(content, input_file, strategy, options)
          {:error, reason} ->
            Mix.shell().error("File size validation failed: #{reason}")
            exit({:shutdown, 1})
        end
      {:error, reason} ->
        Mix.shell().error("Cannot read input file '#{input_file}': #{reason}")
        exit({:shutdown, 1})
    end
  end

  defp complete_prompt(prompt, options) do
    # Load configuration
    config_overrides = extract_config_overrides(options)
    
    case ConfigManager.load_config(config_overrides) do
      {:ok, config} ->
        process_completion(prompt, config, options)
      {:error, reason} ->
        Mix.shell().error("Configuration error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp process_completion(prompt, config, options) do
    # Initialize CLI adapter
    case CLI.init(config: config) do
      {:ok, cli_state} ->
        execute_completion_request(prompt, cli_state, config, options)
      {:error, reason} ->
        Mix.shell().error("Failed to initialize CLI adapter: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp execute_completion_request(prompt, cli_state, config, options) do
    # Parse the complete command
    command_args = [prompt] ++ build_command_flags(options)
    
    case CommandParser.parse("complete", command_args) do
      {:ok, request} ->
        handle_completion_request(request, cli_state, config, options)
      {:error, reason} ->
        Mix.shell().error("Invalid request: #{reason}")
        show_usage_hint()
        exit({:shutdown, 1})
    end
  end

  defp handle_completion_request(request, cli_state, config, options) do
    context = build_request_context(config, options)
    
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
        timeout = get_timeout(config)
        Mix.shell().error("Request timed out after #{timeout}ms")
        exit({:shutdown, 1})
    end
  end

  defp display_success_response(response, request, config, options) do
    # Format the response
    case ResponseFormatter.format(response, request, config) do
      {:ok, formatted} ->
        output_completion(formatted, response, config, options)
      {:error, reason} ->
        Mix.shell().error("Format error: #{reason}")
        # Fallback to raw output
        completion = extract_completion_content(response)
        output_completion(completion, response, config, options)
    end
  end

  defp output_completion(formatted, response, config, options) do
    completion_text = case options[:format] do
      "json" ->
        create_json_output(response, options)
      _ ->
        if options[:quiet] do
          extract_completion_content(response)
        else
          formatted
        end
    end
    
    # Handle output destination
    case options[:output] do
      nil ->
        # Output to stdout
        Mix.shell().info(completion_text)
        
        # Show metadata if verbose and not quiet
        if options[:verbose] and not options[:quiet] do
          show_completion_metadata(response, config)
        end
        
      output_file ->
        write_to_file(completion_text, output_file, options)
        
        unless options[:quiet] do
          Mix.shell().info("Completion written to: #{output_file}")
          
          if options[:verbose] do
            show_completion_metadata(response, config)
          end
        end
    end
  end

  defp create_json_output(response, options) do
    json_data = if options[:verbose] do
      response
    else
      # Simplified JSON output
      %{
        completion: extract_completion_content(response),
        language: get_detected_language(response),
        confidence: get_confidence_score(response),
        status: response.status,
        timestamp: response.metadata[:timestamp]
      }
    end
    
    case Jason.encode(json_data, pretty: true) do
      {:ok, json} -> json
      {:error, reason} -> 
        Mix.shell().error("JSON encoding error: #{reason}")
        extract_completion_content(response)
    end
  end

  defp write_to_file(content, file_path, options) do
    write_mode = if options[:append], do: [:append], else: [:write]
    
    case File.write(file_path, content, write_mode) do
      :ok -> :ok
      {:error, reason} ->
        Mix.shell().error("Cannot write to file '#{file_path}': #{reason}")
        exit({:shutdown, 1})
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

  defp show_completion_metadata(response, config) do
    metadata = response.metadata || %{}
    completion_data = response.data || %{}
    
    metadata_lines = [
      "",
      colorize("Completion Metadata:", :dim, config)
    ]
    
    # Language detection
    if language = get_detected_language(response) do
      metadata_lines = [colorize("Detected language: #{language}", :dim, config) | metadata_lines]
    end
    
    # Confidence score
    if confidence = get_confidence_score(response) do
      score_text = "Confidence: #{Float.round(confidence, 2)}"
      metadata_lines = [colorize(score_text, :dim, config) | metadata_lines]
    end
    
    # Processing time
    if metadata[:processing_time] do
      time_ms = metadata.processing_time
      metadata_lines = [colorize("Processing time: #{time_ms}ms", :dim, config) | metadata_lines]
    end
    
    # Tokens used
    if metadata[:tokens_used] do
      tokens = metadata.tokens_used
      metadata_lines = [colorize("Tokens used: #{tokens}", :dim, config) | metadata_lines]
    end
    
    # Model used
    if metadata[:model_used] do
      model = metadata.model_used
      metadata_lines = [colorize("Model: #{model}", :dim, config) | metadata_lines]
    end
    
    # Suggestions
    if completion_data[:suggestions] && not Enum.empty?(completion_data.suggestions) do
      suggestions_text = "Suggestions: #{length(completion_data.suggestions)} available"
      metadata_lines = [colorize(suggestions_text, :dim, config) | metadata_lines]
    end
    
    Enum.reverse(metadata_lines)
    |> Enum.each(&Mix.shell().info/1)
  end

  defp extract_completion_content(response) do
    case response.data do
      %{completion: completion} when is_binary(completion) -> completion
      %{content: content} when is_binary(content) -> content
      %{result: result} when is_binary(result) -> result
      data when is_binary(data) -> data
      data -> inspect(data, pretty: true)
    end
  end

  defp get_detected_language(response) do
    case response.data do
      %{language: language} when is_binary(language) -> language
      _ -> nil
    end
  end

  defp get_confidence_score(response) do
    case response.data do
      %{confidence: confidence} when is_number(confidence) -> confidence
      _ -> nil
    end
  end

  defp build_command_flags(options) do
    flags = []
    
    flags = if options[:language], do: ["--language", options[:language] | flags], else: flags
    flags = if options[:model], do: ["--model", options[:model] | flags], else: flags
    flags = if options[:session], do: ["--session", options[:session] | flags], else: flags
    flags = if options[:max_tokens], do: ["--max-tokens", to_string(options[:max_tokens]) | flags], else: flags
    flags = if options[:temperature], do: ["--temperature", to_string(options[:temperature]) | flags], else: flags
    
    Enum.reverse(flags)
  end

  defp build_request_context(config, options) do
    %{
      interface: :cli,
      mode: :direct,
      config: config,
      timeout: get_timeout(config)
    }
  end

  defp extract_config_overrides(options) do
    config_map = %{}
    
    # Set default temperature for completions (lower for more predictable results)
    config_map = Map.put(config_map, :temperature, 0.3)
    
    # Set default max_tokens for completions
    config_map = Map.put(config_map, :max_tokens, 500)
    
    # Override with user options
    config_map = if options[:model], do: Map.put(config_map, :model, options[:model]), else: config_map
    config_map = if options[:temperature], do: Map.put(config_map, :temperature, options[:temperature]), else: config_map
    config_map = if options[:max_tokens], do: Map.put(config_map, :max_tokens, options[:max_tokens]), else: config_map
    config_map = if options[:verbose], do: Map.put(config_map, :verbose, true), else: config_map
    config_map = if options[:quiet], do: Map.put(config_map, :quiet, true), else: config_map
    
    config_map
  end

  defp get_timeout(config) do
    config[:timeout] || 30_000  # Default 30 seconds
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

  defp show_missing_prompt do
    Mix.shell().error("Missing required argument: prompt")
    Mix.shell().error("Use --input <file> to read prompt from file")
    show_usage_hint()
  end

  defp show_usage_hint do
    Mix.shell().info("Usage: mix rubber_duck.complete <prompt> [options]")
    Mix.shell().info("Run 'mix help rubber_duck.complete' for detailed help")
  end

  # File size validation and streaming support

  defp validate_file_size_for_completion(content, file_path, options) do
    content_size = byte_size(content)
    
    # Check if streaming is forced via options
    if options[:force_streaming] do
      strategy = %{
        type: :streaming,
        file_size: content_size,
        recommended_chunk_size: 64 * 1024
      }
      {:stream_recommended, strategy}
    else
      # Use FileSizeManager for validation and strategy recommendation
      case FileSizeManager.validate_file_size(content_size, %{processing_mode: :completion}) do
        :ok ->
          # Check if streaming is recommended for this size
          case FileSizeManager.get_processing_strategy(content_size, :code) do
            strategy when strategy.type in [:streaming, :memory_mapped, :chunked] ->
              if options[:auto_stream] != false do
                {:stream_recommended, strategy}
              else
                :ok  # User can still force standard processing
              end
            
            _standard_strategy ->
              :ok
          end
        
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp handle_large_file_completion(content, file_path, strategy, options) do
    content_size = byte_size(content)
    
    # Show information about large file processing
    Mix.shell().info([
      :bright, :blue, "Large file detected: ",
      :reset, format_file_size(content_size)
    ])
    
    Mix.shell().info([
      :yellow, "Recommended processing strategy: ",
      :reset, "#{strategy.type}"
    ])
    
    # Ask user for confirmation unless auto-confirm is enabled
    if options[:auto_confirm] || confirm_streaming_processing(strategy) do
      # Process with streaming
      complete_prompt_with_streaming(content, file_path, strategy, options)
    else
      # Fall back to standard processing with warning
      Mix.shell().info([:yellow, "Proceeding with standard processing (may be slow)..."])
      complete_prompt(content, options)
    end
  end

  defp confirm_streaming_processing(strategy) do
    Mix.shell().yes?([
      :bright, :green, "Use streaming analysis for optimal performance? ",
      :reset, "(recommended for files > 1MB)"
    ])
  end

  defp complete_prompt_with_streaming(content, file_path, strategy, options) do
    # Add streaming metadata to options
    streaming_options = options
    |> Keyword.put(:processing_mode, :streaming)
    |> Keyword.put(:chunk_size, strategy.recommended_chunk_size)
    |> Keyword.put(:file_info, %{
      path: file_path,
      size: byte_size(content),
      strategy: strategy.type
    })
    
    # Show progress for streaming processing
    Mix.shell().info([:bright, :blue, "Processing with streaming analysis..."])
    
    case complete_prompt(content, streaming_options) do
      result ->
        # Show completion statistics if verbose
        if options[:verbose] do
          show_streaming_stats(strategy, byte_size(content))
        end
        result
    end
  end

  defp show_streaming_stats(strategy, content_size) do
    estimated_chunks = div(content_size, strategy.recommended_chunk_size) + 1
    estimated_memory = strategy.estimated_memory || (content_size / 4)
    
    Mix.shell().info([
      :bright, :blue, "\nStreaming Analysis Statistics:\n",
      :reset, "  File size: ", format_file_size(content_size), "\n",
      "  Strategy: #{strategy.type}\n",
      "  Estimated chunks: #{estimated_chunks}\n",
      "  Estimated memory usage: ", format_file_size(round(estimated_memory)), "\n"
    ])
  end

  defp format_file_size(bytes) when bytes >= 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
  end
  
  defp format_file_size(bytes) when bytes >= 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  end
  
  defp format_file_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end
  
  defp format_file_size(bytes) do
    "#{bytes} bytes"
  end
end