defmodule RubberDuck.CLIClient.Formatter do
  @moduledoc """
  Output formatting for CLI client responses.
  """

  @doc """
  Format output based on the specified format.
  """
  def format(output, format) do
    case format do
      :json -> format_json(output)
      :plain -> format_plain(output)
      :table -> format_table(output)
      _ -> format_plain(output)
    end
  end

  defp format_json(output) do
    case Jason.encode(output, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(output, pretty: true)
    end
  end

  defp format_plain(output) when is_binary(output), do: output
  
  defp format_plain(output) when is_map(output) do
    case output do
      %{type: :llm_status, providers: providers} ->
        format_llm_status(providers)
        
      %{type: :analysis_result, issues: issues} ->
        format_analysis_result(issues)
        
      %{type: :generation_result, code: code} ->
        format_generation_result(code)
        
      %{type: :completion_result, suggestions: suggestions} ->
        format_completion_result(suggestions)
        
      %{type: :refactor_result, changes: changes} ->
        format_refactor_result(changes)
        
      %{type: :test_result, tests: tests} ->
        format_test_result(tests)
        
      %{type: :health_status} = health ->
        format_health_status(health)
        
      %{message: message} ->
        message
        
      _ ->
        inspect(output, pretty: true)
    end
  end
  
  defp format_plain(output), do: inspect(output, pretty: true)

  defp format_table(output) when is_map(output) do
    case output do
      %{type: :llm_status, providers: providers} ->
        format_llm_status_table(providers)
        
      %{type: :health_status} = health ->
        format_health_status_table(health)
        
      _ ->
        # Fall back to plain format for non-tabular data
        format_plain(output)
    end
  end
  
  defp format_table(output), do: format_plain(output)

  # LLM status formatting
  defp format_llm_status(providers) do
    lines = ["LLM Provider Status:"]
    
    provider_lines = for provider <- providers do
      status_icon = if provider.status == "connected", do: "✓", else: "✗"
      health_icon = case provider.health do
        "healthy" -> "●"
        "unknown" -> "?"
        _ -> "!"
      end
      
      [
        "\n#{status_icon} #{provider.name}",
        "  Status: #{provider.status}",
        "  Health: #{health_icon} #{provider.health}",
        "  Enabled: #{provider.enabled}",
        "  Last used: #{provider.last_used}",
        "  Errors: #{provider.errors}"
      ]
    end
    
    all_lines = lines ++ List.flatten(provider_lines)
    Enum.join(all_lines, "\n")
  end

  defp format_llm_status_table(providers) do
    headers = ["Provider", "Status", "Health", "Enabled", "Last Used", "Errors"]
    
    rows = for provider <- providers do
      [
        to_string(provider.name),
        provider.status,
        provider.health,
        to_string(provider.enabled),
        provider.last_used,
        to_string(provider.errors)
      ]
    end
    
    RubberDuck.CLIClient.TableFormatter.format(headers, rows)
  end

  # Analysis result formatting
  defp format_analysis_result(issues) do
    if Enum.empty?(issues) do
      "No issues found."
    else
      lines = ["Analysis Results:"]
      
      grouped = Enum.group_by(issues, & &1.severity)
      
      severity_sections = for {severity, severity_issues} <- grouped do
        header = "\n#{String.upcase(to_string(severity))} (#{length(severity_issues)}):"
        
        issue_lines = for issue <- severity_issues do
          [
            "  #{issue.file}:#{issue.line}:#{issue.column}",
            "  #{issue.message}",
            ""
          ]
        end
        
        [header | List.flatten(issue_lines)]
      end
      
      all_lines = lines ++ List.flatten(severity_sections)
      Enum.join(all_lines, "\n")
    end
  end

  # Generation result formatting
  defp format_generation_result(code) do
    """
    Generated Code:
    ================
    #{code}
    ================
    """
  end

  # Completion result formatting  
  defp format_completion_result(suggestions) do
    if Enum.empty?(suggestions) do
      "No completions available."
    else
      lines = ["Code Completions:"]
      
      suggestion_lines = for {suggestion, index} <- Enum.with_index(suggestions, 1) do
        [
          "\n#{index}. #{suggestion.label}",
          "   #{suggestion.detail || ""}",
          "   Insert: #{suggestion.insert_text}"
        ]
      end
      
      all_lines = lines ++ List.flatten(suggestion_lines)
      Enum.join(all_lines, "\n")
    end
  end

  # Refactor result formatting
  defp format_refactor_result(changes) do
    if Enum.empty?(changes) do
      "No changes suggested."
    else
      lines = ["Refactoring Changes:"]
      
      change_lines = for change <- changes do
        [
          "\n#{change.file}:",
          "  Line #{change.start_line}-#{change.end_line}",
          "  #{change.description}",
          "\n  Before:",
          indent(change.before, 4),
          "\n  After:",
          indent(change.after, 4)
        ]
      end
      
      all_lines = lines ++ List.flatten(change_lines)
      Enum.join(all_lines, "\n")
    end
  end

  # Test result formatting
  defp format_test_result(tests) do
    """
    Generated Tests:
    ================
    #{tests}
    ================
    """
  end

  # Health status formatting
  defp format_health_status(health) do
    lines = [
      "Server Health Status:",
      "",
      "Status: #{health.status}",
      "Server Time: #{health.server_time}",
      "Uptime: #{health.uptime}",
      "",
      "Memory Usage:",
      "  Total: #{health.memory.total_mb} MB",
      "  Processes: #{health.memory.processes_mb} MB",
      "  ETS Tables: #{health.memory.ets_mb} MB",
      "  Binaries: #{health.memory.binary_mb} MB", 
      "  System: #{health.memory.system_mb} MB",
      "",
      "Connections:",
      "  Active WebSocket Connections: #{health.connections["active_connections"]}",
      "  Total Channels: #{health.connections["total_channels"]}",
      "",
      "Provider Health:"
    ]
    
    provider_lines = for provider <- health.providers do
      health_icon = case provider.health do
        "healthy" -> "●"
        "unknown" -> "?"
        _ -> "!"
      end
      
      "  #{provider.name}: #{health_icon} #{provider.health} (#{provider.status})"
    end
    
    lines = lines ++ provider_lines
    
    Enum.join(lines, "\n")
  end

  defp format_health_status_table(health) do
    # Main health info
    main_info = """
    Server Health: #{health.status}
    Server Time: #{health.server_time}
    Uptime: #{health.uptime}
    
    """
    
    # Memory table
    memory_headers = ["Component", "Usage (MB)"]
    memory_rows = [
      ["Total", to_string(health.memory.total_mb)],
      ["Processes", to_string(health.memory.processes_mb)],
      ["ETS Tables", to_string(health.memory.ets_mb)],
      ["Binaries", to_string(health.memory.binary_mb)],
      ["System", to_string(health.memory.system_mb)]
    ]
    memory_table = RubberDuck.CLIClient.TableFormatter.format(memory_headers, memory_rows)
    
    # Provider table
    provider_headers = ["Provider", "Status", "Health"]
    provider_rows = for provider <- health.providers do
      [
        to_string(provider.name),
        provider.status,
        provider.health
      ]
    end
    provider_table = RubberDuck.CLIClient.TableFormatter.format(provider_headers, provider_rows)
    
    """
    #{main_info}
    Memory Usage:
    #{memory_table}
    
    Connections: #{health.connections["active_connections"]} active, #{health.connections["total_channels"]} channels
    
    Provider Health:
    #{provider_table}
    """
  end

  defp indent(text, spaces) do
    padding = String.duplicate(" ", spaces)
    
    text
    |> String.split("\n")
    |> Enum.map(&"#{padding}#{&1}")
    |> Enum.join("\n")
  end
end

defmodule RubberDuck.CLIClient.TableFormatter do
  @moduledoc false
  
  def format(headers, rows) do
    # Calculate column widths
    widths = calculate_widths(headers, rows)
    
    # Format header
    header_line = format_row(headers, widths)
    separator = format_separator(widths)
    
    # Format rows
    row_lines = Enum.map(rows, &format_row(&1, widths))
    
    # Combine all parts
    [header_line, separator | row_lines]
    |> Enum.join("\n")
  end
  
  defp calculate_widths(headers, rows) do
    header_widths = Enum.map(headers, &String.length/1)
    
    row_widths = rows
    |> Enum.map(fn row ->
      Enum.map(row, &String.length/1)
    end)
    |> Enum.reduce(header_widths, fn row_width, acc ->
      Enum.zip(acc, row_width)
      |> Enum.map(fn {a, b} -> max(a, b) end)
    end)
    
    row_widths
  end
  
  defp format_row(cells, widths) do
    cells
    |> Enum.zip(widths)
    |> Enum.map(fn {cell, width} ->
      String.pad_trailing(cell, width)
    end)
    |> Enum.join(" | ")
    |> (fn row -> "| #{row} |" end).()
  end
  
  defp format_separator(widths) do
    widths
    |> Enum.map(&String.duplicate("-", &1))
    |> Enum.join("-+-")
    |> (fn sep -> "+-#{sep}-+" end).()
  end
end