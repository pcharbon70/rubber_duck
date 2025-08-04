defmodule RubberDuck.Tools.Agents.RegexExtractorAgent do
  @moduledoc """
  Agent that orchestrates the RegexExtractor tool for intelligent pattern extraction workflows.
  
  This agent manages regex pattern extraction requests, maintains pattern libraries,
  handles batch extraction operations, and provides pattern optimization recommendations.
  
  ## Signals
  
  ### Input Signals
  - `extract_pattern` - Extract patterns from content using regex
  - `batch_extract` - Extract patterns from multiple sources
  - `analyze_patterns` - Analyze extraction patterns for optimization
  - `build_pattern` - Build complex regex patterns interactively
  - `test_pattern` - Test regex patterns against sample content
  - `optimize_pattern` - Optimize regex patterns for performance
  
  ### Output Signals
  - `pattern.extracted` - Pattern extraction completed
  - `pattern.batch.completed` - Batch extraction completed
  - `pattern.analyzed` - Pattern analysis completed
  - `pattern.built` - Pattern building completed
  - `pattern.tested` - Pattern testing completed
  - `pattern.optimized` - Pattern optimization completed
  - `pattern.error` - Pattern extraction error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :regex_extractor,
    name: "regex_extractor_agent",
    description: "Manages intelligent regex pattern extraction and optimization workflows",
    category: "text_analysis",
    tags: ["regex", "pattern_extraction", "text_processing", "data_mining"],
    schema: [
      # Pattern management
      custom_patterns: [type: :map, default: %{}],
      pattern_usage_stats: [type: :map, default: %{}],
      
      # Extraction history
      extraction_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Batch operations
      active_batch_extractions: [type: :map, default: %{}],
      
      # Pattern optimization
      pattern_cache: [type: :map, default: %{}],
      cache_ttl: [type: :integer, default: 600_000], # 10 minutes
      
      # Performance metrics
      performance_metrics: [type: :map, default: %{
        total_extractions: 0,
        successful_extractions: 0,
        failed_extractions: 0,
        average_execution_time: 0,
        patterns_optimized: 0
      }],
      
      # Pattern recommendations
      pattern_suggestions: [type: {:list, :map}, default: []],
      
      # Content analysis
      content_insights: [type: :map, default: %{
        common_patterns: [],
        content_types_analyzed: %{},
        extraction_efficiency: %{}
      }]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchExtractAction,
      __MODULE__.AnalyzePatternsAction,
      __MODULE__.BuildPatternAction,
      __MODULE__.TestPatternAction,
      __MODULE__.OptimizePatternAction
    ]
  end
  
  # Action modules
  
  defmodule BatchExtractAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_extract",
      description: "Extract patterns from multiple content sources in batch",
      schema: [
        sources: [type: {:list, :map}, required: true, doc: "List of content sources to process"],
        pattern: [type: :string, required: false, doc: "Regex pattern to extract"],
        pattern_library: [type: :string, required: false, doc: "Pattern from library to use"],
        extraction_mode: [type: :atom, values: [:matches, :captures, :named_captures, :replace, :split, :scan, :count], default: :matches],
        parallel: [type: :boolean, default: true, doc: "Process sources in parallel"],
        aggregate_results: [type: :boolean, default: true, doc: "Combine results from all sources"]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      batch_id = generate_batch_id()
      
      # Validate that we have either pattern or pattern_library
      if is_nil(params.pattern) and is_nil(params.pattern_library) do
        {:error, "Either pattern or pattern_library must be specified"}
      else
        # Start batch operation
        batch_info = %{
          id: batch_id,
          sources: params.sources,
          pattern: params.pattern,
          pattern_library: params.pattern_library,
          extraction_mode: params.extraction_mode,
          started_at: DateTime.utc_now(),
          status: :in_progress
        }
        
        if params.parallel do
          execute_parallel_extractions(batch_info, params, agent)
        else
          execute_sequential_extractions(batch_info, params, agent)
        end
      end
    end
    
    defp generate_batch_id do
      "batch_#{System.unique_integer([:positive, :monotonic])}"
    end
    
    defp execute_parallel_extractions(batch_info, params, agent) do
      # Execute extractions in parallel using Task.async_stream
      results = batch_info.sources
      |> Task.async_stream(fn source -> 
        extract_from_source(source, batch_info, params, agent)
      end, timeout: 30_000, max_concurrency: 4)
      |> Enum.to_list()
      
      {successful, failed} = Enum.reduce(Enum.zip(batch_info.sources, results), {[], []}, 
        fn {source, result}, {success_acc, fail_acc} ->
          case result do
            {:ok, {:ok, extraction_result}} -> 
              {[%{source: source, result: extraction_result} | success_acc], fail_acc}
            {:ok, {:error, error}} -> 
              {success_acc, [%{source: source, error: error} | fail_acc]}
            {:exit, reason} -> 
              {success_acc, [%{source: source, error: "Task exited: #{inspect(reason)}"} | fail_acc]}
          end
        end)
      
      aggregated_results = if params.aggregate_results do
        aggregate_extraction_results(successful)
      else
        successful
      end
      
      {:ok, %{
        batch_id: batch_info.id,
        total_sources: length(batch_info.sources),
        successful_extractions: length(successful),
        failed_extractions: length(failed),
        results: aggregated_results,
        failures: failed,
        completed_at: DateTime.utc_now()
      }}
    end
    
    defp execute_sequential_extractions(batch_info, params, agent) do
      {successful, failed} = Enum.reduce(batch_info.sources, {[], []}, 
        fn source, {success_acc, fail_acc} ->
          case extract_from_source(source, batch_info, params, agent) do
            {:ok, result} -> 
              {[%{source: source, result: result} | success_acc], fail_acc}
            {:error, error} -> 
              {success_acc, [%{source: source, error: error} | fail_acc]}
          end
        end)
      
      aggregated_results = if params.aggregate_results do
        aggregate_extraction_results(successful)
      else
        Enum.reverse(successful)
      end
      
      {:ok, %{
        batch_id: batch_info.id,
        total_sources: length(batch_info.sources),
        successful_extractions: length(successful),
        failed_extractions: length(failed),
        results: aggregated_results,
        failures: Enum.reverse(failed),
        completed_at: DateTime.utc_now()
      }}
    end
    
    defp extract_from_source(source, batch_info, params, _agent) do
      # Build extraction parameters for this source
      extraction_params = %{
        content: source["content"] || source[:content] || "",
        pattern: batch_info.pattern,
        pattern_library: batch_info.pattern_library,
        extraction_mode: Atom.to_string(params.extraction_mode),
        output_format: "structured"
      }
      
      # Simulate extraction (would use actual RegexExtractor tool)
      case validate_extraction_params(extraction_params) do
        :ok ->
          simulate_extraction(extraction_params, source)
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp validate_extraction_params(params) do
      cond do
        String.length(params.content) == 0 -> 
          {:error, "Content is empty"}
        is_nil(params.pattern) and is_nil(params.pattern_library) -> 
          {:error, "No pattern specified"}
        true -> 
          :ok
      end
    end
    
    defp simulate_extraction(params, source) do
      # Simulate successful extraction
      matches = case params.pattern_library do
        "email" -> ["user@example.com", "admin@test.org"]
        "url" -> ["https://example.com", "http://test.org"]
        "ip_address" -> ["192.168.1.1", "10.0.0.1"]
        _ -> ["pattern_match_1", "pattern_match_2"]
      end
      
      # Filter matches based on content (simple simulation)
      actual_matches = Enum.take(matches, Enum.random(0..length(matches)))
      
      {:ok, %{
        source_name: source["name"] || source[:name] || "unknown",
        total_matches: length(actual_matches),
        results: actual_matches,
        extraction_mode: params.extraction_mode,
        pattern_used: params.pattern || params.pattern_library
      }}
    end
    
    defp aggregate_extraction_results(successful_extractions) do
      # Combine all results into aggregated statistics
      all_matches = successful_extractions
      |> Enum.flat_map(fn extraction -> extraction.result.results end)
      
      unique_matches = Enum.uniq(all_matches)
      
      %{
        total_matches: length(all_matches),
        unique_matches: length(unique_matches),
        matches_by_source: Enum.map(successful_extractions, fn extraction ->
          %{
            source: extraction.source["name"] || "unknown",
            matches: extraction.result.total_matches
          }
        end),
        all_matches: all_matches,
        unique_matches_list: unique_matches,
        pattern_effectiveness: calculate_pattern_effectiveness(successful_extractions)
      }
    end
    
    defp calculate_pattern_effectiveness(extractions) do
      if length(extractions) > 0 do
        total_matches = extractions
        |> Enum.map(fn ext -> ext.result.total_matches end)
        |> Enum.sum()
        
        average_matches = total_matches / length(extractions)
        
        effectiveness = cond do
          average_matches > 10 -> "high"
          average_matches > 3 -> "medium"
          average_matches > 0 -> "low"
          true -> "none"
        end
        
        %{
          average_matches_per_source: average_matches,
          effectiveness_rating: effectiveness
        }
      else
        %{average_matches_per_source: 0, effectiveness_rating: "none"}
      end
    end
  end
  
  defmodule AnalyzePatternsAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_patterns",
      description: "Analyze regex patterns for performance and optimization opportunities",
      schema: [
        patterns: [type: {:list, :string}, required: true, doc: "List of regex patterns to analyze"],
        sample_content: [type: :string, required: false, doc: "Sample content to test patterns against"],
        analysis_depth: [type: :atom, values: [:basic, :detailed, :comprehensive], default: :detailed]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      pattern_analyses = Enum.map(params.patterns, fn pattern ->
        analyze_single_pattern(pattern, params, agent)
      end)
      
      overall_analysis = %{
        total_patterns: length(pattern_analyses),
        complexity_distribution: analyze_complexity_distribution(pattern_analyses),
        performance_insights: generate_performance_insights(pattern_analyses),
        optimization_recommendations: generate_optimization_recommendations(pattern_analyses)
      }
      
      {:ok, %{
        pattern_analyses: pattern_analyses,
        overall_analysis: overall_analysis,
        analyzed_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_single_pattern(pattern, params, _agent) do
      %{
        pattern: pattern,
        complexity_score: estimate_pattern_complexity(pattern),
        potential_issues: identify_potential_issues(pattern),
        performance_estimate: estimate_performance(pattern),
        optimization_suggestions: suggest_optimizations(pattern),
        test_results: if(params.sample_content, do: test_pattern_on_sample(pattern, params.sample_content), else: nil)
      }
    end
    
    defp estimate_pattern_complexity(pattern) do
      # Simple complexity estimation
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
        matches = case Regex.run(regex, pattern) do
          nil -> 0
          _ -> 1
        end
        acc + (matches * weight)
      end)
    end
    
    defp identify_potential_issues(pattern) do
      issues = []
      
      # Check for catastrophic backtracking
      issues = if Regex.match?(~r/\([^)]*\*[^)]*\)\*/, pattern) do
        ["Potential catastrophic backtracking" | issues]
      else
        issues
      end
      
      # Check for overly broad patterns
      issues = if Regex.match?(~r/\.\*/, pattern) do
        ["Overly broad .* pattern" | issues]
      else
        issues
      end
      
      # Check for unescaped special characters
      issues = if Regex.match?(~r/[.+*?^${}()|\[\]\\]/, pattern) and not Regex.match?(~r/\\[.+*?^${}()|\[\]\\]/, pattern) do
        ["Unescaped special characters" | issues]
      else
        issues
      end
      
      issues
    end
    
    defp estimate_performance(pattern) do
      complexity = estimate_pattern_complexity(pattern)
      
      cond do
        complexity > 15 -> "poor"
        complexity > 8 -> "moderate"
        complexity > 3 -> "good"
        true -> "excellent"
      end
    end
    
    defp suggest_optimizations(pattern) do
      suggestions = []
      
      # Suggest specific quantifiers over greedy ones
      suggestions = if Regex.match?(~r/\.\*/, pattern) do
        ["Consider using specific quantifiers instead of .*" | suggestions]
      else
        suggestions
      end
      
      # Suggest anchoring
      suggestions = if not Regex.match?(~r/\^|\$/, pattern) do
        ["Consider anchoring pattern with ^ or $ for better performance" | suggestions]
      else
        suggestions
      end
      
      # Suggest non-capturing groups
      suggestions = if Regex.match?(~r/\([^?]/, pattern) do
        ["Consider using non-capturing groups (?:...) where captures aren't needed" | suggestions]
      else
        suggestions
      end
      
      suggestions
    end
    
    defp test_pattern_on_sample(pattern, sample_content) do
      try do
        case Regex.compile(pattern) do
          {:ok, regex} ->
            matches = Regex.scan(regex, sample_content)
            %{
              successful: true,
              match_count: length(matches),
              sample_matches: Enum.take(matches, 3)
            }
          {:error, {reason, _}} ->
            %{
              successful: false,
              error: "Compilation failed: #{reason}"
            }
        end
      rescue
        error ->
          %{
            successful: false,
            error: "Test failed: #{inspect(error)}"
          }
      end
    end
    
    defp analyze_complexity_distribution(analyses) do
      complexities = Enum.map(analyses, & &1.complexity_score)
      
      %{
        average_complexity: if(length(complexities) > 0, do: Enum.sum(complexities) / length(complexities), else: 0),
        max_complexity: if(length(complexities) > 0, do: Enum.max(complexities), else: 0),
        min_complexity: if(length(complexities) > 0, do: Enum.min(complexities), else: 0),
        distribution: Enum.frequencies_by(complexities, fn complexity ->
          cond do
            complexity <= 3 -> "simple"
            complexity <= 8 -> "moderate"
            complexity <= 15 -> "complex"
            true -> "very_complex"
          end
        end)
      }
    end
    
    defp generate_performance_insights(analyses) do
      performance_ratings = Enum.map(analyses, & &1.performance_estimate)
      
      %{
        performance_distribution: Enum.frequencies(performance_ratings),
        patterns_needing_optimization: Enum.count(performance_ratings, &(&1 in ["poor", "moderate"])),
        high_performance_patterns: Enum.count(performance_ratings, &(&1 in ["good", "excellent"]))
      }
    end
    
    defp generate_optimization_recommendations(analyses) do
      all_suggestions = analyses
      |> Enum.flat_map(& &1.optimization_suggestions)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_suggestion, count} -> -count end)
      
      %{
        top_recommendations: Enum.take(all_suggestions, 5),
        patterns_with_issues: Enum.count(analyses, fn analysis -> 
          length(analysis.potential_issues) > 0
        end)
      }
    end
  end
  
  defmodule BuildPatternAction do
    @moduledoc false
    use Jido.Action,
      name: "build_pattern",
      description: "Interactively build complex regex patterns with guidance",
      schema: [
        requirements: [type: :map, required: true, doc: "Pattern requirements specification"],
        target_content_type: [type: :string, default: "general", doc: "Type of content the pattern will match"],
        complexity_preference: [type: :atom, values: [:simple, :balanced, :comprehensive], default: :balanced],
        include_examples: [type: :boolean, default: true, doc: "Include example matches"]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Build pattern based on requirements
      pattern_components = analyze_requirements(params.requirements)
      base_pattern = construct_base_pattern(pattern_components, params)
      optimized_pattern = optimize_pattern_for_complexity(base_pattern, params.complexity_preference)
      
      # Generate examples and test cases
      examples = if params.include_examples do
        generate_pattern_examples(optimized_pattern, params.target_content_type)
      else
        []
      end
      
      {:ok, %{
        built_pattern: optimized_pattern,
        pattern_explanation: explain_pattern(optimized_pattern),
        complexity_analysis: %{
          complexity_score: estimate_pattern_complexity(optimized_pattern),
          readability: assess_readability(optimized_pattern),
          maintainability: assess_maintainability(optimized_pattern)
        },
        examples: examples,
        usage_recommendations: generate_usage_recommendations(optimized_pattern, params),
        built_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_requirements(requirements) do
      # Extract pattern components from requirements
      %{
        must_match: requirements["must_match"] || requirements[:must_match] || [],
        must_not_match: requirements["must_not_match"] || requirements[:must_not_match] || [],
        length_constraints: requirements["length"] || requirements[:length] || %{},
        character_sets: requirements["characters"] || requirements[:characters] || %{},
        anchoring: requirements["anchoring"] || requirements[:anchoring] || "none"
      }
    end
    
    defp construct_base_pattern(components, _params) do
      # Build pattern from components
      pattern_parts = []
      
      # Add anchoring
      pattern_parts = case components.anchoring do
        "start" -> ["^" | pattern_parts]
        "end" -> pattern_parts ++ ["$"]
        "both" -> ["^" | pattern_parts] ++ ["$"]
        _ -> pattern_parts
      end
      
      # Add character constraints
      pattern_parts = if Map.has_key?(components.character_sets, "allowed") do
        allowed = components.character_sets["allowed"]
        pattern_parts ++ ["[#{allowed}]"]
      else
        pattern_parts
      end
      
      # Add length constraints
      pattern_parts = if Map.has_key?(components.length_constraints, "min") or Map.has_key?(components.length_constraints, "max") do
        min = components.length_constraints["min"] || ""
        max = components.length_constraints["max"] || ""
        quantifier = "{#{min},#{max}}"
        pattern_parts ++ [quantifier]
      else
        pattern_parts
      end
      
      # Combine parts
      Enum.join(pattern_parts, "")
    end
    
    defp optimize_pattern_for_complexity(pattern, complexity_preference) do
      case complexity_preference do
        :simple -> simplify_pattern(pattern)
        :comprehensive -> enhance_pattern(pattern)
        :balanced -> pattern # Use as-is
      end
    end
    
    defp simplify_pattern(pattern) do
      # Simplify the pattern by removing unnecessary complexity
      pattern
      |> String.replace(~r/\(\?:[^)]+\)/, "(?:...)")
      |> String.replace(~r/\[\w+-\w+\]/, "\\w")
    end
    
    defp enhance_pattern(pattern) do
      # Add more comprehensive matching
      if not String.contains?(pattern, "?") do
        pattern <> "?"
      else
        pattern
      end
    end
    
    defp explain_pattern(pattern) do
      # Generate human-readable explanation
      explanations = []
      
      explanations = if String.starts_with?(pattern, "^") do
        ["Matches from the start of the line" | explanations]
      else
        explanations
      end
      
      explanations = if String.ends_with?(pattern, "$") do
        ["Matches until the end of the line" | explanations]
      else
        explanations
      end
      
      explanations = if String.contains?(pattern, "\\w") do
        ["Matches word characters (letters, digits, underscore)" | explanations]
      else
        explanations
      end
      
      explanations = if String.contains?(pattern, "*") do
        ["Matches zero or more of the preceding element" | explanations]
      else
        explanations
      end
      
      if length(explanations) > 0 do
        Enum.join(Enum.reverse(explanations), ". ")
      else
        "Custom pattern with specific matching rules"
      end
    end
    
    defp assess_readability(pattern) do
      # Simple readability assessment
      cond do
        String.length(pattern) > 100 -> "poor"
        String.length(pattern) > 50 -> "moderate"
        String.length(pattern) > 20 -> "good"
        true -> "excellent"
      end
    end
    
    defp assess_maintainability(pattern) do
      # Count complex constructs
      complex_constructs = [
        {~r/\(\?[^)]*\)/, "advanced groups"},
        {~r/\[\^[^\]]*\]/, "negated character classes"},
        {~r/\{\d+,\d+\}/, "specific quantifiers"}
      ]
      
      complexity_count = Enum.count(complex_constructs, fn {regex, _name} ->
        Regex.match?(regex, pattern)
      end)
      
      cond do
        complexity_count > 3 -> "challenging"
        complexity_count > 1 -> "moderate"
        complexity_count > 0 -> "manageable"
        true -> "simple"
      end
    end
    
    defp generate_pattern_examples(_pattern, content_type) do
      # Generate example strings that should match the pattern
      case content_type do
        "email" -> ["user@example.com", "admin@test.org", "contact@domain.co.uk"]
        "phone" -> ["+1-234-567-8900", "(555) 123-4567", "123.456.7890"]
        "url" -> ["https://example.com", "http://test.org/path", "https://sub.domain.com/page"]
        _ -> ["example1", "test_string", "sample123"]
      end
    end
    
    defp generate_usage_recommendations(pattern, params) do
      recommendations = []
      
      recommendations = if String.length(pattern) > 50 do
        ["Consider breaking this pattern into smaller, composable parts" | recommendations]
      else
        recommendations
      end
      
      recommendations = if params.complexity_preference == :simple do
        ["Test thoroughly as simplified patterns may have edge cases" | recommendations]
      else
        recommendations
      end
      
      recommendations = if String.contains?(pattern, ".*") do
        ["Be cautious with .* patterns in large texts to avoid performance issues" | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    defp estimate_pattern_complexity(pattern) do
      # Reuse complexity estimation from AnalyzePatternsAction
      complexity_factors = [
        {~r/\[.*\]/, 1},
        {~r/\(.*\)/, 2},
        {~r/\*|\+|\?/, 1},
        {~r/\{\d+,?\d*\}/, 2},
        {~r/\|/, 2},
        {~r/\\[wWdDsS]/, 1},
        {~r/\^|\$/, 1},
        {~r/\(\?[^)]*\)/, 3}
      ]
      
      Enum.reduce(complexity_factors, 1, fn {regex, weight}, acc ->
        matches = case Regex.run(regex, pattern) do
          nil -> 0
          _ -> 1
        end
        acc + (matches * weight)
      end)
    end
  end
  
  defmodule TestPatternAction do
    @moduledoc false
    use Jido.Action,
      name: "test_pattern",
      description: "Test regex patterns against sample content with detailed reporting",
      schema: [
        pattern: [type: :string, required: true, doc: "Regex pattern to test"],
        test_cases: [type: {:list, :map}, required: true, doc: "List of test cases with content and expected results"],
        performance_test: [type: :boolean, default: false, doc: "Include performance testing"],
        edge_case_testing: [type: :boolean, default: true, doc: "Test against common edge cases"]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Compile the pattern
      case Regex.compile(params.pattern) do
        {:ok, regex} ->
          # Run all test cases
          test_results = Enum.map(params.test_cases, fn test_case ->
            run_single_test(regex, test_case, params)
          end)
          
          # Run edge case tests if requested
          edge_case_results = if params.edge_case_testing do
            run_edge_case_tests(regex, params)
          else
            []
          end
          
          # Run performance tests if requested
          performance_results = if params.performance_test do
            run_performance_tests(regex, params)
          else
            nil
          end
          
          # Analyze results
          analysis = analyze_test_results(test_results, edge_case_results)
          
          {:ok, %{
            pattern: params.pattern,
            test_results: test_results,
            edge_case_results: edge_case_results,
            performance_results: performance_results,
            analysis: analysis,
            tested_at: DateTime.utc_now()
          }}
          
        {:error, {reason, _}} ->
          {:error, "Pattern compilation failed: #{reason}"}
      end
    end
    
    defp run_single_test(regex, test_case, _params) do
      content = test_case["content"] || test_case[:content] || ""
      expected = test_case["expected"] || test_case[:expected]
      description = test_case["description"] || test_case[:description] || "Test case"
      
      # Run the extraction
      matches = Regex.scan(regex, content)
      match_count = length(matches)
      
      # Determine if test passed
      test_passed = case expected do
        %{"match_count" => expected_count} ->
          match_count == expected_count
        %{"should_match" => true} ->
          match_count > 0
        %{"should_match" => false} ->
          match_count == 0
        %{"contains" => expected_matches} when is_list(expected_matches) ->
          flat_matches = List.flatten(matches)
          Enum.all?(expected_matches, fn expected_match ->
            expected_match in flat_matches
          end)
        _ ->
          true # If no specific expectation, consider it passed
      end
      
      %{
        description: description,
        content: content,
        expected: expected,
        actual_matches: matches,
        match_count: match_count,
        passed: test_passed,
        details: %{
          first_match_position: get_first_match_position(regex, content),
          all_matches: List.flatten(matches)
        }
      }
    end
    
    defp get_first_match_position(regex, content) do
      case Regex.run(regex, content, return: :index) do
        [{start, _length} | _] -> start
        _ -> nil
      end
    end
    
    defp run_edge_case_tests(regex, _params) do
      edge_cases = [
        %{content: "", description: "Empty string"},
        %{content: " ", description: "Single space"},
        %{content: "\n", description: "Single newline"},
        %{content: "\t", description: "Single tab"},
        %{content: String.duplicate("a", 1000), description: "Long string (1000 chars)"},
        %{content: "Special chars: !@#$%^&*()_+-=[]{}|;':,.<>?", description: "Special characters"},
        %{content: "Unicode: αβγδε ñáéíóú 中文", description: "Unicode characters"}
      ]
      
      Enum.map(edge_cases, fn edge_case ->
        matches = Regex.scan(regex, edge_case.content)
        %{
          description: edge_case.description,
          content: edge_case.content,
          match_count: length(matches),
          matches: matches,
          issues: identify_edge_case_issues(matches, edge_case)
        }
      end)
    end
    
    defp identify_edge_case_issues(matches, edge_case) do
      issues = []
      
      # Check if pattern unexpectedly matches empty content
      issues = if edge_case.content == "" and length(matches) > 0 do
        ["Pattern matches empty string" | issues]
      else
        issues
      end
      
      # Check for potential issues with special characters
      issues = if String.contains?(edge_case.description, "Special") and length(matches) == 0 do
        ["Pattern might not handle special characters" | issues]
      else
        issues
      end
      
      issues
    end
    
    defp run_performance_tests(regex, _params) do
      # Simple performance test with different content sizes
      test_sizes = [100, 1000, 10000]
      
      results = Enum.map(test_sizes, fn size ->
        content = String.duplicate("test content ", div(size, 12))
        
        {time_microseconds, matches} = :timer.tc(fn ->
          Regex.scan(regex, content)
        end)
        
        %{
          content_size: String.length(content),
          execution_time_microseconds: time_microseconds,
          matches_found: length(matches),
          performance_rating: rate_performance(time_microseconds, String.length(content))
        }
      end)
      
      %{
        test_results: results,
        overall_performance: calculate_overall_performance(results)
      }
    end
    
    defp rate_performance(time_microseconds, content_size) do
      time_per_char = time_microseconds / content_size
      
      cond do
        time_per_char > 10 -> "poor"
        time_per_char > 5 -> "moderate"
        time_per_char > 1 -> "good"
        true -> "excellent"
      end
    end
    
    defp calculate_overall_performance(results) do
      ratings = Enum.map(results, & &1.performance_rating)
      avg_time = results
      |> Enum.map(& &1.execution_time_microseconds)
      |> Enum.sum()
      |> div(length(results))
      
      %{
        average_execution_time: avg_time,
        performance_distribution: Enum.frequencies(ratings),
        scaling_behavior: analyze_scaling_behavior(results)
      }
    end
    
    defp analyze_scaling_behavior(results) do
      # Simple analysis of how performance scales with content size
      if length(results) >= 2 do
        first = hd(results)
        last = List.last(results)
        
        size_ratio = last.content_size / first.content_size
        time_ratio = last.execution_time_microseconds / first.execution_time_microseconds
        
        cond do
          time_ratio > size_ratio * 2 -> "poor_scaling"
          time_ratio > size_ratio * 1.5 -> "moderate_scaling"
          true -> "good_scaling"
        end
      else
        "insufficient_data"
      end
    end
    
    defp analyze_test_results(test_results, edge_case_results) do
      passed_tests = Enum.count(test_results, & &1.passed)
      total_tests = length(test_results)
      
      edge_case_issues = edge_case_results
      |> Enum.flat_map(& &1.issues)
      |> length()
      
      %{
        success_rate: if(total_tests > 0, do: passed_tests / total_tests * 100, else: 0),
        passed_tests: passed_tests,
        failed_tests: total_tests - passed_tests,
        edge_case_issues: edge_case_issues,
        overall_status: determine_overall_status(passed_tests, total_tests, edge_case_issues),
        recommendations: generate_test_recommendations(test_results, edge_case_results)
      }
    end
    
    defp determine_overall_status(passed, total, edge_issues) do
      success_rate = if total > 0, do: passed / total, else: 1
      
      cond do
        success_rate == 1 and edge_issues == 0 -> "excellent"
        success_rate >= 0.8 and edge_issues <= 1 -> "good"
        success_rate >= 0.6 -> "needs_improvement"
        true -> "poor"
      end
    end
    
    defp generate_test_recommendations(test_results, edge_case_results) do
      recommendations = []
      
      failed_tests = Enum.filter(test_results, &(not &1.passed))
      recommendations = if length(failed_tests) > 0 do
        ["Review failed test cases and adjust pattern accordingly" | recommendations]
      else
        recommendations
      end
      
      edge_issues = Enum.filter(edge_case_results, &(length(&1.issues) > 0))
      recommendations = if length(edge_issues) > 0 do
        ["Address edge case issues to improve pattern robustness" | recommendations]
      else
        recommendations
      end
      
      if length(recommendations) == 0 do
        ["Pattern performs well across all test cases"]
      else
        recommendations
      end
    end
  end
  
  defmodule OptimizePatternAction do
    @moduledoc false
    use Jido.Action,
      name: "optimize_pattern",
      description: "Optimize regex patterns for better performance and maintainability",
      schema: [
        pattern: [type: :string, required: true, doc: "Original pattern to optimize"],
        optimization_goals: [type: {:list, :atom}, default: [:performance, :readability], doc: "Optimization objectives"],
        sample_content: [type: :string, required: false, doc: "Sample content for testing optimizations"],
        preserve_functionality: [type: :boolean, default: true, doc: "Ensure optimized pattern maintains original functionality"]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Analyze the original pattern
      original_analysis = analyze_pattern_for_optimization(params.pattern)
      
      # Apply optimizations based on goals
      optimizations = Enum.reduce(params.optimization_goals, [], fn goal, acc ->
        case goal do
          :performance -> [optimize_for_performance(params.pattern) | acc]
          :readability -> [optimize_for_readability(params.pattern) | acc]
          :maintainability -> [optimize_for_maintainability(params.pattern) | acc]
          :size -> [optimize_for_size(params.pattern) | acc]
          _ -> acc
        end
      end) |> List.flatten() |> Enum.uniq()
      
      # Select best optimization
      best_optimization = select_best_optimization(params.pattern, optimizations, params)
      
      # Validate that functionality is preserved if required
      validation_result = if params.preserve_functionality and params.sample_content do
        validate_functionality_preserved(params.pattern, best_optimization.pattern, params.sample_content)
      else
        %{preserved: true, message: "Validation skipped"}
      end
      
      {:ok, %{
        original_pattern: params.pattern,
        optimized_pattern: best_optimization.pattern,
        optimization_applied: best_optimization.type,
        improvement_metrics: calculate_improvement_metrics(original_analysis, best_optimization),
        functionality_validation: validation_result,
        optimization_explanation: best_optimization.explanation,
        optimized_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_pattern_for_optimization(pattern) do
      %{
        length: String.length(pattern),
        complexity: estimate_pattern_complexity(pattern),
        performance_issues: identify_performance_issues(pattern),
        readability_score: assess_readability_score(pattern),
        maintainability_issues: identify_maintainability_issues(pattern)
      }
    end
    
    defp optimize_for_performance(pattern) do
      optimizations = []
      
      # Replace .* with more specific patterns
      optimizations = if String.contains?(pattern, ".*") do
        [%{
          type: "performance",
          pattern: String.replace(pattern, ".*", "[^\\s]*"),
          explanation: "Replaced .* with [^\\s]* for better performance",
          impact: "high"
        } | optimizations]
      else
        optimizations
      end
      
      # Add anchoring for better performance
      optimizations = if not (String.starts_with?(pattern, "^") or String.ends_with?(pattern, "$")) do
        [%{
          type: "performance",
          pattern: "^" <> pattern <> "$",
          explanation: "Added anchoring to prevent unnecessary backtracking",
          impact: "medium"
        } | optimizations]
      else
        optimizations
      end
      
      # Convert capturing groups to non-capturing where possible
      optimizations = if String.contains?(pattern, "(") and not String.contains?(pattern, "?:") do
        non_capturing_pattern = String.replace(pattern, "(", "(?:")
        [%{
          type: "performance",
          pattern: non_capturing_pattern,
          explanation: "Converted capturing groups to non-capturing for better performance",
          impact: "low"
        } | optimizations]
      else
        optimizations
      end
      
      optimizations
    end
    
    defp optimize_for_readability(pattern) do
      optimizations = []
      
      # Break long patterns into components
      optimizations = if String.length(pattern) > 50 do
        # This is a simplified example - real implementation would be more sophisticated
        [%{
          type: :readability,
          pattern: add_comments_to_pattern(pattern),
          explanation: "Added logical breaks for better readability",
          impact: "medium"
        } | optimizations]
      else
        optimizations
      end
      
      # Replace complex character classes with shortcuts
      optimizations = if String.contains?(pattern, "[a-zA-Z0-9_]") do
        readable_pattern = String.replace(pattern, "[a-zA-Z0-9_]", "\\w")
        [%{
          type: :readability,
          pattern: readable_pattern,
          explanation: "Replaced character class with \\w shortcut",
          impact: "low"
        } | optimizations]
      else
        optimizations
      end
      
      optimizations
    end
    
    defp optimize_for_maintainability(pattern) do
      # Focus on making patterns easier to modify and understand
      optimizations = []
      
      # Simplify nested groups
      optimizations = if String.contains?(pattern, "((") do
        [%{
          type: :maintainability,
          pattern: simplify_nested_groups(pattern),
          explanation: "Simplified nested groups for easier maintenance",
          impact: "medium"
        } | optimizations]
      else
        optimizations
      end
      
      optimizations
    end
    
    defp optimize_for_size(pattern) do
      # Focus on reducing pattern size
      optimizations = []
      
      # Use shortcuts for common patterns
      size_optimized = pattern
      |> String.replace("[0-9]", "\\d")
      |> String.replace("[a-zA-Z0-9_]", "\\w")
      |> String.replace("[ \\t\\n\\r\\f]", "\\s")
      
      if size_optimized != pattern do
        [%{
          type: :size,
          pattern: size_optimized,
          explanation: "Used character class shortcuts to reduce pattern size",
          impact: "low"
        } | optimizations]
      else
        optimizations
      end
      
      optimizations
    end
    
    defp select_best_optimization(original_pattern, optimizations, _params) do
      if length(optimizations) == 0 do
        %{
          type: :none,
          pattern: original_pattern,
          explanation: "No optimizations found",
          impact: "none"
        }
      else
        # Select optimization with highest impact that meets goals
        impact_priority = %{"high" => 3, "medium" => 2, "low" => 1, "none" => 0}
        
        best = Enum.max_by(optimizations, fn opt ->
          impact_priority[opt.impact] || 0
        end)
        
        best
      end
    end
    
    defp add_comments_to_pattern(pattern) do
      # Simplified pattern commenting (real implementation would be more sophisticated)
      "(?# Start of pattern) " <> pattern <> " (?# End of pattern)"
    end
    
    defp simplify_nested_groups(pattern) do
      # Simplified group flattening (real implementation would be more sophisticated)
      String.replace(pattern, "((", "(")
    end
    
    defp validate_functionality_preserved(original, optimized, sample_content) do
      try do
        {:ok, original_regex} = Regex.compile(original)
        {:ok, optimized_regex} = Regex.compile(optimized)
        
        original_matches = Regex.scan(original_regex, sample_content)
        optimized_matches = Regex.scan(optimized_regex, sample_content)
        
        preserved = original_matches == optimized_matches
        
        %{
          preserved: preserved,
          message: if preserved do
            "Functionality preserved - same matches found"
          else
            "Functionality changed - different matches found"
          end,
          original_match_count: length(original_matches),
          optimized_match_count: length(optimized_matches)
        }
      rescue
        error ->
          %{
            preserved: false,
            message: "Validation failed: #{inspect(error)}",
            error: true
          }
      end
    end
    
    defp calculate_improvement_metrics(original_analysis, optimization) do
      optimized_analysis = analyze_pattern_for_optimization(optimization.pattern)
      
      %{
        size_change: optimized_analysis.length - original_analysis.length,
        complexity_change: optimized_analysis.complexity - original_analysis.complexity,
        readability_improvement: optimized_analysis.readability_score - original_analysis.readability_score,
        performance_issues_resolved: length(original_analysis.performance_issues) - length(optimized_analysis.performance_issues)
      }
    end
    
    defp estimate_pattern_complexity(pattern) do
      # Reuse from other actions
      complexity_factors = [
        {~r/\[.*\]/, 1},
        {~r/\(.*\)/, 2},
        {~r/\*|\+|\?/, 1},
        {~r/\{\d+,?\d*\}/, 2},
        {~r/\|/, 2},
        {~r/\\[wWdDsS]/, 1},
        {~r/\^|\$/, 1},
        {~r/\(\?[^)]*\)/, 3}
      ]
      
      Enum.reduce(complexity_factors, 1, fn {regex, weight}, acc ->
        matches = case Regex.run(regex, pattern) do
          nil -> 0
          _ -> 1
        end
        acc + (matches * weight)
      end)
    end
    
    defp identify_performance_issues(pattern) do
      issues = []
      
      issues = if String.contains?(pattern, ".*.*") do
        ["Multiple .* patterns can cause catastrophic backtracking" | issues]
      else
        issues
      end
      
      issues = if String.contains?(pattern, "(.*)+") do
        ["Nested quantifiers can cause exponential time complexity" | issues]
      else
        issues
      end
      
      issues
    end
    
    defp assess_readability_score(pattern) do
      score = 100
      
      # Deduct points for complexity
      score = score - min(String.length(pattern), 50)
      score = score - (estimate_pattern_complexity(pattern) * 2)
      
      # Deduct points for hard-to-read constructs
      score = if String.contains?(pattern, "(?:") do
        score - 10
      else
        score
      end
      
      max(score, 0)
    end
    
    defp identify_maintainability_issues(pattern) do
      issues = []
      
      issues = if String.length(pattern) > 100 do
        ["Pattern is very long and may be hard to maintain" | issues]
      else
        issues
      end
      
      issues = if String.match?(pattern, ~r/\([^)]*\([^)]*\)/) do
        ["Nested groups make pattern hard to understand" | issues]
      else
        issues
      end
      
      issues
    end
  end
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "extract_pattern"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      content: data["content"],
      pattern: data["pattern"],
      pattern_library: data["pattern_library"],
      extraction_mode: data["extraction_mode"] || "matches",
      max_matches: data["max_matches"] || 0,
      output_format: data["output_format"] || "structured"
    }
    
    # Execute the extraction
    {:ok, agent, _directives} = __MODULE__.cmd(agent, ExecuteToolAction, %{params: params},
      context: %{agent: agent}
    )
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "batch_extract"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = __MODULE__.cmd(agent, BatchExtractAction, %{
      sources: data["sources"],
      pattern: data["pattern"],
      pattern_library: data["pattern_library"],
      extraction_mode: String.to_atom(data["extraction_mode"] || "matches"),
      parallel: data["parallel"] || true,
      aggregate_results: data["aggregate_results"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "analyze_patterns"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = __MODULE__.cmd(agent, AnalyzePatternsAction, %{
      patterns: data["patterns"],
      sample_content: data["sample_content"],
      analysis_depth: String.to_atom(data["analysis_depth"] || "detailed")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "build_pattern"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = __MODULE__.cmd(agent, BuildPatternAction, %{
      requirements: data["requirements"],
      target_content_type: data["target_content_type"] || "general",
      complexity_preference: String.to_atom(data["complexity_preference"] || "balanced"),
      include_examples: data["include_examples"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "test_pattern"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = __MODULE__.cmd(agent, TestPatternAction, %{
      pattern: data["pattern"],
      test_cases: data["test_cases"],
      performance_test: data["performance_test"] || false,
      edge_case_testing: data["edge_case_testing"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "optimize_pattern"} = signal) do
    %{"data" => data} = signal
    
    optimization_goals = (data["optimization_goals"] || ["performance", "readability"])
    |> Enum.map(&String.to_atom/1)
    
    {:ok, agent, _directives} = __MODULE__.cmd(agent, OptimizePatternAction, %{
      pattern: data["pattern"],
      optimization_goals: optimization_goals,
      sample_content: data["sample_content"],
      preserve_functionality: data["preserve_functionality"] || true
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  def handle_action_result(agent, BatchExtractAction, {:ok, result}, _metadata) do
    # Update batch extraction tracking
    agent = put_in(agent.state.active_batch_extractions[result.batch_id], %{
      status: :completed,
      result: result,
      completed_at: DateTime.utc_now()
    })
    
    # Update performance metrics
    agent = update_in(agent.state.performance_metrics, fn metrics ->
      metrics
      |> Map.update!(:total_extractions, &(&1 + result.total_sources))
      |> Map.update!(:successful_extractions, &(&1 + result.successful_extractions))
      |> Map.update!(:failed_extractions, &(&1 + result.failed_extractions))
    end)
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "pattern.batch.completed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, AnalyzePatternsAction, {:ok, result}, _metadata) do
    # Store pattern analysis results
    analysis_key = "patterns_#{DateTime.utc_now() |> DateTime.to_unix()}"
    agent = put_in(agent.state.pattern_cache[analysis_key], %{
      result: result,
      cached_at: DateTime.utc_now()
    })
    
    # Update pattern suggestions based on analysis
    suggestions = extract_pattern_suggestions(result)
    agent = put_in(agent.state.pattern_suggestions, suggestions)
    
    # Emit analysis complete signal
    signal = Jido.Signal.new!(%{
      type: "pattern.analyzed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, BuildPatternAction, {:ok, result}, _metadata) do
    # Add built pattern to custom patterns library
    pattern_name = "built_#{DateTime.utc_now() |> DateTime.to_unix()}"
    agent = put_in(agent.state.custom_patterns[pattern_name], %{
      pattern: result.built_pattern,
      explanation: result.pattern_explanation,
      created_at: DateTime.utc_now(),
      complexity: result.complexity_analysis.complexity_score
    })
    
    # Emit pattern built signal
    signal = Jido.Signal.new!(%{
      type: "pattern.built",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, TestPatternAction, {:ok, result}, _metadata) do
    # Update pattern usage statistics based on test results
    pattern_key = "pattern_#{result.pattern |> :crypto.hash(:md5) |> Base.encode16()}"
    agent = update_in(agent.state.pattern_usage_stats, fn stats ->
      Map.update(stats, pattern_key, %{
        pattern: result.pattern,
        test_count: 1,
        success_rate: result.analysis.success_rate,
        last_tested: DateTime.utc_now()
      }, fn existing ->
        %{existing |
          test_count: existing.test_count + 1,
          success_rate: (existing.success_rate + result.analysis.success_rate) / 2,
          last_tested: DateTime.utc_now()
        }
      end)
    end)
    
    # Emit pattern tested signal
    signal = Jido.Signal.new!(%{
      type: "pattern.tested",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, OptimizePatternAction, {:ok, result}, _metadata) do
    # Update performance metrics
    agent = update_in(agent.state.performance_metrics.patterns_optimized, &(&1 + 1))
    
    # Store optimized pattern if it's significantly better
    updated_agent = if result.improvement_metrics.complexity_change < -2 do
      optimization_key = "optimized_#{DateTime.utc_now() |> DateTime.to_unix()}"
      put_in(agent.state.custom_patterns[optimization_key], %{
        original_pattern: result.original_pattern,
        optimized_pattern: result.optimized_pattern,
        optimization_type: result.optimization_applied,
        improvement: result.improvement_metrics,
        created_at: DateTime.utc_now()
      })
    else
      agent
    end
    
    # Emit pattern optimized signal
    signal = Jido.Signal.new!(%{
      type: "pattern.optimized",
      source: "agent:#{updated_agent.id}",
      data: result
    })
    emit_signal(updated_agent, signal)
    
    {:ok, updated_agent}
  end
  
  # Handle main tool execution results
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, _metadata) do
    # Record successful extraction
    extraction_record = %{
      pattern: result.pattern,
      extraction_mode: result.extraction_mode,
      total_matches: result.total_matches,
      content_length: result.metadata.content_length,
      execution_time: result.metadata.execution_time,
      timestamp: DateTime.utc_now()
    }
    
    # Add to history
    agent = update_in(agent.state.extraction_history, fn history ->
      new_history = [extraction_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update content insights
    agent = update_content_insights(agent, result)
    
    # Update performance metrics
    agent = update_in(agent.state.performance_metrics, fn metrics ->
      new_total = metrics.total_extractions + 1
      new_successful = metrics.successful_extractions + 1
      new_avg_time = ((metrics.average_execution_time * metrics.total_extractions) + result.metadata.execution_time) / new_total
      
      metrics
      |> Map.put(:total_extractions, new_total)
      |> Map.put(:successful_extractions, new_successful)
      |> Map.put(:average_execution_time, new_avg_time)
    end)
    
    # Emit success signal
    signal = Jido.Signal.new!(%{
      type: "pattern.extracted",
      source: "agent:#{agent.id}",
      data: %{
        pattern: result.pattern,
        total_matches: result.total_matches,
        extraction_mode: result.extraction_mode
      }
    })
    emit_signal(agent, signal)
    
    # Return updated agent
    {:ok, agent}
  end
  
  def handle_action_result(agent, ExecuteToolAction, {:error, reason}, metadata) do
    # Update failure metrics
    agent = update_in(agent.state.performance_metrics.failed_extractions, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "pattern.error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    emit_signal(agent, signal)
    
    # Return updated agent
    {:ok, agent}
  end
  
  # Helper functions
  
  defp extract_pattern_suggestions(analysis_result) do
    # Extract actionable suggestions from pattern analysis
    analysis_result.overall_analysis.optimization_recommendations.top_recommendations
    |> Enum.take(3)
    |> Enum.map(fn {suggestion, frequency} ->
      %{
        suggestion: suggestion,
        frequency: frequency,
        priority: determine_suggestion_priority(suggestion),
        created_at: DateTime.utc_now()
      }
    end)
  end
  
  defp determine_suggestion_priority(suggestion) do
    cond do
      String.contains?(suggestion, "performance") -> :high
      String.contains?(suggestion, "optimization") -> :high
      String.contains?(suggestion, "readability") -> :medium
      true -> :low
    end
  end
  
  defp update_content_insights(agent, result) do
    # Update insights based on extraction results
    agent = update_in(agent.state.content_insights.common_patterns, fn patterns ->
      if result.total_matches > 0 do
        [result.pattern | patterns] |> Enum.take(10) |> Enum.uniq()
      else
        patterns
      end
    end)
    
    # Update content type analysis
    content_type = infer_content_type(result)
    agent = update_in(agent.state.content_insights.content_types_analyzed, fn types ->
      Map.update(types, content_type, 1, &(&1 + 1))
    end)
    
    # Update extraction efficiency
    efficiency = result.statistics.extraction_efficiency
    agent = update_in(agent.state.content_insights.extraction_efficiency, fn eff_map ->
      Map.update(eff_map, result.extraction_mode, [efficiency], &([efficiency | &1] |> Enum.take(10)))
    end)
    
    agent
  end
  
  defp infer_content_type(result) do
    # Simple content type inference based on pattern and results
    cond do
      String.contains?(result.pattern, "@") -> "email_content"
      String.contains?(result.pattern, "http") -> "web_content"
      String.contains?(result.pattern, "\\d") -> "numeric_content"
      result.metadata.content_length > 10000 -> "large_text"
      true -> "general_text"
    end
  end
end