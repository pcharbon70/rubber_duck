defmodule RubberDuck.Tools.Agents.CodeSummarizerAgent do
  @moduledoc """
  Agent that orchestrates the CodeSummarizer tool for intelligent code summarization workflows.
  
  This agent manages code summarization requests, handles batch summarization operations,
  generates architectural overviews, and maintains summary caching for efficiency.
  
  ## Signals
  
  ### Input Signals
  - `summarize_code` - Summarize individual code snippets or files
  - `summarize_project` - Generate project-wide summaries
  - `batch_summarize` - Summarize multiple code snippets in batch
  - `compare_summaries` - Compare summaries of different code versions
  - `update_summary_preferences` - Update summarization preferences
  - `generate_architecture_overview` - Create high-level architecture summary
  
  ### Output Signals
  - `code.summarized` - Code summary completed
  - `code.summary.batch.completed` - Batch summarization done
  - `code.architecture.overview.generated` - Architecture summary ready
  - `code.summary.comparison.completed` - Summary comparison done
  - `code.summary.error` - Summarization error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_summarizer,
    name: "code_summarizer_agent",
    description: "Manages intelligent code summarization and architectural overview workflows",
    category: "documentation",
    tags: ["documentation", "summary", "analysis", "understanding"],
    schema: [
      # User preferences
      default_summary_type: [type: :string, default: "comprehensive"],
      default_focus_level: [type: :string, default: "module"],
      default_target_audience: [type: :string, default: "developer"],
      include_examples_by_default: [type: :boolean, default: true],
      include_dependencies_by_default: [type: :boolean, default: true],
      include_complexity_by_default: [type: :boolean, default: false],
      default_max_length: [type: :integer, default: 200],
      
      # Summary templates
      summary_templates: [type: :map, default: %{
        "module" => "Module providing %{purpose} functionality",
        "function" => "Function that %{action} %{target}",
        "project" => "Project containing %{module_count} modules for %{main_purpose}"
      }],
      
      # Batch operations
      batch_summaries: [type: :map, default: %{}],
      
      # Architecture overview
      architecture_overviews: [type: :map, default: %{}],
      module_relationships: [type: :map, default: %{}],
      
      # Summary cache
      summary_cache: [type: :map, default: %{}],
      cache_ttl: [type: :integer, default: 3600], # 1 hour
      
      # Summary history
      summary_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Statistics
      summary_stats: [type: :map, default: %{
        total_summarized: 0,
        by_type: %{},
        by_focus_level: %{},
        by_audience: %{},
        average_code_size: 0,
        most_complex_modules: []
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "summarize_code"} = signal) do
    %{"data" => data} = signal
    
    # Check cache first
    cache_key = generate_cache_key(data["code"], data)
    
    case get_cached_summary(agent, cache_key) do
      {:ok, cached_summary} ->
        # Emit cached result immediately
        signal = Jido.Signal.new!(%{
          type: "code.summarized",
          source: "agent:#{agent.id}",
          data: %{
            request_id: data["request_id"] || generate_request_id(),
            summary: cached_summary.summary,
            from_cache: true,
            cache_hit_at: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        {:ok, agent}
        
      :not_found ->
        # Build tool parameters
        params = %{
          code: data["code"],
          summary_type: data["summary_type"] || agent.state.default_summary_type,
          focus_level: data["focus_level"] || agent.state.default_focus_level,
          include_examples: data["include_examples"] || agent.state.include_examples_by_default,
          include_dependencies: data["include_dependencies"] || agent.state.include_dependencies_by_default,
          include_complexity: data["include_complexity"] || agent.state.include_complexity_by_default,
          target_audience: data["target_audience"] || agent.state.default_target_audience,
          max_length: data["max_length"] || agent.state.default_max_length
        }
        
        # Create tool request
        tool_request = %{
          "type" => "tool_request",
          "data" => %{
            "params" => params,
            "request_id" => data["request_id"] || generate_request_id(),
            "metadata" => %{
              "cache_key" => cache_key,
              "file_path" => data["file_path"],
              "module_name" => data["module_name"],
              "user_id" => data["user_id"]
            }
          }
        }
        
        # Emit progress
        signal = Jido.Signal.new!(%{
          type: "code.summary.progress",
          source: "agent:#{agent.id}",
          data: %{
            request_id: tool_request["data"]["request_id"],
            status: "analyzing",
            summary_type: params.summary_type,
            focus_level: params.focus_level
          }
        })
        emit_signal(agent, signal)
        
        # Forward to base handler
        handle_signal(agent, tool_request)
    end
  end
  
  def handle_tool_signal(agent, %{"type" => "summarize_project"} = signal) do
    %{"data" => data} = signal
    project_path = data["project_path"] || File.cwd!()
    
    # Discover code files
    files = discover_project_files(project_path, data["include_tests"] || false)
    batch_id = data["batch_id"] || "project_#{System.unique_integer([:positive])}"
    
    # Initialize batch operation
    agent = put_in(agent.state.batch_summaries[batch_id], %{
      id: batch_id,
      project_path: project_path,
      total_files: length(files),
      completed: 0,
      summaries: %{},
      started_at: DateTime.utc_now(),
      generate_overview: data["generate_overview"] || true,
      summary_type: data["summary_type"] || "brief"
    })
    
    # Process each file
    agent = Enum.reduce(files, agent, fn file_path, acc ->
      case File.read(file_path) do
        {:ok, content} ->
          summarize_signal = %{
            "type" => "summarize_code",
            "data" => %{
              "code" => content,
              "summary_type" => data["summary_type"] || "brief",
              "focus_level" => "file",
              "target_audience" => data["target_audience"] || agent.state.default_target_audience,
              "batch_id" => batch_id,
              "file_path" => file_path,
              "request_id" => "#{batch_id}_#{Path.basename(file_path)}"
            }
          }
          
          case handle_tool_signal(acc, summarize_signal) do
            {:ok, updated_agent} -> updated_agent
            _ -> acc
          end
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.summary.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        project_path: project_path,
        total_files: length(files)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "batch_summarize"} = signal) do
    %{"data" => data} = signal
    batch_id = data["batch_id"] || "batch_#{System.unique_integer([:positive])}"
    codes = data["codes"] || []
    
    # Initialize batch
    agent = put_in(agent.state.batch_summaries[batch_id], %{
      id: batch_id,
      total: length(codes),
      completed: 0,
      summaries: %{},
      started_at: DateTime.utc_now()
    })
    
    # Process each code snippet
    agent = Enum.reduce(Enum.with_index(codes), agent, fn {code_item, index}, acc ->
      summarize_signal = %{
        "type" => "summarize_code",
        "data" => Map.merge(code_item, %{
          "batch_id" => batch_id,
          "request_id" => "#{batch_id}_item_#{index}",
          "summary_type" => data["summary_type"] || agent.state.default_summary_type
        })
      }
      
      case handle_tool_signal(acc, summarize_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.summary.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        total_items: length(codes)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "compare_summaries"} = signal) do
    %{"data" => data} = signal
    
    # Generate summaries for both versions
    old_summary_signal = %{
      "type" => "summarize_code",
      "data" => %{
        "code" => data["old_code"],
        "summary_type" => "technical",
        "focus_level" => data["focus_level"] || "all",
        "request_id" => "compare_old_#{data["request_id"]}"
      }
    }
    
    new_summary_signal = %{
      "type" => "summarize_code",
      "data" => %{
        "code" => data["new_code"],
        "summary_type" => "technical",
        "focus_level" => data["focus_level"] || "all",
        "request_id" => "compare_new_#{data["request_id"]}"
      }
    }
    
    # Process both summaries
    {:ok, agent} = handle_tool_signal(agent, old_summary_signal)
    {:ok, agent} = handle_tool_signal(agent, new_summary_signal)
    
    # Store comparison metadata
    agent = put_in(
      agent.state.active_requests[data["request_id"] || generate_request_id()],
      %{
        type: :comparison,
        old_request_id: "compare_old_#{data["request_id"]}",
        new_request_id: "compare_new_#{data["request_id"]}",
        comparison_type: data["comparison_type"] || "changes"
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_architecture_overview"} = signal) do
    %{"data" => data} = signal
    overview_id = data["overview_id"] || "arch_#{System.unique_integer([:positive])}"
    
    # Initialize architecture overview
    agent = put_in(agent.state.architecture_overviews[overview_id], %{
      id: overview_id,
      project_path: data["project_path"] || File.cwd!(),
      started_at: DateTime.utc_now(),
      modules_analyzed: 0,
      relationships: %{},
      layers: %{}
    })
    
    # Trigger project summarization with architecture focus
    project_signal = %{
      "type" => "summarize_project",
      "data" => %{
        "project_path" => data["project_path"],
        "summary_type" => "architectural",
        "focus_level" => "all",
        "include_dependencies" => true,
        "include_complexity" => true,
        "overview_id" => overview_id,
        "generate_overview" => true
      }
    }
    
    {:ok, agent} = handle_tool_signal(agent, project_signal)
    
    signal = Jido.Signal.new!(%{
      type: "code.architecture.analysis.started",
      source: "agent:#{agent.id}",
      data: %{
        overview_id: overview_id,
        project_path: data["project_path"]
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "update_summary_preferences"} = signal) do
    %{"data" => data} = signal
    
    # Update agent preferences
    agent = agent
    |> maybe_update_state(:default_summary_type, data["default_summary_type"])
    |> maybe_update_state(:default_focus_level, data["default_focus_level"])
    |> maybe_update_state(:default_target_audience, data["default_target_audience"])
    |> maybe_update_state(:include_examples_by_default, data["include_examples"])
    |> maybe_update_state(:include_dependencies_by_default, data["include_dependencies"])
    |> maybe_update_state(:include_complexity_by_default, data["include_complexity"])
    |> maybe_update_state(:default_max_length, data["default_max_length"])
    
    # Update templates if provided
    agent = if templates = data["summary_templates"] do
      update_in(agent.state.summary_templates, &Map.merge(&1, templates))
    else
      agent
    end
    
    signal = Jido.Signal.new!(%{
      type: "code.summary.preferences.updated",
      source: "agent:#{agent.id}",
      data: %{
        default_summary_type: agent.state.default_summary_type,
        default_focus_level: agent.state.default_focus_level,
        default_target_audience: agent.state.default_target_audience,
        default_max_length: agent.state.default_max_length
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle summary-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add summary metadata
    cache_key = request[:metadata][:cache_key]
    
    result
    |> Map.put(:summarized_at, DateTime.utc_now())
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
      # Cache the result
      agent = cache_summary(agent, data.result)
      
      # Check for special handling
      request_id = data.request_id
      
      cond do
        # Handle batch summary
        batch_id = data.result[:batch_id] ->
          agent = update_summary_batch(agent, batch_id, data.result)
          
        # Handle comparison results
        String.starts_with?(request_id, "compare_") ->
          agent = handle_comparison_result(agent, request_id, data.result)
          
        # Handle architecture overview
        overview_id = data.result[:overview_id] ->
          agent = update_architecture_overview(agent, overview_id, data.result)
          
        # Handle regular summary
        true ->
          # Add to history
          agent = add_to_summary_history(agent, data.result)
          
          # Update statistics
          agent = update_summary_stats(agent, data.result)
      end
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.summarized",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data.request_id,
          summary: data.result["summary"],
          summary_type: data.result["type"] || data.result[:summary_type],
          focus_level: data.result[:focus_level],
          analysis: data.result["analysis"],
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
    "summary_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_cache_key(code, params) do
    content = code <> inspect(Map.take(params, ["summary_type", "focus_level", "target_audience"]))
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
  
  defp get_cached_summary(agent, cache_key) do
    case agent.state.summary_cache[cache_key] do
      nil -> :not_found
      entry ->
        if DateTime.diff(DateTime.utc_now(), entry.cached_at) <= agent.state.cache_ttl do
          {:ok, entry}
        else
          :not_found
        end
    end
  end
  
  defp cache_summary(agent, result) do
    cache_key = result[:cache_key]
    
    if cache_key do
      entry = %{
        summary: result["summary"],
        analysis: result["analysis"],
        cached_at: DateTime.utc_now()
      }
      
      put_in(agent.state.summary_cache[cache_key], entry)
    else
      agent
    end
  end
  
  defp discover_project_files(project_path, include_tests) do
    patterns = if include_tests do
      ["**/*.ex", "**/*.exs"]
    else
      ["lib/**/*.ex", "lib/**/*.exs", "apps/*/lib/**/*.ex"]
    end
    
    Enum.flat_map(patterns, fn pattern ->
      project_path
      |> Path.join(pattern)
      |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.filter(&File.regular?/1)
  end
  
  defp update_summary_batch(agent, batch_id, result) do
    update_in(agent.state.batch_summaries[batch_id], fn batch ->
      if batch do
        completed = batch.completed + 1
        file_path = result[:file_path] || "item_#{completed}"
        
        updated_batch = batch
        |> Map.put(:completed, completed)
        |> Map.put_in([:summaries, file_path], %{
          summary: result["summary"],
          analysis: result["analysis"]
        })
        
        # Check if batch is complete
        if completed >= batch.total_files || batch.total do
          # Generate overview if requested
          if batch[:generate_overview] do
            generate_project_overview(agent, batch)
          end
          
          signal = Jido.Signal.new!(%{
            type: "code.summary.batch.completed",
            source: "agent:#{Process.self()}",
            data: %{
              batch_id: batch_id,
              project_path: batch[:project_path],
              total_files: batch.total_files || batch.total,
              summaries: updated_batch.summaries
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
  
  defp generate_project_overview(agent, batch) do
    # Analyze all summaries to create overview
    modules = batch.summaries
    |> Enum.map(fn {path, summary} ->
      %{
        path: path,
        summary: summary.summary,
        complexity: get_in(summary, ["analysis", "complexity"]) || 0
      }
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.project.overview.generated",
      source: "agent:#{agent.id}",
      data: %{
        project_path: batch.project_path,
        module_count: map_size(batch.summaries),
        total_complexity: Enum.sum(Enum.map(modules, & &1.complexity)),
        modules: modules
      }
    })
    emit_signal(agent, signal)
  end
  
  defp handle_comparison_result(agent, request_id, result) do
    # Check if we have both summaries for comparison
    [compare_type, original_id] = String.split(request_id, "_", parts: 3) |> Enum.take(2)
    comparison_key = original_id
    
    case agent.state.active_requests[comparison_key] do
      %{type: :comparison} = comparison ->
        other_key = if compare_type == "compare_old" do
          comparison.new_request_id
        else
          comparison.old_request_id
        end
        
        # Check if other summary is ready
        if other_result = get_in(agent.state, [:active_requests, other_key, :result]) do
          old_summary = if compare_type == "compare_old", do: result, else: other_result
          new_summary = if compare_type == "compare_new", do: result, else: other_result
          
          signal = Jido.Signal.new!(%{
            type: "code.summary.comparison.completed",
            source: "agent:#{agent.id}",
            data: %{
              request_id: comparison_key,
              old_summary: old_summary["summary"],
              new_summary: new_summary["summary"],
              changes: analyze_summary_changes(old_summary, new_summary),
              comparison_type: comparison.comparison_type
            }
          })
          emit_signal(agent, signal)
        end
      _ -> nil
    end
    
    agent
  end
  
  defp analyze_summary_changes(old_summary, new_summary) do
    old_analysis = old_summary["analysis"] || %{}
    new_analysis = new_summary["analysis"] || %{}
    
    %{
      complexity_change: (new_analysis["complexity"] || 0) - (old_analysis["complexity"] || 0),
      functions_added: length((new_analysis["functions"] || []) -- (old_analysis["functions"] || [])),
      functions_removed: length((old_analysis["functions"] || []) -- (new_analysis["functions"] || [])),
      summary_length_change: String.length(new_summary["summary"] || "") - String.length(old_summary["summary"] || "")
    }
  end
  
  defp update_architecture_overview(agent, overview_id, result) do
    update_in(agent.state.architecture_overviews[overview_id], fn overview ->
      if overview do
        modules_analyzed = overview.modules_analyzed + 1
        
        # Extract module relationships
        if deps = get_in(result, ["analysis", "dependencies"]) do
          overview = update_in(overview.relationships, fn rels ->
            Map.put(rels, result[:file_path] || "module_#{modules_analyzed}", deps)
          end)
        end
        
        # Categorize into layers
        layer = detect_architectural_layer(result)
        overview = update_in(overview.layers, fn layers ->
          Map.update(layers, layer, [result[:file_path]], &[result[:file_path] | &1])
        end)
        
        Map.put(overview, :modules_analyzed, modules_analyzed)
      else
        overview
      end
    end)
    
    # Check if we should generate final overview
    overview = agent.state.architecture_overviews[overview_id]
    if overview && seems_complete?(overview) do
      signal = Jido.Signal.new!(%{
        type: "code.architecture.overview.generated",
        source: "agent:#{agent.id}",
        data: %{
          overview_id: overview_id,
          project_path: overview.project_path,
          layers: overview.layers,
          relationships: overview.relationships,
          modules_analyzed: overview.modules_analyzed
        }
      })
      emit_signal(agent, signal)
    end
    
    agent
  end
  
  defp detect_architectural_layer(result) do
    patterns = result["analysis"]["patterns"] || []
    
    cond do
      "genserver" in patterns || "supervisor" in patterns -> :core
      "phoenix" in patterns || "controller" in patterns -> :web
      "ecto" in patterns || "schema" in patterns -> :data
      "test" in patterns -> :test
      true -> :business
    end
  end
  
  defp seems_complete?(overview) do
    # Simple heuristic - could be improved
    overview.modules_analyzed > 0 && 
    DateTime.diff(DateTime.utc_now(), overview.started_at) > 5
  end
  
  defp add_to_summary_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      summary: String.slice(result["summary"] || "", 0, 100) <> "...",
      summary_type: result["type"] || result[:summary_type],
      focus_level: result[:focus_level],
      target_audience: result[:target_audience],
      code_size: String.length(result["code"] || ""),
      complexity: get_in(result, ["analysis", "complexity"]) || 0,
      summarized_at: result[:summarized_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.summary_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.summary_history, new_history)
  end
  
  defp update_summary_stats(agent, result) do
    update_in(agent.state.summary_stats, fn stats ->
      summary_type = result["type"] || result[:summary_type] || "unknown"
      focus_level = result[:focus_level] || "unknown"
      audience = result[:target_audience] || "unknown"
      code_size = String.length(result["code"] || "")
      complexity = get_in(result, ["analysis", "complexity"]) || 0
      
      stats
      |> Map.update!(:total_summarized, &(&1 + 1))
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, summary_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:by_focus_level, fn by_level ->
        Map.update(by_level, focus_level, 1, &(&1 + 1))
      end)
      |> Map.update!(:by_audience, fn by_audience ->
        Map.update(by_audience, audience, 1, &(&1 + 1))
      end)
      |> Map.update!(:average_code_size, fn avg ->
        total = stats.total_summarized
        if total > 0 do
          ((avg * total) + code_size) / (total + 1)
        else
          code_size
        end
      end)
      |> update_most_complex_modules(result[:file_path], complexity)
    end)
  end
  
  defp update_most_complex_modules(stats, nil, _complexity), do: stats
  defp update_most_complex_modules(stats, file_path, complexity) do
    modules = [{file_path, complexity} | stats.most_complex_modules]
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(10)
    
    Map.put(stats, :most_complex_modules, modules)
  end
  
  defp maybe_update_state(agent, key, nil), do: agent
  defp maybe_update_state(agent, key, value) do
    put_in(agent.state[key], value)
  end
end