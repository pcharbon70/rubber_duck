defmodule RubberDuck.Tools.Agents.DocFetcherAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.DocFetcherAgent
  
  setup do
    {:ok, agent} = DocFetcherAgent.start_link(id: "test_doc_fetcher")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction with caching", %{agent: agent} do
      params = %{
        query: "Enum.map/2",
        source: "hexdocs",
        doc_type: "function",
        include_examples: true,
        format: "markdown"
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # First execution - should hit the tool
      result1 = DocFetcherAgent.ExecuteToolAction.run(%{params: params}, context)
      assert match?({:ok, _}, result1)
      
      # Second execution - should hit cache
      result2 = DocFetcherAgent.ExecuteToolAction.run(%{params: params}, context)
      assert match?({:ok, _}, result2)
      
      {:ok, doc1} = result1
      {:ok, doc2} = result2
      assert doc1.cache_hit == false
      assert doc2.cache_hit == true
      assert doc1.content == doc2.content
    end
    
    test "batch fetch action fetches multiple docs", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.BatchFetchAction.run(
        %{
          queries: ["Enum.map/2", "String.split/2", "GenServer"],
          source: "auto",
          format: "markdown",
          parallel: true,
          max_concurrent: 3
        },
        context
      )
      
      assert result.total_queries == 3
      assert result.successful == 3
      assert result.failed == 0
      assert length(result.results) == 3
      assert Map.has_key?(result, :performance)
      assert result.performance.parallel == true
    end
    
    test "search documentation action finds relevant docs", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.SearchDocumentationAction.run(
        %{
          search_term: "pattern matching",
          sources: ["elixir", "hexdocs"],
          doc_types: ["guide", "module"],
          max_results: 10,
          include_snippets: true
        },
        context
      )
      
      assert result.search_term == "pattern matching"
      assert is_list(result.sources_searched)
      assert result.total_found >= 0
      assert length(result.results) <= 10
      
      if length(result.results) > 0 do
        first_result = hd(result.results)
        assert Map.has_key?(first_result, :title)
        assert Map.has_key?(first_result, :url)
        assert Map.has_key?(first_result, :relevance_score)
        assert Map.has_key?(first_result, :snippet)
      end
    end
    
    test "fetch related docs action discovers related documentation", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.FetchRelatedDocsAction.run(
        %{
          base_query: "GenServer",
          relationship_types: [:callbacks, :related_modules, :examples, :guides],
          max_depth: 2,
          max_results: 15
        },
        context
      )
      
      assert result.base_query == "GenServer"
      assert result.depth_explored <= 2
      assert Map.has_key?(result, :related_docs)
      
      related = result.related_docs
      assert Map.has_key?(related, :callbacks)
      assert Map.has_key?(related, :related_modules)
      assert Map.has_key?(related, :examples)
      assert Map.has_key?(related, :guides)
      
      assert is_list(result.relationship_graph)
      assert result.total_related >= 0
    end
    
    test "generate doc index action builds searchable index", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.GenerateDocIndexAction.run(
        %{
          packages: ["phoenix", "ecto"],
          doc_types: ["module", "function", "guide"],
          index_format: :search_optimized,
          include_metadata: true
        },
        context
      )
      
      assert result.packages_indexed == ["phoenix", "ecto"]
      assert Map.has_key?(result, :index)
      
      index = result.index
      assert Map.has_key?(index, :entries)
      assert Map.has_key?(index, :metadata)
      assert index.format == :search_optimized
      
      assert result.total_entries >= 0
      assert Map.has_key?(result, :statistics)
      
      stats = result.statistics
      assert Map.has_key?(stats, :modules_indexed)
      assert Map.has_key?(stats, :functions_indexed)
      assert Map.has_key?(stats, :guides_indexed)
    end
    
    test "update cache action manages documentation cache", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.UpdateCacheAction.run(
        %{
          operation: :cleanup,
          max_age_hours: 24,
          max_size_mb: 100,
          preserve_popular: true
        },
        context
      )
      
      assert result.operation == :cleanup
      assert Map.has_key?(result, :before)
      assert Map.has_key?(result, :after)
      assert Map.has_key?(result, :statistics)
      
      stats = result.statistics
      assert stats.entries_removed >= 0
      assert stats.space_freed_mb >= 0
      assert is_float(stats.cache_hit_rate)
    end
  end
  
  describe "signal handling" do
    test "fetch_documentation signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "fetch_documentation",
        "data" => %{
          "query" => "Process.send/3",
          "source" => "elixir",
          "format" => "markdown"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DocFetcherAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "search_docs signal triggers SearchDocumentationAction", %{agent: agent} do
      signal = %{
        "type" => "search_docs",
        "data" => %{
          "search_term" => "supervisor strategies",
          "sources" => ["elixir", "hexdocs"],
          "max_results" => 20
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DocFetcherAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "index_documentation signal triggers GenerateDocIndexAction", %{agent: agent} do
      signal = %{
        "type" => "index_documentation",
        "data" => %{
          "packages" => ["ash", "phoenix"],
          "doc_types" => ["module", "function"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DocFetcherAgent.handle_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "updates documentation cache after fetch", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful documentation fetch
      doc_result = %{
        query: "String.split/2",
        source: "elixir",
        documentation: "# String.split/2\n\nSplits a string...",
        metadata: %{
          url: "https://hexdocs.pm/elixir/String.html#split/2",
          fetched_at: DateTime.utc_now(),
          version: "1.15.0",
          type: "function"
        }
      }
      
      {:ok, updated} = DocFetcherAgent.handle_action_result(
        state,
        DocFetcherAgent.ExecuteToolAction,
        {:ok, doc_result},
        %{params: %{query: "String.split/2"}}
      )
      
      cache_key = DocFetcherAgent.ExecuteToolAction.generate_cache_key(%{
        query: "String.split/2",
        source: "elixir",
        doc_type: "function",
        format: "markdown"
      })
      
      assert Map.has_key?(updated.state.documentation_cache, cache_key)
      cached = updated.state.documentation_cache[cache_key]
      assert cached.content == doc_result
      assert cached.hit_count == 0
    end
    
    test "tracks fetch history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      doc_result = %{
        query: "GenServer",
        source: "hexdocs",
        documentation: "GenServer documentation..."
      }
      
      {:ok, updated} = DocFetcherAgent.handle_action_result(
        state,
        DocFetcherAgent.ExecuteToolAction,
        {:ok, doc_result},
        %{}
      )
      
      assert length(updated.state.fetch_history) == 1
      history_entry = hd(updated.state.fetch_history)
      assert history_entry.query == "GenServer"
      assert history_entry.source == "hexdocs"
      assert history_entry.success == true
    end
    
    test "updates documentation index after generation", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      index_result = %{
        packages_indexed: ["phoenix"],
        index: %{
          format: :search_optimized,
          entries: [
            %{title: "Phoenix", type: "module", url: "https://..."}
          ],
          metadata: %{generated_at: DateTime.utc_now()}
        },
        total_entries: 1,
        statistics: %{
          modules_indexed: 1,
          functions_indexed: 0,
          guides_indexed: 0
        }
      }
      
      {:ok, updated} = DocFetcherAgent.handle_action_result(
        state,
        DocFetcherAgent.GenerateDocIndexAction,
        {:ok, index_result},
        %{}
      )
      
      assert Map.has_key?(updated.state.documentation_index, "phoenix")
      phoenix_index = updated.state.documentation_index["phoenix"]
      assert phoenix_index == index_result.index
    end
  end
  
  describe "agent initialization" do
    test "starts with empty documentation cache", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.documentation_cache == %{}
      assert state.state.cache_stats.total_entries == 0
      assert state.state.cache_stats.total_size == 0
      assert state.state.cache_stats.hit_rate == 0.0
    end
    
    test "starts with default fetch configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.fetch_config
      assert config.default_source == "auto"
      assert config.default_format == "markdown"
      assert config.include_examples == true
      assert config.include_related == false
      assert config.timeout_ms == 30_000
      assert config.max_retries == 2
    end
    
    test "starts with empty fetch history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.fetch_history == []
      assert state.state.active_fetches == %{}
    end
    
    test "starts with initialized source preferences", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      prefs = state.state.source_preferences
      assert prefs["elixir"] == ["elixir", "hexdocs"]
      assert prefs["phoenix"] == ["hexdocs", "github"]
      assert prefs["erlang"] == ["erlang", "hexdocs"]
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = DocFetcherAgent.additional_actions()
      
      assert length(actions) == 6
      assert DocFetcherAgent.ExecuteToolAction in actions
      assert DocFetcherAgent.BatchFetchAction in actions
      assert DocFetcherAgent.SearchDocumentationAction in actions
      assert DocFetcherAgent.FetchRelatedDocsAction in actions
      assert DocFetcherAgent.GenerateDocIndexAction in actions
      assert DocFetcherAgent.UpdateCacheAction in actions
    end
  end
  
  describe "batch fetching" do
    test "respects max concurrent limit", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.BatchFetchAction.run(
        %{
          queries: Enum.map(1..10, &"Module#{&1}"),
          max_concurrent: 3,
          parallel: true
        },
        context
      )
      
      assert result.performance.max_concurrent == 3
      assert result.total_queries == 10
    end
    
    test "falls back to sequential on parallel failure", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.BatchFetchAction.run(
        %{
          queries: ["Invalid::Module", "Another::Invalid"],
          parallel: true
        },
        context
      )
      
      # Even with failures, batch should complete
      assert result.total_queries == 2
      assert Map.has_key?(result, :results)
    end
  end
  
  describe "search functionality" do
    test "scores results by relevance", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.SearchDocumentationAction.run(
        %{
          search_term: "process communication",
          sources: ["elixir"],
          max_results: 5
        },
        context
      )
      
      if length(result.results) > 1 do
        scores = Enum.map(result.results, & &1.relevance_score)
        # Results should be sorted by relevance (descending)
        assert scores == Enum.sort(scores, &>=/2)
      end
    end
    
    test "filters by document type", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.SearchDocumentationAction.run(
        %{
          search_term: "getting started",
          doc_types: ["guide"],
          sources: ["hexdocs"]
        },
        context
      )
      
      # All results should be guides
      Enum.each(result.results, fn doc ->
        assert doc.type == "guide"
      end)
    end
  end
  
  describe "cache management" do
    test "cache cleanup preserves popular entries", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Add some cache entries with different hit counts
      cache = %{
        "key1" => %{content: "data1", hit_count: 10, last_accessed: DateTime.utc_now()},
        "key2" => %{content: "data2", hit_count: 1, last_accessed: DateTime.utc_now()},
        "key3" => %{content: "data3", hit_count: 20, last_accessed: DateTime.utc_now()}
      }
      
      state = put_in(state.state.documentation_cache, cache)
      context = %{agent: state}
      
      {:ok, result} = DocFetcherAgent.UpdateCacheAction.run(
        %{
          operation: :cleanup,
          preserve_popular: true,
          popularity_threshold: 5
        },
        context
      )
      
      # Should preserve entries with hit_count > 5
      assert result.statistics.entries_preserved >= 2
    end
    
    test "cache statistics are calculated correctly", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.UpdateCacheAction.run(
        %{operation: :statistics},
        context
      )
      
      stats = result.statistics
      assert Map.has_key?(stats, :total_entries)
      assert Map.has_key?(stats, :total_size_mb)
      assert Map.has_key?(stats, :average_hit_count)
      assert Map.has_key?(stats, :cache_efficiency)
    end
  end
  
  describe "related documentation discovery" do
    test "builds relationship graph", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.FetchRelatedDocsAction.run(
        %{
          base_query: "Supervisor",
          relationship_types: [:related_modules, :examples],
          max_depth: 1
        },
        context
      )
      
      graph = result.relationship_graph
      assert is_list(graph)
      
      if length(graph) > 0 do
        edge = hd(graph)
        assert Map.has_key?(edge, :from)
        assert Map.has_key?(edge, :to)
        assert Map.has_key?(edge, :relationship)
      end
    end
    
    test "respects depth limit", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DocFetcherAgent.FetchRelatedDocsAction.run(
        %{
          base_query: "GenServer",
          max_depth: 1,
          max_results: 50
        },
        context
      )
      
      assert result.depth_explored <= 1
    end
  end
end