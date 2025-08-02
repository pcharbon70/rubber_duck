defmodule RubberDuck.Tools.Agents.CodeFormatterAgent do
  @moduledoc """
  Agent that orchestrates the CodeFormatter tool for consistent Elixir code formatting.
  
  This agent manages code formatting requests, maintains formatting configurations,
  handles batch formatting operations, and provides intelligent formatting workflows.
  
  ## Signals
  
  ### Input Signals
  - `format_code` - Format individual code snippets or files
  - `format_project` - Format entire project with configuration
  - `validate_formatting` - Check if code follows formatting rules
  - `batch_format` - Format multiple files or code snippets
  - `save_format_config` - Save custom formatting configuration
  - `analyze_formatting` - Analyze formatting issues in code
  
  ### Output Signals
  - `code.formatted` - Successfully formatted code
  - `code.format.validated` - Code formatting validation results
  - `code.format.batch.completed` - Batch formatting completed
  - `code.format.analyzed` - Formatting analysis results
  - `code.format.config.saved` - Configuration saved
  - `code.format.error` - Formatting error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_formatter,
    name: "code_formatter_agent",
    description: "Manages Elixir code formatting workflows",
    category: "code_quality",
    tags: ["formatting", "style", "quality", "consistency"],
    schema: [
      # Formatting configurations
      format_configs: [type: :map, default: %{}],
      active_config: [type: {:nullable, :string}, default: nil],
      
      # Project formatting
      project_configs: [type: :map, default: %{}],
      
      # Batch operations tracking
      batch_operations: [type: :map, default: %{}],
      
      # Formatting preferences
      default_line_length: [type: :integer, default: 98],
      default_force_do_end: [type: :boolean, default: false],
      default_normalize_charlists: [type: :boolean, default: true],
      
      # Analysis and statistics
      format_stats: [type: :map, default: %{
        total_formatted: 0,
        files_formatted: 0,
        lines_formatted: 0,
        issues_fixed: %{}
      }],
      
      # Formatting history
      format_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "format_code"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters with agent preferences
    params = %{
      code: data["code"],
      line_length: data["line_length"] || agent.state.default_line_length,
      locals_without_parens: data["locals_without_parens"] || [],
      force_do_end_blocks: data["force_do_end"] || agent.state.default_force_do_end,
      normalize_bitstring_modifiers: data["normalize_bitstring"] || true,
      normalize_charlists: data["normalize_charlists"] || agent.state.default_normalize_charlists,
      check_equivalent: data["check_equivalent"] || true,
      file_path: data["file_path"],
      use_project_formatter: data["use_project_formatter"] || true
    }
    
    # Apply saved configuration if specified
    params = if config_name = data["config"] do
      apply_saved_config(params, agent.state.format_configs[config_name])
    else
      params
    end
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "file_path" => data["file_path"],
          "config_used" => data["config"],
          "user_id" => data["user_id"]
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "code.format.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "formatting",
        file_path: data["file_path"]
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Store formatting metadata
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:format_metadata],
      %{
        original_code: data["code"],
        config_used: data["config"],
        started_at: DateTime.utc_now()
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "format_project"} = signal) do
    %{"data" => data} = signal
    project_path = data["project_path"] || File.cwd!()
    
    # Discover Elixir files in project
    files = discover_elixir_files(project_path, data["exclude_patterns"] || [])
    
    batch_id = data["batch_id"] || "project_#{System.unique_integer([:positive])}"
    
    # Create batch format request
    batch_signal = %{
      "type" => "batch_format",
      "data" => %{
        "batch_id" => batch_id,
        "files" => Enum.map(files, fn file_path ->
          %{
            "file_path" => file_path,
            "config" => data["config"]
          }
        end),
        "project_path" => project_path,
        "write_files" => data["write_files"] || false
      }
    }
    
    handle_tool_signal(agent, batch_signal)
  end
  
  def handle_tool_signal(agent, %{"type" => "validate_formatting"} = signal) do
    %{"data" => data} = signal
    
    # Format code first to compare
    format_signal = %{
      "type" => "format_code",
      "data" => Map.merge(data, %{
        "request_id" => "validate_#{data["request_id"] || generate_request_id()}",
        "check_equivalent" => true
      })
    }
    
    # This will trigger formatting and we'll compare in the result handler
    {:ok, agent} = handle_tool_signal(agent, format_signal)
    
    # Store validation metadata
    validation_id = format_signal["data"]["request_id"]
    agent = put_in(
      agent.state.active_requests[validation_id][:validation_metadata],
      %{
        original_request_id: data["request_id"],
        validation_mode: true
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "batch_format"} = signal) do
    %{"data" => data} = signal
    batch_id = data["batch_id"] || "batch_#{System.unique_integer([:positive])}"
    files_or_code = data["files"] || data["codes"] || []
    
    # Initialize batch tracking
    agent = put_in(agent.state.batch_operations[batch_id], %{
      id: batch_id,
      total: length(files_or_code),
      completed: 0,
      failed: 0,
      results: [],
      started_at: DateTime.utc_now(),
      write_files: data["write_files"] || false
    })
    
    # Process each file/code
    agent = Enum.reduce(files_or_code, agent, fn item, acc ->
      format_data = case item do
        %{"file_path" => file_path} ->
          # Read file content
          case File.read(file_path) do
            {:ok, content} ->
              %{
                "code" => content,
                "file_path" => file_path,
                "config" => item["config"],
                "batch_id" => batch_id,
                "request_id" => "#{batch_id}_#{System.unique_integer([:positive])}"
              }
            {:error, _} ->
              nil
          end
        %{"code" => code} ->
          %{
            "code" => code,
            "name" => item["name"] || "snippet",
            "config" => item["config"],
            "batch_id" => batch_id,
            "request_id" => "#{batch_id}_#{System.unique_integer([:positive])}"
          }
        _ ->
          nil
      end
      
      if format_data do
        format_signal = %{
          "type" => "format_code",
          "data" => format_data
        }
        
        case handle_tool_signal(acc, format_signal) do
          {:ok, updated_agent} -> updated_agent
          _ -> acc
        end
      else
        acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.format.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        total_items: length(files_or_code)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "save_format_config"} = signal) do
    %{"data" => data} = signal
    config_name = data["name"]
    
    config = %{
      name: config_name,
      line_length: data["line_length"] || 98,
      locals_without_parens: data["locals_without_parens"] || [],
      force_do_end_blocks: data["force_do_end"] || false,
      normalize_bitstring_modifiers: data["normalize_bitstring"] || true,
      normalize_charlists: data["normalize_charlists"] || true,
      description: data["description"] || "",
      created_at: DateTime.utc_now()
    }
    
    agent = put_in(agent.state.format_configs[config_name], config)
    
    signal = Jido.Signal.new!(%{
      type: "code.format.config.saved",
      source: "agent:#{agent.id}",
      data: %{
        name: config_name,
        config: config
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "analyze_formatting"} = signal) do
    %{"data" => data} = signal
    
    # Analyze formatting issues without actually formatting
    analysis = analyze_code_formatting(data["code"])
    
    signal = Jido.Signal.new!(%{
      type: "code.format.analyzed",
      source: "agent:#{agent.id}",
      data: %{
        code_length: String.length(data["code"]),
        line_count: length(String.split(data["code"], "\n")),
        issues: analysis.issues,
        suggestions: analysis.suggestions,
        complexity_score: analysis.complexity_score
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle formatting-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add formatting metadata
    format_metadata = request[:format_metadata] || %{}
    
    result
    |> Map.put(:formatted_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.merge(format_metadata)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %Jido.Signal{type: "tool.result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    data = signal.data
    
    if data.result && not data[:from_cache] do
      # Check if this was a validation request
      request_id = data.request_id
      validation_metadata = get_in(agent.state.active_requests, [request_id, :validation_metadata])
      
      if validation_metadata do
        # Handle validation result
        agent = handle_validation_result(agent, data.result, validation_metadata)
      else
        # Handle regular formatting result
        agent = handle_formatting_result(agent, data.result, data.request_id)
      end
      
      # Update batch if applicable
      agent = if batch_id = data.result[:batch_id] do
        update_batch_progress(agent, batch_id, data.result)
      else
        agent
      end
      
      # Add to history
      agent = add_to_format_history(agent, data.result)
      
      # Update statistics
      agent = update_format_stats(agent, data.result)
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.formatted",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data.request_id,
          formatted_code: data.result["formatted_code"],
          changed: data.result["changed"],
          analysis: data.result["analysis"],
          warnings: data.result["warnings"]
        }
      })
      emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    # Delegate to parent for standard handling
    super(agent, signal)
  end
  
  # Private helpers
  
  defp generate_request_id do
    "fmt_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp apply_saved_config(params, nil), do: params
  defp apply_saved_config(params, config) do
    %{
      params |
      line_length: config.line_length,
      locals_without_parens: config.locals_without_parens,
      force_do_end_blocks: config.force_do_end_blocks,
      normalize_bitstring_modifiers: config.normalize_bitstring_modifiers,
      normalize_charlists: config.normalize_charlists
    }
  end
  
  defp discover_elixir_files(project_path, exclude_patterns) do
    project_path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.reject(fn file ->
      Enum.any?(exclude_patterns, fn pattern ->
        String.contains?(file, pattern)
      end)
    end)
    |> Enum.filter(&File.regular?/1)
  end
  
  defp analyze_code_formatting(code) do
    lines = String.split(code, "\n")
    
    issues = []
    issues = if String.contains?(code, "\t"), do: [:tabs_detected | issues], else: issues
    issues = if Regex.match?(~r/\s+$/, code), do: [:trailing_whitespace | issues], else: issues
    
    long_lines = Enum.count(lines, &(String.length(&1) > 98))
    issues = if long_lines > 0, do: [{:long_lines, long_lines} | issues], else: issues
    
    # Calculate complexity based on nesting and line length variance
    line_lengths = Enum.map(lines, &String.length/1)
    avg_length = if length(line_lengths) > 0, do: Enum.sum(line_lengths) / length(line_lengths), else: 0
    variance = calculate_line_length_variance(line_lengths, avg_length)
    
    complexity_score = case {long_lines, variance} do
      {0, v} when v < 100 -> :low
      {l, v} when l < 5 and v < 200 -> :medium
      _ -> :high
    end
    
    suggestions = generate_formatting_suggestions(issues)
    
    %{
      issues: issues,
      suggestions: suggestions,
      complexity_score: complexity_score
    }
  end
  
  defp calculate_line_length_variance(line_lengths, avg_length) do
    if length(line_lengths) > 0 do
      variance_sum = Enum.reduce(line_lengths, 0, fn length, acc ->
        acc + :math.pow(length - avg_length, 2)
      end)
      variance_sum / length(line_lengths)
    else
      0
    end
  end
  
  defp generate_formatting_suggestions(issues) do
    Enum.flat_map(issues, fn
      :tabs_detected -> ["Replace tabs with spaces for consistent indentation"]
      :trailing_whitespace -> ["Remove trailing whitespace"]
      {:long_lines, count} -> ["Break #{count} long lines for better readability"]
      _ -> []
    end)
  end
  
  defp handle_validation_result(agent, result, validation_metadata) do
    original_code = result[:original_code] || ""
    formatted_code = result["formatted_code"] || ""
    is_formatted = original_code == formatted_code
    
    signal = Jido.Signal.new!(%{
      type: "code.format.validated",
      source: "agent:#{agent.id}",
      data: %{
        request_id: validation_metadata.original_request_id,
        is_properly_formatted: is_formatted,
        changes_needed: not is_formatted,
        analysis: result["analysis"],
        warnings: result["warnings"]
      }
    })
    emit_signal(agent, signal)
    
    agent
  end
  
  defp handle_formatting_result(agent, result, request_id) do
    # Write file if requested and file_path provided
    if result[:file_path] && result[:write_file] do
      case File.write(result.file_path, result["formatted_code"]) do
        :ok ->
          Logger.info("Formatted file written: #{result.file_path}")
        {:error, reason} ->
          Logger.error("Failed to write formatted file: #{inspect(reason)}")
      end
    end
    
    agent
  end
  
  defp update_batch_progress(agent, batch_id, result) do
    update_in(agent.state.batch_operations[batch_id], fn batch ->
      if batch do
        completed = batch.completed + 1
        failed = if result["changed"] == false && result["warnings"] != [], do: batch.failed + 1, else: batch.failed
        
        updated_batch = batch
        |> Map.put(:completed, completed)
        |> Map.put(:failed, failed)
        |> Map.update!(:results, &[result | &1])
        
        # Check if batch is complete
        if completed >= batch.total do
          signal = Jido.Signal.new!(%{
            type: "code.format.batch.completed",
            source: "agent:#{Process.self()}",
            data: %{
              batch_id: batch_id,
              total: batch.total,
              completed: completed,
              failed: failed,
              duration: DateTime.diff(DateTime.utc_now(), batch.started_at, :second)
            }
          })
          emit_signal(nil, signal)
        end
        
        updated_batch
      else
        batch
      end
    end)
  end
  
  defp add_to_format_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      file_path: result[:file_path],
      changed: result["changed"],
      lines_changed: get_in(result, ["analysis", "lines_changed"]) || 0,
      issues_fixed: get_in(result, ["analysis", "formatting_issues"]) || [],
      formatted_at: result[:formatted_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.format_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.format_history, new_history)
  end
  
  defp update_format_stats(agent, result) do
    update_in(agent.state.format_stats, fn stats ->
      issues_fixed = get_in(result, ["analysis", "formatting_issues"]) || []
      lines_changed = get_in(result, ["analysis", "lines_changed"]) || 0
      
      updated_issues = Enum.reduce(issues_fixed, stats.issues_fixed, fn issue, acc ->
        issue_key = case issue do
          atom when is_atom(atom) -> atom
          {key, _count} -> key
          _ -> :other
        end
        Map.update(acc, issue_key, 1, &(&1 + 1))
      end)
      
      stats
      |> Map.update!(:total_formatted, &(&1 + 1))
      |> Map.update!(:files_formatted, fn count ->
        if result[:file_path], do: count + 1, else: count
      end)
      |> Map.update!(:lines_formatted, &(&1 + lines_changed))
      |> Map.put(:issues_fixed, updated_issues)
    end)
  end
end