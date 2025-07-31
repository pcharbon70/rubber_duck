defmodule RubberDuck.Tools.Agents.CodeRefactorerAgent do
  @moduledoc """
  Agent that orchestrates the CodeRefactorer tool for intelligent code refactoring workflows.
  
  This agent manages code refactoring requests, maintains refactoring patterns,
  handles batch refactoring operations, and tracks code quality improvements.
  
  ## Signals
  
  ### Input Signals
  - `refactor_code` - Refactor individual code snippets
  - `batch_refactor` - Refactor multiple code files
  - `suggest_refactorings` - Analyze code and suggest improvements
  - `apply_pattern` - Apply a specific refactoring pattern
  - `validate_refactoring` - Validate a proposed refactoring
  - `save_refactoring_pattern` - Save a custom refactoring pattern
  
  ### Output Signals
  - `code.refactored` - Refactoring completed
  - `code.refactoring.suggested` - Refactoring suggestions ready
  - `code.refactoring.batch.completed` - Batch refactoring done
  - `code.refactoring.validated` - Refactoring validation complete
  - `code.refactoring.pattern.saved` - Pattern saved successfully
  - `code.refactoring.error` - Refactoring error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :code_refactorer,
    name: "code_refactorer_agent",
    description: "Manages intelligent code refactoring workflows and pattern application",
    category: :code_transformation,
    tags: [:refactoring, :code_quality, :transformation, :patterns],
    schema: [
      # Refactoring preferences
      default_refactoring_type: [type: :string, default: "general"],
      default_style_guide: [type: :string, default: "credo"],
      preserve_comments_by_default: [type: :boolean, default: true],
      
      # Refactoring patterns
      refactoring_patterns: [type: :map, default: %{
        "extract_constants" => %{
          instruction: "Extract magic numbers and strings into named constants",
          type: "extract_function",
          priority: :high
        },
        "simplify_conditionals" => %{
          instruction: "Simplify complex conditional logic using pattern matching",
          type: "pattern_matching",
          priority: :medium
        },
        "improve_error_handling" => %{
          instruction: "Use proper {:ok, result} and {:error, reason} tuples",
          type: "error_handling",
          priority: :high
        }
      }],
      
      # Batch operations
      batch_refactorings: [type: :map, default: %{}],
      
      # Refactoring history
      refactoring_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 100],
      
      # Code quality tracking
      quality_improvements: [type: :map, default: %{}],
      
      # Validation settings
      auto_validate: [type: :boolean, default: true],
      validation_rules: [type: :map, default: %{
        "preserve_functionality" => true,
        "maintain_tests" => true,
        "check_complexity" => true
      }],
      
      # Statistics
      refactoring_stats: [type: :map, default: %{
        total_refactored: 0,
        by_type: %{},
        improvements_made: %{},
        average_complexity_reduction: 0,
        most_common_issues: %{}
      }]
    ]
  
  require Logger
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "refactor_code"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      code: data["code"],
      instruction: data["instruction"],
      refactoring_type: data["refactoring_type"] || agent.state.default_refactoring_type,
      preserve_comments: data["preserve_comments"] || agent.state.preserve_comments_by_default,
      style_guide: data["style_guide"] || agent.state.default_style_guide
    }
    
    # Create tool request
    tool_request = %{
      "type" => "tool_request",
      "data" => %{
        "params" => params,
        "request_id" => data["request_id"] || generate_request_id(),
        "metadata" => %{
          "file_path" => data["file_path"],
          "original_complexity" => calculate_code_complexity(data["code"]),
          "user_id" => data["user_id"],
          "auto_validate" => data["auto_validate"] || agent.state.auto_validate
        }
      }
    }
    
    # Emit progress
    signal = Jido.Signal.new!(%{
      type: "code.refactoring.progress",
      source: "agent:#{agent.id}",
      data: %{
        request_id: tool_request["data"]["request_id"],
        status: "analyzing",
        refactoring_type: params.refactoring_type,
        instruction: params.instruction
      }
    })
    emit_signal(agent, signal)
    
    # Forward to base handler
    handle_signal(agent, tool_request)
  end
  
  def handle_tool_signal(agent, %{"type" => "batch_refactor"} = signal) do
    %{"data" => data} = signal
    batch_id = data["batch_id"] || "batch_#{System.unique_integer([:positive])}"
    files = data["files"] || []
    
    # Initialize batch operation
    agent = put_in(agent.state.batch_refactorings[batch_id], %{
      id: batch_id,
      instruction: data["instruction"],
      total_files: length(files),
      completed: 0,
      results: %{},
      started_at: DateTime.utc_now()
    })
    
    # Process each file
    agent = Enum.reduce(files, agent, fn file, acc ->
      refactor_signal = %{
        "type" => "refactor_code",
        "data" => %{
          "code" => file["code"],
          "instruction" => data["instruction"],
          "refactoring_type" => data["refactoring_type"] || file["refactoring_type"],
          "file_path" => file["path"],
          "batch_id" => batch_id,
          "request_id" => "#{batch_id}_#{Path.basename(file["path"])}"
        }
      }
      
      case handle_tool_signal(acc, refactor_signal) do
        {:ok, updated_agent} -> updated_agent
        _ -> acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.refactoring.batch.started",
      source: "agent:#{agent.id}",
      data: %{
        batch_id: batch_id,
        total_files: length(files),
        instruction: data["instruction"]
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "suggest_refactorings"} = signal) do
    %{"data" => data} = signal
    code = data["code"]
    
    # Analyze code for potential improvements
    suggestions = analyze_code_for_improvements(code, agent.state.refactoring_patterns)
    
    # Create individual refactoring signals for each suggestion
    agent = Enum.reduce(Enum.with_index(suggestions), agent, fn {{pattern_name, pattern}, index}, acc ->
      if should_suggest?(pattern, data["threshold"] || :medium) do
        refactor_signal = %{
          "type" => "refactor_code",
          "data" => %{
            "code" => code,
            "instruction" => pattern.instruction,
            "refactoring_type" => pattern.type,
            "pattern_name" => pattern_name,
            "suggestion_id" => "suggest_#{data["request_id"]}_#{index}",
            "request_id" => "#{data["request_id"]}_suggestion_#{index}"
          }
        }
        
        case handle_tool_signal(acc, refactor_signal) do
          {:ok, updated_agent} -> updated_agent
          _ -> acc
        end
      else
        acc
      end
    end)
    
    signal = Jido.Signal.new!(%{
      type: "code.refactoring.suggested",
      source: "agent:#{agent.id}",
      data: %{
        request_id: data["request_id"] || generate_request_id(),
        total_suggestions: length(suggestions),
        suggestions: Enum.map(suggestions, fn {name, pattern} ->
          %{name: name, instruction: pattern.instruction, priority: pattern.priority}
        end)
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "apply_pattern"} = signal) do
    %{"data" => data} = signal
    pattern_name = data["pattern_name"]
    
    case agent.state.refactoring_patterns[pattern_name] do
      nil ->
        signal = Jido.Signal.new!(%{
          type: "code.refactoring.error",
          source: "agent:#{agent.id}",
          data: %{
            error: "Pattern '#{pattern_name}' not found",
            available_patterns: Map.keys(agent.state.refactoring_patterns)
          }
        })
        emit_signal(agent, signal)
        {:ok, agent}
        
      pattern ->
        # Apply the pattern
        refactor_signal = %{
          "type" => "refactor_code",
          "data" => Map.merge(data, %{
            "instruction" => pattern.instruction,
            "refactoring_type" => pattern.type,
            "pattern_applied" => pattern_name
          })
        }
        
        handle_tool_signal(agent, refactor_signal)
    end
  end
  
  def handle_tool_signal(agent, %{"type" => "validate_refactoring"} = signal) do
    %{"data" => data} = signal
    
    validation_result = validate_refactoring_changes(
      data["original_code"],
      data["refactored_code"],
      agent.state.validation_rules
    )
    
    signal = Jido.Signal.new!(%{
      type: "code.refactoring.validated",
      source: "agent:#{agent.id}",
      data: %{
        request_id: data["request_id"] || generate_request_id(),
        is_valid: validation_result.is_valid,
        validation_checks: validation_result.checks,
        warnings: validation_result.warnings,
        errors: validation_result.errors
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "save_refactoring_pattern"} = signal) do
    %{"data" => data} = signal
    pattern_name = data["name"]
    
    pattern = %{
      instruction: data["instruction"],
      type: data["type"] || "general",
      priority: String.to_atom(data["priority"] || "medium"),
      created_at: DateTime.utc_now(),
      created_by: data["user_id"]
    }
    
    agent = put_in(agent.state.refactoring_patterns[pattern_name], pattern)
    
    signal = Jido.Signal.new!(%{
      type: "code.refactoring.pattern.saved",
      source: "agent:#{agent.id}",
      data: %{
        pattern_name: pattern_name,
        pattern: pattern
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Override process_result to handle refactoring-specific processing
  
  @impl true
  def process_result(result, request) do
    # Add refactoring metadata
    metadata = request[:metadata] || %{}
    
    result
    |> Map.put(:refactored_at, DateTime.utc_now())
    |> Map.put(:request_id, request.id)
    |> Map.put(:original_complexity, metadata[:original_complexity])
    |> Map.put(:new_complexity, calculate_code_complexity(result["refactored_code"]))
  end
  
  # Override handle_signal to intercept tool results
  
  @impl true
  def handle_signal(agent, %Jido.Signal{type: "tool.result"} = signal) do
    # Let base handle the signal first
    {:ok, agent} = super(agent, signal)
    
    data = signal.data
    
    if data.result && not data[:from_cache] do
      # Auto-validate if enabled
      agent = if get_in(agent.state, [:active_requests, data.request_id, :metadata, :auto_validate]) do
        validate_and_emit(agent, data.result)
      else
        agent
      end
      
      # Check for special handling
      cond do
        # Handle batch refactoring
        batch_id = data.result[:batch_id] ->
          agent = update_refactoring_batch(agent, batch_id, data.result)
          
        # Handle suggestion result
        pattern_name = data.result[:pattern_name] ->
          agent = track_pattern_effectiveness(agent, pattern_name, data.result)
          
        # Handle regular refactoring
        true ->
          # Add to history
          agent = add_to_refactoring_history(agent, data.result)
          
          # Track quality improvements
          agent = track_quality_improvements(agent, data.result)
          
          # Update statistics
          agent = update_refactoring_stats(agent, data.result)
      end
      
      # Emit specialized signal
      signal = Jido.Signal.new!(%{
        type: "code.refactored",
        source: "agent:#{agent.id}",
        data: %{
          request_id: data.request_id,
          original_code: data.result["original_code"],
          refactored_code: data.result["refactored_code"],
          changes: data.result["changes"],
          refactoring_type: data.result["refactoring_type"],
          instruction: data.result["instruction"],
          complexity_reduction: calculate_complexity_reduction(data.result)
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
    "refactor_#{System.unique_integer([:positive, :monotonic])}"
  end
  
  defp calculate_code_complexity(code) do
    # Simple complexity calculation based on control structures
    indicators = ["if ", "case ", "cond ", "with ", "try ", "rescue ", "catch ", "&"]
    
    base_complexity = Enum.sum(Enum.map(indicators, fn indicator ->
      length(String.split(code, indicator)) - 1
    end))
    
    # Add complexity for function count
    function_count = length(String.split(code, "def ")) - 1
    
    base_complexity + function_count
  end
  
  defp analyze_code_for_improvements(code, patterns) do
    # Check which patterns might apply to this code
    Enum.filter(patterns, fn {_name, pattern} ->
      case pattern.type do
        "extract_function" -> String.contains?(code, ["do", "end"]) && String.length(code) > 100
        "pattern_matching" -> String.contains?(code, ["if ", "case "])
        "error_handling" -> String.contains?(code, ["raise", "throw", "!"]) || 
                            not String.contains?(code, ["{:ok", "{:error"])
        "simplify" -> calculate_code_complexity(code) > 10
        _ -> true
      end
    end)
  end
  
  defp should_suggest?(pattern, threshold) do
    priority_values = %{high: 3, medium: 2, low: 1}
    threshold_values = %{high: 3, medium: 2, low: 1}
    
    priority_values[pattern.priority] >= threshold_values[threshold]
  end
  
  defp validate_refactoring_changes(original_code, refactored_code, rules) do
    checks = %{}
    warnings = []
    errors = []
    
    # Check functionality preservation (simple AST comparison)
    if rules["preserve_functionality"] do
      original_ast = Code.string_to_quoted(original_code)
      refactored_ast = Code.string_to_quoted(refactored_code)
      
      checks = Map.put(checks, :ast_valid, elem(refactored_ast, 0) == :ok)
      
      if elem(refactored_ast, 0) == :error do
        errors = ["Refactored code has syntax errors" | errors]
      end
    end
    
    # Check complexity
    if rules["check_complexity"] do
      original_complexity = calculate_code_complexity(original_code)
      new_complexity = calculate_code_complexity(refactored_code)
      
      checks = Map.put(checks, :complexity_improved, new_complexity <= original_complexity)
      
      if new_complexity > original_complexity do
        warnings = ["Refactoring increased code complexity" | warnings]
      end
    end
    
    %{
      is_valid: length(errors) == 0,
      checks: checks,
      warnings: warnings,
      errors: errors
    }
  end
  
  defp validate_and_emit(agent, result) do
    validation_signal = %{
      "type" => "validate_refactoring",
      "data" => %{
        "original_code" => result["original_code"],
        "refactored_code" => result["refactored_code"],
        "request_id" => "validate_#{result[:request_id]}"
      }
    }
    
    case handle_tool_signal(agent, validation_signal) do
      {:ok, updated_agent} -> updated_agent
      _ -> agent
    end
  end
  
  defp update_refactoring_batch(agent, batch_id, result) do
    update_in(agent.state.batch_refactorings[batch_id], fn batch ->
      if batch do
        completed = batch.completed + 1
        file_path = result[:file_path] || "item_#{completed}"
        
        updated_batch = batch
        |> Map.put(:completed, completed)
        |> Map.put_in([:results, file_path], %{
          original: result["original_code"],
          refactored: result["refactored_code"],
          changes: result["changes"]
        })
        
        # Check if batch is complete
        if completed >= batch.total_files do
          signal = Jido.Signal.new!(%{
            type: "code.refactoring.batch.completed",
            source: "agent:#{Process.self()}",
            data: %{
              batch_id: batch_id,
              total_files: batch.total_files,
              instruction: batch.instruction,
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
  
  defp track_pattern_effectiveness(agent, pattern_name, result) do
    complexity_reduction = calculate_complexity_reduction(result)
    
    update_in(agent.state.refactoring_patterns[pattern_name], fn pattern ->
      if pattern do
        pattern
        |> Map.update(:usage_count, 1, &(&1 + 1))
        |> Map.update(:average_improvement, complexity_reduction, fn avg ->
          count = Map.get(pattern, :usage_count, 1)
          ((avg * (count - 1)) + complexity_reduction) / count
        end)
      else
        pattern
      end
    end)
  end
  
  defp calculate_complexity_reduction(result) do
    original = result[:original_complexity] || calculate_code_complexity(result["original_code"])
    new = result[:new_complexity] || calculate_code_complexity(result["refactored_code"])
    
    if original > 0 do
      ((original - new) / original) * 100
    else
      0.0
    end
  end
  
  defp add_to_refactoring_history(agent, result) do
    history_entry = %{
      id: result[:request_id],
      refactoring_type: result["refactoring_type"],
      instruction: result["instruction"],
      file_path: result[:file_path],
      complexity_reduction: calculate_complexity_reduction(result),
      changes_summary: summarize_changes(result["changes"]),
      refactored_at: result[:refactored_at] || DateTime.utc_now()
    }
    
    new_history = [history_entry | agent.state.refactoring_history]
    |> Enum.take(agent.state.max_history_size)
    
    put_in(agent.state.refactoring_history, new_history)
  end
  
  defp summarize_changes(changes) when is_map(changes) do
    %{
      lines_changed: changes["lines_changed"] || 0,
      functions_affected: changes["functions_affected"] || 0,
      patterns_applied: changes["patterns_applied"] || []
    }
  end
  defp summarize_changes(_), do: %{lines_changed: 0, functions_affected: 0, patterns_applied: []}
  
  defp track_quality_improvements(agent, result) do
    file_path = result[:file_path] || "unknown"
    
    improvement = %{
      complexity_reduction: calculate_complexity_reduction(result),
      refactoring_type: result["refactoring_type"],
      timestamp: DateTime.utc_now()
    }
    
    update_in(agent.state.quality_improvements, fn improvements ->
      Map.update(improvements, file_path, [improvement], &[improvement | &1])
    end)
  end
  
  defp update_refactoring_stats(agent, result) do
    update_in(agent.state.refactoring_stats, fn stats ->
      refactoring_type = result["refactoring_type"]
      complexity_reduction = calculate_complexity_reduction(result)
      
      # Extract common issues from the instruction
      issues = extract_issues_from_instruction(result["instruction"])
      
      stats
      |> Map.update!(:total_refactored, &(&1 + 1))
      |> Map.update!(:by_type, fn by_type ->
        Map.update(by_type, refactoring_type, 1, &(&1 + 1))
      end)
      |> Map.update!(:improvements_made, fn improvements ->
        Map.update(improvements, refactoring_type, [complexity_reduction], &[complexity_reduction | &1])
      end)
      |> Map.update!(:average_complexity_reduction, fn avg ->
        total = stats.total_refactored
        if total > 0 do
          ((avg * total) + complexity_reduction) / (total + 1)
        else
          complexity_reduction
        end
      end)
      |> Map.update!(:most_common_issues, fn common_issues ->
        Enum.reduce(issues, common_issues, fn issue, acc ->
          Map.update(acc, issue, 1, &(&1 + 1))
        end)
      end)
    end)
  end
  
  defp extract_issues_from_instruction(instruction) do
    issue_keywords = %{
      "magic" => "magic_numbers",
      "constant" => "missing_constants",
      "complex" => "complex_logic",
      "conditional" => "complex_conditionals",
      "error" => "poor_error_handling",
      "pattern" => "missing_pattern_matching",
      "readability" => "poor_readability",
      "performance" => "performance_issues"
    }
    
    instruction_lower = String.downcase(instruction)
    
    Enum.filter_map(
      issue_keywords,
      fn {keyword, _issue} -> String.contains?(instruction_lower, keyword) end,
      fn {_keyword, issue} -> issue end
    )
  end
end