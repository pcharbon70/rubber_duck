defmodule RubberDuck.Tools.Agents.RepoSearchAgent do
  @moduledoc """
  Agent that orchestrates the RepoSearch tool for intelligent code search workflows.
  
  This agent manages search requests, maintains search history, handles complex search
  patterns, and provides smart search recommendations and result analysis.
  
  ## Signals
  
  ### Input Signals
  - `search_repository` - Search the repository for patterns
  - `batch_search` - Execute multiple searches in batch
  - `analyze_search_results` - Analyze search results for patterns
  - `suggest_searches` - Suggest relevant searches based on context
  - `search_symbols` - Search for specific symbols or definitions
  - `find_references` - Find all references to a symbol or function
  
  ### Output Signals
  - `search_completed` - Search operation completed successfully
  - `search_results_analyzed` - Search result analysis completed
  - `search_suggestions_ready` - Search suggestions generated
  - `batch_search_completed` - Batch search operation completed
  - `search_error` - Error during search operation
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :repo_search,
    name: "repo_search_agent",
    description: "Manages intelligent code search and discovery workflows",
    category: "navigation",
    tags: ["search", "navigation", "discovery", "analysis", "code_exploration"],
    schema: [
      # Search history and tracking
      search_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Search patterns and preferences
      search_patterns: [type: :map, default: quote do %{} end],
      
      # Batch search operations
      active_batch_searches: [type: :map, default: %{}],
      
      # Search result analysis
      result_analysis_cache: [type: :map, default: %{}],
      analysis_ttl: [type: :integer, default: 600_000], # 10 minutes
      
      # Search statistics
      search_stats: [type: :map, default: quote do %{} end],
      
      # Smart suggestions
      suggested_searches: [type: {:list, :map}, default: []],
      suggestion_context: [type: :map, default: quote do %{} end],
      
      # Search preferences
      search_preferences: [type: :map, default: quote do %{} end],
      
      # Performance tracking
      performance_metrics: [type: :map, default: quote do %{} end]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchSearchAction,
      __MODULE__.AnalyzeResultsAction,
      __MODULE__.SuggestSearchesAction,
      __MODULE__.FindReferencesAction,
      __MODULE__.SearchPatternsAction
    ]
  end
  
  # Action modules
  
  defmodule BatchSearchAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_search",
      description: "Execute multiple search queries in a coordinated batch operation",
      schema: [
        searches: [type: {:list, :map}, required: true, doc: "List of search operations to execute"],
        execution_strategy: [type: :atom, values: [:sequential, :parallel, :smart], default: :smart],
        max_concurrency: [type: :integer, default: 4],
        timeout_per_search: [type: :integer, default: 30_000],
        aggregate_results: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      batch_id = generate_batch_id()
      
      # Start batch operation
      batch_info = %{
        id: batch_id,
        searches: params.searches,
        strategy: params.execution_strategy,
        status: :in_progress,
        started_at: DateTime.utc_now(),
        completed_searches: [],
        failed_searches: []
      }
      
      case params.execution_strategy do
        :sequential -> execute_sequential_searches(batch_info, params, agent)
        :parallel -> execute_parallel_searches(batch_info, params, agent)
        :smart -> execute_smart_searches(batch_info, params, agent)
      end
    end
    
    defp generate_batch_id do
      "batch_#{System.unique_integer([:positive, :monotonic])}"
    end
    
    defp execute_sequential_searches(batch_info, params, agent) do
      {completed, failed} = Enum.reduce(batch_info.searches, {[], []}, fn search, {completed_acc, failed_acc} ->
        case execute_single_search(search, agent) do
          {:ok, result} -> {[result | completed_acc], failed_acc}
          {:error, error} -> {completed_acc, [%{search: search, error: error} | failed_acc]}
        end
      end)
      
      finalize_batch_results(batch_info, completed, failed, params)
    end
    
    defp execute_parallel_searches(batch_info, params, agent) do
      results = batch_info.searches
      |> Task.async_stream(fn search -> execute_single_search(search, agent) end,
                          timeout: params.timeout_per_search,
                          max_concurrency: params.max_concurrency)
      |> Enum.to_list()
      
      {completed, failed} = Enum.reduce(Enum.zip(batch_info.searches, results), {[], []},
        fn {search, result}, {completed_acc, failed_acc} ->
          case result do
            {:ok, {:ok, search_result}} -> {[search_result | completed_acc], failed_acc}
            {:ok, {:error, error}} -> {completed_acc, [%{search: search, error: error} | failed_acc]}
            {:exit, reason} -> {completed_acc, [%{search: search, error: "Task exited: #{inspect(reason)}"} | failed_acc]}
          end
        end)
      
      finalize_batch_results(batch_info, completed, failed, params)
    end
    
    defp execute_smart_searches(batch_info, params, agent) do
      # Analyze searches and determine optimal execution strategy
      {high_priority, normal_priority} = categorize_searches(batch_info.searches)
      
      # Execute high priority searches first (sequential for accuracy)
      {completed_hp, failed_hp} = Enum.reduce(high_priority, {[], []}, fn search, {completed_acc, failed_acc} ->
        case execute_single_search(search, agent) do
          {:ok, result} -> {[result | completed_acc], failed_acc}
          {:error, error} -> {completed_acc, [%{search: search, error: error} | failed_acc]}
        end
      end)
      
      # Execute normal priority searches in parallel
      results_np = normal_priority
      |> Task.async_stream(fn search -> execute_single_search(search, agent) end,
                          timeout: params.timeout_per_search,
                          max_concurrency: params.max_concurrency)
      |> Enum.to_list()
      
      {completed_np, failed_np} = Enum.reduce(Enum.zip(normal_priority, results_np), {[], []},
        fn {search, result}, {completed_acc, failed_acc} ->
          case result do
            {:ok, {:ok, search_result}} -> {[search_result | completed_acc], failed_acc}
            {:ok, {:error, error}} -> {completed_acc, [%{search: search, error: error} | failed_acc]}
            {:exit, reason} -> {completed_acc, [%{search: search, error: "Task exited: #{inspect(reason)}"} | failed_acc]}
          end
        end)
      
      all_completed = completed_hp ++ completed_np
      all_failed = failed_hp ++ failed_np
      
      finalize_batch_results(batch_info, all_completed, all_failed, params)
    end
    
    defp categorize_searches(searches) do
      Enum.split_with(searches, fn search ->
        # High priority: symbol/definition searches, small scope searches
        search["search_type"] in ["symbol", "definition"] or
        String.length(search["query"] || "") < 10
      end)
    end
    
    defp execute_single_search(search, _agent) do
      # Simulate search execution - would use actual RepoSearch tool
      query = search["query"] || ""
      search_type = search["search_type"] || "text"
      
      # Simulate some search logic
      case String.length(query) do
        0 -> {:error, "Empty query"}
        n when n > 500 -> {:error, "Query too long"}
        _ -> 
          {:ok, %{
            query: query,
            search_type: search_type,
            total_matches: Enum.random(0..20),
            files_searched: Enum.random(10..100),
            results: generate_mock_results(query, Enum.random(0..5)),
            search_time: Enum.random(100..2000)
          }}
      end
    end
    
    defp generate_mock_results(query, count) do
      Enum.map(1..count, fn i ->
        %{
          file: "lib/example/file_#{i}.ex",
          line: Enum.random(1..100),
          match: "Found #{query} in context #{i}",
          type: :text_match
        }
      end)
    end
    
    defp finalize_batch_results(batch_info, completed, failed, params) do
      aggregated_results = if params.aggregate_results do
        aggregate_search_results(completed)
      else
        completed
      end
      
      {:ok, %{
        batch_id: batch_info.id,
        total_searches: length(batch_info.searches),
        successful_searches: length(completed),
        failed_searches: length(failed),
        results: aggregated_results,
        failed: failed,
        execution_time: DateTime.diff(DateTime.utc_now(), batch_info.started_at, :millisecond)
      }}
    end
    
    defp aggregate_search_results(results) do
      # Combine and deduplicate results across searches
      all_results = Enum.flat_map(results, fn result -> result.results end)
      
      # Group by file and line for deduplication
      unique_results = all_results
      |> Enum.uniq_by(fn result -> {result.file, result.line, result.match} end)
      |> Enum.sort_by(fn result -> {result.file, result.line} end)
      
      %{
        total_unique_matches: length(unique_results),
        results: unique_results,
        search_summary: %{
          total_files_with_matches: unique_results |> Enum.map(& &1.file) |> Enum.uniq() |> length(),
          match_types: unique_results |> Enum.map(& &1.type) |> Enum.frequencies()
        }
      }
    end
  end
  
  defmodule AnalyzeResultsAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_results",
      description: "Analyze search results to identify patterns and insights",
      schema: [
        search_results: [type: :map, required: true, doc: "Search results to analyze"],
        analysis_type: [type: :atom, values: [:basic, :detailed, :comprehensive], default: :detailed],
        include_suggestions: [type: :boolean, default: true],
        pattern_detection: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      results = params.search_results
      
      analysis = %{
        result_statistics: analyze_result_statistics(results),
        file_distribution: analyze_file_distribution(results),
        pattern_analysis: if(params.pattern_detection, do: detect_patterns(results), else: %{}),
        code_insights: extract_code_insights(results, params.analysis_type),
        search_suggestions: if(params.include_suggestions, do: generate_suggestions(results, agent), else: [])
      }
      
      {:ok, %{
        query: results.query || "unknown",
        analysis_type: params.analysis_type,
        total_results_analyzed: results.total_matches || 0,
        analysis: analysis,
        analyzed_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_result_statistics(results) do
      matches = results.results || []
      
      %{
        total_matches: length(matches),
        unique_files: matches |> Enum.map(& &1.file) |> Enum.uniq() |> length(),
        match_types: matches |> Enum.map(& &1.type) |> Enum.frequencies(),
        average_matches_per_file: if(length(matches) > 0, do: length(matches) / (matches |> Enum.map(& &1.file) |> Enum.uniq() |> length()), else: 0),
        line_distribution: analyze_line_distribution(matches)
      }
    end
    
    defp analyze_file_distribution(results) do
      matches = results.results || []
      
      matches
      |> Enum.group_by(& &1.file)
      |> Enum.map(fn {file, file_matches} ->
        %{
          file: file,
          match_count: length(file_matches),
          match_density: calculate_match_density(file_matches),
          file_type: Path.extname(file)
        }
      end)
      |> Enum.sort_by(& &1.match_count, :desc)
    end
    
    defp detect_patterns(results) do
      matches = results.results || []
      
      %{
        clustering: detect_clustering(matches),
        naming_patterns: detect_naming_patterns(matches),
        code_patterns: detect_code_patterns(matches),
        architectural_insights: detect_architectural_patterns(matches)
      }
    end
    
    defp extract_code_insights(results, analysis_type) do
      case analysis_type do
        :basic -> extract_basic_insights(results)
        :detailed -> extract_detailed_insights(results)
        :comprehensive -> extract_comprehensive_insights(results)
      end
    end
    
    defp generate_suggestions(results, agent) do
      matches = results.results || []
      
      suggestions = []
      
      # Suggest related searches based on current results
      suggestions = suggestions ++ suggest_related_searches(matches)
      
      # Suggest refactoring opportunities
      suggestions = suggestions ++ suggest_refactoring_opportunities(matches)
      
      # Suggest exploration paths
      suggestions = suggestions ++ suggest_exploration_paths(matches, agent)
      
      suggestions
    end
    
    defp analyze_line_distribution(matches) do
      line_numbers = Enum.map(matches, & &1.line)
      
      %{
        min_line: Enum.min(line_numbers, fn -> 0 end),
        max_line: Enum.max(line_numbers, fn -> 0 end),
        average_line: if(length(line_numbers) > 0, do: Enum.sum(line_numbers) / length(line_numbers), else: 0),
        line_clusters: detect_line_clusters(line_numbers)
      }
    end
    
    defp calculate_match_density(matches) do
      if length(matches) == 0, do: 0, else: length(matches) / 100.0 # Simplified density calculation
    end
    
    defp detect_clustering(matches) do
      # Simplified clustering detection
      files_with_multiple_matches = matches
      |> Enum.group_by(& &1.file)
      |> Enum.filter(fn {_file, file_matches} -> length(file_matches) > 2 end)
      |> Enum.map(fn {file, file_matches} -> 
        %{file: file, cluster_size: length(file_matches)}
      end)
      
      %{
        clustered_files: files_with_multiple_matches,
        clustering_score: length(files_with_multiple_matches) / max(1, length(matches))
      }
    end
    
    defp detect_naming_patterns(matches) do
      # Extract naming patterns from matches
      names = matches
      |> Enum.map(& &1.match)
      |> Enum.filter(&is_binary/1)
      
      %{
        common_prefixes: find_common_prefixes(names),
        common_suffixes: find_common_suffixes(names),
        naming_conventions: detect_naming_conventions(names)
      }
    end
    
    defp detect_code_patterns(matches) do
      # Analyze code patterns in matches
      %{
        function_patterns: detect_function_patterns(matches),
        module_patterns: detect_module_patterns(matches),
        usage_patterns: detect_usage_patterns(matches)
      }
    end
    
    defp detect_architectural_patterns(matches) do
      # Higher-level architectural insights
      %{
        layer_distribution: analyze_layer_distribution(matches),
        coupling_indicators: detect_coupling_indicators(matches),
        design_patterns: detect_design_patterns(matches)
      }
    end
    
    defp extract_basic_insights(results) do
      %{
        summary: "Found #{results.total_matches || 0} matches across #{length(results.results || [])} locations",
        key_files: (results.results || []) |> Enum.take(3) |> Enum.map(& &1.file),
        recommendations: ["Review top matching files", "Consider search refinement"]
      }
    end
    
    defp extract_detailed_insights(results) do
      matches = results.results || []
      
      %{
        distribution_analysis: "Matches distributed across #{matches |> Enum.map(& &1.file) |> Enum.uniq() |> length()} files",
        hotspots: identify_hotspots(matches),
        patterns: identify_patterns(matches),
        recommendations: generate_detailed_recommendations(matches)
      }
    end
    
    defp extract_comprehensive_insights(results) do
      matches = results.results || []
      
      %{
        comprehensive_summary: build_comprehensive_summary(matches),
        detailed_analysis: perform_detailed_analysis(matches),
        architectural_view: build_architectural_view(matches),
        actionable_insights: generate_actionable_insights(matches),
        recommendations: generate_comprehensive_recommendations(matches)
      }
    end
    
    # Helper function implementations (simplified)
    defp suggest_related_searches(matches) do
      files = matches |> Enum.map(& &1.file) |> Enum.uniq() |> Enum.take(3)
      
      Enum.map(files, fn file ->
        %{
          type: :related_search,
          description: "Search more in #{Path.basename(file)}",
          suggested_query: "file:#{file}",
          priority: :medium
        }
      end)
    end
    
    defp suggest_refactoring_opportunities(matches) do
      if length(matches) > 10 do
        [%{
          type: "refactoring",
          description: "Consider extracting common patterns found in #{length(matches)} locations",
          priority: :high
        }]
      else
        []
      end
    end
    
    defp suggest_exploration_paths(matches, _agent) do
      unique_files = matches |> Enum.map(& &1.file) |> Enum.uniq()
      
      if length(unique_files) > 5 do
        [%{
          type: :exploration,
          description: "Explore architectural patterns across #{length(unique_files)} files",
          priority: :low
        }]
      else
        []
      end
    end
    
    # Simplified implementations for other helper functions
    defp detect_line_clusters(line_numbers) do
      # Simplified line clustering
      %{clusters: [], cluster_count: 0}
    end
    
    defp find_common_prefixes(names), do: []
    defp find_common_suffixes(names), do: []
    defp detect_naming_conventions(names), do: %{}
    defp detect_function_patterns(matches), do: %{}
    defp detect_module_patterns(matches), do: %{}
    defp detect_usage_patterns(matches), do: %{}
    defp analyze_layer_distribution(matches), do: %{}
    defp detect_coupling_indicators(matches), do: %{}
    defp detect_design_patterns(matches), do: %{}
    defp identify_hotspots(matches), do: []
    defp identify_patterns(matches), do: []
    defp generate_detailed_recommendations(matches), do: []
    defp build_comprehensive_summary(matches), do: "Comprehensive analysis of #{length(matches)} matches"
    defp perform_detailed_analysis(matches), do: %{}
    defp build_architectural_view(matches), do: %{}
    defp generate_actionable_insights(matches), do: []
    defp generate_comprehensive_recommendations(matches), do: []
  end
  
  defmodule SuggestSearchesAction do
    @moduledoc false
    use Jido.Action,
      name: "suggest_searches",
      description: "Generate intelligent search suggestions based on context and history",
      schema: [
        context: [type: :map, default: %{}, doc: "Current context for suggestions"],
        suggestion_types: [type: {:list, :atom}, default: [:related, :exploratory, :refactoring], doc: "Types of suggestions to generate"],
        max_suggestions: [type: :integer, default: 10],
        priority_filter: [type: :atom, values: [:all, :high, :medium, :low], default: :all]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      suggestions = []
      
      # Generate different types of suggestions
      if :related in params.suggestion_types do
        suggestions = suggestions ++ generate_related_suggestions(agent, params.context)
      end
      
      if :exploratory in params.suggestion_types do
        suggestions = suggestions ++ generate_exploratory_suggestions(agent, params.context)
      end
      
      if :refactoring in params.suggestion_types do
        suggestions = suggestions ++ generate_refactoring_suggestions(agent, params.context)
      end
      
      # Filter by priority if specified
      filtered_suggestions = case params.priority_filter do
        :all -> suggestions
        priority -> Enum.filter(suggestions, &(&1.priority == priority))
      end
      
      # Limit results
      final_suggestions = Enum.take(filtered_suggestions, params.max_suggestions)
      
      {:ok, %{
        total_suggestions: length(final_suggestions),
        suggestions: final_suggestions,
        suggestion_types: params.suggestion_types,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp generate_related_suggestions(agent, context) do
      # Generate suggestions based on search history and current context
      recent_searches = Enum.take(agent.state.search_history, 5)
      
      Enum.flat_map(recent_searches, fn search ->
        [
          %{
            type: :related,
            query: "#{search.query} test",
            description: "Find tests related to '#{search.query}'",
            priority: :medium,
            confidence: 0.7
          },
          %{
            type: :related,
            query: search.query,
            description: "Search in different file types",
            search_options: %{file_pattern: "**/*.{exs,eex,heex}"},
            priority: :low,
            confidence: 0.6
          }
        ]
      end)
    end
    
    defp generate_exploratory_suggestions(agent, context) do
      # Generate exploratory search suggestions
      [
        %{
          type: :exploratory,
          query: "def ",
          description: "Explore all function definitions",
          search_options: %{search_type: "text", file_pattern: "lib/**/*.ex"},
          priority: :low,
          confidence: 0.8
        },
        %{
          type: :exploratory,
          query: "TODO",
          description: "Find all TODO comments",
          search_options: %{search_type: "text", case_sensitive: false},
          priority: :medium,
          confidence: 0.9
        }
      ]
    end
    
    defp generate_refactoring_suggestions(agent, context) do
      # Generate suggestions for potential refactoring opportunities
      [
        %{
          type: "refactoring",
          query: "def.*def.*def",
          description: "Find files with many function definitions (potential for splitting)",
          search_options: %{search_type: "regex"},
          priority: :high,
          confidence: 0.6
        }
      ]
    end
  end
  
  defmodule FindReferencesAction do
    @moduledoc false
    use Jido.Action,
      name: "find_references",
      description: "Find all references to a specific symbol, function, or module",
      schema: [
        symbol: [type: :string, required: true, doc: "Symbol to find references for"],
        symbol_type: [type: :atom, values: [:function, :module, :variable, :any], default: :any],
        include_definitions: [type: :boolean, default: false],
        scope: [type: :atom, values: [:project, :app, :deps], default: :project]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Build search queries for different reference types
      searches = build_reference_searches(params)
      
      # Execute searches
      results = Enum.map(searches, fn search ->
        case execute_reference_search(search, agent) do
          {:ok, result} -> result
          {:error, _} -> %{results: [], total_matches: 0}
        end
      end)
      
      # Combine and categorize results
      combined_results = combine_reference_results(results, params)
      
      {:ok, %{
        symbol: params.symbol,
        symbol_type: params.symbol_type,
        total_references: combined_results.total_references,
        reference_categories: combined_results.categories,
        results: combined_results.results,
        scope: params.scope,
        searched_at: DateTime.utc_now()
      }}
    end
    
    defp build_reference_searches(params) do
      symbol = params.symbol
      
      base_searches = [
        %{query: symbol, search_type: "text", description: "Direct text references"},
        %{query: "#{symbol}(", search_type: "text", description: "Function calls"},
        %{query: "#{symbol}.", search_type: "text", description: "Module references"}
      ]
      
      case params.symbol_type do
        :function ->
          base_searches ++ [
            %{query: "def #{symbol}", search_type: "text", description: "Function definitions"},
            %{query: "&#{symbol}/", search_type: "text", description: "Function captures"},
          ]
        :module ->
          base_searches ++ [
            %{query: "alias #{symbol}", search_type: "text", description: "Module aliases"},
            %{query: "import #{symbol}", search_type: "text", description: "Module imports"},
          ]
        _ ->
          base_searches
      end
    end
    
    defp execute_reference_search(search, _agent) do
      # Simulate reference search execution
      {:ok, %{
        query: search.query,
        search_type: search.search_type,
        description: search.description,
        total_matches: Enum.random(0..15),
        results: generate_mock_references(search.query, Enum.random(0..5))
      }}
    end
    
    defp generate_mock_references(query, count) do
      Enum.map(1..count, fn i ->
        %{
          file: "lib/example/file_#{i}.ex",
          line: Enum.random(1..200),
          match: "Reference to #{query} at line #{i}",
          type: Enum.random([:call, :definition, :alias, :import]),
          context: []
        }
      end)
    end
    
    defp combine_reference_results(results, _params) do
      all_results = Enum.flat_map(results, fn result -> result.results end)
      total_references = Enum.sum(Enum.map(results, fn result -> result.total_matches end))
      
      # Categorize by reference type
      categories = all_results
      |> Enum.group_by(fn result -> result.type end)
      |> Enum.map(fn {type, refs} -> 
        %{type: type, count: length(refs), examples: Enum.take(refs, 3)}
      end)
      
      %{
        total_references: total_references,
        categories: categories,
        results: all_results |> Enum.sort_by(fn r -> {r.file, r.line} end)
      }
    end
  end
  
  defmodule SearchPatternsAction do
    @moduledoc false
    use Jido.Action,
      name: "search_patterns",
      description: "Execute searches using predefined or custom patterns",
      schema: [
        pattern_name: [type: :string, required: true, doc: "Name of the pattern to use"],
        pattern_params: [type: :map, default: %{}, doc: "Parameters to customize the pattern"],
        create_new_pattern: [type: :boolean, default: false],
        save_pattern: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Get or create the search pattern
      pattern = case get_search_pattern(agent, params.pattern_name) do
        {:ok, existing_pattern} -> 
          customize_pattern(existing_pattern, params.pattern_params)
        {:error, _} when params.create_new_pattern ->
          create_pattern_from_params(params)
        {:error, reason} ->
          return {:error, reason}
      end
      
      # Execute the pattern search
      case execute_pattern_search(pattern, agent) do
        {:ok, results} ->
          # Save pattern if requested
          if params.save_pattern do
            save_search_pattern(agent, params.pattern_name, pattern)
          end
          
          {:ok, %{
            pattern_name: params.pattern_name,
            pattern: pattern,
            results: results,
            executed_at: DateTime.utc_now()
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp get_search_pattern(agent, pattern_name) do
      case Map.get(agent.state.search_patterns, pattern_name) do
        nil -> {:error, "Pattern '#{pattern_name}' not found"}
        pattern -> {:ok, pattern}
      end
    end
    
    defp customize_pattern(pattern, params) do
      # Merge custom parameters with pattern defaults
      Map.merge(pattern, params)
    end
    
    defp create_pattern_from_params(params) do
      # Create a new pattern from provided parameters
      %{
        patterns: [params.pattern_params["query"] || ""],
        search_type: params.pattern_params["search_type"] || "text",
        file_pattern: params.pattern_params["file_pattern"] || "**/*.{ex,exs}",
        description: params.pattern_params["description"] || "Custom pattern"
      }
    end
    
    defp execute_pattern_search(pattern, _agent) do
      # Execute the pattern search
      searches = Enum.map(pattern.patterns, fn query ->
        %{
          query: query,
          search_type: pattern.search_type,
          file_pattern: pattern.file_pattern
        }
      end)
      
      # Simulate executing all searches in the pattern
      results = Enum.map(searches, fn search ->
        %{
          query: search.query,
          total_matches: Enum.random(0..10),
          results: generate_mock_results(search.query, Enum.random(0..3))
        }
      end)
      
      {:ok, %{
        pattern_searches: length(searches),
        total_matches: Enum.sum(Enum.map(results, fn r -> r.total_matches end)),
        combined_results: Enum.flat_map(results, fn r -> r.results end)
      }}
    end
    
    defp generate_mock_results(query, count) do
      Enum.map(1..count, fn i ->
        %{
          file: "lib/pattern/file_#{i}.ex",
          line: Enum.random(1..150),
          match: "Pattern match for #{query}",
          type: :pattern_match
        }
      end)
    end
    
    defp save_search_pattern(agent, pattern_name, pattern) do
      # In a real implementation, this would update the agent state
      Logger.info("Saving search pattern '#{pattern_name}': #{inspect(pattern)}")
      :ok
    end
  end
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "search_repository"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      query: data["query"],
      search_type: data["search_type"] || "text",
      file_pattern: data["file_pattern"] || "**/*.{ex,exs}",
      case_sensitive: data["case_sensitive"] || false,
      max_results: data["max_results"] || 100,
      context_lines: data["context_lines"] || 2,
      exclude_patterns: data["exclude_patterns"] || ["_build/**", "deps/**"]
    }
    
    # Execute the search
    {:ok, _ref} = __MODULE__.cmd_async(agent, ExecuteToolAction, %{params: params},
      context: %{agent: agent}
    )
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "batch_search"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, BatchSearchAction, %{
      searches: data["searches"],
      execution_strategy: String.to_atom(data["execution_strategy"] || "smart"),
      max_concurrency: data["max_concurrency"] || 4,
      timeout_per_search: data["timeout_per_search"] || 30000,
      aggregate_results: data["aggregate_results"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "analyze_search_results"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, AnalyzeResultsAction, %{
      search_results: data["search_results"],
      analysis_type: String.to_atom(data["analysis_type"] || "detailed"),
      include_suggestions: data["include_suggestions"] || true,
      pattern_detection: data["pattern_detection"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "suggest_searches"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, SuggestSearchesAction, %{
      context: data["context"] || %{},
      suggestion_types: Enum.map(data["suggestion_types"] || ["related", "exploratory"], &String.to_atom/1),
      max_suggestions: data["max_suggestions"] || 10,
      priority_filter: String.to_atom(data["priority_filter"] || "all")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "find_references"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, FindReferencesAction, %{
      symbol: data["symbol"],
      symbol_type: String.to_atom(data["symbol_type"] || "any"),
      include_definitions: data["include_definitions"] || false,
      scope: String.to_atom(data["scope"] || "project")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "search_patterns"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, SearchPatternsAction, %{
      pattern_name: data["pattern_name"],
      pattern_params: data["pattern_params"] || %{},
      create_new_pattern: data["create_new_pattern"] || false,
      save_pattern: data["save_pattern"] || false
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  @impl true
  def handle_action_result(agent, BatchSearchAction, {:ok, result}, metadata) do
    # Update batch search tracking
    agent = put_in(agent.state.active_batch_searches[result.batch_id], %{
      status: :completed,
      result: result,
      completed_at: DateTime.utc_now()
    })
    
    # Update statistics
    agent = update_in(agent.state.search_stats, fn stats ->
      stats
      |> Map.update!(:total_searches, &(&1 + result.total_searches))
      |> Map.update!(:successful_searches, &(&1 + result.successful_searches))
      |> Map.update!(:failed_searches, &(&1 + result.failed_searches))
    end)
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "batch_search_completed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, AnalyzeResultsAction, {:ok, result}, metadata) do
    # Cache analysis result
    cache_key = "analysis_#{System.unique_integer([:positive])}"
    agent = put_in(agent.state.result_analysis_cache[cache_key], %{
      result: result,
      cached_at: DateTime.utc_now()
    })
    
    # Emit analysis complete signal
    signal = Jido.Signal.new!(%{
      type: "search_results_analyzed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, SuggestSearchesAction, {:ok, result}, metadata) do
    # Store suggestions
    agent = put_in(agent.state.suggested_searches, result.suggestions)
    
    # Emit suggestions ready signal
    signal = Jido.Signal.new!(%{
      type: "search_suggestions_ready",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Handle main tool execution results
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Record successful search
    search_record = %{
      query: result.query,
      search_type: result.search_type,
      total_matches: result.total_matches,
      files_searched: result.files_searched,
      truncated: result.truncated,
      timestamp: DateTime.utc_now()
    }
    
    # Add to history
    agent = update_in(agent.state.search_history, fn history ->
      new_history = [search_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update statistics
    agent = update_in(agent.state.search_stats, fn stats ->
      new_avg = if stats.total_searches > 0 do
        (stats.average_results_per_search * stats.total_searches + result.total_matches) / (stats.total_searches + 1)
      else
        result.total_matches
      end
      
      stats
      |> Map.update!(:total_searches, &(&1 + 1))
      |> Map.update!(:successful_searches, &(&1 + 1))
      |> put(:average_results_per_search, new_avg)
      |> update_in([:most_searched_terms, result.query], fn
        nil -> 1
        count -> count + 1
      end)
      |> update_in([:search_types_used, result.search_type], fn
        nil -> 1
        count -> count + 1
      end)
    end)
    
    # Emit success signal
    signal = Jido.Signal.new!(%{
      type: "search_completed",
      source: "agent:#{agent.id}",
      data: %{
        query: result.query,
        search_type: result.search_type,
        total_matches: result.total_matches,
        truncated: result.truncated
      }
    })
    emit_signal(agent, signal)
    
    # Call parent handler
    super(agent, ExecuteToolAction, {:ok, result}, metadata)
  end
  
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:error, reason}, metadata) do
    # Update failure statistics
    agent = update_in(agent.state.search_stats.failed_searches, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "search_error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    emit_signal(agent, signal)
    
    # Call parent handler
    super(agent, ExecuteToolAction, {:error, reason}, metadata)
  end
end