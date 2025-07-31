defmodule RubberDuck.Tools.Agents.CodeGeneratorAgent do
  @moduledoc """
  Agent that orchestrates the CodeGenerator tool for AI-powered code generation.
  
  This agent manages code generation requests, maintains generation history,
  handles template management, and provides intelligent code generation workflows.
  
  ## Signals
  
  ### Input Signals
  - `generate_code` - Generate code from description
  - `generate_from_template` - Generate code using a template
  - `batch_generate` - Generate multiple code pieces
  - `refine_generation` - Refine previously generated code
  - `get_generation_history` - Retrieve past generations
  
  ### Output Signals
  - `code_generated` - Successfully generated code
  - `generation_progress` - Progress updates during generation
  - `generation_error` - Error during generation
  - `history_retrieved` - Generation history response
  - `template_applied` - Template-based generation complete
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_generator,
    name: "code_generator_agent",
    description: "Manages AI-powered code generation workflows",
    category: :code_generation,
    tags: [:code, :generation, :ai, :templates],
    schema: [
      # Generation history
      generation_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Templates
      templates: [type: :map, default: %{}],
      
      # Generation preferences
      default_style: [type: :string, default: "idiomatic"],
      default_include_tests: [type: :boolean, default: false],
      
      # Batch processing
      batch_queue: [type: {:list, :map}, default: []],
      batch_results: [type: :map, default: %{}],
      
      # Statistics
      generation_stats: [type: :map, default: %{
        total_generated: 0,
        by_style: %{},
        with_tests: 0,
        average_length: 0
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "generate_code"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      description: data["description"],
      signature: data["signature"],
      context: data["context"] || %{},
      style: data["style"] || agent.state.default_style,
      include_tests: data["include_tests"] || agent.state.default_include_tests
    }
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "user_id" => data["user_id"],
          "project_id" => data["project_id"],
          "timestamp" => DateTime.utc_now()
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "code.generation.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "started",
        description: params.description
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Store request metadata for history
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:generation_metadata],
      %{
        description: params.description,
        style: params.style,
        has_tests: params.include_tests
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_from_template"} = signal) do
    %{"data" => data} = signal
    template_name = data["template"]
    
    case Map.get(agent.state.templates, template_name) do
      nil ->
        signal = Jido.Signal.new!(%{
          type: "code.generation.error",
          source: "agent:#{agent.id}",
          data: %{
            request_id: data["request_id"],
            error: "Template not found: #{template_name}"
          }
        })
        emit_signal(agent, signal)
        {:ok, agent}
        
      template ->
        # Merge template with provided data
        description = build_template_description(template, data["variables"] || %{})
        
        # Generate using the expanded template
        generate_signal = %{
          "type" => "generate_code",
          "data" => Map.merge(data, %{
            "description" => description,
            "context" => Map.merge(template["context"] || %{}, data["context"] || %{}),
            "style" => data["style"] || template["style"] || agent.state.default_style
          })
        }
        
        signal = Jido.Signal.new!(%{
          type: "code.template.applied",
          source: "agent:#{agent.id}",
          data: %{
            template: template_name,
            request_id: data["request_id"]
          }
        })
        emit_signal(agent, signal)
        
        handle_tool_signal(agent, generate_signal)
    end
  end
  
  def handle_tool_signal(agent, %{"type" => "batch_generate"} = signal) do
    %{"data" => data} = signal
    batch_id = data["batch_id"] || "batch_#{System.unique_integer([:positive])}"
    requests = data["requests"] || []
    
    # Initialize batch tracking
    agent = put_in(agent.state.batch_results[batch_id], %{
      total: length(requests),
      completed: 0,
      results: [],
      started_at: DateTime.utc_now()
    })
    
    # Queue all requests
    agent = Enum.reduce(requests, agent, fn request, acc ->
      request_data = Map.merge(request, %{
        "batch_id" => batch_id,
        "request_id" => "#{batch_id}_#{request["id"] || System.unique_integer([:positive])}"
      })
      
      generate_signal = %{
        "type" => "generate_code",
        "data" => request_data
      }
      
      case handle_tool_signal(acc, generate_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.generation.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        total_requests: length(requests)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "refine_generation"} = signal) do
    %{"data" => data} = signal
    original_code = data["original_code"]
    refinements = data["refinements"] || []
    
    # Build refinement description
    refinement_desc = build_refinement_description(original_code, refinements)
    
    # Generate refined version
    generate_signal = %{
      "type" => "generate_code",
      "data" => Map.merge(data, %{
        "description" => refinement_desc,
        "context" => Map.merge(data["context"] || %{}, %{
          "refinement" => true,
          "original_code" => original_code
        })
      })
    }
    
    handle_tool_signal(agent, generate_signal)
  end
  
  def handle_tool_signal(agent, %{"type" => "get_generation_history"} = signal) do
    %{"data" => data} = signal
    
    # Filter history based on criteria
    filtered_history = filter_history(
      agent.state.generation_history,
      data["filter"] || %{}
    )
    
    # Paginate if requested
    {history, pagination} = paginate_history(
      filtered_history,
      data["page"] || 1,
      data["page_size"] || 20
    )
    
    signal = Jido.Signal.new!(%{
      type: "code.generation.history.retrieved",
      source: "agent:#{agent.id}",
      data: %{
        history: history,
        pagination: pagination,
        total_generated: agent.state.generation_stats.total_generated
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "save_template"} = signal) do
    %{"data" => data} = signal
    template_name = data["name"]
    
    template = %{
      "description" => data["description"],
      "variables" => data["variables"] || [],
      "context" => data["context"] || %{},
      "style" => data["style"],
      "created_at" => DateTime.utc_now()
    }
    
    agent = put_in(agent.state.templates[template_name], template)
    
    signal = Jido.Signal.new!(%{
      type: "code.template.saved",
      source: "agent:#{agent.id}",
      data: %{
        name: template_name,
        template: template
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle generation-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add generation metadata
    generation_metadata = request[:generation_metadata] || %{}
    
    result
    |> Map.put(:generated_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.merge(generation_metadata)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %{"type" => "tool_result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    %{"data" => data} = signal
    
    if data["result"] && not data["from_cache"] do
      # Update generation history
      agent = add_to_history(agent, data["result"])
      
      # Update statistics
      agent = update_generation_stats(agent, data["result"])
      
      # Check if part of batch
      if batch_id = get_in(data, ["result", "batch_id"]) do
        agent = update_batch_progress(agent, batch_id, data["result"])
      end
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.generated",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data["request_id"],
          code: data["result"]["code"],
          tests: data["result"]["tests"],
          metadata: %{
            style: data["result"]["style"],
            has_tests: not is_nil(data["result"]["tests"]),
            length: String.length(data["result"]["code"] || "")
          }
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
    "gen_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp build_template_description(template, variables) do
    description = template["description"] || ""
    
    # Replace variables in template
    Enum.reduce(variables, description, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
  
  defp build_refinement_description(original_code, refinements) do
    refinement_list = refinements
    |> Enum.map(fn r -> "- #{r}" end)
    |> Enum.join("\n")
    
    """
    Refine the following Elixir code with these improvements:
    
    #{refinement_list}
    
    Original code:
    ```elixir
    #{original_code}
    ```
    
    Generate an improved version that addresses all the refinements while maintaining the original functionality.
    """
  end
  
  defp add_to_history(agent, result) do
    history_entry = %{
      id: result[:request_id] || generate_request_id(),
      description: result[:description],
      code: result["code"],
      tests: result["tests"],
      style: result[:style],
      generated_at: result[:generated_at] || DateTime.utc_now()
    }
    
    # Add to history with size limit
    new_history = [history_entry | agent.state.generation_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.generation_history, new_history)
  end
  
  defp update_generation_stats(agent, result) do
    update_in(agent.state.generation_stats, fn stats ->
      code_length = String.length(result["code"] || "")
      style = result[:style] || "unknown"
      
      stats
      |> Map.update!(:total_generated, &(&1 + 1))
      |> Map.update!(:by_style, fn by_style ->
        Map.update(by_style, style, 1, &(&1 + 1))
      end)
      |> Map.update!(:with_tests, fn count ->
        if result["tests"], do: count + 1, else: count
      end)
      |> Map.update!(:average_length, fn avg ->
        total = stats.total_generated
        if total > 0 do
          ((avg * total) + code_length) / (total + 1)
        else
          code_length
        end
      end)
    end)
  end
  
  defp update_batch_progress(agent, batch_id, result) do
    update_in(agent.state.batch_results[batch_id], fn batch ->
      if batch do
        updated_batch = batch
        |> Map.update!(:completed, &(&1 + 1))
        |> Map.update!(:results, &([result | &1]))
        
        # Check if batch is complete
        if updated_batch.completed >= updated_batch.total do
          signal = Jido.Signal.new!(%{
            type: "code.generation.batch.completed",
            source: "agent:#{agent.id}",
            data: %{
              batch_id: batch_id,
              total: updated_batch.total,
              results: Enum.reverse(updated_batch.results),
              duration: DateTime.diff(DateTime.utc_now(), updated_batch.started_at)
            }
          })
          emit_signal(agent, signal)
        end
        
        updated_batch
      else
        batch
      end
    end)
  end
  
  defp filter_history(history, filters) do
    history
    |> filter_by_style(filters["style"])
    |> filter_by_date_range(filters["from"], filters["to"])
    |> filter_by_has_tests(filters["has_tests"])
    |> filter_by_search(filters["search"])
  end
  
  defp filter_by_style(history, nil), do: history
  defp filter_by_style(history, style) do
    Enum.filter(history, &(&1.style == style))
  end
  
  defp filter_by_date_range(history, nil, nil), do: history
  defp filter_by_date_range(history, from, to) do
    history
    |> then(fn h ->
      if from, do: Enum.filter(h, &(DateTime.compare(&1.generated_at, from) != :lt)), else: h
    end)
    |> then(fn h ->
      if to, do: Enum.filter(h, &(DateTime.compare(&1.generated_at, to) != :gt)), else: h
    end)
  end
  
  defp filter_by_has_tests(history, nil), do: history
  defp filter_by_has_tests(history, true) do
    Enum.filter(history, &(not is_nil(&1.tests)))
  end
  defp filter_by_has_tests(history, false) do
    Enum.filter(history, &is_nil(&1.tests))
  end
  
  defp filter_by_search(history, nil), do: history
  defp filter_by_search(history, search_term) do
    term = String.downcase(search_term)
    Enum.filter(history, fn entry ->
      String.contains?(String.downcase(entry.description || ""), term) or
      String.contains?(String.downcase(entry.code || ""), term)
    end)
  end
  
  defp paginate_history(history, page, page_size) do
    total = length(history)
    total_pages = ceil(total / page_size)
    offset = (page - 1) * page_size
    
    paginated = history
    |> Enum.drop(offset)
    |> Enum.take(page_size)
    
    pagination = %{
      page: page,
      page_size: page_size,
      total: total,
      total_pages: total_pages,
      has_next: page < total_pages,
      has_prev: page > 1
    }
    
    {paginated, pagination}
  end
end