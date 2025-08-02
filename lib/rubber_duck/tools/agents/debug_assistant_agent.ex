defmodule RubberDuck.Tools.Agents.DebugAssistantAgent do
  @moduledoc """
  Agent that orchestrates the DebugAssistant tool for intelligent error analysis and debugging.
  
  This agent manages debugging sessions, maintains error history, tracks debugging patterns,
  and provides contextual debugging workflows for Elixir applications.
  
  ## Signals
  
  ### Input Signals
  - `analyze_error` - Analyze an error message and stack trace
  - `start_debug_session` - Start a debugging session for complex issues
  - `add_debug_context` - Add additional context to ongoing session
  - `suggest_debugging_steps` - Get step-by-step debugging guidance
  - `track_debug_attempt` - Record a debugging attempt and outcome
  - `get_similar_errors` - Find similar errors from history
  - `create_debug_report` - Generate comprehensive debugging report
  
  ### Output Signals
  - `error_analyzed` - Error analysis completed
  - `debug_session_started` - Debug session initialized
  - `debugging_steps` - Step-by-step debugging guidance
  - `similar_errors_found` - Similar historical errors
  - `debug_report_generated` - Comprehensive debug report
  - `debug_progress` - Progress updates during analysis
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :debug_assistant,
    name: "debug_assistant_agent",
    description: "Manages intelligent error analysis and debugging workflows",
    category: "debugging",
    tags: ["debugging", :troubleshooting, :error_analysis, :diagnostics],
    schema: [
      # Active debugging sessions
      debug_sessions: [type: :map, default: %{}],
      active_session: [type: {:nullable, :string}, default: nil],
      
      # Error history and patterns
      error_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      error_patterns: [type: :map, default: %{}],
      
      # Learning from debugging attempts
      successful_solutions: [type: :map, default: %{}],
      failed_attempts: [type: :map, default: %{}],
      
      # Common debugging contexts
      common_contexts: [type: :map, default: %{
        "phoenix" => ["web", "controllers", "views", "live"],
        "ecto" => ["database", "queries", "migrations", "schemas"],
        "genserver" => ["concurrency", "state", "messaging"],
        "testing" => ["unit", "integration", "mocks"]
      }],
      
      # Statistics
      debug_stats: [type: :map, default: %{
        total_errors_analyzed: 0,
        by_error_type: %{},
        by_severity: %{},
        resolution_rate: 0,
        average_resolution_time: 0
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "analyze_error"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      error_message: data["error_message"],
      stack_trace: data["stack_trace"] || "",
      code_context: data["code_context"] || "",
      analysis_depth: data["analysis_depth"] || "comprehensive",
      runtime_info: data["runtime_info"] || %{},
      previous_attempts: data["previous_attempts"] || [],
      error_history: get_relevant_error_history(agent, data["error_message"]),
      include_examples: data["include_examples"] || true
    }
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "session_id" => data["session_id"],
          "user_id" => data["user_id"],
          "error_context" => categorize_error_context(data["error_message"])
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "debug.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "analyzing_error",
        error_type: extract_error_type(data["error_message"])
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Store debugging metadata
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:debug_metadata],
      %{
        error_message: data["error_message"],
        analysis_depth: params.analysis_depth,
        started_at: DateTime.utc_now()
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "start_debug_session"} = signal) do
    %{"data" => data} = signal
    session_id = data["session_id"] || "session_#{System.unique_integer([:positive])}"
    
    # Initialize debug session
    session = %{
      id: session_id,
      name: data["name"] || "Debug Session",
      started_at: DateTime.utc_now(),
      errors: [],
      attempts: [],
      context: data["context"] || %{},
      status: "active",
      resolution_strategy: data["strategy"] || "systematic"
    }
    
    agent = put_in(agent.state.debug_sessions[session_id], session)
    agent = put_in(agent.state.active_session, session_id)
    
    # Analyze initial error if provided
    agent = if data["initial_error"] do
      error_signal = %{
        "type" => "analyze_error",
        "data" => Map.merge(data["initial_error"], %{
          "session_id" => session_id,
          "analysis_depth" => "step_by_step"
        })
      }
      
      case handle_tool_signal(agent, error_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> agent
      end
    else
      agent
    end
    
    signal = Jido.Signal.new!(%{
      type: "debug.session.started",
      source: "agent:#{agent.id}",
      data: %{
        session_id: session_id,
        name: session.name,
        strategy: session.resolution_strategy
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "add_debug_context"} = signal) do
    %{"data" => data} = signal
    session_id = data["session_id"] || agent.state.active_session
    
    if session_id && agent.state.debug_sessions[session_id] do
      # Add context to session
      agent = update_in(agent.state.debug_sessions[session_id][:context], fn context ->
        Map.merge(context, data["context"] || %{})
      end)
      
      # Re-analyze recent errors with new context if requested
      agent = if data["reanalyze"] && not Enum.empty?(agent.state.debug_sessions[session_id].errors) do
        latest_error = List.first(agent.state.debug_sessions[session_id].errors)
        
        reanalyze_signal = %{
          "type" => "analyze_error",
          "data" => Map.merge(latest_error, %{
            "session_id" => session_id,
            "code_context" => data["context"]["code"] || latest_error["code_context"],
            "runtime_info" => data["context"]["runtime"] || latest_error["runtime_info"]
          })
        }
        
        case handle_tool_signal(agent, reanalyze_signal) do
          {:ok, updated_agent} -> updated_agent
          _ -> agent
        end
      else
        agent
      end
      
      signal = Jido.Signal.new!(%{
        type: "debug.context.added",
        source: "agent:#{agent.id}",
        data: %{
          session_id: session_id,
          context_keys: Map.keys(data["context"] || %{})
        }
      })
      emit_signal(agent, signal)
      
      {:ok, agent}
    else
      signal = Jido.Signal.new!(%{
        type: "debug.error",
        source: "agent:#{agent.id}",
        data: %{
          error: "Invalid session ID or no active session"
        }
      })
      emit_signal(agent, signal)
      {:ok, agent}
    end
  end
  
  def handle_tool_signal(agent, %{"type" => "suggest_debugging_steps"} = signal) do
    %{"data" => data} = signal
    
    # Generate debugging steps based on error type and context
    steps = generate_contextual_debugging_steps(
      data["error_type"],
      data["context"] || %{},
      agent.state.successful_solutions
    )
    
    signal = Jido.Signal.new!(%{
      type: "debug.steps",
      source: "agent:#{agent.id}",
      data: %{
        error_type: data["error_type"],
        steps: steps,
        estimated_time: estimate_debugging_time(data["error_type"], length(steps)),
        difficulty: assess_debugging_difficulty(data["error_type"])
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "track_debug_attempt"} = signal) do
    %{"data" => data} = signal
    session_id = data["session_id"] || agent.state.active_session
    
    attempt = %{
      id: "attempt_#{System.unique_integer([:positive])}",
      description: data["description"],
      approach: data["approach"],
      outcome: data["outcome"],  # "success", "failure", "partial"
      timestamp: DateTime.utc_now(),
      time_spent: data["time_spent_minutes"],
      notes: data["notes"] || ""
    }
    
    # Add to session if available
    agent = if session_id && agent.state.debug_sessions[session_id] do
      update_in(agent.state.debug_sessions[session_id][:attempts], &[attempt | &1])
    else
      agent
    end
    
    # Learn from attempt
    agent = case data["outcome"] do
      "success" ->
        update_successful_solution(agent, data["error_type"], data["approach"], data["description"])
      "failure" ->
        update_failed_attempt(agent, data["error_type"], data["approach"], data["description"])
      _ ->
        agent
    end
    
    signal = Jido.Signal.new!(%{
      type: "debug.attempt.tracked",
      source: "agent:#{agent.id}",
      data: %{
        attempt_id: attempt.id,
        outcome: data["outcome"],
        learning_updated: data["outcome"] in ["success", "failure"]
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "get_similar_errors"} = signal) do
    %{"data" => data} = signal
    
    # Find similar errors in history
    similar_errors = find_similar_errors(
      agent.state.error_history,
      data["error_message"],
      data["similarity_threshold"] || 0.7
    )
    
    # Include successful solutions if any
    relevant_solutions = get_relevant_solutions(
      agent.state.successful_solutions,
      extract_error_type(data["error_message"])
    )
    
    signal = Jido.Signal.new!(%{
      type: "debug.similar_errors.found",
      source: "agent:#{agent.id}",
      data: %{
        query_error: data["error_message"],
        similar_errors: similar_errors,
        successful_solutions: relevant_solutions,
        total_found: length(similar_errors)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "create_debug_report"} = signal) do
    %{"data" => data} = signal
    session_id = data["session_id"] || agent.state.active_session
    
    if session_id && agent.state.debug_sessions[session_id] do
      session = agent.state.debug_sessions[session_id]
      
      report = %{
        "session_id" => session_id,
        "session_name" => session.name,
        "duration" => DateTime.diff(DateTime.utc_now(), session.started_at, :minute),
        "errors_analyzed" => length(session.errors),
        "attempts_made" => length(session.attempts),
        "resolution_status" => determine_resolution_status(session.attempts),
        "key_findings" => extract_key_findings(session),
        "lessons_learned" => extract_lessons_learned(session.attempts),
        "recommendations" => generate_recommendations(session),
        "generated_at" => DateTime.utc_now()
      }
      
      # Mark session as completed
      agent = put_in(agent.state.debug_sessions[session_id][:status], "completed")
      
      signal = Jido.Signal.new!(%{
        type: "debug.report.generated",
        source: "agent:#{agent.id}",
        data: report
      })
      emit_signal(agent, signal)
      
      {:ok, agent}
    else
      signal = Jido.Signal.new!(%{
        type: "debug.error",
        source: "agent:#{agent.id}",
        data: %{
          error: "No session found for report generation"
        }
      })
      emit_signal(agent, signal)
      {:ok, agent}
    end
  end
  
  # Override process_result to handle debug-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add debug metadata
    debug_metadata = request[:debug_metadata] || %{}
    
    result
    |> Map.put(:analyzed_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.merge(debug_metadata)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %{"type" => "tool_result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    %{"data" => data} = signal
    
    if data["result"] && not data["from_cache"] do
      # Add to error history
      agent = add_to_error_history(agent, data["result"])
      
      # Update session if applicable
      agent = if session_id = get_in(data, ["result", :session_id]) do
        add_error_to_session(agent, session_id, data["result"])
      else
        agent
      end
      
      # Update statistics
      agent = update_debug_stats(agent, data["result"])
      
      # Learn patterns
      agent = update_error_patterns(agent, data["result"])
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "debug.error.analyzed",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data["request_id"],
          error_type: data["result"]["error_type"],
          likely_causes: data["result"]["likely_causes"],
          debugging_steps: data["result"]["debugging_steps"],
          suggested_fixes: data["result"]["suggested_fixes"],
          confidence: data["result"]["confidence"],
          severity: assess_severity_from_type(data["result"]["error_type"])
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
    "debug_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp categorize_error_context(error_message) do
    cond do
      error_message =~ ~r/Phoenix/ -> "web"
      error_message =~ ~r/Ecto|Postgrex/ -> "database"
      error_message =~ ~r/GenServer/ -> "concurrency"
      error_message =~ ~r/ExUnit/ -> "testing"
      error_message =~ ~r/File|IO/ -> "file_system"
      true -> "application"
    end
  end
  
  defp extract_error_type(error_message) do
    cond do
      error_message =~ ~r/UndefinedFunctionError/ -> "undefined_function"
      error_message =~ ~r/FunctionClauseError/ -> "function_clause"
      error_message =~ ~r/MatchError/ -> "match_error"
      error_message =~ ~r/KeyError/ -> "key_error"
      error_message =~ ~r/ArgumentError/ -> "argument_error"
      error_message =~ ~r/timeout/ -> "timeout"
      true -> "generic"
    end
  end
  
  defp get_relevant_error_history(agent, error_message) do
    error_type = extract_error_type(error_message)
    
    agent.state.error_history
    |> Enum.filter(fn entry ->
      entry.error_type == error_type
    end)
    |> Enum.take(5)
    |> Enum.map(fn entry ->
      "#{entry.error_message} (resolved: #{entry.resolved || false})"
    end)
  end
  
  defp generate_contextual_debugging_steps(error_type, context, successful_solutions) do
    base_steps = get_base_debugging_steps(error_type)
    
    # Add context-specific steps
    context_steps = case context["domain"] do
      "web" -> [
        "Check request parameters and routing",
        "Verify controller action exists and has proper clauses",
        "Check view/template rendering"
      ]
      "database" -> [
        "Verify database connection and configuration",
        "Check schema definitions and migrations",
        "Review query syntax and parameters"
      ]
      "concurrency" -> [
        "Check process state and message handling",
        "Verify GenServer callbacks are properly implemented",
        "Look for race conditions or deadlocks"
      ]
      _ -> []
    end
    
    # Add successful solution steps if available
    solution_steps = case Map.get(successful_solutions, error_type) do
      nil -> []
      solutions -> [
        "Try these previously successful approaches:",
        Enum.map_join(solutions, "\n  ", fn {approach, _} -> "- #{approach}" end)
      ]
    end
    
    base_steps ++ context_steps ++ solution_steps
  end
  
  defp get_base_debugging_steps(error_type) do
    case error_type do
      "undefined_function" ->
        [
          "Verify the module name and function spelling",
          "Check if the module is properly aliased or imported",
          "Ensure the function is defined with correct arity",
          "Check mix.exs dependencies"
        ]
      "function_clause" ->
        [
          "Check the function arguments and their types",
          "Verify pattern matching in function heads",
          "Add IO.inspect to see actual values being passed",
          "Consider adding a catch-all clause"
        ]
      "match_error" ->
        [
          "Examine the expected vs actual data structure",
          "Use pattern matching more defensively",
          "Consider using case or with statements",
          "Add proper error handling"
        ]
      _ ->
        [
          "Read the error message carefully",
          "Check the stack trace for the error location",
          "Add debugging output to understand data flow",
          "Test with simpler inputs"
        ]
    end
  end
  
  defp estimate_debugging_time(error_type, step_count) do
    base_time = case error_type do
      "undefined_function" -> 10
      "function_clause" -> 15
      "match_error" -> 20
      "timeout" -> 30
      _ -> 15
    end
    
    "#{base_time + (step_count * 3)}-#{base_time * 2 + (step_count * 5)} minutes"
  end
  
  defp assess_debugging_difficulty(error_type) do
    case error_type do
      "undefined_function" -> "easy"
      "key_error" -> "easy"
      "argument_error" -> "easy"
      "function_clause" -> "medium"
      "match_error" -> "medium"
      "timeout" -> "hard"
      "generic" -> "hard"
      _ -> "medium"
    end
  end
  
  defp update_successful_solution(agent, error_type, approach, description) do
    update_in(agent.state.successful_solutions, fn solutions ->
      type_solutions = Map.get(solutions, error_type, [])
      updated_solutions = [{approach, description} | type_solutions]
      |> Enum.uniq_by(fn {approach, _} -> approach end)
      |> Enum.take(5)  # Keep top 5 solutions
      
      Map.put(solutions, error_type, updated_solutions)
    end)
  end
  
  defp update_failed_attempt(agent, error_type, approach, description) do
    update_in(agent.state.failed_attempts, fn attempts ->
      type_attempts = Map.get(attempts, error_type, [])
      updated_attempts = [{approach, description} | type_attempts]
      |> Enum.take(10)  # Keep recent failures
      
      Map.put(attempts, error_type, updated_attempts)
    end)
  end
  
  defp find_similar_errors(error_history, query_error, threshold) do
    query_words = extract_error_keywords(query_error)
    
    error_history
    |> Enum.map(fn entry ->
      similarity = calculate_similarity(query_words, extract_error_keywords(entry.error_message))
      {entry, similarity}
    end)
    |> Enum.filter(fn {_, similarity} -> similarity >= threshold end)
    |> Enum.sort_by(fn {_, similarity} -> similarity end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {entry, similarity} ->
      %{
        error_message: entry.error_message,
        error_type: entry.error_type,
        resolution: entry.resolution,
        similarity: similarity,
        analyzed_at: entry.analyzed_at
      }
    end)
  end
  
  defp extract_error_keywords(error_message) do
    error_message
    |> String.downcase()
    |> String.split(~r/[^\w]/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.uniq()
  end
  
  defp calculate_similarity(words1, words2) do
    intersection = MapSet.intersection(MapSet.new(words1), MapSet.new(words2))
    union = MapSet.union(MapSet.new(words1), MapSet.new(words2))
    
    if MapSet.size(union) > 0 do
      MapSet.size(intersection) / MapSet.size(union)
    else
      0
    end
  end
  
  defp get_relevant_solutions(successful_solutions, error_type) do
    Map.get(successful_solutions, error_type, [])
    |> Enum.take(3)
    |> Enum.map(fn {approach, description} ->
      %{approach: approach, description: description}
    end)
  end
  
  defp add_to_error_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      error_message: result[:error_message],
      error_type: result["error_type"],
      likely_causes: result["likely_causes"],
      confidence: result["confidence"],
      resolved: false,  # Will be updated when resolution is tracked
      analyzed_at: result[:analyzed_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.error_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.error_history, new_history)
  end
  
  defp add_error_to_session(agent, session_id, result) do
    if agent.state.debug_sessions[session_id] do
      error_entry = %{
        error_message: result[:error_message],
        error_type: result["error_type"],
        analysis: result,
        analyzed_at: DateTime.utc_now()
      }
      
      update_in(agent.state.debug_sessions[session_id][:errors], &[error_entry | &1])
    else
      agent
    end
  end
  
  defp update_debug_stats(agent, result) do
    update_in(agent.state.debug_stats, fn stats ->
      error_type = result["error_type"]
      severity = assess_severity_from_type(error_type)
      
      stats
      |> Map.update!(:total_errors_analyzed, &(&1 + 1))
      |> Map.update!(:by_error_type, fn by_type ->
        Map.update(by_type, error_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:by_severity, fn by_severity ->
        Map.update(by_severity, severity, 1, &(&1 + 1))
      end)
    end)
  end
  
  defp assess_severity_from_type(error_type) do
    case error_type do
      "compile_error" -> "critical"
      "system_limit_error" -> "critical"
      "timeout" -> "high"
      "database_error" -> "high"
      "undefined_function" -> "medium"
      "function_clause" -> "medium"
      _ -> "low"
    end
  end
  
  defp update_error_patterns(agent, result) do
    error_type = result["error_type"]
    causes = result["likely_causes"] || []
    
    update_in(agent.state.error_patterns, fn patterns ->
      type_patterns = Map.get(patterns, error_type, %{})
      
      updated_patterns = Enum.reduce(causes, type_patterns, fn cause, acc ->
        Map.update(acc, cause, 1, &(&1 + 1))
      end)
      
      Map.put(patterns, error_type, updated_patterns)
    end)
  end
  
  defp determine_resolution_status(attempts) do
    if Enum.any?(attempts, &(&1.outcome == "success")) do
      "resolved"
    else
      if Enum.any?(attempts, &(&1.outcome == "partial")) do
        "partially_resolved"
      else
        "unresolved"
      end
    end
  end
  
  defp extract_key_findings(session) do
    session.errors
    |> Enum.map(fn error ->
      %{
        error_type: error.error_type,
        main_cause: List.first(error.analysis["likely_causes"] || []),
        confidence: error.analysis["confidence"]
      }
    end)
  end
  
  defp extract_lessons_learned(attempts) do
    attempts
    |> Enum.filter(&(&1.outcome in ["success", "failure"]))
    |> Enum.map(fn attempt ->
      %{
        approach: attempt.approach,
        outcome: attempt.outcome,
        lesson: if(attempt.outcome == "success", do: "Effective approach", else: "Avoid this approach"),
        notes: attempt.notes
      }
    end)
  end
  
  defp generate_recommendations(session) do
    recommendations = []
    
    # Based on error patterns
    error_types = Enum.map(session.errors, & &1.error_type) |> Enum.uniq()
    
    recommendations = if "function_clause" in error_types do
      ["Add more defensive pattern matching", "Consider using guards for input validation" | recommendations]
    else
      recommendations
    end
    
    recommendations = if "timeout" in error_types do
      ["Review timeout settings", "Consider async processing for long operations" | recommendations]
    else
      recommendations
    end
    
    # Based on attempt patterns
    failed_attempts = Enum.filter(session.attempts, &(&1.outcome == "failure"))
    
    recommendations = if length(failed_attempts) > 3 do
      ["Break down the problem into smaller pieces", "Consider pair programming or code review" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
    |> Enum.take(5)
  end
end