defmodule RubberDuck.Jido.Actions.Conversation.Enhancement.EnhancementRequestAction do
  @moduledoc """
  Action for handling enhancement requests.
  
  This action manages content enhancement by:
  - Building enhancement tasks from content and context
  - Selecting appropriate enhancement techniques
  - Coordinating with Enhancement system
  - Managing iterative enhancement flows
  """
  
  use Jido.Action,
    name: "enhancement_request",
    description: "Handles content enhancement requests with technique coordination",
    schema: [
      content: [type: :string, required: true, doc: "Content to enhance"],
      context: [type: :map, default: %{}, doc: "Enhancement context"],
      preferences: [type: :map, default: %{}, doc: "User preferences for enhancement"],
      request_id: [type: :string, required: true, doc: "Unique request identifier"],
      previous_result: [type: :map, default: nil, doc: "Previous enhancement result for iterations"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.Enhancement.{Coordinator, TechniqueSelector}

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, task} <- build_enhancement_task(params),
         {:ok, enhancement} <- create_enhancement_record(params, task),
         {:ok, updated_agent} <- update_agent_state(agent, enhancement),
         {:ok, _} <- emit_progress_signal(updated_agent, enhancement, "started") do
      
      # Start enhancement asynchronously
      Task.start(fn ->
        process_enhancement_async(updated_agent.id, enhancement)
      end)
      
      {:ok, %{
        enhancement_started: true,
        request_id: params.request_id,
        iteration: enhancement.iteration
      }, %{agent: updated_agent}}
    end
  end

  # Private functions

  defp build_enhancement_task(params) do
    content_type = detect_content_type(params.content, params.context)
    
    task = %{
      type: content_type,
      content: params.content,
      context: Map.merge(params.context, %{
        content_type: content_type,
        has_previous: params.previous_result != nil,
        iteration: if(params.previous_result, do: params.previous_result["iteration"] || 1, else: 1)
      }),
      options: build_enhancement_options(params.preferences, content_type)
    }
    
    {:ok, task}
  end

  defp detect_content_type(content, context) do
    cond do
      context["type"] -> String.to_atom(context["type"])
      String.contains?(content, ["def ", "defmodule", "defmacro"]) -> :elixir_code
      String.contains?(content, ["function", "const", "=>"]) -> :javascript_code
      String.contains?(content, ["class", "def ", "import"]) -> :python_code
      Regex.match?(~r/^#+ /, content) -> :markdown
      true -> :text
    end
  end

  defp build_enhancement_options(preferences, content_type) do
    base_options = [
      max_iterations: preferences["max_iterations"] || 3,
      timeout: preferences["timeout"] || 60_000
    ]
    
    # Add content-type specific options
    case content_type do
      type when type in [:elixir_code, :javascript_code, :python_code] ->
        base_options ++ [
          include_tests: preferences["include_tests"] || true,
          validate_syntax: true
        ]
      
      :markdown ->
        base_options ++ [
          improve_structure: true,
          check_links: preferences["check_links"] || false
        ]
      
      _ ->
        base_options
    end
  end

  defp create_enhancement_record(params, task) do
    enhancement = %{
      request_id: params.request_id,
      task: task,
      preferences: params.preferences,
      started_at: System.monotonic_time(:millisecond),
      iteration: if(params.previous_result, do: (params.previous_result["iteration"] || 0) + 1, else: 1)
    }
    
    {:ok, enhancement}
  end

  defp update_agent_state(agent, enhancement) do
    state_updates = %{
      enhancement_queue: agent.state.enhancement_queue ++ [enhancement],
      active_enhancements: Map.put(agent.state.active_enhancements, enhancement.request_id, enhancement)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_progress_signal(agent, enhancement, status) do
    message = case status do
      "started" -> "Analyzing content for enhancement opportunities"
      "enhancing" -> "Applying enhancement techniques"
      "validating" -> "Validating enhancement results"
      _ -> "Processing enhancement"
    end
    
    signal_params = %{
      signal_type: "conversation.enhancement.progress",
      data: %{
        request_id: enhancement.request_id,
        status: status,
        message: message,
        iteration: enhancement.iteration,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp process_enhancement_async(agent_id, enhancement) do
    try do
      # Select enhancement techniques
      techniques = select_techniques(enhancement.task, enhancement.preferences)
      
      # Emit technique selection
      emit_async_signal("conversation.enhancement.technique_selection", %{
        request_id: enhancement.request_id,
        techniques: Enum.map(techniques, &Atom.to_string/1),
        reason: "Selected based on content type and preferences",
        timestamp: DateTime.utc_now()
      })
      
      # Update progress
      emit_async_signal("conversation.enhancement.progress", %{
        request_id: enhancement.request_id,
        status: "enhancing",
        message: "Applying #{length(techniques)} enhancement techniques",
        timestamp: DateTime.utc_now()
      })
      
      # Apply enhancements through coordinator
      enhancement_result = apply_enhancements(enhancement.task, techniques, enhancement.preferences)
      
      # Generate suggestions from enhancement
      suggestions = generate_suggestions(enhancement_result, enhancement.task)
      
      # Emit individual suggestions
      Enum.each(suggestions, fn suggestion ->
        emit_async_signal("conversation.enhancement.suggestion_generated", %{
          request_id: enhancement.request_id,
          suggestion: suggestion,
          timestamp: DateTime.utc_now()
        })
      end)
      
      # Prepare final result
      result = %{
        "request_id" => enhancement.request_id,
        "enhanced_content" => enhancement_result.enhanced,
        "original_content" => enhancement.task.content,
        "suggestions" => suggestions,
        "techniques_applied" => enhancement_result.techniques_applied,
        "metrics" => enhancement_result.metrics,
        "iteration" => enhancement.iteration,
        "validation_pending" => false
      }
      
      # Emit result
      emit_async_signal("conversation.enhancement.result", Map.merge(result, %{
        timestamp: DateTime.utc_now()
      }))
      
    rescue
      error ->
        Logger.error("Enhancement processing failed",
          request_id: enhancement.request_id,
          error: Exception.message(error)
        )
        
        emit_async_signal("conversation.enhancement.result", %{
          request_id: enhancement.request_id,
          error: Exception.message(error),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp select_techniques(task, preferences) do
    if preferences["techniques"] do
      # Use explicitly requested techniques
      Enum.map(preferences["techniques"], &String.to_atom/1)
    else
      # Use TechniqueSelector for automatic selection
      config = %{
        content_type: task.type,
        iteration: task.context[:iteration] || 1,
        has_previous: task.context[:has_previous] || false
      }
      
      TechniqueSelector.select_techniques(task, config)
    end
  end

  defp apply_enhancements(task, techniques, preferences) do
    # Build options for coordinator
    opts = [
      techniques: techniques,
      pipeline_type: String.to_atom(preferences["pipeline_type"] || "sequential"),
      max_iterations: preferences["max_iterations"] || 3,
      timeout: preferences["timeout"] || 60_000
    ]
    
    case Coordinator.enhance(task, opts) do
      {:ok, result} -> result
      {:error, reason} -> 
        raise "Enhancement failed: #{inspect(reason)}"
    end
  end

  defp generate_suggestions(enhancement_result, _task) do
    %{
      enhanced: enhanced_content,
      original: original_content,
      techniques_applied: techniques,
      metrics: metrics
    } = enhancement_result
    
    suggestions = []
    
    # Generate suggestions based on techniques applied
    suggestions = suggestions ++ 
      if :cot in techniques do
        [%{
          "id" => generate_suggestion_id(),
          "type" => "reasoning",
          "description" => "Added step-by-step reasoning to improve clarity",
          "impact" => "medium",
          "confidence" => metrics[:cot_improvement] || 0.7,
          "technique" => "chain_of_thought"
        }]
      else
        []
      end
    
    # Add general improvement suggestion if content changed significantly
    suggestions = if String.length(enhanced_content) > String.length(original_content) * 1.1 do
      suggestions ++ [%{
        "id" => generate_suggestion_id(),
        "type" => "expansion",
        "description" => "Expanded content with additional context and details",
        "impact" => "high",
        "confidence" => 0.8
      }]
    else
      suggestions
    end
    
    # Rank and limit suggestions
    suggestions
    |> rank_suggestions()
    |> Enum.take(5)
  end

  defp rank_suggestions(suggestions) do
    suggestions
    |> Enum.sort_by(fn s -> 
      impact_score = case s["impact"] do
        "high" -> 3
        "medium" -> 2
        "low" -> 1
        _ -> 0
      end
      
      confidence = s["confidence"] || 0.5
      impact_score * confidence
    end, :desc)
  end

  defp generate_suggestion_id do
    "sug_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp emit_async_signal(signal_type, data) do
    signal = %{
      type: signal_type,
      source: "agent:enhancement_conversation",
      data: data
    }
    
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(signal)])
  end
end