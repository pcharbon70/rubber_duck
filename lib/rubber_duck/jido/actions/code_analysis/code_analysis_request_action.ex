defmodule RubberDuck.Jido.Actions.CodeAnalysis.CodeAnalysisRequestAction do
  @moduledoc """
  Action for handling code analysis requests on specific files.
  
  This action processes file analysis requests by:
  - Checking cache for existing results
  - Performing static analysis (if not cached)
  - Running CoT analysis if LLM parameters provided
  - Enhancing results with LLM if requested
  - Emitting the final analysis result
  """
  
  use Jido.Action,
    name: "code_analysis_request",
    description: "Handles code analysis requests with caching and optional LLM enhancement",
    schema: [
      file_path: [
        type: :string,
        required: true,
        doc: "Path to the file to analyze"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Analysis options including provider, model, enhancement settings"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ]
    ]

  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain
  alias RubberDuck.LLM
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{file_path: file_path, options: options, request_id: _request_id} = params
    
    Logger.info("Processing code analysis request for #{file_path}")
    
    # Check cache first
    cache_key = generate_cache_key(file_path, options)
    
    case get_cached_result(agent, cache_key) do
      {:ok, cached_result} ->
        handle_cache_hit(agent, cached_result, params)
        
      :not_found ->
        handle_cache_miss(agent, params, cache_key)
    end
  end

  # Private functions
  
  defp handle_cache_hit(agent, cached_result, params) do
    Logger.info("Cache hit for analysis of #{params.file_path}")
    
    # Update metrics
    with {:ok, _, %{agent: updated_agent}} <- update_cache_metrics(agent, :hit),
         {:ok, _} <- emit_analysis_result(updated_agent, cached_result, params, true) do
      {:ok, %{cache_hit: true, result: cached_result}, %{agent: updated_agent}}
    end
  end
  
  defp handle_cache_miss(agent, params, _cache_key) do
    %{file_path: file_path, options: options, request_id: request_id} = params
    
    # Add to queue and start analysis
    analysis_request = %{
      type: :file,
      file_path: file_path,
      options: options,
      request_id: request_id,
      started_at: System.monotonic_time(:millisecond)
    }
    
    # Update state with new request in queue
    with {:ok, _, %{agent: queued_agent}} <- add_to_queue(agent, analysis_request),
         {:ok, _, %{agent: metrics_agent}} <- update_cache_metrics(queued_agent, :miss),
         {:ok, _} <- emit_analysis_progress(metrics_agent, params, "started") do
      
      # Start analysis asynchronously
      Task.start(fn ->
        analyze_file_async(analysis_request)
      end)
      
      {:ok, %{processing_started: true}, %{agent: metrics_agent}}
    end
  end
  
  defp analyze_file_async(request) do
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
      
      # Emit result directly to signal bus
      emit_async_result(request, final_result, nil)
      
    rescue
      error ->
        Logger.error("Analysis failed: #{inspect(error)}")
        emit_async_result(request, nil, Exception.message(error))
    end
  end
  
  defp run_static_analysis(input) do
    case input.language do
      :elixir -> run_elixir_analysis(input)
      :javascript -> []
      :python -> []
      _ -> []
    end
  end
  
  defp run_elixir_analysis(input) do
    issues = []
    
    # Check for unused variables
    issues = issues ++ find_unused_variables(input.content)
    
    # Check for missing documentation
    issues = issues ++ find_missing_documentation(input.content)
    
    # Check for code smells
    issues = issues ++ detect_code_smells(input.content)
    
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
  
  defp detect_code_smells(content) do
    lines = String.split(content, "\n")
    max_nesting = calculate_max_nesting(lines)
    
    if max_nesting > 3 do
      [%{
        type: :warning,
        category: :complexity,
        message: "Code has deep nesting (level #{max_nesting}). Consider refactoring.",
        line: 1,
        column: 1
      }]
    else
      []
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
  
  # Cache and state management helpers
  
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
  
  defp add_to_queue(agent, request) do
    state_updates = %{
      analysis_queue: agent.state.analysis_queue ++ [request],
      active_analyses: Map.put(agent.state.active_analyses, request.request_id, request)
    }
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_cache_metrics(agent, hit_or_miss) do
    metric_field = case hit_or_miss do
      :hit -> :cache_hits
      :miss -> :cache_misses
    end
    
    updated_metrics = Map.update(agent.state.metrics, metric_field, 1, &(&1 + 1))
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_analysis_result(agent, result, params, from_cache \\ false) do
    signal_params = %{
      signal_type: "analysis.result",
      data: %{
        request_id: params.request_id,
        result: result,
        from_cache: from_cache,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
  
  defp emit_analysis_progress(agent, params, status) do
    signal_params = %{
      signal_type: "analysis.progress",
      data: %{
        request_id: params.request_id,
        status: status,
        file_path: params.file_path,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
  
  defp emit_async_result(request, result, error) do
    signal_data = case {result, error} do
      {result, nil} ->
        %{
          request_id: request.request_id,
          result: result,
          timestamp: DateTime.utc_now()
        }
      {nil, error} ->
        %{
          request_id: request.request_id,
          error: error,
          timestamp: DateTime.utc_now()
        }
    end
    
    signal = Jido.Signal.new!(%{
      type: "analysis.result",
      source: "agent:code_analysis",
      data: signal_data
    })
    
    # Publish directly to signal bus from async context
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
  end
end