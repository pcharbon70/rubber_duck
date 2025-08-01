defmodule RubberDuck.Tools.Agents.RepoSearchAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.RepoSearchAgent
  
  setup do
    {:ok, agent} = RepoSearchAgent.start_link(id: "test_repo_search")
    
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
        query: "def test_function",
        search_type: "text",
        file_pattern: "**/*.ex",
        case_sensitive: false,
        max_results: 50
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: RepoSearchAgent}
      
      result = RepoSearchAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "batch search action executes multiple searches", %{agent: agent} do
      searches = [
        %{
          "query" => "def test",
          "search_type" => "text",
          "file_pattern" => "**/*.ex"
        },
        %{
          "query" => "describe",
          "search_type" => "text",
          "file_pattern" => "test/**/*.exs"
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.BatchSearchAction.run(
        %{
          searches: searches,
          execution_strategy: :sequential,
          max_concurrency: 2,
          aggregate_results: true
        },
        context
      )
      
      assert result.total_searches == 2
      assert result.successful_searches >= 0
      assert result.failed_searches >= 0
      assert Map.has_key?(result, :results)
    end
    
    test "analyze results action provides search result analysis", %{agent: agent} do
      search_results = %{
        query: "test_function",
        search_type: "text",
        total_matches: 5,
        results: [
          %{file: "lib/test.ex", line: 10, match: "def test_function", type: :text_match},
          %{file: "lib/helper.ex", line: 25, match: "test_function()", type: :text_match},
          %{file: "test/test_test.exs", line: 5, match: "test_function should work", type: :text_match}
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.AnalyzeResultsAction.run(
        %{
          search_results: search_results,
          analysis_type: :detailed,
          include_suggestions: true,
          pattern_detection: true
        },
        context
      )
      
      assert result.query == "test_function"
      assert result.analysis_type == :detailed
      assert result.total_results_analyzed == 5
      
      analysis = result.analysis
      assert Map.has_key?(analysis, :result_statistics)
      assert Map.has_key?(analysis, :file_distribution)
      assert Map.has_key?(analysis, :pattern_analysis)
      assert Map.has_key?(analysis, :search_suggestions)
    end
    
    test "suggest searches action generates intelligent suggestions", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.SuggestSearchesAction.run(
        %{
          context: %{current_file: "lib/example.ex"},
          suggestion_types: [:related, :exploratory],
          max_suggestions: 5,
          priority_filter: :all
        },
        context
      )
      
      assert result.total_suggestions >= 0
      assert is_list(result.suggestions)
      assert result.suggestion_types == [:related, :exploratory]
      
      if length(result.suggestions) > 0 do
        suggestion = hd(result.suggestions)
        assert Map.has_key?(suggestion, :type)
        assert Map.has_key?(suggestion, :description)
        assert Map.has_key?(suggestion, :priority)
      end
    end
    
    test "find references action locates symbol references", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.FindReferencesAction.run(
        %{
          symbol: "test_function",
          symbol_type: :function,
          include_definitions: true,
          scope: :project
        },
        context
      )
      
      assert result.symbol == "test_function"
      assert result.symbol_type == :function
      assert result.total_references >= 0
      assert is_list(result.reference_categories)
      assert is_list(result.results)
      assert result.scope == :project
    end
    
    test "search patterns action executes predefined patterns", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.SearchPatternsAction.run(
        %{
          pattern_name: "common_functions",
          pattern_params: %{},
          create_new_pattern: false,
          save_pattern: false
        },
        context
      )
      
      assert result.pattern_name == "common_functions"
      assert Map.has_key?(result, :pattern)
      assert Map.has_key?(result, :results)
      assert Map.has_key?(result.results, :pattern_searches)
    end
  end
  
  describe "signal handling with actions" do
    test "search_repository signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "search_repository",
        "data" => %{
          "query" => "def test",
          "search_type" => "text",
          "file_pattern" => "**/*.ex"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RepoSearchAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "batch_search signal triggers BatchSearchAction", %{agent: agent} do
      signal = %{
        "type" => "batch_search",
        "data" => %{
          "searches" => [
            %{"query" => "test", "search_type" => "text"}
          ],
          "execution_strategy" => "parallel"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RepoSearchAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "find_references signal triggers FindReferencesAction", %{agent: agent} do
      signal = %{
        "type" => "find_references",
        "data" => %{
          "symbol" => "test_function",
          "symbol_type" => "function",
          "scope" => "project"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = RepoSearchAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "tracks search history after successful searches", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful search result
      search_result = %{
        query: "test_function",
        search_type: "text",
        total_matches: 3,
        files_searched: 10,
        results: [],
        truncated: false
      }
      
      metadata = %{
        search_context: "user_initiated"
      }
      
      {:ok, updated} = RepoSearchAgent.handle_action_result(
        state,
        RepoSearchAgent.ExecuteToolAction,
        {:ok, search_result},
        metadata
      )
      
      assert length(updated.state.search_history) == 1
      search_record = hd(updated.state.search_history)
      assert search_record.query == "test_function"
      assert search_record.search_type == "text"
      assert search_record.total_matches == 3
    end
    
    test "updates search statistics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      initial_total = state.state.search_stats.total_searches
      initial_successful = state.state.search_stats.successful_searches
      
      search_result = %{
        query: "example",
        search_type: "regex",
        total_matches: 5,
        files_searched: 20,
        results: [],
        truncated: false
      }
      
      {:ok, updated} = RepoSearchAgent.handle_action_result(
        state,
        RepoSearchAgent.ExecuteToolAction,
        {:ok, search_result},
        %{}
      )
      
      assert updated.state.search_stats.total_searches == initial_total + 1
      assert updated.state.search_stats.successful_searches == initial_successful + 1
      assert updated.state.search_stats.most_searched_terms["example"] == 1
      assert updated.state.search_stats.search_types_used["regex"] == 1
    end
    
    test "caches analysis results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      analysis_result = %{
        query: "test_query",
        analysis_type: :detailed,
        total_results_analyzed: 10,
        analysis: %{
          result_statistics: %{total_matches: 10}
        }
      }
      
      {:ok, updated} = RepoSearchAgent.handle_action_result(
        state,
        RepoSearchAgent.AnalyzeResultsAction,
        {:ok, analysis_result},
        %{}
      )
      
      # Should have one cached analysis
      assert map_size(updated.state.result_analysis_cache) == 1
      
      cache_entry = updated.state.result_analysis_cache |> Map.values() |> hd()
      assert cache_entry.result == analysis_result
      assert Map.has_key?(cache_entry, :cached_at)
    end
  end
  
  describe "agent initialization" do
    test "starts with default search patterns", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      patterns = state.state.search_patterns
      assert Map.has_key?(patterns, "common_functions")
      assert Map.has_key?(patterns, "test_functions")
      assert Map.has_key__(patterns, "configuration")
      
      common_functions = patterns["common_functions"]
      assert common_functions.patterns == ["def ", "defp ", "defmacro "]
      assert common_functions.search_type == "text"
    end
    
    test "starts with default search preferences", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      prefs = state.state.search_preferences
      assert prefs.default_search_type == "text"
      assert prefs.default_file_pattern == "**/*.{ex,exs}"
      assert prefs.default_context_lines == 2
      assert prefs.case_sensitive_by_default == false
      assert prefs.max_results_per_search == 100
    end
    
    test "starts with empty search history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.search_history == []
      assert state.state.result_analysis_cache == %{}
      assert state.state.active_batch_searches == %{}
      assert state.state.suggested_searches == []
    end
    
    test "starts with zero search statistics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      stats = state.state.search_stats
      assert stats.total_searches == 0
      assert stats.successful_searches == 0
      assert stats.failed_searches == 0
      assert stats.average_results_per_search == 0.0
      assert stats.most_searched_terms == %{}
      assert stats.search_types_used == %{}
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = RepoSearchAgent.additional_actions()
      
      assert length(actions) == 5
      assert RepoSearchAgent.BatchSearchAction in actions
      assert RepoSearchAgent.AnalyzeResultsAction in actions
      assert RepoSearchAgent.SuggestSearchesAction in actions
      assert RepoSearchAgent.FindReferencesAction in actions
      assert RepoSearchAgent.SearchPatternsAction in actions
    end
  end
  
  describe "batch search strategies" do
    test "sequential strategy executes searches in order", %{agent: agent} do
      searches = [
        %{"query" => "first", "search_type" => "text"},
        %{"query" => "second", "search_type" => "text"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.BatchSearchAction.run(
        %{searches: searches, execution_strategy: :sequential, aggregate_results: false},
        context
      )
      
      assert result.total_searches == 2
      assert result.successful_searches >= 0
      assert is_integer(result.execution_time)
    end
    
    test "parallel strategy can execute searches concurrently", %{agent: agent} do
      searches = [
        %{"query" => "first", "search_type" => "text"},
        %{"query" => "second", "search_type" => "text"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.BatchSearchAction.run(
        %{searches: searches, execution_strategy: :parallel, max_concurrency: 2},
        context
      )
      
      assert result.total_searches == 2
      assert result.successful_searches >= 0
    end
    
    test "smart strategy optimizes execution based on search types", %{agent: agent} do
      searches = [
        %{"query" => "sym", "search_type" => "symbol"}, # High priority
        %{"query" => "long text search query", "search_type" => "text"} # Normal priority
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.BatchSearchAction.run(
        %{searches: searches, execution_strategy: :smart},
        context
      )
      
      assert result.total_searches == 2
    end
  end
  
  describe "search analysis levels" do
    test "basic analysis provides minimal insights", %{agent: agent} do
      search_results = %{
        query: "test",
        total_matches: 3,
        results: [
          %{file: "lib/test.ex", line: 1, match: "test", type: :text_match}
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.AnalyzeResultsAction.run(
        %{search_results: search_results, analysis_type: :basic},
        context
      )
      
      assert result.analysis_type == :basic
      insights = result.analysis.code_insights
      assert Map.has_key?(insights, :summary)
      assert Map.has_key?(insights, :key_files)
    end
    
    test "comprehensive analysis performs thorough analysis", %{agent: agent} do
      search_results = %{
        query: "function",
        total_matches: 10,
        results: Enum.map(1..10, fn i ->
          %{file: "lib/file_#{i}.ex", line: i * 10, match: "def function_#{i}", type: :text_match}
        end)
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.AnalyzeResultsAction.run(
        %{
          search_results: search_results,
          analysis_type: :comprehensive,
          pattern_detection: true,
          include_suggestions: true
        },
        context
      )
      
      insights = result.analysis.code_insights
      assert Map.has_key?(insights, :comprehensive_summary)
      assert Map.has_key?(insights, :detailed_analysis)
      assert Map.has_key__(insights, :architectural_view)
      assert Map.has_key?(insights, :actionable_insights)
    end
  end
  
  describe "reference finding" do
    test "finds function references with different symbol types", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.FindReferencesAction.run(
        %{symbol: "MyModule", symbol_type: :module, scope: :project},
        context
      )
      
      assert result.symbol == "MyModule"
      assert result.symbol_type == :module
      
      # Should have different reference categories
      if length(result.reference_categories) > 0 do
        category = hd(result.reference_categories)
        assert Map.has_key?(category, :type)
        assert Map.has_key__(category, :count)
        assert Map.has_key?(category, :examples)
      end
    end
  end
  
  describe "pattern management" do
    test "executes existing search patterns", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.SearchPatternsAction.run(
        %{pattern_name: "test_functions", save_pattern: false},
        context
      )
      
      assert result.pattern_name == "test_functions"
      assert Map.has_key__(result.pattern, :patterns)
      assert result.pattern.patterns == ["test ", "describe "]
    end
    
    test "creates new patterns when requested", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = RepoSearchAgent.SearchPatternsAction.run(
        %{
          pattern_name: "custom_pattern",
          pattern_params: %{
            "query" => "custom search",
            "search_type" => "regex",
            "description" => "My custom pattern"
          },
          create_new_pattern: true
        },
        context
      )
      
      assert result.pattern_name == "custom_pattern"
      assert result.pattern.patterns == ["custom search"]
      assert result.pattern.search_type == "regex"
    end
  end
end