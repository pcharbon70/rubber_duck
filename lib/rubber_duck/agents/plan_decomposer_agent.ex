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
      persist_to_db: [type: :boolean, default: true],
      strategies: [type: {:list, :atom}, default: [:linear, :hierarchical, :tree_of_thought]],
      default_strategy: [type: :atom, default: :hierarchical],
      max_depth: [type: :integer, default: 5],
      llm_config: [type: :map, default: %{}],
      validation_enabled: [type: :boolean, default: true]
    ]
  
  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Planning.{Plan, Task, TaskDependency}
  alias RubberDuck.Agents.PlanDecomposer.{
    LinearDecomposer,
    HierarchicalDecomposer, 
    TreeOfThoughtDecomposer
  }
  
  require Logger
  require Ash.Query
  
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
    Elixir.Task.start(fn ->
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
    # Persist tasks if configured
    persisted_result = if agent.state[:persist_to_db] != false do
      case persist_decomposition(plan_id, result) do
        {:ok, persisted} -> 
          Map.put(result, :persisted, persisted)
        {:error, reason} ->
          Logger.error("Failed to persist decomposition: #{inspect(reason)}")
          Map.put(result, :persist_error, reason)
      end
    else
      result
    end
    
    emit_signal(agent, %{
      "type" => "decomposition_complete",
      "plan_id" => plan_id,
      "result" => persisted_result,
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
  
  # Persistence functions
  
  defp persist_decomposition(plan_id, %{tasks: tasks, dependencies: dependencies} = result) do
    # First, verify the plan exists and update its status
    with {:ok, plan} <- get_and_update_plan(plan_id),
         {:ok, created_tasks} <- create_tasks(tasks, plan_id),
         task_id_map <- create_task_id_mapping(tasks, created_tasks),
         {:ok, created_deps} <- create_dependencies(dependencies, task_id_map) do
      
      # Update plan metadata with decomposition info
      update_plan_metadata(plan, result, created_tasks)
      
      {:ok, %{
        tasks: created_tasks,
        dependencies: created_deps,
        task_count: length(created_tasks),
        dependency_count: length(created_deps),
        plan_id: plan.id
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Decomposition persistence failed: #{inspect(e)}")
      {:error, {:persistence_exception, e}}
  end
  
  defp get_and_update_plan(plan_id) do
    case Ash.get(Plan, plan_id, domain: RubberDuck.Planning) do
      {:ok, plan} ->
        # Update plan status to indicate decomposition is complete
        case Ash.update(plan, %{
          status: :ready,
          metadata: Map.merge(plan.metadata || %{}, %{
            "decomposed_at" => DateTime.utc_now(),
            "decomposition_complete" => true
          })
        }, domain: RubberDuck.Planning) do
          {:ok, updated_plan} -> {:ok, updated_plan}
          error -> error
        end
        
      error -> 
        Logger.error("Failed to find plan #{plan_id}: #{inspect(error)}")
        error
    end
  end
  
  defp create_tasks(tasks, plan_id) do
    prepared_tasks = prepare_tasks_for_persistence(tasks, plan_id)
    
    Ash.bulk_create(prepared_tasks, Task, :create,
      return_records?: true,
      return_errors?: true,
      stop_on_error?: true,
      authorize?: false,
      domain: RubberDuck.Planning
    )
    |> case do
      %{records: created_tasks, errors: []} ->
        {:ok, created_tasks}
        
      %{errors: errors} ->
        {:error, {:task_creation_failed, errors}}
    end
  end
  
  defp update_plan_metadata(plan, decomposition_result, created_tasks) do
    metadata_update = %{
      "decomposition_strategy" => decomposition_result.strategy,
      "total_tasks_created" => length(created_tasks),
      "complexity_distribution" => calculate_complexity_distribution(created_tasks),
      "last_decomposed_at" => DateTime.utc_now()
    }
    
    Ash.update(plan, %{
      metadata: Map.merge(plan.metadata || %{}, metadata_update)
    }, domain: RubberDuck.Planning)
  end
  
  defp calculate_complexity_distribution(tasks) do
    tasks
    |> Enum.group_by(& &1.complexity)
    |> Enum.map(fn {complexity, tasks} -> {complexity, length(tasks)} end)
    |> Map.new()
  end
  
  defp prepare_tasks_for_persistence(tasks, plan_id) do
    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} ->
      %{
        plan_id: plan_id,
        name: task["name"] || "Task #{index + 1}",
        description: task["description"] || "",
        complexity: to_complexity_atom(task["complexity"]),
        position: task["position"] || index,
        number: "#{index + 1}",
        success_criteria: task["success_criteria"] || %{},
        validation_rules: task["validation_rules"] || %{},
        metadata: Map.merge(
          task["metadata"] || %{},
          %{
            "decomposer_task_id" => task["id"] || "task_#{index}",
            "phase_name" => task["phase_name"],
            "is_critical" => task["is_critical"] || false
          }
        )
      }
    end)
  end
  
  defp create_task_id_mapping(original_tasks, created_tasks) do
    # Map from original task IDs to database task IDs
    created_by_position = created_tasks
    |> Enum.map(fn task -> {task.position, task.id} end)
    |> Map.new()
    
    original_tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} ->
      original_id = task["id"] || "task_#{index}"
      position = task["position"] || index
      db_id = Map.get(created_by_position, position)
      {original_id, db_id}
    end)
    |> Map.new()
  end
  
  defp create_dependencies(dependencies, task_id_map) do
    dependency_attrs = dependencies
    |> Enum.map(fn %{from: from_id, to: to_id} ->
      from_db_id = Map.get(task_id_map, from_id)
      to_db_id = Map.get(task_id_map, to_id)
      
      if from_db_id && to_db_id do
        %{
          dependency_id: from_db_id,
          task_id: to_db_id
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    # Create dependencies
    created = dependency_attrs
    |> Enum.map(fn attrs ->
      # Try using Ash.Changeset to see accepted attributes
      changeset = TaskDependency
      |> Ash.Changeset.for_create(:create, attrs, domain: RubberDuck.Planning)
      
      case Ash.create(changeset) do
        {:ok, dep} -> dep
        {:error, reason} -> 
          Logger.error("Failed to create dependency: #{inspect(reason)}")
          Logger.error("Attempted attrs: #{inspect(attrs)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    
    if length(created) == length(dependency_attrs) do
      {:ok, created}
    else
      {:error, :some_dependencies_failed}
    end
  end
  
  defp to_complexity_atom(complexity) when is_atom(complexity), do: complexity
  defp to_complexity_atom(complexity) when is_binary(complexity) do
    case complexity do
      "trivial" -> :trivial
      "simple" -> :simple
      "medium" -> :medium
      "complex" -> :complex
      "very_complex" -> :very_complex
      _ -> :medium
    end
  end
  defp to_complexity_atom(_), do: :medium
  
  # Test helpers - only available in test environment
  if Mix.env() == :test do
    @doc false
    def test_persist_decomposition(plan_id, result) do
      persist_decomposition(plan_id, result)
    end
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