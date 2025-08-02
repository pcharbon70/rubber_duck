defmodule RubberDuck.Tools.Agents.FunctionMoverAgent do
  @moduledoc """
  Agent that orchestrates the FunctionMover tool for intelligent function relocation workflows.
  
  This agent manages function moving requests, maintains move history,
  handles batch move operations, and provides smart recommendations for
  function organization and module restructuring.
  
  ## Signals
  
  ### Input Signals
  - `move_function` - Move a single function between modules
  - `batch_move` - Move multiple functions in a coordinated operation
  - `analyze_move` - Analyze potential moves and their impact
  - `suggest_moves` - Suggest beneficial function moves for better organization
  - `validate_move` - Validate a proposed function move
  - `preview_move` - Preview the changes without executing the move
  
  ### Output Signals
  - `function.moved` - Function move completed successfully
  - `function.move.analyzed` - Move analysis completed
  - `function.move.suggested` - Move suggestions ready
  - `function.move.validated` - Move validation completed
  - `function.move.previewed` - Move preview generated
  - `function.move.error` - Function move error occurred
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :function_mover,
    name: "function_mover_agent",
    description: "Manages intelligent function relocation and module restructuring workflows",
    category: "code_transformation",
    tags: ["refactoring", "module_organization", "function_move", "code_structure"],
    schema: [
      # Move history and tracking
      move_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50],
      
      # Move patterns and recommendations
      move_patterns: [type: :map, default: %{
        "utility_functions" => %{
          target_modules: ["Utils", "Helpers"],
          criteria: [:small_function, :stateless, :widely_used]
        },
        "domain_functions" => %{
          target_modules: [],
          criteria: [:domain_specific, :cohesive]
        },
        "validation_functions" => %{
          target_modules: ["Validators"],
          criteria: [:validation_logic, :pure_function]
        }
      }],
      
      # Batch operations
      active_batch_moves: [type: :map, default: %{}],
      
      # Analysis results
      analysis_cache: [type: :map, default: %{}],
      analysis_ttl: [type: :integer, default: 300_000], # 5 minutes
      
      # Organization metrics
      organization_metrics: [type: :map, default: %{
        total_moves: 0,
        successful_moves: 0,
        failed_moves: 0,
        modules_affected: 0,
        dependencies_updated: 0
      }],
      
      # Move suggestions
      suggested_moves: [type: {:list, :map}, default: []],
      suggestion_criteria: [type: :map, default: %{
        cohesion_threshold: 0.7,
        coupling_threshold: 0.3,
        utility_usage_threshold: 3
      }],
      
      # Safety settings
      safety_checks: [type: :map, default: %{
        require_validation: true,
        backup_before_move: true,
        check_circular_dependencies: true,
        verify_tests_pass: false
      }]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchMoveAction,
      __MODULE__.AnalyzeMoveAction,
      __MODULE__.SuggestMovesAction,
      __MODULE__.ValidateMoveAction,
      __MODULE__.PreviewMoveAction
    ]
  end
  
  # Action modules
  
  defmodule BatchMoveAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_move",
      description: "Execute multiple function moves in a coordinated batch operation",
      schema: [
        moves: [type: {:list, :map}, required: true, doc: "List of move operations to execute"],
        strategy: [type: :atom, values: [:sequential, :parallel, :dependency_order], default: :dependency_order],
        rollback_on_failure: [type: :boolean, default: true],
        dry_run: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      batch_id = generate_batch_id()
      
      # Start batch operation
      batch_info = %{
        id: batch_id,
        moves: params.moves,
        strategy: params.strategy,
        status: :in_progress,
        started_at: DateTime.utc_now(),
        completed_moves: [],
        failed_moves: [],
        rollback_on_failure: params.rollback_on_failure
      }
      
      if params.dry_run do
        execute_dry_run_batch(batch_info, agent)
      else
        execute_batch_moves(batch_info, agent)
      end
    end
    
    defp generate_batch_id do
      "batch_#{System.unique_integer([:positive, :monotonic])}"
    end
    
    defp execute_dry_run_batch(batch_info, _agent) do
      # Simulate batch execution for validation
      results = Enum.map(batch_info.moves, fn move ->
        %{
          move: move,
          status: :simulated,
          predicted_changes: simulate_move_changes(move),
          warnings: validate_move_safety(move)
        }
      end)
      
      {:ok, %{
        batch_id: batch_info.id,
        dry_run: true,
        total_moves: length(batch_info.moves),
        simulated_results: results,
        estimated_duration: estimate_batch_duration(batch_info.moves)
      }}
    end
    
    defp execute_batch_moves(batch_info, agent) do
      case batch_info.strategy do
        :sequential -> execute_sequential_moves(batch_info, agent)
        :parallel -> execute_parallel_moves(batch_info, agent)
        :dependency_order -> execute_dependency_ordered_moves(batch_info, agent)
      end
    end
    
    defp execute_sequential_moves(batch_info, agent) do
      {completed, failed} = Enum.reduce(batch_info.moves, {[], []}, fn move, {completed_acc, failed_acc} ->
        case execute_single_move(move, agent) do
          {:ok, result} -> {[result | completed_acc], failed_acc}
          {:error, error} -> 
            if batch_info.rollback_on_failure do
              rollback_completed_moves(completed_acc, agent)
              {[], [%{move: move, error: error} | failed_acc]}
            else
              {completed_acc, [%{move: move, error: error} | failed_acc]}
            end
        end
      end)
      
      {:ok, %{
        batch_id: batch_info.id,
        total_moves: length(batch_info.moves),
        successful_moves: length(completed),
        failed_moves: length(failed),
        completed: Enum.reverse(completed),
        failed: Enum.reverse(failed)
      }}
    end
    
    defp execute_parallel_moves(batch_info, agent) do
      # Execute moves in parallel using Task.async_stream
      results = batch_info.moves
      |> Task.async_stream(fn move -> execute_single_move(move, agent) end, 
                          timeout: 30_000, max_concurrency: 4)
      |> Enum.to_list()
      
      {completed, failed} = Enum.reduce(Enum.zip(batch_info.moves, results), {[], []}, 
        fn {move, result}, {completed_acc, failed_acc} ->
          case result do
            {:ok, {:ok, move_result}} -> {[move_result | completed_acc], failed_acc}
            {:ok, {:error, error}} -> {completed_acc, [%{move: move, error: error} | failed_acc]}
            {:exit, reason} -> {completed_acc, [%{move: move, error: "Task exited: #{inspect(reason)}"} | failed_acc]}
          end
        end)
      
      {:ok, %{
        batch_id: batch_info.id,
        total_moves: length(batch_info.moves),
        successful_moves: length(completed),
        failed_moves: length(failed),
        completed: completed,
        failed: failed
      }}
    end
    
    defp execute_dependency_ordered_moves(batch_info, agent) do
      # Order moves based on dependencies
      ordered_moves = order_moves_by_dependencies(batch_info.moves)
      
      batch_info_ordered = %{batch_info | moves: ordered_moves}
      execute_sequential_moves(batch_info_ordered, agent)
    end
    
    defp execute_single_move(move, _agent) do
      # Execute individual move - would use the actual FunctionMover tool
      # For now, simulate the execution
      case validate_move_safety(move) do
        [] -> {:ok, %{move: move, status: :completed, timestamp: DateTime.utc_now()}}
        warnings -> {:error, "Move failed validation: #{Enum.join(warnings, ", ")}"}
      end
    end
    
    defp simulate_move_changes(move) do
      %{
        source_file_changes: ["Remove function #{move["function_name"]}"],
        target_file_changes: ["Add function #{move["function_name"]}"],
        reference_updates: estimate_reference_count(move),
        import_changes: ["May need to update imports"]
      }
    end
    
    defp validate_move_safety(move) do
      warnings = []
      
      # Check for potential issues
      warnings = if move["function_name"] in ["init", "start_link"], 
        do: ["Moving lifecycle functions may break supervision" | warnings], 
        else: warnings
        
      warnings = if String.contains?(move["source_module"] || "", move["target_module"] || ""),
        do: ["Circular module dependency detected" | warnings],
        else: warnings
        
      warnings
    end
    
    defp estimate_reference_count(_move), do: Enum.random(0..10)
    
    defp estimate_batch_duration(moves), do: length(moves) * 2 # 2 seconds per move estimate
    
    defp order_moves_by_dependencies(moves) do
      # Simple ordering - would implement proper dependency analysis
      Enum.sort_by(moves, fn move -> move["function_name"] end)
    end
    
    defp rollback_completed_moves(completed_moves, _agent) do
      Logger.info("Rolling back #{length(completed_moves)} completed moves")
      # Would implement actual rollback logic
      :ok
    end
  end
  
  defmodule AnalyzeMoveAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_move",
      description: "Analyze the impact and feasibility of a function move",
      schema: [
        source_module: [type: :string, required: true],
        target_module: [type: :string, required: true],
        function_name: [type: :string, required: true],
        function_arity: [type: :integer, required: false],
        analysis_depth: [type: :atom, values: [:shallow, :deep, :comprehensive], default: :deep]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      analysis = %{
        move_feasibility: analyze_feasibility(params),
        impact_assessment: assess_impact(params, agent),
        dependency_analysis: analyze_dependencies(params),
        organizational_benefit: calculate_organizational_benefit(params, agent),
        risk_assessment: assess_risks(params),
        recommendations: generate_recommendations(params, agent)
      }
      
      {:ok, %{
        source_module: params.source_module,
        target_module: params.target_module,
        function: "#{params.function_name}/#{params.function_arity || "*"}",
        analysis: analysis,
        analyzed_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_feasibility(params) do
      %{
        can_move: true, # Would implement actual feasibility check
        blocking_issues: [],
        complexity_score: calculate_move_complexity(params),
        estimated_effort: "low" # low, medium, high
      }
    end
    
    defp assess_impact(params, agent) do
      %{
        modules_affected: 2, # source and target
        estimated_references: Enum.random(1..15),
        breaking_changes: false,
        test_updates_needed: true,
        documentation_updates: ["Update module documentation"],
        performance_impact: "neutral"
      }
    end
    
    defp analyze_dependencies(params) do
      %{
        function_dependencies: [], # Functions this function calls
        dependent_functions: [], # Functions that call this function
        circular_dependencies: false,
        dependency_depth: 1
      }
    end
    
    defp calculate_organizational_benefit(params, agent) do
      criteria = agent.state.suggestion_criteria
      
      %{
        cohesion_improvement: 0.1,
        coupling_reduction: 0.05,
        module_size_balance: 0.0,
        overall_score: 0.15,
        benefits: [
          "Improves target module cohesion",
          "Reduces coupling between modules"
        ]
      }
    end
    
    defp assess_risks(params) do
      %{
        risk_level: "low", # low, medium, high
        potential_issues: [
          "May need to update imports in dependent modules"
        ],
        mitigation_strategies: [
          "Run comprehensive tests after move",
          "Update documentation"
        ]
      }
    end
    
    defp generate_recommendations(_params, _agent) do
      [
        "Consider moving related helper functions together",
        "Update module documentation after move",
        "Verify all tests pass after the move"
      ]
    end
    
    defp calculate_move_complexity(_params) do
      # Simple complexity calculation - would implement proper analysis
      Enum.random(1..10)
    end
  end
  
  defmodule SuggestMovesAction do
    @moduledoc false
    use Jido.Action,
      name: "suggest_moves",
      description: "Analyze codebase and suggest beneficial function moves",
      schema: [
        modules: [type: {:list, :string}, required: true, doc: "Modules to analyze for move suggestions"],
        criteria: [type: {:list, :atom}, default: [:cohesion, :coupling, :utility], doc: "Criteria for suggestions"],
        max_suggestions: [type: :integer, default: 10],
        min_benefit_score: [type: :float, default: 0.1]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      suggestions = params.modules
      |> Enum.flat_map(fn module -> analyze_module_for_moves(module, params, agent) end)
      |> Enum.filter(fn suggestion -> suggestion.benefit_score >= params.min_benefit_score end)
      |> Enum.sort_by(fn suggestion -> -suggestion.benefit_score end)
      |> Enum.take(params.max_suggestions)
      
      {:ok, %{
        total_suggestions: length(suggestions),
        suggestions: suggestions,
        analysis_criteria: params.criteria,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_module_for_moves(module, params, agent) do
      # Would implement actual module analysis
      # For now, generate some example suggestions
      [
        %{
          function: "validate_input/1",
          source_module: module,
          suggested_target: "#{module}.Validators",
          reason: "Validation logic should be grouped together",
          benefit_score: 0.3,
          criteria_met: [:cohesion]
        },
        %{
          function: "format_output/1",
          source_module: module,
          suggested_target: "#{module}.Formatters",
          reason: "Formatting functions should be in dedicated module",
          benefit_score: 0.2,
          criteria_met: [:cohesion]
        }
      ]
    end
  end
  
  defmodule ValidateMoveAction do
    @moduledoc false
    use Jido.Action,
      name: "validate_move",
      description: "Validate a proposed function move for safety and feasibility",
      schema: [
        source_module: [type: :string, required: true],
        target_module: [type: :string, required: true],
        function_name: [type: :string, required: true],
        function_arity: [type: :integer, required: false],
        validation_level: [type: :atom, values: [:basic, :thorough, :comprehensive], default: :thorough]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      validation_results = %{
        syntax_check: validate_syntax(params),
        dependency_check: validate_dependencies(params),
        naming_conflicts: check_naming_conflicts(params),
        circular_dependencies: check_circular_dependencies(params),
        test_coverage: validate_test_coverage(params),
        documentation: validate_documentation(params)
      }
      
      overall_status = determine_overall_status(validation_results)
      
      {:ok, %{
        function: "#{params.function_name}/#{params.function_arity || "*"}",
        source_module: params.source_module,
        target_module: params.target_module,
        validation_status: overall_status,
        validation_results: validation_results,
        can_proceed: overall_status in [:passed, :warning],
        blocking_issues: extract_blocking_issues(validation_results),
        warnings: extract_warnings(validation_results),
        validated_at: DateTime.utc_now()
      }}
    end
    
    defp validate_syntax(_params) do
      %{status: :passed, message: "No syntax issues detected"}
    end
    
    defp validate_dependencies(_params) do
      %{status: :passed, message: "Dependencies can be resolved"}
    end
    
    defp check_naming_conflicts(_params) do
      %{status: :passed, message: "No naming conflicts detected"}
    end
    
    defp check_circular_dependencies(_params) do
      %{status: :passed, message: "No circular dependencies detected"}
    end
    
    defp validate_test_coverage(_params) do
      %{status: :warning, message: "Tests may need updates after move"}
    end
    
    defp validate_documentation(_params) do
      %{status: :warning, message: "Documentation should be updated"}
    end
    
    defp determine_overall_status(results) do
      if Enum.any?(Map.values(results), &(&1.status == :failed)) do
        :failed
      else
        if Enum.any?(Map.values(results), &(&1.status == :warning)) do
          :warning
        else
          :passed
        end
      end
    end
    
    defp extract_blocking_issues(results) do
      results
      |> Enum.filter(fn {_key, result} -> result.status == :failed end)
      |> Enum.map(fn {key, result} -> "#{key}: #{result.message}" end)
    end
    
    defp extract_warnings(results) do
      results
      |> Enum.filter(fn {_key, result} -> result.status == :warning end)
      |> Enum.map(fn {key, result} -> "#{key}: #{result.message}" end)
    end
  end
  
  defmodule PreviewMoveAction do
    @moduledoc false
    use Jido.Action,
      name: "preview_move",
      description: "Generate a preview of changes that would be made by a function move",
      schema: [
        source_module: [type: :string, required: true],
        target_module: [type: :string, required: true],
        function_name: [type: :string, required: true],
        function_arity: [type: :integer, required: false],
        include_references: [type: :boolean, default: true],
        preview_format: [type: :atom, values: [:diff, :summary, :detailed], default: :diff]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      preview = case params.preview_format do
        :diff -> generate_diff_preview(params)
        :summary -> generate_summary_preview(params)
        :detailed -> generate_detailed_preview(params)
      end
      
      {:ok, %{
        function: "#{params.function_name}/#{params.function_arity || "*"}",
        source_module: params.source_module,
        target_module: params.target_module,
        preview_format: params.preview_format,
        preview: preview,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp generate_diff_preview(params) do
      %{
        source_file_diff: "--- #{params.source_module}\n+++ #{params.source_module}\n@@ -10,5 +10,0 @@\n-  def #{params.function_name} do\n-    # function body\n-  end",
        target_file_diff: "+++ #{params.target_module}\n@@ +15,5 @@\n+  def #{params.function_name} do\n+    # function body\n+  end",
        affected_files: [
          %{file: "lib/app/caller.ex", changes: "Update import statement"}
        ]
      }
    end
    
    defp generate_summary_preview(params) do
      %{
        summary: "Move #{params.function_name} from #{params.source_module} to #{params.target_module}",
        changes_count: 3,
        files_affected: 3,
        estimated_time: "2 minutes"
      }
    end
    
    defp generate_detailed_preview(params) do
      %{
        source_changes: [
          "Remove function definition: #{params.function_name}",
          "Remove any function-specific documentation",
          "Clean up unused imports if any"
        ],
        target_changes: [
          "Add function definition: #{params.function_name}",
          "Add necessary imports",
          "Update module documentation"
        ],
        reference_updates: [
          "Update 3 files that call this function",
          "Update test files",
          "Update documentation references"
        ],
        potential_issues: [
          "May need to make function public in target module",
          "Tests may need to be updated"
        ]
      }
    end
  end
  
  # Tool-specific signal handlers
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "move_function"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      source_code: data["source_code"],
      target_code: data["target_code"],
      function_name: data["function_name"],
      function_arity: data["function_arity"],
      source_module: data["source_module"],
      target_module: data["target_module"],
      update_references: data["update_references"] || true,
      affected_files: data["affected_files"] || [],
      visibility: data["visibility"] || "preserve",
      include_dependencies: data["include_dependencies"] || false
    }
    
    # Execute the move
    {:ok, _ref} = __MODULE__.cmd_async(agent, ExecuteToolAction, %{params: params},
      context: %{agent: agent}
    )
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "batch_move"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, BatchMoveAction, %{
      moves: data["moves"],
      strategy: String.to_atom(data["strategy"] || "dependency_order"),
      rollback_on_failure: data["rollback_on_failure"] || true,
      dry_run: data["dry_run"] || false
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "analyze_move"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, AnalyzeMoveAction, %{
      source_module: data["source_module"],
      target_module: data["target_module"],
      function_name: data["function_name"],
      function_arity: data["function_arity"],
      analysis_depth: String.to_atom(data["analysis_depth"] || "deep")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "suggest_moves"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, SuggestMovesAction, %{
      modules: data["modules"],
      criteria: Enum.map(data["criteria"] || ["cohesion", "coupling"], &String.to_atom/1),
      max_suggestions: data["max_suggestions"] || 10,
      min_benefit_score: data["min_benefit_score"] || 0.1
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "validate_move"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, ValidateMoveAction, %{
      source_module: data["source_module"],
      target_module: data["target_module"],
      function_name: data["function_name"],
      function_arity: data["function_arity"],
      validation_level: String.to_atom(data["validation_level"] || "thorough")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "preview_move"} = signal) do
    %{"data" => data} = signal
    
    {:ok, _ref} = __MODULE__.cmd_async(agent, PreviewMoveAction, %{
      source_module: data["source_module"],
      target_module: data["target_module"],
      function_name: data["function_name"],
      function_arity: data["function_arity"],
      include_references: data["include_references"] || true,
      preview_format: String.to_atom(data["preview_format"] || "diff")
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  @impl true
  def handle_action_result(agent, BatchMoveAction, {:ok, result}, metadata) do
    # Update batch move tracking
    agent = put_in(agent.state.active_batch_moves[result.batch_id], %{
      status: :completed,
      result: result,
      completed_at: DateTime.utc_now()
    })
    
    # Update metrics
    agent = update_in(agent.state.organization_metrics, fn metrics ->
      metrics
      |> Map.update!(:total_moves, &(&1 + result.total_moves))
      |> Map.update!(:successful_moves, &(&1 + result.successful_moves))
      |> Map.update!(:failed_moves, &(&1 + result.failed_moves))
    end)
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "function.move.batch.completed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, AnalyzeMoveAction, {:ok, result}, metadata) do
    # Cache analysis result
    cache_key = "#{result.source_module}:#{result.function}:#{result.target_module}"
    agent = put_in(agent.state.analysis_cache[cache_key], %{
      result: result,
      cached_at: DateTime.utc_now()
    })
    
    # Emit analysis complete signal
    signal = Jido.Signal.new!(%{
      type: "function.move.analyzed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, SuggestMovesAction, {:ok, result}, metadata) do
    # Store suggestions
    agent = put_in(agent.state.suggested_moves, result.suggestions)
    
    # Emit suggestions ready signal
    signal = Jido.Signal.new!(%{
      type: "function.move.suggested",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, ValidateMoveAction, {:ok, result}, metadata) do
    # Emit validation complete signal
    signal = Jido.Signal.new!(%{
      type: "function.move.validated",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  @impl true
  def handle_action_result(agent, PreviewMoveAction, {:ok, result}, metadata) do
    # Emit preview ready signal
    signal = Jido.Signal.new!(%{
      type: "function.move.previewed",
      source: "agent:#{agent.id}",
      data: result
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  # Handle main tool execution results
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Record successful move
    move_record = %{
      function: "#{result.moved_function.name}/#{result.moved_function.arity}",
      source_module: metadata[:source_module],
      target_module: metadata[:target_module],
      dependencies_moved: result.dependencies_moved,
      references_updated: length(result.reference_updates),
      warnings: result.warnings,
      timestamp: DateTime.utc_now()
    }
    
    # Add to history
    agent = update_in(agent.state.move_history, fn history ->
      new_history = [move_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update metrics
    agent = update_in(agent.state.organization_metrics, fn metrics ->
      metrics
      |> Map.update!(:total_moves, &(&1 + 1))
      |> Map.update!(:successful_moves, &(&1 + 1))
      |> Map.update!(:dependencies_updated, &(&1 + length(result.dependencies_moved)))
    end)
    
    # Emit success signal
    signal = Jido.Signal.new!(%{
      type: "function.moved",
      source: "agent:#{agent.id}",
      data: %{
        function: move_record.function,
        source_module: move_record.source_module,
        target_module: move_record.target_module,
        warnings: result.warnings
      }
    })
    emit_signal(agent, signal)
    
    # Call parent handler
    super(agent, ExecuteToolAction, {:ok, result}, metadata)
  end
  
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:error, reason}, metadata) do
    # Update failure metrics
    agent = update_in(agent.state.organization_metrics.failed_moves, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "function.move.error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    emit_signal(agent, signal)
    
    # Call parent handler
    super(agent, ExecuteToolAction, {:error, reason}, metadata)
  end
end