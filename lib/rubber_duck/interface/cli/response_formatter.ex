defmodule RubberDuck.Interface.CLI.ResponseFormatter do
  @moduledoc """
  Formats responses for terminal output with CLI-specific formatting.
  
  This module handles the conversion of response data into terminal-friendly
  output with support for colors, syntax highlighting, progress indicators,
  and various verbosity levels.
  
  ## Features
  
  - Syntax highlighting for code blocks
  - Colored output based on message types
  - Progress indicators and spinners
  - Table formatting for structured data
  - Stream formatting for real-time responses
  - Verbosity level controls
  - Terminal width adaptation
  
  ## Usage
  
      response = %{message: "Hello world", code: "def hello, do: :world"}
      {:ok, formatted} = ResponseFormatter.format(response, request, config)
      IO.puts(formatted)
  """

  alias RubberDuck.Interface.Behaviour

  @type format_result :: {:ok, String.t()} | {:error, String.t()}
  @type config :: map()
  @type request :: Behaviour.request()
  @type response :: Behaviour.response()

  # ANSI color codes
  @colors %{
    reset: "\e[0m",
    bold: "\e[1m",
    dim: "\e[2m",
    italic: "\e[3m",
    underline: "\e[4m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    white: "\e[37m",
    bright_red: "\e[91m",
    bright_green: "\e[92m",
    bright_yellow: "\e[93m",
    bright_blue: "\e[94m",
    bright_magenta: "\e[95m",
    bright_cyan: "\e[96m",
    bright_white: "\e[97m"
  }

  # Programming language syntax patterns
  @syntax_patterns %{
    elixir: [
      {~r/\b(def|defp|defmodule|defprotocol|defimpl|defstruct|defexception)\b/, :keyword},
      {~r/\b(do|end|if|else|unless|cond|case|when|with|try|rescue|catch|after|receive)\b/, :control},
      {~r/\b(true|false|nil)\b/, :constant},
      {~r/"(?:[^"\\]|\\.)*"/, :string},
      {~r/'(?:[^'\\]|\\.)*'/, :string},
      {~r/#.*$/, :comment},
      {~r/:\w+/, :atom},
      {~r/@\w+/, :attribute}
    ],
    python: [
      {~r/\b(def|class|import|from|return|if|elif|else|for|while|try|except|finally|with|as|yield|lambda)\b/, :keyword},
      {~r/\b(True|False|None)\b/, :constant},
      {~r/"(?:[^"\\]|\\.)*"/, :string},
      {~r/'(?:[^'\\]|\\.)*'/, :string},
      {~r/#.*$/, :comment},
      {~r/\d+/, :number}
    ],
    javascript: [
      {~r/\b(function|const|let|var|return|if|else|for|while|try|catch|finally|class|extends|async|await)\b/, :keyword},
      {~r/\b(true|false|null|undefined)\b/, :constant},
      {~r/"(?:[^"\\]|\\.)*"/, :string},
      {~r/'(?:[^'\\]|\\.)*'/, :string},
      {~r/\/\/.*$/, :comment},
      {~r/\d+/, :number}
    ]
  }

  @doc """
  Format a response for CLI output based on the request type and configuration.
  
  ## Parameters
  - `response` - The response data to format
  - `request` - The original request for context
  - `config` - CLI configuration including colors, verbosity, etc.
  
  ## Returns
  - `{:ok, formatted_string}` - Successfully formatted output
  - `{:error, reason}` - Formatting failed with reason
  """
  def format(response, request, config \\ %{}) do
    try do
      formatted = case response.status do
        :success -> format_success_response(response, request, config)
        :error -> format_error_response(response, request, config)
        :stream -> format_stream_response(response, request, config)
        _ -> format_unknown_response(response, request, config)
      end
      
      {:ok, formatted}
    rescue
      error -> {:error, "Formatting error: #{Exception.message(error)}"}
    end
  end

  @doc """
  Format a response for streaming output (real-time updates).
  """
  def format_stream(chunk, request, config \\ %{}) do
    case chunk do
      %{type: :start} -> format_stream_start(chunk, config)
      %{type: :data} -> format_stream_data(chunk, config)
      %{type: :end} -> format_stream_end(chunk, config)
      %{type: :error} -> format_stream_error(chunk, config)
      _ -> format_stream_data(chunk, config)
    end
  end

  @doc """
  Create a progress indicator for long-running operations.
  """
  def progress_indicator(message, config \\ %{}) do
    if config[:colors] != false do
      spinner = get_spinner_frame()
      colorize("#{spinner} #{message}", :cyan, config)
    else
      "... #{message}"
    end
  end

  @doc """
  Format data as a table for structured output.
  """
  def format_table(headers, rows, config \\ %{}) do
    # Calculate column widths
    max_widths = calculate_column_widths(headers, rows)
    
    # Format header
    header_line = format_table_row(headers, max_widths, config)
    separator = create_table_separator(max_widths, config)
    
    # Format data rows
    data_lines = Enum.map(rows, &format_table_row(&1, max_widths, config))
    
    [header_line, separator | data_lines]
    |> Enum.join("\n")
  end

  @doc """
  Apply syntax highlighting to code based on detected language.
  """
  def highlight_code(code, language \\ nil, config \\ %{}) do
    if config[:syntax_highlight] != false and config[:colors] != false do
      detected_language = language || detect_language(code)
      apply_syntax_highlighting(code, detected_language, config)
    else
      code
    end
  end

  # Private formatting functions

  defp format_success_response(response, request, config) do
    case request.operation do
      :chat -> format_chat_response(response, config)
      :complete -> format_completion_response(response, config)
      :analyze -> format_analysis_response(response, config)
      :session_management -> format_session_response(response, config)
      :configuration -> format_config_response(response, config)
      :help -> format_help_response(response, config)
      :status -> format_status_response(response, config)
      :version -> format_version_response(response, config)
      _ -> format_generic_response(response, config)
    end
  end

  defp format_error_response(response, request, config) do
    error_icon = if config[:colors] != false, do: colorize("✗", :red, config), else: "[ERROR]"
    error_message = colorize(response.data.message || "Unknown error", :red, config)
    
    error_text = "#{error_icon} #{error_message}"
    
    # Add suggestions if available
    case response.data[:suggestions] do
      suggestions when is_list(suggestions) and length(suggestions) > 0 ->
        suggestion_text = format_suggestions(suggestions, config)
        "#{error_text}\n\n#{suggestion_text}"
      _ ->
        error_text
    end
  end

  defp format_stream_response(response, _request, config) do
    case response.data do
      %{chunk: chunk} -> format_stream_chunk(chunk, config)
      %{message: message} -> message
      data -> inspect(data, pretty: true)
    end
  end

  defp format_unknown_response(response, _request, config) do
    warning = colorize("⚠ Unknown response format", :yellow, config)
    data = inspect(response.data, pretty: true)
    "#{warning}\n#{data}"
  end

  # Specific response formatters

  defp format_chat_response(response, config) do
    message = response.data.message || ""
    
    # Add duck emoji prefix for chat responses
    prefix = if config[:colors] != false do
      "🦆 "
    else
      "RubberDuck: "
    end
    
    formatted_message = if String.contains?(message, "```") do
      format_message_with_code_blocks(message, config)
    else
      message
    end
    
    "#{prefix}#{formatted_message}"
  end

  defp format_completion_response(response, config) do
    completion = response.data.completion || ""
    language = response.data.language || detect_language(completion)
    
    # Highlight the completion
    highlighted = highlight_code(completion, language, config)
    
    # Add metadata if verbose
    if config[:verbose] do
      confidence = response.data.confidence || 0.0
      metadata = colorize("(#{language}, confidence: #{Float.round(confidence, 2)})", :dim, config)
      "#{highlighted}\n\n#{metadata}"
    else
      highlighted
    end
  end

  defp format_analysis_response(response, config) do
    analysis = response.data
    
    sections = []
    
    # Content type and language
    if analysis[:content_type] or analysis[:language] do
      type_info = [analysis[:content_type], analysis[:language]]
      |> Enum.filter(& &1)
      |> Enum.join(", ")
      
      header = colorize("Analysis: #{type_info}", :cyan, config)
      sections = [header | sections]
    end
    
    # Metrics
    if analysis[:metrics] do
      metrics_text = format_metrics(analysis.metrics, config)
      sections = [metrics_text | sections]
    end
    
    # Suggestions
    if analysis[:suggestions] do
      suggestions_text = format_suggestions(analysis.suggestions, config)
      sections = [suggestions_text | sections]
    end
    
    # Word count and complexity
    details = []
    if analysis[:word_count], do: details = ["#{analysis.word_count} words" | details]
    if analysis[:complexity], do: details = ["#{analysis.complexity} complexity" | details]
    
    if not Enum.empty?(details) do
      details_text = colorize("Details: #{Enum.join(details, ", ")}", :dim, config)
      sections = [details_text | sections]
    end
    
    Enum.reverse(sections) |> Enum.join("\n\n")
  end

  defp format_session_response(response, config) do
    case response.data do
      %{sessions: sessions} -> format_sessions_list(sessions, config)
      %{session: session} -> format_session_info(session, config)
      %{deleted: session_id} -> 
        colorize("✓ Session '#{session_id}' deleted", :green, config)
      data -> 
        inspect(data, pretty: true)
    end
  end

  defp format_config_response(response, config) do
    case response.data do
      %{config: config_data} -> format_config_display(config_data, config)
      %{updated: changes} -> 
        updated_keys = Map.keys(changes) |> Enum.join(", ")
        colorize("✓ Configuration updated: #{updated_keys}", :green, config)
      data -> 
        inspect(data, pretty: true)
    end
  end

  defp format_help_response(response, config) do
    help_content = response.data.help || "No help available"
    
    # Apply basic formatting to help text
    help_content
    |> String.replace(~r/^(USAGE:|EXAMPLES:|OPTIONS:)/m, fn match ->
      colorize(match, :bold, config)
    end)
    |> String.replace(~r/^  ([a-z_\.]+)/m, fn _, command ->
      "  " <> colorize(command, :cyan, config)
    end)
  end

  defp format_status_response(response, config) do
    status = response.data
    
    # Health status with colored indicator
    health_indicator = case status.health do
      :healthy -> colorize("●", :green, config)
      :degraded -> colorize("●", :yellow, config)
      :unhealthy -> colorize("●", :red, config)
      _ -> colorize("●", :dim, config)
    end
    
    # Format uptime
    uptime_ms = status.uptime || 0
    uptime_str = format_duration(uptime_ms)
    
    lines = [
      "#{health_indicator} RubberDuck CLI Status",
      "",
      "Health: #{status.health}",
      "Uptime: #{uptime_str}",
      "Sessions: #{status.sessions}",
      "Requests processed: #{status.requests_processed}",
      "Errors: #{status.errors}"
    ]
    
    # Add current session if available
    if status.current_session do
      lines = lines ++ ["Current session: #{status.current_session}"]
    end
    
    # Add configuration info
    if status.config do
      config_info = [
        "Colors: #{status.config.colors_enabled}",
        "Syntax highlighting: #{status.config.syntax_highlighting}",
        "Format: #{status.config.format}"
      ]
      lines = lines ++ [""] ++ config_info
    end
    
    Enum.join(lines, "\n")
  end

  defp format_version_response(response, config) do
    version = response.data.version || "unknown"
    colorize("RubberDuck CLI v#{version}", :cyan, config)
  end

  defp format_generic_response(response, config) do
    # Try to format common data structures nicely
    case response.data do
      %{message: message} when is_binary(message) -> message
      %{content: content} when is_binary(content) -> content
      %{result: result} -> inspect(result, pretty: true)
      data when is_binary(data) -> data
      data -> inspect(data, pretty: true, limit: :infinity)
    end
  end

  # Helper formatting functions

  defp format_message_with_code_blocks(message, config) do
    # Split on code block markers
    parts = String.split(message, ~r/```(\w+)?\n?/, include_captures: true)
    
    {formatted_parts, _in_code} = Enum.reduce(parts, {[], false}, fn part, {acc, in_code} ->
      cond do
        String.starts_with?(part, "```") ->
          # Extract language from marker
          language = part |> String.trim_leading("```") |> String.trim()
          {acc, not in_code}
          
        in_code ->
          # Apply syntax highlighting
          highlighted = highlight_code(part, nil, config)
          {[highlighted | acc], in_code}
          
        true ->
          # Regular text
          {[part | acc], in_code}
      end
    end)
    
    formatted_parts |> Enum.reverse() |> Enum.join("")
  end

  defp format_sessions_list(sessions, config) do
    if Enum.empty?(sessions) do
      colorize("No sessions found", :dim, config)
    else
      headers = ["ID", "Name", "Created", "Last Updated"]
      
      rows = Enum.map(sessions, fn session ->
        [
          session.id,
          session.name || "-",
          format_timestamp(session.created_at),
          format_timestamp(session.updated_at)
        ]
      end)
      
      format_table(headers, rows, config)
    end
  end

  defp format_session_info(session, config) do
    [
      colorize("Session Information", :bold, config),
      "",
      "ID: #{session.id}",
      "Name: #{session.name || "unnamed"}",
      "Created: #{format_timestamp(session.created_at)}",
      "Updated: #{format_timestamp(session.updated_at)}"
    ] |> Enum.join("\n")
  end

  defp format_config_display(config_data, config) do
    # Group configuration by categories
    categorized = categorize_config(config_data)
    
    sections = Enum.map(categorized, fn {category, settings} ->
      header = colorize("#{String.capitalize(category)}:", :bold, config)
      setting_lines = Enum.map(settings, fn {key, value} ->
        "  #{key}: #{format_config_value(value, config)}"
      end)
      
      [header | setting_lines] |> Enum.join("\n")
    end)
    
    Enum.join(sections, "\n\n")
  end

  defp format_metrics(metrics, config) when is_map(metrics) do
    metric_lines = Enum.map(metrics, fn {key, value} ->
      formatted_key = key |> to_string() |> String.replace("_", " ") |> String.capitalize()
      formatted_value = case value do
        val when is_float(val) -> Float.round(val, 3)
        val -> val
      end
      "#{formatted_key}: #{formatted_value}"
    end)
    
    colorize("Metrics:", :bold, config) <> "\n" <> Enum.join(metric_lines, "\n")
  end

  defp format_suggestions(suggestions, config) when is_list(suggestions) do
    if Enum.empty?(suggestions) do
      ""
    else
      header = colorize("Suggestions:", :bold, config)
      suggestion_lines = Enum.with_index(suggestions, 1)
      |> Enum.map(fn {suggestion, index} ->
        "  #{index}. #{suggestion}"
      end)
      
      [header | suggestion_lines] |> Enum.join("\n")
    end
  end

  # Stream formatting functions

  defp format_stream_start(chunk, config) do
    message = chunk[:message] || "Starting..."
    colorize("⟳ #{message}", :cyan, config)
  end

  defp format_stream_data(chunk, config) do
    case chunk do
      %{content: content} -> content
      %{message: message} -> message
      content when is_binary(content) -> content
      _ -> ""
    end
  end

  defp format_stream_end(chunk, config) do
    message = chunk[:message] || "Complete"
    colorize("✓ #{message}", :green, config)
  end

  defp format_stream_error(chunk, config) do
    message = chunk[:message] || "Stream error"
    colorize("✗ #{message}", :red, config)
  end

  # Table formatting helpers

  defp calculate_column_widths(headers, rows) do
    all_rows = [headers | rows]
    
    Enum.reduce(all_rows, [], fn row, acc ->
      row
      |> Enum.with_index()
      |> Enum.map(fn {cell, index} ->
        cell_width = String.length(to_string(cell))
        current_width = Enum.at(acc, index, 0)
        max(cell_width, current_width)
      end)
    end)
  end

  defp format_table_row(row, max_widths, config) do
    row
    |> Enum.with_index()
    |> Enum.map(fn {cell, index} ->
      width = Enum.at(max_widths, index, 0)
      String.pad_trailing(to_string(cell), width)
    end)
    |> Enum.join(" | ")
  end

  defp create_table_separator(max_widths, _config) do
    max_widths
    |> Enum.map(&String.duplicate("-", &1))
    |> Enum.join("-+-")
  end

  # Syntax highlighting

  defp detect_language(code) do
    cond do
      String.contains?(code, "defmodule") or String.contains?(code, "def ") -> :elixir
      String.contains?(code, "def ") and String.contains?(code, ":") -> :python
      String.contains?(code, "function ") or String.contains?(code, "=>") -> :javascript
      String.contains?(code, "#include") or String.contains?(code, "int main") -> :c
      String.contains?(code, "public class") or String.contains?(code, "import java") -> :java
      true -> :text
    end
  end

  defp apply_syntax_highlighting(code, language, config) do
    patterns = Map.get(@syntax_patterns, language, [])
    
    Enum.reduce(patterns, code, fn {regex, token_type}, acc ->
      String.replace(acc, regex, fn match ->
        color = get_token_color(token_type)
        colorize(match, color, config)
      end)
    end)
  end

  defp get_token_color(token_type) do
    case token_type do
      :keyword -> :blue
      :control -> :magenta
      :constant -> :cyan
      :string -> :green
      :comment -> :dim
      :atom -> :yellow
      :attribute -> :cyan
      :number -> :cyan
      _ -> :white
    end
  end

  # Color and formatting utilities

  defp colorize(text, color, config) do
    if config[:colors] != false and color != :reset do
      color_code = Map.get(@colors, color, @colors.reset)
      "#{color_code}#{text}#{@colors.reset}"
    else
      text
    end
  end

  defp get_spinner_frame do
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    index = rem(System.monotonic_time(:millisecond), length(frames))
    Enum.at(frames, index)
  end

  # Utility functions

  defp format_timestamp(datetime) when is_struct(datetime, DateTime) do
    DateTime.to_string(datetime) |> String.slice(0, 19)
  end
  defp format_timestamp(timestamp) when is_binary(timestamp), do: timestamp
  defp format_timestamp(_), do: "unknown"

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      ms < 3_600_000 -> "#{div(ms, 60_000)}m #{rem(div(ms, 1000), 60)}s"
      true -> "#{div(ms, 3_600_000)}h #{rem(div(ms, 60_000), 60)}m"
    end
  end
  defp format_duration(_), do: "unknown"

  defp format_config_value(value, config) do
    case value do
      val when is_boolean(val) -> 
        color = if val, do: :green, else: :red
        colorize(to_string(val), color, config)
      val when is_binary(val) -> 
        colorize("\"#{val}\"", :cyan, config)
      val when is_number(val) -> 
        colorize(to_string(val), :yellow, config)
      val -> 
        inspect(val)
    end
  end

  defp categorize_config(config_data) do
    # Group configuration keys by category
    Enum.group_by(config_data, fn {key, _value} ->
      key_str = to_string(key)
      cond do
        String.contains?(key_str, "color") -> "display"
        String.contains?(key_str, "format") -> "display"
        String.contains?(key_str, "prompt") -> "interface"
        String.contains?(key_str, "model") -> "ai"
        String.contains?(key_str, "session") -> "session"
        true -> "general"
      end
    end)
  end
end