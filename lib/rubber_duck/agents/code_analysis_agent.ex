defmodule RubberDuck.Agents.CodeAnalysisAgent do
  @moduledoc """
  Autonomous agent for code analysis operations.
  
  This agent performs comprehensive code analysis combining static analysis
  with LLM-enhanced insights. It handles both direct file analysis and
  conversational code analysis requests.
  
  ## Signals
  
  ### Input Signals
  - `code_analysis_request`: Analyze a specific file
  - `conversation_analysis_request`: Analyze code within conversation context
  - `get_analysis_metrics`: Request current analysis metrics
  
  ### Output Signals
  - `analysis_result`: Complete analysis results
  - `analysis_progress`: Progress updates during analysis
  - `enhancement_complete`: LLM enhancement completed
  - `analysis_metrics`: Current metrics data
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "code_analysis",
    description: "Performs comprehensive code analysis with static and LLM-enhanced insights",
    category: "analysis",
    schema: [
      analysis_queue: [type: {:list, :map}, default: []],
      active_analyses: [type: :map, default: %{}],
      analysis_cache: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        files_analyzed: 0,
        conversations_analyzed: 0,
        total_issues: 0,
        analysis_time_ms: 0,
        cache_hits: 0,
        llm_enhancements: 0
      }],
      analyzers: [type: {:list, :atom}, default: [:static, :security, :style]],
      llm_config: [type: :map, default: %{temperature: 0.3, max_tokens: 2000}],
      cache_ttl_ms: [type: :integer, default: 300_000] # 5 minutes
    ]
  
  require Logger
  
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain
  alias RubberDuck.LLM
  
  # Signal Handlers
  
    def handle_signal(agent, %{"type" => "code_analysis_request"} = signal) do
    %{
      "data" => %{
        "file_path" => file_path,
        "options" => options,
        "request_id" => request_id
      } = data
    } = signal
    
    # Check cache first
    cache_key = generate_cache_key(file_path, options)
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        Logger.info("Cache hit for analysis of #{file_path}")
        
        # Emit cached result
        signal = Jido.Signal.new!(%{
          type: "analysis.result",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            result: cached_result,
            from_cache: true,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
        # Update metrics
        update_metrics(agent, :cache_hit)
        
      :not_found ->
        # Add to queue and start analysis
        analysis_request = %{
          type: :file,
          file_path: file_path,
          options: Map.merge(%{
            "provider" => data["provider"],
            "model" => data["model"],
            "user_id" => data["user_id"]
          }, options || %{}),
          request_id: request_id,
          started_at: System.monotonic_time(:millisecond)
        }
        
        agent = add_to_queue(agent, analysis_request)
        
        # Start analysis asynchronously
        Task.start(fn ->
          analyze_file(analysis_request)
        end)
        
        # Emit progress signal
        signal = Jido.Signal.new!(%{
          type: "analysis.progress",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            status: "started",
            file_path: file_path,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "conversation_analysis_request"} = signal) do
    %{
      "data" => %{
        "query" => query,
        "code" => code,
        "context" => context,
        "request_id" => request_id
      } = data
    } = signal
    
    # Create analysis request
    analysis_request = %{
      type: :conversation,
      query: query,
      code: code,
      context: context,
      llm_params: %{
        "provider" => data["provider"],
        "model" => data["model"],
        "user_id" => data["user_id"]
      },
      request_id: request_id,
      started_at: System.monotonic_time(:millisecond)
    }
    
    agent = add_to_queue(agent, analysis_request)
    
    # Start conversational analysis asynchronously
    Task.start(fn ->
      analyze_conversation(analysis_request)
    end)
    
    # Emit progress signal
    signal = Jido.Signal.new!(%{
      type: "analysis.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: request_id,
        status: "started",
        analysis_type: detect_analysis_type(query),
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "get_analysis_metrics"} = _signal) do
    signal = Jido.Signal.new!(%{
      type: "analysis.metrics",
      source: "agent:#{agent.id}",
      data: %{
        metrics: agent.state.metrics,
        queue_length: length(agent.state.analysis_queue),
        active_analyses: map_size(agent.state.active_analyses),
        cache_size: map_size(agent.state.analysis_cache),
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Remove the analysis_complete handler since we can't send signals to ourselves
  # The completion logic is handled directly in the async tasks
  
  def handle_signal(agent, signal) do
    Logger.warning("CodeAnalysisAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end
  
  # Private Functions
  
  defp add_to_queue(agent, request) do
    update_in(agent.state.analysis_queue, &(&1 ++ [request]))
    |> put_in([:state, :active_analyses, request.request_id], request)
  end
  
  
  defp analyze_file(request) do
    try do
      # Read file content
      content = read_file_content(request.file_path)
      language = detect_language(request.file_path)
      
      # Run static analysis
      static_results = run_static_analysis(%{
        file_path: request.file_path,
        content: content,
        language: language,
        options: request.options
      })
      
      # Run CoT analysis if LLM params provided
      cot_result = if request.options["provider"] do
        run_cot_analysis(content, request)
      else
        nil
      end
      
      # Enhance with LLM if requested
      enhanced_results = if request.options["enhance_with_llm"] && request.options["provider"] do
        enhance_with_llm(static_results, request)
      else
        static_results
      end
      
      # Merge all results
      final_result = build_analysis_result(
        request.file_path,
        language,
        static_results,
        enhanced_results,
        cot_result
      )
      
      # Emit result
      signal = Jido.Signal.new!(%{
        type: "analysis.result",
        source: "agent:code_analysis",
        data: %{
          request_id: request.request_id,
          result: final_result,
          timestamp: DateTime.utc_now()
        }
      })
      # In async context, publish directly to signal bus
      Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
      
      # Analysis complete - metrics will be tracked by the agent
      
    rescue
      error ->
        Logger.error("Analysis failed: #{inspect(error)}")
        signal = Jido.Signal.new!(%{
          type: "analysis.result",
          source: "agent:code_analysis",
          data: %{
            request_id: request.request_id,
            error: Exception.message(error),
            timestamp: DateTime.utc_now()
          }
        })
        # In async context, publish directly to signal bus
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
    end
  end
  
  defp analyze_conversation(request) do
    try do
      # Build CoT context
      cot_context = %{
        provider: request.llm_params["provider"],
        model: request.llm_params["model"],
        user_id: request.llm_params["user_id"],
        code: request.code || extract_code_from_context(request.context),
        context: Map.merge(request.context || %{}, %{
          analysis_type: detect_analysis_type(request.query),
          conversation_type: :analysis
        }),
        llm_config: %{
          temperature: 0.3,
          max_tokens: 2000
        }
      }
      
      # Execute AnalysisChain
      case ConversationManager.execute_chain(AnalysisChain, request.query, cot_context) do
        {:ok, cot_session} ->
          # Extract and emit result
          result = extract_conversation_result(cot_session, request)
          
          signal = Jido.Signal.new!(%{
            type: "analysis.result",
            source: "agent:code_analysis",
            data: %{
              request_id: request.request_id,
              result: result,
              timestamp: DateTime.utc_now()
            }
          })
          # In async context, publish directly to signal bus
          Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
          
          # Analysis complete - metrics will be tracked by the agent
          
        {:error, reason} ->
          Logger.error("Conversation analysis failed: #{inspect(reason)}")
          signal = Jido.Signal.new!(%{
            type: "analysis.result",
            source: "agent:code_analysis",
            data: %{
              request_id: request.request_id,
              error: "Analysis failed: #{inspect(reason)}",
              timestamp: DateTime.utc_now()
            }
          })
          # In async context, publish directly to signal bus
          Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
      end
      
    rescue
      error ->
        Logger.error("Conversation analysis error: #{inspect(error)}")
        signal = Jido.Signal.new!(%{
          type: "analysis.result",
          source: "agent:code_analysis",
          data: %{
            request_id: request.request_id,
            error: Exception.message(error),
            timestamp: DateTime.utc_now()
          }
        })
        # In async context, publish directly to signal bus
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
    end
  end
  
  defp run_static_analysis(input) do
    # Port static analysis logic from Analysis engine
    case input.language do
      :elixir -> run_elixir_analysis(input)
      :javascript -> []
      :python -> []
      _ -> []
    end
  end
  
  defp run_elixir_analysis(input) do
    issues = []
    lines = String.split(input.content, "\n")
    
    # Check for unused variables
    issues = issues ++ find_unused_variables(input.content)
    
    # Check for missing documentation
    issues = issues ++ find_missing_documentation(input.content)
    
    # Check for code smells
    issues = issues ++ detect_code_smells(input.content, lines)
    
    issues
  end
  
  defp find_unused_variables(content) do
    ~r/_\w+\s*=/
    |> Regex.scan(content)
    |> Enum.map(fn [match] ->
      %{
        type: :warning,
        category: :unused_variable,
        message: "Unused variable: #{String.trim(match, " =")}",
        line: 1,
        column: 1
      }
    end)
  end
  
  defp find_missing_documentation(content) do
    if String.contains?(content, "def ") and not String.contains?(content, "@doc") do
      [%{
        type: :info,
        category: :documentation,
        message: "Public functions should have @doc documentation",
        line: 1,
        column: 1
      }]
    else
      []
    end
  end
  
  defp detect_code_smells(_content, lines) do
    issues = []
    
    # Check for deeply nested code
    max_nesting = calculate_max_nesting(lines)
    
    if max_nesting > 3 do
      issues ++ [%{
        type: :warning,
        category: :complexity,
        message: "Code has deep nesting (level #{max_nesting}). Consider refactoring.",
        line: 1,
        column: 1
      }]
    else
      issues
    end
  end
  
  defp calculate_max_nesting(lines) do
    lines
    |> Enum.map(&calculate_indentation/1)
    |> Enum.max(fn -> 0 end)
    |> div(2)
  end
  
  defp calculate_indentation(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end
  
  defp run_cot_analysis(_content, _request) do
    # This would integrate with CoT analysis chain
    # For now, return nil to indicate not implemented
    nil
  end
  
  defp enhance_with_llm(static_results, request) do
    # Group issues by category
    grouped = Enum.group_by(static_results, & &1.category)
    
    # Enhance each group
    Enum.flat_map(grouped, fn {category, issues} ->
      case enhance_issue_group(category, issues, request) do
        {:ok, enhanced} -> enhanced
        {:error, _} -> issues
      end
    end)
  end
  
  defp enhance_issue_group(category, issues, request) do
    prompt = build_enhancement_prompt(category, issues)
    
    opts = [
      provider: request.options["provider"],
      model: request.options["model"],
      messages: [
        %{"role" => "system", "content" => get_analysis_system_prompt()},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: 0.3,
      max_tokens: 1024,
      user_id: request.options["user_id"]
    ]
    
    case LLM.Service.completion(opts) do
      {:ok, response} ->
        enhanced = parse_llm_enhancement(response, issues)
        {:ok, enhanced}
      {:error, reason} ->
        Logger.debug("LLM enhancement failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp build_enhancement_prompt(category, issues) do
    issue_descriptions = Enum.map(issues, fn issue ->
      "Line #{issue.line}: #{issue.message}"
    end) |> Enum.join("\n")
    
    """
    Analyze the following #{category} issues:
    
    #{issue_descriptions}
    
    For each issue, provide:
    1. A brief explanation of why it's a problem
    2. A suggested fix
    3. The potential impact if not fixed
    
    Keep explanations concise and actionable.
    """
  end
  
  defp get_analysis_system_prompt do
    """
    You are a code analysis expert. Provide clear, actionable insights about code issues.
    Focus on practical solutions and real-world impact.
    Be concise but thorough in your explanations.
    """
  end
  
  defp parse_llm_enhancement(response, original_issues) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""
    insights = String.split(content, "\n\n")
    
    original_issues
    |> Enum.zip(insights)
    |> Enum.map(fn {issue, insight} ->
      Map.merge(issue, %{
        explanation: insight,
        enhanced: true
      })
    end)
  end
  
  defp build_analysis_result(file_path, language, static_results, enhanced_results, cot_result) do
    all_issues = enhanced_results || static_results
    
    result = %{
      file: file_path,
      language: language,
      issues: all_issues,
      metrics: calculate_metrics(all_issues),
      summary: generate_summary(all_issues)
    }
    
    # Add CoT insights if available
    if cot_result do
      Map.merge(result, %{
        patterns: cot_result.patterns,
        suggestions: cot_result.suggestions,
        priorities: cot_result.priorities
      })
    else
      result
    end
  end
  
  defp extract_conversation_result(cot_session, request) do
    # Extract key information from CoT session
    analysis_points = extract_analysis_points(cot_session.reasoning_steps)
    recommendations = extract_recommendations(cot_session.reasoning_steps)
    
    %{
      query: request.query,
      response: cot_session.final_answer,
      conversation_type: :analysis,
      analysis_points: analysis_points,
      recommendations: recommendations,
      processing_time: cot_session.duration_ms,
      metadata: %{
        provider: request.llm_params["provider"],
        model: request.llm_params["model"],
        analysis_type: detect_analysis_type(request.query)
      }
    }
  end
  
  defp extract_analysis_points(reasoning_steps) do
    reasoning_steps
    |> Enum.filter(fn step ->
      step.name in [:identify_patterns, :analyze_code, :evaluate_quality]
    end)
    |> Enum.flat_map(fn step ->
      parse_analysis_points(step.result)
    end)
  end
  
  defp extract_recommendations(reasoning_steps) do
    reasoning_steps
    |> Enum.find(fn step ->
      step.name == :suggest_improvements
    end)
    |> case do
      nil -> []
      step -> parse_recommendations(step.result)
    end
  end
  
  defp parse_analysis_points(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["•", "-", "*", "Issue:", "Finding:"]))
    |> Enum.map(&String.trim/1)
  end
  defp parse_analysis_points(_), do: []
  
  defp parse_recommendations(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["Recommend", "Suggest", "Consider", "Should"]))
    |> Enum.map(&String.trim/1)
  end
  defp parse_recommendations(_), do: []
  
  defp detect_analysis_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      String.contains?(query_lower, ["security", "vulnerability", "exploit"]) -> :security
      String.contains?(query_lower, ["performance", "optimize", "speed", "efficiency"]) -> :performance
      String.contains?(query_lower, ["architecture", "design", "structure"]) -> :architecture
      String.contains?(query_lower, ["review", "quality", "best practice"]) -> :code_review
      String.contains?(query_lower, ["complexity", "maintainability", "readability"]) -> :complexity
      true -> :general_analysis
    end
  end
  
  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".py" -> :python
      _ -> :unknown
    end
  end
  
  defp read_file_content(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end
  
  defp extract_code_from_context(context) do
    context[:code] || context[:current_code] || ""
  end
  
  defp calculate_metrics(issues) do
    %{
      total_issues: length(issues),
      by_type: Enum.frequencies_by(issues, & &1.type),
      by_category: Enum.frequencies_by(issues, & &1.category)
    }
  end
  
  defp generate_summary(issues) do
    total = length(issues)
    critical = Enum.count(issues, &(&1.type == :error))
    warnings = Enum.count(issues, &(&1.type == :warning))
    
    """
    Found #{total} issues: #{critical} errors, #{warnings} warnings.
    Main concerns: #{summarize_categories(issues)}.
    """
  end
  
  defp summarize_categories(issues) do
    issues
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.join(", ")
  end
  
  # Cache Management
  
  defp generate_cache_key(file_path, options) do
    options_hash = :crypto.hash(:sha256, :erlang.term_to_binary(options))
    |> Base.encode16(case: :lower)
    
    "#{file_path}:#{options_hash}"
  end
  
  defp get_cached_result(agent, cache_key) do
    case agent.state.analysis_cache[cache_key] do
      nil -> :not_found
      %{result: result, cached_at: cached_at} ->
        age = System.monotonic_time(:millisecond) - cached_at
        if age < agent.state.cache_ttl_ms do
          {:ok, result}
        else
          :not_found
        end
    end
  end
  
  
  # Metrics
  
  defp update_metrics(agent, :cache_hit) do
    update_in(agent.state.metrics.cache_hits, &(&1 + 1))
  end
  
end