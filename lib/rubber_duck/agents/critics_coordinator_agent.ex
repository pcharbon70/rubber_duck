defmodule RubberDuck.Agents.CriticsCoordinatorAgent do
  @moduledoc """
  Agent that coordinates validation critics for plans and tasks.
  
  This agent manages a registry of critics, distributes validation work,
  and aggregates results. It replaces the module-based Orchestrator with
  a signal-based coordination system.
  
  ## Signals
  
  ### Input Signals
  - `validate_target` - Request validation of a plan or task
    - Required: `target_type`, `target_id`, `target_data`
    - Optional: `critic_types`, `priority`, `timeout`
    
  - `register_critic` - Register a new critic agent
    - Required: `critic_id`, `critic_type`, `capabilities`
    
  - `unregister_critic` - Remove a critic from registry
    - Required: `critic_id`
  
  ### Output Signals
  - `validation_started` - Validation process begun
  - `critic_assigned` - Work assigned to specific critic
  - `validation_progress` - Progress updates
  - `validation_complete` - Final aggregated results
  - `validation_failed` - Error during validation
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "critics_coordinator_agent",
    description: "Coordinates validation critics for plans and tasks",
    schema: [
      active_validations: [type: :map, default: %{}],
      critic_registry: [type: :map, default: %{}],
      cache: [type: :map, default: %{}],
      cache_enabled: [type: :boolean, default: true],
      cache_ttl: [type: :integer, default: 3_600_000], # 1 hour
      parallel_execution: [type: :boolean, default: true],
      timeout: [type: :integer, default: 30_000],
      max_retries: [type: :integer, default: 3],
      metrics: [type: :map, default: %{
        total_validations: 0,
        cache_hits: 0,
        cache_misses: 0,
        critic_performance: %{}
      }]
    ]
  
  
  require Logger
  
  # Signal handlers
  
  @impl true
  def handle_signal(agent, %{"type" => "register_critic"} = signal) do
    critic_id = signal["critic_id"]
    
    if is_nil(critic_id) do
      Logger.error("Missing critic_id in register_critic signal")
      {:ok, agent}
    else
      critic_info = %{
        "critic_type" => signal["critic_type"] || "soft",
        "capabilities" => signal["capabilities"] || %{},
        "registered_at" => DateTime.utc_now()
      }
      
      updated_registry = Map.put(agent.state.critic_registry, critic_id, critic_info)
      updated_state = %{agent.state | critic_registry: updated_registry}
      
      Logger.info("Registered critic: #{critic_id}")
      
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  def handle_signal(agent, %{"type" => "unregister_critic"} = signal) do
    critic_id = signal["critic_id"]
    
    if is_nil(critic_id) do
      Logger.error("Missing critic_id in unregister_critic signal")
      {:ok, agent}
    else
      updated_registry = Map.delete(agent.state.critic_registry, critic_id)
      updated_state = %{agent.state | critic_registry: updated_registry}
      
      Logger.info("Unregistered critic: #{critic_id}")
      
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  def handle_signal(agent, %{"type" => "validate_target"} = signal) do
    target_type = signal["target_type"]
    target_id = signal["target_id"]
    target_data = signal["target_data"]
    
    if is_nil(target_type) or is_nil(target_id) or is_nil(target_data) do
      emit_validation_failed(agent, target_id, "Missing required fields")
      {:ok, agent}
    else
      # Check cache first
      cache_key = generate_cache_key(target_type, target_id, signal)
      
      case check_cache(agent, cache_key) do
        {:hit, cached_result} ->
          # Update metrics
          updated_metrics = Map.update(agent.state.metrics, :cache_hits, 1, &(&1 + 1))
          updated_state = %{agent.state | metrics: updated_metrics}
          
          # Emit cached result
          emit_validation_complete(agent, target_id, cached_result)
          
          {:ok, %{agent | state: updated_state}}
          
        :miss ->
          # Start new validation
          validation = %{
            target_type: target_type,
            target_id: target_id,
            target_data: target_data,
            status: :in_progress,
            started_at: DateTime.utc_now(),
            critics_assigned: [],
            results: [],
            cache_key: cache_key,
            options: Map.take(signal, ["critic_types", "priority", "timeout"])
          }
          
          # Update state
          updated_validations = Map.put(agent.state.active_validations, target_id, validation)
          updated_metrics = Map.update(agent.state.metrics, :cache_misses, 1, &(&1 + 1))
          updated_state = %{agent.state | 
            active_validations: updated_validations,
            metrics: updated_metrics
          }
          updated_agent = %{agent | state: updated_state}
          
          # Emit start signal
          emit_validation_started(updated_agent, target_id)
          
          # Start validation process
          spawn_validation_task(updated_agent, validation)
          
          {:ok, updated_agent}
      end
    end
  end
  
  def handle_signal(agent, signal) do
    # Let parent handle unknown signals
    super(agent, signal)
  end
  
  # Public functions for testing
  
  @doc """
  Aggregates validation results from multiple critics.
  """
  def aggregate_results(results) do
    hard_results = Enum.filter(results, fn r -> r["critic_type"] == "hard" end)
    soft_results = Enum.filter(results, fn r -> r["critic_type"] == "soft" end)
    
    overall_status = determine_overall_status(results)
    
    %{
      "overall_status" => overall_status,
      "hard_critics" => hard_results,
      "soft_critics" => soft_results,
      "blocking_issues" => find_blocking_issues(hard_results),
      "all_suggestions" => collect_suggestions(results),
      "summary" => generate_summary(results),
      "aggregated_at" => DateTime.utc_now()
    }
  end
  
  @doc """
  Selects appropriate critics based on criteria.
  """
  def select_critics(critic_registry, criteria) do
    target_type = criteria["target_type"]
    critic_types = criteria["critic_types"]
    
    critic_registry
    |> Enum.filter(fn {_id, critic} ->
      # Filter by target type support
      targets = get_in(critic, ["capabilities", "targets"]) || []
      supports_target = target_type in targets
      
      # Filter by critic type if specified
      type_matches = is_nil(critic_types) or critic["critic_type"] in critic_types
      
      supports_target and type_matches
    end)
    |> Enum.sort_by(fn {_id, critic} ->
      get_in(critic, ["capabilities", "priority"]) || 999
    end)
  end
  
  # Private functions
  
  defp generate_cache_key(target_type, target_id, signal) do
    options_hash = :erlang.phash2(Map.get(signal, "options", %{}))
    "#{target_type}:#{target_id}:#{options_hash}"
  end
  
  defp check_cache(%{state: %{cache_enabled: false}}, _), do: :miss
  
  defp check_cache(%{state: state}, cache_key) do
    cache = Map.get(state, :cache, %{})
    ttl = Map.get(state, :cache_ttl, 3_600_000) # Default 1 hour
    
    case Map.get(cache, cache_key) do
      nil -> 
        :miss
      %{"timestamp" => timestamp} = result ->
        age = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
        if age < ttl do
          {:hit, result}
        else
          :miss
        end
    end
  end
  
  defp spawn_validation_task(agent, validation) do
    Elixir.Task.start(fn ->
      try do
        # Select critics
        criteria = Map.merge(validation.options, %{
          "target_type" => validation.target_type
        })
        selected_critics = select_critics(agent.state.critic_registry, criteria)
        
        # Assign critics
        Enum.each(selected_critics, fn {critic_id, _critic} ->
          emit_critic_assigned(agent, validation.target_id, critic_id)
        end)
        
        # Execute validations
        results = if agent.state.parallel_execution do
          execute_parallel_validations(selected_critics, validation, agent)
        else
          execute_sequential_validations(selected_critics, validation, agent)
        end
        
        # Aggregate results
        aggregated = aggregate_results(results)
        
        # Cache results
        if agent.state.cache_enabled do
          cache_validation_result(agent, validation.cache_key, aggregated)
        end
        
        # Complete validation
        complete_validation(agent, validation.target_id, aggregated)
        
      rescue
        error ->
          Logger.error("Validation failed: #{inspect(error)}")
          emit_validation_failed(agent, validation.target_id, Exception.message(error))
      end
    end)
  end
  
  defp execute_parallel_validations(critics, validation, agent) do
    timeout = validation.options["timeout"] || agent.state.timeout
    
    tasks = Enum.map(critics, fn {critic_id, critic} ->
      Elixir.Task.async(fn ->
        execute_single_validation(critic_id, critic, validation, agent)
      end)
    end)
    
    tasks
    |> Elixir.Task.yield_many(timeout)
    |> Enum.map(fn {task, res} ->
      case res do
        {:ok, result} -> result
        {:exit, reason} ->
          %{
            "critic_id" => "unknown",
            "status" => "error",
            "message" => "Critic crashed: #{inspect(reason)}"
          }
        nil ->
          Elixir.Task.shutdown(task, :brutal_kill)
          %{
            "critic_id" => "unknown",
            "status" => "error",
            "message" => "Critic timed out"
          }
      end
    end)
  end
  
  defp execute_sequential_validations(critics, validation, agent) do
    Enum.map(critics, fn {critic_id, critic} ->
      execute_single_validation(critic_id, critic, validation, agent)
    end)
  end
  
  defp execute_single_validation(critic_id, critic, validation, agent) do
    start_time = System.monotonic_time(:millisecond)
    
    # In a real implementation, this would send a signal to the critic agent
    # For now, we'll return a mock result
    result = %{
      "critic_id" => critic_id,
      "critic_type" => critic["critic_type"],
      "status" => "passed",
      "message" => "Validation passed",
      "execution_time" => System.monotonic_time(:millisecond) - start_time
    }
    
    # Update performance metrics
    update_critic_performance(agent, critic_id, result["execution_time"])
    
    # Emit progress
    emit_validation_progress(agent, validation.target_id, critic_id, "completed")
    
    result
  end
  
  defp determine_overall_status(results) do
    statuses = Enum.map(results, & &1["status"])
    
    cond do
      "failed" in statuses -> "failed"
      "error" in statuses -> "error"
      "warning" in statuses -> "warning"
      true -> "passed"
    end
  end
  
  defp find_blocking_issues(hard_results) do
    hard_results
    |> Enum.filter(fn r -> r["status"] in ["failed", "error"] end)
    |> Enum.map(fn r ->
      %{
        "critic" => r["critic_id"],
        "message" => r["message"],
        "details" => r["details"]
      }
    end)
  end
  
  defp collect_suggestions(results) do
    results
    |> Enum.flat_map(fn r -> r["suggestions"] || [] end)
    |> Enum.uniq()
  end
  
  defp generate_summary(results) do
    total = length(results)
    passed = Enum.count(results, fn r -> r["status"] == "passed" end)
    failed = Enum.count(results, fn r -> r["status"] == "failed" end)
    warnings = Enum.count(results, fn r -> r["status"] == "warning" end)
    
    "Ran #{total} critics: #{passed} passed, #{failed} failed, #{warnings} warnings"
  end
  
  defp cache_validation_result(_agent, cache_key, _result) do
    # This would normally update the agent state through proper channels
    # For now we'll log it
    Logger.debug("Caching validation result for key: #{cache_key}")
  end
  
  defp complete_validation(agent, target_id, aggregated_result) do
    # Remove from active validations
    # This would be done through proper state management
    emit_validation_complete(agent, target_id, aggregated_result)
  end
  
  defp update_critic_performance(_agent, critic_id, execution_time) do
    # Update performance metrics
    # This would be done through proper state management
    Logger.debug("Critic #{critic_id} executed in #{execution_time}ms")
  end
  
  # Signal emission helpers
  
  defp emit_validation_started(agent, target_id) do
    emit_signal(agent, %{
      "type" => "validation_started",
      "target_id" => target_id,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_critic_assigned(agent, target_id, critic_id) do
    emit_signal(agent, %{
      "type" => "critic_assigned",
      "target_id" => target_id,
      "critic_id" => critic_id,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_validation_progress(agent, target_id, critic_id, status) do
    emit_signal(agent, %{
      "type" => "validation_progress",
      "target_id" => target_id,
      "critic_id" => critic_id,
      "status" => status,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_validation_complete(agent, target_id, result) do
    emit_signal(agent, %{
      "type" => "validation_complete",
      "target_id" => target_id,
      "result" => result,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_validation_failed(agent, target_id, reason) do
    emit_signal(agent, %{
      "type" => "validation_failed",
      "target_id" => target_id,
      "reason" => reason,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  # Health check
  
  @impl true
  def health_check(agent) do
    active_count = map_size(agent.state.active_validations)
    critic_count = map_size(agent.state.critic_registry)
    cache_size = map_size(agent.state.cache)
    
    cond do
      active_count > 100 ->
        {:unhealthy, %{
          reason: "Too many active validations",
          active_validations: active_count
        }}
        
      critic_count == 0 ->
        {:unhealthy, %{
          reason: "No critics registered",
          critic_count: 0
        }}
        
      true ->
        {:healthy, %{
          active_validations: active_count,
          registered_critics: critic_count,
          cache_entries: cache_size,
          metrics: agent.state.metrics
        }}
    end
  end
end