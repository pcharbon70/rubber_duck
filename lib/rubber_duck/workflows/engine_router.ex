defmodule RubberDuck.Workflows.EngineRouter do
  @moduledoc """
  Intelligent routing system for workflow steps to engines.

  This module provides sophisticated routing capabilities that can dynamically
  select the best engine for a workflow step based on various factors including
  capability matching, load balancing, performance history, and resource availability.
  """

  alias RubberDuck.Hybrid.{CapabilityRegistry, ExecutionContext}
  alias RubberDuck.Engine.Manager, as: EngineManager

  require Logger

  @type routing_strategy :: :best_available | :load_balanced | :performance_based | :resource_aware
  @type routing_context :: %{
          step_name: atom(),
          capability: atom(),
          input_size: integer(),
          deadline: DateTime.t() | nil,
          quality_requirements: map(),
          resource_constraints: map()
        }

  ## Public API

  @doc """
  Routes a workflow step to the most appropriate engine.

  This function analyzes the step requirements and selects the best available
  engine based on the specified routing strategy and current system state.

  ## Routing Strategies
  - `:best_available` - Select highest priority available engine
  - `:load_balanced` - Select engine with lowest current load
  - `:performance_based` - Select engine with best historical performance
  - `:resource_aware` - Select engine based on resource availability
  """
  @spec route_to_engine(atom(), atom(), map(), routing_strategy()) ::
          {:ok, atom()} | {:error, term()}
  def route_to_engine(step_name, capability, context, strategy \\ :best_available) do
    routing_context = build_routing_context(step_name, capability, context)

    case find_candidate_engines(capability) do
      [] ->
        {:error, {:no_engines_for_capability, capability}}

      candidates ->
        selected_engine = select_engine_by_strategy(candidates, routing_context, strategy)
        {:ok, selected_engine.id}
    end
  end

  @doc """
  Creates a workflow step that automatically routes to the best engine.

  This function generates a workflow step configuration that uses intelligent
  routing to select the optimal engine at execution time.
  """
  @spec create_engine_step(atom(), atom(), keyword()) :: map()
  def create_engine_step(capability, input_name, opts \\ []) do
    step_name = opts[:step_name] || :"routed_#{capability}_step"
    routing_strategy = opts[:routing_strategy] || :best_available

    %{
      name: step_name,
      run: {__MODULE__, :execute_routed_engine_step},
      arguments: %{
        capability: capability,
        input: {:argument, input_name},
        routing_strategy: routing_strategy,
        routing_options: opts
      },
      timeout: opts[:timeout] || 30_000,
      max_retries: opts[:retries] || 3
    }
  end

  @doc """
  Optimizes engine allocation for an entire workflow.

  This function analyzes a workflow's engine requirements and creates an
  optimized allocation plan that minimizes resource contention and maximizes
  performance.
  """
  @spec optimize_engine_allocation(list(map()), map()) ::
          {:ok, map()} | {:error, term()}
  def optimize_engine_allocation(workflow_steps, context) do
    with {:ok, engine_requirements} <- analyze_workflow_engine_needs(workflow_steps),
         {:ok, resource_availability} <- assess_current_resource_state(),
         {:ok, allocation_plan} <- create_allocation_plan(engine_requirements, resource_availability, context) do
      {:ok, allocation_plan}
    else
      error -> error
    end
  end

  @doc """
  Monitors engine performance and adjusts routing decisions.

  This function tracks engine performance metrics and uses this data to
  improve future routing decisions through machine learning techniques.
  """
  @spec update_performance_metrics(atom(), atom(), map()) :: :ok
  def update_performance_metrics(engine_id, capability, metrics) do
    performance_data = %{
      engine_id: engine_id,
      capability: capability,
      execution_time: metrics.execution_time,
      success: metrics.success,
      quality_score: metrics.quality_score || 1.0,
      resource_usage: metrics.resource_usage || %{},
      timestamp: DateTime.utc_now()
    }

    store_performance_data(performance_data)
    update_routing_weights(engine_id, capability, performance_data)

    :ok
  end

  ## Step Execution Functions (called by Reactor)

  @doc false
  def execute_routed_engine_step(arguments, context) do
    %{
      capability: capability,
      input: input,
      routing_strategy: strategy,
      routing_options: opts
    } = arguments

    step_name = arguments[:step_name] || :routed_step
    routing_context = build_routing_context(step_name, capability, %{input: input})

    start_time = System.monotonic_time(:millisecond)

    case route_to_engine(step_name, capability, routing_context, strategy) do
      {:ok, engine_id} ->
        execution_context = create_engine_execution_context(engine_id, capability, context, opts)

        case execute_engine_with_monitoring(engine_id, input, execution_context) do
          {:ok, result} ->
            record_successful_execution(engine_id, capability, start_time, result)
            {:ok, result}

          {:error, reason} ->
            record_failed_execution(engine_id, capability, start_time, reason)
            handle_routing_failure(capability, input, context, reason, opts)
        end

      {:error, reason} ->
        Logger.warning("Failed to route step #{step_name} to engine: #{reason}")
        {:error, reason}
    end
  end

  ## Private Functions - Engine Selection

  defp find_candidate_engines(capability) do
    CapabilityRegistry.find_by_capability(capability, :engine)
    |> filter_available_engines()
  end

  defp select_engine_by_strategy(candidates, routing_context, strategy) do
    case strategy do
      :best_available ->
        select_best_available(candidates)

      :load_balanced ->
        select_load_balanced(candidates)

      :performance_based ->
        select_performance_based(candidates, routing_context.capability)

      :resource_aware ->
        select_resource_aware(candidates, routing_context)

      _ ->
        select_best_available(candidates)
    end
  end

  defp select_best_available(candidates) do
    # Already sorted by priority from CapabilityRegistry
    List.first(candidates)
  end

  defp select_load_balanced(candidates) do
    # Get current load for each candidate engine
    load_scores =
      Enum.map(candidates, fn engine ->
        load = get_current_engine_load(engine.id)
        {engine, load}
      end)

    # Select engine with lowest load
    {selected_engine, _load} = Enum.min_by(load_scores, fn {_engine, load} -> load end)
    selected_engine
  end

  defp select_performance_based(candidates, capability) do
    # Get historical performance for each candidate
    performance_scores =
      Enum.map(candidates, fn engine ->
        performance = get_engine_performance_score(engine.id, capability)
        {engine, performance}
      end)

    # Select engine with best performance
    {selected_engine, _score} = Enum.max_by(performance_scores, fn {_engine, score} -> score end)
    selected_engine
  end

  defp select_resource_aware(candidates, routing_context) do
    # Analyze resource requirements and availability
    resource_scores =
      Enum.map(candidates, fn engine ->
        resource_fit = calculate_resource_fitness(engine, routing_context)
        {engine, resource_fit}
      end)

    # Select engine with best resource fit
    {selected_engine, _fit} = Enum.max_by(resource_scores, fn {_engine, fit} -> fit end)
    selected_engine
  end

  ## Private Functions - Resource Analysis

  defp analyze_workflow_engine_needs(workflow_steps) do
    engine_steps = Enum.filter(workflow_steps, &is_engine_step?/1)

    requirements =
      Enum.map(engine_steps, fn step ->
        %{
          step_name: step.name,
          capability: extract_capability_from_step(step),
          estimated_duration: step[:timeout] || 30_000,
          resource_requirements: extract_resource_requirements(step),
          parallelizable: step[:async] || false
        }
      end)

    {:ok, requirements}
  end

  defp assess_current_resource_state do
    # This would integrate with actual resource monitoring
    resource_state = %{
      available_cpu_cores: System.schedulers_online(),
      available_memory_mb: get_available_memory(),
      engine_pool_utilization: get_engine_pool_utilization(),
      current_load: get_system_load()
    }

    {:ok, resource_state}
  end

  defp create_allocation_plan(requirements, availability, _context) do
    # Create an optimized allocation plan
    plan = %{
      sequential_steps: filter_sequential_steps(requirements),
      parallel_groups: group_parallel_steps(requirements),
      resource_allocation: allocate_resources(requirements, availability),
      estimated_total_duration: calculate_total_duration(requirements),
      bottleneck_analysis: identify_bottlenecks(requirements, availability)
    }

    {:ok, plan}
  end

  ## Private Functions - Performance Tracking

  defp store_performance_data(performance_data) do
    # Store in ETS or database for historical analysis
    table_name = :engine_performance_history

    # Ensure table exists
    unless :ets.whereis(table_name) != :undefined do
      :ets.new(table_name, [:bag, :public, :named_table])
    end

    :ets.insert(table_name, {
      {performance_data.engine_id, performance_data.capability},
      performance_data
    })
  end

  defp update_routing_weights(engine_id, capability, performance_data) do
    # Update routing weights based on performance
    current_weight = get_routing_weight(engine_id, capability)
    adjustment = calculate_weight_adjustment(performance_data)
    new_weight = max(0.1, min(2.0, current_weight + adjustment))

    set_routing_weight(engine_id, capability, new_weight)
  end

  ## Private Functions - Helper Functions

  defp build_routing_context(step_name, capability, context) do
    input_size = calculate_input_size(context[:input])

    %{
      step_name: step_name,
      capability: capability,
      input_size: input_size,
      deadline: context[:deadline],
      quality_requirements: context[:quality_requirements] || %{},
      resource_constraints: context[:resource_constraints] || %{}
    }
  end

  defp filter_available_engines(engines) do
    # Filter out engines that are currently unavailable
    Enum.filter(engines, &engine_available?/1)
  end

  defp engine_available?(engine) do
    # Check if engine is available (not overloaded, healthy, etc.)
    case EngineManager.health_check(engine.id) do
      {:ok, :healthy} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp create_engine_execution_context(engine_id, capability, reactor_context, opts) do
    ExecutionContext.create_hybrid_context(
      engine_context: %{
        selected_by_router: true,
        routing_strategy: opts[:routing_strategy],
        step_context: reactor_context
      },
      telemetry_metadata: %{
        engine_id: engine_id,
        capability: capability,
        routing_timestamp: DateTime.utc_now()
      }
    )
  end

  defp execute_engine_with_monitoring(engine_id, input, context) do
    # Execute with performance monitoring
    start_time = System.monotonic_time(:millisecond)
    start_memory = get_process_memory()

    result = EngineManager.execute(engine_id, input, ExecutionContext.extract_engine_context(context))

    end_time = System.monotonic_time(:millisecond)
    end_memory = get_process_memory()

    # Record performance metrics
    metrics = %{
      execution_time: end_time - start_time,
      memory_used: end_memory - start_memory,
      success: match?({:ok, _}, result)
    }

    emit_routing_telemetry(engine_id, metrics, context)

    result
  end

  defp handle_routing_failure(capability, input, context, reason, opts) do
    case opts[:fallback_strategy] do
      :retry_different_engine ->
        retry_with_different_engine(capability, input, context, reason)

      :fail_fast ->
        {:error, reason}

      _ ->
        {:error, reason}
    end
  end

  defp retry_with_different_engine(capability, input, context, original_reason) do
    # Try to find an alternative engine
    case find_alternative_engine(capability, original_reason) do
      nil ->
        {:error, {:no_alternative_engine, original_reason}}

      alternative_engine ->
        Logger.info("Retrying with alternative engine: #{alternative_engine.id}")
        execution_context = create_engine_execution_context(alternative_engine.id, capability, context, [])
        EngineManager.execute(alternative_engine.id, input, ExecutionContext.extract_engine_context(execution_context))
    end
  end

  defp find_alternative_engine(capability, _reason) do
    CapabilityRegistry.find_by_capability(capability, :engine)
    # Skip the first (already failed) engine
    |> Enum.drop(1)
    |> List.first()
  end

  ## Private Functions - Metrics and Monitoring

  defp record_successful_execution(engine_id, capability, start_time, result) do
    duration = System.monotonic_time(:millisecond) - start_time
    quality_score = calculate_result_quality(result)

    update_performance_metrics(engine_id, capability, %{
      execution_time: duration,
      success: true,
      quality_score: quality_score,
      resource_usage: get_current_resource_usage()
    })
  end

  defp record_failed_execution(engine_id, capability, start_time, reason) do
    duration = System.monotonic_time(:millisecond) - start_time

    update_performance_metrics(engine_id, capability, %{
      execution_time: duration,
      success: false,
      failure_reason: reason,
      resource_usage: get_current_resource_usage()
    })
  end

  ## Placeholder implementations for system integration functions

  defp get_current_engine_load(_engine_id), do: :rand.uniform()
  defp get_engine_performance_score(_engine_id, _capability), do: :rand.uniform()
  defp calculate_resource_fitness(_engine, _context), do: :rand.uniform()
  defp get_available_memory, do: 1024
  defp get_engine_pool_utilization, do: %{}
  defp get_system_load, do: 0.5
  defp calculate_input_size(_input), do: 100
  defp is_engine_step?(_step), do: true
  defp extract_capability_from_step(_step), do: :unknown
  defp extract_resource_requirements(_step), do: %{}
  defp filter_sequential_steps(requirements), do: requirements
  defp group_parallel_steps(_requirements), do: []
  defp allocate_resources(requirements, _availability), do: requirements
  defp calculate_total_duration(requirements), do: Enum.sum(Enum.map(requirements, & &1.estimated_duration))
  defp identify_bottlenecks(_requirements, _availability), do: []
  defp get_routing_weight(_engine_id, _capability), do: 1.0

  defp calculate_weight_adjustment(performance_data) do
    if performance_data.success, do: 0.1, else: -0.1
  end

  defp set_routing_weight(_engine_id, _capability, _weight), do: :ok
  defp get_process_memory, do: 0
  defp get_current_resource_usage, do: %{}
  defp calculate_result_quality(_result), do: 1.0
  defp emit_routing_telemetry(_engine_id, _metrics, _context), do: :ok
end
