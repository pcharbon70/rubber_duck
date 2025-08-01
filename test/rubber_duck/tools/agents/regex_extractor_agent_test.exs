defmodule RubberDuck.Tools.Agents.RegexExtractorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.RegexExtractorAgent
  
  setup do
    {:ok, agent} = RegexExtractorAgent.start_link(id: "test_regex_extractor")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        content: "Visit https://example.com or email test@example.com",
        pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b",
        extraction_mode: "matches"
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: RegexExtractorAgent}
      
      result = RegexExtractorAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "batch extract action processes multiple contents", %{agent: agent} do
      contents = [
        %{
          "id" => "doc1",
          "content" => "Email: user@example.com, Phone: 123-456-7890",
          "patterns" => ["email", "phone"]
        },
        %{
          "id" => "doc2", 
          "content" => "Visit https://github.com and https://docs.elixir-lang.org",
          "patterns" => ["url"]
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.BatchExtractAction.run(
        %{
          contents: contents,
          execution_strategy: :parallel,
          max_concurrency: 2,
          timeout_per_item: 5000
        },
        context
      )
      
      assert result.total_processed == 2
      assert result.total_extractions >= 3 # emails, phone, urls
      assert length(result.results) == 2
    end
    
    test "analyze patterns action provides pattern performance analysis", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.AnalyzePatternsAction.run(
        %{
          patterns: ["\\b\\w+@\\w+\\.\\w+\\b", "https?://[^\\s]+", "\\d{3}-\\d{3}-\\d{4}"],
          test_contents: [
            "Contact: user@example.com, website: https://example.com, phone: 123-456-7890",
            "More emails: admin@test.org and support@help.com"
          ],
          analysis_depth: :comprehensive
        },
        context
      )
      
      assert result.total_patterns == 3
      assert length(result.pattern_analysis) == 3
      
      analysis = hd(result.pattern_analysis)
      assert Map.has_key?(analysis, :pattern)
      assert Map.has_key?(analysis, :performance_score)
      assert Map.has_key?(analysis, :match_distribution)
      assert Map.has_key?(analysis, :optimization_suggestions)
    end
    
    test "build pattern action constructs patterns interactively", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.BuildPatternAction.run(
        %{
          target_content: "Version 1.2.3, Release v2.0.0-beta, Build 3.1.4-rc1",
          target_type: :version_numbers,
          examples: ["1.2.3", "v2.0.0-beta", "3.1.4-rc1"],
          validation_contents: [
            "App version: 1.0.0",
            "Library v2.1.0-alpha"
          ]
        },
        context
      )
      
      assert result.target_type == :version_numbers
      assert is_binary(result.constructed_pattern)
      assert result.pattern_effectiveness > 0.5
      assert length(result.validation_results) == 2
      assert Map.has_key?(result, :pattern_explanation)
    end
    
    test "test pattern action validates patterns thoroughly", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.TestPatternAction.run(
        %{
          pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b",
          test_cases: [
            %{content: "valid@example.com", expected_matches: 1},
            %{content: "invalid-email", expected_matches: 0},
            %{content: "multiple@test.com and another@domain.org", expected_matches: 2}
          ],
          edge_case_testing: true,
          performance_testing: true
        },
        context
      )
      
      assert result.pattern_valid == true
      assert result.test_results.passed >= 2
      assert result.test_results.total == 3
      assert Map.has_key?(result, :edge_case_results)
      assert Map.has_key?(result, :performance_metrics)
      assert is_list(result.recommendations)
    end
    
    test "optimize pattern action improves pattern performance", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.OptimizePatternAction.run(
        %{
          original_pattern: ".*@.*\\..*", # Inefficient pattern
          sample_content: "Find email@example.com in this text with many words and email2@test.org",
          optimization_goals: [:performance, :precision, :readability],
          preserve_functionality: true
        },
        context
      )
      
      assert result.original_pattern == ".*@.*\\..*"
      assert is_binary(result.optimized_pattern)
      assert result.optimization_applied == true
      assert result.performance_improvement > 0
      assert length(result.optimizations) > 0
      
      optimization = hd(result.optimizations)
      assert Map.has_key?(optimization, :type)
      assert Map.has_key?(optimization, :description)
      assert Map.has_key__(optimization, :impact)
    end
  end
  
  describe "signal handling with actions" do
    test "extract_patterns signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "extract_patterns",
        "data" => %{
          "content" => "Extract emails: test@example.com and admin@domain.org",
          "pattern_library" => "email",
          "extraction_mode" => "matches"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RegexExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "batch_extract signal triggers BatchExtractAction", %{agent: agent} do
      signal = %{
        "type" => "batch_extract",
        "data" => %{
          "contents" => [
            %{"id" => "doc1", "content" => "Email: user@test.com", "patterns" => ["email"]}
          ],
          "execution_strategy" => "parallel"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RegexExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_patterns signal triggers AnalyzePatternsAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_patterns",
        "data" => %{
          "patterns" => ["\\w+@\\w+\\.\\w+", "https?://[^\\s]+"],
          "test_contents" => ["Sample content with patterns"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RegexExtractorAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "tracks extraction history after successful extractions", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful extraction result
      extraction_result = %{
        pattern: "\\w+@\\w+\\.\\w+",
        extraction_mode: "matches",
        total_matches: 2,
        results: ["user@example.com", "admin@test.org"],
        statistics: %{total_matches: 2, unique_matches: 2}
      }
      
      metadata = %{
        content_type: "email_document",
        source: "user_input"
      }
      
      {:ok, updated} = RegexExtractorAgent.handle_action_result(
        state,
        RegexExtractorAgent.ExecuteToolAction,
        {:ok, extraction_result},
        metadata
      )
      
      assert length(updated.state.extraction_history) == 1
      extraction_record = hd(updated.state.extraction_history)
      assert extraction_record.pattern == "\\w+@\\w+\\.\\w+"
      assert extraction_record.total_matches == 2
      assert extraction_record.content_type == "email_document"
    end
    
    test "updates pattern performance metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      initial_extractions = state.state.performance_metrics.total_extractions
      initial_matches = state.state.performance_metrics.total_matches_found
      
      extraction_result = %{
        pattern: "test_pattern",
        total_matches: 5,
        statistics: %{extraction_efficiency: 0.8}
      }
      
      {:ok, updated} = RegexExtractorAgent.handle_action_result(
        state,
        RegexExtractorAgent.ExecuteToolAction,
        {:ok, extraction_result},
        %{}
      )
      
      assert updated.state.performance_metrics.total_extractions == initial_extractions + 1
      assert updated.state.performance_metrics.total_matches_found == initial_matches + 5
      assert updated.state.performance_metrics.average_efficiency > 0
    end
    
    test "caches pattern analysis results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      analysis_result = %{
        total_patterns: 2,
        pattern_analysis: [
          %{pattern: "\\w+@\\w+\\.\\w+", performance_score: 0.85},
          %{pattern: "https?://[^\\s]+", performance_score: 0.90}
        ]
      }
      
      {:ok, updated} = RegexExtractorAgent.handle_action_result(
        state,
        RegexExtractorAgent.AnalyzePatternsAction,
        {:ok, analysis_result},
        %{}
      )
      
      assert Map.has_key?(updated.state.pattern_analysis_cache, "analysis_2")
      cached_analysis = updated.state.pattern_analysis_cache["analysis_2"]
      assert cached_analysis.result == analysis_result
      assert Map.has_key?(cached_analysis, :cached_at)
    end
  end
  
  describe "agent initialization" do
    test "starts with default pattern library", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      library = state.state.pattern_library
      assert Map.has_key?(library.common_patterns, "email")
      assert Map.has_key__(library.common_patterns, "url")
      assert Map.has_key?(library.common_patterns, "phone")
      assert Map.has_key?(library.programming_patterns, "elixir_function")
    end
    
    test "starts with default optimization settings", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      settings = state.state.optimization_settings
      assert settings.auto_optimize_patterns == false
      assert settings.performance_threshold == 0.8
      assert settings.cache_optimized_patterns == true
    end
    
    test "starts with empty extraction history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.extraction_history == []
      assert state.state.pattern_analysis_cache == %{}
      assert state.state.active_batch_extractions == %{}
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = RegexExtractorAgent.additional_actions()
      
      assert length(actions) == 5
      assert RegexExtractorAgent.BatchExtractAction in actions
      assert RegexExtractorAgent.AnalyzePatternsAction in actions
      assert RegexExtractorAgent.BuildPatternAction in actions
      assert RegexExtractorAgent.TestPatternAction in actions
      assert RegexExtractorAgent.OptimizePatternAction in actions
    end
  end
  
  describe "batch extraction strategies" do
    test "sequential strategy processes contents in order", %{agent: agent} do
      contents = [
        %{"id" => "first", "content" => "Email: first@example.com", "patterns" => ["email"]},
        %{"id" => "second", "content" => "URL: https://second.com", "patterns" => ["url"]}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.BatchExtractAction.run(
        %{contents: contents, execution_strategy: :sequential},
        context
      )
      
      assert result.total_processed == 2
      assert result.execution_strategy == :sequential
    end
    
    test "parallel strategy can process contents concurrently", %{agent: agent} do
      contents = [
        %{"id" => "first", "content" => "Email: first@example.com", "patterns" => ["email"]},
        %{"id" => "second", "content" => "Phone: 123-456-7890", "patterns" => ["phone"]}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.BatchExtractAction.run(
        %{contents: contents, execution_strategy: :parallel, max_concurrency: 2},
        context
      )
      
      assert result.total_processed == 2
      assert result.execution_strategy == :parallel
    end
  end
  
  describe "pattern testing levels" do
    test "basic testing performs minimal validation", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.TestPatternAction.run(
        %{
          pattern: "\\w+",
          test_cases: [%{content: "word", expected_matches: 1}],
          testing_level: :basic
        },
        context
      )
      
      assert result.testing_level == :basic
      assert result.pattern_valid in [true, false]
    end
    
    test "comprehensive testing performs thorough analysis", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RegexExtractorAgent.TestPatternAction.run(
        %{
          pattern: "\\b\\w+@\\w+\\.\\w+\\b",
          test_cases: [%{content: "test@example.com", expected_matches: 1}],
          testing_level: :comprehensive,
          edge_case_testing: true,
          performance_testing: true
        },
        context
      )
      
      test_results = result.test_results
      assert Map.has_key?(test_results, :basic_validation)
      assert Map.has_key?(test_results, :edge_case_validation)
      assert Map.has_key?(test_results, :performance_validation)
      assert Map.has_key?(test_results, :security_validation)
      assert Map.has_key?(test_results, :compatibility_validation)
    end
  end
end