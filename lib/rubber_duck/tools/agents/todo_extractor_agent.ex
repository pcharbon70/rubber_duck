defmodule RubberDuck.Tools.Agents.TodoExtractorAgent do
  @moduledoc """
  Agent that orchestrates TODO and technical debt extraction from codebases.
  
  This agent manages the discovery, analysis, and tracking of TODO comments,
  technical debt markers, and deferred work items across a codebase. It provides
  specialized actions for comprehensive debt management and prioritization.
  """
  
  use Jido.Agent,
    name: "todo_extractor_agent",
    description: "Orchestrates TODO extraction and technical debt tracking",
    category: "maintenance",
    tags: ["maintenance", "debt", "planning", "documentation", "todos"],
    vsn: "1.0.0",
    schema: [
      extraction_config: [
        type: :map,
        doc: "Configuration for TODO extraction",
        default: %{
          standard_patterns: ["TODO", "FIXME", "HACK", "BUG", "NOTE", "OPTIMIZE"],
          priority_keywords: ["URGENT", "CRITICAL", "IMPORTANT", "ASAP", "BLOCKER"],
          include_context: true,
          context_lines: 2,
          author_extraction: true
        }
      ],
      todo_database: [
        type: :map,
        doc: "Database of extracted TODOs",
        default: %{}
      ],
      scan_history: [
        type: {:list, :map},
        doc: "History of scans performed",
        default: []
      ],
      debt_metrics: [
        type: :map,
        doc: "Technical debt metrics",
        default: %{
          total_todos: 0,
          high_priority_count: 0,
          debt_score: 0.0,
          files_with_debt: 0,
          avg_todos_per_file: 0.0
        }
      ],
      author_stats: [
        type: :map,
        doc: "Statistics by author",
        default: %{}
      ],
      file_stats: [
        type: :map,
        doc: "Statistics by file",
        default: %{}
      ],
      debt_trends: [
        type: :map,
        doc: "Trends in technical debt over time",
        default: %{
          daily_counts: [],
          trend_direction: :stable
        }
      ],
      active_scans: [
        type: :map,
        doc: "Currently active scans",
        default: %{}
      ]
    ]
  
  alias RubberDuck.Tools.TodoExtractor
  
  # Action to execute the todo extractor tool
  defmodule ExecuteToolAction do
    use Jido.Action,
      name: "execute_todo_extractor_tool",
      description: "Execute the todo extractor tool with given parameters",
      schema: [
        params: [type: :map, required: true]
      ]
    
    def run(%{params: params}, context) do
      case TodoExtractor.execute(params, context) do
        {:ok, result} ->
          {:ok, result}
        error ->
          error
      end
    end
  end
  
  # Action to scan entire codebase for TODOs
  defmodule ScanCodebaseAction do
    use Jido.Action,
      name: "scan_codebase_for_todos",
      description: "Perform comprehensive codebase scan for TODOs",
      schema: [
        paths: [type: {:list, :string}, default: ["lib", "test", "apps"]],
        exclude_paths: [type: {:list, :string}, default: ["deps", "_build", ".git"]],
        file_extensions: [type: {:list, :string}, default: [".ex", ".exs", ".eex", ".leex"]],
        custom_patterns: [type: {:list, :string}, default: []],
        batch_size: [type: :integer, default: 50]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      scan_id = generate_scan_id()
      
      # Start scan tracking
      start_time = System.monotonic_time(:millisecond)
      
      # Find all files to scan
      files = find_files_to_scan(params)
      total_files = length(files)
      
      # Process files in batches
      todos = files
      |> Enum.chunk_every(params.batch_size)
      |> Enum.with_index()
      |> Enum.flat_map(fn {batch, batch_idx} ->
        process_batch(batch, batch_idx, params, agent_state)
      end)
      
      end_time = System.monotonic_time(:millisecond)
      
      # Analyze results
      analysis = analyze_scan_results(todos, files)
      
      {:ok, %{
        scan_id: scan_id,
        files_scanned: total_files,
        todos_found: length(todos),
        todos: todos,
        analysis: analysis,
        performance: %{
          duration_ms: end_time - start_time,
          files_per_second: total_files / ((end_time - start_time) / 1000)
        }
      }}
    end
    
    defp find_files_to_scan(params) do
      all_files = params.paths
      |> Enum.flat_map(fn path ->
        if File.dir?(path) do
          find_files_in_directory(path, params.file_extensions)
        else
          [path]
        end
      end)
      |> Enum.uniq()
      
      # Filter out excluded paths
      Enum.reject(all_files, fn file ->
        Enum.any?(params.exclude_paths, &String.contains?(file, &1))
      end)
    end
    
    defp find_files_in_directory(dir, extensions) do
      extensions
      |> Enum.flat_map(fn ext ->
        Path.wildcard(Path.join(dir, "**/*#{ext}"))
      end)
    end
    
    defp process_batch(files, _batch_idx, params, agent_state) do
      patterns = build_patterns(params, agent_state)
      
      Enum.flat_map(files, fn file ->
        case File.read(file) do
          {:ok, content} ->
            extract_todos_from_file(file, content, patterns)
          {:error, _} ->
            []
        end
      end)
    end
    
    defp build_patterns(params, agent_state) do
      standard = agent_state.extraction_config.standard_patterns
      custom = params.custom_patterns
      
      (standard ++ custom)
      |> Enum.uniq()
      |> Enum.map(&compile_pattern/1)
    end
    
    defp compile_pattern(pattern) do
      regex_pattern = "(?:#|//|/\\*|\")\\s*(#{pattern})\\b(.*)$"
      {pattern, Regex.compile!(regex_pattern, "mi")}
    end
    
    defp extract_todos_from_file(file, content, patterns) do
      lines = String.split(content, "\n")
      
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        extract_from_line(file, line, line_num, patterns)
      end)
    end
    
    defp extract_from_line(file, line, line_num, patterns) do
      patterns
      |> Enum.flat_map(fn {pattern_name, regex} ->
        case Regex.run(regex, line) do
          nil -> []
          matches ->
            [build_todo_entry(file, line, line_num, pattern_name, matches)]
        end
      end)
    end
    
    defp build_todo_entry(file, _line, line_num, pattern, [_full, _pattern, description | _]) do
      %{
        id: generate_todo_id(file, line_num),
        type: String.downcase(pattern),
        file: file,
        line_number: line_num,
        description: String.trim(description || ""),
        timestamp: DateTime.utc_now()
      }
    end
    
    defp analyze_scan_results(todos, files) do
      %{
        total_files: length(files),
        files_with_todos: todos |> Enum.map(& &1.file) |> Enum.uniq() |> length(),
        by_type: Enum.frequencies_by(todos, & &1.type),
        hotspots: find_hotspot_files(todos, 5)
      }
    end
    
    defp find_hotspot_files(todos, limit) do
      todos
      |> Enum.group_by(& &1.file)
      |> Enum.map(fn {file, file_todos} -> {file, length(file_todos)} end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(limit)
    end
    
    defp generate_scan_id do
      :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
    
    defp generate_todo_id(file, line_num) do
      content = "#{file}:#{line_num}"
      :crypto.hash(:sha256, content) |> Base.encode16() |> String.slice(0..15)
    end
  end
  
  # Action to analyze technical debt
  defmodule AnalyzeDebtAction do
    use Jido.Action,
      name: "analyze_technical_debt",
      description: "Analyze technical debt from extracted TODOs",
      schema: [
        scoring_weights: [type: :map, default: %{
          high_priority: 10,
          medium_priority: 5,
          low_priority: 2,
          complex: 8,
          old: 7
        }],
        debt_thresholds: [type: :map, default: %{
          critical: 100,
          high: 75,
          medium: 50,
          low: 25
        }]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      todos = Map.values(agent_state.todo_database)
      
      # Calculate debt score
      debt_score = calculate_debt_score(todos, params.scoring_weights)
      
      # Categorize debt
      debt_level = categorize_debt_level(debt_score, params.debt_thresholds)
      
      # Analyze debt distribution
      distribution = analyze_debt_distribution(todos)
      
      # Find critical areas
      critical_areas = identify_critical_areas(todos, agent_state)
      
      # Generate debt report
      report = %{
        total_debt_score: debt_score,
        debt_level: debt_level,
        total_items: length(todos),
        distribution: distribution,
        critical_areas: critical_areas,
        recommendations: generate_debt_recommendations(debt_level, distribution, critical_areas)
      }
      
      {:ok, report}
    end
    
    defp calculate_debt_score(todos, weights) do
      todos
      |> Enum.map(fn todo ->
        priority_score = case todo[:priority] || :low do
          :high -> weights.high_priority
          :medium -> weights.medium_priority
          :low -> weights.low_priority
        end
        
        complexity_score = case todo[:complexity] || :simple do
          :complex -> weights.complex
          :moderate -> weights.complex / 2
          :simple -> 0
        end
        
        age_score = case todo[:estimated_age] || "unknown" do
          "old" -> weights.old
          _ -> 0
        end
        
        priority_score + complexity_score + age_score
      end)
      |> Enum.sum()
    end
    
    defp categorize_debt_level(score, thresholds) do
      cond do
        score >= thresholds.critical -> :critical
        score >= thresholds.high -> :high
        score >= thresholds.medium -> :medium
        score >= thresholds.low -> :low
        true -> :minimal
      end
    end
    
    defp analyze_debt_distribution(todos) do
      %{
        by_type: Enum.frequencies_by(todos, & &1.type),
        by_priority: Enum.frequencies_by(todos, & &1[:priority] || :low),
        by_complexity: Enum.frequencies_by(todos, & &1[:complexity] || :simple),
        by_age: Enum.frequencies_by(todos, & &1[:estimated_age] || "unknown")
      }
    end
    
    defp identify_critical_areas(todos, _agent_state) do
      file_scores = todos
      |> Enum.group_by(& &1.file)
      |> Enum.map(fn {file, file_todos} ->
        score = calculate_debt_score(file_todos, %{
          high_priority: 10,
          medium_priority: 5,
          low_priority: 2,
          complex: 8,
          old: 7
        })
        
        {file, %{
          score: score,
          count: length(file_todos),
          high_priority_count: Enum.count(file_todos, &(&1[:priority] == :high))
        }}
      end)
      |> Enum.sort_by(fn {_, stats} -> stats.score end, :desc)
      |> Enum.take(10)
      
      file_scores
    end
    
    defp generate_debt_recommendations(debt_level, distribution, critical_areas) do
      recommendations = []
      
      # Debt level recommendations
      recommendations = case debt_level do
        :critical -> ["URGENT: Technical debt has reached critical levels. Immediate action required." | recommendations]
        :high -> ["High technical debt detected. Schedule dedicated debt reduction sprints." | recommendations]
        :medium -> ["Moderate technical debt. Include debt reduction in regular development cycles." | recommendations]
        _ -> recommendations
      end
      
      # Priority-based recommendations
      high_priority = Map.get(distribution.by_priority, :high, 0)
      recommendations = if high_priority > 5 do
        ["Address #{high_priority} high-priority items immediately" | recommendations]
      else
        recommendations
      end
      
      # File hotspot recommendations
      recommendations = if length(critical_areas) > 0 do
        [{worst_file, stats} | _] = critical_areas
        filename = Path.basename(worst_file)
        ["File '#{filename}' has #{stats.count} TODOs and needs refactoring" | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
  end
  
  # Action to track TODO lifecycle
  defmodule TrackTodoLifecycleAction do
    use Jido.Action,
      name: "track_todo_lifecycle",
      description: "Track TODO items over time to identify resolved and new items",
      schema: [
        previous_scan_id: [type: :string, required: false],
        current_todos: [type: {:list, :map}, required: true]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      # Get previous TODOs if scan ID provided
      previous_todos = if params[:previous_scan_id] do
        get_todos_from_scan(agent_state, params.previous_scan_id)
      else
        Map.values(agent_state.todo_database)
      end
      
      # Convert to sets for comparison
      current_set = MapSet.new(params.current_todos, &todo_signature/1)
      previous_set = MapSet.new(previous_todos, &todo_signature/1)
      
      # Find changes
      new_todos = MapSet.difference(current_set, previous_set) |> MapSet.to_list()
      resolved_todos = MapSet.difference(previous_set, current_set) |> MapSet.to_list()
      persistent_todos = MapSet.intersection(current_set, previous_set) |> MapSet.to_list()
      
      # Calculate metrics
      resolution_rate = if length(previous_todos) > 0 do
        length(resolved_todos) / length(previous_todos) * 100
      else
        0.0
      end
      
      growth_rate = if length(previous_todos) > 0 do
        (length(params.current_todos) - length(previous_todos)) / length(previous_todos) * 100
      else
        0.0
      end
      
      {:ok, %{
        lifecycle: %{
          new: new_todos,
          resolved: resolved_todos,
          persistent: persistent_todos
        },
        metrics: %{
          total_before: length(previous_todos),
          total_after: length(params.current_todos),
          new_count: length(new_todos),
          resolved_count: length(resolved_todos),
          persistent_count: length(persistent_todos),
          resolution_rate: Float.round(resolution_rate, 2),
          growth_rate: Float.round(growth_rate, 2)
        },
        trend: determine_trend(growth_rate)
      }}
    end
    
    defp get_todos_from_scan(agent_state, scan_id) do
      case Enum.find(agent_state.scan_history, &(&1.scan_id == scan_id)) do
        nil -> []
        scan -> scan.todos
      end
    end
    
    defp todo_signature(todo) do
      # Create a signature that identifies a TODO uniquely
      "#{todo.file}:#{todo.line_number}:#{todo.type}:#{String.slice(todo.description || "", 0..50)}"
    end
    
    defp determine_trend(growth_rate) do
      cond do
        growth_rate > 10 -> :increasing
        growth_rate < -10 -> :decreasing
        true -> :stable
      end
    end
  end
  
  # Action to generate TODO report
  defmodule GenerateTodoReportAction do
    use Jido.Action,
      name: "generate_todo_report",
      description: "Generate comprehensive TODO and technical debt report",
      schema: [
        format: [type: :atom, default: :markdown],
        sections: [type: {:list, :atom}, default: [:summary, :distribution, :hotspots, :trends, :recommendations]],
        include_details: [type: :boolean, default: true]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      # Gather data for report
      todos = Map.values(agent_state.todo_database)
      
      sections = Enum.reduce(params.sections, %{}, fn section, acc ->
        content = generate_section(section, todos, agent_state)
        Map.put(acc, section, content)
      end)
      
      # Format report
      report = case params.format do
        :markdown -> format_markdown_report(sections, agent_state)
        :json -> format_json_report(sections, agent_state)
        :html -> format_html_report(sections, agent_state)
        _ -> format_text_report(sections, agent_state)
      end
      
      {:ok, %{
        format: params.format,
        report: report,
        metadata: %{
          generated_at: DateTime.utc_now(),
          total_todos: length(todos),
          debt_score: agent_state.debt_metrics.debt_score
        }
      }}
    end
    
    defp generate_section(:summary, todos, agent_state) do
      %{
        total_todos: length(todos),
        debt_score: agent_state.debt_metrics.debt_score,
        high_priority_items: Enum.count(todos, &(&1[:priority] == :high)),
        files_affected: todos |> Enum.map(& &1.file) |> Enum.uniq() |> length(),
        authors_involved: agent_state.author_stats |> Map.keys() |> length()
      }
    end
    
    defp generate_section(:distribution, todos, _agent_state) do
      %{
        by_type: Enum.frequencies_by(todos, & &1.type),
        by_priority: Enum.frequencies_by(todos, & &1[:priority] || :low),
        by_complexity: Enum.frequencies_by(todos, & &1[:complexity] || :simple),
        by_file_type: group_by_file_type(todos)
      }
    end
    
    defp generate_section(:hotspots, todos, _agent_state) do
      todos
      |> Enum.group_by(& &1.file)
      |> Enum.map(fn {file, file_todos} ->
        %{
          file: file,
          count: length(file_todos),
          types: Enum.frequencies_by(file_todos, & &1.type),
          high_priority_count: Enum.count(file_todos, &(&1[:priority] == :high))
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)
      |> Enum.take(10)
    end
    
    defp generate_section(:trends, _todos, agent_state) do
      %{
        debt_trend: agent_state.debt_trends.trend_direction,
        daily_counts: Enum.take(agent_state.debt_trends.daily_counts, -7),
        resolution_metrics: calculate_resolution_metrics(agent_state)
      }
    end
    
    defp generate_section(:recommendations, todos, agent_state) do
      generate_recommendations(todos, agent_state)
    end
    
    defp group_by_file_type(todos) do
      todos
      |> Enum.group_by(fn todo ->
        Path.extname(todo.file)
      end)
      |> Enum.map(fn {ext, todos} -> {ext, length(todos)} end)
      |> Enum.into(%{})
    end
    
    defp calculate_resolution_metrics(agent_state) do
      recent_scans = Enum.take(agent_state.scan_history, 5)
      
      if length(recent_scans) >= 2 do
        [latest, previous | _] = recent_scans
        
        resolved = max(0, length(previous.todos) - length(latest.todos))
        added = max(0, length(latest.todos) - length(previous.todos))
        
        %{
          resolved_recently: resolved,
          added_recently: added,
          net_change: length(latest.todos) - length(previous.todos)
        }
      else
        %{resolved_recently: 0, added_recently: 0, net_change: 0}
      end
    end
    
    defp generate_recommendations(todos, agent_state) do
      recommendations = []
      
      # High priority recommendations
      high_priority = Enum.count(todos, &(&1[:priority] == :high))
      recommendations = if high_priority > 10 do
        ["Create a dedicated sprint to address #{high_priority} high-priority items" | recommendations]
      else
        recommendations
      end
      
      # File hotspot recommendations
      hotspots = todos
      |> Enum.group_by(& &1.file)
      |> Enum.filter(fn {_, file_todos} -> length(file_todos) > 10 end)
      
      recommendations = if length(hotspots) > 0 do
        ["Refactor #{length(hotspots)} files with excessive TODOs" | recommendations]
      else
        recommendations
      end
      
      # Debt trend recommendations
      recommendations = case agent_state.debt_trends.trend_direction do
        :increasing ->
          ["Technical debt is increasing. Allocate time for debt reduction." | recommendations]
        :stable ->
          ["Technical debt is stable but should be actively reduced." | recommendations]
        _ ->
          recommendations
      end
      
      recommendations
    end
    
    defp format_markdown_report(sections, _agent_state) do
      """
      # Technical Debt Report
      
      Generated: #{DateTime.utc_now() |> DateTime.to_string()}
      
      ## Summary
      #{format_markdown_section(sections[:summary])}
      
      ## Distribution
      #{format_markdown_section(sections[:distribution])}
      
      ## Hotspots
      #{format_markdown_section(sections[:hotspots])}
      
      ## Trends
      #{format_markdown_section(sections[:trends])}
      
      ## Recommendations
      #{format_markdown_list(sections[:recommendations])}
      """
    end
    
    defp format_markdown_section(nil), do: "No data available"
    defp format_markdown_section(data) when is_map(data) do
      data
      |> Enum.map(fn {key, value} ->
        "- **#{humanize(key)}**: #{format_value(value)}"
      end)
      |> Enum.join("\n")
    end
    defp format_markdown_section(data) when is_list(data) do
      data
      |> Enum.map(&format_markdown_item/1)
      |> Enum.join("\n\n")
    end
    
    defp format_markdown_item(item) when is_map(item) do
      item
      |> Enum.map(fn {k, v} -> "- #{humanize(k)}: #{v}" end)
      |> Enum.join("\n")
    end
    
    defp format_markdown_list(nil), do: "No recommendations"
    defp format_markdown_list(items) when is_list(items) do
      items
      |> Enum.map(fn item -> "- #{item}" end)
      |> Enum.join("\n")
    end
    
    defp format_json_report(sections, agent_state) do
      Map.merge(sections, %{
        metadata: %{
          generated_at: DateTime.utc_now(),
          total_todos: length(Map.values(agent_state.todo_database)),
          debt_score: agent_state.debt_metrics.debt_score
        }
      })
    end
    
    defp format_html_report(_sections, _agent_state) do
      "<html><body><h1>Technical Debt Report</h1><p>HTML format not implemented</p></body></html>"
    end
    
    defp format_text_report(sections, _agent_state) do
      sections
      |> Enum.map(fn {section, content} ->
        """
        === #{humanize(section)} ===
        #{inspect(content, pretty: true)}
        """
      end)
      |> Enum.join("\n\n")
    end
    
    defp humanize(atom) do
      atom
      |> to_string()
      |> String.replace("_", " ")
      |> String.capitalize()
    end
    
    defp format_value(value) when is_map(value), do: "#{map_size(value)} items"
    defp format_value(value) when is_list(value), do: "#{length(value)} items"
    defp format_value(value), do: to_string(value)
  end
  
  # Action to prioritize TODOs
  defmodule PrioritizeTodosAction do
    use Jido.Action,
      name: "prioritize_todos",
      description: "Prioritize TODOs based on various factors",
      schema: [
        criteria: [type: {:list, :atom}, default: [:impact, :effort, :risk, :age]],
        weights: [type: :map, default: %{
          impact: 0.4,
          effort: 0.2,
          risk: 0.3,
          age: 0.1
        }],
        limit: [type: :integer, default: 20]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      todos = Map.values(agent_state.todo_database)
      
      # Score each TODO
      scored_todos = todos
      |> Enum.map(fn todo ->
        score = calculate_priority_score(todo, params.criteria, params.weights)
        Map.put(todo, :priority_score, score)
      end)
      |> Enum.sort_by(& &1.priority_score, :desc)
      
      # Get top priority items
      top_priority = Enum.take(scored_todos, params.limit)
      
      # Group by recommended action
      action_groups = group_by_action(top_priority)
      
      {:ok, %{
        total_evaluated: length(todos),
        top_priority_count: length(top_priority),
        top_priority_items: top_priority,
        action_plan: action_groups,
        estimated_effort: estimate_total_effort(top_priority)
      }}
    end
    
    defp calculate_priority_score(todo, criteria, weights) do
      scores = Enum.map(criteria, fn criterion ->
        score = case criterion do
          :impact -> estimate_impact(todo)
          :effort -> estimate_effort(todo)
          :risk -> estimate_risk(todo)
          :age -> estimate_age_score(todo)
        end
        
        score * Map.get(weights, criterion, 0)
      end)
      
      Enum.sum(scores)
    end
    
    defp estimate_impact(todo) do
      # Higher score for more impactful items
      base_score = case todo[:priority] || :low do
        :high -> 10
        :medium -> 5
        :low -> 2
      end
      
      # Adjust based on type
      type_multiplier = case todo.type do
        "bug" -> 1.5
        "fixme" -> 1.3
        "security" -> 2.0
        "performance" -> 1.2
        _ -> 1.0
      end
      
      base_score * type_multiplier
    end
    
    defp estimate_effort(todo) do
      # Lower score for higher effort (we want easy wins)
      case todo[:complexity] || :simple do
        :simple -> 10
        :moderate -> 5
        :complex -> 2
      end
    end
    
    defp estimate_risk(todo) do
      # Higher score for higher risk items
      risk_keywords = ["security", "data", "auth", "payment", "critical"]
      
      description = String.downcase(todo.description || "")
      
      if Enum.any?(risk_keywords, &String.contains?(description, &1)) do
        10
      else
        case todo.type do
          "bug" -> 7
          "fixme" -> 5
          _ -> 3
        end
      end
    end
    
    defp estimate_age_score(todo) do
      # Higher score for older items
      case todo[:estimated_age] || "unknown" do
        "old" -> 10
        "ongoing" -> 5
        "recent" -> 2
        _ -> 3
      end
    end
    
    defp group_by_action(todos) do
      todos
      |> Enum.group_by(&recommend_action/1)
      |> Enum.map(fn {action, items} ->
        %{
          action: action,
          count: length(items),
          items: Enum.take(items, 5)  # Sample items
        }
      end)
    end
    
    defp recommend_action(todo) do
      cond do
        todo.type in ["bug", "fixme"] -> :fix_immediately
        todo[:priority] == :high -> :schedule_sprint
        todo[:complexity] == :simple -> :quick_win
        todo[:estimated_age] == "old" -> :review_and_close
        true -> :backlog
      end
    end
    
    defp estimate_total_effort(todos) do
      total_points = todos
      |> Enum.map(fn todo ->
        case todo[:complexity] || :simple do
          :simple -> 1
          :moderate -> 3
          :complex -> 8
        end
      end)
      |> Enum.sum()
      
      %{
        story_points: total_points,
        estimated_days: Float.round(total_points / 8, 1)
      }
    end
  end
  
  def additional_actions do
    [
      ExecuteToolAction,
      ScanCodebaseAction,
      AnalyzeDebtAction,
      TrackTodoLifecycleAction,
      GenerateTodoReportAction,
      PrioritizeTodosAction
    ]
  end
  
  @impl true
  def handle_signal(state, %{"type" => "extract_todos"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case ExecuteToolAction.run(%{params: params}, context) do
      {:ok, result} -> 
        {:ok, update_state_after_extraction(state, result)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, %{"type" => "scan_codebase"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    {:ok, result} = ScanCodebaseAction.run(params, context)
    {:ok, update_state_after_scan(state, result)}
  end
  
  @impl true
  def handle_signal(state, %{"type" => "analyze_debt"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    {:ok, result} = AnalyzeDebtAction.run(params, context)
    {:ok, update_debt_metrics(state, result)}
  end
  
  @impl true
  def handle_signal(state, _signal) do
    {:ok, state}
  end
  
  def handle_action_result(state, ExecuteToolAction, {:ok, result}, _params) do
    # Update TODO database
    new_todos = Enum.reduce(result.todos, state.todo_database, fn todo, acc ->
      todo_id = generate_todo_id(todo)
      Map.put(acc, todo_id, Map.put(todo, :id, todo_id))
    end)
    
    state = put_in(state.todo_database, new_todos)
    
    # Update statistics
    state = update_statistics(state, result)
    
    {:ok, state}
  end
  
  def handle_action_result(state, ScanCodebaseAction, {:ok, result}, _params) do
    # Add to scan history
    scan_entry = %{
      scan_id: result.scan_id,
      timestamp: DateTime.utc_now(),
      files_scanned: result.files_scanned,
      todos_found: result.todos_found,
      todos: result.todos
    }
    
    state = update_in(state.scan_history, &([scan_entry | &1] |> Enum.take(50)))
    
    # Update TODO database
    new_todos = Enum.reduce(result.todos, state.todo_database, fn todo, acc ->
      todo_id = todo.id || generate_todo_id(todo)
      Map.put(acc, todo_id, Map.put(todo, :id, todo_id))
    end)
    
    state = put_in(state.todo_database, new_todos)
    
    # Update metrics
    state = update_debt_metrics_from_scan(state, result)
    
    {:ok, state}
  end
  
  def handle_action_result(state, AnalyzeDebtAction, {:ok, result}, _params) do
    # Update debt metrics
    metrics = %{
      debt_score: result.total_debt_score,
      high_priority_count: get_in(result.distribution.by_priority, [:high]) || 0,
      total_todos: result.total_items
    }
    
    state = update_in(state.debt_metrics, &Map.merge(&1, metrics))
    
    # Update trend
    trend = case result.debt_level do
      level when level in [:critical, :high] -> :increasing
      :medium -> :stable
      _ -> :decreasing
    end
    
    state = put_in(state.debt_trends.trend_direction, trend)
    
    {:ok, state}
  end
  
  def handle_action_result(state, _action, _result, _params) do
    {:ok, state}
  end
  
  defp update_state_after_extraction(state, result) do
    # Update TODO database
    new_todos = Enum.reduce(result.todos, %{}, fn todo, acc ->
      todo_id = generate_todo_id(todo)
      Map.put(acc, todo_id, Map.put(todo, :id, todo_id))
    end)
    
    state
    |> put_in([:todo_database], Map.merge(state.todo_database, new_todos))
    |> update_statistics(result)
  end
  
  defp update_state_after_scan(state, result) do
    scan_entry = %{
      scan_id: result.scan_id,
      timestamp: DateTime.utc_now(),
      files_scanned: result.files_scanned,
      todos_found: result.todos_found,
      performance: result.performance
    }
    
    state
    |> update_in([:scan_history], &([scan_entry | &1] |> Enum.take(100)))
    |> update_debt_metrics_from_scan(result)
  end
  
  defp update_statistics(state, result) do
    # Update file statistics
    file_stats = result.todos
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, todos} -> {file, length(todos)} end)
    |> Enum.into(%{})
    
    state = put_in(state.file_stats, Map.merge(state.file_stats, file_stats))
    
    # Update author statistics if available
    author_stats = result.todos
    |> Enum.filter(&Map.has_key?(&1, :author))
    |> Enum.group_by(& &1.author)
    |> Enum.map(fn {author, todos} -> {author, length(todos)} end)
    |> Enum.into(%{})
    
    put_in(state.author_stats, Map.merge(state.author_stats, author_stats))
  end
  
  defp update_debt_metrics(state, result) do
    put_in(state.debt_metrics, %{
      total_todos: result.total_items,
      high_priority_count: get_in(result.distribution, [:by_priority, :high]) || 0,
      debt_score: result.total_debt_score,
      files_with_debt: length(result.critical_areas),
      avg_todos_per_file: if(length(result.critical_areas) > 0, 
        do: result.total_items / length(result.critical_areas), 
        else: 0.0)
    })
  end
  
  defp update_debt_metrics_from_scan(state, scan_result) do
    todos = scan_result.todos
    files_with_todos = todos |> Enum.map(& &1.file) |> Enum.uniq() |> length()
    
    metrics = %{
      total_todos: length(todos),
      files_with_debt: files_with_todos,
      avg_todos_per_file: if(files_with_todos > 0, 
        do: length(todos) / files_with_todos, 
        else: 0.0)
    }
    
    update_in(state.debt_metrics, &Map.merge(&1, metrics))
  end
  
  defp generate_todo_id(todo) do
    content = "#{todo.file}:#{todo.line_number}:#{todo.type}"
    :crypto.hash(:sha256, content)
    |> Base.encode16()
    |> String.slice(0..15)
  end
end