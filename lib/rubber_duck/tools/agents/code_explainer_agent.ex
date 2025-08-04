defmodule RubberDuck.Tools.Agents.CodeExplainerAgent do
  @moduledoc """
  Agent that orchestrates the CodeExplainer tool for intelligent code explanation workflows.
  
  This agent manages code explanation requests, maintains explanation preferences,
  handles batch explanations, and provides contextual documentation generation.
  
  ## Signals
  
  ### Input Signals
  - `explain_code` - Explain individual code snippets or functions
  - `generate_documentation` - Generate docstrings for modules/functions
  - `explain_project` - Explain multiple files or entire project structure
  - `explain_diff` - Explain code changes and their impact
  - `create_tutorial` - Create step-by-step learning content
  - `update_explanation_preferences` - Set audience/style preferences
  
  ### Output Signals
  - `code.explained` - Code explanation completed
  - `code.documentation.generated` - Documentation created
  - `code.tutorial.created` - Tutorial content ready
  - `code.diff.explained` - Code changes explained
  - `code.explanation.batch.completed` - Batch explanations done
  - `code.explanation.error` - Explanation error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_explainer,
    name: "code_explainer_agent",
    description: "Manages intelligent code explanation and documentation workflows",
    category: "documentation",
    tags: ["documentation", "explanation", "understanding", "learning"],
    schema: [
      # User preferences
      default_audience: [type: :string, default: "intermediate"],
      default_explanation_type: [type: :string, default: "comprehensive"],
      include_examples_by_default: [type: :boolean, default: true],
      
      # Explanation templates and styles
      explanation_templates: [type: :map, default: %{}],
      style_preferences: [type: :map, default: %{
        "beginner" => %{tone: "friendly", depth: "detailed", jargon: "minimal"},
        "intermediate" => %{tone: "professional", depth: "balanced", jargon: "moderate"},
        "expert" => %{tone: "technical", depth: "concise", jargon: "full"}
      }],
      
      # Documentation patterns
      doc_patterns: [type: :map, default: %{}],
      
      # Batch operations
      batch_explanations: [type: :map, default: %{}],
      
      # Learning paths and tutorials
      tutorials: [type: :map, default: %{}],
      learning_paths: [type: :map, default: %{}],
      
      # Explanation history and analytics
      explanation_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Statistics
      explanation_stats: [type: :map, default: %{
        total_explained: 0,
        by_type: %{},
        by_audience: %{},
        average_complexity: 0,
        most_common_patterns: %{}
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "explain_code"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters with agent preferences
    params = %{
      code: data["code"],
      explanation_type: data["explanation_type"] || agent.state.default_explanation_type,
      include_examples: data["include_examples"] || agent.state.include_examples_by_default,
      target_audience: data["target_audience"] || agent.state.default_audience,
      focus_areas: data["focus_areas"] || []
    }
    
    # Apply style preferences
    style = agent.state.style_preferences[params.target_audience] || %{}
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "code_type" => detect_code_type(data["code"]),
          "style_applied" => style,
          "user_id" => data["user_id"],
          "context" => data["context"] || %{}
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "code.explanation.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "analyzing",
        explanation_type: params.explanation_type,
        target_audience: params.target_audience
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Store explanation metadata
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:explanation_metadata],
      %{
        original_code: data["code"],
        explanation_type: params.explanation_type,
        target_audience: params.target_audience,
        started_at: DateTime.utc_now()
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_documentation"} = signal) do
    %{"data" => data} = signal
    
    # Force docstring generation mode
    doc_signal = %{
      "type" => "explain_code",
      "data" => Map.merge(data, %{
        "explanation_type" => "docstring",
        "include_examples" => data["include_examples"] || true,
        "focus_areas" => ["parameters", "return_values", "examples", "usage"]
      })
    }
    
    handle_tool_signal(agent, doc_signal)
  end
  
  def handle_tool_signal(agent, %{"type" => "explain_project"} = signal) do
    %{"data" => data} = signal
    project_path = data["project_path"] || File.cwd!()
    
    # Discover Elixir files
    files = discover_project_files(project_path, data["include_tests"] || false)
    batch_id = data["batch_id"] || "project_#{System.unique_integer([:positive])}"
    
    # Initialize batch operation
    agent = put_in(agent.state.batch_explanations[batch_id], %{
      id: batch_id,
      project_path: project_path,
      total_files: length(files),
      completed: 0,
      explanations: %{},
      started_at: DateTime.utc_now(),
      generate_overview: data["generate_overview"] || true
    })
    
    # Process each file
    agent = Enum.reduce(files, agent, fn file_path, acc ->
      case File.read(file_path) do
        {:ok, content} ->
          explain_signal = %{
            "type" => "explain_code",
            "data" => %{
              "code" => content,
              "explanation_type" => data["explanation_type"] || "summary",
              "target_audience" => data["target_audience"] || "intermediate",
              "batch_id" => batch_id,
              "file_path" => file_path,
              "request_id" => "#{batch_id}_#{Path.basename(file_path)}"
            }
          }
          
          case handle_tool_signal(acc, explain_signal) do
            {:ok, updated_agent} -> updated_agent
            _ -> acc
          end
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.explanation.batch.started",
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
  
  def handle_tool_signal(agent, %{"type" => "explain_diff"} = signal) do
    %{"data" => data} = signal
    
    # Build explanation for code changes
    diff_context = build_diff_context(data["old_code"], data["new_code"])
    
    params = %{
      code: data["new_code"],
      explanation_type: "comprehensive",
      target_audience: data["target_audience"] || agent.state.default_audience,
      focus_areas: ["changes", "impact", "reasoning"]
    }
    
    # Create tool request with diff context
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "diff_context" => diff_context,
          "old_code" => data["old_code"],
          "change_type" => data["change_type"] || "modification"
        }
      }
    }
    
    {:ok, agent} = handle_signal(agent, tool_request)
    
    # Mark as diff explanation
    agent = put_in(
      agent.state.active_requests[tool_request["data"]["request_id"]][:diff_metadata],
      %{
        old_code: data["old_code"],
        new_code: data["new_code"],
        change_type: data["change_type"]
      }
    )
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "create_tutorial"} = signal) do
    %{"data" => data} = signal
    tutorial_id = data["tutorial_id"] || "tutorial_#{System.unique_integer([:positive])}"
    
    # Break down code into learning steps
    steps = create_learning_steps(data["code"], data["difficulty"] || "beginner")
    
    # Initialize tutorial
    tutorial = %{
      id: tutorial_id,
      title: data["title"] || "Code Tutorial",
      code: data["code"],
      difficulty: data["difficulty"] || "beginner",
      steps: steps,
      current_step: 0,
      created_at: DateTime.utc_now()
    }
    
    agent = put_in(agent.state.tutorials[tutorial_id], tutorial)
    
    # Generate explanation for each step
    agent = Enum.reduce(Enum.with_index(steps), agent, fn {step, index}, acc ->
      step_signal = %{
        "type" => "explain_code",
        "data" => %{
          "code" => step.code,
          "explanation_type" => "beginner",
          "target_audience" => tutorial.difficulty,
          "focus_areas" => step.focus_areas,
          "tutorial_id" => tutorial_id,
          "step_number" => index + 1,
          "request_id" => "#{tutorial_id}_step_#{index + 1}"
        }
      }
      
      case handle_tool_signal(acc, step_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.tutorial.started",
      source: "agent:#{agent.id}",
      data: %{
        tutorial_id: tutorial_id,
        title: tutorial.title,
        total_steps: length(steps),
        difficulty: tutorial.difficulty
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "update_explanation_preferences"} = signal) do
    %{"data" => data} = signal
    
    # Update agent preferences
    agent = agent
    |> put_in([:state, :default_audience], data["default_audience"] || agent.state.default_audience)
    |> put_in([:state, :default_explanation_type], data["default_explanation_type"] || agent.state.default_explanation_type)
    |> put_in([:state, :include_examples_by_default], data["include_examples"] || agent.state.include_examples_by_default)
    
    # Update style preferences if provided
    agent = if style_updates = data["style_preferences"] do
      update_in(agent.state.style_preferences, fn prefs ->
        Map.merge(prefs, style_updates)
      end)
    else
      agent
    end
    
    signal = Jido.Signal.new!(%{
      type: "code.explanation.preferences.updated",
      source: "agent:#{agent.id}",
      data: %{
        default_audience: agent.state.default_audience,
        default_explanation_type: agent.state.default_explanation_type,
        include_examples_by_default: agent.state.include_examples_by_default
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle explanation-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add explanation metadata
    explanation_metadata = request[:explanation_metadata] || %{}
    
    result
    |> Map.put(:explained_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.merge(explanation_metadata)
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %Jido.Signal{type: "tool.result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    data = signal.data
    
    if data.result && not data[:from_cache] do
      # Check for special handling
      request_id = data.request_id
      
      agent = cond do
        # Handle diff explanation
        diff_metadata = get_in(agent.state.active_requests, [request_id, :diff_metadata]) ->
          handle_diff_explanation_result(agent, data.result, diff_metadata)
          
        # Handle tutorial step
        tutorial_id = data.result[:tutorial_id] ->
          handle_tutorial_step_result(agent, data.result, tutorial_id)
          
        # Handle batch explanation
        batch_id = data.result[:batch_id] ->
          update_explanation_batch(agent, batch_id, data.result)
          
        # Handle regular explanation
        true ->
          handle_regular_explanation_result(agent, data.result)
      end
      
      # Add to history
      agent = add_to_explanation_history(agent, data.result)
      
      # Update statistics
      agent = update_explanation_stats(agent, data.result)
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.explained",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data.request_id,
          explanation: data.result["explanation"],
          code: data.result["code"],
          type: data.result["type"],
          analysis: data.result["analysis"],
          examples: data.result[:examples]
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
  
  
  defp detect_code_type(code) do
    cond do
      String.contains?(code, "defmodule") -> "module"
      String.contains?(code, "def ") -> "function"
      String.contains?(code, "defp ") -> "private_function"
      String.contains?(code, "use GenServer") -> "genserver"
      String.contains?(code, "use Phoenix") -> "phoenix"
      String.contains?(code, "test ") -> "test"
      true -> "snippet"
    end
  end
  
  defp discover_project_files(project_path, include_tests) do
    patterns = if include_tests do
      ["**/*.ex", "**/*.exs"]
    else
      ["lib/**/*.ex", "lib/**/*.exs"]
    end
    
    Enum.flat_map(patterns, fn pattern ->
      project_path
      |> Path.join(pattern)
      |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.filter(&File.regular?/1)
  end
  
  defp build_diff_context(old_code, new_code) do
    # Simple diff analysis
    old_lines = String.split(old_code || "", "\n")
    new_lines = String.split(new_code || "", "\n")
    
    %{
      lines_added: length(new_lines) - length(old_lines),
      has_new_functions: String.contains?(new_code, "def ") && not String.contains?(old_code || "", "def "),
      has_deleted_functions: String.contains?(old_code || "", "def ") && not String.contains?(new_code, "def "),
      complexity_change: estimate_complexity_change(old_code, new_code)
    }
  end
  
  defp estimate_complexity_change(old_code, new_code) do
    old_complexity = count_complexity_indicators(old_code || "")
    new_complexity = count_complexity_indicators(new_code)
    
    case new_complexity - old_complexity do
      diff when diff > 2 -> "increased"
      diff when diff < -2 -> "decreased"
      _ -> "similar"
    end
  end
  
  defp count_complexity_indicators(code) do
    indicators = ["if ", "case ", "cond ", "with ", "try ", "rescue ", "catch "]
    Enum.sum(Enum.map(indicators, fn indicator ->
      length(String.split(code, indicator)) - 1
    end))
  end
  
  defp create_learning_steps(code, difficulty) do
    # Break code into logical learning steps
    lines = String.split(code, "\n")
    
    case difficulty do
      "beginner" ->
        create_beginner_steps(code, lines)
      "intermediate" ->
        create_intermediate_steps(code, lines)
      "expert" ->
        create_expert_steps(code, lines)
    end
  end
  
  defp create_beginner_steps(code, _lines) do
    # Very detailed steps for beginners
    [
      %{
        title: "Module Structure",
        code: extract_module_definition(code),
        focus_areas: ["module", "naming", "structure"],
        description: "Understanding the basic module structure"
      },
      %{
        title: "Function Definitions", 
        code: extract_function_definitions(code),
        focus_areas: ["functions", "parameters", "syntax"],
        description: "How functions are defined and structured"
      },
      %{
        title: "Function Logic",
        code: extract_function_bodies(code),
        focus_areas: ["logic", "flow", "implementation"],
        description: "Understanding what the functions actually do"
      }
    ]
    |> Enum.reject(&is_nil(&1.code))
  end
  
  defp create_intermediate_steps(code, _lines) do
    [
      %{
        title: "Code Overview",
        code: code,
        focus_areas: ["purpose", "architecture", "patterns"],
        description: "High-level understanding of the code"
      }
    ]
  end
  
  defp create_expert_steps(code, _lines) do
    [
      %{
        title: "Technical Analysis",
        code: code,
        focus_areas: ["performance", "patterns", "optimization"],
        description: "Technical deep-dive and analysis"
      }
    ]
  end
  
  defp extract_module_definition(code) do
    case Regex.run(~r/defmodule\s+[\w.]+\s+do/, code) do
      [match] -> match <> "\nend"
      _ -> nil
    end
  end
  
  defp extract_function_definitions(code) do
    Regex.scan(~r/def\s+\w+.*?do/, code)
    |> Enum.map(fn [match] -> match end)
    |> Enum.join("\n")
    |> case do
      "" -> nil
      result -> result
    end
  end
  
  defp extract_function_bodies(code) do
    # Extract function implementations (simplified)
    case Regex.run(~r/def\s+\w+.*?do\n(.*?)\n\s*end/s, code) do
      [_, body] -> String.trim(body)
      _ -> nil
    end
  end
  
  defp handle_diff_explanation_result(agent, result, diff_metadata) do
    signal = Jido.Signal.new!(%{
      type: "code.diff.explained",
      source: "agent:#{agent.id}",
      data: %{
        explanation: result["explanation"],
        old_code: diff_metadata.old_code,
        new_code: diff_metadata.new_code,
        change_type: diff_metadata.change_type,
        impact_analysis: result["analysis"]
      }
    })
    emit_signal(agent, signal)
    
    agent
  end
  
  defp handle_tutorial_step_result(agent, result, tutorial_id) do
    step_number = result[:step_number] || 1
    
    # Update tutorial with explanation
    agent = update_in(agent.state.tutorials[tutorial_id][:steps], fn steps ->
      List.update_at(steps, step_number - 1, fn step ->
        Map.put(step, :explanation, result[:explanation])
      end)
    end)
    
    # Check if tutorial is complete
    tutorial = agent.state.tutorials[tutorial_id]
    total_steps = length(tutorial.steps)
    explained_steps = Enum.count(tutorial.steps, &Map.has_key?(&1, :explanation))
    
    if explained_steps >= total_steps do
      signal = Jido.Signal.new!(%{
        type: "code.tutorial.created",
        source: "agent:#{agent.id}",
        data: %{
          tutorial_id: tutorial_id,
          title: tutorial.title,
          total_steps: total_steps,
          tutorial: tutorial
        }
      })
      emit_signal(agent, signal)
    end
    
    agent
  end
  
  defp update_explanation_batch(agent, batch_id, result) do
    update_in(agent.state.batch_explanations[batch_id], fn batch ->
      if batch do
        completed = batch.completed + 1
        
        updated_batch = batch
        |> Map.put(:completed, completed)
        |> put_in([:explanations, result[:file_path] || "snippet_#{completed}"], result[:explanation])
        
        # Check if batch is complete
        if completed >= batch.total_files do
          signal = Jido.Signal.new!(%{
            type: "code.explanation.batch.completed",
            source: "agent:#{self()}",
            data: %{
              batch_id: batch_id,
              project_path: batch.project_path,
              total_files: batch.total_files,
              explanations: updated_batch.explanations
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
  
  defp handle_regular_explanation_result(agent, result) do
    # Check if this should generate documentation
    if result["type"] == "docstring" do
      signal = Jido.Signal.new!(%{
        type: "code.documentation.generated",
        source: "agent:#{agent.id}",
        data: %{
          documentation: result["explanation"],
          code: result["code"],
          format: "elixir_docs"
        }
      })
      emit_signal(agent, signal)
    end
    
    agent
  end
  
  defp add_to_explanation_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      code_type: result[:code_type] || "unknown",
      explanation_type: result["type"],
      target_audience: result[:target_audience] || "intermediate",
      complexity: get_in(result, ["analysis", "complexity"]) || 0,
      explained_at: result[:explained_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.explanation_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.explanation_history, new_history)
  end
  
  defp update_explanation_stats(agent, result) do
    update_in(agent.state.explanation_stats, fn stats ->
      explanation_type = result["type"]
      audience = result[:target_audience] || "intermediate"
      complexity = get_in(result, ["analysis", "complexity"]) || 0
      
      stats
      |> Map.update!(:total_explained, &(&1 + 1))
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, explanation_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:by_audience, fn by_audience ->
        Map.update(by_audience, audience, 1, &(&1 + 1))
      end)
      |> Map.update!(:average_complexity, fn avg ->
        total = stats.total_explained
        if total > 0 do
          ((avg * total) + complexity) / (total + 1)
        else
          complexity
        end
      end)
    end)
  end
end