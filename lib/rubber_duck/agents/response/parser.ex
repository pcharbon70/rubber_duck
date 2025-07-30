defmodule RubberDuck.Agents.Response.Parser do
  @moduledoc """
  Multi-format response parsing system.
  
  This module provides a unified interface for parsing various response formats
  from LLM providers, with automatic format detection and structured extraction
  capabilities.
  """

  require Logger

  @behaviour ResponseParser

  @doc """
  Behavior that all format-specific parsers must implement.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour RubberDuck.Agents.Response.Parser.ResponseParser
    end
  end

  defmodule ResponseParser do
    @moduledoc """
    Behavior for format-specific response parsers.
    """

    @callback parse(content :: String.t(), options :: map()) :: 
      {:ok, parsed_content :: term()} | {:error, reason :: String.t()}
    
    @callback detect(content :: String.t()) :: 
      {:ok, confidence :: float()} | {:error, reason :: String.t()}
    
    @callback format() :: atom()
    
    @callback supports_streaming?() :: boolean()
  end

  # Format detection patterns
  @format_patterns %{
    json: [
      {~r/^\s*[\{\[]/, 0.8},
      {~r/^\s*[\{\[].*[\}\]]\s*$/s, 0.9},
      {~r/"[^"]*"\s*:\s*/, 0.7}
    ],
    xml: [
      {~r/^\s*<\?xml/, 0.95},
      {~r/^\s*<[^>]+>/, 0.8},
      {~r/<\/[^>]+>\s*$/, 0.7}
    ],
    markdown: [
      {~r/^#+\s/, 0.8},
      {~r/\*\*[^*]+\*\*/, 0.6},
      {~r/\[[^\]]+\]\([^)]+\)/, 0.7},
      {~r/```[^`]*```/s, 0.9}
    ],
    html: [
      {~r/^\s*<!DOCTYPE html/i, 0.95},
      {~r/<html[^>]*>/i, 0.9},
      {~r/<\/html>\s*$/i, 0.9},
      {~r/<[a-z]+[^>]*>/i, 0.6}
    ],
    yaml: [
      {~r/^---\s*$/, 0.9},
      {~r/^\s*[a-zA-Z_][a-zA-Z0-9_]*\s*:\s*/, 0.7},
      {~r/^\s*-\s+/, 0.6}
    ],
    code: [
      {~r/^(def|function|class|import|from)\s/, 0.8},
      {~r/[{}();]/, 0.6},
      {~r/^\s*(\/\/|\/\*|#)/, 0.7}
    ]
  }

  @doc """
  Parses a response with automatic format detection.
  
  ## Examples
  
      iex> content = ~s({"name": "John", "age": 30})
      iex> RubberDuck.Agents.Response.Parser.parse(content)
      {:ok, %{"name" => "John", "age" => 30}, :json}
  """
  def parse(content, options \\ %{}) when is_binary(content) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, format} <- detect_format(content, options),
         {:ok, parsed_content} <- parse_with_format(content, format, options) do
      
      processing_time = System.monotonic_time(:millisecond) - start_time
      
      {:ok, parsed_content, format, %{processing_time: processing_time}}
    else
      {:error, reason} ->
        # Fallback to text parsing
        {:ok, content, :text, %{
          processing_time: System.monotonic_time(:millisecond) - start_time,
          fallback_reason: reason
        }}
    end
  end

  @doc """
  Detects the format of the given content.
  
  Returns the most likely format based on pattern matching and confidence scores.
  """
  def detect_format(content, options \\ %{}) do
    force_format = Map.get(options, :force_format)
    
    if force_format && format_supported?(force_format) do
      {:ok, force_format}
    else
      scores = calculate_format_confidence(content)
      
      case Enum.max_by(scores, fn {_format, confidence} -> confidence end, fn -> nil end) do
        {format, confidence} when confidence >= 0.6 ->
          {:ok, format}
        _ ->
          {:ok, :text}  # Default fallback
      end
    end
  end

  @doc """
  Parses content with a specific format.
  """
  def parse_with_format(content, format, options \\ %{}) do
    case get_parser_module(format) do
      {:ok, parser_module} ->
        try do
          parser_module.parse(content, options)
        rescue
          error ->
            Logger.warning("Parser #{parser_module} failed: #{inspect(error)}")
            {:error, "Parsing failed: #{Exception.message(error)}"}
        end
        
      {:error, :unsupported} ->
        # Return content as-is for unsupported formats
        {:ok, content}
    end
  end

  @doc """
  Lists all supported formats.
  """
  def supported_formats do
    Map.keys(@format_patterns) ++ [:text]
  end

  @doc """
  Checks if a format is supported.
  """
  def format_supported?(format) do
    format in supported_formats()
  end

  @doc """
  Parses a streaming response incrementally.
  """
  def parse_streaming(content_stream, format, options \\ %{}) do
    case get_parser_module(format) do
      {:ok, parser_module} ->
        if parser_module.supports_streaming?() do
          parse_streaming_with_module(content_stream, parser_module, options)
        else
          # Accumulate full content then parse
          full_content = Enum.join(content_stream, "")
          parse_with_format(full_content, format, options)
        end
        
      {:error, :unsupported} ->
        # Return accumulated content
        {:ok, Enum.join(content_stream, "")}
    end
  end

  @doc """
  Validates that parsed content matches expected structure.
  """
  def validate_parsed_content(parsed_content, format, validation_rules \\ %{}) do
    case format do
      :json -> validate_json_structure(parsed_content, validation_rules)
      :xml -> validate_xml_structure(parsed_content, validation_rules)
      :markdown -> validate_markdown_structure(parsed_content, validation_rules)
      _ -> {:ok, parsed_content}
    end
  end

  @doc """
  Extracts metadata from parsed content.
  """
  def extract_metadata(parsed_content, format) do
    case format do
      :json -> extract_json_metadata(parsed_content)
      :xml -> extract_xml_metadata(parsed_content)
      :markdown -> extract_markdown_metadata(parsed_content)
      :html -> extract_html_metadata(parsed_content)
      _ -> %{}
    end
  end

  # Private functions

  defp calculate_format_confidence(content) do
    @format_patterns
    |> Enum.map(fn {format, patterns} ->
      confidence = calculate_pattern_confidence(content, patterns)
      {format, confidence}
    end)
  end

  defp calculate_pattern_confidence(content, patterns) do
    patterns
    |> Enum.map(fn {pattern, weight} ->
      if Regex.match?(pattern, content), do: weight, else: 0.0
    end)
    |> Enum.sum()
    |> min(1.0)  # Cap at 1.0
  end

  defp get_parser_module(format) do
    case format do
      :json -> {:ok, __MODULE__.JSONParser}
      :xml -> {:ok, __MODULE__.XMLParser}
      :markdown -> {:ok, __MODULE__.MarkdownParser}
      :html -> {:ok, __MODULE__.HTMLParser}
      :yaml -> {:ok, __MODULE__.YAMLParser}
      :code -> {:ok, __MODULE__.CodeParser}
      :text -> {:ok, __MODULE__.TextParser}
      _ -> {:error, :unsupported}
    end
  end

  defp parse_streaming_with_module(content_stream, parser_module, options) do
    # This would be implemented based on the specific parser's streaming capabilities
    # For now, fall back to accumulating content
    full_content = Enum.join(content_stream, "")
    parser_module.parse(full_content, options)
  end

  defp validate_json_structure(parsed_content, _validation_rules) do
    # Basic JSON validation
    cond do
      is_map(parsed_content) or is_list(parsed_content) ->
        {:ok, parsed_content}
      true ->
        {:error, "Invalid JSON structure"}
    end
  end

  defp validate_xml_structure(parsed_content, _validation_rules) do
    # Basic XML validation would go here
    {:ok, parsed_content}
  end

  defp validate_markdown_structure(parsed_content, _validation_rules) do
    # Basic Markdown validation would go here
    {:ok, parsed_content}
  end

  defp extract_json_metadata(parsed_content) when is_map(parsed_content) do
    %{
      keys: Map.keys(parsed_content),
      depth: calculate_map_depth(parsed_content),
      size: map_size(parsed_content)
    }
  end

  defp extract_json_metadata(parsed_content) when is_list(parsed_content) do
    %{
      length: length(parsed_content),
      types: parsed_content |> Enum.map(&get_type/1) |> Enum.uniq()
    }
  end

  defp extract_json_metadata(_), do: %{}

  defp extract_xml_metadata(_parsed_content) do
    %{type: :xml}
  end

  defp extract_markdown_metadata(content) when is_binary(content) do
    %{
      headers: count_markdown_headers(content),
      links: count_markdown_links(content),
      code_blocks: count_code_blocks(content),
      word_count: count_words(content)
    }
  end

  defp extract_markdown_metadata(_), do: %{}

  defp extract_html_metadata(_parsed_content) do
    %{type: :html}
  end

  defp calculate_map_depth(map) when is_map(map) do
    if Enum.empty?(map) do
      1
    else
      map
      |> Map.values()
      |> Enum.map(fn
        value when is_map(value) -> 1 + calculate_map_depth(value)
        _ -> 1
      end)
      |> Enum.max()
    end
  end

  defp get_type(value) when is_binary(value), do: :string
  defp get_type(value) when is_integer(value), do: :integer
  defp get_type(value) when is_float(value), do: :float
  defp get_type(value) when is_boolean(value), do: :boolean
  defp get_type(value) when is_list(value), do: :list
  defp get_type(value) when is_map(value), do: :map
  defp get_type(_), do: :unknown

  defp count_markdown_headers(content) do
    Regex.scan(~r/^#+\s/m, content) |> length()
  end

  defp count_markdown_links(content) do
    Regex.scan(~r/\[[^\]]+\]\([^)]+\)/, content) |> length()
  end

  defp count_code_blocks(content) do
    Regex.scan(~r/```[^`]*```/s, content) |> length()
  end

  defp count_words(content) do
    content
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end
end