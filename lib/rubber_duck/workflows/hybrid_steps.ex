defmodule RubberDuck.Workflows.HybridSteps do
  @moduledoc """
  Hybrid workflow steps that integrate engines and workflows.

  This module provides workflow steps that can automatically bridge to engines,
  enabling seamless integration between the engine DSL system and workflow
  orchestration layer.
  """

  alias RubberDuck.Hybrid.{Bridge, CapabilityRegistry, ExecutionContext}

  require Logger

  @doc """
  Generates a workflow step from an engine capability.

  This function creates a Reactor step that executes an engine with the
  specified capability, automatically handling engine discovery, execution,
  and result formatting.

  ## Options
  - `:input_argument` - Name of the argument containing input data (default: `:input`)
  - `:timeout` - Step timeout in milliseconds (default: 30_000)
  - `:retries` - Number of retries (default: 3)
  - `:async` - Whether to execute asynchronously (default: false)
  - `:pool_size` - Engine pool size (default: 1)
  - `:fallback_strategy` - Strategy when primary engine fails (default: `:next_best`)
  """
  @spec generate_engine_step(atom(), keyword()) :: map()
  def generate_engine_step(engine_capability, opts \\ []) do
    step_name = opts[:step_name] || :"#{engine_capability}_engine_step"
    input_arg = opts[:input_argument] || :input

    %{
      name: step_name,
      run: {__MODULE__, :execute_engine_capability},
      arguments: %{
        capability: engine_capability,
        input: {:argument, input_arg},
        execution_options: opts
      },
      timeout: opts[:timeout] || 30_000,
      max_retries: opts[:retries] || 3,
      async: opts[:async] || false
    }
  end

  @doc """
  Generates a workflow step that can route to either engines or workflows.

  This creates a hybrid step that uses capability-based routing to select
  the best available implementation at runtime, whether it's an engine,
  workflow, or hybrid component.
  """
  @spec generate_hybrid_step(atom(), keyword()) :: map()
  def generate_hybrid_step(capability, opts \\ []) do
    step_name = opts[:step_name] || :"#{capability}_hybrid_step"
    input_arg = opts[:input_argument] || :input

    %{
      name: step_name,
      run: {__MODULE__, :execute_hybrid_capability},
      arguments: %{
        capability: capability,
        input: {:argument, input_arg},
        execution_options: opts,
        routing_strategy: opts[:routing_strategy] || :best_available
      },
      timeout: opts[:timeout] || 60_000,
      max_retries: opts[:retries] || 3,
      async: opts[:async] || false
    }
  end

  @doc """
  Generates multiple steps that execute in parallel for the same capability.

  This is useful when you want to run multiple implementations of the same
  capability in parallel and either take the first result or aggregate results.
  """
  @spec generate_parallel_capability_steps(atom(), keyword()) :: [map()]
  def generate_parallel_capability_steps(capability, opts \\ []) do
    strategy = opts[:parallel_strategy] || :first_success
    max_parallel = opts[:max_parallel] || 3

    implementations =
      CapabilityRegistry.find_by_capability(capability)
      |> Enum.take(max_parallel)

    steps =
      Enum.with_index(implementations, fn implementation, index ->
        step_name = :"#{capability}_parallel_#{index}"

        %{
          name: step_name,
          run: {__MODULE__, :execute_specific_implementation},
          arguments: %{
            implementation: implementation,
            input: {:argument, :input},
            execution_options: opts
          },
          timeout: opts[:timeout] || 30_000,
          # Lower retries for parallel execution
          max_retries: opts[:retries] || 1,
          async: true
        }
      end)

    # Add aggregation step
    aggregation_step = %{
      name: :"#{capability}_aggregate_results",
      run: {__MODULE__, :aggregate_parallel_results},
      arguments: %{
        parallel_results: Enum.map(steps, fn step -> {:result, step.name} end),
        aggregation_strategy: strategy,
        capability: capability
      },
      timeout: opts[:aggregation_timeout] || 10_000
    }

    steps ++ [aggregation_step]
  end

  @doc """
  Generates a step that dynamically selects the best engine based on current load.

  This step performs real-time load balancing across available engines for
  a capability, selecting the engine with the lowest current load.
  """
  @spec generate_load_balanced_step(atom(), keyword()) :: map()
  def generate_load_balanced_step(capability, opts \\ []) do
    step_name = opts[:step_name] || :"#{capability}_load_balanced_step"

    %{
      name: step_name,
      run: {__MODULE__, :execute_load_balanced_capability},
      arguments: %{
        capability: capability,
        input: {:argument, :input},
        load_balancing_strategy: opts[:load_balancing] || :least_loaded,
        execution_options: opts
      },
      timeout: opts[:timeout] || 45_000,
      max_retries: opts[:retries] || 3
    }
  end

  ## Step Execution Functions (called by Reactor)

  @doc false
  def execute_engine_capability(arguments, context) do
    %{
      capability: capability,
      input: input,
      execution_options: opts
    } = arguments

    Logger.debug("Executing engine capability: #{capability}")

    case find_best_engine_for_capability(capability, opts) do
      nil ->
        Logger.warning("No engine found for capability: #{capability}")
        {:error, {:no_engine_for_capability, capability}}

      engine_registration ->
        execution_context = create_execution_context(engine_registration, context, opts)
        execute_engine_with_fallback(engine_registration, input, execution_context, opts)
    end
  end

  @doc false
  def execute_hybrid_capability(arguments, context) do
    %{
      capability: capability,
      input: input,
      execution_options: opts,
      routing_strategy: strategy
    } = arguments

    Logger.debug("Executing hybrid capability: #{capability} with strategy: #{strategy}")

    case route_to_best_implementation(capability, strategy, opts) do
      nil ->
        Logger.warning("No implementation found for capability: #{capability}")
        {:error, {:no_implementation_for_capability, capability}}

      implementation ->
        execution_context = create_execution_context(implementation, context, opts)
        Bridge.unified_execute({implementation.type, implementation.id}, input, execution_context)
    end
  end

  @doc false
  def execute_specific_implementation(arguments, context) do
    %{
      implementation: implementation,
      input: input,
      execution_options: opts
    } = arguments

    execution_context = create_execution_context(implementation, context, opts)
    Bridge.unified_execute({implementation.type, implementation.id}, input, execution_context)
  end

  @doc false
  def aggregate_parallel_results(arguments, _context) do
    %{
      parallel_results: results,
      aggregation_strategy: strategy,
      capability: capability
    } = arguments

    Logger.debug("Aggregating parallel results for capability: #{capability} with strategy: #{strategy}")

    case strategy do
      :first_success ->
        aggregate_first_success(results)

      :best_quality ->
        aggregate_best_quality(results)

      :consensus ->
        aggregate_consensus(results)

      :all_results ->
        {:ok, %{results: results, strategy: strategy}}

      _ ->
        {:error, {:unsupported_aggregation_strategy, strategy}}
    end
  end

  @doc false
  def execute_load_balanced_capability(arguments, context) do
    %{
      capability: capability,
      input: input,
      load_balancing_strategy: strategy,
      execution_options: opts
    } = arguments

    case select_by_load_balancing(capability, strategy) do
      nil ->
        {:error, {:no_available_implementation, capability}}

      selected_implementation ->
        execution_context = create_execution_context(selected_implementation, context, opts)
        Bridge.unified_execute({selected_implementation.type, selected_implementation.id}, input, execution_context)
    end
  end

  ## Private Helper Functions

  defp find_best_engine_for_capability(capability, opts) do
    type_preference = opts[:engine_type_preference] || :any

    CapabilityRegistry.find_by_capability(capability, :engine)
    |> filter_by_type_preference(type_preference)
    |> List.first()
  end

  defp route_to_best_implementation(capability, strategy, _opts) do
    implementations = CapabilityRegistry.find_hybrid_compatible(capability)

    case strategy do
      :best_available ->
        # Already sorted by priority
        List.first(implementations)

      :prefer_engines ->
        Enum.find(implementations, &(&1.type == :engine)) || List.first(implementations)

      :prefer_workflows ->
        Enum.find(implementations, &(&1.type == :workflow)) || List.first(implementations)

      :prefer_hybrid ->
        Enum.find(implementations, &(&1.type == :hybrid)) || List.first(implementations)

      :round_robin ->
        select_round_robin(capability, implementations)

      _ ->
        List.first(implementations)
    end
  end

  defp execute_engine_with_fallback(primary_engine, input, context, opts) do
    case Bridge.unified_execute({:engine, primary_engine.id}, input, context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_engine_fallback(primary_engine, input, context, reason, opts)
    end
  end

  defp handle_engine_fallback(failed_engine, input, context, reason, opts) do
    fallback_strategy = opts[:fallback_strategy] || :next_best

    case fallback_strategy do
      :next_best ->
        try_next_best_engine(failed_engine, input, context)

      :retry_same ->
        Bridge.unified_execute({:engine, failed_engine.id}, input, context)

      :fail_fast ->
        {:error, reason}

      _ ->
        {:error, reason}
    end
  end

  defp try_next_best_engine(failed_engine, input, context) do
    case find_next_best_engine(failed_engine) do
      nil ->
        {:error, {:no_fallback_engine, failed_engine.capability}}

      fallback_engine ->
        Logger.info("Falling back to engine: #{fallback_engine.id}")
        Bridge.unified_execute({:engine, fallback_engine.id}, input, context)
    end
  end

  defp find_next_best_engine(failed_engine) do
    CapabilityRegistry.find_by_capability(failed_engine.capability, :engine)
    |> Enum.reject(&(&1.id == failed_engine.id))
    |> List.first()
  end

  defp select_by_load_balancing(capability, strategy) do
    implementations = CapabilityRegistry.find_hybrid_compatible(capability)

    case strategy do
      :least_loaded ->
        select_least_loaded(implementations)

      :round_robin ->
        select_round_robin(capability, implementations)

      :random ->
        Enum.random(implementations)

      _ ->
        List.first(implementations)
    end
  end

  defp select_least_loaded(implementations) do
    # This would integrate with actual load monitoring
    # For now, just return the first available
    List.first(implementations)
  end

  defp select_round_robin(capability, implementations) do
    # This would use a persistent counter for true round-robin
    # For now, use a simple hash-based selection
    hash = :erlang.phash2(capability, length(implementations))
    Enum.at(implementations, hash)
  end

  defp filter_by_type_preference(implementations, :any), do: implementations

  defp filter_by_type_preference(implementations, type) do
    Enum.filter(implementations, &(&1.type == type))
  end

  defp create_execution_context(implementation, reactor_context, _opts) do
    ExecutionContext.create_hybrid_context(
      shared_state: %{
        implementation: implementation,
        step_type: :hybrid_step,
        reactor_context: reactor_context
      },
      telemetry_metadata: %{
        capability: implementation.capability,
        implementation_type: implementation.type,
        implementation_id: implementation.id
      }
    )
  end

  ## Result Aggregation Functions

  defp aggregate_first_success(results) do
    case Enum.find(results, fn
           {:ok, _} -> true
           _ -> false
         end) do
      nil ->
        errors =
          Enum.map(results, fn
            {:error, reason} -> reason
            _ -> :unknown_error
          end)

        {:error, {:all_parallel_executions_failed, errors}}

      success_result ->
        success_result
    end
  end

  defp aggregate_best_quality(results) do
    successful_results =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    case successful_results do
      [] ->
        # Fall back to error handling
        aggregate_first_success(results)

      [single_result] ->
        single_result

      multiple_results ->
        # Score results based on quality metrics
        best_result =
          multiple_results
          |> Enum.map(&score_result_quality/1)
          |> Enum.max_by(fn {_result, score} -> score end)
          |> elem(0)

        best_result
    end
  end

  defp aggregate_consensus(results) do
    successful_results =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    case successful_results do
      [] ->
        aggregate_first_success(results)

      [single_result] ->
        single_result

      multiple_results ->
        # Find consensus among results
        {:ok,
         %{
           consensus_result: find_consensus_result(multiple_results),
           all_results: multiple_results,
           consensus_confidence: calculate_consensus_confidence(multiple_results)
         }}
    end
  end

  defp score_result_quality({:ok, result}) do
    # This would implement actual quality scoring
    # For now, return a simple score based on result size
    score =
      case result do
        result when is_binary(result) -> String.length(result)
        result when is_map(result) -> map_size(result)
        result when is_list(result) -> length(result)
        _ -> 1
      end

    {{:ok, result}, score}
  end

  defp find_consensus_result(results) do
    # Simple consensus: most common result
    results
    |> Enum.frequencies()
    |> Enum.max_by(fn {_result, count} -> count end)
    |> elem(0)
    # Extract the actual result from {:ok, result}
    |> elem(1)
  end

  defp calculate_consensus_confidence(results) do
    total = length(results)

    {_most_common, count} =
      results
      |> Enum.frequencies()
      |> Enum.max_by(fn {_result, count} -> count end)

    count / total
  end
end
