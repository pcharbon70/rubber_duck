defmodule RubberDuck.Tools.Agents.SemanticEmbedderAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.SemanticEmbedderAgent
  
  setup do
    {:ok, agent} = SemanticEmbedderAgent.start_link(id: "test_semantic_embedder")
    
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
        code: """
        defmodule Example do
          def hello, do: "world"
        end
        """,
        embedding_type: "semantic",
        model: "text-embedding-ada-002",
        include_metadata: true
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # First execution - should generate new embedding
      result1 = SemanticEmbedderAgent.ExecuteToolAction.run(%{params: params}, context)
      assert match?({:ok, _}, result1)
      {:ok, embedding1} = result1
      assert embedding1.cache_hit == false
      
      # Second execution - should hit cache
      result2 = SemanticEmbedderAgent.ExecuteToolAction.run(%{params: params}, context)
      assert match?({:ok, _}, result2)
      {:ok, embedding2} = result2
      assert embedding2.cache_hit == true
      
      # Embeddings should be the same
      assert embedding1.embeddings == embedding2.embeddings
    end
    
    test "batch embed action processes multiple code snippets", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      code_items = [
        %{id: "1", code: "def add(a, b), do: a + b"},
        %{id: "2", code: "def multiply(a, b), do: a * b"},
        %{id: "3", code: "def divide(a, b), do: a / b"}
      ]
      
      {:ok, result} = SemanticEmbedderAgent.BatchEmbedAction.run(
        %{
          code_items: code_items,
          embedding_type: "semantic",
          parallel: true,
          max_concurrent: 2
        },
        context
      )
      
      assert result.total_items == 3
      assert result.successful == 3
      assert result.failed == 0
      assert length(result.embeddings) == 3
      assert Map.has_key?(result.performance, :duration_ms)
      assert Map.has_key?(result.performance, :items_per_second)
    end
    
    test "similarity search finds similar code", %{agent: agent} do
      # First, add some embeddings to the index
      state = GenServer.call(agent, :get_state)
      
      # Create test embeddings (simplified vectors)
      test_index = %{
        vectors: [
          [0.1, 0.2, 0.3, 0.4],  # Similar to query
          [0.9, 0.8, 0.7, 0.6],  # Very different
          [0.15, 0.25, 0.35, 0.45]  # Most similar
        ],
        metadata: [
          %{id: "1", code: "def add(a, b), do: a + b"},
          %{id: "2", code: "def complex_logic, do: ..."},
          %{id: "3", code: "def sum(x, y), do: x + y"}
        ],
        dimension: 4
      }
      
      state = put_in(state.state.embedding_index, test_index)
      context = %{agent: state}
      
      # Mock the query embedding generation
      query_code = "def add_numbers(n1, n2), do: n1 + n2"
      
      # For this test, we'll directly test the search functionality
      query_embedding = [0.12, 0.22, 0.32, 0.42]
      
      results = SemanticEmbedderAgent.SimilaritySearchAction.search_index(
        query_embedding,
        test_index,
        :cosine_similarity,
        0.5,
        10,
        %{}
      )
      
      assert length(results) > 0
      assert hd(results).id == "3"  # Most similar should be first
    end
    
    test "cluster code action groups similar embeddings", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Create test embeddings with clear clusters
      test_index = %{
        vectors: [
          # Cluster 1 - arithmetic operations
          [0.1, 0.2, 0.3, 0.4],
          [0.15, 0.25, 0.35, 0.45],
          [0.12, 0.22, 0.32, 0.42],
          # Cluster 2 - string operations
          [0.7, 0.8, 0.9, 1.0],
          [0.75, 0.85, 0.95, 1.05],
          [0.72, 0.82, 0.92, 1.02]
        ],
        metadata: [
          %{id: "1", code: "def add(a, b), do: a + b"},
          %{id: "2", code: "def sum(x, y), do: x + y"},
          %{id: "3", code: "def plus(m, n), do: m + n"},
          %{id: "4", code: "def concat(s1, s2), do: s1 <> s2"},
          %{id: "5", code: "def join(a, b), do: a <> b"},
          %{id: "6", code: "def append(str1, str2), do: str1 <> str2"}
        ],
        dimension: 4
      }
      
      state = put_in(state.state.embedding_index, test_index)
      context = %{agent: state}
      
      {:ok, result} = SemanticEmbedderAgent.ClusterCodeAction.run(
        %{
          min_cluster_size: 2,
          max_clusters: 2,
          algorithm: :k_means
        },
        context
      )
      
      assert result.total_embeddings == 6
      assert result.cluster_count > 0
      assert Map.has_key?(result, :statistics)
      
      stats = result.statistics
      assert Map.has_key?(stats, :average_size)
      assert Map.has_key?(stats, :min_size)
      assert Map.has_key?(stats, :max_size)
    end
    
    test "build index action creates searchable index", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      embeddings = [
        %{
          id: "1",
          code: "def hello, do: :world",
          embeddings: [[0.1, 0.2, 0.3]],
          metadata: %{module: "Greeter"}
        },
        %{
          id: "2",
          code: "def goodbye, do: :farewell",
          embeddings: [[0.4, 0.5, 0.6]],
          metadata: %{module: "Farewell"}
        }
      ]
      
      {:ok, result} = SemanticEmbedderAgent.BuildIndexAction.run(
        %{
          embeddings: embeddings,
          rebuild: true,
          index_type: :flat
        },
        context
      )
      
      assert result.total_vectors == 2
      assert result.dimension == 3
      assert result.rebuild == true
      
      index = result.index
      assert length(index.vectors) == 2
      assert length(index.metadata) == 2
      assert index.dimension == 3
    end
    
    test "export embeddings action exports in multiple formats", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Setup test index
      test_index = %{
        vectors: [
          [0.1, 0.2, 0.3],
          [0.4, 0.5, 0.6]
        ],
        metadata: [
          %{id: "1", code: "def a, do: 1", timestamp: DateTime.utc_now()},
          %{id: "2", code: "def b, do: 2", timestamp: DateTime.utc_now()}
        ],
        dimension: 3
      }
      
      state = put_in(state.state.embedding_index, test_index)
      context = %{agent: state}
      
      # Test JSON export
      {:ok, json_result} = SemanticEmbedderAgent.ExportEmbeddingsAction.run(
        %{format: :json, include_metadata: true},
        context
      )
      
      assert json_result.format == :json
      assert json_result.total_exported == 2
      assert length(json_result.data.embeddings) == 2
      
      # Test CSV export
      {:ok, csv_result} = SemanticEmbedderAgent.ExportEmbeddingsAction.run(
        %{format: :csv, include_metadata: false},
        context
      )
      
      assert csv_result.format == :csv
      assert length(csv_result.data.headers) == 3  # 3 dimensions
      assert length(csv_result.data.rows) == 2
      
      # Test NumPy export
      {:ok, numpy_result} = SemanticEmbedderAgent.ExportEmbeddingsAction.run(
        %{format: :numpy},
        context
      )
      
      assert numpy_result.format == :numpy
      assert numpy_result.data.shape == [2, 3]
      assert numpy_result.data.dtype == "float32"
    end
  end
  
  describe "signal handling" do
    test "generate_embedding signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "generate_embedding",
        "data" => %{
          "code" => "def test, do: :ok",
          "embedding_type" => "semantic"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SemanticEmbedderAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "search_similar signal triggers SimilaritySearchAction", %{agent: agent} do
      signal = %{
        "type" => "search_similar",
        "data" => %{
          "query_code" => "def add(a, b), do: a + b",
          "threshold" => 0.7,
          "max_results" => 5
        }
      }
      
      state = GenServer.call(agent, :get_state)
      result = SemanticEmbedderAgent.handle_signal(state, signal)
      
      # Should succeed even with empty index
      assert match?({:ok, _}, result)
    end
    
    test "build_index signal triggers BuildIndexAction", %{agent: agent} do
      signal = %{
        "type" => "build_index",
        "data" => %{
          "embeddings" => [],
          "rebuild" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, updated} = SemanticEmbedderAgent.handle_signal(state, signal)
      
      assert Map.has_key?(updated.embedding_index, :vectors)
    end
  end
  
  describe "state management" do
    test "caches embeddings after generation", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      params = %{
        code: "def unique_function, do: :unique",
        embedding_type: "semantic"
      }
      
      result = %{
        embeddings: [[0.1, 0.2, 0.3]],
        metadata: %{model: "test-model"},
        cache_hit: false
      }
      
      {:ok, updated} = SemanticEmbedderAgent.handle_action_result(
        state,
        SemanticEmbedderAgent.ExecuteToolAction,
        {:ok, result},
        %{params: params}
      )
      
      cache_key = SemanticEmbedderAgent.ExecuteToolAction.generate_cache_key(params)
      assert Map.has_key?(updated.embedding_store, cache_key)
    end
    
    test "tracks generation history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        embeddings: [[0.1, 0.2, 0.3]],
        cache_hit: false
      }
      
      params = %{
        params: %{
          code: "test code",
          model: "test-model"
        }
      }
      
      {:ok, updated} = SemanticEmbedderAgent.handle_action_result(
        state,
        SemanticEmbedderAgent.ExecuteToolAction,
        {:ok, result},
        params
      )
      
      assert length(updated.generation_history) == 1
      history = hd(updated.generation_history)
      assert history.code_length == String.length("test code")
      assert history.model == "test-model"
      assert history.cache_hit == false
    end
    
    test "tracks search history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        query: "def search_me",
        total_results: 3,
        search_algorithm: :cosine_similarity,
        results: []
      }
      
      {:ok, updated} = SemanticEmbedderAgent.handle_action_result(
        state,
        SemanticEmbedderAgent.SimilaritySearchAction,
        {:ok, result},
        %{}
      )
      
      assert length(updated.search_history) == 1
      history = hd(updated.search_history)
      assert history.query == "def search_me"
      assert history.results_count == 3
      assert history.algorithm == :cosine_similarity
    end
    
    test "updates performance metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      initial_metrics = state.state.performance_metrics
      
      # Simulate generation
      {:ok, updated} = SemanticEmbedderAgent.handle_action_result(
        state,
        SemanticEmbedderAgent.ExecuteToolAction,
        {:ok, %{embeddings: [[0.1]], cache_hit: false}},
        %{params: %{code: "test"}}
      )
      
      assert updated.performance_metrics.total_embeddings == initial_metrics.total_embeddings + 1
      assert updated.performance_metrics.cache_misses == initial_metrics.cache_misses + 1
      
      # Simulate search
      {:ok, updated2} = SemanticEmbedderAgent.handle_action_result(
        updated,
        SemanticEmbedderAgent.SimilaritySearchAction,
        {:ok, %{query: "test", total_results: 0, search_algorithm: :cosine_similarity}},
        %{}
      )
      
      assert updated2.performance_metrics.total_searches == initial_metrics.total_searches + 1
    end
  end
  
  describe "agent initialization" do
    test "starts with default embedding configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.embedding_config
      assert config.default_model == "text-embedding-ada-002"
      assert config.default_type == "semantic"
      assert config.chunk_size == 2000
      assert config.chunk_overlap == 200
    end
    
    test "starts with empty embedding store and index", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.embedding_store == %{}
      assert state.state.embedding_index.vectors == []
      assert state.state.embedding_index.metadata == []
    end
    
    test "starts with zero performance metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      metrics = state.state.performance_metrics
      assert metrics.total_embeddings == 0
      assert metrics.total_searches == 0
      assert metrics.cache_hits == 0
      assert metrics.cache_misses == 0
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = SemanticEmbedderAgent.additional_actions()
      
      assert length(actions) == 6
      assert SemanticEmbedderAgent.ExecuteToolAction in actions
      assert SemanticEmbedderAgent.BatchEmbedAction in actions
      assert SemanticEmbedderAgent.SimilaritySearchAction in actions
      assert SemanticEmbedderAgent.ClusterCodeAction in actions
      assert SemanticEmbedderAgent.BuildIndexAction in actions
      assert SemanticEmbedderAgent.ExportEmbeddingsAction in actions
    end
  end
  
  describe "embedding operations" do
    test "generates consistent cache keys", %{agent: agent} do
      params1 = %{
        code: "def test, do: :ok",
        embedding_type: "semantic",
        model: "test-model",
        dimensions: 256
      }
      
      params2 = %{
        code: "def test, do: :ok",
        embedding_type: "semantic",
        model: "test-model",
        dimensions: 256
      }
      
      key1 = SemanticEmbedderAgent.ExecuteToolAction.generate_cache_key(params1)
      key2 = SemanticEmbedderAgent.ExecuteToolAction.generate_cache_key(params2)
      
      assert key1 == key2
    end
    
    test "batch processing respects concurrency limits", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Create many items
      code_items = Enum.map(1..20, fn i ->
        %{id: "item_#{i}", code: "def func_#{i}, do: #{i}"}
      end)
      
      {:ok, result} = SemanticEmbedderAgent.BatchEmbedAction.run(
        %{
          code_items: code_items,
          max_concurrent: 5,
          parallel: true
        },
        context
      )
      
      assert result.total_items == 20
      # Should process all items despite concurrency limit
      assert result.successful + result.failed == 20
    end
  end
  
  describe "similarity calculations" do
    test "cosine similarity calculation is correct" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [1.0, 0.0, 0.0]
      vec3 = [0.0, 1.0, 0.0]
      
      # Same vectors should have similarity 1.0
      similarity1 = SemanticEmbedderAgent.SimilaritySearchAction.calculate_similarity(
        vec1, vec2, :cosine_similarity
      )
      assert_in_delta(similarity1, 1.0, 0.001)
      
      # Orthogonal vectors should have similarity 0.0
      similarity2 = SemanticEmbedderAgent.SimilaritySearchAction.calculate_similarity(
        vec1, vec3, :cosine_similarity
      )
      assert_in_delta(similarity2, 0.0, 0.001)
    end
    
    test "euclidean distance similarity is correct" do
      vec1 = [0.0, 0.0]
      vec2 = [0.0, 0.0]
      vec3 = [3.0, 4.0]
      
      # Same vectors should have high similarity (distance 0)
      similarity1 = SemanticEmbedderAgent.SimilaritySearchAction.calculate_similarity(
        vec1, vec2, :euclidean_distance
      )
      assert similarity1 == 1.0
      
      # Distance of 5 should give similarity 1/(1+5) = 0.1667
      similarity2 = SemanticEmbedderAgent.SimilaritySearchAction.calculate_similarity(
        vec1, vec3, :euclidean_distance
      )
      assert_in_delta(similarity2, 0.1667, 0.001)
    end
  end
  
  describe "export formats" do
    test "JSON export includes all required fields", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      test_index = %{
        vectors: [[0.1, 0.2]],
        metadata: [%{id: "test", code: "def test"}],
        dimension: 2
      }
      
      state = put_in(state.state.embedding_index, test_index)
      context = %{agent: state}
      
      {:ok, result} = SemanticEmbedderAgent.ExportEmbeddingsAction.run(
        %{format: :json, include_metadata: true},
        context
      )
      
      embedding = hd(result.data.embeddings)
      assert Map.has_key?(embedding, :vector)
      assert Map.has_key?(embedding, :metadata)
      assert result.data.dimension == 2
    end
    
    test "CSV export has correct structure", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      test_index = %{
        vectors: [[0.1, 0.2], [0.3, 0.4]],
        metadata: [
          %{id: "1", code: "code1"},
          %{id: "2", code: "code2"}
        ],
        dimension: 2
      }
      
      state = put_in(state.state.embedding_index, test_index)
      context = %{agent: state}
      
      {:ok, result} = SemanticEmbedderAgent.ExportEmbeddingsAction.run(
        %{format: :csv, include_metadata: true},
        context
      )
      
      assert result.data.headers == ["id", "dim_0", "dim_1"]
      assert length(result.data.rows) == 2
      assert hd(result.data.rows) == ["1", 0.1, 0.2]
    end
  end
end