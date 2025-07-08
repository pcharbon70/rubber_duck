defmodule RubberDuck.Hybrid.Bridge do
  @moduledoc """
  Central bridge for engine-workflow integration in the hybrid architecture.

  This module serves as the primary integration point between the engine DSL system
  and the workflow orchestration layer, providing seamless interoperability and
  unified execution capabilities.
  """

  alias RubberDuck.Hybrid.{ExecutionContext, CapabilityRegistry}
  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.Workflows.Executor, as: WorkflowExecutor

  require Logger

  @type execution_target :: {:engine, atom()} | {:workflow, atom()} | {:hybrid, atom()}
  @type execution_input :: map()
  @type execution_options :: keyword()
  @type execution_result :: {:ok, term()} | {:error, term()}

  @doc """
  Converts an engine to a workflow step for hybrid execution.

  This function creates a workflow step that wraps an engine, allowing engines
  to participate directly in workflow orchestration.

  ## Options
  - `:timeout` - Step timeout (default: 30_000)
  - `:retries` - Number of retries (default: 3)
  - `:async` - Whether to execute asynchronously (default: false)
  - `:pool_size` - Engine pool size for this step (default: 1)
  """
  @spec engine_to_step(atom(), execution_options()) :: map()
  def engine_to_step(engine_name, opts \\ []) do
    %{
      name: :"#{engine_name}_step",
      run: {__MODULE__, :execute_engine_step},
      arguments: %{
        engine_name: engine_name,
        engine_input: {:argument, :input},
        execution_options: opts
      },
      timeout: opts[:timeout] || 30_000,
      max_retries: opts[:retries] || 3,
      async: opts[:async] || false
    }
  end

  @doc """
  Exposes a workflow as an engine capability for engine-style execution.

  This function creates an engine-compatible interface for workflow execution,
  allowing workflows to be called through the engine API.
  """
  @spec workflow_to_engine(atom(), execution_options()) :: map()
  def workflow_to_engine(workflow_name, opts \\ []) do
    capability = opts[:capability] || :"workflow_#{workflow_name}"

    # Register the workflow as a hybrid capability
    CapabilityRegistry.register_hybrid_capability(
      workflow_name,
      capability,
      %{
        type: :workflow_engine_adapter,
        workflow_name: workflow_name,
        module: __MODULE__,
        priority: opts[:priority] || 100,
        timeout: opts[:timeout] || 60_000
      }
    )

    %{
      name: workflow_name,
      capability: capability,
      module: __MODULE__,
      execute_function: :execute_workflow_as_engine
    }
  end

  @doc """
  Unified execution interface that can handle engines, workflows, or hybrid targets.

  This function provides a single entry point for executing any registered
  capability, automatically routing to the appropriate execution mechanism.
  """
  @spec unified_execute(execution_target() | atom(), execution_input(), ExecutionContext.t()) :: execution_result()
  def unified_execute(target, input, context \\ nil)

  def unified_execute({:engine, engine_name}, input, context) do
    execute_engine_with_context(engine_name, input, context)
  end

  def unified_execute({:workflow, workflow_name}, input, context) do
    execute_workflow_with_context(workflow_name, input, context)
  end

  def unified_execute({:hybrid, hybrid_name}, input, context) do
    execute_hybrid_with_context(hybrid_name, input, context)
  end

  def unified_execute(capability, input, context) when is_atom(capability) do
    case CapabilityRegistry.find_best_for_capability(capability) do
      nil ->
        {:error, {:capability_not_found, capability}}

      registration ->
        target = {registration.type, registration.id}
        unified_execute(target, input, context)
    end
  end

  @doc """
  Creates a hybrid step that can dynamically route to engines or workflows.

  This function creates a workflow step that uses capability-based routing
  to select the best available implementation at runtime.
  """
  @spec create_hybrid_step(atom(), execution_options()) :: map()
  def create_hybrid_step(capability, opts \\ []) do
    %{
      name: :"hybrid_#{capability}_step",
      run: {__MODULE__, :execute_hybrid_step},
      arguments: %{
        capability: capability,
        step_input: {:argument, :input},
        execution_options: opts
      },
      timeout: opts[:timeout] || 60_000,
      max_retries: opts[:retries] || 3
    }
  end

  @doc """
  Optimizes execution by analyzing the hybrid configuration and available resources.

  This function examines the current system state and recommends the optimal
  execution strategy for a given hybrid workflow.
  """
  @spec optimize_hybrid_execution(map(), ExecutionContext.t()) :: {:ok, map()} | {:error, term()}
  def optimize_hybrid_execution(hybrid_config, context) do
    with {:ok, resource_analysis} <- analyze_resource_requirements(hybrid_config, context),
         {:ok, capability_mapping} <- map_capabilities_to_implementations(hybrid_config),
         {:ok, optimized_plan} <- generate_optimization_plan(resource_analysis, capability_mapping) do
      {:ok, optimized_plan}
    else
      error -> error
    end
  end

  ## Workflow Step Execution Functions (called by Reactor)

  @doc false
  def execute_engine_step(arguments, _context) do
    %{
      engine_name: engine_name,
      engine_input: input,
      execution_options: _opts
    } = arguments

    execution_context =
      ExecutionContext.create_hybrid_context(
        engine_context: %{step_type: :engine_step},
        telemetry_metadata: %{engine_name: engine_name}
      )

    case execute_engine_with_context(engine_name, input, execution_context) do
      {:ok, result} ->
        emit_telemetry(:engine_step_success, %{engine_name: engine_name}, execution_context)
        {:ok, result}

      {:error, reason} ->
        emit_telemetry(:engine_step_failure, %{engine_name: engine_name, reason: reason}, execution_context)
        {:error, reason}
    end
  end

  @doc false
  def execute_hybrid_step(arguments, _context) do
    %{
      capability: capability,
      step_input: input,
      execution_options: _opts
    } = arguments

    execution_context =
      ExecutionContext.create_hybrid_context(
        shared_state: %{step_type: :hybrid_step},
        telemetry_metadata: %{capability: capability}
      )

    case unified_execute(capability, input, execution_context) do
      {:ok, result} ->
        emit_telemetry(:hybrid_step_success, %{capability: capability}, execution_context)
        {:ok, result}

      {:error, reason} ->
        emit_telemetry(:hybrid_step_failure, %{capability: capability, reason: reason}, execution_context)
        {:error, reason}
    end
  end

  @doc false
  def execute_workflow_as_engine(input, opts \\ []) do
    workflow_name = opts[:workflow_name]

    execution_context =
      ExecutionContext.create_hybrid_context(
        workflow_context: %{adapter_type: :workflow_as_engine},
        telemetry_metadata: %{workflow_name: workflow_name}
      )

    execute_workflow_with_context(workflow_name, input, execution_context)
  end

  ## Private Execution Functions

  defp execute_engine_with_context(engine_name, input, context) do
    engine_context =
      if context do
        ExecutionContext.extract_engine_context(context)
      else
        %{}
      end

    case EngineManager.execute(engine_name, input, engine_context) do
      {:ok, result} ->
        if context do
          ExecutionContext.update_shared_state(context, %{
            last_engine_result: result,
            last_engine: engine_name
          })
        end

        {:ok, result}

      error ->
        error
    end
  end

  defp execute_workflow_with_context(workflow_name, input, context) do
    workflow_context =
      if context do
        ExecutionContext.extract_workflow_context(context)
      else
        %{}
      end

    case WorkflowExecutor.execute_workflow(workflow_name, input, workflow_context, []) do
      {:ok, result} ->
        if context do
          ExecutionContext.update_shared_state(context, %{
            last_workflow_result: result,
            last_workflow: workflow_name
          })
        end

        {:ok, result}

      error ->
        error
    end
  end

  defp execute_hybrid_with_context(hybrid_name, input, context) do
    # Hybrid execution combines both engine and workflow capabilities
    case CapabilityRegistry.find_by_id(hybrid_name) do
      nil ->
        {:error, {:hybrid_not_found, hybrid_name}}

      registration ->
        execute_hybrid_registration(registration, input, context)
    end
  end

  defp execute_hybrid_registration(registration, input, context) do
    case registration.metadata do
      %{type: :workflow_engine_adapter, workflow_name: workflow_name} ->
        execute_workflow_with_context(workflow_name, input, context)

      %{type: :engine_workflow_adapter, engine_name: engine_name} ->
        execute_engine_with_context(engine_name, input, context)

      %{type: :native_hybrid, module: module, function: function} ->
        apply(module, function, [input, context])

      _ ->
        {:error, {:unsupported_hybrid_type, registration.metadata.type}}
    end
  end

  ## Optimization Functions

  defp analyze_resource_requirements(hybrid_config, _context) do
    # Analyze resource needs for engines and workflows in the hybrid config
    engine_requirements = analyze_engine_requirements(hybrid_config)
    workflow_requirements = analyze_workflow_requirements(hybrid_config)

    total_requirements = %{
      cpu_cores: engine_requirements.cpu_cores + workflow_requirements.cpu_cores,
      memory_mb: engine_requirements.memory_mb + workflow_requirements.memory_mb,
      estimated_duration: max(engine_requirements.estimated_duration, workflow_requirements.estimated_duration),
      parallel_potential: engine_requirements.parallel_potential && workflow_requirements.parallel_potential
    }

    {:ok, total_requirements}
  end

  defp map_capabilities_to_implementations(hybrid_config) do
    # Map each required capability to available implementations
    capabilities = extract_required_capabilities(hybrid_config)

    capability_mapping =
      Enum.reduce(capabilities, %{}, fn capability, acc ->
        implementations = CapabilityRegistry.find_hybrid_compatible(capability)
        Map.put(acc, capability, implementations)
      end)

    {:ok, capability_mapping}
  end

  defp generate_optimization_plan(resource_analysis, capability_mapping) do
    # Generate an optimized execution plan based on resources and capabilities
    plan = %{
      execution_strategy: determine_execution_strategy(resource_analysis),
      capability_assignments: optimize_capability_assignments(capability_mapping),
      resource_allocation: optimize_resource_allocation(resource_analysis),
      parallelization_opportunities: identify_parallelization_opportunities(capability_mapping)
    }

    {:ok, plan}
  end

  ## Helper Functions

  defp analyze_engine_requirements(_hybrid_config) do
    # Placeholder implementation - would analyze actual engine requirements
    %{cpu_cores: 2, memory_mb: 512, estimated_duration: 5000, parallel_potential: true}
  end

  defp analyze_workflow_requirements(_hybrid_config) do
    # Placeholder implementation - would analyze actual workflow requirements
    %{cpu_cores: 1, memory_mb: 256, estimated_duration: 10000, parallel_potential: true}
  end

  defp extract_required_capabilities(_hybrid_config) do
    # Placeholder implementation - would extract capabilities from config
    [:semantic_analysis, :code_generation, :code_review]
  end

  defp determine_execution_strategy(resource_analysis) do
    if resource_analysis.parallel_potential do
      :parallel
    else
      :sequential
    end
  end

  defp optimize_capability_assignments(capability_mapping) do
    # Assign best implementation for each capability
    Enum.reduce(capability_mapping, %{}, fn {capability, implementations}, acc ->
      # Already sorted by priority
      best_implementation = List.first(implementations)
      Map.put(acc, capability, best_implementation)
    end)
  end

  defp optimize_resource_allocation(resource_analysis) do
    %{
      max_concurrent_engines: min(resource_analysis.cpu_cores, 4),
      memory_per_engine: div(resource_analysis.memory_mb, 2),
      timeout_multiplier: if(resource_analysis.estimated_duration > 30_000, do: 2, else: 1)
    }
  end

  defp identify_parallelization_opportunities(capability_mapping) do
    # Identify which capabilities can run in parallel
    independent_capabilities =
      Enum.filter(capability_mapping, fn {_cap, impls} ->
        # Has multiple implementations, can potentially parallelize
        length(impls) > 1
      end)

    Enum.map(independent_capabilities, fn {capability, _} -> capability end)
  end

  defp emit_telemetry(event, measurements, context) do
    metadata =
      if context do
        Map.merge(context.telemetry_metadata, %{
          execution_id: context.execution_id,
          execution_duration: ExecutionContext.execution_duration(context)
        })
      else
        %{}
      end

    :telemetry.execute([:rubber_duck, :hybrid, event], measurements, metadata)
  end
end
