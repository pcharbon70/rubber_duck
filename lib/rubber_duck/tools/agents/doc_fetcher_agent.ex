defmodule RubberDuck.Tools.Agents.DocFetcherAgent do
  @moduledoc """
  Agent that orchestrates the DocFetcher tool for intelligent documentation retrieval workflows.
  
  This agent manages documentation fetching requests, maintains a documentation cache,
  provides smart search suggestions, and handles batch documentation operations.
  
  ## Signals
  
  ### Input Signals
  - `fetch_documentation` - Fetch documentation for a specific query
  - `batch_fetch` - Fetch documentation for multiple queries
  - `search_documentation` - Search for documentation matching criteria
  - `update_cache` - Update or invalidate documentation cache
  - `generate_doc_index` - Generate searchable index of documentation
  - `fetch_related_docs` - Fetch related documentation based on context
  
  ### Output Signals
  - `documentation_fetched` - Documentation successfully retrieved
  - `batch_fetch_completed` - Batch documentation fetch completed
  - `documentation_indexed` - Documentation index generated
  - `related_docs_found` - Related documentation discovered
  - `cache_updated` - Documentation cache updated
  - `fetch_error` - Error during documentation fetch
  """
  
  use Jido.Agent,
    name: "doc_fetcher_agent",
    description: "Manages intelligent documentation retrieval and caching workflows",
    category: "documentation",
    tags: ["documentation", "reference", "learning", "api", "knowledge_base"],
    schema: [
      # Documentation cache
      doc_cache: [type: :map, default: %{}],
      cache_ttl: [type: :integer, default: 3600_000], # 1 hour
      max_cache_size: [type: :integer, default: 100],
      
      # Fetch history
      fetch_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50],
      
      # Documentation sources
      enabled_sources: [type: {:list, :string}, default: ["hexdocs", "elixir", "erlang", "github"]],
      source_preferences: [type: :map, default: %{
        "hexdocs" => %{priority: 1, base_url: "https://hexdocs.pm"},
        "elixir" => %{priority: 2, base_url: "https://hexdocs.pm/elixir"},
        "erlang" => %{priority: 3, base_url: "https://www.erlang.org/doc"},
        "github" => %{priority: 4, base_url: "https://github.com"}
      }],
      
      # Search index
      doc_index: [type: :map, default: %{
        modules: %{},
        functions: %{},
        types: %{},
        guides: %{},
        last_updated: nil
      }],
      
      # Batch operations
      active_batches: [type: :map, default: %{}],
      
      # Related documentation tracking
      related_docs: [type: :map, default: %{}],
      max_related: [type: :integer, default: 10],
      
      # Statistics
      fetch_stats: [type: :map, default: %{
        total_fetches: 0,
        cache_hits: 0,
        cache_misses: 0,
        failed_fetches: 0,
        average_fetch_time: 0.0,
        popular_queries: %{}
      }],
      
      # Search preferences
      search_config: [type: :map, default: %{
        fuzzy_matching: true,
        include_deprecated: false,
        max_results: 20,
        relevance_threshold: 0.6
      }],
      
      # Documentation patterns
      doc_patterns: [type: :map, default: %{
        "stdlib" => ["Enum", "Map", "List", "String", "Process", "GenServer"],
        "common_packages" => ["Phoenix", "Ecto", "Plug", "Absinthe", "LiveView"],
        "testing" => ["ExUnit", "Mox", "StreamData", "Wallaby"]
      }]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  def additional_actions do
    [
      __MODULE__.ExecuteToolAction,
      __MODULE__.BatchFetchAction,
      __MODULE__.SearchDocumentationAction,
      __MODULE__.FetchRelatedDocsAction,
      __MODULE__.GenerateDocIndexAction,
      __MODULE__.UpdateCacheAction
    ]
  end
  
  # Action modules
  
  defmodule ExecuteToolAction do
    @moduledoc false
    use Jido.Action,
      name: "execute_tool",
      description: "Execute the DocFetcher tool with specified parameters",
      schema: [
        params: [type: :map, required: true, doc: "Parameters for the DocFetcher tool"]
      ]
    
    @impl true
    def run(action_params, context) do
      agent = context.agent
      params = action_params.params
      
      # Check cache first
      cache_key = generate_cache_key(params)
      case get_from_cache(agent, cache_key) do
        {:ok, cached_doc} ->
          {:ok, Map.put(cached_doc, :from_cache, true)}
        
        :miss ->
          # Execute the DocFetcher tool
          case RubberDuck.Tools.DocFetcher.execute(params, %{}) do
            {:ok, result} -> 
              # Cache the result
              cache_result(agent, cache_key, result)
              {:ok, result}
            {:error, reason} -> 
              {:error, reason}
          end
      end
    end
    
    defp generate_cache_key(params) do
      "#{params.query}:#{params.source}:#{params.doc_type}:#{params.version}"
    end
    
    defp get_from_cache(agent, key) do
      case Map.get(agent.state.doc_cache, key) do
        nil -> :miss
        cached ->
          if DateTime.diff(DateTime.utc_now(), cached.cached_at, :millisecond) < agent.state.cache_ttl do
            {:ok, cached.data}
          else
            :miss
          end
      end
    end
    
    defp cache_result(_agent, _key, result) do
      # Would update agent state in real implementation
      Logger.info("Caching documentation result")
      result
    end
  end
  
  defmodule BatchFetchAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_fetch",
      description: "Fetch documentation for multiple queries in batch",
      schema: [
        queries: [type: {:list, :map}, required: true, doc: "List of documentation queries"],
        strategy: [type: :atom, values: [:parallel, :sequential], default: :parallel],
        max_concurrency: [type: :integer, default: 5],
        continue_on_error: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      batch_id = generate_batch_id()
      
      # Start batch operation
      batch_info = %{
        id: batch_id,
        queries: params.queries,
        strategy: params.strategy,
        status: :in_progress,
        started_at: DateTime.utc_now()
      }
      
      results = case params.strategy do
        :parallel -> execute_parallel_fetch(batch_info, params, agent)
        :sequential -> execute_sequential_fetch(batch_info, params, agent)
      end
      
      {:ok, %{
        batch_id: batch_id,
        total_queries: length(params.queries),
        successful: length(Enum.filter(results, &match?({:ok, _}, &1))),
        failed: length(Enum.filter(results, &match?({:error, _}, &1))),
        results: results,
        execution_time: DateTime.diff(DateTime.utc_now(), batch_info.started_at, :millisecond)
      }}
    end
    
    defp generate_batch_id do
      "batch_#{System.unique_integer([:positive, :monotonic])}"
    end
    
    defp execute_parallel_fetch(batch_info, params, agent) do
      batch_info.queries
      |> Task.async_stream(fn query -> fetch_single_doc(query, agent) end,
                          timeout: 30_000,
                          max_concurrency: params.max_concurrency)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, "Task exited: #{inspect(reason)}"}
      end)
    end
    
    defp execute_sequential_fetch(batch_info, params, agent) do
      Enum.map(batch_info.queries, fn query ->
        case fetch_single_doc(query, agent) do
          {:ok, result} -> {:ok, result}
          {:error, reason} ->
            if params.continue_on_error do
              {:error, reason}
            else
              throw {:batch_error, reason}
            end
        end
      end)
    end
    
    defp fetch_single_doc(query_map, _agent) do
      params = Map.merge(%{
        source: "auto",
        doc_type: "module",
        version: "latest",
        include_examples: true,
        include_related: false,
        format: "markdown"
      }, query_map)
      
      RubberDuck.Tools.DocFetcher.execute(params, %{})
    end
  end
  
  defmodule SearchDocumentationAction do
    @moduledoc false
    use Jido.Action,
      name: "search_documentation",
      description: "Search for documentation matching criteria",
      schema: [
        search_query: [type: :string, required: true],
        search_in: [type: {:list, :atom}, default: [:modules, :functions, :types, :guides]],
        sources: [type: {:list, :string}, default: ["hexdocs", "elixir"]],
        filters: [type: :map, default: %{}],
        max_results: [type: :integer, default: 20]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Search in documentation index
      search_results = search_doc_index(agent.state.doc_index, params)
      
      # Apply filters
      filtered_results = apply_search_filters(search_results, params.filters)
      
      # Rank by relevance
      ranked_results = rank_search_results(filtered_results, params.search_query)
      
      # Limit results
      final_results = Enum.take(ranked_results, params.max_results)
      
      {:ok, %{
        query: params.search_query,
        total_matches: length(filtered_results),
        returned_results: length(final_results),
        results: final_results,
        search_metadata: %{
          searched_in: params.search_in,
          sources: params.sources,
          filters_applied: params.filters
        }
      }}
    end
    
    defp search_doc_index(doc_index, params) do
      results = []
      
      # Search modules
      results = if :modules in params.search_in do
        module_matches = search_in_category(doc_index.modules, params.search_query)
        |> Enum.map(fn match -> Map.put(match, :category, :module) end)
        results ++ module_matches
      else
        results
      end
      
      # Search functions
      results = if :functions in params.search_in do
        function_matches = search_in_category(doc_index.functions, params.search_query)
        |> Enum.map(fn match -> Map.put(match, :category, :function) end)
        results ++ function_matches
      else
        results
      end
      
      # Search types
      results = if :types in params.search_in do
        type_matches = search_in_category(doc_index.types, params.search_query)
        |> Enum.map(fn match -> Map.put(match, :category, :type) end)
        results ++ type_matches
      else
        results
      end
      
      # Search guides
      results = if :guides in params.search_in do
        guide_matches = search_in_category(doc_index.guides, params.search_query)
        |> Enum.map(fn match -> Map.put(match, :category, :guide) end)
        results ++ guide_matches
      else
        results
      end
      
      results
    end
    
    defp search_in_category(category_index, query) do
      # Simple search implementation
      query_lower = String.downcase(query)
      
      category_index
      |> Enum.filter(fn {name, _data} ->
        String.contains?(String.downcase(to_string(name)), query_lower)
      end)
      |> Enum.map(fn {name, data} ->
        %{
          name: name,
          data: data,
          relevance: calculate_relevance(name, query)
        }
      end)
    end
    
    defp calculate_relevance(name, query) do
      name_str = String.downcase(to_string(name))
      query_lower = String.downcase(query)
      
      cond do
        name_str == query_lower -> 1.0
        String.starts_with?(name_str, query_lower) -> 0.8
        String.contains?(name_str, query_lower) -> 0.6
        true -> 0.3
      end
    end
    
    defp apply_search_filters(results, filters) do
      results
      |> filter_by_source(filters[:source])
      |> filter_by_version(filters[:version])
      |> filter_by_package(filters[:package])
    end
    
    defp filter_by_source(results, nil), do: results
    defp filter_by_source(results, source) do
      Enum.filter(results, fn result ->
        get_in(result, [:data, :source]) == source
      end)
    end
    
    defp filter_by_version(results, nil), do: results
    defp filter_by_version(results, version) do
      Enum.filter(results, fn result ->
        get_in(result, [:data, :version]) == version
      end)
    end
    
    defp filter_by_package(results, nil), do: results
    defp filter_by_package(results, package) do
      Enum.filter(results, fn result ->
        get_in(result, [:data, :package]) == package
      end)
    end
    
    defp rank_search_results(results, _query) do
      Enum.sort_by(results, fn result -> -result.relevance end)
    end
  end
  
  defmodule FetchRelatedDocsAction do
    @moduledoc false
    use Jido.Action,
      name: "fetch_related_docs",
      description: "Fetch documentation related to a given context",
      schema: [
        base_query: [type: :string, required: true],
        relation_types: [type: {:list, :atom}, default: [:functions, :types, :behaviours, :modules]],
        max_depth: [type: :integer, default: 2],
        max_related: [type: :integer, default: 10]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # First fetch the base documentation
      base_params = %{
        query: params.base_query,
        source: "auto",
        doc_type: "module",
        include_related: true
      }
      
      case RubberDuck.Tools.DocFetcher.execute(base_params, %{}) do
        {:ok, base_doc} ->
          # Extract related items from base doc
          related_items = extract_related_items(base_doc, params.relation_types)
          
          # Fetch documentation for related items
          related_docs = fetch_related_documentation(related_items, params, agent)
          
          # Build relationship graph
          relationship_graph = build_relationship_graph(base_doc, related_docs)
          
          {:ok, %{
            base_query: params.base_query,
            base_documentation: base_doc,
            related_count: length(related_docs),
            related_documentation: Enum.take(related_docs, params.max_related),
            relationship_graph: relationship_graph,
            relation_types: params.relation_types
          }}
        
        {:error, reason} ->
          {:error, "Failed to fetch base documentation: #{reason}"}
      end
    end
    
    defp extract_related_items(doc, relation_types) do
      _metadata = doc.metadata || %{}
      related = []
      
      # Extract from documentation content
      related = if :functions in relation_types do
        functions = extract_function_references(doc.documentation)
        related ++ Enum.map(functions, fn func -> %{type: :function, query: func} end)
      else
        related
      end
      
      related = if :types in relation_types do
        types = extract_type_references(doc.documentation)
        related ++ Enum.map(types, fn type -> %{type: :type, query: type} end)
      else
        related
      end
      
      related = if :modules in relation_types do
        modules = extract_module_references(doc.documentation)
        related ++ Enum.map(modules, fn mod -> %{type: :module, query: mod} end)
      else
        related
      end
      
      Enum.uniq_by(related, & &1.query)
    end
    
    defp extract_function_references(content) do
      # Extract function references like Module.function/arity
      Regex.scan(~r/([A-Z][\w.]*\.\w+\/\d+)/, content)
      |> Enum.map(fn [_, match] -> match end)
      |> Enum.uniq()
    end
    
    defp extract_type_references(content) do
      # Extract type references like t:Module.type/0
      Regex.scan(~r/t:([A-Z][\w.]*\.\w+\/\d+)/, content)
      |> Enum.map(fn [_, match] -> "t:#{match}" end)
      |> Enum.uniq()
    end
    
    defp extract_module_references(content) do
      # Extract module references
      Regex.scan(~r/\b([A-Z][\w.]*)\b/, content)
      |> Enum.map(fn [_, match] -> match end)
      |> Enum.filter(fn name -> String.contains?(name, ".") or known_module?(name) end)
      |> Enum.uniq()
    end
    
    defp known_module?(name) do
      # Check if it's a known Elixir/Erlang module
      name in ["GenServer", "Supervisor", "Task", "Agent", "Phoenix", "Ecto", "Plug"]
    end
    
    defp fetch_related_documentation(items, params, _agent) do
      items
      |> Enum.take(params.max_related * 2) # Fetch extra in case some fail
      |> Enum.map(fn item ->
        doc_params = %{
          query: item.query,
          doc_type: to_string(item.type),
          include_examples: false,
          include_related: false
        }
        
        case RubberDuck.Tools.DocFetcher.execute(doc_params, %{}) do
          {:ok, doc} -> 
            %{
              query: item.query,
              type: item.type,
              documentation: doc,
              success: true
            }
          {:error, _} -> 
            %{
              query: item.query,
              type: item.type,
              documentation: nil,
              success: false
            }
        end
      end)
      |> Enum.filter(& &1.success)
    end
    
    defp build_relationship_graph(base_doc, related_docs) do
      nodes = [
        %{id: base_doc.query, type: :base, label: base_doc.query}
      ]
      
      nodes = nodes ++ Enum.map(related_docs, fn doc ->
        %{id: doc.query, type: doc.type, label: doc.query}
      end)
      
      edges = Enum.map(related_docs, fn doc ->
        %{from: base_doc.query, to: doc.query, relationship: doc.type}
      end)
      
      %{
        nodes: nodes,
        edges: edges,
        node_count: length(nodes),
        edge_count: length(edges)
      }
    end
  end
  
  defmodule GenerateDocIndexAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_doc_index",
      description: "Generate a searchable index of documentation",
      schema: [
        packages: [type: {:list, :string}, required: true],
        include_stdlib: [type: :boolean, default: true],
        include_deps: [type: :boolean, default: false],
        index_depth: [type: :atom, values: [:shallow, :deep], default: :shallow]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Build documentation index
      index = %{
        modules: %{},
        functions: %{},
        types: %{},
        guides: %{},
        packages: %{}
      }
      
      # Index stdlib if requested
      index = if params.include_stdlib do
        index_stdlib_docs(index)
      else
        index
      end
      
      # Index specified packages
      index = Enum.reduce(params.packages, index, fn package, acc ->
        index_package_docs(acc, package, params.index_depth)
      end)
      
      # Generate search metadata
      metadata = %{
        total_modules: map_size(index.modules),
        total_functions: map_size(index.functions),
        total_types: map_size(index.types),
        total_guides: map_size(index.guides),
        indexed_packages: params.packages,
        index_generated_at: DateTime.utc_now()
      }
      
      {:ok, %{
        index: index,
        metadata: metadata,
        packages_indexed: length(params.packages),
        index_size: calculate_index_size(index)
      }}
    end
    
    defp index_stdlib_docs(index) do
      stdlib_modules = [
        "Enum", "Map", "List", "String", "Process", "GenServer",
        "Supervisor", "Task", "Agent", "Registry", "File", "Path"
      ]
      
      Enum.reduce(stdlib_modules, index, fn module_name, acc ->
        module_data = %{
          name: module_name,
          package: "elixir",
          description: "#{module_name} module from Elixir standard library",
          source: "elixir"
        }
        
        put_in(acc.modules[module_name], module_data)
      end)
    end
    
    defp index_package_docs(index, package, depth) do
      # Simulate indexing a package
      package_modules = generate_package_modules(package)
      
      index = Enum.reduce(package_modules, index, fn module_name, acc ->
        module_data = %{
          name: module_name,
          package: package,
          description: "#{module_name} from #{package}",
          source: "hexdocs"
        }
        
        acc = put_in(acc.modules[module_name], module_data)
        
        if depth == :deep do
          # Also index functions and types
          acc = index_module_functions(acc, module_name, package)
          index_module_types(acc, module_name, package)
        else
          acc
        end
      end)
      
      put_in(index.packages[package], %{
        indexed_at: DateTime.utc_now(),
        module_count: length(package_modules)
      })
    end
    
    defp generate_package_modules(package) do
      # Simulate package module structure
      case package do
        "phoenix" -> ["Phoenix", "Phoenix.Controller", "Phoenix.Router", "Phoenix.Channel"]
        "ecto" -> ["Ecto", "Ecto.Query", "Ecto.Schema", "Ecto.Changeset"]
        "plug" -> ["Plug", "Plug.Conn", "Plug.Router", "Plug.Builder"]
        _ -> ["#{Macro.camelize(package)}"]
      end
    end
    
    defp index_module_functions(index, module_name, package) do
      # Simulate function indexing
      functions = case module_name do
        "Enum" -> ["map/2", "filter/2", "reduce/3", "sort/1"]
        "Phoenix.Controller" -> ["render/3", "json/2", "redirect/2"]
        _ -> ["new/1", "get/2", "put/3"]
      end
      
      Enum.reduce(functions, index, fn func_sig, acc ->
        func_key = "#{module_name}.#{func_sig}"
        func_data = %{
          signature: func_sig,
          module: module_name,
          package: package,
          source: "hexdocs"
        }
        put_in(acc.functions[func_key], func_data)
      end)
    end
    
    defp index_module_types(index, module_name, package) do
      # Simulate type indexing
      types = case module_name do
        "Ecto.Changeset" -> ["t/0", "error/0", "action/0"]
        _ -> ["t/0"]
      end
      
      Enum.reduce(types, index, fn type_sig, acc ->
        type_key = "#{module_name}.#{type_sig}"
        type_data = %{
          signature: type_sig,
          module: module_name,
          package: package,
          source: "hexdocs"
        }
        put_in(acc.types[type_key], type_data)
      end)
    end
    
    defp calculate_index_size(index) do
      map_size(index.modules) + 
      map_size(index.functions) + 
      map_size(index.types) + 
      map_size(index.guides)
    end
  end
  
  defmodule UpdateCacheAction do
    @moduledoc false
    use Jido.Action,
      name: "update_cache",
      description: "Update or manage the documentation cache",
      schema: [
        operation: [type: :atom, values: [:clear, :evict, :refresh, :stats], required: true],
        target: [type: :string, required: false],
        force: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      result = case params.operation do
        :clear -> clear_cache(agent, params.force)
        :evict -> evict_cache_entry(agent, params.target)
        :refresh -> refresh_cache(agent, params.target)
        :stats -> get_cache_stats(agent)
      end
      
      {:ok, result}
    end
    
    defp clear_cache(agent, force) do
      if force or cache_size(agent) > agent.state.max_cache_size do
        %{
          operation: :clear,
          cleared_entries: map_size(agent.state.doc_cache),
          cache_size_before: cache_size(agent),
          cache_size_after: 0,
          message: "Cache cleared successfully"
        }
      else
        %{
          operation: :clear,
          skipped: true,
          message: "Cache clear skipped - use force: true to clear"
        }
      end
    end
    
    defp evict_cache_entry(agent, target) do
      if target && Map.has_key?(agent.state.doc_cache, target) do
        %{
          operation: :evict,
          evicted_key: target,
          success: true,
          message: "Cache entry evicted"
        }
      else
        %{
          operation: :evict,
          success: false,
          message: "Cache entry not found"
        }
      end
    end
    
    defp refresh_cache(agent, target) do
      entries_to_refresh = if target do
        agent.state.doc_cache
        |> Enum.filter(fn {key, _} -> String.contains?(key, target) end)
        |> Enum.map(fn {key, _} -> key end)
      else
        # Refresh oldest entries
        agent.state.doc_cache
        |> Enum.sort_by(fn {_, entry} -> entry.cached_at end)
        |> Enum.take(10)
        |> Enum.map(fn {key, _} -> key end)
      end
      
      %{
        operation: :refresh,
        refreshed_count: length(entries_to_refresh),
        refreshed_keys: entries_to_refresh,
        message: "Cache entries marked for refresh"
      }
    end
    
    defp get_cache_stats(agent) do
      cache = agent.state.doc_cache
      stats = agent.state.fetch_stats
      
      %{
        operation: :stats,
        cache_size: map_size(cache),
        max_cache_size: agent.state.max_cache_size,
        cache_hit_rate: if(stats.total_fetches > 0, do: stats.cache_hits / stats.total_fetches * 100, else: 0),
        total_fetches: stats.total_fetches,
        cache_hits: stats.cache_hits,
        cache_misses: stats.cache_misses,
        oldest_entry: find_oldest_cache_entry(cache),
        newest_entry: find_newest_cache_entry(cache)
      }
    end
    
    defp cache_size(agent) do
      map_size(agent.state.doc_cache)
    end
    
    defp find_oldest_cache_entry(cache) do
      case Enum.min_by(cache, fn {_, entry} -> entry.cached_at end, fn -> nil end) do
        {key, entry} -> %{key: key, cached_at: entry.cached_at}
        nil -> nil
      end
    end
    
    defp find_newest_cache_entry(cache) do
      case Enum.max_by(cache, fn {_, entry} -> entry.cached_at end, fn -> nil end) do
        {key, entry} -> %{key: key, cached_at: entry.cached_at}
        nil -> nil
      end
    end
  end
  
  # Signal handlers
  
  def handle_signal(agent, %{"type" => "fetch_documentation"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      query: data["query"],
      source: data["source"] || "auto",
      doc_type: data["doc_type"] || "module",
      version: data["version"] || "latest",
      include_examples: data["include_examples"] || true,
      include_related: data["include_related"] || false,
      format: data["format"] || "markdown"
    }
    
    # Execute the fetch
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, ExecuteToolAction, %{params: params})
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "batch_fetch"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, BatchFetchAction, %{
      queries: data["queries"],
      strategy: String.to_atom(data["strategy"] || "parallel"),
      max_concurrency: data["max_concurrency"] || 5,
      continue_on_error: data["continue_on_error"] || true
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "search_documentation"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, SearchDocumentationAction, %{
      search_query: data["search_query"],
      search_in: Enum.map(data["search_in"] || ["modules", "functions"], &String.to_atom/1),
      sources: data["sources"] || ["hexdocs", "elixir"],
      filters: data["filters"] || %{},
      max_results: data["max_results"] || 20
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "fetch_related_docs"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, FetchRelatedDocsAction, %{
      base_query: data["base_query"],
      relation_types: Enum.map(data["relation_types"] || ["functions", "types"], &String.to_atom/1),
      max_depth: data["max_depth"] || 2,
      max_related: data["max_related"] || 10
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "generate_doc_index"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, GenerateDocIndexAction, %{
      packages: data["packages"],
      include_stdlib: data["include_stdlib"] || true,
      include_deps: data["include_deps"] || false,
      index_depth: String.to_atom(data["index_depth"] || "shallow")
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "update_cache"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, UpdateCacheAction, %{
      operation: String.to_atom(data["operation"]),
      target: data["target"],
      force: data["force"] || false
    })
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, _metadata) do
    # Update fetch history
    fetch_record = %{
      query: result.query,
      source: result.source,
      doc_type: get_in(result, [:metadata, :type]),
      from_cache: Map.get(result, :from_cache, false),
      timestamp: DateTime.utc_now()
    }
    
    agent = update_in(agent.state.fetch_history, fn history ->
      new_history = [fetch_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update statistics
    agent = update_in(agent.state.fetch_stats, fn stats ->
      stats
      |> Map.update!(:total_fetches, &(&1 + 1))
      |> Map.update!(if(result[:from_cache], do: :cache_hits, else: :cache_misses), &(&1 + 1))
      |> update_in([:popular_queries, result.query], fn
        nil -> 1
        count -> count + 1
      end)
    end)
    
    # Cache the result if not from cache
    agent = if not Map.get(result, :from_cache, false) do
      cache_key = "#{result.query}:#{result.source}:#{get_in(result, [:metadata, :type])}:#{get_in(result, [:metadata, :version])}"
      update_in(agent.state.doc_cache, fn cache ->
        # Evict old entries if at capacity
        cache = if map_size(cache) >= agent.state.max_cache_size do
          evict_oldest_cache_entry(cache)
        else
          cache
        end
        
        Map.put(cache, cache_key, %{
          data: result,
          cached_at: DateTime.utc_now()
        })
      end)
    else
      agent
    end
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "documentation_fetched",
      source: "agent:#{agent.id}",
      data: %{
        query: result.query,
        source: result.source,
        from_cache: Map.get(result, :from_cache, false)
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, BatchFetchAction, {:ok, result}, _metadata) do
    # Update batch tracking
    agent = put_in(agent.state.active_batches[result.batch_id], %{
      status: :completed,
      result: result,
      completed_at: DateTime.utc_now()
    })
    
    # Update statistics
    agent = update_in(agent.state.fetch_stats.total_fetches, &(&1 + result.total_queries))
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "batch_fetch_completed",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, GenerateDocIndexAction, {:ok, result}, _metadata) do
    # Update doc index
    agent = put_in(agent.state.doc_index, Map.merge(result.index, %{
      last_updated: DateTime.utc_now()
    }))
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "documentation_indexed",
      source: "agent:#{agent.id}",
      data: result.metadata
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, FetchRelatedDocsAction, {:ok, result}, _metadata) do
    # Store related docs information
    agent = put_in(agent.state.related_docs[result.base_query], %{
      related_items: result.related_documentation,
      graph: result.relationship_graph,
      fetched_at: DateTime.utc_now()
    })
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "related_docs_found",
      source: "agent:#{agent.id}",
      data: %{
        base_query: result.base_query,
        related_count: result.related_count
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, UpdateCacheAction, {:ok, result}, _metadata) do
    # Handle cache update results
    agent = case result.operation do
      :clear ->
        if result[:cleared_entries] do
          put_in(agent.state.doc_cache, %{})
        else
          agent
        end
      :evict ->
        if result[:success] do
          update_in(agent.state.doc_cache, &Map.delete(&1, result[:evicted_key]))
        else
          agent
        end
      _ ->
        agent
    end
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "cache_updated",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, _, {:error, reason}, metadata) do
    # Update failure statistics
    agent = update_in(agent.state.fetch_stats.failed_fetches, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "fetch_error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:error, reason}
  end
  
  # Helper functions
  
  defp evict_oldest_cache_entry(cache) do
    if map_size(cache) == 0 do
      cache
    else
      {oldest_key, _} = Enum.min_by(cache, fn {_, entry} -> entry.cached_at end)
      Map.delete(cache, oldest_key)
    end
  end
end