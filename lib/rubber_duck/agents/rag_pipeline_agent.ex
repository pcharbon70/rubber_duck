defmodule RubberDuck.Agents.RAGPipelineAgent do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) Pipeline Agent for enhanced LLM context.
  
  This agent manages the complete RAG workflow including document retrieval,
  context augmentation, and generation coordination. It provides intelligent
  document search, reranking, and optimization for high-quality LLM responses.
  
  ## Responsibilities
  
  - Multi-modal document retrieval (vector, keyword, hybrid)
  - Intelligent reranking and filtering
  - Context augmentation and optimization
  - Generation prompt construction
  - Performance analytics and A/B testing
  
  ## State Structure
  
  ```elixir
  %{
    pipelines: %{pipeline_id => pipeline_state},
    retrieval_config: %{
      vector_weight: float,
      keyword_weight: float,
      rerank_enabled: boolean
    },
    document_store: %{doc_id => document},
    cache: %{query_hash => results},
    active_tests: %{test_id => ab_test},
    metrics: %{
      queries_processed: integer,
      avg_retrieval_time_ms: float,
      avg_relevance_score: float
    }
  }
  ```
  """

  use RubberDuck.Agents.BaseAgent,
    name: "rag_pipeline",
    description: "Manages retrieval-augmented generation pipelines for enhanced LLM context",
    category: "ai_infrastructure"

  alias RubberDuck.RAG.{RAGQuery, RetrievedDocument, AugmentedContext, RetrievalEngine}
  alias RubberDuck.RAG.{AugmentationProcessor, GenerationCoordinator, PipelineMetrics}
  require Logger

  @default_config %{
    max_documents: 10,
    min_relevance_score: 0.5,
    vector_weight: 0.7,
    keyword_weight: 0.3,
    rerank_enabled: true,
    cache_ttl: 300_000,  # 5 minutes
    max_context_tokens: 4000,
    streaming_enabled: true
  }

  @retrieval_strategies [:vector_only, :keyword_only, :hybrid, :ensemble]

  ## Initialization

  @impl true
  def init(_args) do
    state = %{
      pipelines: %{},
      retrieval_config: build_retrieval_config(),
      augmentation_config: build_augmentation_config(),
      generation_config: build_generation_config(),
      document_store: %{},
      cache: %{},
      active_tests: %{},
      metrics: %{
        queries_processed: 0,
        pipelines_completed: 0,
        avg_retrieval_time_ms: 0.0,
        avg_augmentation_time_ms: 0.0,
        avg_generation_time_ms: 0.0,
        avg_relevance_score: 0.0,
        cache_hits: 0,
        cache_misses: 0,
        errors: %{}
      },
      config: @default_config
    }
    
    # Schedule periodic cache cleanup
    schedule_cache_cleanup()
    
    # Initialize retrieval engine
    {:ok, _} = RetrievalEngine.start_link()
    
    {:ok, state}
  end

  ## Signal Handlers - Pipeline Operations

    def handle_signal("execute_rag_pipeline", data, agent) do
    query = build_rag_query(data)
    
    # Check cache first
    case get_cached_results(agent, query) do
      {:ok, cached} ->
        agent = update_in(agent.metrics.cache_hits, &(&1 + 1))
        {:ok, cached, agent}
        
      :not_found ->
        agent = update_in(agent.metrics.cache_misses, &(&1 + 1))
        execute_pipeline(agent, query)
    end
  end

    def handle_signal("retrieve_documents", data, agent) do
    query = build_rag_query(data)
    start_time = System.monotonic_time(:millisecond)
    
    # Perform retrieval
    case perform_retrieval(agent, query) do
      {:ok, documents} ->
        retrieval_time = System.monotonic_time(:millisecond) - start_time
        
        agent = update_retrieval_metrics(agent, retrieval_time, documents)
        
        result = %{
          "query_id" => query.id,
          "documents" => Enum.map(documents, &document_to_map/1),
          "count" => length(documents),
          "retrieval_time_ms" => retrieval_time
        }
        
        {:ok, result, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

    def handle_signal("augment_context", data, agent) do
    %{
      "query_id" => query_id,
      "documents" => doc_data
    } = data
    
    documents = Enum.map(doc_data, &build_document/1)
    start_time = System.monotonic_time(:millisecond)
    
    # Perform augmentation
    augmented = augment_documents(agent, query_id, documents)
    augmentation_time = System.monotonic_time(:millisecond) - start_time
    
    agent = update_augmentation_metrics(agent, augmentation_time)
    
    {:ok, augmented_to_map(augmented), agent}
  end

    def handle_signal("generate_response", data, agent) do
    %{
      "query_id" => query_id,
      "context" => context_data,
      "prompt_template" => template
    } = data
    
    context = build_augmented_context(context_data)
    
    # Coordinate generation
    case coordinate_generation(agent, query_id, context, template) do
      {:ok, response} ->
        {:ok, response, agent}
        
      {:error, reason} ->
        {:error, reason, agent}
    end
  end

  ## Signal Handlers - Configuration

    def handle_signal("configure_retrieval", data, agent) do
    config_updates = %{
      max_documents: data["max_documents"] || agent.config.max_documents,
      min_relevance_score: data["min_relevance_score"] || agent.config.min_relevance_score,
      vector_weight: data["vector_weight"] || agent.retrieval_config.vector_weight,
      keyword_weight: data["keyword_weight"] || agent.retrieval_config.keyword_weight,
      rerank_enabled: data["rerank_enabled"] || agent.retrieval_config.rerank_enabled
    }
    
    agent = agent
    |> update_in([Access.key(:config)], &Map.merge(&1, config_updates))
    |> update_in([Access.key(:retrieval_config)], &Map.merge(&1, config_updates))
    
    {:ok, %{"updated" => true, "config" => config_updates}, agent}
  end

    def handle_signal("configure_augmentation", data, agent) do
    aug_config = %{
      dedup_threshold: data["dedup_threshold"] || agent.augmentation_config.dedup_threshold,
      summarization_enabled: data["summarization_enabled"] || agent.augmentation_config.summarization_enabled,
      format_standardization: data["format_standardization"] || agent.augmentation_config.format_standardization,
      max_summary_ratio: data["max_summary_ratio"] || agent.augmentation_config.max_summary_ratio
    }
    
    agent = put_in(agent.augmentation_config, Map.merge(agent.augmentation_config, aug_config))
    
    {:ok, %{"updated" => true, "config" => aug_config}, agent}
  end

    def handle_signal("configure_generation", data, agent) do
    gen_config = %{
      max_context_tokens: data["max_context_tokens"] || agent.config.max_context_tokens,
      streaming_enabled: data["streaming_enabled"] || agent.config.streaming_enabled,
      quality_check_enabled: data["quality_check_enabled"] || agent.generation_config.quality_check_enabled,
      fallback_strategy: data["fallback_strategy"] || agent.generation_config.fallback_strategy
    }
    
    agent = agent
    |> update_in([Access.key(:config)], &Map.merge(&1, gen_config))
    |> update_in([Access.key(:generation_config)], &Map.merge(&1, gen_config))
    
    {:ok, %{"updated" => true, "config" => gen_config}, agent}
  end

  ## Signal Handlers - Analytics

    def handle_signal("get_pipeline_metrics", _data, agent) do
    metrics = Map.merge(agent.metrics, %{
      "cache_hit_rate" => calculate_cache_hit_rate(agent),
      "avg_pipeline_time_ms" => calculate_avg_pipeline_time(agent),
      "success_rate" => calculate_success_rate(agent),
      "active_pipelines" => map_size(agent.pipelines),
      "cached_queries" => map_size(agent.cache),
      "document_store_size" => map_size(agent.document_store)
    })
    
    {:ok, metrics, agent}
  end

    def handle_signal("run_ab_test", data, agent) do
    test = %{
      id: generate_test_id(),
      name: data["name"],
      variant_a: data["variant_a"],
      variant_b: data["variant_b"],
      metrics_to_track: data["metrics"] || ["relevance_score", "response_time"],
      sample_size: data["sample_size"] || 100,
      current_samples: 0,
      results: %{a: [], b: []},
      started_at: DateTime.utc_now()
    }
    
    agent = put_in(agent.active_tests[test.id], test)
    
    emit_signal("ab_test_started", %{
      "test_id" => test.id,
      "name" => test.name
    })
    
    {:ok, %{"test_id" => test.id, "status" => "started"}, agent}
  end

    def handle_signal("optimize_pipeline", data, agent) do
    optimization_type = data["type"] || "auto"
    
    optimizations = case optimization_type do
      "retrieval" -> optimize_retrieval(agent)
      "augmentation" -> optimize_augmentation(agent)
      "generation" -> optimize_generation(agent)
      "auto" -> optimize_all(agent)
    end
    
    # Apply optimizations
    agent = apply_optimizations(agent, optimizations)
    
    {:ok, %{"optimizations" => optimizations, "applied" => true}, agent}
  end

  ## Private Functions - Pipeline Execution

  defp execute_pipeline(agent, query) do
    pipeline_id = query.id
    start_time = System.monotonic_time(:millisecond)
    
    # Initialize pipeline state
    pipeline_state = %{
      query: query,
      stage: :retrieval,
      started_at: DateTime.utc_now(),
      timings: %{}
    }
    
    agent = put_in(agent.pipelines[pipeline_id], pipeline_state)
    
    # Execute pipeline stages
    with {:ok, documents, agent} <- execute_retrieval_stage(agent, query),
         {:ok, augmented, agent} <- execute_augmentation_stage(agent, query, documents),
         {:ok, response, agent} <- execute_generation_stage(agent, query, augmented) do
      
      # Complete pipeline
      total_time = System.monotonic_time(:millisecond) - start_time
      
      result = %{
        "pipeline_id" => pipeline_id,
        "query" => query.query,
        "documents_retrieved" => length(documents),
        "context_size" => augmented.total_tokens,
        "response" => response,
        "total_time_ms" => total_time,
        "stages" => pipeline_state.timings
      }
      
      # Cache results
      agent = cache_pipeline_results(agent, query, result)
      
      # Update metrics
      agent = update_pipeline_metrics(agent, total_time)
      
      # Clean up pipeline state
      agent = update_in(agent.pipelines, &Map.delete(&1, pipeline_id))
      
      emit_signal("pipeline_completed", %{
        "pipeline_id" => pipeline_id,
        "duration_ms" => total_time
      })
      
      {:ok, result, agent}
    else
      {:error, reason} ->
        agent = record_pipeline_error(agent, pipeline_id, reason)
        {:error, reason, agent}
    end
  end

  defp execute_retrieval_stage(agent, query) do
    start_time = System.monotonic_time(:millisecond)
    
    case perform_retrieval(agent, query) do
      {:ok, documents} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        agent = update_in(agent.pipelines[query.id].timings, &Map.put(&1, :retrieval, duration))
        
        {:ok, documents, agent}
        
      error -> error
    end
  end

  defp execute_augmentation_stage(agent, query, documents) do
    start_time = System.monotonic_time(:millisecond)
    
    augmented = augment_documents(agent, query.id, documents)
    duration = System.monotonic_time(:millisecond) - start_time
    
    agent = update_in(agent.pipelines[query.id].timings, &Map.put(&1, :augmentation, duration))
    
    {:ok, augmented, agent}
  end

  defp execute_generation_stage(agent, query, augmented_context) do
    start_time = System.monotonic_time(:millisecond)
    
    case coordinate_generation(agent, query.id, augmented_context, query.generation_config["template"]) do
      {:ok, response} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        agent = update_in(agent.pipelines[query.id].timings, &Map.put(&1, :generation, duration))
        
        {:ok, response, agent}
        
      error -> error
    end
  end

  ## Private Functions - Retrieval

  defp perform_retrieval(agent, query) do
    strategy = determine_retrieval_strategy(agent, query)
    
    try do
      documents = case strategy do
        :vector_only -> 
          RetrievalEngine.vector_search(query.query, agent.config.max_documents)
          
        :keyword_only ->
          RetrievalEngine.keyword_search(query.query, agent.config.max_documents)
          
        :hybrid ->
          perform_hybrid_retrieval(agent, query)
          
        :ensemble ->
          perform_ensemble_retrieval(agent, query)
      end
      
      # Filter by relevance score
      filtered = Enum.filter(documents, fn doc ->
        doc.relevance_score >= agent.config.min_relevance_score
      end)
      
      # Rerank if enabled
      reranked = if agent.retrieval_config.rerank_enabled do
        rerank_documents(filtered, query)
      else
        filtered
      end
      
      {:ok, reranked}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp perform_hybrid_retrieval(agent, query) do
    # Get results from both vector and keyword search
    vector_task = Task.async(fn ->
      RetrievalEngine.vector_search(query.query, agent.config.max_documents * 2)
    end)
    
    keyword_task = Task.async(fn ->
      RetrievalEngine.keyword_search(query.query, agent.config.max_documents * 2)
    end)
    
    vector_results = Task.await(vector_task)
    keyword_results = Task.await(keyword_task)
    
    # Merge and score
    merge_retrieval_results(
      vector_results,
      keyword_results,
      agent.retrieval_config.vector_weight,
      agent.retrieval_config.keyword_weight
    )
    |> Enum.take(agent.config.max_documents)
  end

  defp perform_ensemble_retrieval(agent, query) do
    # Use multiple retrieval strategies and ensemble
    strategies = [:vector_only, :keyword_only, :semantic_expansion]
    
    results = Enum.map(strategies, fn strategy ->
      Task.async(fn ->
        case strategy do
          :semantic_expansion ->
            expanded_query = expand_query_semantically(query.query)
            RetrievalEngine.vector_search(expanded_query, agent.config.max_documents)
          _ ->
            perform_retrieval(%{agent | retrieval_config: %{agent.retrieval_config | strategy: strategy}}, query)
        end
      end)
    end)
    |> Enum.map(&Task.await/1)
    
    # Ensemble results
    ensemble_documents(results)
    |> Enum.take(agent.config.max_documents)
  end

  defp merge_retrieval_results(vector_docs, keyword_docs, vector_weight, keyword_weight) do
    # Create maps for easy lookup
    vector_map = Map.new(vector_docs, fn doc -> {doc.id, doc} end)
    keyword_map = Map.new(keyword_docs, fn doc -> {doc.id, doc} end)
    
    all_ids = MapSet.union(MapSet.new(Map.keys(vector_map)), MapSet.new(Map.keys(keyword_map)))
    
    Enum.map(all_ids, fn id ->
      vector_doc = Map.get(vector_map, id)
      keyword_doc = Map.get(keyword_map, id)
      
      merged_score = calculate_merged_score(
        vector_doc && vector_doc.relevance_score,
        keyword_doc && keyword_doc.relevance_score,
        vector_weight,
        keyword_weight
      )
      
      base_doc = vector_doc || keyword_doc
      %{base_doc | relevance_score: merged_score}
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
  end

  defp calculate_merged_score(nil, keyword_score, _vector_weight, keyword_weight) do
    keyword_score * keyword_weight * 0.8  # Penalty for missing vector score
  end
  
  defp calculate_merged_score(vector_score, nil, vector_weight, _keyword_weight) do
    vector_score * vector_weight * 0.8  # Penalty for missing keyword score
  end
  
  defp calculate_merged_score(vector_score, keyword_score, vector_weight, keyword_weight) do
    vector_score * vector_weight + keyword_score * keyword_weight
  end

  defp rerank_documents(documents, query) do
    # Simple reranking based on query terms and document metadata
    query_terms = String.split(String.downcase(query.query))
    
    Enum.map(documents, fn doc ->
      boost = calculate_rerank_boost(doc, query_terms)
      %{doc | relevance_score: doc.relevance_score * boost}
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
  end

  defp calculate_rerank_boost(document, query_terms) do
    content_lower = String.downcase(document.content)
    
    # Calculate term frequency boost
    term_freq_boost = Enum.reduce(query_terms, 0, fn term, acc ->
      occurrences = length(String.split(content_lower, term)) - 1
      acc + min(occurrences * 0.1, 0.3)
    end)
    
    # Metadata boost
    metadata_boost = case document.metadata do
      %{"importance" => "high"} -> 0.2
      %{"verified" => true} -> 0.1
      _ -> 0.0
    end
    
    1.0 + term_freq_boost + metadata_boost
  end

  ## Private Functions - Augmentation

  defp augment_documents(agent, query_id, documents) do
    config = agent.augmentation_config
    
    # Build augmentation pipeline
    pipeline = [
      {:deduplicate, config.dedup_threshold},
      {:standardize_format, config.format_standardization},
      {:summarize, config.summarization_enabled},
      {:validate, true}
    ]
    
    # Process documents through pipeline
    processed_docs = Enum.reduce(pipeline, documents, fn {step, param}, docs ->
      apply_augmentation_step(step, docs, param, config)
    end)
    
    # Build augmented context
    AugmentedContext.new(%{
      query_id: query_id,
      documents: processed_docs,
      summary: generate_context_summary(processed_docs),
      metadata: %{
        original_count: length(documents),
        processed_count: length(processed_docs),
        augmentation_steps: Keyword.keys(pipeline)
      },
      total_tokens: calculate_total_tokens(processed_docs)
    })
  end

  defp apply_augmentation_step(:deduplicate, docs, threshold, _config) do
    AugmentationProcessor.deduplicate(docs, threshold)
  end

  defp apply_augmentation_step(:standardize_format, docs, true, _config) do
    Enum.map(docs, &AugmentationProcessor.standardize_format/1)
  end

  defp apply_augmentation_step(:standardize_format, docs, false, _config), do: docs

  defp apply_augmentation_step(:summarize, docs, true, config) do
    max_tokens_per_doc = div(config.max_context_tokens, length(docs))
    
    Enum.map(docs, fn doc ->
      if doc.size_tokens > max_tokens_per_doc do
        AugmentationProcessor.summarize(doc, config.max_summary_ratio)
      else
        doc
      end
    end)
  end

  defp apply_augmentation_step(:summarize, docs, false, _config), do: docs

  defp apply_augmentation_step(:validate, docs, true, _config) do
    Enum.filter(docs, &AugmentationProcessor.validate_document/1)
  end

  defp generate_context_summary(documents) do
    # Generate a brief summary of all documents
    doc_summaries = Enum.map(documents, fn doc ->
      "- #{doc.metadata["title"] || "Document"}: #{String.slice(doc.content, 0, 100)}..."
    end)
    
    """
    Context contains #{length(documents)} documents:
    #{Enum.join(doc_summaries, "\n")}
    """
  end

  defp calculate_total_tokens(documents) do
    Enum.sum(Enum.map(documents, & &1.size_tokens))
  end

  ## Private Functions - Generation

  defp coordinate_generation(agent, query_id, context, template) do
    config = agent.generation_config
    
    # Build prompt
    prompt = GenerationCoordinator.build_prompt(template, context, config)
    
    # Check token limits
    if String.length(prompt) > config.max_prompt_length do
      # Apply fallback strategy
      prompt = apply_fallback_strategy(prompt, context, config)
    end
    
    # Emit generation request
    generation_data = %{
      "query_id" => query_id,
      "prompt" => prompt,
      "streaming" => config.streaming_enabled,
      "max_tokens" => config.max_response_tokens,
      "temperature" => config.temperature || 0.7
    }
    
    case emit_signal("generate_completion", generation_data) do
      {:ok, response} ->
        # Quality check if enabled
        if config.quality_check_enabled do
          verify_response_quality(response, context)
        else
          {:ok, response}
        end
        
      error -> error
    end
  end

  defp apply_fallback_strategy(prompt, context, config) do
    case config.fallback_strategy do
      "truncate" ->
        # Simple truncation
        String.slice(prompt, 0, config.max_prompt_length)
        
      "summarize_context" ->
        # Summarize context more aggressively
        summarized_context = AugmentationProcessor.aggressive_summarize(context, 0.2)
        GenerationCoordinator.build_prompt(config.template, summarized_context, config)
        
      "reduce_documents" ->
        # Keep only top documents
        reduced_context = %{context | documents: Enum.take(context.documents, 3)}
        GenerationCoordinator.build_prompt(config.template, reduced_context, config)
        
      _ ->
        prompt  # No fallback
    end
  end

  defp verify_response_quality(response, context) do
    quality_score = GenerationCoordinator.assess_quality(response, context)
    
    if quality_score >= 0.7 do
      {:ok, response}
    else
      {:error, "Response quality below threshold: #{quality_score}"}
    end
  end

  ## Private Functions - Caching

  defp get_cached_results(agent, query) do
    cache_key = generate_cache_key(query)
    
    case Map.get(agent.cache, cache_key) do
      nil -> :not_found
      cached ->
        if cache_still_valid?(cached, agent.config.cache_ttl) do
          {:ok, cached["result"]}
        else
          :not_found
        end
    end
  end

  defp cache_pipeline_results(agent, query, result) do
    cache_key = generate_cache_key(query)
    
    cache_entry = %{
      "result" => result,
      "cached_at" => DateTime.utc_now(),
      "query" => query.query
    }
    
    put_in(agent.cache[cache_key], cache_entry)
  end

  defp generate_cache_key(query) do
    key_string = "#{query.query}_#{inspect(query.retrieval_config)}"
    :crypto.hash(:md5, key_string) |> Base.encode16(case: :lower)
  end

  defp cache_still_valid?(cached_entry, ttl) do
    age = DateTime.diff(DateTime.utc_now(), cached_entry["cached_at"], :millisecond)
    age < ttl
  end

  ## Private Functions - Metrics

  defp update_retrieval_metrics(agent, retrieval_time, documents) do
    avg_relevance = if length(documents) > 0 do
      Enum.sum(Enum.map(documents, & &1.relevance_score)) / length(documents)
    else
      0.0
    end
    
    queries = agent.metrics.queries_processed + 1
    
    agent
    |> put_in([Access.key(:metrics), :queries_processed], queries)
    |> put_in([Access.key(:metrics), :avg_retrieval_time_ms], 
              update_average(agent.metrics.avg_retrieval_time_ms, retrieval_time, queries))
    |> put_in([Access.key(:metrics), :avg_relevance_score],
              update_average(agent.metrics.avg_relevance_score, avg_relevance, queries))
  end

  defp update_augmentation_metrics(agent, augmentation_time) do
    count = agent.metrics.queries_processed
    
    update_in(agent.metrics.avg_augmentation_time_ms, fn avg ->
      update_average(avg, augmentation_time, count)
    end)
  end

  defp update_pipeline_metrics(agent, total_time) do
    completed = agent.metrics.pipelines_completed + 1
    
    update_in(agent.metrics.pipelines_completed, fn _ -> completed end)
  end

  defp update_average(current_avg, new_value, count) do
    if count <= 1 do
      new_value / 1
    else
      (current_avg * (count - 1) + new_value) / count
    end
  end

  defp calculate_cache_hit_rate(agent) do
    total = agent.metrics.cache_hits + agent.metrics.cache_misses
    if total > 0 do
      agent.metrics.cache_hits / total * 100
    else
      0.0
    end
  end

  defp calculate_avg_pipeline_time(agent) do
    agent.metrics.avg_retrieval_time_ms +
    agent.metrics.avg_augmentation_time_ms +
    agent.metrics.avg_generation_time_ms
  end

  defp calculate_success_rate(agent) do
    total_errors = agent.metrics.errors |> Map.values() |> Enum.sum()
    total_attempts = agent.metrics.pipelines_completed + total_errors
    
    if total_attempts > 0 do
      agent.metrics.pipelines_completed / total_attempts * 100
    else
      100.0
    end
  end

  ## Private Functions - Optimization

  defp optimize_retrieval(agent) do
    # Analyze retrieval metrics and suggest optimizations
    %{
      "strategy" => suggest_retrieval_strategy(agent),
      "weights" => optimize_retrieval_weights(agent),
      "max_documents" => suggest_document_count(agent)
    }
  end

  defp optimize_augmentation(agent) do
    %{
      "dedup_threshold" => suggest_dedup_threshold(agent),
      "summarization" => should_enable_summarization?(agent),
      "format_standardization" => true
    }
  end

  defp optimize_generation(agent) do
    %{
      "max_context_tokens" => suggest_context_size(agent),
      "fallback_strategy" => "summarize_context",
      "quality_check_enabled" => agent.metrics.avg_relevance_score < 0.7
    }
  end

  defp optimize_all(agent) do
    %{
      "retrieval" => optimize_retrieval(agent),
      "augmentation" => optimize_augmentation(agent),
      "generation" => optimize_generation(agent)
    }
  end

  defp apply_optimizations(agent, optimizations) do
    Enum.reduce(optimizations, agent, fn {component, opts}, acc ->
      apply_component_optimizations(acc, component, opts)
    end)
  end

  defp apply_component_optimizations(agent, "retrieval", opts) do
    agent
    |> put_in([Access.key(:retrieval_config), :strategy], opts["strategy"])
    |> put_in([Access.key(:retrieval_config), :vector_weight], opts["weights"]["vector"])
    |> put_in([Access.key(:retrieval_config), :keyword_weight], opts["weights"]["keyword"])
    |> put_in([Access.key(:config), :max_documents], opts["max_documents"])
  end

  defp apply_component_optimizations(agent, "augmentation", opts) do
    put_in(agent.augmentation_config, Map.merge(agent.augmentation_config, opts))
  end

  defp apply_component_optimizations(agent, "generation", opts) do
    agent
    |> put_in([Access.key(:config), :max_context_tokens], opts["max_context_tokens"])
    |> put_in([Access.key(:generation_config)], Map.merge(agent.generation_config, opts))
  end

  ## Private Functions - Helpers

  defp build_rag_query(data) do
    RAGQuery.new(%{
      id: data["query_id"] || generate_query_id(),
      query: data["query"],
      retrieval_config: data["retrieval_config"] || %{},
      augmentation_config: data["augmentation_config"] || %{},
      generation_config: data["generation_config"] || %{},
      metadata: data["metadata"] || %{}
    })
  end

  defp build_document(doc_data) do
    RetrievedDocument.new(%{
      id: doc_data["id"],
      content: doc_data["content"],
      metadata: doc_data["metadata"] || %{},
      relevance_score: doc_data["relevance_score"] || 0.5,
      source: doc_data["source"] || "unknown"
    })
  end

  defp build_augmented_context(data) do
    AugmentedContext.new(%{
      query_id: data["query_id"],
      documents: Enum.map(data["documents"] || [], &build_document/1),
      summary: data["summary"],
      metadata: data["metadata"] || %{},
      total_tokens: data["total_tokens"] || 0
    })
  end

  defp document_to_map(doc) do
    %{
      "id" => doc.id,
      "content" => doc.content,
      "metadata" => doc.metadata,
      "relevance_score" => doc.relevance_score,
      "source" => doc.source
    }
  end

  defp augmented_to_map(augmented) do
    %{
      "query_id" => augmented.query_id,
      "documents" => Enum.map(augmented.documents, &document_to_map/1),
      "summary" => augmented.summary,
      "metadata" => augmented.metadata,
      "total_tokens" => augmented.total_tokens
    }
  end

  defp build_retrieval_config do
    %{
      strategy: :hybrid,
      vector_weight: 0.7,
      keyword_weight: 0.3,
      rerank_enabled: true,
      expansion_enabled: false
    }
  end

  defp build_augmentation_config do
    %{
      dedup_threshold: 0.85,
      summarization_enabled: true,
      format_standardization: true,
      max_summary_ratio: 0.3,
      max_context_tokens: 4000
    }
  end

  defp build_generation_config do
    %{
      max_prompt_length: 8000,
      max_response_tokens: 2000,
      streaming_enabled: true,
      quality_check_enabled: true,
      fallback_strategy: "summarize_context",
      temperature: 0.7
    }
  end

  defp determine_retrieval_strategy(agent, query) do
    cond do
      query.retrieval_config["force_strategy"] ->
        String.to_atom(query.retrieval_config["force_strategy"])
        
      agent.retrieval_config.strategy ->
        agent.retrieval_config.strategy
        
      true ->
        :hybrid
    end
  end

  defp expand_query_semantically(query) do
    # Simple semantic expansion - in production, use proper NLP
    synonyms = %{
      "bug" => ["error", "issue", "problem"],
      "fix" => ["resolve", "repair", "correct"],
      "create" => ["make", "build", "generate"]
    }
    
    words = String.split(query)
    expanded = Enum.flat_map(words, fn word ->
      [word | Map.get(synonyms, String.downcase(word), [])]
    end)
    
    Enum.join(Enum.uniq(expanded), " ")
  end

  defp ensemble_documents(result_lists) do
    # Combine multiple result lists using voting
    all_docs = List.flatten(result_lists)
    
    # Group by ID and average scores
    all_docs
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {_id, docs} ->
      base_doc = hd(docs)
      avg_score = Enum.sum(Enum.map(docs, & &1.relevance_score)) / length(docs)
      %{base_doc | relevance_score: avg_score}
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
  end

  defp suggest_retrieval_strategy(agent) do
    # Based on metrics, suggest best strategy
    if agent.metrics.avg_relevance_score < 0.6 do
      :ensemble
    else
      :hybrid
    end
  end

  defp optimize_retrieval_weights(agent) do
    # Simple optimization - in production, use ML
    %{
      "vector" => if(agent.metrics.avg_relevance_score > 0.7, do: 0.8, else: 0.6),
      "keyword" => if(agent.metrics.avg_relevance_score > 0.7, do: 0.2, else: 0.4)
    }
  end

  defp suggest_document_count(agent) do
    # Based on context usage
    avg_tokens_per_doc = if agent.metrics.queries_processed > 0 do
      agent.config.max_context_tokens / agent.config.max_documents
    else
      400
    end
    
    min(max(round(agent.config.max_context_tokens / avg_tokens_per_doc), 5), 20)
  end

  defp suggest_dedup_threshold(agent) do
    # Lower threshold if getting too many similar documents
    if agent.metrics.avg_relevance_score > 0.8 do
      0.9  # Stricter deduplication
    else
      0.85  # Standard deduplication
    end
  end

  defp should_enable_summarization?(agent) do
    # Enable if frequently hitting token limits
    agent.metrics.avg_augmentation_time_ms > 100
  end

  defp suggest_context_size(agent) do
    # Adjust based on generation success
    if calculate_success_rate(agent) < 90 do
      round(agent.config.max_context_tokens * 0.8)
    else
      agent.config.max_context_tokens
    end
  end

  defp record_pipeline_error(agent, pipeline_id, reason) do
    error_type = categorize_error(reason)
    
    agent
    |> update_in([Access.key(:metrics), :errors, error_type], &((&1 || 0) + 1))
    |> update_in([Access.key(:pipelines)], &Map.delete(&1, pipeline_id))
  end

  defp categorize_error(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "retrieval") -> :retrieval_errors
      String.contains?(reason, "augmentation") -> :augmentation_errors
      String.contains?(reason, "generation") -> :generation_errors
      true -> :other_errors
    end
  end
  defp categorize_error(_), do: :other_errors

  defp generate_query_id do
    "rag_query_" <> :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end

  defp generate_test_id do
    "ab_test_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  ## Scheduled Tasks

  defp schedule_cache_cleanup do
    Process.send_after(self(), :cleanup_cache, 60_000)  # Every minute
  end

  @impl true
  def handle_info(:cleanup_cache, agent) do
    # Remove expired cache entries
    now = DateTime.utc_now()
    
    updated_cache = agent.cache
    |> Enum.filter(fn {_key, entry} ->
      age = DateTime.diff(now, entry["cached_at"], :millisecond)
      age < agent.config.cache_ttl
    end)
    |> Map.new()
    
    removed = map_size(agent.cache) - map_size(updated_cache)
    
    if removed > 0 do
      Logger.debug("RAG cache cleanup: removed #{removed} expired entries")
    end
    
    schedule_cache_cleanup()
    
    {:noreply, %{agent | cache: updated_cache}}
  end
end