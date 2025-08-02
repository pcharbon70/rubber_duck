defmodule RubberDuck.Tools.Agents.SemanticEmbedderAgent do
  @moduledoc """
  Agent that orchestrates semantic embedding generation for code similarity search.
  
  This agent manages the generation of vector embeddings for code, enabling
  semantic search, code clustering, and similarity analysis. It provides
  specialized actions for batch embedding, similarity search, and embedding
  management.
  """
  
  use Jido.Agent,
    name: "semantic_embedder_agent",
    description: "Orchestrates semantic embedding generation and similarity search",
    category: "analysis",
    tags: [:embeddings, "search", :ml, :similarity, :vectors],
    vsn: "1.0.0",
    schema: [
      embedding_config: [
        type: :map,
        doc: "Configuration for embedding generation",
        default: %{
          default_model: "text-embedding-ada-002",
          default_dimensions: nil,
          default_type: "semantic",
          chunk_size: 2000,
          chunk_overlap: 200
        }
      ],
      search_config: [
        type: :map,
        doc: "Configuration for similarity search",
        default: %{
          default_threshold: 0.8,
          max_results: 10,
          search_algorithm: :cosine_similarity,
          include_metadata: true
        }
      ],
      embedding_store: [
        type: :map,
        doc: "Storage for generated embeddings",
        default: %{}
      ],
      embedding_index: [
        type: :map,
        doc: "Index for fast similarity search",
        default: %{
          vectors: [],
          metadata: [],
          dimension: nil
        }
      ],
      generation_history: [
        type: {:list, :map},
        doc: "History of embedding generation operations",
        default: []
      ],
      search_history: [
        type: {:list, :map},
        doc: "History of search operations",
        default: []
      ],
      active_generations: [
        type: :map,
        doc: "Currently active embedding generations",
        default: %{}
      ],
      performance_metrics: [
        type: :map,
        doc: "Performance metrics for operations",
        default: %{
          total_embeddings: 0,
          total_searches: 0,
          average_generation_time: 0,
          average_search_time: 0,
          cache_hits: 0,
          cache_misses: 0
        }
      ]
    ]
  
  alias RubberDuck.Tools.SemanticEmbedder
  
  # Action to execute the semantic embedder tool
  defmodule ExecuteToolAction do
    use Jido.Action,
      name: "execute_semantic_embedder_tool",
      description: "Execute the semantic embedder tool with given parameters",
      schema: [
        params: [type: :map, required: true]
      ]
    
    def run(%{params: params}, context) do
      agent_state = context.agent.state
      
      # Check if we have a cached embedding for this code
      cache_key = generate_cache_key(params)
      
      if cached = get_in(agent_state.embedding_store, [cache_key]) do
        {:ok, Map.merge(cached, %{cache_hit: true})}
      else
        case SemanticEmbedder.execute(params, context) do
          {:ok, result} ->
            # Cache the result
            {:ok, Map.merge(result, %{cache_hit: false, cache_key: cache_key})}
          error ->
            error
        end
      end
    end
    
    def generate_cache_key(params) do
      content = "#{params.code}_#{params.embedding_type}_#{params.model}_#{params.dimensions}"
      :crypto.hash(:sha256, content)
      |> Base.encode16()
      |> String.slice(0..15)
    end
  end
  
  # Action to generate embeddings for multiple code snippets
  defmodule BatchEmbedAction do
    use Jido.Action,
      name: "batch_embed_code",
      description: "Generate embeddings for multiple code snippets in batch",
      schema: [
        code_items: [type: {:list, :map}, required: true],
        embedding_type: [type: :string, default: "semantic"],
        model: [type: :string, default: "text-embedding-ada-002"],
        parallel: [type: :boolean, default: true],
        max_concurrent: [type: :integer, default: 5]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      start_time = System.monotonic_time(:millisecond)
      
      # Process embeddings
      results = if params.parallel do
        process_parallel(params.code_items, params, context)
      else
        process_sequential(params.code_items, params, context)
      end
      
      # Calculate statistics
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _}, &1))
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      {:ok, %{
        total_items: length(params.code_items),
        successful: length(successful),
        failed: length(failed),
        embeddings: Enum.map(successful, fn {:ok, embedding} -> embedding end),
        errors: Enum.map(failed, fn {:error, reason} -> reason end),
        performance: %{
          duration_ms: duration,
          items_per_second: length(params.code_items) / (duration / 1000)
        }
      }}
    end
    
    defp process_parallel(items, params, context) do
      items
      |> Enum.chunk_every(params.max_concurrent)
      |> Enum.flat_map(fn chunk ->
        chunk
        |> Enum.map(fn item ->
          Task.async(fn ->
            generate_embedding(item, params, context)
          end)
        end)
        |> Enum.map(&Task.await(&1, 30_000))
      end)
    end
    
    defp process_sequential(items, params, context) do
      Enum.map(items, &generate_embedding(&1, params, context))
    end
    
    defp generate_embedding(item, params, context) do
      embedding_params = %{
        code: item.code,
        embedding_type: params.embedding_type,
        model: params.model,
        include_metadata: true
      }
      
      case ExecuteToolAction.run(%{params: embedding_params}, context) do
        {:ok, result} ->
          {:ok, Map.merge(result, %{id: item[:id] || generate_id(), metadata: item[:metadata]})}
        error ->
          error
      end
    end
    
    defp generate_id do
      :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
  end
  
  # Action to search for similar code using embeddings
  defmodule SimilaritySearchAction do
    use Jido.Action,
      name: "search_similar_code",
      description: "Search for similar code using vector similarity",
      schema: [
        query_code: [type: :string, required: true],
        search_algorithm: [type: :atom, default: :cosine_similarity],
        threshold: [type: :float, default: 0.8],
        max_results: [type: :integer, default: 10],
        filter: [type: :map, default: %{}]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      
      # Generate embedding for query code
      query_params = %{
        code: params.query_code,
        embedding_type: agent_state.embedding_config.default_type,
        model: agent_state.embedding_config.default_model
      }
      
      case ExecuteToolAction.run(%{params: query_params}, context) do
        {:ok, query_result} ->
          query_embedding = hd(query_result.embeddings)
          
          # Search in index
          results = search_index(
            query_embedding,
            agent_state.embedding_index,
            params.search_algorithm,
            params.threshold,
            params.max_results,
            params.filter
          )
          
          {:ok, %{
            query: params.query_code,
            total_results: length(results),
            results: results,
            search_algorithm: params.search_algorithm,
            threshold: params.threshold
          }}
          
        error ->
          error
      end
    end
    
    defp search_index(query_embedding, index, algorithm, threshold, max_results, filter) do
      if index.vectors == [] do
        []
      else
        index.vectors
        |> Enum.zip(index.metadata)
        |> Enum.map(fn {vector, metadata} ->
          similarity = calculate_similarity(query_embedding, vector, algorithm)
          {similarity, metadata}
        end)
        |> Enum.filter(fn {similarity, metadata} ->
          similarity >= threshold and passes_filter?(metadata, filter)
        end)
        |> Enum.sort_by(&elem(&1, 0), :desc)
        |> Enum.take(max_results)
        |> Enum.map(fn {similarity, metadata} ->
          Map.merge(metadata, %{similarity_score: similarity})
        end)
      end
    end
    
    defp calculate_similarity(vec1, vec2, :cosine_similarity) do
      dot_product = Enum.zip(vec1, vec2)
      |> Enum.map(fn {a, b} -> a * b end)
      |> Enum.sum()
      
      magnitude1 = :math.sqrt(Enum.map(vec1, &(&1 * &1)) |> Enum.sum())
      magnitude2 = :math.sqrt(Enum.map(vec2, &(&1 * &1)) |> Enum.sum())
      
      if magnitude1 == 0 or magnitude2 == 0 do
        0.0
      else
        dot_product / (magnitude1 * magnitude2)
      end
    end
    
    defp calculate_similarity(vec1, vec2, :euclidean_distance) do
      distance = Enum.zip(vec1, vec2)
      |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
      |> Enum.sum()
      |> :math.sqrt()
      
      # Convert distance to similarity (0-1 range)
      1.0 / (1.0 + distance)
    end
    
    defp passes_filter?(metadata, filter) when map_size(filter) == 0, do: true
    defp passes_filter?(metadata, filter) do
      Enum.all?(filter, fn {key, value} ->
        Map.get(metadata, key) == value
      end)
    end
  end
  
  # Action to cluster code based on embeddings
  defmodule ClusterCodeAction do
    use Jido.Action,
      name: "cluster_code_embeddings",
      description: "Cluster code snippets based on their embeddings",
      schema: [
        min_cluster_size: [type: :integer, default: 2],
        max_clusters: [type: :integer, default: 10],
        algorithm: [type: :atom, default: :k_means],
        distance_threshold: [type: :float, default: 0.3]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      index = agent_state.embedding_index
      
      if length(index.vectors) < params.min_cluster_size do
        {:ok, %{
          clusters: [],
          message: "Not enough embeddings for clustering"
        }}
      else
        clusters = case params.algorithm do
          :k_means -> cluster_k_means(index, params)
          :hierarchical -> cluster_hierarchical(index, params)
          :density -> cluster_density_based(index, params)
        end
        
        {:ok, %{
          algorithm: params.algorithm,
          total_embeddings: length(index.vectors),
          cluster_count: length(clusters),
          clusters: clusters,
          statistics: calculate_cluster_statistics(clusters)
        }}
      end
    end
    
    defp cluster_k_means(index, params) do
      # Simplified k-means clustering
      k = min(params.max_clusters, div(length(index.vectors), params.min_cluster_size))
      
      # Initialize centroids randomly
      centroids = Enum.take_random(index.vectors, k)
      
      # Run clustering iterations (simplified)
      clusters = assign_to_clusters(index.vectors, index.metadata, centroids)
      
      format_clusters(clusters)
    end
    
    defp cluster_hierarchical(_index, _params) do
      # Placeholder for hierarchical clustering
      []
    end
    
    defp cluster_density_based(_index, _params) do
      # Placeholder for density-based clustering
      []
    end
    
    defp assign_to_clusters(vectors, metadata, centroids) do
      Enum.zip(vectors, metadata)
      |> Enum.group_by(fn {vector, _metadata} ->
        # Find nearest centroid
        centroids
        |> Enum.with_index()
        |> Enum.map(fn {centroid, idx} ->
          distance = calculate_euclidean_distance(vector, centroid)
          {idx, distance}
        end)
        |> Enum.min_by(&elem(&1, 1))
        |> elem(0)
      end)
    end
    
    defp calculate_euclidean_distance(vec1, vec2) do
      Enum.zip(vec1, vec2)
      |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
      |> Enum.sum()
      |> :math.sqrt()
    end
    
    defp format_clusters(cluster_map) do
      cluster_map
      |> Enum.map(fn {cluster_id, members} ->
        %{
          id: cluster_id,
          size: length(members),
          members: Enum.map(members, &elem(&1, 1))
        }
      end)
    end
    
    defp calculate_cluster_statistics(clusters) do
      sizes = Enum.map(clusters, & &1.size)
      
      %{
        average_size: if(sizes == [], do: 0, else: Enum.sum(sizes) / length(sizes)),
        min_size: if(sizes == [], do: 0, else: Enum.min(sizes)),
        max_size: if(sizes == [], do: 0, else: Enum.max(sizes)),
        size_variance: calculate_variance(sizes)
      }
    end
    
    defp calculate_variance([]), do: 0
    defp calculate_variance(values) do
      mean = Enum.sum(values) / length(values)
      
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))
    end
  end
  
  # Action to build/update the embedding index
  defmodule BuildIndexAction do
    use Jido.Action,
      name: "build_embedding_index",
      description: "Build or update the embedding index for fast search",
      schema: [
        embeddings: [type: {:list, :map}, required: true],
        rebuild: [type: :boolean, default: false],
        index_type: [type: :atom, default: :flat]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      current_index = agent_state.embedding_index
      
      new_index = if params.rebuild do
        build_new_index(params.embeddings, params.index_type)
      else
        update_existing_index(current_index, params.embeddings, params.index_type)
      end
      
      {:ok, %{
        index_type: params.index_type,
        total_vectors: length(new_index.vectors),
        dimension: new_index.dimension,
        rebuild: params.rebuild,
        index: new_index
      }}
    end
    
    defp build_new_index(embeddings, _index_type) do
      vectors = Enum.map(embeddings, & &1.embeddings) |> List.flatten()
      metadata = Enum.map(embeddings, fn emb ->
        %{
          id: emb[:id] || generate_id(),
          code: emb[:code],
          metadata: emb[:metadata] || %{},
          timestamp: DateTime.utc_now()
        }
      end)
      
      dimension = if vectors != [] do
        hd(vectors) |> length()
      else
        nil
      end
      
      %{
        vectors: vectors,
        metadata: metadata,
        dimension: dimension,
        index_type: :flat
      }
    end
    
    defp update_existing_index(current_index, new_embeddings, _index_type) do
      new_vectors = Enum.map(new_embeddings, & &1.embeddings) |> List.flatten()
      new_metadata = Enum.map(new_embeddings, fn emb ->
        %{
          id: emb[:id] || generate_id(),
          code: emb[:code],
          metadata: emb[:metadata] || %{},
          timestamp: DateTime.utc_now()
        }
      end)
      
      %{
        vectors: current_index.vectors ++ new_vectors,
        metadata: current_index.metadata ++ new_metadata,
        dimension: current_index.dimension,
        index_type: current_index[:index_type] || :flat
      }
    end
    
    defp generate_id do
      :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
  end
  
  # Action to export embeddings
  defmodule ExportEmbeddingsAction do
    use Jido.Action,
      name: "export_embeddings",
      description: "Export embeddings in various formats",
      schema: [
        format: [type: :atom, default: :json],
        include_metadata: [type: :boolean, default: true],
        filter: [type: :map, default: %{}]
      ]
    
    def run(params, context) do
      agent_state = context.agent.state
      index = agent_state.embedding_index
      
      # Filter embeddings if needed
      filtered = filter_embeddings(index, params.filter)
      
      # Format for export
      exported = case params.format do
        :json -> export_as_json(filtered, params.include_metadata)
        :csv -> export_as_csv(filtered, params.include_metadata)
        :numpy -> export_as_numpy_compatible(filtered)
        :parquet -> export_as_parquet_compatible(filtered)
      end
      
      {:ok, %{
        format: params.format,
        total_exported: length(filtered.vectors),
        data: exported,
        metadata: %{
          dimension: index.dimension,
          export_date: DateTime.utc_now()
        }
      }}
    end
    
    defp filter_embeddings(index, filter) when map_size(filter) == 0 do
      index
    end
    defp filter_embeddings(index, filter) do
      filtered_pairs = Enum.zip(index.vectors, index.metadata)
      |> Enum.filter(fn {_vector, metadata} ->
        Enum.all?(filter, fn {key, value} ->
          Map.get(metadata, key) == value
        end)
      end)
      
      %{
        vectors: Enum.map(filtered_pairs, &elem(&1, 0)),
        metadata: Enum.map(filtered_pairs, &elem(&1, 1)),
        dimension: index.dimension
      }
    end
    
    defp export_as_json(data, include_metadata) do
      entries = Enum.zip(data.vectors, data.metadata)
      |> Enum.map(fn {vector, metadata} ->
        base = %{vector: vector}
        if include_metadata do
          Map.merge(base, %{metadata: metadata})
        else
          base
        end
      end)
      
      %{
        embeddings: entries,
        dimension: data.dimension
      }
    end
    
    defp export_as_csv(data, include_metadata) do
      headers = if include_metadata do
        ["id"] ++ Enum.map(0..(data.dimension - 1), &"dim_#{&1}")
      else
        Enum.map(0..(data.dimension - 1), &"dim_#{&1}")
      end
      
      rows = Enum.zip(data.vectors, data.metadata)
      |> Enum.map(fn {vector, metadata} ->
        if include_metadata do
          [metadata.id | vector]
        else
          vector
        end
      end)
      
      %{
        headers: headers,
        rows: rows
      }
    end
    
    defp export_as_numpy_compatible(data) do
      %{
        shape: [length(data.vectors), data.dimension],
        data: List.flatten(data.vectors),
        dtype: "float32"
      }
    end
    
    defp export_as_parquet_compatible(data) do
      %{
        schema: %{
          id: :string,
          vector: {:list, :float32},
          timestamp: :timestamp
        },
        data: Enum.zip(data.vectors, data.metadata)
        |> Enum.map(fn {vector, metadata} ->
          %{
            id: metadata.id,
            vector: vector,
            timestamp: metadata.timestamp
          }
        end)
      }
    end
  end
  
  @impl true
  def additional_actions do
    [
      ExecuteToolAction,
      BatchEmbedAction,
      SimilaritySearchAction,
      ClusterCodeAction,
      BuildIndexAction,
      ExportEmbeddingsAction
    ]
  end
  
  @impl true
  def handle_signal(state, %{"type" => "generate_embedding"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case ExecuteToolAction.run(%{params: params}, context) do
      {:ok, result} -> 
        {:ok, update_state_after_generation(state, result, params)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, %{"type" => "search_similar"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case SimilaritySearchAction.run(params, context) do
      {:ok, result} -> 
        {:ok, update_state_after_search(state, result)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, %{"type" => "build_index"} = signal) do
    params = Map.get(signal, "data", %{})
    context = %{agent: %{state: state}}
    
    case BuildIndexAction.run(params, context) do
      {:ok, result} -> 
        {:ok, put_in(state.embedding_index, result.index)}
      {:error, reason} -> 
        {:error, reason}
    end
  end
  
  @impl true
  def handle_signal(state, signal) do
    {:ok, state}
  end
  
  @impl true
  def handle_action_result(state, ExecuteToolAction, {:ok, result}, params) do
    # Cache the embedding if not already cached
    cache_key = result[:cache_key] || ExecuteToolAction.generate_cache_key(params.params)
    
    state = if not result[:cache_hit] do
      put_in(state.embedding_store[cache_key], result)
    else
      state
    end
    
    # Update generation history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      code_length: String.length(params.params.code),
      model: params.params[:model] || state.embedding_config.default_model,
      cache_hit: result[:cache_hit] || false,
      dimensions: length(hd(result.embeddings))
    }
    
    state = update_in(state.generation_history, &([history_entry | &1] |> Enum.take(100)))
    
    # Update metrics
    {:ok, update_performance_metrics(state, :generation)}
  end
  
  @impl true
  def handle_action_result(state, SimilaritySearchAction, {:ok, result}, _params) do
    # Update search history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      query: result.query,
      results_count: result.total_results,
      algorithm: result.search_algorithm
    }
    
    state = update_in(state.search_history, &([history_entry | &1] |> Enum.take(100)))
    
    {:ok, update_performance_metrics(state, "search")}
  end
  
  @impl true
  def handle_action_result(state, BuildIndexAction, {:ok, result}, _params) do
    state = put_in(state.embedding_index, result.index)
    {:ok, state}
  end
  
  @impl true
  def handle_action_result(state, _action, _result, _params) do
    {:ok, state}
  end
  
  defp update_state_after_generation(state, result, params) do
    cache_key = result[:cache_key] || ExecuteToolAction.generate_cache_key(params)
    
    state
    |> put_in([:embedding_store, cache_key], result)
    |> update_in([:performance_metrics, :total_embeddings], &(&1 + 1))
  end
  
  defp update_state_after_search(state, result) do
    state
    |> update_in([:performance_metrics, :total_searches], &(&1 + 1))
  end
  
  defp update_performance_metrics(state, :generation) do
    update_in(state.performance_metrics, fn metrics ->
      %{metrics | 
        total_embeddings: metrics.total_embeddings + 1,
        cache_misses: metrics.cache_misses + 1
      }
    end)
  end
  
  defp update_performance_metrics(state, "search") do
    update_in(state.performance_metrics, fn metrics ->
      %{metrics | total_searches: metrics.total_searches + 1}
    end)
  end
end