defmodule RubberDuck.Tools.Agents.CodeComparerAgent do
  @moduledoc """
  Agent for the CodeComparer tool.
  
  Handles code comparison requests with version tracking, pattern matching,
  and batch comparison operations.
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_comparer,
    name: "code_comparer_agent",
    description: "Analyzes differences between code files, functions, or implementations",
    schema: [
      # Comparison history tracking
      comparison_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 100],
      
      # Pattern analysis
      pattern_cache: [type: :map, default: %{}],
      common_patterns: [type: :map, default: %{
        refactoring: [],
        bug_fixes: [],
        feature_additions: []
      }]
    ]
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchCompareAction,
      __MODULE__.AnalyzePatternsAction,
      __MODULE__.GenerateReportAction
    ]
  end
  
  # Action modules
  defmodule BatchCompareAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_compare",
      description: "Compare multiple files or versions in batch",
      schema: [
        comparisons: [
          type: {:list, :map},
          required: true,
          doc: "List of comparison specs with file1, file2, and options"
        ],
        parallel: [type: :boolean, default: true]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      comparisons = params.comparisons
      
      results = if params.parallel do
        comparisons
        |> Task.async_stream(fn spec ->
          execute_comparison(spec, context)
        end, timeout: 30_000)
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, reason}
        end)
      else
        Enum.map(comparisons, &execute_comparison(&1, context))
      end
      
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _}, &1))
      
      {:ok, %{
        total: length(comparisons),
        successful: length(successful),
        failed: length(failed),
        results: results
      }}
    end
    
    defp execute_comparison(spec, _context) do
      Executor.execute(:code_comparer, %{
        file1: spec.file1,
        file2: spec.file2,
        options: spec[:options] || %{}
      })
    end
  end
  
  defmodule AnalyzePatternsAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_patterns",
      description: "Analyze comparison history for patterns",
      schema: [
        pattern_type: [
          type: :atom,
          values: ["refactoring", :bug_fixes, :feature_additions, :all],
          default: :all
        ],
        min_occurrences: [type: :integer, default: 2]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      history = agent.state.comparison_history
      
      patterns = case params.pattern_type do
        :all -> analyze_all_patterns(history, params.min_occurrences)
        type -> analyze_specific_pattern(history, type, params.min_occurrences)
      end
      
      {:ok, %{
        pattern_type: params.pattern_type,
        patterns_found: length(patterns),
        patterns: patterns
      }}
    end
    
    defp analyze_all_patterns(history, min_occurrences) do
      ["refactoring", :bug_fixes, :feature_additions]
      |> Enum.flat_map(&analyze_specific_pattern(history, &1, min_occurrences))
    end
    
    defp analyze_specific_pattern(history, type, min_occurrences) do
      # Group by similar changes
      history
      |> Enum.filter(&(&1[:type] == type))
      |> Enum.group_by(&change_signature/1)
      |> Enum.filter(fn {_, occurrences} -> length(occurrences) >= min_occurrences end)
      |> Enum.map(fn {signature, occurrences} ->
        %{
          type: type,
          signature: signature,
          occurrences: length(occurrences),
          examples: Enum.take(occurrences, 3)
        }
      end)
    end
    
    defp change_signature(comparison) do
      # Create a signature based on the type of changes
      changes = comparison[:changes] || []
      
      %{
        added_lines: count_change_type(changes, :added),
        removed_lines: count_change_type(changes, :removed),
        modified_functions: count_modified_functions(changes)
      }
    end
    
    defp count_change_type(changes, type) do
      Enum.count(changes, &(&1[:type] == type))
    end
    
    defp count_modified_functions(changes) do
      changes
      |> Enum.filter(&(&1[:function_name] != nil))
      |> Enum.uniq_by(&(&1[:function_name]))
      |> length()
    end
  end
  
  defmodule GenerateReportAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_report",
      description: "Generate comparison report",
      schema: [
        format: [type: :atom, values: [:text, :markdown, :json], default: :markdown],
        include_patterns: [type: :boolean, default: true],
        time_range: [type: :map, required: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      history = filter_by_time_range(agent.state.comparison_history, params[:time_range])
      patterns = if params.include_patterns, do: agent.state.common_patterns, else: %{}
      
      report = case params.format do
        :text -> generate_text_report(history, patterns)
        :markdown -> generate_markdown_report(history, patterns)
        :json -> generate_json_report(history, patterns)
      end
      
      {:ok, %{
        format: params.format,
        report: report,
        comparisons_included: length(history)
      }}
    end
    
    defp filter_by_time_range(history, nil), do: history
    defp filter_by_time_range(history, %{from: from, to: to}) do
      Enum.filter(history, fn item ->
        timestamp = item[:timestamp]
        timestamp >= from && timestamp <= to
      end)
    end
    
    defp generate_markdown_report(history, patterns) do
      """
      # Code Comparison Report
      
      ## Summary
      - Total comparisons: #{length(history)}
      - Time period: #{format_time_period(history)}
      
      ## Pattern Analysis
      #{format_patterns_markdown(patterns)}
      
      ## Recent Comparisons
      #{format_comparisons_markdown(Enum.take(history, 10))}
      """
    end
    
    defp generate_text_report(history, patterns) do
      """
      CODE COMPARISON REPORT
      
      Summary:
      - Total comparisons: #{length(history)}
      - Time period: #{format_time_period(history)}
      
      Pattern Analysis:
      #{format_patterns_text(patterns)}
      
      Recent Comparisons:
      #{format_comparisons_text(Enum.take(history, 10))}
      """
    end
    
    defp generate_json_report(history, patterns) do
      %{
        summary: %{
          total_comparisons: length(history),
          time_period: format_time_period(history)
        },
        patterns: patterns,
        recent_comparisons: Enum.take(history, 10)
      }
    end
    
    defp format_time_period([]), do: "No comparisons"
    defp format_time_period(history) do
      oldest = history |> List.last() |> Map.get(:timestamp)
      newest = history |> List.first() |> Map.get(:timestamp)
      "#{oldest} to #{newest}"
    end
    
    defp format_patterns_markdown(patterns) do
      patterns
      |> Enum.map(fn {type, items} ->
        "### #{type}\n#{Enum.map(items, &"- #{inspect(&1)}\n") |> Enum.join()}"
      end)
      |> Enum.join("\n")
    end
    
    defp format_patterns_text(patterns) do
      patterns
      |> Enum.map(fn {type, items} ->
        "#{type}:\n#{Enum.map(items, &"  - #{inspect(&1)}\n") |> Enum.join()}"
      end)
      |> Enum.join("\n")
    end
    
    defp format_comparisons_markdown(comparisons) do
      comparisons
      |> Enum.map(fn comp ->
        "- #{comp[:file1]} vs #{comp[:file2]} (#{comp[:timestamp]})"
      end)
      |> Enum.join("\n")
    end
    
    defp format_comparisons_text(comparisons) do
      comparisons
      |> Enum.map(fn comp ->
        "  #{comp[:file1]} vs #{comp[:file2]} (#{comp[:timestamp]})"
      end)
      |> Enum.join("\n")
    end
  end
  
  # Tool-specific signal handlers using the new action system
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "batch_compare"} = signal) do
    comparisons = get_in(signal, ["data", "comparisons"]) || []
    parallel = get_in(signal, ["data", "parallel"]) || true
    
    # Execute batch compare action
    {:ok, _ref} = __MODULE__.cmd_async(agent, BatchCompareAction, %{
      comparisons: comparisons,
      parallel: parallel
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "analyze_patterns"} = signal) do
    pattern_type = get_in(signal, ["data", "pattern_type"]) || :all
    min_occurrences = get_in(signal, ["data", "min_occurrences"]) || 2
    
    # Execute pattern analysis action
    {:ok, _ref} = __MODULE__.cmd_async(agent, AnalyzePatternsAction, %{
      pattern_type: pattern_type,
      min_occurrences: min_occurrences
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_report"} = signal) do
    format = get_in(signal, ["data", "format"]) || :markdown
    include_patterns = get_in(signal, ["data", "include_patterns"]) || true
    time_range = get_in(signal, ["data", "time_range"])
    
    # Execute report generation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, GenerateReportAction, %{
      format: format,
      include_patterns: include_patterns,
      time_range: time_range
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, _signal), do: super(agent, _signal)
  
  # Process comparison results to track history and patterns
  @impl true
  def process_result(result, _context) do
    # Add timestamp to result
    Map.put(result, :timestamp, DateTime.utc_now())
  end
  
  # Override action result handler to update history
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Let parent handle the standard processing
    {:ok, agent} = super(agent, ExecuteToolAction, {:ok, result}, metadata)
    
    # Update comparison history
    if result[:from_cache] == false do
      comparison_record = %{
        file1: get_in(result, [:result, :file1]),
        file2: get_in(result, [:result, :file2]),
        changes: get_in(result, [:result, :changes]),
        timestamp: result[:result][:timestamp] || DateTime.utc_now(),
        type: classify_comparison(result[:result])
      }
      
      agent = update_in(agent.state.comparison_history, fn history ->
        [comparison_record | history]
        |> Enum.take(agent.state.max_history)
      end)
      
      # Update pattern detection
      agent = detect_and_update_patterns(agent, comparison_record)
    end
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, action, result, metadata) do
    # Let parent handle other actions
    super(agent, action, result, metadata)
  end
  
  # Helper functions
  
  defp classify_comparison(result) do
    changes = result[:changes] || []
    
    cond do
      mostly_refactoring?(changes) -> "refactoring"
      contains_bug_fix_patterns?(changes) -> :bug_fixes
      mostly_additions?(changes) -> :feature_additions
      true -> :other
    end
  end
  
  defp mostly_refactoring?(changes) do
    # Heuristic: similar amount of additions and deletions
    added = Enum.count(changes, &(&1[:type] == :added))
    removed = Enum.count(changes, &(&1[:type] == :removed))
    
    added > 0 && removed > 0 && abs(added - removed) < max(added, removed) * 0.3
  end
  
  defp contains_bug_fix_patterns?(changes) do
    # Look for common bug fix patterns in change descriptions
    bug_keywords = ~w(fix bug error exception nil null crash)
    
    Enum.any?(changes, fn change ->
      description = change[:description] || ""
      Enum.any?(bug_keywords, &String.contains?(String.downcase(description), &1))
    end)
  end
  
  defp mostly_additions?(changes) do
    added = Enum.count(changes, &(&1[:type] == :added))
    total = length(changes)
    
    total > 0 && added / total > 0.7
  end
  
  defp detect_and_update_patterns(agent, comparison) do
    type = comparison[:type]
    
    if type in ["refactoring", :bug_fixes, :feature_additions] do
      update_in(agent.state.common_patterns[type], fn patterns ->
        # Simple pattern tracking - could be enhanced
        signature = %{
          files: [comparison[:file1], comparison[:file2]],
          change_count: length(comparison[:changes] || [])
        }
        
        [signature | patterns]
        |> Enum.take(20) # Keep last 20 patterns per type
      end)
    else
      agent
    end
  end
end