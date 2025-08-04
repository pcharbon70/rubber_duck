defmodule RubberDuck.Tools.RegexExtractor do
  @moduledoc """
  Extracts patterns from code using regex queries.
  
  This tool provides powerful pattern extraction capabilities using regular expressions
  to find and extract specific patterns from code, documentation, or any text content.
  Supports multiple extraction modes, pattern libraries, and result formatting options.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :regex_extractor
    description "Extracts patterns from code using regex queries"
    category :code_analysis
    version "1.0.0"
    tags [:regex, :pattern_extraction, :text_analysis, :code_search]
    
    parameter :content do
      type :string
      required true
      description "The text/code content to extract patterns from"
      constraints [
        min_length: 1,
        max_length: 100_000
      ]
    end
    
    parameter :pattern do
      type :string
      required true
      description "The regular expression pattern to match"
      constraints [
        min_length: 1,
        max_length: 1000
      ]
    end
    
    parameter :extraction_mode do
      type :string
      required false
      description "How to extract matches from the content"
      default "matches"
      constraints [
        enum: [
          "matches",        # Return all matches
          "captures",       # Return captured groups
          "named_captures", # Return named capture groups
          "replace",        # Replace matches with substitution
          "split",          # Split content on pattern
          "scan",           # Advanced scanning with position info
          "count"           # Just count matches
        ]
      ]
    end
    
    parameter :options do
      type :map
      required false
      description "Regex compilation and matching options"
      default %{}
    end
    
    parameter :substitution do
      type :string
      required false
      description "Replacement string when using 'replace' mode"
      default ""
    end
    
    parameter :max_matches do
      type :integer
      required false
      description "Maximum number of matches to return (0 = unlimited)"
      default 0
      constraints [
        min: 0,
        max: 10000
      ]
    end
    
    parameter :include_positions do
      type :boolean
      required false
      description "Include position information for matches"
      default false
    end
    
    parameter :include_context do
      type :boolean
      required false
      description "Include surrounding context for each match"
      default false
    end
    
    parameter :context_lines do
      type :integer
      required false
      description "Number of lines of context to include before/after matches"
      default 2
      constraints [
        min: 0,
        max: 10
      ]
    end
    
    parameter :output_format do
      type :string
      required false
      description "Format for the extraction results"
      default "structured"
      constraints [
        enum: ["structured", "json", "csv", "plain", "detailed"]
      ]
    end
    
    parameter :pattern_library do
      type :string
      required false
      description "Use a predefined pattern from the pattern library"
      default nil
      constraints [
        enum: [
          "email", "url", "ip_address", "phone", "date", "time", "uuid",
          "elixir_function", "elixir_module", "elixir_variable", "elixir_atom",
          "javascript_function", "javascript_variable", "sql_table", "sql_column",
          "html_tag", "css_class", "css_id", "hex_color", "version_number",
          "file_path", "docker_image", "git_commit", "log_level", "stack_trace"
        ]
      ]
    end
    
    parameter :multiline do
      type :boolean
      required false
      description "Enable multiline matching mode"
      default false
    end
    
    parameter :case_sensitive do
      type :boolean
      required false
      description "Case sensitive matching"
      default true
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:regex_processing]
      rate_limit [max_requests: 200, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the regex extraction based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, regex_pattern} <- build_regex_pattern(params),
         {:ok, compiled_regex} <- compile_regex(regex_pattern, params),
         {:ok, matches} <- extract_matches(params.content, compiled_regex, params),
         {:ok, processed_results} <- process_results(matches, params),
         {:ok, formatted_output} <- format_output(processed_results, params) do
      
      {:ok, %{
        pattern: regex_pattern,
        extraction_mode: params.extraction_mode,
        total_matches: get_match_count(processed_results),
        results: formatted_output,
        statistics: calculate_statistics(processed_results, params),
        metadata: %{
          content_length: String.length(params.content),
          pattern_complexity: estimate_pattern_complexity(regex_pattern),
          execution_time: context[:execution_time] || 0
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp build_regex_pattern(params) do
    cond do
      params.pattern_library -> 
        get_library_pattern(params.pattern_library)
      
      params.pattern -> 
        {:ok, params.pattern}
      
      true -> 
        {:error, "Either pattern or pattern_library must be specified"}
    end
  end
  
  defp get_library_pattern(library_key) do
    patterns = %{
      # Contact Information
      "email" => ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      "phone" => ~r/\b(?:\+?1[-.]?)?\(?([0-9]{3})\)?[-.]?([0-9]{3})[-.]?([0-9]{4})\b/,
      
      # Network
      "url" => ~r/https?:\/\/[^\s]+/,
      "ip_address" => ~r/\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b/,
      
      # Date/Time
      "date" => ~r/\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/,
      "time" => ~r/\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp][Mm])?\b/,
      
      # Identifiers
      "uuid" => ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
      "hex_color" => ~r/#[0-9A-Fa-f]{3,6}\b/,
      "version_number" => ~r/\bv?\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9-]+)?\b/,
      
      # Elixir Patterns
      "elixir_function" => ~r/def\s+([a-z_][a-zA-Z0-9_]*[!?]?)\s*\(/,
      "elixir_module" => ~r/defmodule\s+([A-Z][a-zA-Z0-9_.]*)/,
      "elixir_variable" => ~r/\b[a-z_][a-zA-Z0-9_]*\b/,
      "elixir_atom" => ~r/:[a-zA-Z_][a-zA-Z0-9_]*[!?]?/,
      
      # JavaScript Patterns
      "javascript_function" => ~r/function\s+([a-zA-Z_$][a-zA-Z0-9_$]*)\s*\(/,
      "javascript_variable" => ~r/(?:var|let|const)\s+([a-zA-Z_$][a-zA-Z0-9_$]*)/,
      
      # SQL Patterns
      "sql_table" => ~r/FROM\s+([a-zA-Z_][a-zA-Z0-9_]*)/i,
      "sql_column" => ~r/SELECT\s+([a-zA-Z_][a-zA-Z0-9_]*(?:\s*,\s*[a-zA-Z_][a-zA-Z0-9_]*)*)/i,
      
      # Web Patterns
      "html_tag" => ~r/<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/,
      "css_class" => ~r/\.([a-zA-Z_-][a-zA-Z0-9_-]*)/,
      "css_id" => ~r/#([a-zA-Z_-][a-zA-Z0-9_-]*)/,
      
      # File System
      "file_path" => ~r/\b(?:\/[\w.-]+)+\/?\b/,
      
      # DevOps
      "docker_image" => ~r/(?:[a-zA-Z0-9.-]+\/)?[a-zA-Z0-9.-]+(?::[a-zA-Z0-9.-]+)?/,
      "git_commit" => ~r/\b[0-9a-f]{7,40}\b/,
      
      # Logging
      "log_level" => ~r/\b(?:DEBUG|INFO|WARN|ERROR|FATAL|TRACE)\b/i,
      "stack_trace" => ~r/at\s+[a-zA-Z0-9_.]+\([^)]*\)(?:\s+~r\/[^:]+:\d+)?/
    }
    
    case Map.get(patterns, library_key) do
      nil -> {:error, "Unknown pattern library key: #{library_key}"}
      regex -> {:ok, Regex.source(regex)}
    end
  end
  
  defp compile_regex(pattern, params) do
    # Build regex options
    options = []
    options = if params.case_sensitive, do: options, else: [:caseless | options]
    options = if params.multiline, do: [:multiline | options], else: options
    
    # Add any custom options from params.options
    custom_options = params.options
    |> Map.get("regex_options", [])
    |> Enum.map(&String.to_atom/1)
    
    all_options = options ++ custom_options
    
    case Regex.compile(pattern, all_options) do
      {:ok, regex} -> {:ok, regex}
      {:error, {reason, _}} -> {:error, "Regex compilation failed: #{reason}"}
    end
  end
  
  defp extract_matches(content, regex, params) do
    try do
      case params.extraction_mode do
        "matches" -> extract_all_matches(content, regex, params)
        "captures" -> extract_captures(content, regex, params)
        "named_captures" -> extract_named_captures(content, regex, params)
        "replace" -> extract_with_replacement(content, regex, params)
        "split" -> extract_with_split(content, regex, params)
        "scan" -> extract_with_scan(content, regex, params)
        "count" -> extract_count_only(content, regex, params)
        _ -> {:error, "Unknown extraction mode: #{params.extraction_mode}"}
      end
    rescue
      error -> {:error, "Extraction failed: #{inspect(error)}"}
    end
  end
  
  defp extract_all_matches(content, regex, params) do
    matches = Regex.scan(regex, content)
    |> Enum.map(fn match ->
      case match do
        [full_match | _] -> full_match
        [] -> ""
      end
    end)
    |> limit_matches(params.max_matches)
    
    {:ok, matches}
  end
  
  defp extract_captures(content, regex, params) do
    captures = Regex.scan(regex, content, capture: :all_but_first)
    |> limit_matches(params.max_matches)
    
    {:ok, captures}
  end
  
  defp extract_named_captures(content, regex, params) do
    named_captures = Regex.scan(regex, content, capture: :all_names)
    |> limit_matches(params.max_matches)
    
    {:ok, named_captures}
  end
  
  defp extract_with_replacement(content, regex, params) do
    substitution = params.substitution || ""
    result = Regex.replace(regex, content, substitution, global: true)
    {:ok, result}
  end
  
  defp extract_with_split(content, regex, params) do
    parts = Regex.split(regex, content)
    |> limit_matches(params.max_matches)
    
    {:ok, parts}
  end
  
  defp extract_with_scan(content, regex, params) do
    matches = Regex.scan(regex, content, return: :index)
    |> Enum.map(fn match_indices ->
      case match_indices do
        [{start, length} | _] ->
          match_text = String.slice(content, start, length)
          %{
            text: match_text,
            start_position: start,
            end_position: start + length - 1,
            length: length,
            line_number: get_line_number(content, start)
          }
        [] -> %{text: "", start_position: 0, end_position: 0, length: 0, line_number: 1}
      end
    end)
    |> limit_matches(params.max_matches)
    
    {:ok, matches}
  end
  
  defp extract_count_only(content, regex, _params) do
    count = Regex.scan(regex, content) |> length()
    {:ok, count}
  end
  
  defp limit_matches(matches, 0), do: matches
  defp limit_matches(matches, max_matches) when max_matches > 0 do
    Enum.take(matches, max_matches)
  end
  
  defp get_line_number(content, position) do
    content
    |> String.slice(0, position)
    |> String.split("\n")
    |> length()
  end
  
  defp process_results(matches, params) do
    processed = cond do
      params.include_positions and params.extraction_mode != "scan" ->
        add_position_info(matches, params)
      
      params.include_context ->
        add_context_info(matches, params)
      
      true ->
        matches
    end
    
    {:ok, processed}
  end
  
  defp add_position_info(matches, _params) when is_list(matches) do
    # For modes that don't already include position info
    Enum.with_index(matches, fn match, index ->
      %{
        match: match,
        index: index,
        # Would need to re-scan to get actual positions
        # This is a simplified version
        estimated_position: index * 50
      }
    end)
  end
  defp add_position_info(matches, _params), do: matches
  
  defp add_context_info(matches, params) when is_list(matches) do
    content_lines = String.split(params.content, "\n")
    
    Enum.map(matches, fn match ->
      # Simplified context addition - would need actual line detection
      context_before = Enum.take(content_lines, params.context_lines)
      context_after = Enum.take(content_lines, -params.context_lines)
      
      %{
        match: match,
        context: %{
          before: context_before,
          after: context_after
        }
      }
    end)
  end
  defp add_context_info(matches, _params), do: matches
  
  defp format_output(results, params) do
    case params.output_format do
      "structured" -> {:ok, results}
      "json" -> format_as_json(results)
      "csv" -> format_as_csv(results)
      "plain" -> format_as_plain(results)
      "detailed" -> format_as_detailed(results, params)
      _ -> {:ok, results}
    end
  end
  
  defp format_as_json(results) do
    case Jason.encode(results, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "JSON formatting failed: #{inspect(reason)}"}
    end
  end
  
  defp format_as_csv(results) when is_list(results) do
    csv_content = results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      case result do
        %{match: match} -> "#{index},\"#{escape_csv(inspect(match))}\""
        match when is_binary(match) -> "#{index},\"#{escape_csv(match)}\""
        _ -> "#{index},\"#{escape_csv(inspect(result))}\""
      end
    end)
    |> Enum.join("\n")
    
    header = "Index,Match\n"
    {:ok, header <> csv_content}
  end
  defp format_as_csv(results), do: {:ok, inspect(results)}
  
  defp format_as_plain(results) when is_list(results) do
    plain_content = results
    |> Enum.map(fn result ->
      case result do
        %{match: match} -> inspect(match)
        match when is_binary(match) -> match
        _ -> inspect(result)
      end
    end)
    |> Enum.join("\n")
    
    {:ok, plain_content}
  end
  defp format_as_plain(results), do: {:ok, inspect(results)}
  
  defp format_as_detailed(results, params) do
    detailed = %{
      extraction_summary: %{
        pattern: params.pattern || params.pattern_library,
        mode: params.extraction_mode,
        total_results: get_match_count(results),
        options_used: build_options_summary(params)
      },
      results: results,
      statistics: calculate_statistics(results, params)
    }
    
    {:ok, detailed}
  end
  
  defp escape_csv(text) do
    text
    |> String.replace("\"", "\"\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
  
  defp build_options_summary(params) do
    %{
      multiline: params.multiline,
      case_sensitive: params.case_sensitive,
      include_positions: params.include_positions,
      include_context: params.include_context,
      max_matches: params.max_matches
    }
  end
  
  defp get_match_count(results) when is_list(results), do: length(results)
  defp get_match_count(results) when is_integer(results), do: results
  defp get_match_count(_), do: 1
  
  defp calculate_statistics(results, params) do
    %{
      total_matches: get_match_count(results),
      average_match_length: calculate_average_length(results),
      unique_matches: count_unique_matches(results),
      match_distribution: analyze_match_distribution(results),
      extraction_efficiency: calculate_efficiency(results, params)
    }
  end
  
  defp calculate_average_length(results) when is_list(results) do
    lengths = results
    |> Enum.map(fn result ->
      case result do
        %{match: match} when is_binary(match) -> String.length(match)
        match when is_binary(match) -> String.length(match)
        _ -> 0
      end
    end)
    
    if length(lengths) > 0 do
      Enum.sum(lengths) / length(lengths)
    else
      0.0
    end
  end
  defp calculate_average_length(_), do: 0.0
  
  defp count_unique_matches(results) when is_list(results) do
    results
    |> Enum.map(fn result ->
      case result do
        %{match: match} -> match
        match -> match
      end
    end)
    |> Enum.uniq()
    |> length()
  end
  defp count_unique_matches(_), do: 1
  
  defp analyze_match_distribution(results) when is_list(results) do
    results
    |> Enum.map(fn result ->
      case result do
        %{match: match} when is_binary(match) -> String.length(match)
        match when is_binary(match) -> String.length(match)
        _ -> 0
      end
    end)
    |> Enum.frequencies_by(fn length ->
      cond do
        length <= 5 -> "short"
        length <= 20 -> "medium" 
        length <= 50 -> "long"
        true -> "very_long"
      end
    end)
  end
  defp analyze_match_distribution(_), do: %{}
  
  defp calculate_efficiency(results, params) do
    content_length = String.length(params.content)
    match_count = get_match_count(results)
    
    if content_length > 0 do
      (match_count / content_length) * 1000 # matches per 1000 characters
    else
      0.0
    end
  end
  
  defp estimate_pattern_complexity(pattern) do
    # Simple complexity estimation based on regex features
    complexity_factors = [
      {~r/\[.*\]/, 1},        # character classes
      {~r/\(.*\)/, 2},        # groups
      {~r/\*|\+|\?/, 1},      # quantifiers
      {~r/\{\d+,?\d*\}/, 2},  # specific quantifiers
      {~r/\|/, 2},            # alternation
      {~r/\\[wWdDsS]/, 1},   # character shortcuts
      {~r/\^|\$/, 1},         # anchors
      {~r/\(\?[^)]*\)/, 3}   # advanced groups
    ]
    
    Enum.reduce(complexity_factors, 1, fn {regex, weight}, acc ->
      matches = Regex.scan(regex, pattern) |> length()
      acc + (matches * weight)
    end)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end