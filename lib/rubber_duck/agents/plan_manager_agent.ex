defmodule RubberDuck.Agents.PlanManagerAgent do
  @moduledoc """
  Plan Manager Agent responsible for managing the lifecycle of development plans.
  
  This agent provides:
  - Plan creation and validation
  - State management and transitions
  - Concurrency control with locking
  - Query interface for plan discovery
  - Metrics collection and reporting
  
  ## Signal Interface
  
  ### Input Signals
  - `{:create_plan, params}` - Create a new plan
  - `{:update_plan, params}` - Update existing plan
  - `{:transition_plan, params}` - Transition plan state
  - `{:query_plans, params}` - Query plans with filters
  - `{:lock_plan, plan_id}` - Acquire plan lock
  - `{:unlock_plan, plan_id}` - Release plan lock
  
  ### Output Signals
  - `{:plan_created, data}` - Plan creation notification
  - `{:plan_updated, data}` - Plan update notification
  - `{:plan_transitioned, data}` - State transition notification
  - `{:plans_found, data}` - Query results
  - `{:metrics_updated, data}` - Metrics update
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "plan_manager",
    description: "Manages development plan lifecycle and state",
    tags: ["plan_management", "coordination", "persistence"],
    schema: [
      plans: [type: {:map, :string, :map}, default: %{}],
      active_plans: [type: {:list, :string}, default: []],
      archived_plans: [type: {:list, :string}, default: []],
      metrics: [type: :map, default: %{
        total_created: 0,
        total_completed: 0,
        total_failed: 0,
        average_duration: 0,
        active_count: 0
      }],
      locks: [type: {:map, :string, :map}, default: %{}],
      query_cache: [type: :map, default: %{}],
      last_cleanup: [type: {:or, [:string, nil]}, default: nil]
    ]
  
  require Logger
  # alias RubberDuck.Planning.Plan # Not used currently
  
  # Plan states
  @draft_state :draft
  # @active_state :active
  # @paused_state :paused
  # @completed_state :completed
  # @failed_state :failed
  # @archived_state :archived
  
  # @valid_states [@draft_state, @active_state, @paused_state, @completed_state, @failed_state, @archived_state]
  @valid_transitions %{
    draft: [:active, :archived],
    active: [:paused, :completed, :failed],
    paused: [:active, :failed, :archived],
    completed: [:archived],
    failed: [:archived],
    archived: []
  }
  
  # Configuration
  @max_active_plans Application.compile_env(:rubber_duck, [__MODULE__, :max_active_plans], 100)
  # @plan_timeout Application.compile_env(:rubber_duck, [__MODULE__, :plan_timeout], :timer.hours(24))
  @cleanup_interval Application.compile_env(:rubber_duck, [__MODULE__, :cleanup_interval], :timer.hours(1))
  @lock_timeout Application.compile_env(:rubber_duck, [__MODULE__, :lock_timeout], :timer.minutes(5))
  
  ## Lifecycle Callbacks
  
  @impl true
  def pre_init(config) do
    # Validate configuration
    with :ok <- validate_config(config) do
      # Initialize with empty plans if not provided
      config = Map.put_new(config, :plans, %{})
      {:ok, config}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def post_init(agent) do
    # Schedule cleanup task
    schedule_cleanup()
    
    # Subscribe to relevant signals
    agent = agent
    |> subscribe_to_signals(%{"type" => "plan_request"})
    |> subscribe_to_signals(%{"type" => "plan_update"})
    |> subscribe_to_signals(%{"type" => "plan_query"})
    
    # Recover any persisted state
    agent = recover_state(agent)
    
    {:ok, agent}
  end
  
  @impl true
  def on_before_run(agent) do
    # Clean up expired locks before processing
    agent = cleanup_expired_locks(agent)
    
    # Run parent implementation
    super(agent)
  end
  
  @impl true
  def on_after_run(agent, result, metadata) do
    # Persist state after successful operations
    case result do
      {:ok, _} -> persist_state(agent)
      _ -> :ok
    end
    
    # Run parent implementation
    super(agent, result, metadata)
  end
  
  @impl true
  def health_check(agent) do
    active_count = length(agent.state.active_plans)
    lock_count = map_size(agent.state.locks)
    
    cond do
      active_count > @max_active_plans ->
        {:unhealthy, %{reason: "Too many active plans", count: active_count, max: @max_active_plans}}
        
      lock_count > div(@max_active_plans, 2) ->
        {:unhealthy, %{reason: "Too many locks held", count: lock_count}}
        
      true ->
        {:healthy, %{
          total_plans: map_size(agent.state.plans),
          active_plans: active_count,
          archived_plans: length(agent.state.archived_plans),
          locks_held: lock_count,
          metrics: agent.state.metrics
        }}
    end
  end
  
  ## Signal Handlers
  
  @impl Jido.Agent
  def handle_signal(agent, %{"type" => "create_plan"} = signal) do
    params = signal["params"] || %{}
    
    with {:ok, plan_id} <- generate_plan_id(),
         {:ok, plan} <- create_plan_record(params, plan_id),
         {:ok, agent} <- add_plan(agent, plan_id, plan),
         :ok <- emit_plan_created(agent, plan_id, plan) do
      
      Logger.info("Plan created: #{plan_id}")
      {:ok, update_metrics(agent, :created)}
    else
      {:error, reason} = error ->
        Logger.error("Failed to create plan: #{inspect(reason)}")
        error
    end
  end
  
  def handle_signal(agent, %{"type" => "update_plan"} = signal) do
    plan_id = signal["plan_id"]
    updates = signal["updates"] || %{}
    
    with {:ok, plan} <- get_plan(agent, plan_id),
         {:ok, lock} <- acquire_lock(agent, plan_id),
         {:ok, updated_plan} <- apply_updates(plan, updates),
         {:ok, agent} <- update_plan(agent, plan_id, updated_plan),
         :ok <- release_lock(agent, plan_id, lock),
         :ok <- emit_plan_updated(agent, plan_id, updates) do
      
      Logger.info("Plan updated: #{plan_id}")
      {:ok, agent}
    else
      {:error, reason} = error ->
        Logger.error("Failed to update plan #{plan_id}: #{inspect(reason)}")
        error
    end
  end
  
  def handle_signal(agent, %{"type" => "transition_plan"} = signal) do
    plan_id = signal["plan_id"]
    to_state = String.to_atom(signal["to_state"])
    
    with {:ok, plan} <- get_plan(agent, plan_id),
         {:ok, from_state} <- Map.fetch(plan, :state),
         :ok <- validate_transition(from_state, to_state),
         {:ok, lock} <- acquire_lock(agent, plan_id),
         {:ok, agent} <- perform_transition(agent, plan_id, from_state, to_state),
         :ok <- release_lock(agent, plan_id, lock),
         :ok <- emit_plan_transitioned(agent, plan_id, from_state, to_state) do
      
      Logger.info("Plan #{plan_id} transitioned: #{from_state} -> #{to_state}")
      {:ok, update_metrics(agent, {:transition, to_state})}
    else
      {:error, reason} = error ->
        Logger.error("Failed to transition plan #{plan_id}: #{inspect(reason)}")
        error
    end
  end
  
  def handle_signal(agent, %{"type" => "query_plans"} = signal) do
    filters = signal["filters"] || %{}
    pagination = signal["pagination"] || %{page: 1, limit: 20}
    
    # Check cache first
    cache_key = generate_cache_key(filters, pagination)
    case Map.get(agent.state.query_cache, cache_key) do
      nil ->
        # Perform query
        results = query_plans(agent, filters, pagination)
        
        # Cache results
        agent = cache_query_results(agent, cache_key, results)
        
        # Emit results
        emit_plans_found(agent, results)
        {:ok, agent}
        
      cached_results ->
        # Return cached results
        emit_plans_found(agent, cached_results)
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, signal) do
    # Let parent handle unknown signals
    super(agent, signal)
  end
  
  ## Private Functions
  
  defp validate_config(_config) do
    # Add any specific validation logic here
    :ok
  end
  
  defp generate_plan_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_ref = :erlang.unique_integer([:positive, :monotonic])
    {:ok, "plan_#{timestamp}_#{unique_ref}"}
  end
  
  defp create_plan_record(params, plan_id) do
    plan = %{
      id: plan_id,
      name: params["name"] || "Untitled Plan",
      description: params["description"] || "",
      phases: params["phases"] || [],
      metadata: params["metadata"] || %{},
      state: @draft_state,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      started_at: nil,
      completed_at: nil
    }
    
    {:ok, plan}
  end
  
  defp add_plan(agent, plan_id, plan) do
    updated_plans = Map.put(agent.state.plans, plan_id, plan)
    updated_state = Map.put(agent.state, :plans, updated_plans)
    
    {:ok, %{agent | state: updated_state}}
  end
  
  defp get_plan(agent, plan_id) do
    case Map.get(agent.state.plans, plan_id) do
      nil -> {:error, :plan_not_found}
      plan -> {:ok, plan}
    end
  end
  
  defp update_plan(agent, plan_id, updated_plan) do
    updated_plan = Map.put(updated_plan, :updated_at, DateTime.utc_now())
    updated_plans = Map.put(agent.state.plans, plan_id, updated_plan)
    updated_state = Map.put(agent.state, :plans, updated_plans)
    
    # Clear query cache on update
    updated_state = Map.put(updated_state, :query_cache, %{})
    
    {:ok, %{agent | state: updated_state}}
  end
  
  defp apply_updates(plan, updates) do
    # Only allow updating certain fields
    allowed_fields = ["name", "description", "phases", "metadata"]
    
    filtered_updates = updates
    |> Enum.filter(fn {k, _v} -> k in allowed_fields end)
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
    
    updated_plan = Map.merge(plan, filtered_updates)
    {:ok, updated_plan}
  end
  
  defp validate_transition(from_state, to_state) do
    allowed_transitions = Map.get(@valid_transitions, from_state, [])
    
    if to_state in allowed_transitions do
      :ok
    else
      {:error, {:invalid_transition, from_state, to_state}}
    end
  end
  
  defp perform_transition(agent, plan_id, from_state, to_state) do
    with {:ok, plan} <- get_plan(agent, plan_id) do
      # Update plan state
      updated_plan = plan
      |> Map.put(:state, to_state)
      |> Map.put(:updated_at, DateTime.utc_now())
      |> maybe_set_timestamp(from_state, to_state)
      
      # Update active/archived lists
      agent = agent
      |> update_active_plans(plan_id, from_state, to_state)
      |> update_archived_plans(plan_id, to_state)
      
      # Update the plan
      update_plan(agent, plan_id, updated_plan)
    end
  end
  
  defp maybe_set_timestamp(plan, _from, :active) do
    Map.put(plan, :started_at, DateTime.utc_now())
  end
  
  defp maybe_set_timestamp(plan, _from, to) when to in [:completed, :failed] do
    Map.put(plan, :completed_at, DateTime.utc_now())
  end
  
  defp maybe_set_timestamp(plan, _, _), do: plan
  
  defp update_active_plans(agent, plan_id, _from, :active) do
    active_plans = [plan_id | agent.state.active_plans] |> Enum.uniq()
    update_state(agent, %{active_plans: active_plans})
  end
  
  defp update_active_plans(agent, plan_id, from, _to) when from == :active do
    active_plans = List.delete(agent.state.active_plans, plan_id)
    update_state(agent, %{active_plans: active_plans})
  end
  
  defp update_active_plans(agent, _, _, _), do: agent
  
  defp update_archived_plans(agent, plan_id, :archived) do
    archived_plans = [plan_id | agent.state.archived_plans] |> Enum.uniq()
    update_state(agent, %{archived_plans: archived_plans})
  end
  
  defp update_archived_plans(agent, _, _), do: agent
  
  ## Locking Functions
  
  defp acquire_lock(agent, plan_id) do
    case Map.get(agent.state.locks, plan_id) do
      nil ->
        lock = %{
          holder: self(),
          acquired_at: DateTime.utc_now(),
          expires_at: DateTime.add(DateTime.utc_now(), @lock_timeout, :millisecond)
        }
        
        updated_locks = Map.put(agent.state.locks, plan_id, lock)
        updated_state = Map.put(agent.state, :locks, updated_locks)
        _agent = %{agent | state: updated_state}
        
        {:ok, lock}
        
      existing_lock ->
        if DateTime.compare(DateTime.utc_now(), existing_lock.expires_at) == :gt do
          # Lock expired, acquire it
          acquire_lock(agent, plan_id)
        else
          {:error, {:lock_held, existing_lock}}
        end
    end
  end
  
  defp release_lock(agent, plan_id, _lock) do
    updated_locks = Map.delete(agent.state.locks, plan_id)
    updated_state = Map.put(agent.state, :locks, updated_locks)
    _agent = %{agent | state: updated_state}
    :ok
  end
  
  defp cleanup_expired_locks(agent) do
    now = DateTime.utc_now()
    
    updated_locks = agent.state.locks
    |> Enum.filter(fn {_plan_id, lock} ->
      DateTime.compare(now, lock.expires_at) == :lt
    end)
    |> Enum.into(%{})
    
    update_state(agent, %{locks: updated_locks})
  end
  
  ## Query Functions
  
  defp query_plans(agent, filters, pagination) do
    all_plans = Map.values(agent.state.plans)
    
    # Apply filters
    filtered_plans = all_plans
    |> filter_by_state(filters["state"])
    |> filter_by_date_range(filters["created_after"], filters["created_before"])
    |> filter_by_tags(filters["tags"])
    |> filter_by_name(filters["name"])
    
    # Sort by creation date (newest first)
    sorted_plans = Enum.sort_by(filtered_plans, & &1.created_at, {:desc, DateTime})
    
    # Apply pagination
    page = pagination["page"] || 1
    limit = pagination["limit"] || 20
    offset = (page - 1) * limit
    
    paginated_plans = sorted_plans
    |> Enum.drop(offset)
    |> Enum.take(limit)
    
    %{
      plans: paginated_plans,
      total: length(sorted_plans),
      page: page,
      limit: limit,
      total_pages: ceil(length(sorted_plans) / limit)
    }
  end
  
  defp filter_by_state(plans, nil), do: plans
  defp filter_by_state(plans, state) do
    state_atom = String.to_atom(state)
    Enum.filter(plans, & &1.state == state_atom)
  end
  
  defp filter_by_date_range(plans, nil, nil), do: plans
  defp filter_by_date_range(plans, after_date, before_date) do
    plans
    |> then(fn p -> 
      if after_date do
        {:ok, datetime, _} = DateTime.from_iso8601(after_date)
        Enum.filter(p, & DateTime.compare(&1.created_at, datetime) != :lt)
      else
        p
      end
    end)
    |> then(fn p ->
      if before_date do
        {:ok, datetime, _} = DateTime.from_iso8601(before_date)
        Enum.filter(p, & DateTime.compare(&1.created_at, datetime) != :gt)
      else
        p
      end
    end)
  end
  
  defp filter_by_tags(plans, nil), do: plans
  defp filter_by_tags(plans, tags) when is_list(tags) do
    Enum.filter(plans, fn plan ->
      plan_tags = get_in(plan, [:metadata, "tags"]) || []
      Enum.any?(tags, & &1 in plan_tags)
    end)
  end
  
  defp filter_by_name(plans, nil), do: plans
  defp filter_by_name(plans, name_pattern) do
    regex = ~r/#{name_pattern}/i
    Enum.filter(plans, & Regex.match?(regex, &1.name))
  end
  
  defp generate_cache_key(filters, pagination) do
    key_data = {filters, pagination}
    :crypto.hash(:sha256, :erlang.term_to_binary(key_data))
    |> Base.encode16()
  end
  
  defp cache_query_results(agent, key, results) do
    # Limit cache size
    cache = agent.state.query_cache
    cache = if map_size(cache) > 100 do
      # Remove oldest entries
      cache
      |> Enum.sort_by(fn {_, v} -> v[:cached_at] end)
      |> Enum.drop(50)
      |> Enum.into(%{})
    else
      cache
    end
    
    # Add new entry
    cache_entry = Map.put(results, :cached_at, DateTime.utc_now())
    updated_cache = Map.put(cache, key, cache_entry)
    
    update_state(agent, %{query_cache: updated_cache})
  end
  
  ## Metrics Functions
  
  defp update_metrics(agent, :created) do
    metrics = agent.state.metrics
    |> Map.update(:total_created, 1, & &1 + 1)
    |> Map.put(:active_count, length(agent.state.active_plans))
    
    update_state(agent, %{metrics: metrics})
  end
  
  defp update_metrics(agent, {:transition, :completed}) do
    metrics = agent.state.metrics
    |> Map.update(:total_completed, 1, & &1 + 1)
    |> Map.put(:active_count, length(agent.state.active_plans))
    
    update_state(agent, %{metrics: metrics})
  end
  
  defp update_metrics(agent, {:transition, :failed}) do
    metrics = agent.state.metrics
    |> Map.update(:total_failed, 1, & &1 + 1)
    |> Map.put(:active_count, length(agent.state.active_plans))
    
    update_state(agent, %{metrics: metrics})
  end
  
  defp update_metrics(agent, _), do: agent
  
  ## Signal Emission Functions
  
  defp emit_plan_created(agent, plan_id, plan) do
    emit_signal(agent, %{
      "type" => "plan_created",
      "plan_id" => plan_id,
      "plan" => plan,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_plan_updated(agent, plan_id, updates) do
    emit_signal(agent, %{
      "type" => "plan_updated",
      "plan_id" => plan_id,
      "updates" => updates,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_plan_transitioned(agent, plan_id, from_state, to_state) do
    emit_signal(agent, %{
      "type" => "plan_transitioned",
      "plan_id" => plan_id,
      "from_state" => from_state,
      "to_state" => to_state,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  defp emit_plans_found(agent, results) do
    emit_signal(agent, %{
      "type" => "plans_found",
      "results" => results,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  ## Cleanup Functions
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  @impl GenServer
  def handle_info(:cleanup, agent) do
    agent = agent
    |> cleanup_expired_locks()
    |> cleanup_old_cache_entries()
    |> update_state(%{last_cleanup: DateTime.to_iso8601(DateTime.utc_now())})
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, agent}
  end
  
  defp cleanup_old_cache_entries(agent) do
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second) # 1 hour old
    
    updated_cache = agent.state.query_cache
    |> Enum.filter(fn {_k, v} ->
      DateTime.compare(v[:cached_at], cutoff) == :gt
    end)
    |> Enum.into(%{})
    
    update_state(agent, %{query_cache: updated_cache})
  end
end