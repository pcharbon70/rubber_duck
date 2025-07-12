defmodule RubberDuck.Commands.Formatters do
  @moduledoc """
  Command result formatters for different output formats and client types.
  
  Provides formatters to convert command results into client-appropriate formats
  such as JSON, text, tables, and markdown for different client types.
  """

  @doc """
  Returns a map of formatters keyed by format or {format, client_type} tuples.
  """
  def load_formatters do
    %{
      # JSON formatters for all client types
      :json => __MODULE__.JSONFormatter,
      {:json, :cli} => __MODULE__.JSONFormatter,
      {:json, :websocket} => __MODULE__.JSONFormatter,
      {:json, :liveview} => __MODULE__.JSONFormatter,
      {:json, :tui} => __MODULE__.JSONFormatter,
      
      # Text formatters
      :text => __MODULE__.TextFormatter,
      {:text, :cli} => __MODULE__.TextFormatter,
      {:text, :tui} => __MODULE__.TextFormatter,
      
      # Table formatters (primarily for CLI)
      :table => __MODULE__.TableFormatter,
      {:table, :cli} => __MODULE__.TableFormatter,
      
      # Markdown formatters
      :markdown => __MODULE__.MarkdownFormatter,
      {:markdown, :cli} => __MODULE__.MarkdownFormatter,
      {:markdown, :liveview} => __MODULE__.MarkdownFormatter
    }
  end

  defmodule JSONFormatter do
    @moduledoc """
    Formats command results as JSON.
    """

    def format(result) when is_map(result) do
      case Jason.encode(result, pretty: true) do
        {:ok, json} -> json
        {:error, reason} -> 
          fallback_json = %{
            error: "JSON encoding failed",
            reason: inspect(reason),
            raw_result: inspect(result)
          }
          Jason.encode!(fallback_json, pretty: true)
      end
    end

    def format(result) do
      result
      |> wrap_in_map()
      |> format()
    end

    defp wrap_in_map(result) when is_binary(result), do: %{message: result}
    defp wrap_in_map(result) when is_list(result), do: %{items: result}
    defp wrap_in_map(result), do: %{result: result}
  end

  defmodule TextFormatter do
    @moduledoc """
    Formats command results as human-readable text.
    """

    def format(%{type: "health"} = result) do
      status = Map.get(result, :status, "unknown")
      uptime = Map.get(result, :uptime, 0)
      
      """
      Health Status: #{status}
      Uptime: #{format_uptime(uptime)}ms
      Memory: #{format_memory(result[:memory])}
      Services: #{format_services(result[:services])}
      """
    end

    def format(%{type: "analysis_results"} = result) do
      file_count = Map.get(result, :file_count, 0)
      
      """
      Analysis Complete
      Files analyzed: #{file_count}
      Timestamp: #{format_time(result[:timestamp])}
      """
    end

    def format(%{type: "test_generation"} = result) do
      framework = Map.get(result, :framework, "unknown")
      message = Map.get(result, :message, "Tests generated")
      
      """
      #{message}
      Framework: #{framework}
      #{if result[:output_file], do: "Saved to: #{result.output_file}", else: "Suggested path: #{result[:suggested_path]}"}
      """
    end

    def format(%{type: "refactor"} = result) do
      """
      #{Map.get(result, :message, "Refactoring completed")}
      File: #{Map.get(result, :original_file, "unknown")}
      Dry run: #{Map.get(result, :dry_run, false)}
      """
    end

    def format(%{type: "llm_status"} = result) do
      summary = result[:summary] || %{}
      
      """
      LLM Status Summary
      Total providers: #{Map.get(summary, :total, 0)}
      Connected: #{Map.get(summary, :connected, 0)}
      Healthy: #{Map.get(summary, :healthy, 0)}
      """
    end

    def format(%{completions: completions} = result) when is_list(completions) do
      count = length(completions)
      
      """
      Code Completions (#{count} suggestions)
      File: #{Map.get(result, :file, "unknown")}
      Position: #{Map.get(result, :line, "?")}:#{Map.get(result, :column, "?")}
      """
    end

    def format(%{generated_code: code} = result) do
      language = Map.get(result, :language, "unknown")
      description = Map.get(result, :description, "Generated code")
      
      """
      Generated #{language} code
      Description: #{description}
      
      #{code}
      """
    end

    def format(result) when is_binary(result) do
      result
    end

    def format(result) when is_map(result) do
      message = Map.get(result, :message) || Map.get(result, "message")
      if message do
        message
      else
        inspect(result, pretty: true)
      end
    end

    def format(result) do
      inspect(result, pretty: true)
    end

    # Helper functions
    defp format_uptime(uptime) when is_integer(uptime) do
      seconds = div(uptime, 1000)
      minutes = div(seconds, 60)
      hours = div(minutes, 60)
      
      cond do
        hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
        minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
        true -> "#{seconds}s"
      end
    end
    defp format_uptime(_), do: "unknown"

    defp format_memory(nil), do: "unknown"
    defp format_memory(memory) when is_map(memory) do
      total = Map.get(memory, :total, 0)
      "#{format_bytes(total)} total"
    end

    defp format_services(nil), do: "unknown"
    defp format_services(services) when is_map(services) do
      services
      |> Enum.map(fn {name, status} -> "#{name}: #{status}" end)
      |> Enum.join(", ")
    end

    defp format_bytes(bytes) when is_integer(bytes) do
      cond do
        bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)}GB"
        bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
        bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
        true -> "#{bytes}B"
      end
    end
    defp format_bytes(_), do: "unknown"

    defp format_time(nil), do: "unknown"
    defp format_time(%DateTime{} = time) do
      DateTime.to_string(time)
    end
    defp format_time(_), do: "unknown"
  end

  defmodule TableFormatter do
    @moduledoc """
    Formats command results as ASCII tables.
    """

    def format(%{type: "llm_status", providers: providers} = _result) when is_list(providers) do
      headers = ["Name", "Status", "Enabled", "Health", "Errors"]
      
      rows = Enum.map(providers, fn provider ->
        [
          to_string(provider.name),
          provider.status,
          to_string(provider.enabled),
          provider.health,
          to_string(provider.errors)
        ]
      end)
      
      format_table(headers, rows)
    end

    def format(%{completions: completions} = _result) when is_list(completions) do
      headers = ["Rank", "Text", "Score"]
      
      rows = Enum.map(completions, fn completion ->
        [
          to_string(Map.get(completion, :rank, "?")),
          String.slice(Map.get(completion, :text, ""), 0, 50),
          Float.to_string(Map.get(completion, :score, 0.0))
        ]
      end)
      
      format_table(headers, rows)
    end

    def format(%{analysis_results: results} = _result) when is_list(results) do
      headers = ["File", "Issues", "Lines", "Complexity"]
      
      rows = Enum.map(results, fn result ->
        metrics = Map.get(result, :metrics, %{})
        issues = Map.get(result, :issues, [])
        
        [
          Path.basename(Map.get(result, :file, "unknown")),
          to_string(length(issues)),
          to_string(Map.get(metrics, :lines, 0)),
          to_string(Map.get(metrics, :complexity, 0))
        ]
      end)
      
      format_table(headers, rows)
    end

    def format(result) do
      # Fallback to text formatting for non-tabular data
      TextFormatter.format(result)
    end

    defp format_table(headers, rows) do
      # Calculate column widths
      all_rows = [headers | rows]
      widths = 
        0..(length(headers) - 1)
        |> Enum.map(fn col_idx ->
          all_rows
          |> Enum.map(&Enum.at(&1, col_idx, ""))
          |> Enum.map(&String.length/1)
          |> Enum.max()
        end)
      
      # Format header
      header_line = format_row(headers, widths)
      separator = format_separator(widths)
      
      # Format data rows
      data_lines = Enum.map(rows, &format_row(&1, widths))
      
      [header_line, separator | data_lines]
      |> Enum.join("\n")
    end

    defp format_row(row, widths) do
      row
      |> Enum.zip(widths)
      |> Enum.map(fn {cell, width} -> String.pad_trailing(to_string(cell), width) end)
      |> Enum.join(" | ")
      |> (&("| #{&1} |")).()
    end

    defp format_separator(widths) do
      widths
      |> Enum.map(&String.duplicate("-", &1))
      |> Enum.join("-+-")
      |> (&("+-#{&1}-+")).()
    end
  end

  defmodule MarkdownFormatter do
    @moduledoc """
    Formats command results as Markdown.
    """

    def format(%{type: "health"} = result) do
      status = Map.get(result, :status, "unknown")
      
      """
      # System Health

      **Status:** #{status}  
      **Uptime:** #{format_uptime(result[:uptime])}  
      **Timestamp:** #{format_time(result[:timestamp])}  

      ## Memory Usage
      #{format_memory_markdown(result[:memory])}

      ## Services
      #{format_services_markdown(result[:services])}
      """
    end

    def format(%{generated_code: code} = result) do
      language = Map.get(result, :language, "text")
      description = Map.get(result, :description, "Generated code")
      
      """
      # Generated Code

      **Description:** #{description}  
      **Language:** #{language}  
      **Generated:** #{format_time(result[:timestamp])}  

      ```#{language}
      #{code}
      ```
      """
    end

    def format(%{type: "test_generation", tests: tests} = result) do
      framework = Map.get(result, :framework, "unknown")
      
      """
      # Generated Tests

      **Framework:** #{framework}  
      **Generated:** #{format_time(result[:timestamp])}  
      #{if result[:output_file], do: "**Saved to:** `#{result.output_file}`", else: "**Suggested path:** `#{result[:suggested_path]}`"}

      ```elixir
      #{tests}
      ```
      """
    end

    def format(%{type: "refactor"} = result) do
      file = Map.get(result, :original_file, "unknown")
      dry_run = Map.get(result, :dry_run, false)
      
      """
      # Code Refactoring

      **File:** `#{file}`  
      **Dry Run:** #{dry_run}  
      **Completed:** #{format_time(result[:timestamp])}  
      **Status:** #{Map.get(result, :message, "Completed")}

      #{if not dry_run and result[:refactored_code] do
        """
        ## Refactored Code

        ```elixir
        #{result.refactored_code}
        ```
        """
      else
        ""
      end}
      """
    end

    def format(result) do
      # Fallback to text formatting with code blocks
      text_result = TextFormatter.format(result)
      
      """
      # Command Result

      ```
      #{text_result}
      ```
      """
    end

    # Helper functions
    defp format_uptime(uptime) when is_integer(uptime) do
      seconds = div(uptime, 1000)
      minutes = div(seconds, 60)
      hours = div(minutes, 60)
      
      cond do
        hours > 0 -> "#{hours}h #{rem(minutes, 60)}m"
        minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
        true -> "#{seconds}s"
      end
    end
    defp format_uptime(_), do: "unknown"

    defp format_time(nil), do: "unknown"
    defp format_time(%DateTime{} = time) do
      DateTime.to_string(time)
    end
    defp format_time(_), do: "unknown"

    defp format_memory_markdown(nil), do: "_No memory information available_"
    defp format_memory_markdown(memory) when is_map(memory) do
      memory
      |> Enum.map(fn {key, value} -> "- **#{key}:** #{format_bytes(value)}" end)
      |> Enum.join("\n")
    end

    defp format_services_markdown(nil), do: "_No service information available_"
    defp format_services_markdown(services) when is_map(services) do
      services
      |> Enum.map(fn {name, status} -> "- **#{name}:** #{status}" end)
      |> Enum.join("\n")
    end

    defp format_bytes(bytes) when is_integer(bytes) do
      cond do
        bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)}GB"
        bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
        bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
        true -> "#{bytes}B"
      end
    end
    defp format_bytes(_), do: "unknown"
  end
end