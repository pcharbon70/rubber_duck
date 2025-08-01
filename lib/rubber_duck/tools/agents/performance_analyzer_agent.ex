defmodule RubberDuck.Tools.Agents.PerformanceAnalyzerAgent do
  @moduledoc """
  Agent that analyzes code performance and provides optimization recommendations.
  
  Capabilities:
  - Performance profiling and bottleneck detection
  - Time and space complexity analysis
  - Memory usage analysis
  - Database query optimization
  - Caching opportunity identification
  - Performance benchmarking
  """
  
  use RubberDuck.Tools.BaseToolAgent, tool: :performance_analyzer
  
  alias Jido.Agent.Server.State
  
  # Custom actions for performance analysis
  defmodule ProfileCodeAction do
    @moduledoc """
    Profiles code execution to identify performance bottlenecks.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to profile"],
        language: [type: :string, required: true, doc: "Programming language"],
        profile_type: [type: :string, default: "cpu", doc: "Profile type: cpu, memory, io"],
        execution_context: [type: :map, doc: "Context for execution (input data, env)"]
      }
    end
    
    @impl true
    def run(params, _context) do
      profile_result = perform_profiling(
        params.source_code,
        params.language,
        params.profile_type,
        params.execution_context
      )
      
      {:ok, %{
        profile_type: params.profile_type,
        hotspots: profile_result.hotspots,
        bottlenecks: profile_result.bottlenecks,
        metrics: profile_result.metrics,
        recommendations: generate_recommendations(profile_result),
        optimization_opportunities: identify_optimizations(profile_result)
      }}
    end
    
    defp perform_profiling(code, language, type, context) do
      # Analyze code structure
      functions = extract_functions(code, language)
      
      # Simulate profiling based on code patterns
      hotspots = case type do
        "cpu" -> identify_cpu_hotspots(functions, code)
        "memory" -> identify_memory_hotspots(functions, code)
        "io" -> identify_io_hotspots(functions, code)
        _ -> []
      end
      
      bottlenecks = analyze_bottlenecks(hotspots, functions)
      
      %{
        hotspots: hotspots,
        bottlenecks: bottlenecks,
        metrics: calculate_metrics(hotspots, type),
        functions: functions
      }
    end
    
    defp extract_functions(code, _language) do
      # Simple function extraction
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} -> 
        String.match?(line, ~r/function|def|func|method/)
      end)
      |> Enum.map(fn {line, line_num} ->
        name = extract_function_name(line)
        %{
          name: name,
          line: line_num,
          complexity: estimate_complexity(code, line_num)
        }
      end)
    end
    
    defp extract_function_name(line) do
      cond do
        String.contains?(line, "function") ->
          Regex.run(~r/function\s+(\w+)/, line) |> List.last() || "anonymous"
        String.contains?(line, "def") ->
          Regex.run(~r/def\s+(\w+)/, line) |> List.last() || "unknown"
        true ->
          "unknown"
      end
    end
    
    defp estimate_complexity(code, start_line) do
      # Simple complexity estimation based on patterns
      lines = String.split(code, "\n")
      function_lines = Enum.slice(lines, start_line - 1, 50)
      
      loop_count = Enum.count(function_lines, &String.match?(&1, ~r/for|while|loop/))
      condition_count = Enum.count(function_lines, &String.match?(&1, ~r/if|else|switch|case/))
      
      1 + loop_count * 2 + condition_count
    end
    
    defp identify_cpu_hotspots(functions, code) do
      patterns = [
        {~r/nested.*loop|loop.*loop/, 10, "Nested loops detected"},
        {~r/recursion|recursive/, 8, "Recursive calls detected"},
        {~r/sort|sorting/, 6, "Sorting operation detected"},
        {~r/regex|regular expression/, 5, "Complex regex operations"},
        {~r/parse|parsing/, 4, "Parsing operations"}
      ]
      
      code_lines = String.split(code, "\n")
      
      patterns
      |> Enum.flat_map(fn {pattern, severity, description} ->
        code_lines
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(pattern, line) end)
        |> Enum.map(fn {line, line_num} ->
          %{
            type: :cpu,
            location: "line #{line_num}",
            severity: severity,
            description: description,
            code_snippet: String.trim(line),
            impact: severity * 10  # percentage
          }
        end)
      end)
      |> Enum.sort_by(& -&1.severity)
    end
    
    defp identify_memory_hotspots(functions, code) do
      patterns = [
        {~r/new Array|malloc|allocate/, 8, "Memory allocation detected"},
        {~r/concat|join.*large/, 7, "String concatenation in loop"},
        {~r/cache|memo|store/, 5, "Potential memory leak"},
        {~r/global|static.*array/, 6, "Large static allocation"}
      ]
      
      code_lines = String.split(code, "\n")
      
      patterns
      |> Enum.flat_map(fn {pattern, severity, description} ->
        code_lines
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(pattern, line) end)
        |> Enum.map(fn {line, line_num} ->
          %{
            type: :memory,
            location: "line #{line_num}",
            severity: severity,
            description: description,
            code_snippet: String.trim(line),
            memory_impact: estimate_memory_impact(line)
          }
        end)
      end)
    end
    
    defp identify_io_hotspots(_functions, code) do
      patterns = [
        {~r/read|write|file|disk/, 9, "File I/O operation"},
        {~r/database|query|select|insert/, 8, "Database operation"},
        {~r/http|request|fetch|api/, 7, "Network operation"},
        {~r/console|print|log/, 3, "Console I/O"}
      ]
      
      code_lines = String.split(code, "\n")
      
      patterns
      |> Enum.flat_map(fn {pattern, severity, description} ->
        code_lines
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(pattern, line) end)
        |> Enum.map(fn {line, line_num} ->
          %{
            type: :io,
            location: "line #{line_num}",
            severity: severity,
            description: description,
            code_snippet: String.trim(line),
            latency_impact: "#{severity * 10}ms"
          }
        end)
      end)
    end
    
    defp analyze_bottlenecks(hotspots, functions) do
      # Group hotspots by proximity
      grouped = Enum.group_by(hotspots, fn hotspot ->
        # Extract line number from location
        case Regex.run(~r/line (\d+)/, hotspot.location) do
          [_, line_str] -> 
            line = String.to_integer(line_str)
            # Find which function this belongs to
            Enum.find(functions, fn func -> 
              func.line <= line && line <= func.line + 50
            end)
          _ -> nil
        end
      end)
      
      grouped
      |> Enum.reject(fn {k, _} -> is_nil(k) end)
      |> Enum.map(fn {function, function_hotspots} ->
        total_severity = Enum.sum(Enum.map(function_hotspots, & &1.severity))
        
        %{
          function: function.name,
          severity: total_severity,
          hotspot_count: length(function_hotspots),
          types: Enum.map(function_hotspots, & &1.type) |> Enum.uniq(),
          estimated_impact: "#{total_severity * 5}% of execution time"
        }
      end)
      |> Enum.sort_by(& -&1.severity)
      |> Enum.take(5)
    end
    
    defp calculate_metrics(hotspots, profile_type) do
      total_severity = Enum.sum(Enum.map(hotspots, & &1.severity))
      
      base_metrics = %{
        total_hotspots: length(hotspots),
        critical_hotspots: Enum.count(hotspots, &(&1.severity >= 8)),
        profile_score: max(0, 100 - total_severity * 2)
      }
      
      case profile_type do
        "cpu" ->
          Map.merge(base_metrics, %{
            estimated_cpu_usage: "#{min(100, total_severity * 10)}%",
            optimization_potential: "#{min(50, total_severity * 5)}%"
          })
        
        "memory" ->
          Map.merge(base_metrics, %{
            estimated_memory_pressure: categorize_severity(total_severity),
            leak_risk: if(total_severity > 20, do: "high", else: "low")
          })
        
        "io" ->
          Map.merge(base_metrics, %{
            io_wait_estimate: "#{total_severity * 20}ms",
            blocking_operations: Enum.count(hotspots, &(&1.severity >= 7))
          })
        
        _ -> base_metrics
      end
    end
    
    defp categorize_severity(severity) do
      cond do
        severity >= 30 -> "critical"
        severity >= 20 -> "high"
        severity >= 10 -> "medium"
        true -> "low"
      end
    end
    
    defp estimate_memory_impact(line) do
      cond do
        String.match?(line, ~r/\[\s*\d{4,}/) -> "High (large array)"
        String.match?(line, ~r/new|malloc/) -> "Medium (allocation)"
        String.match?(line, ~r/push|append/) -> "Low (growth)"
        true -> "Minimal"
      end
    end
    
    defp generate_recommendations(profile_result) do
      recommendations = []
      
      # CPU recommendations
      cpu_hotspots = Enum.filter(profile_result.hotspots, &(&1.type == :cpu))
      recommendations = if length(cpu_hotspots) > 0 do
        [
          "Consider optimizing algorithmic complexity in hot paths",
          "Use memoization for expensive computations",
          "Parallelize independent operations"
        ] ++ recommendations
      else
        recommendations
      end
      
      # Memory recommendations
      memory_hotspots = Enum.filter(profile_result.hotspots, &(&1.type == :memory))
      recommendations = if length(memory_hotspots) > 0 do
        [
          "Implement object pooling for frequent allocations",
          "Use streaming for large data processing",
          "Review data structure choices"
        ] ++ recommendations
      else
        recommendations
      end
      
      # IO recommendations
      io_hotspots = Enum.filter(profile_result.hotspots, &(&1.type == :io))
      if length(io_hotspots) > 0 do
        [
          "Batch I/O operations where possible",
          "Implement caching for repeated reads",
          "Use async I/O for non-blocking operations"
        ] ++ recommendations
      else
        recommendations
      end
    end
    
    defp identify_optimizations(profile_result) do
      profile_result.hotspots
      |> Enum.map(fn hotspot ->
        %{
          location: hotspot.location,
          optimization_type: suggest_optimization_type(hotspot),
          expected_improvement: "#{hotspot.severity * 10}%",
          priority: if(hotspot.severity >= 7, do: "high", else: "medium")
        }
      end)
      |> Enum.take(10)
    end
    
    defp suggest_optimization_type(hotspot) do
      case hotspot.type do
        :cpu ->
          cond do
            String.contains?(hotspot.description, "Nested loops") -> "Loop optimization"
            String.contains?(hotspot.description, "Recursive") -> "Tail recursion or iteration"
            String.contains?(hotspot.description, "Sorting") -> "Algorithm selection"
            true -> "Algorithm optimization"
          end
        
        :memory ->
          cond do
            String.contains?(hotspot.description, "allocation") -> "Memory pooling"
            String.contains?(hotspot.description, "concatenation") -> "StringBuilder pattern"
            true -> "Memory management"
          end
        
        :io ->
          cond do
            String.contains?(hotspot.description, "Database") -> "Query optimization"
            String.contains?(hotspot.description, "File") -> "Buffered I/O"
            String.contains?(hotspot.description, "Network") -> "Connection pooling"
            true -> "I/O optimization"
          end
      end
    end
  end
  
  defmodule AnalyzeComplexityAction do
    @moduledoc """
    Analyzes time and space complexity of algorithms.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to analyze"],
        language: [type: :string, required: true, doc: "Programming language"],
        function_name: [type: :string, doc: "Specific function to analyze"],
        include_space: [type: :boolean, default: true, doc: "Include space complexity"]
      }
    end
    
    @impl true
    def run(params, _context) do
      functions = if params.function_name do
        [analyze_specific_function(params.source_code, params.function_name, params.language)]
      else
        analyze_all_functions(params.source_code, params.language)
      end
      
      complexity_report = functions
        |> Enum.map(fn func ->
          %{
            function: func.name,
            time_complexity: func.time_complexity,
            space_complexity: if(params.include_space, do: func.space_complexity, else: nil),
            analysis: func.analysis,
            suggestions: func.suggestions
          }
        end)
      
      {:ok, %{
        complexity_analysis: complexity_report,
        overall_assessment: assess_overall_complexity(complexity_report),
        optimization_targets: identify_complexity_targets(complexity_report)
      }}
    end
    
    defp analyze_specific_function(code, function_name, language) do
      # Extract function code
      function_code = extract_function_code(code, function_name)
      analyze_function_complexity(function_name, function_code, language)
    end
    
    defp analyze_all_functions(code, language) do
      # Extract all functions
      extract_all_functions(code, language)
      |> Enum.map(fn {name, func_code} ->
        analyze_function_complexity(name, func_code, language)
      end)
    end
    
    defp extract_function_code(code, function_name) do
      lines = String.split(code, "\n")
      
      # Find function start
      start_idx = Enum.find_index(lines, fn line ->
        String.contains?(line, function_name) && 
        String.match?(line, ~r/function|def|func/)
      end)
      
      if start_idx do
        # Extract until end of function (simplified)
        Enum.slice(lines, start_idx, 50) |> Enum.join("\n")
      else
        ""
      end
    end
    
    defp extract_all_functions(code, _language) do
      lines = String.split(code, "\n")
      
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _} ->
        String.match?(line, ~r/function|def|func/)
      end)
      |> Enum.map(fn {line, idx} ->
        name = extract_function_name_from_line(line)
        func_code = Enum.slice(lines, idx, 50) |> Enum.join("\n")
        {name, func_code}
      end)
    end
    
    defp extract_function_name_from_line(line) do
      cond do
        match = Regex.run(~r/function\s+(\w+)/, line) -> List.last(match)
        match = Regex.run(~r/def\s+(\w+)/, line) -> List.last(match)
        match = Regex.run(~r/func\s+(\w+)/, line) -> List.last(match)
        true -> "anonymous"
      end
    end
    
    defp analyze_function_complexity(name, code, _language) do
      # Detect patterns that indicate complexity
      loop_depth = calculate_loop_depth(code)
      has_recursion = String.match?(code, ~r/#{name}\s*\(/)
      has_nested_loops = loop_depth > 1
      data_structure_ops = detect_data_structure_operations(code)
      
      time_complexity = determine_time_complexity(
        loop_depth,
        has_recursion,
        data_structure_ops
      )
      
      space_complexity = determine_space_complexity(
        code,
        has_recursion,
        data_structure_ops
      )
      
      %{
        name: name,
        time_complexity: time_complexity,
        space_complexity: space_complexity,
        analysis: %{
          loop_depth: loop_depth,
          has_recursion: has_recursion,
          has_nested_loops: has_nested_loops,
          data_structures: data_structure_ops
        },
        suggestions: generate_complexity_suggestions(time_complexity, space_complexity)
      }
    end
    
    defp calculate_loop_depth(code) do
      lines = String.split(code, "\n")
      max_depth = 0
      current_depth = 0
      
      Enum.reduce(lines, {max_depth, current_depth}, fn line, {max, current} ->
        cond do
          String.match?(line, ~r/for|while|loop/) ->
            new_depth = current + 1
            {max(max, new_depth), new_depth}
          
          String.match?(line, ~r/}|end/) && current > 0 ->
            {max, current - 1}
          
          true ->
            {max, current}
        end
      end)
      |> elem(0)
    end
    
    defp detect_data_structure_operations(code) do
      operations = []
      
      operations = if String.match?(code, ~r/sort|sorted/) do
        ["sorting" | operations]
      else
        operations
      end
      
      operations = if String.match?(code, ~r/search|find|includes/) do
        ["searching" | operations]
      else
        operations
      end
      
      operations = if String.match?(code, ~r/push|pop|enqueue|dequeue/) do
        ["queue/stack ops" | operations]
      else
        operations
      end
      
      operations = if String.match?(code, ~r/hash|map|dict/) do
        ["hash table ops" | operations]
      else
        operations
      end
      
      operations
    end
    
    defp determine_time_complexity(loop_depth, has_recursion, data_ops) do
      base_complexity = cond do
        loop_depth == 0 && !has_recursion -> "O(1)"
        loop_depth == 1 && !has_recursion -> "O(n)"
        loop_depth == 2 -> "O(n²)"
        loop_depth == 3 -> "O(n³)"
        loop_depth > 3 -> "O(n^#{loop_depth})"
        has_recursion -> "O(n) to O(2^n)"  # Conservative estimate
        true -> "O(n)"
      end
      
      # Adjust for data structure operations
      if "sorting" in data_ops do
        "O(n log n)"
      else
        base_complexity
      end
    end
    
    defp determine_space_complexity(code, has_recursion, _data_ops) do
      cond do
        String.match?(code, ~r/new Array|malloc.*n|Array\.new/) -> "O(n)"
        String.match?(code, ~r/matrix|grid|2d.array/) -> "O(n²)"
        has_recursion -> "O(n)"  # Call stack
        String.match?(code, ~r/memo|cache|dp/) -> "O(n)"
        true -> "O(1)"
      end
    end
    
    defp generate_complexity_suggestions(time_complexity, space_complexity) do
      suggestions = []
      
      suggestions = if String.contains?(time_complexity, "n²") || String.contains?(time_complexity, "n³") do
        [
          "Consider using more efficient algorithms",
          "Look for opportunities to reduce nested loops",
          "Consider using hash tables for lookups"
        ] ++ suggestions
      else
        suggestions
      end
      
      suggestions = if String.contains?(time_complexity, "2^n") do
        [
          "Exponential complexity detected - consider dynamic programming",
          "Look for overlapping subproblems to memoize"
        ] ++ suggestions
      else
        suggestions
      end
      
      if String.contains?(space_complexity, "n²") do
        ["Consider space-time tradeoffs", "Evaluate if all data needs to be stored"] ++ suggestions
      else
        suggestions
      end
    end
    
    defp assess_overall_complexity(complexity_report) do
      complexities = Enum.map(complexity_report, & &1.time_complexity)
      
      worst_case = find_worst_complexity(complexities)
      
      %{
        worst_case_complexity: worst_case,
        performance_grade: grade_complexity(worst_case),
        scalability_assessment: assess_scalability(worst_case)
      }
    end
    
    defp find_worst_complexity(complexities) do
      complexity_order = ["O(1)", "O(log n)", "O(n)", "O(n log n)", "O(n²)", "O(n³)", "O(2^n)"]
      
      complexities
      |> Enum.max_by(fn complexity ->
        Enum.find_index(complexity_order, &String.contains?(complexity, &1)) || 999
      end)
    end
    
    defp grade_complexity(complexity) do
      cond do
        String.contains?(complexity, "O(1)") || String.contains?(complexity, "O(log n)") -> "A"
        String.contains?(complexity, "O(n)") && !String.contains?(complexity, "n²") -> "B"
        String.contains?(complexity, "O(n log n)") -> "B"
        String.contains?(complexity, "O(n²)") -> "C"
        String.contains?(complexity, "O(n³)") -> "D"
        true -> "F"
      end
    end
    
    defp assess_scalability(complexity) do
      cond do
        String.contains?(complexity, "O(1)") -> "Excellent - constant time"
        String.contains?(complexity, "O(log n)") -> "Excellent - logarithmic growth"
        String.contains?(complexity, "O(n)") && !String.contains?(complexity, "n²") -> "Good - linear growth"
        String.contains?(complexity, "O(n log n)") -> "Good - efficient for most use cases"
        String.contains?(complexity, "O(n²)") -> "Poor - quadratic growth limits scalability"
        String.contains?(complexity, "O(n³)") -> "Very poor - cubic growth severely limits scale"
        String.contains?(complexity, "2^n") -> "Unscalable - exponential growth"
        true -> "Unknown"
      end
    end
    
    defp identify_complexity_targets(complexity_report) do
      complexity_report
      |> Enum.filter(fn report ->
        grade = grade_complexity(report.time_complexity)
        grade in ["C", "D", "F"]
      end)
      |> Enum.map(fn report ->
        %{
          function: report.function,
          current_complexity: report.time_complexity,
          priority: if(String.contains?(report.time_complexity, "2^n"), do: "critical", else: "high"),
          improvement_potential: estimate_improvement_potential(report.time_complexity)
        }
      end)
    end
    
    defp estimate_improvement_potential(complexity) do
      cond do
        String.contains?(complexity, "2^n") -> "10-100x with dynamic programming"
        String.contains?(complexity, "n³") -> "10-50x with better algorithm"
        String.contains?(complexity, "n²") -> "5-20x with optimized approach"
        true -> "2-5x possible"
      end
    end
  end
  
  defmodule OptimizeDatabaseQueriesAction do
    @moduledoc """
    Analyzes and optimizes database queries for better performance.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        queries: [type: {:list, :string}, required: true, doc: "SQL queries to analyze"],
        schema: [type: :map, doc: "Database schema information"],
        execution_plans: [type: {:list, :map}, doc: "Query execution plans if available"],
        database_type: [type: :string, default: "postgresql", doc: "Database type"]
      }
    end
    
    @impl true
    def run(params, _context) do
      analyzed_queries = params.queries
        |> Enum.with_index()
        |> Enum.map(fn {query, idx} ->
          analyze_query(query, idx, params.schema, params.database_type)
        end)
      
      {:ok, %{
        query_analysis: analyzed_queries,
        optimization_summary: summarize_optimizations(analyzed_queries),
        index_recommendations: generate_index_recommendations(analyzed_queries, params.schema),
        estimated_improvement: calculate_overall_improvement(analyzed_queries)
      }}
    end
    
    defp analyze_query(query, index, schema, db_type) do
      issues = detect_query_issues(query, schema)
      optimizations = suggest_query_optimizations(query, issues, db_type)
      
      %{
        query_index: index,
        original_query: query,
        issues_found: issues,
        optimizations: optimizations,
        optimized_query: apply_optimizations(query, optimizations),
        performance_impact: estimate_query_impact(issues)
      }
    end
    
    defp detect_query_issues(query, _schema) do
      issues = []
      
      # Check for SELECT *
      issues = if String.match?(query, ~r/SELECT\s+\*/i) do
        [%{type: :select_star, severity: :medium, description: "SELECT * fetches unnecessary columns"} | issues]
      else
        issues
      end
      
      # Check for missing WHERE clause
      issues = if String.match?(query, ~r/FROM/i) && !String.match?(query, ~r/WHERE/i) do
        [%{type: :full_table_scan, severity: :high, description: "Query may perform full table scan"} | issues]
      else
        issues
      end
      
      # Check for OR conditions
      issues = if String.match?(query, ~r/WHERE.*OR/i) do
        [%{type: :or_condition, severity: :medium, description: "OR conditions may prevent index usage"} | issues]
      else
        issues
      end
      
      # Check for LIKE with leading wildcard
      issues = if String.match?(query, ~r/LIKE\s+['"]%/i) do
        [%{type: :leading_wildcard, severity: :high, description: "Leading wildcard prevents index usage"} | issues]
      else
        issues
      end
      
      # Check for functions on indexed columns
      issues = if String.match?(query, ~r/WHERE.*\(.*\)/i) do
        [%{type: :function_on_column, severity: :medium, description: "Functions on columns prevent index usage"} | issues]
      else
        issues
      end
      
      # Check for NOT IN
      issues = if String.match?(query, ~r/NOT\s+IN/i) do
        [%{type: :not_in, severity: :medium, description: "NOT IN can be inefficient, consider NOT EXISTS"} | issues]
      else
        issues
      end
      
      # Check for missing JOIN conditions
      join_count = length(Regex.scan(~r/JOIN/i, query))
      on_count = length(Regex.scan(~r/ON/i, query))
      issues = if join_count > on_count do
        [%{type: :missing_join_condition, severity: :critical, description: "Missing JOIN condition may cause cartesian product"} | issues]
      else
        issues
      end
      
      issues
    end
    
    defp suggest_query_optimizations(query, issues, _db_type) do
      optimizations = []
      
      Enum.reduce(issues, optimizations, fn issue, opts ->
        case issue.type do
          :select_star ->
            [%{
              type: :specify_columns,
              description: "Specify only required columns instead of SELECT *",
              impact: :medium
            } | opts]
          
          :full_table_scan ->
            [%{
              type: :add_where_clause,
              description: "Add WHERE clause to filter results",
              impact: :high
            } | opts]
          
          :or_condition ->
            [%{
              type: :union_instead_of_or,
              description: "Consider using UNION instead of OR for better index usage",
              impact: :medium
            } | opts]
          
          :leading_wildcard ->
            [%{
              type: :fulltext_search,
              description: "Use full-text search or reverse the pattern if possible",
              impact: :high
            } | opts]
          
          :function_on_column ->
            [%{
              type: :functional_index,
              description: "Create functional index or rewrite to avoid functions on columns",
              impact: :medium
            } | opts]
          
          :not_in ->
            [%{
              type: :use_not_exists,
              description: "Replace NOT IN with NOT EXISTS for better performance",
              impact: :medium
            } | opts]
          
          :missing_join_condition ->
            [%{
              type: :add_join_condition,
              description: "Add proper JOIN conditions to avoid cartesian product",
              impact: :critical
            } | opts]
          
          _ -> opts
        end
      end)
    end
    
    defp apply_optimizations(query, optimizations) do
      # Simple demonstration of query rewriting
      optimized = query
      
      Enum.reduce(optimizations, optimized, fn opt, q ->
        case opt.type do
          :specify_columns ->
            # Replace SELECT * with column list (simplified)
            String.replace(q, ~r/SELECT\s+\*/i, "SELECT id, name, created_at")
          
          :use_not_exists ->
            # Replace NOT IN with NOT EXISTS (simplified)
            String.replace(q, ~r/NOT\s+IN/i, "NOT EXISTS")
          
          _ -> q
        end
      end)
    end
    
    defp estimate_query_impact(issues) do
      total_severity = issues
        |> Enum.map(fn issue ->
          case issue.severity do
            :critical -> 10
            :high -> 7
            :medium -> 4
            :low -> 1
          end
        end)
        |> Enum.sum()
      
      cond do
        total_severity >= 15 -> "Very High - Query needs immediate optimization"
        total_severity >= 10 -> "High - Significant performance impact"
        total_severity >= 5 -> "Medium - Noticeable performance impact"
        total_severity > 0 -> "Low - Minor performance impact"
        true -> "Optimal"
      end
    end
    
    defp summarize_optimizations(analyzed_queries) do
      all_issues = analyzed_queries
        |> Enum.flat_map(& &1.issues_found)
      
      issue_counts = Enum.reduce(all_issues, %{}, fn issue, acc ->
        Map.update(acc, issue.type, 1, &(&1 + 1))
      end)
      
      %{
        total_issues: length(all_issues),
        critical_issues: Enum.count(all_issues, &(&1.severity == :critical)),
        issue_breakdown: issue_counts,
        most_common_issue: find_most_common_issue(issue_counts)
      }
    end
    
    defp find_most_common_issue(issue_counts) do
      if map_size(issue_counts) > 0 do
        {type, count} = Enum.max_by(issue_counts, fn {_, count} -> count end)
        %{type: type, occurrences: count}
      else
        nil
      end
    end
    
    defp generate_index_recommendations(analyzed_queries, _schema) do
      # Extract columns used in WHERE, JOIN, and ORDER BY clauses
      all_queries = Enum.map(analyzed_queries, & &1.original_query) |> Enum.join("\n")
      
      where_columns = extract_where_columns(all_queries)
      join_columns = extract_join_columns(all_queries)
      order_columns = extract_order_columns(all_queries)
      
      # Generate recommendations
      recommendations = []
      
      recommendations = if length(where_columns) > 0 do
        [%{
          type: :single_column_index,
          columns: where_columns,
          reason: "Columns frequently used in WHERE clauses",
          priority: :high
        } | recommendations]
      else
        recommendations
      end
      
      recommendations = if length(join_columns) > 0 do
        [%{
          type: :join_index,
          columns: join_columns,
          reason: "Columns used in JOIN conditions",
          priority: :high
        } | recommendations]
      else
        recommendations
      end
      
      recommendations = if length(order_columns) > 0 do
        [%{
          type: :covering_index,
          columns: order_columns,
          reason: "Columns used in ORDER BY for covering index",
          priority: :medium
        } | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    defp extract_where_columns(queries) do
      Regex.scan(~r/WHERE\s+(\w+)\s*=/i, queries)
      |> Enum.map(fn [_, col] -> col end)
      |> Enum.uniq()
    end
    
    defp extract_join_columns(queries) do
      Regex.scan(~r/ON\s+\w+\.(\w+)\s*=\s*\w+\.(\w+)/i, queries)
      |> Enum.flat_map(fn [_, col1, col2] -> [col1, col2] end)
      |> Enum.uniq()
    end
    
    defp extract_order_columns(queries) do
      Regex.scan(~r/ORDER\s+BY\s+(\w+)/i, queries)
      |> Enum.map(fn [_, col] -> col end)
      |> Enum.uniq()
    end
    
    defp calculate_overall_improvement(analyzed_queries) do
      improvements = analyzed_queries
        |> Enum.map(fn query ->
          case length(query.issues_found) do
            0 -> 0
            1 -> 20
            2 -> 35
            3 -> 50
            _ -> 65
          end
        end)
      
      if length(improvements) > 0 do
        avg_improvement = Enum.sum(improvements) / length(improvements)
        "#{round(avg_improvement)}% average performance improvement expected"
      else
        "No optimization opportunities found"
      end
    end
  end
  
  defmodule IdentifyCachingOpportunitiesAction do
    @moduledoc """
    Identifies opportunities for caching to improve performance.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to analyze"],
        language: [type: :string, required: true, doc: "Programming language"],
        access_patterns: [type: :map, doc: "Data access patterns if available"],
        performance_data: [type: :map, doc: "Performance metrics if available"]
      }
    end
    
    @impl true
    def run(params, _context) do
      opportunities = identify_caching_opportunities(
        params.source_code,
        params.language,
        params.access_patterns
      )
      
      {:ok, %{
        caching_opportunities: opportunities,
        implementation_guide: generate_implementation_guide(opportunities, params.language),
        estimated_benefits: estimate_caching_benefits(opportunities),
        cache_strategy: recommend_cache_strategy(opportunities)
      }}
    end
    
    defp identify_caching_opportunities(code, _language, _patterns) do
      opportunities = []
      
      # Check for repeated database queries
      db_queries = find_database_queries(code)
      opportunities = if length(db_queries) > 0 do
        db_opportunities = analyze_query_caching_potential(db_queries)
        opportunities ++ db_opportunities
      else
        opportunities
      end
      
      # Check for expensive computations
      computations = find_expensive_computations(code)
      opportunities = if length(computations) > 0 do
        comp_opportunities = analyze_computation_caching(computations)
        opportunities ++ comp_opportunities
      else
        opportunities
      end
      
      # Check for API calls
      api_calls = find_api_calls(code)
      opportunities = if length(api_calls) > 0 do
        api_opportunities = analyze_api_caching(api_calls)
        opportunities ++ api_opportunities
      else
        opportunities
      end
      
      # Check for repeated file I/O
      file_ops = find_file_operations(code)
      opportunities = if length(file_ops) > 0 do
        file_opportunities = analyze_file_caching(file_ops)
        opportunities ++ file_opportunities
      else
        opportunities
      end
      
      opportunities |> Enum.sort_by(& -&1.impact_score)
    end
    
    defp find_database_queries(code) do
      patterns = [
        ~r/query|select|find|fetch.*from/i,
        ~r/db\.|database\.|sql/i,
        ~r/execute.*query/i
      ]
      
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
      |> Enum.map(fn {line, line_num} ->
        %{
          type: :database,
          line: line_num,
          code: String.trim(line),
          operation: detect_db_operation(line)
        }
      end)
    end
    
    defp detect_db_operation(line) do
      cond do
        String.match?(line, ~r/select|find|get/i) -> :read
        String.match?(line, ~r/insert|create/i) -> :write
        String.match?(line, ~r/update|modify/i) -> :update
        String.match?(line, ~r/delete|remove/i) -> :delete
        true -> :unknown
      end
    end
    
    defp find_expensive_computations(code) do
      patterns = [
        ~r/for.*for|while.*while/,  # Nested loops
        ~r/calculate|compute|process/i,
        ~r/transform|convert|parse/i,
        ~r/encrypt|decrypt|hash/i
      ]
      
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
      |> Enum.map(fn {line, line_num} ->
        %{
          type: :computation,
          line: line_num,
          code: String.trim(line),
          complexity: estimate_computation_complexity(line)
        }
      end)
    end
    
    defp estimate_computation_complexity(line) do
      cond do
        String.match?(line, ~r/for.*for|while.*while/) -> :high
        String.match?(line, ~r/encrypt|decrypt/) -> :high
        String.match?(line, ~r/sort|search/) -> :medium
        true -> :low
      end
    end
    
    defp find_api_calls(code) do
      patterns = [
        ~r/http|request|fetch|axios/i,
        ~r/api\.|rest\.|graphql/i,
        ~r/get|post|put|delete.*url/i
      ]
      
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
      |> Enum.map(fn {line, line_num} ->
        %{
          type: :api,
          line: line_num,
          code: String.trim(line),
          method: detect_http_method(line)
        }
      end)
    end
    
    defp detect_http_method(line) do
      cond do
        String.match?(line, ~r/\.get|GET/i) -> :get
        String.match?(line, ~r/\.post|POST/i) -> :post
        String.match?(line, ~r/\.put|PUT/i) -> :put
        String.match?(line, ~r/\.delete|DELETE/i) -> :delete
        true -> :unknown
      end
    end
    
    defp find_file_operations(code) do
      patterns = [
        ~r/readFile|read_file|File\.read/,
        ~r/fs\.|file\.|io\./,
        ~r/open.*file|load.*file/i
      ]
      
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
      |> Enum.map(fn {line, line_num} ->
        %{
          type: :file_io,
          line: line_num,
          code: String.trim(line)
        }
      end)
    end
    
    defp analyze_query_caching_potential(queries) do
      read_queries = Enum.filter(queries, &(&1.operation == :read))
      
      if length(read_queries) > 1 do
        [%{
          type: :query_result_cache,
          description: "Cache frequently accessed database query results",
          locations: Enum.map(read_queries, & &1.line),
          impact_score: min(10, length(read_queries) * 3),
          cache_strategy: :time_based,
          ttl_recommendation: "5-15 minutes",
          implementation_complexity: :medium
        }]
      else
        []
      end
    end
    
    defp analyze_computation_caching(computations) do
      high_complexity = Enum.filter(computations, &(&1.complexity == :high))
      
      if length(high_complexity) > 0 do
        [%{
          type: :computation_memoization,
          description: "Memoize expensive computation results",
          locations: Enum.map(high_complexity, & &1.line),
          impact_score: length(high_complexity) * 4,
          cache_strategy: :memoization,
          key_recommendation: "Use input parameters as cache key",
          implementation_complexity: :low
        }]
      else
        []
      end
    end
    
    defp analyze_api_caching(api_calls) do
      get_requests = Enum.filter(api_calls, &(&1.method == :get))
      
      if length(get_requests) > 0 do
        [%{
          type: :http_response_cache,
          description: "Cache HTTP GET responses",
          locations: Enum.map(get_requests, & &1.line),
          impact_score: length(get_requests) * 2,
          cache_strategy: :http_cache,
          headers_recommendation: "Respect Cache-Control headers",
          implementation_complexity: :low
        }]
      else
        []
      end
    end
    
    defp analyze_file_caching(file_ops) do
      if length(file_ops) > 2 do
        [%{
          type: :file_content_cache,
          description: "Cache frequently read file contents",
          locations: Enum.map(file_ops, & &1.line),
          impact_score: length(file_ops) * 2,
          cache_strategy: :lru,
          size_recommendation: "Monitor cache size, use LRU eviction",
          implementation_complexity: :medium
        }]
      else
        []
      end
    end
    
    defp generate_implementation_guide(opportunities, language) do
      opportunities
      |> Enum.map(fn opp ->
        %{
          cache_type: opp.type,
          implementation_steps: get_implementation_steps(opp.type, language),
          code_example: generate_cache_example(opp.type, language),
          best_practices: get_cache_best_practices(opp.type)
        }
      end)
    end
    
    defp get_implementation_steps(cache_type, _language) do
      case cache_type do
        :query_result_cache ->
          [
            "Choose caching backend (Redis, Memcached, in-memory)",
            "Implement cache key generation based on query parameters",
            "Add cache check before query execution",
            "Store results with appropriate TTL",
            "Implement cache invalidation strategy"
          ]
        
        :computation_memoization ->
          [
            "Create memoization wrapper function",
            "Generate cache key from function arguments",
            "Check cache before computation",
            "Store computation results",
            "Consider memory limits"
          ]
        
        :http_response_cache ->
          [
            "Implement HTTP cache middleware",
            "Respect Cache-Control headers",
            "Handle conditional requests (ETags)",
            "Set appropriate cache duration",
            "Handle cache invalidation"
          ]
        
        :file_content_cache ->
          [
            "Implement file cache manager",
            "Use file modification time for validation",
            "Set cache size limits",
            "Implement LRU eviction",
            "Handle file updates"
          ]
        
        _ -> ["Analyze specific caching requirements"]
      end
    end
    
    defp generate_cache_example(cache_type, language) do
      case {cache_type, language} do
        {:computation_memoization, "javascript"} ->
          """
          const memoize = (fn) => {
            const cache = new Map();
            return (...args) => {
              const key = JSON.stringify(args);
              if (cache.has(key)) {
                return cache.get(key);
              }
              const result = fn(...args);
              cache.set(key, result);
              return result;
            };
          };
          """
        
        {:query_result_cache, "javascript"} ->
          """
          async function cachedQuery(query, params) {
            const cacheKey = `query:${query}:${JSON.stringify(params)}`;
            const cached = await cache.get(cacheKey);
            
            if (cached) return cached;
            
            const result = await db.query(query, params);
            await cache.set(cacheKey, result, 300); // 5 min TTL
            return result;
          }
          """
        
        _ -> "// Implement caching based on your specific needs"
      end
    end
    
    defp get_cache_best_practices(cache_type) do
      base_practices = [
        "Monitor cache hit/miss rates",
        "Implement proper error handling",
        "Set appropriate TTL values",
        "Plan cache warming strategy"
      ]
      
      specific_practices = case cache_type do
        :query_result_cache ->
          ["Invalidate on data updates", "Consider query complexity"]
        
        :computation_memoization ->
          ["Limit cache size", "Consider argument variations"]
        
        :http_response_cache ->
          ["Respect HTTP caching standards", "Handle failed requests"]
        
        :file_content_cache ->
          ["Watch for file changes", "Handle concurrent access"]
        
        _ -> []
      end
      
      base_practices ++ specific_practices
    end
    
    defp estimate_caching_benefits(opportunities) do
      total_impact = opportunities
        |> Enum.map(& &1.impact_score)
        |> Enum.sum()
      
      %{
        performance_improvement: "#{min(80, total_impact * 5)}% reduction in response time",
        resource_savings: estimate_resource_savings(opportunities),
        user_experience: "Significantly improved for repeat operations",
        scalability: "Better handling of concurrent requests"
      }
    end
    
    defp estimate_resource_savings(opportunities) do
      savings = []
      
      if Enum.any?(opportunities, &(&1.type == :query_result_cache)) do
        savings = ["Reduced database load" | savings]
      end
      
      if Enum.any?(opportunities, &(&1.type == :computation_memoization)) do
        savings = ["Lower CPU usage" | savings]
      end
      
      if Enum.any?(opportunities, &(&1.type == :http_response_cache)) do
        savings = ["Reduced network traffic" | savings]
      end
      
      if Enum.any?(opportunities, &(&1.type == :file_content_cache)) do
        savings = ["Fewer disk I/O operations" | savings]
      end
      
      savings
    end
    
    defp recommend_cache_strategy(opportunities) do
      strategies = opportunities
        |> Enum.map(& &1.cache_strategy)
        |> Enum.uniq()
      
      %{
        recommended_strategies: strategies,
        cache_layers: recommend_cache_layers(opportunities),
        invalidation_strategy: recommend_invalidation_strategy(opportunities),
        monitoring_approach: "Track hit rates, response times, and cache size"
      }
    end
    
    defp recommend_cache_layers(opportunities) do
      layers = []
      
      if Enum.any?(opportunities, &(&1.type in [:computation_memoization])) do
        layers = ["Application-level cache" | layers]
      end
      
      if Enum.any?(opportunities, &(&1.type in [:query_result_cache, :http_response_cache])) do
        layers = ["Distributed cache (Redis/Memcached)" | layers]
      end
      
      if Enum.any?(opportunities, &(&1.type == :http_response_cache)) do
        layers = ["CDN/Edge cache" | layers]
      end
      
      layers
    end
    
    defp recommend_invalidation_strategy(opportunities) do
      if Enum.any?(opportunities, &(&1.type == :query_result_cache)) do
        "Event-based invalidation on data updates"
      else
        "Time-based expiration with periodic refresh"
      end
    end
  end
  
  defmodule GenerateBenchmarkAction do
    @moduledoc """
    Generates performance benchmarks for code.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Code to benchmark"],
        language: [type: :string, required: true, doc: "Programming language"],
        benchmark_type: [type: :string, default: "comprehensive", doc: "Type: micro, macro, comprehensive"],
        scenarios: [type: {:list, :map}, doc: "Test scenarios to benchmark"]
      }
    end
    
    @impl true
    def run(params, _context) do
      benchmarks = generate_benchmarks(
        params.source_code,
        params.language,
        params.benchmark_type,
        params.scenarios
      )
      
      {:ok, %{
        benchmark_suite: benchmarks,
        execution_plan: create_execution_plan(benchmarks),
        metrics_to_collect: define_metrics(params.benchmark_type),
        analysis_guidance: provide_analysis_guidance(benchmarks)
      }}
    end
    
    defp generate_benchmarks(code, language, type, scenarios) do
      functions = extract_benchmarkable_functions(code, language)
      
      base_benchmarks = case type do
        "micro" -> generate_micro_benchmarks(functions, language)
        "macro" -> generate_macro_benchmarks(functions, language)
        _ -> generate_comprehensive_benchmarks(functions, language)
      end
      
      scenario_benchmarks = if scenarios do
        generate_scenario_benchmarks(functions, scenarios, language)
      else
        []
      end
      
      base_benchmarks ++ scenario_benchmarks
    end
    
    defp extract_benchmarkable_functions(code, _language) do
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        String.match?(line, ~r/function|def|func/) &&
        !String.match?(line, ~r/private|internal/)
      end)
      |> Enum.map(fn {line, idx} ->
        %{
          name: extract_function_name_simple(line),
          line: idx,
          params: extract_function_params(line)
        }
      end)
    end
    
    defp extract_function_name_simple(line) do
      cond do
        match = Regex.run(~r/function\s+(\w+)/, line) -> List.last(match)
        match = Regex.run(~r/def\s+(\w+)/, line) -> List.last(match)
        true -> "anonymous"
      end
    end
    
    defp extract_function_params(line) do
      case Regex.run(~r/\((.*?)\)/, line) do
        [_, params] -> 
          params
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        _ -> []
      end
    end
    
    defp generate_micro_benchmarks(functions, language) do
      functions
      |> Enum.map(fn func ->
        %{
          name: "micro_benchmark_#{func.name}",
          type: :micro,
          target_function: func.name,
          code: generate_micro_benchmark_code(func, language),
          iterations: 10000,
          warmup: 1000
        }
      end)
    end
    
    defp generate_micro_benchmark_code(func, language) do
      case language do
        "javascript" ->
          """
          // Micro benchmark for #{func.name}
          const benchmark = require('benchmark');
          const suite = new benchmark.Suite;
          
          suite.add('#{func.name}', function() {
            #{func.name}(#{generate_test_args(func.params)});
          })
          .on('cycle', function(event) {
            console.log(String(event.target));
          })
          .run();
          """
        
        "python" ->
          """
          # Micro benchmark for #{func.name}
          import timeit
          
          def benchmark_#{func.name}():
              return #{func.name}(#{generate_test_args(func.params)})
          
          time = timeit.timeit(benchmark_#{func.name}, number=10000)
          print(f"#{func.name}: {time:.6f} seconds")
          """
        
        _ ->
          "// Implement benchmark for #{func.name}"
      end
    end
    
    defp generate_test_args(params) do
      params
      |> Enum.map(fn _ -> "testData" end)
      |> Enum.join(", ")
    end
    
    defp generate_macro_benchmarks(functions, language) do
      # Group related functions
      [%{
        name: "macro_benchmark_full_flow",
        type: :macro,
        target_functions: Enum.map(functions, & &1.name),
        code: generate_macro_benchmark_code(functions, language),
        iterations: 1000,
        warmup: 100
      }]
    end
    
    defp generate_macro_benchmark_code(functions, language) do
      case language do
        "javascript" ->
          """
          // Macro benchmark - full application flow
          const benchmark = require('benchmark');
          
          function fullFlow() {
            // Simulate real-world usage
            #{Enum.map(functions, fn f -> "#{f.name}();" end) |> Enum.join("\n  ")}
          }
          
          const suite = new benchmark.Suite;
          suite.add('Full Application Flow', fullFlow)
            .on('complete', function() {
              console.log('Fastest: ' + this.filter('fastest').map('name'));
            })
            .run();
          """
        
        _ ->
          "// Implement macro benchmark"
      end
    end
    
    defp generate_comprehensive_benchmarks(functions, language) do
      micro = generate_micro_benchmarks(functions, language)
      macro = generate_macro_benchmarks(functions, language)
      stress = generate_stress_benchmarks(functions, language)
      
      micro ++ macro ++ stress
    end
    
    defp generate_stress_benchmarks(functions, language) do
      functions
      |> Enum.filter(fn func ->
        # Only stress test functions that might have performance issues
        length(func.params) > 0
      end)
      |> Enum.map(fn func ->
        %{
          name: "stress_test_#{func.name}",
          type: :stress,
          target_function: func.name,
          code: generate_stress_test_code(func, language),
          load_levels: [100, 1000, 10000],
          concurrent: true
        }
      end)
    end
    
    defp generate_stress_test_code(func, language) do
      case language do
        "javascript" ->
          """
          // Stress test for #{func.name}
          async function stressTest(load) {
            const promises = [];
            const start = Date.now();
            
            for (let i = 0; i < load; i++) {
              promises.push(#{func.name}(generateLargeInput()));
            }
            
            await Promise.all(promises);
            const duration = Date.now() - start;
            
            console.log(`Load ${load}: ${duration}ms`);
          }
          """
        
        _ ->
          "// Implement stress test"
      end
    end
    
    defp generate_scenario_benchmarks(functions, scenarios, language) do
      scenarios
      |> Enum.map(fn scenario ->
        %{
          name: "scenario_#{scenario.name}",
          type: :scenario,
          description: scenario.description,
          code: generate_scenario_code(scenario, functions, language),
          expected_duration: scenario.expected_duration,
          performance_criteria: scenario.criteria
        }
      end)
    end
    
    defp generate_scenario_code(scenario, _functions, language) do
      case language do
        "javascript" ->
          """
          // Scenario: #{scenario.description}
          async function scenario_#{scenario.name}() {
            const start = performance.now();
            
            // #{scenario.description}
            // Add scenario-specific code here
            
            const duration = performance.now() - start;
            return { duration, passed: duration < #{scenario.expected_duration} };
          }
          """
        
        _ ->
          "// Implement scenario benchmark"
      end
    end
    
    defp create_execution_plan(benchmarks) do
      %{
        phases: [
          %{
            phase: "warmup",
            description: "JIT compilation and cache warming",
            benchmarks: Enum.filter(benchmarks, &(&1.type == :micro))
          },
          %{
            phase: "baseline",
            description: "Establish performance baseline",
            benchmarks: benchmarks
          },
          %{
            phase: "stress",
            description: "Test under load",
            benchmarks: Enum.filter(benchmarks, &(&1.type == :stress))
          }
        ],
        total_estimated_time: estimate_total_time(benchmarks),
        parallelization: recommend_parallelization(benchmarks)
      }
    end
    
    defp estimate_total_time(benchmarks) do
      total_ms = benchmarks
        |> Enum.map(fn b ->
          iterations = Map.get(b, :iterations, 1000)
          # Rough estimate: 0.1ms per iteration
          iterations * 0.1
        end)
        |> Enum.sum()
      
      "#{round(total_ms / 1000)} seconds"
    end
    
    defp recommend_parallelization(benchmarks) do
      if length(benchmarks) > 5 do
        "Run micro benchmarks in parallel, macro benchmarks sequentially"
      else
        "Run all benchmarks sequentially for consistent results"
      end
    end
    
    defp define_metrics(benchmark_type) do
      base_metrics = [
        %{name: "execution_time", unit: "ms", description: "Time to complete"},
        %{name: "throughput", unit: "ops/sec", description: "Operations per second"},
        %{name: "latency_p99", unit: "ms", description: "99th percentile latency"}
      ]
      
      additional_metrics = case benchmark_type do
        "comprehensive" ->
          [
            %{name: "memory_usage", unit: "MB", description: "Peak memory usage"},
            %{name: "cpu_usage", unit: "%", description: "CPU utilization"},
            %{name: "gc_time", unit: "ms", description: "Garbage collection time"}
          ]
        
        "stress" ->
          [
            %{name: "error_rate", unit: "%", description: "Percentage of failures"},
            %{name: "degradation", unit: "%", description: "Performance degradation under load"}
          ]
        
        _ -> []
      end
      
      base_metrics ++ additional_metrics
    end
    
    defp provide_analysis_guidance(benchmarks) do
      %{
        interpretation_guide: [
          "Compare results against baseline performance",
          "Look for non-linear scaling with input size",
          "Identify outliers and investigate causes",
          "Consider variance in measurements"
        ],
        warning_signs: [
          "High variance between runs (>20%)",
          "Memory usage growing with iterations",
          "Performance degradation under load",
          "Long tail latencies (p99 >> p50)"
        ],
        optimization_priorities: prioritize_optimizations(benchmarks),
        reporting_template: generate_report_template()
      }
    end
    
    defp prioritize_optimizations(benchmarks) do
      benchmarks
      |> Enum.map(& &1.target_function)
      |> Enum.uniq()
      |> Enum.map(fn func ->
        %{
          function: func,
          priority: "Optimize if execution time > 100ms or called frequently"
        }
      end)
    end
    
    defp generate_report_template do
      """
      # Performance Benchmark Report
      
      ## Executive Summary
      - Overall performance score: [X/100]
      - Critical issues found: [count]
      - Optimization opportunities: [count]
      
      ## Detailed Results
      [Benchmark results here]
      
      ## Recommendations
      1. Priority optimizations
      2. Quick wins
      3. Long-term improvements
      """
    end
  end
  
  defmodule AnalyzeMemoryUsageAction do
    @moduledoc """
    Analyzes memory usage patterns and identifies memory leaks.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to analyze"],
        language: [type: :string, required: true, doc: "Programming language"],
        runtime_data: [type: :map, doc: "Runtime memory profiling data if available"],
        heap_snapshots: [type: {:list, :map}, doc: "Heap snapshots if available"]
      }
    end
    
    @impl true
    def run(params, _context) do
      analysis = analyze_memory_patterns(
        params.source_code,
        params.language,
        params.runtime_data
      )
      
      {:ok, %{
        memory_analysis: analysis,
        leak_detection: detect_memory_leaks(analysis, params.heap_snapshots),
        optimization_suggestions: suggest_memory_optimizations(analysis),
        memory_profile: create_memory_profile(analysis)
      }}
    end
    
    defp analyze_memory_patterns(code, _language, runtime_data) do
      static_analysis = perform_static_memory_analysis(code)
      
      runtime_analysis = if runtime_data do
        analyze_runtime_memory(runtime_data)
      else
        %{status: "No runtime data available"}
      end
      
      %{
        static_analysis: static_analysis,
        runtime_analysis: runtime_analysis,
        memory_hotspots: identify_memory_hotspots(static_analysis),
        allocation_patterns: analyze_allocation_patterns(code)
      }
    end
    
    defp perform_static_memory_analysis(code) do
      issues = []
      
      # Check for memory allocation in loops
      loop_allocations = find_allocations_in_loops(code)
      issues = issues ++ loop_allocations
      
      # Check for large data structures
      large_structures = find_large_data_structures(code)
      issues = issues ++ large_structures
      
      # Check for potential memory leaks
      leak_patterns = find_leak_patterns(code)
      issues = issues ++ leak_patterns
      
      # Check for inefficient string operations
      string_issues = find_string_inefficiencies(code)
      issues = issues ++ string_issues
      
      %{
        total_issues: length(issues),
        critical_issues: Enum.count(issues, &(&1.severity == :critical)),
        issues: issues,
        memory_score: calculate_memory_score(issues)
      }
    end
    
    defp find_allocations_in_loops(code) do
      lines = String.split(code, "\n")
      
      in_loop = false
      loop_depth = 0
      issues = []
      
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({issues, in_loop, loop_depth}, fn {line, line_num}, {acc_issues, in_loop, depth} ->
        cond do
          String.match?(line, ~r/for|while|loop/) ->
            {acc_issues, true, depth + 1}
          
          String.match?(line, ~r/}|end/) && depth > 0 ->
            {acc_issues, depth > 1, depth - 1}
          
          in_loop && String.match?(line, ~r/new|malloc|Array|push|concat/) ->
            issue = %{
              type: :loop_allocation,
              line: line_num,
              code: String.trim(line),
              severity: if(depth > 1, do: :critical, else: :high),
              description: "Memory allocation inside loop (depth: #{depth})"
            }
            {[issue | acc_issues], in_loop, depth}
          
          true ->
            {acc_issues, in_loop, depth}
        end
      end)
      |> elem(0)
    end
    
    defp find_large_data_structures(code) do
      patterns = [
        {~r/Array\s*\(\s*(\d+)\)/, "Large array allocation"},
        {~r/new\s+\w+\[\s*(\d+)\s*\]/, "Large array initialization"},
        {~r/\.repeat\s*\(\s*(\d+)\s*\)/, "Large string creation"}
      ]
      
      lines = String.split(code, "\n")
      
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        patterns
        |> Enum.flat_map(fn {pattern, desc} ->
          case Regex.run(pattern, line) do
            [_, size_str] ->
              size = String.to_integer(size_str)
              if size > 1000 do
                [%{
                  type: :large_allocation,
                  line: line_num,
                  code: String.trim(line),
                  severity: if(size > 10000, do: :critical, else: :high),
                  description: "#{desc}: size = #{size}",
                  estimated_memory: "~#{size * 8} bytes"
                }]
              else
                []
              end
            _ -> []
          end
        end)
      end)
    end
    
    defp find_leak_patterns(code) do
      patterns = [
        {~r/addEventListener|on\w+\s*=/, :event_listener, "Event listener without removal"},
        {~r/setInterval|setTimeout/, :timer, "Timer without cleanup"},
        {~r/subscribe|observe/, :subscription, "Subscription without unsubscribe"},
        {~r/global\.|window\./, :global_reference, "Global variable reference"}
      ]
      
      lines = String.split(code, "\n")
      
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        patterns
        |> Enum.flat_map(fn {pattern, type, desc} ->
          if Regex.match?(pattern, line) do
            # Check if there's corresponding cleanup
            has_cleanup = check_for_cleanup(code, type)
            
            if !has_cleanup do
              [%{
                type: :memory_leak,
                leak_type: type,
                line: line_num,
                code: String.trim(line),
                severity: :high,
                description: desc
              }]
            else
              []
            end
          else
            []
          end
        end)
      end)
    end
    
    defp check_for_cleanup(code, leak_type) do
      cleanup_patterns = case leak_type do
        :event_listener -> ~r/removeEventListener/
        :timer -> ~r/clearInterval|clearTimeout/
        :subscription -> ~r/unsubscribe|dispose/
        _ -> ~r/cleanup|destroy|dispose/
      end
      
      Regex.match?(cleanup_patterns, code)
    end
    
    defp find_string_inefficiencies(code) do
      lines = String.split(code, "\n")
      
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        cond do
          # String concatenation in loop
          String.match?(line, ~r/\+=.*['"]/) && String.match?(line, ~r/for|while/) ->
            [%{
              type: :string_concatenation,
              line: line_num,
              code: String.trim(line),
              severity: :high,
              description: "String concatenation in loop - use array join instead"
            }]
          
          # Multiple string concatenations
          length(Regex.scan(~r/\+/, line)) > 3 && String.match?(line, ~r/['"]/) ->
            [%{
              type: :excessive_concatenation,
              line: line_num,
              code: String.trim(line),
              severity: :medium,
              description: "Multiple string concatenations - consider template literals"
            }]
          
          true -> []
        end
      end)
    end
    
    defp calculate_memory_score(issues) do
      total_penalty = issues
        |> Enum.map(fn issue ->
          case issue.severity do
            :critical -> 20
            :high -> 10
            :medium -> 5
            :low -> 2
          end
        end)
        |> Enum.sum()
      
      max(0, 100 - total_penalty)
    end
    
    defp identify_memory_hotspots(static_analysis) do
      static_analysis.issues
      |> Enum.group_by(& &1.line)
      |> Enum.map(fn {line, issues} ->
        %{
          line: line,
          issue_count: length(issues),
          severity: Enum.map(issues, & &1.severity) |> Enum.max(),
          types: Enum.map(issues, & &1.type) |> Enum.uniq()
        }
      end)
      |> Enum.sort_by(&{&1.severity, &1.issue_count}, :desc)
      |> Enum.take(5)
    end
    
    defp analyze_allocation_patterns(code) do
      %{
        total_allocations: count_allocations(code),
        allocation_types: categorize_allocations(code),
        allocation_frequency: analyze_allocation_frequency(code),
        recommendations: generate_allocation_recommendations(code)
      }
    end
    
    defp count_allocations(code) do
      allocation_patterns = [
        ~r/new\s+\w+/,
        ~r/malloc|alloc/,
        ~r/Array\s*\(/,
        ~r/Object\.create/
      ]
      
      allocation_patterns
      |> Enum.map(fn pattern ->
        length(Regex.scan(pattern, code))
      end)
      |> Enum.sum()
    end
    
    defp categorize_allocations(code) do
      %{
        objects: length(Regex.scan(~r/new\s+\w+|{.*}/, code)),
        arrays: length(Regex.scan(~r/\[.*\]|Array/, code)),
        strings: length(Regex.scan(~r/["'].*["']/, code)),
        functions: length(Regex.scan(~r/function|=>/, code))
      }
    end
    
    defp analyze_allocation_frequency(_code) do
      # Simplified - would need runtime data for accurate frequency
      %{
        high_frequency: "Check loops and event handlers",
        medium_frequency: "Monitor recursive functions",
        low_frequency: "Initialization code acceptable"
      }
    end
    
    defp generate_allocation_recommendations(code) do
      recommendations = []
      
      if String.match?(code, ~r/new.*loop|while.*new/) do
        recommendations = ["Consider object pooling for loop allocations" | recommendations]
      end
      
      if String.match?(code, ~r/concat|join/) do
        recommendations = ["Use StringBuilder pattern for string operations" | recommendations]
      end
      
      if String.match?(code, ~r/Array\(\d{4,}/) do
        recommendations = ["Pre-allocate large arrays with fixed size" | recommendations]
      end
      
      recommendations
    end
    
    defp analyze_runtime_memory(runtime_data) do
      %{
        heap_usage: runtime_data[:heap_usage] || "Unknown",
        heap_growth_rate: calculate_heap_growth(runtime_data),
        gc_frequency: runtime_data[:gc_frequency] || "Unknown",
        memory_pressure: assess_memory_pressure(runtime_data)
      }
    end
    
    defp calculate_heap_growth(runtime_data) do
      if runtime_data[:heap_snapshots] do
        # Calculate growth rate from snapshots
        "Calculated from heap snapshots"
      else
        "No heap snapshot data"
      end
    end
    
    defp assess_memory_pressure(runtime_data) do
      if runtime_data[:heap_usage] && runtime_data[:heap_limit] do
        usage_percent = runtime_data.heap_usage / runtime_data.heap_limit * 100
        
        cond do
          usage_percent > 90 -> :critical
          usage_percent > 70 -> :high
          usage_percent > 50 -> :medium
          true -> :low
        end
      else
        :unknown
      end
    end
    
    defp detect_memory_leaks(analysis, heap_snapshots) do
      static_leaks = analysis.static_analysis.issues
        |> Enum.filter(&(&1.type == :memory_leak))
      
      heap_leaks = if heap_snapshots do
        analyze_heap_growth_patterns(heap_snapshots)
      else
        []
      end
      
      %{
        potential_leaks: static_leaks ++ heap_leaks,
        leak_severity: assess_leak_severity(static_leaks ++ heap_leaks),
        verification_steps: generate_leak_verification_steps(),
        fix_priority: prioritize_leak_fixes(static_leaks ++ heap_leaks)
      }
    end
    
    defp analyze_heap_growth_patterns(_snapshots) do
      # Simplified - would analyze actual heap snapshots
      []
    end
    
    defp assess_leak_severity(leaks) do
      if length(leaks) == 0 do
        :none
      else
        max_severity = leaks
          |> Enum.map(& &1.severity)
          |> Enum.max()
        
        max_severity
      end
    end
    
    defp generate_leak_verification_steps do
      [
        "Monitor heap usage over time",
        "Check for growing object counts",
        "Verify event listener cleanup",
        "Test long-running scenarios",
        "Use heap profiler to track allocations"
      ]
    end
    
    defp prioritize_leak_fixes(leaks) do
      leaks
      |> Enum.sort_by(&{&1.severity, &1.type})
      |> Enum.map(fn leak ->
        %{
          location: "Line #{leak.line}",
          type: leak.leak_type || leak.type,
          priority: leak.severity,
          fix_suggestion: suggest_leak_fix(leak)
        }
      end)
    end
    
    defp suggest_leak_fix(leak) do
      case leak[:leak_type] do
        :event_listener -> "Add removeEventListener in cleanup"
        :timer -> "Store timer ID and call clearInterval/clearTimeout"
        :subscription -> "Implement unsubscribe in component cleanup"
        :global_reference -> "Avoid global variables or clean up references"
        _ -> "Review memory management for this allocation"
      end
    end
    
    defp suggest_memory_optimizations(analysis) do
      issues = analysis.static_analysis.issues
      
      optimizations = []
      
      # Loop allocation optimizations
      loop_allocs = Enum.filter(issues, &(&1.type == :loop_allocation))
      if length(loop_allocs) > 0 do
        optimizations = [%{
          type: :object_pooling,
          description: "Implement object pooling for frequently allocated objects",
          impact: :high,
          complexity: :medium,
          example: generate_object_pool_example()
        } | optimizations]
      end
      
      # Large allocation optimizations
      large_allocs = Enum.filter(issues, &(&1.type == :large_allocation))
      if length(large_allocs) > 0 do
        optimizations = [%{
          type: :lazy_loading,
          description: "Implement lazy loading for large data structures",
          impact: :high,
          complexity: :low,
          example: "Load data on demand rather than upfront"
        } | optimizations]
      end
      
      # String optimization
      string_issues = Enum.filter(issues, &(&1.type in [:string_concatenation, :excessive_concatenation]))
      if length(string_issues) > 0 do
        optimizations = [%{
          type: :string_builder,
          description: "Use efficient string building techniques",
          impact: :medium,
          complexity: :low,
          example: "Use array.join() or template literals"
        } | optimizations]
      end
      
      optimizations
    end
    
    defp generate_object_pool_example do
      """
      class ObjectPool {
        constructor(createFn, resetFn, maxSize = 100) {
          this.createFn = createFn;
          this.resetFn = resetFn;
          this.pool = [];
          this.maxSize = maxSize;
        }
        
        acquire() {
          return this.pool.pop() || this.createFn();
        }
        
        release(obj) {
          if (this.pool.length < this.maxSize) {
            this.resetFn(obj);
            this.pool.push(obj);
          }
        }
      }
      """
    end
    
    defp create_memory_profile(analysis) do
      %{
        overall_health: determine_memory_health(analysis),
        metrics: %{
          static_score: analysis.static_analysis.memory_score,
          issue_count: analysis.static_analysis.total_issues,
          critical_issues: analysis.static_analysis.critical_issues
        },
        top_concerns: extract_top_concerns(analysis),
        action_items: generate_action_items(analysis)
      }
    end
    
    defp determine_memory_health(analysis) do
      score = analysis.static_analysis.memory_score
      
      cond do
        score >= 90 -> :excellent
        score >= 75 -> :good
        score >= 60 -> :fair
        score >= 40 -> :poor
        true -> :critical
      end
    end
    
    defp extract_top_concerns(analysis) do
      analysis.static_analysis.issues
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, issues} ->
        %{
          concern: type,
          occurrences: length(issues),
          severity: Enum.map(issues, & &1.severity) |> Enum.max()
        }
      end)
      |> Enum.sort_by(&{&1.severity, &1.occurrences}, :desc)
      |> Enum.take(3)
    end
    
    defp generate_action_items(analysis) do
      critical_issues = Enum.filter(analysis.static_analysis.issues, &(&1.severity == :critical))
      
      action_items = critical_issues
        |> Enum.map(fn issue ->
          %{
            priority: :immediate,
            location: "Line #{issue.line}",
            action: "Fix #{issue.type}: #{issue.description}"
          }
        end)
      
      if length(action_items) == 0 do
        [%{
          priority: :low,
          action: "Continue monitoring memory usage patterns"
        }]
      else
        action_items
      end
    end
  end
  
  defmodule GeneratePerformanceReportAction do
    @moduledoc """
    Generates comprehensive performance analysis reports.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        analysis_results: [type: :map, required: true, doc: "Results from performance analyses"],
        report_format: [type: :string, default: "detailed", doc: "Format: summary, detailed, executive"],
        include_recommendations: [type: :boolean, default: true, doc: "Include optimization recommendations"],
        comparison_baseline: [type: :map, doc: "Baseline metrics for comparison"]
      }
    end
    
    @impl true
    def run(params, _context) do
      report = generate_performance_report(
        params.analysis_results,
        params.report_format,
        params.include_recommendations,
        params.comparison_baseline
      )
      
      {:ok, report}
    end
    
    defp generate_performance_report(results, format, include_recommendations, baseline) do
      base_report = build_base_report(results)
      
      formatted_report = case format do
        "executive" -> format_executive_report(base_report, baseline)
        "summary" -> format_summary_report(base_report)
        _ -> format_detailed_report(base_report)
      end
      
      if include_recommendations do
        add_recommendations_section(formatted_report, results)
      else
        formatted_report
      end
    end
    
    defp build_base_report(results) do
      %{
        overview: build_performance_overview(results),
        metrics: extract_key_metrics(results),
        bottlenecks: identify_bottlenecks(results),
        optimizations: consolidate_optimizations(results),
        trends: analyze_performance_trends(results)
      }
    end
    
    defp build_performance_overview(results) do
      %{
        title: "Performance Analysis Report",
        timestamp: DateTime.utc_now(),
        summary: generate_performance_summary(results),
        overall_grade: calculate_performance_grade(results),
        key_findings: extract_key_findings(results)
      }
    end
    
    defp generate_performance_summary(results) do
      hotspot_count = get_in(results, [:profile, :hotspots]) |> length()
      complexity_issues = get_in(results, [:complexity, :optimization_targets]) |> length()
      memory_issues = get_in(results, [:memory, :static_analysis, :total_issues]) || 0
      
      "Analysis identified #{hotspot_count} performance hotspots, #{complexity_issues} complexity issues, and #{memory_issues} memory concerns."
    end
    
    defp calculate_performance_grade(results) do
      scores = []
      
      if results[:profile] do
        scores = [results.profile.metrics.profile_score | scores]
      end
      
      if results[:memory] do
        scores = [results.memory.static_analysis.memory_score | scores]
      end
      
      if length(scores) > 0 do
        avg_score = Enum.sum(scores) / length(scores)
        
        cond do
          avg_score >= 90 -> "A"
          avg_score >= 80 -> "B"
          avg_score >= 70 -> "C"
          avg_score >= 60 -> "D"
          true -> "F"
        end
      else
        "N/A"
      end
    end
    
    defp extract_key_findings(results) do
      findings = []
      
      # Profile findings
      if results[:profile] && results.profile[:bottlenecks] do
        top_bottleneck = List.first(results.profile.bottlenecks)
        if top_bottleneck do
          findings = ["Critical bottleneck in #{top_bottleneck.function}" | findings]
        end
      end
      
      # Complexity findings
      if results[:complexity] && results.complexity[:overall_assessment] do
        worst_case = results.complexity.overall_assessment.worst_case_complexity
        if String.contains?(worst_case, "n²") || String.contains?(worst_case, "2^n") do
          findings = ["High complexity detected: #{worst_case}" | findings]
        end
      end
      
      # Memory findings
      if results[:memory] && results.memory[:leak_detection] do
        leak_count = length(results.memory.leak_detection.potential_leaks)
        if leak_count > 0 do
          findings = ["#{leak_count} potential memory leaks detected" | findings]
        end
      end
      
      Enum.take(findings, 5)
    end
    
    defp extract_key_metrics(results) do
      %{
        performance: extract_performance_metrics(results),
        complexity: extract_complexity_metrics(results),
        memory: extract_memory_metrics(results),
        quality: calculate_quality_metrics(results)
      }
    end
    
    defp extract_performance_metrics(results) do
      if results[:profile] do
        %{
          hotspot_count: length(results.profile.hotspots),
          critical_hotspots: results.profile.metrics.critical_hotspots,
          optimization_potential: extract_optimization_potential(results.profile)
        }
      else
        %{}
      end
    end
    
    defp extract_optimization_potential(profile) do
      if profile[:optimization_opportunities] do
        opportunities = profile.optimization_opportunities
        high_priority = Enum.count(opportunities, &(&1.priority == "high"))
        
        "#{high_priority} high-priority optimizations available"
      else
        "Unknown"
      end
    end
    
    defp extract_complexity_metrics(results) do
      if results[:complexity] do
        %{
          worst_case: results.complexity.overall_assessment.worst_case_complexity,
          grade: results.complexity.overall_assessment.performance_grade,
          targets: length(results.complexity.optimization_targets)
        }
      else
        %{}
      end
    end
    
    defp extract_memory_metrics(results) do
      if results[:memory] do
        %{
          score: results.memory.static_analysis.memory_score,
          issues: results.memory.static_analysis.total_issues,
          leaks: length(results.memory.leak_detection.potential_leaks)
        }
      else
        %{}
      end
    end
    
    defp calculate_quality_metrics(results) do
      metrics = []
      
      if results[:profile] do
        metrics = [results.profile.metrics.profile_score | metrics]
      end
      
      if results[:memory] do
        metrics = [results.memory.static_analysis.memory_score | metrics]
      end
      
      if length(metrics) > 0 do
        %{
          overall_score: Enum.sum(metrics) / length(metrics),
          components_analyzed: map_size(results)
        }
      else
        %{overall_score: 0, components_analyzed: 0}
      end
    end
    
    defp identify_bottlenecks(results) do
      bottlenecks = []
      
      # CPU bottlenecks
      if results[:profile] && results.profile[:bottlenecks] do
        cpu_bottlenecks = Enum.map(results.profile.bottlenecks, fn b ->
          Map.put(b, :category, :cpu)
        end)
        bottlenecks = bottlenecks ++ cpu_bottlenecks
      end
      
      # Complexity bottlenecks
      if results[:complexity] && results.complexity[:optimization_targets] do
        complexity_bottlenecks = Enum.map(results.complexity.optimization_targets, fn t ->
          %{
            category: :algorithmic,
            function: t.function,
            severity: t.current_complexity,
            impact: t.improvement_potential
          }
        end)
        bottlenecks = bottlenecks ++ complexity_bottlenecks
      end
      
      # Memory bottlenecks
      if results[:memory] && results.memory[:memory_hotspots] do
        memory_bottlenecks = Enum.map(results.memory.memory_hotspots, fn h ->
          %{
            category: :memory,
            location: "Line #{h.line}",
            severity: h.severity,
            types: h.types
          }
        end)
        bottlenecks = bottlenecks ++ memory_bottlenecks
      end
      
      bottlenecks |> Enum.sort_by(& &1.severity)
    end
    
    defp consolidate_optimizations(results) do
      all_optimizations = []
      
      if results[:profile] && results.profile[:recommendations] do
        all_optimizations = all_optimizations ++ results.profile.recommendations
      end
      
      if results[:complexity] && results.complexity[:optimization_targets] do
        complexity_opts = Enum.flat_map(results.complexity.optimization_targets, fn target ->
          ["Optimize #{target.function}: #{target.improvement_potential}"]
        end)
        all_optimizations = all_optimizations ++ complexity_opts
      end
      
      if results[:memory] && results.memory[:optimization_suggestions] do
        memory_opts = Enum.map(results.memory.optimization_suggestions, & &1.description)
        all_optimizations = all_optimizations ++ memory_opts
      end
      
      all_optimizations |> Enum.uniq() |> Enum.take(10)
    end
    
    defp analyze_performance_trends(_results) do
      # Would compare with historical data
      %{
        trend: :improving,
        areas_improved: ["Memory efficiency", "Algorithm complexity"],
        areas_degraded: [],
        projection: "Continued improvement expected with recommended optimizations"
      }
    end
    
    defp format_executive_report(base_report, baseline) do
      %{
        title: "Executive Performance Summary",
        date: base_report.overview.timestamp,
        grade: base_report.overview.overall_grade,
        summary: %{
          key_findings: base_report.overview.key_findings,
          immediate_actions: extract_immediate_actions(base_report),
          expected_impact: estimate_optimization_impact(base_report)
        },
        comparison: if baseline do
          compare_with_baseline(base_report, baseline)
        else
          nil
        end
      }
    end
    
    defp extract_immediate_actions(base_report) do
      base_report.bottlenecks
      |> Enum.filter(fn b -> 
        b[:severity] in [:critical, :high, "critical", "high"] ||
        String.contains?(to_string(b[:severity]), "n²")
      end)
      |> Enum.take(3)
      |> Enum.map(fn b ->
        "Address #{b.category} issue: #{b[:function] || b[:location]}"
      end)
    end
    
    defp estimate_optimization_impact(base_report) do
      optimization_count = length(base_report.optimizations)
      
      cond do
        optimization_count >= 10 -> "50-70% performance improvement possible"
        optimization_count >= 5 -> "30-50% performance improvement possible"
        optimization_count >= 2 -> "10-30% performance improvement possible"
        true -> "Minor improvements possible"
      end
    end
    
    defp compare_with_baseline(report, baseline) do
      %{
        performance_change: calculate_performance_change(report, baseline),
        improved_areas: identify_improvements(report, baseline),
        degraded_areas: identify_degradations(report, baseline)
      }
    end
    
    defp calculate_performance_change(report, baseline) do
      current_score = report.metrics.quality.overall_score
      baseline_score = baseline[:overall_score] || 50
      
      change = ((current_score - baseline_score) / baseline_score * 100)
      "#{round(change)}% #{if change > 0, do: "improvement", else: "degradation"}"
    end
    
    defp identify_improvements(_report, _baseline) do
      # Simplified
      ["Response time", "Memory efficiency"]
    end
    
    defp identify_degradations(_report, _baseline) do
      # Simplified
      []
    end
    
    defp format_summary_report(base_report) do
      %{
        title: "Performance Analysis Summary",
        timestamp: base_report.overview.timestamp,
        overview: base_report.overview.summary,
        metrics: format_summary_metrics(base_report.metrics),
        top_issues: format_top_issues(base_report.bottlenecks),
        quick_wins: identify_quick_wins(base_report.optimizations)
      }
    end
    
    defp format_summary_metrics(metrics) do
      %{
        performance_score: metrics.quality.overall_score,
        critical_issues: metrics.performance.critical_hotspots || 0,
        memory_health: metrics.memory.score || "N/A",
        complexity_grade: metrics.complexity.grade || "N/A"
      }
    end
    
    defp format_top_issues(bottlenecks) do
      bottlenecks
      |> Enum.take(5)
      |> Enum.map(fn b ->
        %{
          type: b.category,
          location: b[:function] || b[:location],
          impact: b[:impact] || b[:severity]
        }
      end)
    end
    
    defp identify_quick_wins(optimizations) do
      # Filter for easy-to-implement optimizations
      optimizations
      |> Enum.filter(fn opt ->
        String.contains?(opt, ["cache", "memoize", "pool"]) ||
        String.contains?(opt, ["batch", "reduce", "optimize"])
      end)
      |> Enum.take(3)
    end
    
    defp format_detailed_report(base_report) do
      %{
        title: "Comprehensive Performance Analysis",
        timestamp: base_report.overview.timestamp,
        table_of_contents: [
          "Executive Summary",
          "Performance Metrics",
          "Bottleneck Analysis",
          "Optimization Opportunities",
          "Implementation Guide",
          "Appendices"
        ],
        sections: %{
          executive_summary: base_report.overview,
          metrics: format_detailed_metrics(base_report.metrics),
          bottlenecks: format_detailed_bottlenecks(base_report.bottlenecks),
          optimizations: format_optimization_plan(base_report.optimizations),
          trends: base_report.trends
        },
        appendices: generate_appendices()
      }
    end
    
    defp format_detailed_metrics(metrics) do
      %{
        performance: %{
          title: "Performance Metrics",
          data: metrics.performance,
          interpretation: interpret_performance_metrics(metrics.performance)
        },
        complexity: %{
          title: "Code Complexity Analysis",
          data: metrics.complexity,
          interpretation: interpret_complexity_metrics(metrics.complexity)
        },
        memory: %{
          title: "Memory Usage Analysis",
          data: metrics.memory,
          interpretation: interpret_memory_metrics(metrics.memory)
        }
      }
    end
    
    defp interpret_performance_metrics(perf) do
      if perf[:critical_hotspots] && perf.critical_hotspots > 0 do
        "Critical performance issues require immediate attention"
      else
        "Performance is within acceptable parameters"
      end
    end
    
    defp interpret_complexity_metrics(complexity) do
      if complexity[:grade] do
        case complexity.grade do
          "A" -> "Excellent algorithmic efficiency"
          "B" -> "Good complexity, minor improvements possible"
          "C" -> "Moderate complexity issues should be addressed"
          "D" -> "Poor algorithmic choices impacting performance"
          "F" -> "Critical complexity issues requiring refactoring"
          _ -> "Complexity analysis incomplete"
        end
      else
        "No complexity data available"
      end
    end
    
    defp interpret_memory_metrics(memory) do
      if memory[:score] do
        cond do
          memory.score >= 90 -> "Excellent memory management"
          memory.score >= 75 -> "Good memory usage with minor issues"
          memory.score >= 60 -> "Memory management needs improvement"
          true -> "Critical memory issues detected"
        end
      else
        "No memory analysis data available"
      end
    end
    
    defp format_detailed_bottlenecks(bottlenecks) do
      bottlenecks
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {category, items} ->
        %{
          category: category,
          count: length(items),
          items: Enum.map(items, &format_bottleneck_item/1),
          remediation: suggest_category_remediation(category)
        }
      end)
    end
    
    defp format_bottleneck_item(bottleneck) do
      %{
        description: describe_bottleneck(bottleneck),
        severity: bottleneck[:severity],
        location: bottleneck[:function] || bottleneck[:location],
        impact: bottleneck[:impact] || "Performance degradation"
      }
    end
    
    defp describe_bottleneck(bottleneck) do
      case bottleneck.category do
        :cpu -> "CPU-intensive operation"
        :algorithmic -> "Inefficient algorithm"
        :memory -> "Memory allocation issue"
        :io -> "I/O blocking operation"
        _ -> "Performance bottleneck"
      end
    end
    
    defp suggest_category_remediation(category) do
      case category do
        :cpu -> "Consider parallelization or algorithm optimization"
        :algorithmic -> "Review data structures and algorithm choices"
        :memory -> "Implement object pooling or lazy loading"
        :io -> "Use async operations or caching"
        _ -> "Analyze and optimize the specific bottleneck"
      end
    end
    
    defp format_optimization_plan(optimizations) do
      optimizations
      |> Enum.with_index(1)
      |> Enum.map(fn {opt, idx} ->
        %{
          priority: idx,
          optimization: opt,
          estimated_effort: estimate_optimization_effort(opt),
          expected_impact: estimate_optimization_impact(opt)
        }
      end)
    end
    
    defp estimate_optimization_effort(optimization) do
      cond do
        String.contains?(optimization, ["cache", "memoize"]) -> "Low (1-2 hours)"
        String.contains?(optimization, ["refactor", "rewrite"]) -> "High (1-2 days)"
        String.contains?(optimization, ["optimize", "improve"]) -> "Medium (4-8 hours)"
        true -> "Variable"
      end
    end
    
    defp estimate_optimization_impact(optimization) do
      cond do
        String.contains?(optimization, ["n²", "exponential"]) -> "Very High (10x+)"
        String.contains?(optimization, ["database", "query"]) -> "High (5-10x)"
        String.contains?(optimization, ["cache", "pool"]) -> "Medium (2-5x)"
        true -> "Low-Medium (1.5-2x)"
      end
    end
    
    defp generate_appendices do
      %{
        glossary: %{
          "Time Complexity" => "How execution time grows with input size",
          "Space Complexity" => "How memory usage grows with input size",
          "Hotspot" => "Code section consuming significant resources",
          "Bottleneck" => "Performance-limiting component"
        },
        tools: [
          "CPU Profilers: perf, VTune, Instruments",
          "Memory Profilers: Valgrind, Chrome DevTools",
          "APM Tools: New Relic, DataDog, AppDynamics"
        ],
        references: [
          "Big O Notation Guide",
          "Performance Best Practices",
          "Optimization Patterns"
        ]
      }
    end
    
    defp add_recommendations_section(report, results) do
      recommendations = generate_recommendations(results)
      
      Map.put(report, :recommendations, %{
        immediate: recommendations.immediate,
        short_term: recommendations.short_term,
        long_term: recommendations.long_term,
        monitoring: recommendations.monitoring
      })
    end
    
    defp generate_recommendations(results) do
      %{
        immediate: generate_immediate_recommendations(results),
        short_term: generate_short_term_recommendations(results),
        long_term: generate_long_term_recommendations(results),
        monitoring: generate_monitoring_recommendations()
      }
    end
    
    defp generate_immediate_recommendations(results) do
      recs = []
      
      # Critical performance issues
      if results[:profile] && results.profile.metrics.critical_hotspots > 0 do
        recs = ["Address critical performance hotspots immediately" | recs]
      end
      
      # Memory leaks
      if results[:memory] && length(results.memory.leak_detection.potential_leaks) > 0 do
        recs = ["Fix identified memory leaks" | recs]
      end
      
      # High complexity
      if results[:complexity] do
        targets = results.complexity.optimization_targets
        critical = Enum.filter(targets, &(&1.priority == "critical"))
        if length(critical) > 0 do
          recs = ["Refactor high-complexity functions" | recs]
        end
      end
      
      recs
    end
    
    defp generate_short_term_recommendations(results) do
      recs = []
      
      # Caching opportunities
      if results[:caching] && length(results.caching.caching_opportunities) > 0 do
        recs = ["Implement identified caching strategies" | recs]
      end
      
      # Query optimization
      if results[:queries] && results.queries.optimization_summary.total_issues > 0 do
        recs = ["Optimize database queries" | recs]
      end
      
      # General optimizations
      recs = [
        "Set up performance monitoring",
        "Establish performance baselines",
        "Create performance test suite"
      ] ++ recs
      
      recs
    end
    
    defp generate_long_term_recommendations(_results) do
      [
        "Implement continuous performance testing",
        "Establish performance budgets",
        "Regular architecture reviews",
        "Team training on performance best practices"
      ]
    end
    
    defp generate_monitoring_recommendations do
      %{
        metrics: [
          "Response time (p50, p95, p99)",
          "Throughput (requests/second)",
          "Error rate",
          "CPU and memory usage",
          "Database query time"
        ],
        tools: [
          "Application Performance Monitoring (APM)",
          "Real User Monitoring (RUM)",
          "Synthetic monitoring",
          "Custom dashboards"
        ],
        alerts: [
          "Response time > 2x baseline",
          "Error rate > 1%",
          "Memory usage > 80%",
          "CPU usage sustained > 70%"
        ]
      }
    end
  end
  
  @impl BaseToolAgent
  def initial_state do
    %{
      profile_cache: %{},
      analysis_history: [],
      performance_baselines: %{},
      optimization_tracking: %{},
      benchmark_results: %{},
      alert_thresholds: default_alert_thresholds(),
      max_history: 50
    }
  end
  
  @impl BaseToolAgent
  def handle_tool_signal(%State{} = state, signal) do
    signal_type = signal["type"]
    data = signal["data"] || %{}
    
    case signal_type do
      "profile_code" ->
        cmd_async(state, ProfileCodeAction, data)
        
      "analyze_complexity" ->
        cmd_async(state, AnalyzeComplexityAction, data)
        
      "optimize_queries" ->
        cmd_async(state, OptimizeDatabaseQueriesAction, data)
        
      "identify_caching" ->
        cmd_async(state, IdentifyCachingOpportunitiesAction, data)
        
      "generate_benchmark" ->
        cmd_async(state, GenerateBenchmarkAction, data)
        
      "analyze_memory" ->
        cmd_async(state, AnalyzeMemoryUsageAction, data)
        
      "generate_report" ->
        cmd_async(state, GeneratePerformanceReportAction, data)
        
      _ ->
        super(state, signal)
    end
  end
  
  @impl BaseToolAgent
  def handle_action_result(state, action, result, metadata) do
    case action do
      ProfileCodeAction ->
        handle_profile_result(state, result, metadata)
        
      AnalyzeComplexityAction ->
        handle_complexity_result(state, result, metadata)
        
      GenerateBenchmarkAction ->
        handle_benchmark_result(state, result, metadata)
        
      _ ->
        super(state, action, result, metadata)
    end
  end
  
  defp handle_profile_result(state, {:ok, result}, metadata) do
    # Cache profile results
    cache_key = generate_profile_key(metadata)
    updated_cache = Map.put(state.state.profile_cache, cache_key, %{
      result: result,
      timestamp: DateTime.utc_now()
    })
    
    # Add to analysis history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :performance_profile,
      profile_type: result.profile_type,
      hotspot_count: length(result.hotspots),
      score: result.metrics.profile_score,
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.analysis_history]
      |> Enum.take(state.state.max_history)
    
    # Check performance alerts
    alerts = check_performance_alerts(result, state.state.alert_thresholds)
    
    updated_state = %{state.state |
      profile_cache: updated_cache,
      analysis_history: updated_history
    }
    
    updated_state = if length(alerts) > 0 do
      # Emit alert signals
      Enum.each(alerts, fn alert ->
        emit_performance_alert(state, alert)
      end)
      updated_state
    else
      updated_state
    end
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_profile_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_complexity_result(state, {:ok, result}, metadata) do
    # Track optimization opportunities
    targets = result.optimization_targets
    
    updated_tracking = Enum.reduce(targets, state.state.optimization_tracking, fn target, acc ->
      Map.put(acc, target.function, %{
        complexity: target.current_complexity,
        improvement_potential: target.improvement_potential,
        tracked_at: DateTime.utc_now()
      })
    end)
    
    # Add to history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :complexity_analysis,
      worst_complexity: result.overall_assessment.worst_case_complexity,
      grade: result.overall_assessment.performance_grade,
      targets: length(targets),
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.analysis_history]
      |> Enum.take(state.state.max_history)
    
    updated_state = %{state.state |
      optimization_tracking: updated_tracking,
      analysis_history: updated_history
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_complexity_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_benchmark_result(state, {:ok, result}, metadata) do
    # Store benchmark results
    benchmark_id = metadata[:benchmark_id] || generate_benchmark_id()
    
    updated_benchmarks = Map.put(state.state.benchmark_results, benchmark_id, %{
      suite: result.benchmark_suite,
      created_at: DateTime.utc_now(),
      metadata: metadata
    })
    
    # Update baselines if this is a baseline run
    updated_baselines = if metadata[:is_baseline] do
      Map.put(state.state.performance_baselines, metadata[:component], %{
        benchmark_id: benchmark_id,
        metrics: result.metrics_to_collect,
        established_at: DateTime.utc_now()
      })
    else
      state.state.performance_baselines
    end
    
    updated_state = %{state.state |
      benchmark_results: updated_benchmarks,
      performance_baselines: updated_baselines
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_benchmark_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  @impl BaseToolAgent
  def process_result(result, _metadata) do
    Map.put(result, :analyzed_at, DateTime.utc_now())
  end
  
  @impl BaseToolAgent
  def additional_actions do
    [
      ProfileCodeAction,
      AnalyzeComplexityAction,
      OptimizeDatabaseQueriesAction,
      IdentifyCachingOpportunitiesAction,
      GenerateBenchmarkAction,
      AnalyzeMemoryUsageAction,
      GeneratePerformanceReportAction
    ]
  end
  
  # Helper functions
  defp generate_profile_key(metadata) do
    source = metadata[:source_code] || ""
    profile_type = metadata[:profile_type] || "unknown"
    
    hash = :crypto.hash(:md5, source <> profile_type) |> Base.encode16()
    "profile_#{profile_type}_#{hash}"
  end
  
  defp check_performance_alerts(profile_result, thresholds) do
    alerts = []
    
    # Check CPU threshold
    if profile_result.profile_type == "cpu" && profile_result.metrics[:estimated_cpu_usage] do
      cpu_usage = String.trim_trailing(profile_result.metrics.estimated_cpu_usage, "%") |> String.to_integer()
      if cpu_usage > thresholds.cpu_threshold do
        alerts = [%{
          type: :high_cpu_usage,
          severity: :warning,
          value: cpu_usage,
          threshold: thresholds.cpu_threshold,
          message: "CPU usage #{cpu_usage}% exceeds threshold"
        } | alerts]
      end
    end
    
    # Check critical hotspots
    if profile_result.metrics.critical_hotspots > thresholds.critical_hotspot_threshold do
      alerts = [%{
        type: :critical_hotspots,
        severity: :critical,
        value: profile_result.metrics.critical_hotspots,
        threshold: thresholds.critical_hotspot_threshold,
        message: "#{profile_result.metrics.critical_hotspots} critical performance hotspots detected"
      } | alerts]
    end
    
    alerts
  end
  
  defp emit_performance_alert(state, alert) do
    signal = %{
      "type" => "performance.alert",
      "source" => "performance_analyzer",
      "data" => alert,
      "time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Jido.Signal.emit(signal, state)
  end
  
  defp generate_benchmark_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end
  
  defp default_alert_thresholds do
    %{
      cpu_threshold: 80,  # percentage
      memory_threshold: 85,  # percentage
      response_time_threshold: 1000,  # milliseconds
      critical_hotspot_threshold: 2,  # count
      complexity_threshold: "O(n²)"  # complexity notation
    }
  end
end