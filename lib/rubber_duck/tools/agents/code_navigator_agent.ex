defmodule RubberDuck.Tools.Agents.CodeNavigatorAgent do
  @moduledoc """
  Agent that orchestrates the CodeNavigator tool for intelligent code navigation workflows.
  
  This agent manages symbol navigation requests, maintains navigation history,
  handles batch symbol searches, and provides intelligent code exploration features.
  
  ## Signals
  
  ### Input Signals
  - `navigate_to_symbol` - Find and navigate to a specific symbol
  - `find_all_references` - Find all references to a symbol
  - `find_implementations` - Find all implementations of a protocol/behaviour
  - `navigate_call_hierarchy` - Trace call hierarchy for a function
  - `batch_navigate` - Navigate to multiple symbols
  - `explore_module` - Explore all symbols in a module
  - `save_navigation_bookmark` - Save current navigation point
  
  ### Output Signals
  - `code.navigation.completed` - Navigation results ready
  - `code.navigation.references.found` - References located
  - `code.navigation.implementations.found` - Implementations found
  - `code.navigation.hierarchy.traced` - Call hierarchy ready
  - `code.navigation.batch.completed` - Batch navigation done
  - `code.navigation.module.explored` - Module exploration complete
  - `code.navigation.bookmark.saved` - Bookmark saved
  - `code.navigation.error` - Navigation error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_navigator,
    name: "code_navigator_agent",
    description: "Manages intelligent code navigation and symbol exploration workflows",
    category: "navigation",
    tags: ["navigation", "search", :symbols, :exploration],
    schema: [
      # Navigation preferences
      default_search_type: [type: :string, default: "comprehensive"],
      default_scope: [type: :string, default: "project"],
      default_file_pattern: [type: :string, default: "**/*.{ex,exs}"],
      case_sensitive_by_default: [type: :boolean, default: true],
      include_tests_by_default: [type: :boolean, default: true],
      include_deps_by_default: [type: :boolean, default: false],
      default_max_results: [type: :integer, default: 100],
      default_context_lines: [type: :integer, default: 2],
      
      # Navigation history
      navigation_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50],
      current_position: [type: :map, default: nil],
      
      # Bookmarks
      navigation_bookmarks: [type: :map, default: %{}],
      
      # Symbol index (cache)
      symbol_index: [type: :map, default: %{}],
      index_ttl: [type: :integer, default: 300], # 5 minutes
      
      # Call hierarchy cache
      call_hierarchies: [type: :map, default: %{}],
      
      # Batch operations
      batch_navigations: [type: :map, default: %{}],
      
      # Module exploration results
      module_explorations: [type: :map, default: %{}],
      
      # Related symbols tracking
      related_symbols: [type: :map, default: %{}],
      
      # Statistics
      navigation_stats: [type: :map, default: %{
        total_navigations: 0,
        by_type: %{},
        by_symbol_type: %{},
        most_navigated: %{},
        average_results_per_search: 0
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "navigate_to_symbol"} = signal) do
    %{"data" => data} = signal
    
    # Check symbol index cache first
    symbol = data["symbol"]
    cache_key = generate_cache_key(symbol, data)
    
    case get_cached_results(agent, cache_key) do
      {:ok, cached} ->
        # Emit cached results immediately
        signal = Jido.Signal.new!(%{
          type: "code.navigation.completed",
          source: "agent:#{agent.id}",
          data: %{
            request_id: data["request_id"] || generate_request_id(),
            results: cached.results,
            from_cache: true,
            symbol: symbol
          }
        })
        emit_signal(agent, signal)
        
        # Update navigation position
        agent = update_navigation_position(agent, cached.primary_definition)
        {:ok, agent}
        
      :not_found ->
        # Build tool parameters
        params = %{
          symbol: symbol,
          search_type: data["search_type"] || agent.state.default_search_type,
          scope: data["scope"] || agent.state.default_scope,
          file_pattern: data["file_pattern"] || agent.state.default_file_pattern,
          case_sensitive: data["case_sensitive"] || agent.state.case_sensitive_by_default,
          include_tests: data["include_tests"] || agent.state.include_tests_by_default,
          include_deps: data["include_deps"] || agent.state.include_deps_by_default,
          max_results: data["max_results"] || agent.state.default_max_results,
          context_lines: data["context_lines"] || agent.state.default_context_lines
        }
        
        # Create tool request
        tool_request = %{
          "type" => "tool_request",
          "data" => %{
            "params" => params,
            "request_id" => data["request_id"] || generate_request_id(),
            "metadata" => %{
              "cache_key" => cache_key,
              "navigation_type" => "symbol",
              "from_position" => agent.state.current_position,
              "user_id" => data["user_id"]
            }
          }
        }
        
        # Emit progress
        signal = Jido.Signal.new!(%{
          type: "code.navigation.progress",
          source: "agent:#{agent.id}",
          data: %{
            request_id: tool_request["data"]["request_id"],
            status: "searching",
            symbol: symbol,
            search_type: params.search_type
          }
        })
        emit_signal(agent, signal)
        
        # Forward to base handler
        handle_signal(agent, tool_request)
    end
  end
  
  def handle_tool_signal(agent, %{"type" => "find_all_references"} = signal) do
    %{"data" => data} = signal
    
    # Force references search type
    reference_signal = %{
      "type" => "navigate_to_symbol",
      "data" => Map.merge(data, %{
        "search_type" => "references",
        "navigation_subtype" => "find_references"
      })
    }
    
    handle_tool_signal(agent, reference_signal)
  end
  
  def handle_tool_signal(agent, %{"type" => "find_implementations"} = signal) do
    %{"data" => data} = signal
    protocol_or_behaviour = data["symbol"]
    
    # Search for implementations
    impl_signal = %{
      "type" => "navigate_to_symbol",
      "data" => Map.merge(data, %{
        "symbol" => "#{protocol_or_behaviour}.*",  # Wildcard search
        "search_type" => "definitions",
        "navigation_subtype" => "find_implementations",
        "implementation_of" => protocol_or_behaviour
      })
    }
    
    handle_tool_signal(agent, impl_signal)
  end
  
  def handle_tool_signal(agent, %{"type" => "navigate_call_hierarchy"} = signal) do
    %{"data" => data} = signal
    function_symbol = data["symbol"]
    direction = data["direction"] || "both"  # callers, callees, or both
    
    # Initialize call hierarchy tracking
    hierarchy_id = data["hierarchy_id"] || "hierarchy_#{System.unique_integer([:positive])}"
    
    agent = put_in(agent.state.call_hierarchies[hierarchy_id], %{
      root_symbol: function_symbol,
      direction: direction,
      levels_explored: 0,
      max_depth: data["max_depth"] || 5,
      nodes: %{},
      edges: []
    })
    
    # Start with finding the root symbol
    root_signal = %{
      "type" => "navigate_to_symbol",
      "data" => %{
        "symbol" => function_symbol,
        "search_type" => "definitions",
        "hierarchy_id" => hierarchy_id,
        "hierarchy_level" => 0,
        "navigation_subtype" => "call_hierarchy"
      }
    }
    
    {:ok, agent} = handle_tool_signal(agent, root_signal)
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.hierarchy.started",
      source: "agent:#{agent.id}",
      data: %{
        hierarchy_id: hierarchy_id,
        root_symbol: function_symbol,
        direction: direction
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "batch_navigate"} = signal) do
    %{"data" => data} = signal
    symbols = data["symbols"] || []
    batch_id = data["batch_id"] || "batch_#{System.unique_integer([:positive])}"
    
    # Initialize batch operation
    agent = put_in(agent.state.batch_navigations[batch_id], %{
      id: batch_id,
      total_symbols: length(symbols),
      completed: 0,
      results: %{},
      started_at: DateTime.utc_now()
    })
    
    # Process each symbol
    agent = Enum.reduce(symbols, agent, fn symbol, acc ->
      nav_signal = %{
        "type" => "navigate_to_symbol",
        "data" => %{
          "symbol" => symbol,
          "search_type" => data["search_type"] || agent.state.default_search_type,
          "batch_id" => batch_id,
          "request_id" => "#{batch_id}_#{symbol}"
        }
      }
      
      case handle_tool_signal(acc, nav_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        total_symbols: length(symbols)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "explore_module"} = signal) do
    %{"data" => data} = signal
    module_name = data["module"]
    exploration_id = data["exploration_id"] || "explore_#{System.unique_integer([:positive])}"
    
    # Initialize module exploration
    agent = put_in(agent.state.module_explorations[exploration_id], %{
      id: exploration_id,
      module: module_name,
      symbols_found: %{},
      started_at: DateTime.utc_now()
    })
    
    # Search for all symbols in the module
    explore_signal = %{
      "type" => "navigate_to_symbol",
      "data" => %{
        "symbol" => "#{module_name}.*",
        "search_type" => "comprehensive",
        "scope" => "module",
        "exploration_id" => exploration_id,
        "navigation_subtype" => "module_exploration"
      }
    }
    
    {:ok, agent} = handle_tool_signal(agent, explore_signal)
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.exploration.started",
      source: "agent:#{agent.id}",
      data: %{
        exploration_id: exploration_id,
        module: module_name
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "save_navigation_bookmark"} = signal) do
    %{"data" => data} = signal
    bookmark_name = data["name"]
    
    bookmark = %{
      name: bookmark_name,
      position: agent.state.current_position || data["position"],
      description: data["description"],
      created_at: DateTime.utc_now(),
      tags: data["tags"] || []
    }
    
    agent = put_in(agent.state.navigation_bookmarks[bookmark_name], bookmark)
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.bookmark.saved",
      source: "agent:#{agent.id}",
      data: %{
        bookmark_name: bookmark_name,
        bookmark: bookmark
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle navigation-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add navigation metadata
    cache_key = request[:metadata][:cache_key]
    
    result
    |> Map.put(:navigated_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.put(:cache_key, cache_key)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %Jido.Signal{type: "tool.result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    data = signal.data
    
    if data.result && not data[:from_cache] do
      # Cache the results
      agent = cache_navigation_results(agent, data.result)
      
      # Update navigation position if primary definition found
      agent = if primary = get_in(data.result, ["navigation", "primary_definition"]) do
        update_navigation_position(agent, primary)
      else
        agent
      end
      
      # Check for special handling
      navigation_subtype = get_in(agent.state.active_requests, [data.request_id, :metadata, :navigation_subtype])
      
      agent = case navigation_subtype do
        "find_references" ->
          handle_references_result(agent, data.result)
          
        "find_implementations" ->
          handle_implementations_result(agent, data.result)
          
        "call_hierarchy" ->
          handle_call_hierarchy_result(agent, data.result)
          
        "module_exploration" ->
          handle_module_exploration_result(agent, data.result)
          
        _ ->
          # Handle regular navigation
          agent = add_to_navigation_history(agent, data.result)
          agent = update_navigation_stats(agent, data.result)
          agent = track_related_symbols(agent, data.result)
          agent
      end
      
      # Handle batch navigation
      if batch_id = data.result[:batch_id] do
        agent = update_navigation_batch(agent, batch_id, data.result)
      end
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.navigation.completed",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data.request_id,
          results: data.result["results"],
          summary: data.result["summary"],
          navigation: data.result["navigation"],
          metadata: data.result["metadata"]
        }
      })
      emit_signal(agent, signal)
    end
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    # Delegate to parent for standard handling
    super(agent, signal)
  end
  
  # Private helpers
  
  defp generate_request_id do
    "nav_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_cache_key(symbol, params) do
    content = symbol <> inspect(Map.take(params, ["search_type", "scope", "file_pattern"]))
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
  
  defp get_cached_results(agent, cache_key) do
    case agent.state.symbol_index[cache_key] do
      nil -> :not_found
      entry ->
        if DateTime.diff(DateTime.utc_now(), entry.cached_at) <= agent.state.index_ttl do
          {:ok, entry}
        else
          :not_found
        end
    end
  end
  
  defp cache_navigation_results(agent, result) do
    cache_key = result[:cache_key]
    
    if cache_key && get_in(result, ["summary", "total_matches"]) > 0 do
      entry = %{
        results: result["results"],
        primary_definition: get_in(result, ["navigation", "primary_definition"]),
        cached_at: DateTime.utc_now()
      }
      
      put_in(agent.state.symbol_index[cache_key], entry)
    else
      agent
    end
  end
  
  defp update_navigation_position(agent, nil), do: agent
  defp update_navigation_position(agent, position) do
    put_in(agent.state.current_position, %{
      file: position["file"],
      line: position["line"],
      column: position["column"],
      symbol: position["symbol"],
      updated_at: DateTime.utc_now()
    })
  end
  
  defp handle_references_result(agent, result) do
    references = result["results"] || []
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.references.found",
      source: "agent:#{agent.id}",
      data: %{
        symbol: result[:symbol],
        references: references,
        total_count: length(references),
        by_file: group_results_by_file(references)
      }
    })
    emit_signal(agent, signal)
    
    agent
  end
  
  defp handle_implementations_result(agent, result) do
    implementation_of = get_in(agent.state.active_requests, [result[:request_id], :metadata, :implementation_of])
    implementations = result["results"] || []
    
    # Filter to actual implementations
    filtered = Enum.filter(implementations, fn result ->
      String.contains?(result["match_type"] || "", "definition") &&
      (String.contains?(result["context"] || "", "defimpl") ||
       String.contains?(result["context"] || "", "@behaviour"))
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.navigation.implementations.found",
      source: "agent:#{agent.id}",
      data: %{
        protocol_or_behaviour: implementation_of,
        implementations: filtered,
        total_count: length(filtered)
      }
    })
    emit_signal(agent, signal)
    
    agent
  end
  
  defp handle_call_hierarchy_result(agent, result) do
    hierarchy_id = get_in(agent.state.active_requests, [result[:request_id], :metadata, :hierarchy_id])
    
    if hierarchy_id && agent.state.call_hierarchies[hierarchy_id] do
      agent = update_in(agent.state.call_hierarchies[hierarchy_id], fn hierarchy ->
        level = get_in(agent.state.active_requests, [result[:request_id], :metadata, :hierarchy_level]) || 0
        
        # Add node to hierarchy
        hierarchy = if primary = get_in(result, ["navigation", "primary_definition"]) do
          put_in(hierarchy, [:nodes, primary["symbol"]], %{
            definition: primary,
            level: level
          })
        else
          hierarchy
        end
        
        # Continue exploring if not at max depth
        if level < hierarchy.max_depth do
          explore_next_level(agent, hierarchy, result["results"] || [], level + 1)
        else
          # Hierarchy complete
          signal = Jido.Signal.new!(%{
            type: "code.navigation.hierarchy.traced",
            source: "agent:#{Process.self()}",
            data: %{
              hierarchy_id: hierarchy_id,
              root_symbol: hierarchy.root_symbol,
              nodes: hierarchy.nodes,
              edges: hierarchy.edges,
              levels_explored: level
            }
          })
          emit_signal(nil, signal)
        end
        
        Map.put(hierarchy, :levels_explored, max(hierarchy.levels_explored, level))
      end)
    else
      agent
    end
  end
  
  defp explore_next_level(agent, hierarchy, results, next_level) do
    # Find function calls in the results
    Enum.each(results, fn result ->
      if result["match_type"] == "call" do
        # Queue navigation to this symbol
        Task.start(fn ->
          signal = %{
            "type" => "navigate_to_symbol",
            "data" => %{
              "symbol" => extract_called_function(result),
              "search_type" => "definitions",
              "hierarchy_id" => hierarchy.id,
              "hierarchy_level" => next_level,
              "navigation_subtype" => "call_hierarchy"
            }
          }
          
          GenServer.cast(agent.pid, {:signal, signal})
        end)
      end
    end)
    
    hierarchy
  end
  
  defp extract_called_function(result) do
    # Extract function name from call context
    context = result["context"] || ""
    case Regex.run(~r/(\w+\.\w+|\w+)\(/, context) do
      [_, function_name] -> function_name
      _ -> nil
    end
  end
  
  defp handle_module_exploration_result(agent, result) do
    exploration_id = get_in(agent.state.active_requests, [result[:request_id], :metadata, :exploration_id])
    
    if exploration_id && agent.state.module_explorations[exploration_id] do
      agent = update_in(agent.state.module_explorations[exploration_id], fn exploration ->
        # Categorize symbols
        symbols = categorize_module_symbols(result["results"] || [])
        
        exploration
        |> Map.put(:symbols_found, symbols)
        |> Map.put(:completed_at, DateTime.utc_now())
      end)
      
      exploration = agent.state.module_explorations[exploration_id]
      
      signal = Jido.Signal.new!(%{
        type: "code.navigation.module.explored",
        source: "agent:#{agent.id}",
        data: %{
          exploration_id: exploration_id,
          module: exploration.module,
          symbols: exploration.symbols_found,
          summary: %{
            total_symbols: count_all_symbols(exploration.symbols_found),
            public_functions: length(exploration.symbols_found[:public_functions] || []),
            private_functions: length(exploration.symbols_found[:private_functions] || []),
            macros: length(exploration.symbols_found[:macros] || []),
            types: length(exploration.symbols_found[:types] || [])
          }
        }
      })
      emit_signal(agent, signal)
    end
    
    agent
  end
  
  defp categorize_module_symbols(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      category = determine_symbol_category(result)
      Map.update(acc, category, [result], &[result | &1])
    end)
  end
  
  defp determine_symbol_category(result) do
    context = result["context"] || ""
    
    cond do
      String.contains?(context, "defmacro") -> :macros
      String.contains?(context, "defp") -> :private_functions
      String.contains?(context, "def") -> :public_functions
      String.contains?(context, "@type") -> :types
      String.contains?(context, "@spec") -> :specs
      String.contains?(context, "@callback") -> :callbacks
      String.contains?(context, "defstruct") -> :structs
      true -> :other
    end
  end
  
  defp count_all_symbols(symbols_map) do
    symbols_map
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
  end
  
  defp group_results_by_file(results) do
    Enum.group_by(results, & &1["file"])
  end
  
  defp update_navigation_batch(agent, batch_id, result) do
    update_in(agent.state.batch_navigations[batch_id], fn batch ->
      if batch do
        completed = batch.completed + 1
        symbol = result[:symbol] || "symbol_#{completed}"
        
        updated_batch = batch
        |> Map.put(:completed, completed)
        |> Map.put_in([:results, symbol], result["results"])
        
        # Check if batch is complete
        if completed >= batch.total_symbols do
          signal = Jido.Signal.new!(%{
            type: "code.navigation.batch.completed",
            source: "agent:#{Process.self()}",
            data: %{
              batch_id: batch_id,
              total_symbols: batch.total_symbols,
              results: updated_batch.results
            }
          })
          emit_signal(nil, signal)
        end
        
        updated_batch
      else
        batch
      end
    end)
  end
  
  defp add_to_navigation_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      symbol: result[:symbol],
      search_type: get_in(result, ["metadata", "search_type"]),
      results_count: get_in(result, ["summary", "total_matches"]) || 0,
      primary_definition: get_in(result, ["navigation", "primary_definition"]),
      navigated_at: result[:navigated_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.navigation_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.navigation_history, new_history)
  end
  
  defp update_navigation_stats(agent, result) do
    update_in(agent.state.navigation_stats, fn stats ->
      search_type = get_in(result, ["metadata", "search_type"]) || "unknown"
      symbol = result[:symbol] || "unknown"
      results_count = get_in(result, ["summary", "total_matches"]) || 0
      
      # Determine symbol type from results
      symbol_type = if results = result["results"], do: detect_symbol_type(results), else: "unknown"
      
      stats
      |> Map.update!(:total_navigations, &(&1 + 1))
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, search_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:by_symbol_type, fn by_symbol ->
        Map.update(by_symbol, symbol_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:most_navigated, fn most ->
        Map.update(most, symbol, 1, &(&1 + 1))
      end)
      |> Map.update!(:average_results_per_search, fn avg ->
        total = stats.total_navigations
        if total > 0 do
          ((avg * total) + results_count) / (total + 1)
        else
          results_count
        end
      end)
    end)
  end
  
  defp detect_symbol_type(results) do
    # Analyze first result to determine symbol type
    case List.first(results) do
      %{"context" => context} ->
        cond do
          String.contains?(context, "defmodule") -> "module"
          String.contains?(context, "def ") -> "function"
          String.contains?(context, "defmacro") -> "macro"
          String.contains?(context, "@") -> "attribute"
          true -> "variable"
        end
      _ -> "unknown"
    end
  end
  
  defp track_related_symbols(agent, result) do
    if related = get_in(result, ["navigation", "related_symbols"]) do
      symbol = result[:symbol]
      
      update_in(agent.state.related_symbols, fn symbols ->
        Map.put(symbols, symbol, related)
      end)
    else
      agent
    end
  end
end