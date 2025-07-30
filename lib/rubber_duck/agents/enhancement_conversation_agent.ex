defmodule RubberDuck.Agents.EnhancementConversationAgent do
  @moduledoc """
  Autonomous agent for handling enhancement conversations.
  
  This agent manages code and content enhancement requests through
  asynchronous signal-based communication. It coordinates with the
  existing enhancement system to apply techniques like CoT, RAG,
  and self-correction.
  
  ## Signals
  
  ### Input Signals
  - `enhancement_request`: Request content or code enhancement
  - `feedback_received`: User feedback on enhancement suggestions
  - `validation_response`: Results from validation requests
  - `get_enhancement_metrics`: Request current metrics
  
  ### Output Signals
  - `enhancement_result`: Final enhanced content with suggestions
  - `enhancement_progress`: Progress updates during enhancement
  - `suggestion_generated`: Individual enhancement suggestions
  - `technique_selection`: Selected enhancement techniques
  - `validation_request`: Request validation of enhancements
  - `enhancement_metrics`: Current metrics data
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "enhancement_conversation",
    description: "Handles code and content enhancement conversations with technique coordination",
    category: "conversation",
    schema: [
      enhancement_queue: [type: {:list, :map}, default: []],
      active_enhancements: [type: :map, default: %{}],
      enhancement_history: [type: {:list, :map}, default: []],
      suggestion_cache: [type: :map, default: %{}],
      validation_results: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        total_enhancements: 0,
        suggestions_generated: 0,
        suggestions_accepted: 0,
        avg_improvement_score: 0.0,
        technique_effectiveness: %{}
      }],
      enhancement_config: [type: :map, default: %{
        default_techniques: [:cot, :self_correction],
        max_suggestions: 5,
        validation_enabled: true,
        ab_testing_enabled: false
      }]
    ]
  
  require Logger
  
  alias RubberDuck.Enhancement.{Coordinator, TechniqueSelector}
  
  # Signal Handlers
  
  @impl true
  def handle_signal(agent, %{"type" => "enhancement_request"} = signal) do
    %{
      "data" => %{
        "content" => content,
        "context" => context,
        "preferences" => preferences,
        "request_id" => request_id
      } = data
    } = signal
    
    # Check if this is an iterative enhancement
    previous_result = data["previous_result"]
    
    # Build enhancement task
    task = build_enhancement_task(content, context, preferences, previous_result)
    
    # Create enhancement record
    enhancement = %{
      request_id: request_id,
      task: task,
      preferences: preferences || %{},
      started_at: System.monotonic_time(:millisecond),
      iteration: if(previous_result, do: (previous_result["iteration"] || 0) + 1, else: 1)
    }
    
    # Add to queue and active enhancements
    agent = agent
    |> update_in([:state, :enhancement_queue], &(&1 ++ [enhancement]))
    |> put_in([:state, :active_enhancements, request_id], enhancement)
    
    # Start enhancement asynchronously
    Task.start(fn ->
      process_enhancement(agent.id, enhancement)
    end)
    
    # Emit initial progress
    emit_signal("enhancement_progress", %{
      "request_id" => request_id,
      "status" => "started",
      "message" => "Analyzing content for enhancement opportunities"
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "feedback_received"} = signal) do
    %{
      "data" => %{
        "request_id" => request_id,
        "suggestion_id" => suggestion_id,
        "feedback" => feedback,
        "accepted" => accepted
      }
    } = signal
    
    # Update metrics based on feedback
    agent = agent
    |> update_suggestion_metrics(suggestion_id, accepted)
    |> update_technique_effectiveness(request_id, suggestion_id, feedback)
    
    # Store feedback in history
    agent = update_in(agent.state.enhancement_history, fn history ->
      history ++ [%{
        request_id: request_id,
        suggestion_id: suggestion_id,
        feedback: feedback,
        accepted: accepted,
        timestamp: DateTime.utc_now()
      }]
    end)
    
    Logger.info("Enhancement feedback received",
      request_id: request_id,
      accepted: accepted
    )
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "validation_response"} = signal) do
    %{
      "data" => %{
        "request_id" => request_id,
        "validation_id" => validation_id,
        "results" => results
      }
    } = signal
    
    # Store validation results
    agent = put_in(agent.state.validation_results[validation_id], results)
    
    # Check if all validations for this request are complete
    if all_validations_complete?(agent, request_id) do
      # Finalize enhancement with validation results
      finalize_enhancement(agent, request_id)
    else
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "get_enhancement_metrics"} = _signal) do
    emit_signal("enhancement_metrics", %{
      "metrics" => agent.state.metrics,
      "active_enhancements" => map_size(agent.state.active_enhancements),
      "history_size" => length(agent.state.enhancement_history),
      "cache_size" => map_size(agent.state.suggestion_cache),
      "config" => agent.state.enhancement_config
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    Logger.warning("EnhancementConversationAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end
  
  # Private Functions
  
  defp build_enhancement_task(content, context, preferences, previous_result) do
    content_type = detect_content_type(content, context)
    
    %{
      type: content_type,
      content: content,
      context: Map.merge(context || %{}, %{
        content_type: content_type,
        has_previous: previous_result != nil,
        iteration: if(previous_result, do: previous_result["iteration"] || 1, else: 1)
      }),
      options: build_enhancement_options(preferences, content_type)
    }
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
  
  defp process_enhancement(_agent_id, enhancement) do
    %{request_id: request_id, task: task, preferences: preferences} = enhancement
    
    try do
      # Select enhancement techniques
      techniques = select_techniques(task, preferences)
      
      # Emit technique selection
      emit_signal("technique_selection", %{
        "request_id" => request_id,
        "techniques" => Enum.map(techniques, &Atom.to_string/1),
        "reason" => "Selected based on content type and preferences"
      })
      
      # Update progress
      emit_signal("enhancement_progress", %{
        "request_id" => request_id,
        "status" => "enhancing",
        "message" => "Applying #{length(techniques)} enhancement techniques"
      })
      
      # Apply enhancements through coordinator
      enhancement_result = apply_enhancements(task, techniques, preferences)
      
      # Generate suggestions from enhancement
      suggestions = generate_suggestions(enhancement_result, task)
      
      # Emit individual suggestions
      Enum.each(suggestions, fn suggestion ->
        emit_signal("suggestion_generated", %{
          "request_id" => request_id,
          "suggestion" => suggestion
        })
      end)
      
      # Validate if enabled
      validation_ids = if should_validate?(preferences) do
        validate_suggestions(request_id, suggestions, task)
      else
        []
      end
      
      # Prepare final result
      result = %{
        "request_id" => request_id,
        "enhanced_content" => enhancement_result.enhanced,
        "original_content" => task.content,
        "suggestions" => suggestions,
        "techniques_applied" => enhancement_result.techniques_applied,
        "metrics" => enhancement_result.metrics,
        "iteration" => enhancement.iteration,
        "validation_pending" => length(validation_ids) > 0
      }
      
      # If no validation needed, emit result immediately
      unless result["validation_pending"] do
        emit_signal("enhancement_result", result)
      end
      
    rescue
      error ->
        Logger.error("Enhancement processing failed",
          request_id: request_id,
          error: Exception.message(error)
        )
        
        emit_signal("enhancement_result", %{
          "request_id" => request_id,
          "error" => Exception.message(error)
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
    
    # Extract specific improvements as suggestions
    suggestions = []
    
    # Generate suggestions based on techniques applied
    suggestions = suggestions ++ 
      if :cot in techniques do
        generate_cot_suggestions(enhanced_content, original_content, metrics)
      else
        []
      end
    
    suggestions = suggestions ++
      if :self_correction in techniques do
        generate_correction_suggestions(enhanced_content, original_content, metrics)
      else
        []
      end
    
    suggestions = suggestions ++
      if :rag in techniques do
        generate_rag_suggestions(enhanced_content, original_content, metrics)
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
  
  defp generate_cot_suggestions(_enhanced, _original, metrics) do
    [
      %{
        "id" => generate_suggestion_id(),
        "type" => "reasoning",
        "description" => "Added step-by-step reasoning to improve clarity",
        "impact" => "medium",
        "confidence" => metrics[:cot_improvement] || 0.7,
        "technique" => "chain_of_thought"
      }
    ]
  end
  
  defp generate_correction_suggestions(_enhanced, _original, metrics) do
    corrections = metrics[:corrections] || []
    
    Enum.map(corrections, fn correction ->
      %{
        "id" => generate_suggestion_id(),
        "type" => "correction",
        "description" => correction[:description] || "Applied self-correction",
        "impact" => "high",
        "confidence" => correction[:confidence] || 0.85,
        "technique" => "self_correction"
      }
    end)
  end
  
  defp generate_rag_suggestions(_enhanced, _original, metrics) do
    sources = metrics[:rag_sources] || []
    
    if length(sources) > 0 do
      [%{
        "id" => generate_suggestion_id(),
        "type" => "context",
        "description" => "Enhanced with relevant context from #{length(sources)} sources",
        "impact" => "medium",
        "confidence" => 0.75,
        "technique" => "rag",
        "sources" => Enum.take(sources, 3)
      }]
    else
      []
    end
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
  
  defp should_validate?(preferences) do
    preferences["validation_enabled"] != false
  end
  
  defp validate_suggestions(request_id, suggestions, task) do
    # For code improvements, generate validation requests
    case task.type do
      type when type in [:elixir_code, :javascript_code, :python_code] ->
        Enum.map(suggestions, fn suggestion ->
          validation_id = generate_validation_id()
          
          emit_signal("validation_request", %{
            "request_id" => request_id,
            "validation_id" => validation_id,
            "suggestion_id" => suggestion["id"],
            "content" => task.content,
            "suggestion" => suggestion,
            "validation_type" => "syntax_and_tests"
          })
          
          validation_id
        end)
      
      _ ->
        # Non-code content doesn't need validation
        []
    end
  end
  
  defp all_validations_complete?(_agent, _request_id) do
    # Check if all validation responses have been received
    # This is simplified - in production would track pending validations
    true
  end
  
  defp finalize_enhancement(agent, request_id) do
    case agent.state.active_enhancements[request_id] do
      nil -> 
        {:ok, agent}
      
      _enhancement ->
        # Collect all validation results
        validations = collect_validation_results(agent, request_id)
        
        # Update suggestions with validation results
        # Emit final result
        emit_signal("enhancement_result", %{
          "request_id" => request_id,
          "status" => "completed_with_validation",
          "validations" => validations
        })
        
        # Clean up and update metrics
        agent = agent
        |> update_in([:state, :active_enhancements], &Map.delete(&1, request_id))
        |> update_in([:state, :metrics, :total_enhancements], &(&1 + 1))
        
        {:ok, agent}
    end
  end
  
  defp collect_validation_results(agent, request_id) do
    # Collect all validation results for this request
    agent.state.validation_results
    |> Map.values()
    |> Enum.filter(fn v -> v[:request_id] == request_id end)
  end
  
  defp update_suggestion_metrics(agent, _suggestion_id, accepted) do
    agent
    |> update_in([:state, :metrics, :suggestions_generated], &(&1 + 1))
    |> update_in([:state, :metrics, :suggestions_accepted], fn count ->
      if accepted, do: count + 1, else: count
    end)
    |> update_in([:state, :metrics, :avg_improvement_score], fn avg ->
      # Simple running average
      total = agent.state.metrics.suggestions_generated
      score = if accepted, do: 1.0, else: 0.0
      (avg * (total - 1) + score) / total
    end)
  end
  
  defp update_technique_effectiveness(agent, _request_id, _suggestion_id, feedback) do
    # Find the technique used for this suggestion
    # This is simplified - would need to track suggestion->technique mapping
    technique = :unknown
    
    effectiveness_delta = case feedback["rating"] do
      rating when is_number(rating) -> rating / 5.0
      "positive" -> 0.1
      "negative" -> -0.1
      _ -> 0.0
    end
    
    update_in(agent.state.metrics.technique_effectiveness[technique], fn current ->
      current_value = current || 0.5
      # Exponential moving average
      alpha = 0.1
      current_value * (1 - alpha) + effectiveness_delta * alpha
    end)
  end
  
  defp generate_suggestion_id do
    "sug_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp generate_validation_id do
    "val_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end