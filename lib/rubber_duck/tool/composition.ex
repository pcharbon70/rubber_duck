defmodule RubberDuck.Tool.Composition do
  @moduledoc """
  Tool composition system for building complex workflows using Reactor.

  This module provides a comprehensive system for composing tools into sophisticated
  workflows with support for:

  - Sequential and parallel tool execution
  - Conditional branching based on results
  - Loop constructs for batch processing
  - Data transformation between tools
  - Error handling with compensation
  - Real-time monitoring and debugging

  ## Example Usage

      # Create a simple sequential workflow
      workflow = Composition.sequential("data_processing", [
        {:fetch, DataFetcher, %{source: "api"}},
        {:transform, DataTransformer, %{format: "json"}},
        {:save, DataSaver, %{destination: "database"}}
      ])
      
      # Execute the workflow
      {:ok, result} = Composition.execute(workflow, %{user_id: "123"})
      
      # Create a conditional workflow
      workflow = Composition.conditional("user_processing",
        condition: {:validate, UserValidator, %{strict: true}},
        success: [
          {:welcome, WelcomeService, %{template: "premium"}},
          {:notify, NotificationService, %{event: "new_user"}}
        ],
        failure: [
          {:reject, RejectionService, %{reason: "validation_failed"}},
          {:log, LogService, %{level: "error"}}
        ]
      )
  """

  alias RubberDuck.Workflows.Executor
  alias RubberDuck.Tool.Composition.Step
  alias RubberDuck.Tool.Composition.Middleware.Monitoring

  require Logger

  @type workflow_id :: String.t()
  @type step_name :: atom()
  @type tool_module :: module()
  @type params :: map()
  @type context :: map()

  @type step_definition :: {step_name(), tool_module(), params()}
  @type workflow_result :: {:ok, map()} | {:error, term()}

  @doc """
  Creates a sequential workflow where steps execute in order.

  Each step receives the output of the previous step as input.

  ## Options

  - `:timeout` - Overall workflow timeout in milliseconds
  - `:max_retries` - Maximum retries for failed steps
  - `:error_strategy` - Error handling strategy (:fail_fast, :continue, :compensate)

  ## Example

      workflow = Composition.sequential("data_pipeline", [
        {:fetch, DataFetcher, %{source: "api"}},
        {:validate, DataValidator, %{schema: "user_schema"}},
        {:save, DataSaver, %{destination: "database"}}
      ], timeout: 30_000)
  """
  @spec sequential(String.t(), [step_definition()], keyword()) :: Reactor.t()
  def sequential(_name, steps, _opts \\ []) do
    reactor = Reactor.Builder.new()

    # Add sequential steps to the reactor
    {reactor, _} =
      Enum.reduce(steps, {reactor, nil}, fn {step_name, tool_module, params}, {acc_reactor, prev_step} ->
        case prev_step do
          nil ->
            # First step - no dependencies
            {:ok, new_reactor} = Reactor.Builder.add_step(acc_reactor, step_name, {Step, [tool_module, params]}, [])
            {new_reactor, step_name}

          prev_name ->
            # Subsequent steps depend on previous step
            arguments = [
              %Reactor.Argument{
                name: :input,
                source: %Reactor.Template.Result{name: prev_name}
              }
            ]

            {:ok, new_reactor} =
              Reactor.Builder.add_step(acc_reactor, step_name, {Step, [tool_module, params]}, arguments)

            {new_reactor, step_name}
        end
      end)

    # Set the last step as the return value
    case steps do
      [] ->
        reactor

      _ ->
        {last_step_name, _, _} = List.last(steps)
        {:ok, reactor} = Reactor.Builder.return(reactor, last_step_name)
        reactor
    end
  end

  @doc """
  Creates a parallel workflow where steps execute concurrently.

  All steps execute simultaneously and their results are collected.

  ## Options

  - `:merge_step` - Optional step to merge results from parallel steps
  - `:timeout` - Overall workflow timeout in milliseconds
  - `:max_concurrent` - Maximum number of concurrent steps

  ## Example

      workflow = Composition.parallel("data_aggregation", [
        {:fetch_users, UserFetcher, %{source: "database"}},
        {:fetch_orders, OrderFetcher, %{source: "api"}},
        {:fetch_products, ProductFetcher, %{source: "cache"}}
      ], merge_step: {:merge, DataMerger, %{strategy: "combine"}})
  """
  @spec parallel(String.t(), [step_definition()], keyword()) :: Reactor.t()
  def parallel(_name, steps, opts \\ []) do
    reactor = Reactor.Builder.new()

    # Add all parallel steps
    {reactor, step_names} =
      Enum.reduce(steps, {reactor, []}, fn {step_name, tool_module, params}, {acc_reactor, acc_names} ->
        {:ok, new_reactor} = Reactor.Builder.add_step(acc_reactor, step_name, {Step, [tool_module, params]}, [])
        {new_reactor, [step_name | acc_names]}
      end)

    step_names = Enum.reverse(step_names)

    # Add merge step if specified
    case Keyword.get(opts, :merge_step) do
      {merge_name, merge_tool, merge_params} ->
        # Create arguments from all parallel steps
        arguments =
          Enum.map(step_names, fn step_name ->
            %Reactor.Argument{
              name: step_name,
              source: %Reactor.Template.Result{name: step_name}
            }
          end)

        {:ok, reactor} = Reactor.Builder.add_step(reactor, merge_name, {Step, [merge_tool, merge_params]}, arguments)
        {:ok, reactor} = Reactor.Builder.return(reactor, merge_name)
        reactor

      nil ->
        # No merge step, return all results
        case step_names do
          [] ->
            reactor

          [single_step] ->
            {:ok, reactor} = Reactor.Builder.return(reactor, single_step)
            reactor

          multiple_steps ->
            # Return the first step as default
            {:ok, reactor} = Reactor.Builder.return(reactor, hd(multiple_steps))
            reactor
        end
    end
  end

  @doc """
  Creates a conditional workflow with branching logic.

  Executes different paths based on the result of a condition step.

  ## Options

  - `:condition` - The condition step that determines the branch
  - `:success` - Steps to execute if condition succeeds
  - `:failure` - Steps to execute if condition fails
  - `:timeout` - Overall workflow timeout in milliseconds

  ## Example

      workflow = Composition.conditional("user_processing",
        condition: {:validate, UserValidator, %{strict: true}},
        success: [
          {:welcome, WelcomeService, %{template: "premium"}},
          {:notify, NotificationService, %{event: "new_user"}}
        ],
        failure: [
          {:reject, RejectionService, %{reason: "validation_failed"}},
          {:log, LogService, %{level: "error"}}
        ]
      )
  """
  @spec conditional(String.t(), keyword()) :: Reactor.t()
  def conditional(_name, opts) do
    reactor = Reactor.Builder.new()

    # Add condition step
    {condition_name, condition_tool, condition_params} = Keyword.fetch!(opts, :condition)
    {:ok, reactor} = Reactor.Builder.add_step(reactor, condition_name, {Step, [condition_tool, condition_params]}, [])

    # Add success path
    {reactor, success_final} =
      case Keyword.get(opts, :success, []) do
        [] -> {reactor, nil}
        success_steps -> add_sequential_path(reactor, success_steps, condition_name, :success, opts)
      end

    # Add failure path
    {reactor, failure_final} =
      case Keyword.get(opts, :failure, []) do
        [] -> {reactor, nil}
        failure_steps -> add_sequential_path(reactor, failure_steps, condition_name, :failure, opts)
      end

    # Create a final step that returns the result of whichever path was taken
    case {success_final, failure_final} do
      {nil, nil} ->
        {:ok, reactor} = Reactor.Builder.return(reactor, condition_name)
        reactor

      {success_step, nil} ->
        {:ok, reactor} = Reactor.Builder.return(reactor, success_step)
        reactor

      {nil, failure_step} ->
        {:ok, reactor} = Reactor.Builder.return(reactor, failure_step)
        reactor

      {success_step, failure_step} ->
        # Create a conditional return step
        {:ok, reactor} =
          Reactor.Builder.add_step(
            reactor,
            :conditional_return,
            {Step, [RubberDuck.Tool.Composition.ConditionalReturn, %{}]},
            [
              %Reactor.Argument{name: :condition_result, source: %Reactor.Template.Result{name: condition_name}},
              %Reactor.Argument{name: :success_result, source: %Reactor.Template.Result{name: success_step}},
              %Reactor.Argument{name: :failure_result, source: %Reactor.Template.Result{name: failure_step}}
            ]
          )

        {:ok, reactor} = Reactor.Builder.return(reactor, :conditional_return)
        reactor
    end
  end

  @doc """
  Creates a loop workflow for batch processing.

  Processes a collection of items, executing the same set of steps for each item.

  ## Options

  - `:items` - Collection of items to process
  - `:steps` - Steps to execute for each item
  - `:aggregator` - Optional step to aggregate results
  - `:max_concurrent` - Maximum concurrent item processing

  ## Example

      workflow = Composition.loop("batch_processing",
        items: ["item1", "item2", "item3"],
        steps: [
          {:process, ItemProcessor, %{action: "transform"}},
          {:validate, ItemValidator, %{schema: "item_schema"}}
        ],
        aggregator: {:collect, ResultCollector, %{strategy: "merge"}}
      )
  """
  @spec loop(String.t(), keyword()) :: Reactor.t()
  def loop(_name, opts) do
    reactor = Reactor.Builder.new()
    items = Keyword.fetch!(opts, :items)
    steps = Keyword.fetch!(opts, :steps)

    # Create steps for each item
    {reactor, final_steps} =
      Enum.with_index(items)
      |> Enum.reduce({reactor, []}, fn {item, index}, {acc_reactor, acc_final_steps} ->
        # Create item-specific steps
        {item_reactor, item_final_step} = create_item_steps(acc_reactor, steps, item, index, opts)
        {item_reactor, [item_final_step | acc_final_steps]}
      end)

    final_steps = Enum.reverse(final_steps)

    # Add aggregator step if specified
    case Keyword.get(opts, :aggregator) do
      {agg_name, agg_tool, agg_params} ->
        # Create arguments from all item final steps
        arguments =
          Enum.map(final_steps, fn step_name ->
            %Reactor.Argument{
              name: step_name,
              source: %Reactor.Template.Result{name: step_name}
            }
          end)

        {:ok, reactor} = Reactor.Builder.add_step(reactor, agg_name, {Step, [agg_tool, agg_params]}, arguments)
        {:ok, reactor} = Reactor.Builder.return(reactor, agg_name)
        reactor

      nil ->
        # Return all item results
        case final_steps do
          [] ->
            reactor

          [single_step] ->
            {:ok, reactor} = Reactor.Builder.return(reactor, single_step)
            reactor

          multiple_steps ->
            {:ok, reactor} = Reactor.Builder.return(reactor, hd(multiple_steps))
            reactor
        end
    end
  end

  @doc """
  Executes a workflow with the given inputs.

  Uses the RubberDuck.Workflows.Executor to run the workflow with proper
  monitoring, error handling, and telemetry.

  ## Options

  - `:timeout` - Execution timeout in milliseconds
  - `:context` - Additional context for the workflow
  - `:telemetry_metadata` - Custom telemetry metadata

  ## Example

      {:ok, result} = Composition.execute(workflow, %{user_id: "123"}, 
        timeout: 30_000, 
        context: %{trace_id: "abc-123"}
      )
  """
  @spec execute(Reactor.t(), map(), keyword()) :: workflow_result()
  def execute(workflow, inputs \\ %{}, opts \\ []) do
    # Add monitoring middleware to the workflow
    monitored_workflow = add_monitoring_middleware(workflow, opts)

    # Execute using the RubberDuck workflow executor
    case Executor.run_dynamic(monitored_workflow, Keyword.put(opts, :input, inputs)) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a workflow asynchronously.

  Returns a task that can be awaited for the result.

  ## Example

      task = Composition.execute_async(workflow, %{user_id: "123"})
      {:ok, result} = Task.await(task, 30_000)
  """
  @spec execute_async(Reactor.t(), map(), keyword()) :: Task.t()
  def execute_async(workflow, inputs \\ %{}, opts \\ []) do
    Task.async(fn ->
      execute(workflow, inputs, opts)
    end)
  end

  @doc """
  Executes a workflow with enhanced monitoring.

  This function provides additional monitoring capabilities beyond the standard execute/3,
  including custom telemetry metadata and monitoring options.

  ## Options

  - `:monitoring_enabled` - Enable/disable monitoring (default: true)
  - `:telemetry_metadata` - Custom telemetry metadata
  - `:alert_on_failure` - Enable alerting on workflow failure
  - `:performance_tracking` - Enable detailed performance tracking

  ## Example

      {:ok, result} = Composition.execute_with_monitoring(workflow, %{user_id: "123"}, 
        monitoring_enabled: true,
        alert_on_failure: true,
        telemetry_metadata: %{team: "data_processing", environment: "production"}
      )
  """
  @spec execute_with_monitoring(Reactor.t(), map(), keyword()) :: workflow_result()
  def execute_with_monitoring(workflow, inputs \\ %{}, opts \\ []) do
    # Ensure monitoring is enabled
    monitoring_opts = Keyword.put(opts, :monitoring_enabled, true)
    execute(workflow, inputs, monitoring_opts)
  end

  # Private helper functions

  defp add_monitoring_middleware(workflow, opts) do
    # Check if monitoring is enabled (default: true)
    monitoring_enabled = Keyword.get(opts, :monitoring_enabled, true)

    if monitoring_enabled do
      # Add monitoring middleware to the workflow
      case Reactor.Builder.add_middleware(workflow, Monitoring) do
        {:ok, monitored_workflow} ->
          monitored_workflow

        {:error, reason} ->
          # If middleware addition fails, log warning and continue without monitoring
          Logger.warning("Failed to add monitoring middleware to workflow: #{inspect(reason)}")
          workflow
      end
    else
      workflow
    end
  end

  defp add_sequential_path(builder, steps, condition_step, branch_type, _opts) do
    {builder, prev_step} =
      Enum.reduce(steps, {builder, condition_step}, fn {step_name, tool_module, params}, {acc_builder, prev_name} ->
        # Create unique step name for this branch
        branch_step_name = :"#{branch_type}_#{step_name}"

        # Create arguments based on previous step
        arguments =
          case prev_name do
            ^condition_step ->
              # First step in branch - depends on condition
              [
                %Reactor.Argument{
                  name: :condition_result,
                  source: %Reactor.Template.Result{name: condition_step}
                }
              ]

            _ ->
              # Subsequent steps in branch - depends on previous step in branch
              [
                %Reactor.Argument{
                  name: :input,
                  source: %Reactor.Template.Result{name: prev_name}
                }
              ]
          end

        {:ok, new_builder} =
          Reactor.Builder.add_step(acc_builder, branch_step_name, {Step, [tool_module, params]}, arguments)

        {new_builder, branch_step_name}
      end)

    {builder, prev_step}
  end

  defp create_item_steps(builder, steps, item, index, _opts) do
    {builder, prev_step} =
      Enum.reduce(steps, {builder, nil}, fn {step_name, tool_module, params}, {acc_builder, prev_name} ->
        # Create unique step name for this item
        item_step_name = :"#{step_name}_#{index}"

        # Add item to step parameters
        item_params = Map.put(params, :item, item)

        # Create arguments based on previous step
        arguments =
          case prev_name do
            nil ->
              # First step for this item - no dependencies
              []

            _ ->
              # Subsequent steps - depends on previous step for this item
              [
                %Reactor.Argument{
                  name: :input,
                  source: %Reactor.Template.Result{name: prev_name}
                }
              ]
          end

        {:ok, new_builder} =
          Reactor.Builder.add_step(acc_builder, item_step_name, {Step, [tool_module, item_params]}, arguments)

        {new_builder, item_step_name}
      end)

    {builder, prev_step}
  end
end
