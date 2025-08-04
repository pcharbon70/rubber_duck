defmodule RubberDuck.Agents.PlanManagerAgent do
  @moduledoc """
  Autonomous agent responsible for managing the lifecycle of plans in the planning system.
  
  This agent handles:
  - Plan creation and initialization
  - State transitions and lifecycle management
  - Query processing and result aggregation
  - Metrics collection and monitoring
  - Coordination with other planning agents
  
  ## Responsibilities
  
  - **Plan Creation**: Orchestrates the creation of new plans with validation
  - **State Management**: Tracks and transitions plan states
  - **Query Processing**: Handles search and filtering of plans
  - **Metrics Collection**: Monitors plan-related metrics
  - **Signal Coordination**: Routes signals to appropriate planning agents
  
  ## Signal Handling
  
  The agent responds to the following signals:
  - `plan.create` - Create a new plan
  - `plan.update` - Update an existing plan
  - `plan.transition` - Transition plan state
  - `plan.query` - Query plans
  - `plan.delete` - Delete a plan
  - `plan.metrics` - Request metrics
  """
  
  use Jido.Agent,
    name: "plan_manager",
    description: "Manages plan lifecycle and coordination",
    schema: [
      plans: [
        type: :map,
        default: %{},
        doc: "Active plans indexed by ID"
      ],
      plan_locks: [
        type: :map,
        default: %{},
        doc: "Concurrency locks for plans"
      ],
      metrics: [
        type: :map,
        default: %{
          plans_created: 0,
          plans_completed: 0,
          plans_failed: 0,
          active_plans: 0,
          total_execution_time: 0,
          average_execution_time: 0
        },
        doc: "Plan-related metrics"
      ],
      query_cache: [
        type: :map,
        default: %{},
        doc: "Cached query results"
      ],
      workflows: [
        type: :map,
        default: %{},
        doc: "Active plan creation workflows"
      ],
      config: [
        type: :map,
        default: %{
          max_concurrent_plans: 10,
          lock_timeout: 30_000,
          cache_ttl: 60_000,
          validation_required: true
        },
        doc: "Agent configuration"
      ]
    ]
  
  require Logger
  
  alias RubberDuck.Planning.Plan
  alias RubberDuck.Jido.Workflows.WorkflowCoordinator
  
  # Mount callback for initialization
  @impl Jido.Agent
  def mount(opts, initial_state) do
    Logger.info("Mounting PlanManagerAgent", opts: opts)
    
    # Initialize state with configuration
    state = Map.merge(initial_state, %{
      plans: Map.get(opts, :plans, %{}),
      plan_locks: Map.get(opts, :plan_locks, %{}),
      metrics: Map.get(opts, :metrics, initial_state.metrics || %{}),
      query_cache: Map.get(opts, :query_cache, %{}),
      workflows: Map.get(opts, :workflows, %{}),
      config: Map.merge(
        initial_state.config || %{},
        Map.get(opts, :config, %{})
      )
    })
    
    # Schedule periodic cache cleanup
    Process.send_after(self(), :cleanup_cache, state.config.cache_ttl)
    
    {:ok, state}
  end
  
  # Signal mappings
  def signal_mappings do
    %{
      "plan.create" => {__MODULE__.CreatePlanAction, &extract_create_params/1},
      "plan.update" => {__MODULE__.UpdatePlanAction, &extract_update_params/1},
      "plan.transition" => {__MODULE__.TransitionPlanAction, &extract_transition_params/1},
      "plan.query" => {__MODULE__.QueryPlansAction, &extract_query_params/1},
      "plan.delete" => {__MODULE__.DeletePlanAction, &extract_delete_params/1},
      "plan.metrics" => {__MODULE__.GetMetricsAction, &extract_metrics_params/1},
      "plan.validate" => {__MODULE__.ValidatePlanAction, &extract_validate_params/1},
      "plan.execute" => {__MODULE__.ExecutePlanAction, &extract_execute_params/1}
    }
  end
  
  # Parameter extraction functions
  defp extract_create_params(%{"data" => data}) do
    %{
      name: Map.get(data, "name", "Untitled Plan"),
      description: Map.get(data, "description", ""),
      type: String.to_atom(Map.get(data, "type", "standard")),
      context: Map.get(data, "context", %{}),
      dependencies: Map.get(data, "dependencies", []),
      constraints: Map.get(data, "constraints", []),
      metadata: Map.get(data, "metadata", %{})
    }
  end
  
  defp extract_update_params(%{"data" => data}) do
    %{
      plan_id: Map.fetch!(data, "plan_id"),
      updates: Map.get(data, "updates", %{}),
      validate: Map.get(data, "validate", true)
    }
  end
  
  defp extract_transition_params(%{"data" => data}) do
    %{
      plan_id: Map.fetch!(data, "plan_id"),
      new_status: String.to_atom(Map.fetch!(data, "new_status")),
      reason: Map.get(data, "reason", nil)
    }
  end
  
  defp extract_query_params(%{"data" => data}) do
    %{
      filters: Map.get(data, "filters", %{}),
      sort_by: Map.get(data, "sort_by", :created_at),
      order: String.to_atom(Map.get(data, "order", "desc")),
      limit: Map.get(data, "limit", 20),
      offset: Map.get(data, "offset", 0)
    }
  end
  
  defp extract_delete_params(%{"data" => data}) do
    %{
      plan_id: Map.fetch!(data, "plan_id"),
      force: Map.get(data, "force", false)
    }
  end
  
  defp extract_metrics_params(%{"data" => data}) do
    %{
      metric_types: Map.get(data, "metric_types", [:all]),
      time_range: Map.get(data, "time_range", :all_time)
    }
  end
  
  defp extract_validate_params(%{"data" => data}) do
    %{
      plan_id: Map.fetch!(data, "plan_id"),
      validation_types: Map.get(data, "validation_types", [:all])
    }
  end
  
  defp extract_execute_params(%{"data" => data}) do
    %{
      plan_id: Map.fetch!(data, "plan_id"),
      execution_mode: String.to_atom(Map.get(data, "execution_mode", "sequential")),
      dry_run: Map.get(data, "dry_run", false)
    }
  end
  
  # Lifecycle hooks
  @impl Jido.Agent
  def on_before_run(agent) do
    Logger.debug("PlanManagerAgent preparing to run action",
      agent_id: agent.id,
      active_plans: map_size(agent.state.plans)
    )
    {:ok, agent}
  end
  
  @impl Jido.Agent
  def on_after_run(agent, _result, metadata) do
    # Update metrics after action completion
    updated_metrics = update_metrics(agent.state.metrics, metadata[:action])
    updated_state = Map.put(agent.state, :metrics, updated_metrics)
    
    Logger.debug("PlanManagerAgent completed action",
      agent_id: agent.id,
      action: metadata[:action]
    )
    
    {:ok, %{agent | state: updated_state}}
  end
  
  @impl Jido.Agent
  def on_error(agent, error) do
    Logger.error("PlanManagerAgent encountered error",
      agent_id: agent.id,
      error: error
    )
    {:ok, agent}
  end
  
  @impl Jido.Agent
  def shutdown(agent, reason) do
    Logger.info("PlanManagerAgent shutting down",
      agent_id: agent.id,
      reason: reason,
      active_plans: map_size(agent.state.plans)
    )
    :ok
  end
  
  # Handle periodic cache cleanup
  def handle_info(:cleanup_cache, agent) do
    now = System.system_time(:millisecond)
    cache_ttl = agent.state.config.cache_ttl
    
    updated_cache = 
      agent.state.query_cache
      |> Enum.filter(fn {_key, {_result, timestamp}} ->
        now - timestamp < cache_ttl
      end)
      |> Map.new()
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_cache, cache_ttl)
    
    {:noreply, %{agent | state: Map.put(agent.state, :query_cache, updated_cache)}}
  end
  
  # Helper functions
  defp update_metrics(metrics, action) do
    case action do
      CreatePlanAction -> Map.update(metrics, :plans_created, 1, &(&1 + 1))
      _ -> metrics
    end
  end
  
  # Action Modules
  
  defmodule CreatePlanAction do
    @moduledoc """
    Action for creating a new plan with validation and workflow orchestration.
    """
    
    use Jido.Action,
      name: "create_plan",
      description: "Creates a new plan with validation",
      schema: [
        name: [type: :string, required: true],
        description: [type: :string, default: ""],
        type: [type: :atom, default: :standard],
        context: [type: :map, default: %{}],
        dependencies: [type: {:list, :string}, default: []],
        constraints: [type: {:list, :map}, default: []],
        metadata: [type: :map, default: %{}]
      ]
    
    alias RubberDuck.Planning.Plan
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, :unlocked} <- check_plan_limit(agent),
           {:ok, plan_id} <- generate_plan_id(),
           {:ok, plan} <- create_plan_record(params, plan_id),
           {:ok, workflow_id} <- start_creation_workflow(plan, agent),
           {:ok, updated_agent} <- track_plan(agent, plan_id, plan, workflow_id) do
        
        {:ok, %{
          plan_id: plan_id,
          workflow_id: workflow_id,
          status: :creating,
          plan: plan
        }, %{agent: updated_agent}}
      end
    end
    
    defp check_plan_limit(agent) do
      active_count = map_size(agent.state.plans)
      max_concurrent = agent.state.config.max_concurrent_plans
      
      if active_count < max_concurrent do
        {:ok, :unlocked}
      else
        {:error, :max_plans_reached}
      end
    end
    
    defp generate_plan_id do
      {:ok, "plan_" <> Ecto.UUID.generate()}
    end
    
    defp create_plan_record(params, plan_id) do
      plan_params = Map.merge(params, %{
        id: plan_id,
        status: :draft,
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })
      
      case Plan.create(plan_params) do
        {:ok, plan} -> {:ok, plan}
        {:error, reason} -> {:error, {:plan_creation_failed, reason}}
      end
    end
    
    defp start_creation_workflow(plan, agent) do
      if agent.state.config.validation_required do
        # Start workflow with validation
        WorkflowCoordinator.start_workflow(
          RubberDuck.Workflows.PlanCreationWorkflow,
          %{plan: plan, validate: true},
          persist: true
        )
      else
        {:ok, nil}
      end
    end
    
    defp track_plan(agent, plan_id, plan, workflow_id) do
      updated_plans = Map.put(agent.state.plans, plan_id, %{
        plan: plan,
        workflow_id: workflow_id,
        status: :creating,
        created_at: DateTime.utc_now()
      })
      
      updated_metrics = 
        agent.state.metrics
        |> Map.update(:plans_created, 1, &(&1 + 1))
        |> Map.update(:active_plans, 1, &(&1 + 1))
      
      updated_state = 
        agent.state
        |> Map.put(:plans, updated_plans)
        |> Map.put(:metrics, updated_metrics)
      
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  defmodule UpdatePlanAction do
    @moduledoc """
    Action for updating an existing plan with optional validation.
    """
    
    use Jido.Action,
      name: "update_plan",
      description: "Updates an existing plan",
      schema: [
        plan_id: [type: :string, required: true],
        updates: [type: :map, required: true],
        validate: [type: :boolean, default: true]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, plan_info} <- get_plan(agent, params.plan_id),
           {:ok, :acquired} <- acquire_lock(agent, params.plan_id),
           {:ok, updated_plan} <- update_plan_record(plan_info.plan, params.updates),
           {:ok, validated_plan} <- maybe_validate(updated_plan, params.validate),
           {:ok, updated_agent} <- update_tracked_plan(agent, params.plan_id, validated_plan) do
        
        release_lock(updated_agent, params.plan_id)
        
        {:ok, %{
          plan_id: params.plan_id,
          plan: validated_plan,
          updated_fields: Map.keys(params.updates)
        }, %{agent: updated_agent}}
      end
    end
    
    defp get_plan(agent, plan_id) do
      case Map.get(agent.state.plans, plan_id) do
        nil -> {:error, :plan_not_found}
        plan_info -> {:ok, plan_info}
      end
    end
    
    defp acquire_lock(agent, plan_id) do
      if Map.get(agent.state.plan_locks, plan_id) do
        {:error, :plan_locked}
      else
        {:ok, :acquired}
      end
    end
    
    defp update_plan_record(plan, updates) do
      updated_params = Map.merge(plan, updates)
      Plan.update(plan, updated_params)
    end
    
    defp maybe_validate(plan, true) do
      # Trigger validation workflow
      case WorkflowCoordinator.execute_workflow(
        RubberDuck.Workflows.PlanValidationWorkflow,
        %{plan: plan},
        timeout: 10_000
      ) do
        {:ok, validated_plan} -> {:ok, validated_plan}
        {:error, reason} -> {:error, {:validation_failed, reason}}
      end
    end
    defp maybe_validate(plan, false), do: {:ok, plan}
    
    defp update_tracked_plan(agent, plan_id, plan) do
      updated_info = Map.merge(agent.state.plans[plan_id], %{
        plan: plan,
        updated_at: DateTime.utc_now()
      })
      
      updated_plans = Map.put(agent.state.plans, plan_id, updated_info)
      updated_state = Map.put(agent.state, :plans, updated_plans)
      
      {:ok, %{agent | state: updated_state}}
    end
    
    defp release_lock(agent, plan_id) do
      updated_locks = Map.delete(agent.state.plan_locks, plan_id)
      Map.put(agent.state, :plan_locks, updated_locks)
    end
  end
  
  defmodule TransitionPlanAction do
    @moduledoc """
    Action for transitioning a plan between states with validation.
    """
    
    use Jido.Action,
      name: "transition_plan",
      description: "Transitions a plan to a new state",
      schema: [
        plan_id: [type: :string, required: true],
        new_status: [type: :atom, required: true],
        reason: [type: {:or, [:string, nil]}, default: nil]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, plan_info} <- get_plan(agent, params.plan_id),
           {:ok, :valid} <- validate_transition(plan_info.plan.status, params.new_status),
           {:ok, transitioned_plan} <- transition_plan(plan_info.plan, params.new_status, params.reason),
           {:ok, updated_agent} <- update_plan_status(agent, params.plan_id, transitioned_plan) do
        
        emit_transition_signal(params.plan_id, plan_info.plan.status, params.new_status)
        
        {:ok, %{
          plan_id: params.plan_id,
          old_status: plan_info.plan.status,
          new_status: params.new_status,
          plan: transitioned_plan
        }, %{agent: updated_agent}}
      end
    end
    
    defp get_plan(agent, plan_id) do
      case Map.get(agent.state.plans, plan_id) do
        nil -> {:error, :plan_not_found}
        plan_info -> {:ok, plan_info}
      end
    end
    
    defp validate_transition(current_status, new_status) do
      valid_transitions = %{
        draft: [:ready, :failed],
        ready: [:executing, :failed],
        executing: [:completed, :failed],
        completed: [],
        failed: [:draft]
      }
      
      if new_status in Map.get(valid_transitions, current_status, []) do
        {:ok, :valid}
      else
        {:error, {:invalid_transition, current_status, new_status}}
      end
    end
    
    defp transition_plan(plan, new_status, reason) do
      Plan.transition_status(plan, %{
        new_status: new_status,
        reason: reason,
        transitioned_at: DateTime.utc_now()
      })
    end
    
    defp update_plan_status(agent, plan_id, plan) do
      updated_info = Map.merge(agent.state.plans[plan_id], %{
        plan: plan,
        status: plan.status,
        updated_at: DateTime.utc_now()
      })
      
      updated_plans = Map.put(agent.state.plans, plan_id, updated_info)
      
      # Update metrics based on status
      updated_metrics = update_status_metrics(agent.state.metrics, plan.status)
      
      updated_state = 
        agent.state
        |> Map.put(:plans, updated_plans)
        |> Map.put(:metrics, updated_metrics)
      
      {:ok, %{agent | state: updated_state}}
    end
    
    defp update_status_metrics(metrics, :completed) do
      metrics
      |> Map.update(:plans_completed, 1, &(&1 + 1))
      |> Map.update(:active_plans, 0, &max(&1 - 1, 0))
    end
    defp update_status_metrics(metrics, :failed) do
      metrics
      |> Map.update(:plans_failed, 1, &(&1 + 1))
      |> Map.update(:active_plans, 0, &max(&1 - 1, 0))
    end
    defp update_status_metrics(metrics, _), do: metrics
    
    defp emit_transition_signal(plan_id, old_status, new_status) do
      Jido.Signal.emit(%{
        type: "plan.status_changed",
        data: %{
          plan_id: plan_id,
          old_status: old_status,
          new_status: new_status,
          timestamp: DateTime.utc_now()
        }
      })
    end
  end
  
  defmodule QueryPlansAction do
    @moduledoc """
    Action for querying plans with caching support.
    """
    
    use Jido.Action,
      name: "query_plans",
      description: "Queries plans with filters and pagination",
      schema: [
        filters: [type: :map, default: %{}],
        sort_by: [type: :atom, default: :created_at],
        order: [type: :atom, default: :desc],
        limit: [type: :integer, default: 20],
        offset: [type: :integer, default: 0]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      cache_key = generate_cache_key(params)
      
      case get_cached_result(agent, cache_key) do
        {:ok, cached_result} ->
          {:ok, cached_result, context}
        
        :miss ->
          with {:ok, results} <- query_plans(agent, params),
               {:ok, updated_agent} <- cache_results(agent, cache_key, results) do
            {:ok, results, %{agent: updated_agent}}
          end
      end
    end
    
    defp generate_cache_key(params) do
      :crypto.hash(:sha256, :erlang.term_to_binary(params))
      |> Base.encode16()
    end
    
    defp get_cached_result(agent, cache_key) do
      case Map.get(agent.state.query_cache, cache_key) do
        {result, timestamp} ->
          if System.system_time(:millisecond) - timestamp < agent.state.config.cache_ttl do
            {:ok, result}
          else
            :miss
          end
        nil ->
          :miss
      end
    end
    
    defp query_plans(agent, params) do
      plans = 
        agent.state.plans
        |> Map.values()
        |> apply_filters(params.filters)
        |> sort_plans(params.sort_by, params.order)
        |> paginate(params.limit, params.offset)
      
      {:ok, %{
        plans: plans,
        total: length(plans),
        offset: params.offset,
        limit: params.limit
      }}
    end
    
    defp apply_filters(plans, filters) when map_size(filters) == 0, do: plans
    defp apply_filters(plans, filters) do
      Enum.filter(plans, fn plan_info ->
        Enum.all?(filters, fn {key, value} ->
          get_in(plan_info, [Access.key(:plan), Access.key(key)]) == value
        end)
      end)
    end
    
    defp sort_plans(plans, sort_by, order) do
      Enum.sort_by(plans, &get_in(&1, [Access.key(:plan), Access.key(sort_by)]), order)
    end
    
    defp paginate(plans, limit, offset) do
      plans
      |> Enum.drop(offset)
      |> Enum.take(limit)
    end
    
    defp cache_results(agent, cache_key, results) do
      updated_cache = Map.put(
        agent.state.query_cache,
        cache_key,
        {results, System.system_time(:millisecond)}
      )
      
      updated_state = Map.put(agent.state, :query_cache, updated_cache)
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  defmodule DeletePlanAction do
    @moduledoc """
    Action for deleting a plan with safety checks.
    """
    
    use Jido.Action,
      name: "delete_plan",
      description: "Deletes a plan",
      schema: [
        plan_id: [type: :string, required: true],
        force: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, plan_info} <- get_plan(agent, params.plan_id),
           {:ok, :can_delete} <- check_deletion_allowed(plan_info, params.force),
           {:ok, _} <- delete_plan_record(plan_info.plan),
           {:ok, updated_agent} <- remove_tracked_plan(agent, params.plan_id) do
        
        {:ok, %{
          plan_id: params.plan_id,
          deleted_at: DateTime.utc_now()
        }, %{agent: updated_agent}}
      end
    end
    
    defp get_plan(agent, plan_id) do
      case Map.get(agent.state.plans, plan_id) do
        nil -> {:error, :plan_not_found}
        plan_info -> {:ok, plan_info}
      end
    end
    
    defp check_deletion_allowed(plan_info, force) do
      if force or plan_info.plan.status in [:draft, :failed, :completed] do
        {:ok, :can_delete}
      else
        {:error, {:cannot_delete_active_plan, plan_info.plan.status}}
      end
    end
    
    defp delete_plan_record(plan) do
      Plan.destroy(plan)
    end
    
    defp remove_tracked_plan(agent, plan_id) do
      updated_plans = Map.delete(agent.state.plans, plan_id)
      updated_locks = Map.delete(agent.state.plan_locks, plan_id)
      
      updated_state = 
        agent.state
        |> Map.put(:plans, updated_plans)
        |> Map.put(:plan_locks, updated_locks)
        |> update_in([:metrics, :active_plans], &max(&1 - 1, 0))
      
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  defmodule GetMetricsAction do
    @moduledoc """
    Action for retrieving plan metrics.
    """
    
    use Jido.Action,
      name: "get_metrics",
      description: "Retrieves plan-related metrics",
      schema: [
        metric_types: [type: {:list, :atom}, default: [:all]],
        time_range: [type: :atom, default: :all_time]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      metrics = collect_metrics(agent, params.metric_types, params.time_range)
      
      {:ok, metrics, context}
    end
    
    defp collect_metrics(agent, [:all], _time_range) do
      base_metrics = agent.state.metrics
      
      # Calculate additional metrics
      Map.merge(base_metrics, %{
        success_rate: calculate_success_rate(base_metrics),
        average_active_time: calculate_average_active_time(agent),
        plan_distribution: calculate_plan_distribution(agent)
      })
    end
    defp collect_metrics(agent, metric_types, _time_range) do
      Enum.reduce(metric_types, %{}, fn type, acc ->
        Map.put(acc, type, Map.get(agent.state.metrics, type, 0))
      end)
    end
    
    defp calculate_success_rate(%{plans_completed: completed, plans_failed: failed}) do
      total = completed + failed
      if total > 0, do: completed / total * 100, else: 0.0
    end
    
    defp calculate_average_active_time(agent) do
      active_times = 
        agent.state.plans
        |> Map.values()
        |> Enum.map(fn info ->
          if info.status == :completed do
            DateTime.diff(info.updated_at, info.created_at, :second)
          else
            0
          end
        end)
      
      if length(active_times) > 0 do
        Enum.sum(active_times) / length(active_times)
      else
        0
      end
    end
    
    defp calculate_plan_distribution(agent) do
      agent.state.plans
      |> Map.values()
      |> Enum.group_by(& &1.status)
      |> Enum.map(fn {status, plans} -> {status, length(plans)} end)
      |> Map.new()
    end
  end
  
  defmodule ValidatePlanAction do
    @moduledoc """
    Action for validating a plan through the validation workflow.
    """
    
    use Jido.Action,
      name: "validate_plan",
      description: "Validates a plan",
      schema: [
        plan_id: [type: :string, required: true],
        validation_types: [type: {:list, :atom}, default: [:all]]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, plan_info} <- get_plan(agent, params.plan_id),
           {:ok, validation_result} <- run_validation(plan_info.plan, params.validation_types),
           {:ok, updated_plan} <- update_validation_results(plan_info.plan, validation_result) do
        
        {:ok, %{
          plan_id: params.plan_id,
          validation_result: validation_result,
          is_valid: validation_result.is_valid
        }, context}
      end
    end
    
    defp get_plan(agent, plan_id) do
      case Map.get(agent.state.plans, plan_id) do
        nil -> {:error, :plan_not_found}
        plan_info -> {:ok, plan_info}
      end
    end
    
    defp run_validation(plan, validation_types) do
      # This would integrate with the Critics system
      {:ok, %{
        is_valid: true,
        validation_types: validation_types,
        issues: [],
        warnings: [],
        timestamp: DateTime.utc_now()
      }}
    end
    
    defp update_validation_results(plan, validation_result) do
      Plan.add_validation_result(plan, %{validation_results: validation_result})
    end
  end
  
  defmodule ExecutePlanAction do
    @moduledoc """
    Action for executing a plan through the execution workflow.
    """
    
    use Jido.Action,
      name: "execute_plan",
      description: "Executes a plan",
      schema: [
        plan_id: [type: :string, required: true],
        execution_mode: [type: :atom, default: :sequential],
        dry_run: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      with {:ok, plan_info} <- get_plan(agent, params.plan_id),
           {:ok, :ready} <- check_execution_ready(plan_info),
           {:ok, workflow_id} <- start_execution_workflow(plan_info.plan, params) do
        
        {:ok, %{
          plan_id: params.plan_id,
          workflow_id: workflow_id,
          execution_mode: params.execution_mode,
          dry_run: params.dry_run,
          started_at: DateTime.utc_now()
        }, context}
      end
    end
    
    defp get_plan(agent, plan_id) do
      case Map.get(agent.state.plans, plan_id) do
        nil -> {:error, :plan_not_found}
        plan_info -> {:ok, plan_info}
      end
    end
    
    defp check_execution_ready(plan_info) do
      if plan_info.status == :ready do
        {:ok, :ready}
      else
        {:error, {:invalid_status_for_execution, plan_info.status}}
      end
    end
    
    defp start_execution_workflow(plan, params) do
      WorkflowCoordinator.start_workflow(
        RubberDuck.Workflows.PlanExecutionWorkflow,
        %{
          plan: plan,
          execution_mode: params.execution_mode,
          dry_run: params.dry_run
        },
        persist: true
      )
    end
  end
end