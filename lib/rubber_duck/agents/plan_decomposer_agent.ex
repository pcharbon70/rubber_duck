defmodule RubberDuck.Agents.PlanDecomposerAgent do
  @moduledoc """
  Agent that decomposes high-level plans into actionable tasks.
  
  This agent transforms complex requests into structured task hierarchies using
  multiple decomposition strategies (linear, hierarchical, tree-of-thought).
  It integrates with the LLM service for intelligent decomposition and provides
  caching for repeated patterns.
  
  ## Signals
  
  ### Input Signals
  - `decompose_plan` - Initiates plan decomposition
    - Required: `plan_id`, `query`
    - Optional: `strategy`, `context`, `constraints`
  
  ### Output Signals  
  - `decomposition_progress` - Reports progress updates
  - `decomposition_complete` - Returns decomposed tasks
  - `decomposition_failed` - Reports errors
  
  ## State
  - `active_decompositions` - Currently processing decompositions
  - `cache` - Cached decomposition results
  - `strategies` - Available decomposition strategies
  - `default_strategy` - Strategy to use when not specified
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "plan_decomposer_agent",
    description: "Decomposes high-level plans into actionable tasks",
    schema: [
      active_decompositions: [type: :map, default: %{}],
      cache: [type: :map, default: %{}],
      cache_enabled: [type: :boolean, default: true],
      strategies: [type: {:list, :atom}, default: [:linear, :hierarchical, :tree_of_thought]],
      default_strategy: [type: :atom, default: :hierarchical],
      max_depth: [type: :integer, default: 5],
      llm_config: [type: :map, default: %{}],
      validation_enabled: [type: :boolean, default: true]
    ]
  
  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Agents.PlanDecomposer.{
    LinearDecomposer,
    HierarchicalDecomposer, 
    TreeOfThoughtDecomposer
  }
  
  require Logger
  
  # Signal handlers
  
  @impl true
  def handle_signal(agent, %{"type" => "decompose_plan"} = signal) do
    plan_id = signal["plan_id"]
    query = signal["query"]
    
    if is_nil(plan_id) or is_nil(query) do
      emit_decomposition_failed(agent, plan_id, "Missing required fields: plan_id or query")
      {:ok, agent}
    else
      # Check cache first
      cache_key = generate_cache_key(query, signal)
      
      case check_cache(agent, cache_key) do
        {:hit, cached_result} ->
          emit_decomposition_complete(agent, plan_id, cached_result)
          {:ok, agent}
          
        :miss ->
          # Start new decomposition
          decomposition = %{
            plan_id: plan_id,
            query: query,
            context: signal["context"] || %{},
            constraints: signal["constraints"] || %{},
            strategy: determine_strategy(signal, agent.state),
            started_at: DateTime.utc_now(),
            cache_key: cache_key
          }
          
          # Track active decomposition
          updated_state = Map.put(agent.state, :active_decompositions, 
            Map.put(agent.state.active_decompositions, plan_id, decomposition))
          updated_agent = %{agent | state: updated_state}
          
          # Start async decomposition
          spawn_decomposition_task(updated_agent, decomposition)
          
          {:ok, updated_agent}
      end
    end
  end
  
  def handle_signal(agent, signal) do
    # Let parent handle unknown signals
    super(agent, signal)
  end
  
  # Private functions
  
  defp determine_strategy(%{"strategy" => strategy}, state) when is_binary(strategy) do
    strategy_atom = try do
      String.to_existing_atom(strategy)
    rescue
      _ -> nil
    end
    
    if strategy_atom in state.strategies do
      strategy_atom
    else
      state.default_strategy
    end
  end
  
  defp determine_strategy(_, state), do: state.default_strategy
  
  defp generate_cache_key(query, signal) do
    # Create a deterministic cache key from query and relevant context
    context_hash = :erlang.phash2({
      signal["context"] || %{},
      signal["constraints"] || %{},
      signal["strategy"]
    })
    
    "decompose:#{:erlang.phash2(query)}:#{context_hash}"
  end
  
  defp check_cache(%{state: %{cache_enabled: false}}, _), do: :miss
  
  defp check_cache(%{state: %{cache: cache}}, cache_key) do
    case Map.get(cache, cache_key) do
      nil -> 
        :miss
      {result, timestamp} ->
        # Cache entries expire after 1 hour
        if DateTime.diff(DateTime.utc_now(), timestamp, :hour) < 1 do
          {:hit, result}
        else
          :miss
        end
    end
  end
  
  defp spawn_decomposition_task(agent, decomposition) do
    # Since we're in an agent context, we need to handle this differently
    # We'll perform the decomposition synchronously for now
    Task.start(fn ->
      try do
        # Emit progress signal
        emit_signal(agent, %{
          "type" => "decomposition_progress",
          "plan_id" => decomposition.plan_id,
          "status" => "started",
          "strategy" => decomposition.strategy
        })
        
        # Perform decomposition
        result = perform_decomposition(decomposition, agent.state)
        
        # For now, we'll emit completion directly
        # In a real implementation, we'd update state through proper agent channels
        emit_decomposition_complete(agent, decomposition.plan_id, result)
        
      rescue
        error ->
          Logger.error("Decomposition failed: #{inspect(error)}")
          emit_decomposition_failed(agent, decomposition.plan_id, Exception.message(error))
      end
    end)
  end
  
  defp perform_decomposition(decomposition, state) do
    # Prepare input for decomposition
    input = %{
      query: decomposition.query,
      context: decomposition.context,
      constraints: decomposition.constraints
    }
    
    # Execute decomposition based on strategy
    {:ok, raw_tasks} = case decomposition.strategy do
      :linear -> 
        LinearDecomposer.decompose(input, state)
      :hierarchical -> 
        HierarchicalDecomposer.decompose(input, state)
      :tree_of_thought -> 
        TreeOfThoughtDecomposer.decompose(input, state)
    end
    
    # Refine and validate tasks
    {:ok, refined_tasks} = refine_tasks(raw_tasks, state)
    {:ok, dependencies} = build_dependencies(refined_tasks, state)
    
    # Run validation if enabled
    validation_result = if state.validation_enabled do
      validate_decomposition(refined_tasks, dependencies, state)
    else
      %{valid: true}
    end
    
    %{
      tasks: refined_tasks,
      dependencies: dependencies,
      strategy: decomposition.strategy,
      metadata: %{
        total_tasks: length(refined_tasks),
        validation: validation_result,
        decomposed_at: DateTime.utc_now()
      }
    }
  end
  
  defp refine_tasks(tasks, state) do
    refined = Enum.map(tasks, fn task ->
      # Add any missing required fields
      task
      |> ensure_field("id", fn -> "task_#{:rand.uniform(1_000_000)}" end)
      |> ensure_field("status", fn -> "pending" end)
      |> ensure_field("complexity", fn -> estimate_complexity(task, state) end)
      |> ensure_field("success_criteria", fn -> generate_success_criteria(task, state) end)
    end)
    
    {:ok, refined}
  end
  
  defp ensure_field(task, field, generator) do
    if Map.has_key?(task, field) && task[field] != nil && task[field] != "" do
      task
    else
      Map.put(task, field, generator.())
    end
  end
  
  defp estimate_complexity(task, _state) do
    # Simple heuristic for now
    description_length = String.length(task["description"] || "")
    
    cond do
      description_length < 50 -> "simple"
      description_length < 150 -> "medium"
      description_length < 300 -> "complex"
      true -> "very_complex"
    end
  end
  
  defp generate_success_criteria(task, _state) do
    %{
      "criteria" => [
        "#{task["name"]} completed successfully",
        "All requirements met",
        "Tests passing"
      ]
    }
  end
  
  defp build_dependencies(tasks, _state) do
    # Extract explicit dependencies
    deps = tasks
    |> Enum.flat_map(fn task ->
      task_id = task["id"]
      
      (task["depends_on"] || [])
      |> Enum.map(fn dep_id ->
        %{from: dep_id, to: task_id}
      end)
    end)
    
    {:ok, deps}
  end
  
  defp validate_decomposition(tasks, dependencies, state) do
    # Create a mock plan for validation
    plan = %{
      tasks: tasks,
      dependencies: dependencies
    }
    
    orchestrator = Orchestrator.new(
      cache_enabled: false,
      config: state.llm_config
    )
    
    case Orchestrator.validate(orchestrator, plan) do
      {:ok, results} ->
        aggregated = Orchestrator.aggregate_results(results)
        %{
          valid: aggregated.summary != :failed,
          summary: aggregated.summary,
          issues: aggregated.blocking_issues
        }
    end
  end
  
  defp emit_decomposition_complete(agent, plan_id, result) do
    emit_signal(agent, %{
      "type" => "decomposition_complete",
      "plan_id" => plan_id,
      "result" => result,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_decomposition_failed(agent, plan_id, reason) do
    emit_signal(agent, %{
      "type" => "decomposition_failed", 
      "plan_id" => plan_id,
      "reason" => reason,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  
  # Health check
  
  @impl true
  def health_check(agent) do
    active_count = map_size(agent.state.active_decompositions)
    cache_size = map_size(agent.state.cache)
    
    if active_count > 100 do
      {:unhealthy, %{
        reason: "Too many active decompositions",
        active_count: active_count,
        cache_size: cache_size
      }}
    else
      {:healthy, %{
        active_decompositions: active_count,
        cache_entries: cache_size,
        strategies_available: agent.state.strategies
      }}
    end
  end
end