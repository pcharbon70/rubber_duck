defmodule RubberDuck.Agents.ResearchAgent do
  @moduledoc """
  Research Agent specialized in information gathering, context building, and semantic search.

  The Research Agent is responsible for:
  - Gathering relevant information from various sources
  - Building comprehensive context for tasks
  - Performing semantic searches across codebases and documentation
  - Extracting insights from code patterns and structures
  - Providing background knowledge for other agents

  ## Capabilities

  - `:semantic_search` - Advanced semantic search across code and docs
  - `:context_building` - Building comprehensive task context
  - `:pattern_analysis` - Identifying code patterns and structures
  - `:information_extraction` - Extracting relevant information from sources
  - `:knowledge_synthesis` - Combining information from multiple sources

  ## Task Types

  - `:research_topic` - Research a specific topic or technology
  - `:gather_context` - Gather context for a coding task
  - `:analyze_patterns` - Analyze code patterns in a codebase
  - `:extract_documentation` - Extract and synthesize documentation
  - `:build_knowledge_base` - Build knowledge base from sources

  ## Example Usage

      # Research a specific topic
      task = %{
        id: "research_1",
        type: :research_topic,
        payload: %{
          topic: "elixir genserver patterns",
          scope: :comprehensive,
          sources: [:code, :documentation, :memory]
        }
      }

      {:ok, result} = Agent.assign_task(agent_pid, task, context)
  """

  use RubberDuck.Agents.Behavior

  alias RubberDuck.Memory.Manager, as: MemoryManager
  # alias RubberDuck.RAG.{Retrieval, Chunking}
  alias RubberDuck.Analysis.AST
  # alias RubberDuck.LLM.Service, as: LLMService

  require Logger

  @capabilities [
    :semantic_search,
    :context_building,
    :pattern_analysis,
    :information_extraction,
    :knowledge_synthesis
  ]

  # Behavior Implementation

  @impl true
  def init(config) do
    state = %{
      config: config,
      workspace: setup_workspace(config),
      knowledge_cache: %{},
      search_indices: %{},
      metrics: initialize_metrics(),
      last_activity: DateTime.utc_now()
    }

    Logger.info("Research Agent initialized with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_task(task, context, state) do
    Logger.info("Research Agent handling task: #{task.type}")

    case task.type do
      :research_topic ->
        handle_research_topic(task, context, state)

      :gather_context ->
        handle_gather_context(task, context, state)

      :analyze_patterns ->
        handle_analyze_patterns(task, context, state)

      :extract_documentation ->
        handle_extract_documentation(task, context, state)

      :build_knowledge_base ->
        handle_build_knowledge_base(task, context, state)

      :semantic_search ->
        handle_semantic_search(task, context, state)

      _ ->
        {:error, {:unsupported_task_type, task.type}, state}
    end
  end

  @impl true
  def handle_message(message, from, state) do
    case message do
      {:search_request, query, filters} ->
        result = perform_search(query, filters, state)
        send_response(from, {:search_result, result})
        {:ok, state}

      {:context_request, task_context} ->
        context = build_enhanced_context(task_context, state)
        send_response(from, {:context_result, context})
        {:ok, state}

      {:knowledge_query, topic} ->
        knowledge = extract_knowledge(topic, state)
        send_response(from, {:knowledge_result, knowledge})
        {:ok, state}

      _ ->
        Logger.debug("Research Agent received unknown message: #{inspect(message)}")
        {:noreply, state}
    end
  end

  @impl true
  def get_capabilities(_state) do
    @capabilities
  end

  @impl true
  def get_status(state) do
    %{
      status: determine_status(state),
      current_task: Map.get(state, :current_task),
      metrics: state.metrics,
      health: %{
        healthy: true,
        workspace_size: map_size(state.workspace),
        cache_size: map_size(state.knowledge_cache)
      },
      last_activity: state.last_activity,
      capabilities: @capabilities
    }
  end

  @impl true
  def terminate(_reason, state) do
    Logger.info("Research Agent terminating, cleaning up workspace")
    cleanup_workspace(state.workspace)
    :ok
  end

  # Task Handlers

  defp handle_research_topic(%{payload: payload} = _task, context, state) do
    topic = payload.topic
    scope = Map.get(payload, :scope, :standard)
    sources = Map.get(payload, :sources, [:memory, :code])

    research_result = %{
      topic: topic,
      scope: scope,
      findings: [],
      sources_searched: [],
      confidence: 0.0,
      timestamp: DateTime.utc_now()
    }

    # Perform research across different sources
    research_result =
      sources
      |> Enum.reduce(research_result, fn source, acc ->
        case research_from_source(topic, source, scope, context, state) do
          {:ok, findings} ->
            %{
              acc
              | findings: acc.findings ++ findings,
                sources_searched: [source | acc.sources_searched]
            }

          {:error, reason} ->
            Logger.warning("Research failed for source #{source}: #{inspect(reason)}")
            acc
        end
      end)

    # Calculate confidence based on findings
    final_result = %{
      research_result
      | confidence: calculate_research_confidence(research_result)
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :research_topic),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_gather_context(%{payload: payload} = _task, context, state) do
    # Code file, function, module, etc.
    target = payload.target
    depth = Map.get(payload, :depth, :medium)

    context_result = %{
      target: target,
      context_type: determine_context_type(target),
      related_items: [],
      dependencies: [],
      usage_patterns: [],
      documentation: [],
      confidence: 0.0
    }

    # Build context based on target type
    context_result =
      case context_result.context_type do
        :code_file ->
          gather_file_context(target, depth, context, state, context_result)

        :function ->
          gather_function_context(target, depth, context, state, context_result)

        :module ->
          gather_module_context(target, depth, context, state, context_result)

        :topic ->
          gather_topic_context(target, depth, context, state, context_result)
      end

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :gather_context),
        last_activity: DateTime.utc_now()
    }

    {:ok, context_result, new_state}
  end

  defp handle_analyze_patterns(%{payload: payload} = _task, context, state) do
    codebase_path = payload.codebase_path
    pattern_types = Map.get(payload, :pattern_types, [:all])

    analysis_result = %{
      codebase_path: codebase_path,
      patterns_found: [],
      pattern_summary: %{},
      recommendations: [],
      confidence: 0.0
    }

    # Analyze different pattern types
    analysis_result =
      pattern_types
      |> Enum.reduce(analysis_result, fn pattern_type, acc ->
        {:ok, patterns} = analyze_pattern_type(codebase_path, pattern_type, context, state)

        %{
          acc
          | patterns_found: acc.patterns_found ++ patterns
        }
      end)

    # Generate summary and recommendations
    final_result = %{
      analysis_result
      | pattern_summary: summarize_patterns(analysis_result.patterns_found),
        recommendations: generate_pattern_recommendations(analysis_result.patterns_found),
        confidence: calculate_pattern_confidence(analysis_result.patterns_found)
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :analyze_patterns),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_extract_documentation(%{payload: payload} = _task, context, state) do
    source = payload.source
    format = Map.get(payload, :format, :markdown)

    extraction_result = %{
      source: source,
      format: format,
      extracted_docs: [],
      structure: %{},
      metadata: %{},
      confidence: 0.0
    }

    # Extract documentation based on source type
    {:ok, docs} = extract_docs_from_source(source, format, context, state)

    final_result = %{
      extraction_result
      | extracted_docs: docs,
        structure: analyze_doc_structure(docs),
        metadata: extract_doc_metadata(docs),
        confidence: 0.9
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :extract_documentation),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_build_knowledge_base(%{payload: payload} = _task, context, state) do
    sources = payload.sources
    domain = Map.get(payload, :domain, :general)

    kb_result = %{
      domain: domain,
      sources_processed: [],
      knowledge_items: [],
      relationships: [],
      confidence: 0.0
    }

    # Process each source
    kb_result =
      sources
      |> Enum.reduce(kb_result, fn source, acc ->
        {:ok, knowledge} = process_knowledge_source(source, domain, context, state)

        %{
          acc
          | sources_processed: [source | acc.sources_processed],
            knowledge_items: acc.knowledge_items ++ knowledge.items,
            relationships: acc.relationships ++ knowledge.relationships
        }
      end)

    # Build relationships between knowledge items
    final_result = %{
      kb_result
      | relationships: build_knowledge_relationships(kb_result.knowledge_items),
        confidence: calculate_kb_confidence(kb_result)
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :build_knowledge_base),
        knowledge_cache: update_knowledge_cache(state.knowledge_cache, final_result),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  defp handle_semantic_search(%{payload: payload} = _task, context, state) do
    query = payload.query
    scope = Map.get(payload, :scope, :all)
    limit = Map.get(payload, :limit, 10)

    search_result = %{
      query: query,
      scope: scope,
      results: [],
      total_found: 0,
      search_time: 0,
      confidence: 0.0
    }

    start_time = System.monotonic_time(:millisecond)

    # Perform semantic search
    {:ok, results} = perform_semantic_search(query, scope, limit, context, state)

    search_time = System.monotonic_time(:millisecond) - start_time

    final_result = %{
      search_result
      | results: results,
        total_found: length(results),
        search_time: search_time,
        confidence: calculate_search_confidence(results)
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :semantic_search),
        last_activity: DateTime.utc_now()
    }

    {:ok, final_result, new_state}
  end

  # Helper Functions

  defp setup_workspace(config) do
    %{
      temp_dir: System.tmp_dir(),
      cache_dir: Map.get(config, :cache_dir, "/tmp/research_agent"),
      # 100MB
      max_cache_size: Map.get(config, :max_cache_size, 100_000_000)
    }
  end

  defp cleanup_workspace(workspace) do
    # Clean up temporary files and caches
    case File.rm_rf(workspace.cache_dir) do
      {:ok, _} -> :ok
      # Don't fail if cleanup fails
      _ -> :ok
    end
  end

  defp initialize_metrics do
    %{
      tasks_completed: 0,
      research_topics: 0,
      contexts_gathered: 0,
      patterns_analyzed: 0,
      searches_performed: 0,
      total_execution_time: 0
    }
  end

  defp update_task_metrics(metrics, task_type) do
    metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(task_type, 1, &(&1 + 1))
  end

  defp determine_status(state) do
    if Map.has_key?(state, :current_task) do
      :busy
    else
      :idle
    end
  end

  defp research_from_source(topic, :memory, scope, _context, _state) do
    # Search memory for topic-related information
    case MemoryManager.search(topic, scope: scope) do
      {:ok, memories} ->
        findings =
          memories
          |> Enum.map(&convert_memory_to_finding/1)
          |> Enum.filter(&(&1.relevance > 0.3))

        {:ok, findings}

      error ->
        error
    end
  end

  defp research_from_source(topic, :code, scope, context, state) do
    # Search codebase for topic-related patterns
    case search_codebase_for_topic(topic, scope, context, state) do
      {:ok, code_findings} ->
        {:ok, code_findings}

      error ->
        error
    end
  end

  defp research_from_source(topic, :documentation, scope, context, state) do
    # Search documentation for topic information
    case search_documentation_for_topic(topic, scope, context, state) do
      {:ok, doc_findings} ->
        {:ok, doc_findings}

      error ->
        error
    end
  end

  defp search_codebase_for_topic(topic, _scope, _context, _state) do
    # Simplified codebase search - in production would use advanced indexing
    findings = [
      %{
        type: :code_pattern,
        content: "Found GenServer patterns related to #{topic}",
        source: "lib/example.ex",
        relevance: 0.8,
        metadata: %{pattern_type: :genserver}
      }
    ]

    {:ok, findings}
  end

  defp search_documentation_for_topic(topic, _scope, _context, _state) do
    # Simplified documentation search
    findings = [
      %{
        type: :documentation,
        content: "Documentation about #{topic}",
        source: "docs/#{String.downcase(topic)}.md",
        relevance: 0.7,
        metadata: %{doc_type: :guide}
      }
    ]

    {:ok, findings}
  end

  defp convert_memory_to_finding(memory) do
    %{
      type: :memory,
      content: memory.content,
      source: "memory_#{memory.id}",
      relevance: memory.relevance_score || 0.5,
      metadata: %{
        memory_type: memory.type,
        created_at: memory.created_at
      }
    }
  end

  defp calculate_research_confidence(research_result) do
    if Enum.empty?(research_result.findings) do
      0.0
    else
      avg_relevance =
        research_result.findings
        |> Enum.map(& &1.relevance)
        |> Enum.sum()
        |> Kernel./(length(research_result.findings))

      # Factor in number of sources
      source_factor = min(length(research_result.sources_searched) / 3, 1.0)

      avg_relevance * source_factor
    end
  end

  defp determine_context_type(target) do
    cond do
      String.ends_with?(target, ".ex") or String.ends_with?(target, ".exs") ->
        :code_file

      String.contains?(target, "/") and String.contains?(target, ".") ->
        :function

      String.match?(target, ~r/^[A-Z][a-zA-Z0-9]*(\.[A-Z][a-zA-Z0-9]*)*$/) ->
        :module

      true ->
        :topic
    end
  end

  defp gather_file_context(file_path, _depth, _context, _state, context_result) do
    # Analyze file and gather related context
    case AST.parse(File.read!(file_path), :elixir) do
      {:ok, ast_info} ->
        %{
          context_result
          | related_items: find_related_files(file_path, ast_info),
            dependencies: extract_dependencies(ast_info),
            usage_patterns: analyze_usage_patterns(ast_info),
            confidence: 0.8
        }

      {:error, _reason} ->
        %{context_result | confidence: 0.2}
    end
  end

  defp gather_function_context(_function_spec, _depth, _context, _state, context_result) do
    # Parse function specification and gather context
    %{context_result | confidence: 0.6}
  end

  defp gather_module_context(_module_name, _depth, _context, _state, context_result) do
    # Analyze module and gather context
    %{context_result | confidence: 0.7}
  end

  defp gather_topic_context(_topic, _depth, _context, _state, context_result) do
    # Research topic and build context
    %{context_result | confidence: 0.5}
  end

  defp find_related_files(_file_path, _ast_info) do
    # Simplified related file detection
    []
  end

  defp extract_dependencies(ast_info) do
    (ast_info.aliases || []) ++ (ast_info.imports || []) ++ (ast_info.requires || [])
  end

  defp analyze_usage_patterns(ast_info) do
    # Analyze how functions are called and used
    ast_info.calls || []
  end

  defp analyze_pattern_type(codebase_path, pattern_type, _context, _state) do
    # Analyze specific pattern types in codebase
    patterns = [
      %{
        type: pattern_type,
        location: "#{codebase_path}/lib/example.ex:25",
        description: "GenServer pattern implementation",
        confidence: 0.9
      }
    ]

    {:ok, patterns}
  end

  defp summarize_patterns(patterns) do
    # Generate pattern summary
    patterns
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, pattern_list} -> {type, length(pattern_list)} end)
  end

  defp generate_pattern_recommendations(_patterns) do
    # Generate recommendations based on patterns found
    [
      "Consider consolidating similar GenServer patterns",
      "Review error handling patterns for consistency"
    ]
  end

  defp calculate_pattern_confidence(patterns) do
    if Enum.empty?(patterns) do
      0.0
    else
      patterns
      |> Enum.map(& &1.confidence)
      |> Enum.sum()
      |> Kernel./(length(patterns))
    end
  end

  defp extract_docs_from_source(source, format, _context, _state) do
    # Extract documentation from various sources
    docs = [
      %{
        title: "Example Documentation",
        content: "This is example documentation content",
        format: format,
        source: source
      }
    ]

    {:ok, docs}
  end

  defp analyze_doc_structure(docs) do
    # Analyze documentation structure
    %{
      sections: length(docs),
      has_examples: true,
      has_api_docs: true
    }
  end

  defp extract_doc_metadata(docs) do
    # Extract metadata from documentation
    %{
      total_docs: length(docs),
      languages: [:elixir],
      last_updated: DateTime.utc_now()
    }
  end

  defp process_knowledge_source(source, domain, _context, _state) do
    # Process knowledge from various sources
    knowledge = %{
      items: [
        %{
          id: "knowledge_1",
          content: "Knowledge extracted from #{inspect(source)}",
          domain: domain,
          confidence: 0.8
        }
      ],
      relationships: []
    }

    {:ok, knowledge}
  end

  defp build_knowledge_relationships(_knowledge_items) do
    # Build relationships between knowledge items
    # Simplified - would implement relationship detection
    []
  end

  defp calculate_kb_confidence(kb_result) do
    if Enum.empty?(kb_result.knowledge_items) do
      0.0
    else
      # Simplified confidence calculation
      0.7
    end
  end

  defp update_knowledge_cache(cache, kb_result) do
    # Update the knowledge cache with new results
    Map.put(cache, kb_result.domain, kb_result)
  end

  defp perform_semantic_search(query, _scope, limit, _context, _state) do
    # Perform semantic search across available sources
    results =
      [
        %{
          content: "Semantic search result for: #{query}",
          relevance: 0.95,
          source: "memory",
          metadata: %{type: :code_example}
        },
        %{
          content: "Additional result for: #{query}",
          relevance: 0.87,
          source: "documentation",
          metadata: %{type: :guide}
        }
      ]
      |> Enum.take(limit)

    {:ok, results}
  end

  defp calculate_search_confidence(results) do
    if Enum.empty?(results) do
      0.0
    else
      results
      |> Enum.map(& &1.relevance)
      |> Enum.sum()
      |> Kernel./(length(results))
    end
  end

  defp perform_search(query, filters, _state) do
    # Perform filtered search
    %{
      query: query,
      filters: filters,
      results: [],
      total: 0
    }
  end

  defp build_enhanced_context(task_context, _state) do
    # Build enhanced context using agent's knowledge
    Map.merge(task_context, %{
      enhanced: true,
      agent_insights: "Research agent insights",
      confidence: 0.8
    })
  end

  defp extract_knowledge(topic, _state) do
    # Extract knowledge about a topic
    %{
      topic: topic,
      knowledge: "Extracted knowledge about #{topic}",
      confidence: 0.7
    }
  end

  defp send_response(from, message) do
    if is_pid(from) do
      send(from, message)
    end
  end
end
