defmodule RubberDuck.Workflows.WorkflowBehavior do
  @moduledoc """
  Base behavior and macros for defining workflows in RubberDuck.

  Workflows orchestrate complex multi-step operations with automatic
  dependency resolution, concurrent execution, and error handling.

  ## Example

      defmodule MyWorkflow do
        use RubberDuck.Workflows.WorkflowBehavior
        
        workflow do
          step :fetch_data do
            run DataFetcher
            max_retries 3
          end
          
          step :process_data do
            run DataProcessor
            argument :data, result(:fetch_data)
          end
        end
      end
  """

  @type workflow_name :: atom() | String.t()
  @type step_name :: atom()
  @type step_result :: {:ok, term()} | {:error, term()}
  @type workflow_result :: %{
          status: :completed | :failed | :cancelled,
          results: %{step_name() => step_result()},
          errors: list(term()),
          metadata: map()
        }

  @callback name() :: workflow_name()
  @callback description() :: String.t()
  @callback steps() :: list(Reactor.Step.t())
  @callback version() :: String.t()

  defmacro __using__(opts) do
    quote do
      @behaviour RubberDuck.Workflows.WorkflowBehavior
      import RubberDuck.Workflows.WorkflowBehavior

      @workflow_opts unquote(opts)
      @before_compile RubberDuck.Workflows.WorkflowBehavior

      Module.register_attribute(__MODULE__, :workflow_steps, accumulate: true)
      Module.register_attribute(__MODULE__, :workflow_metadata, accumulate: false)

      # Default implementations
      def name, do: __MODULE__ |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()
      def description, do: @moduledoc || "Workflow: #{name()}"
      def version, do: "1.0.0"

      defoverridable name: 0, description: 0, version: 0
    end
  end

  @doc """
  Defines workflow metadata and configuration.
  """
  defmacro workflow(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a workflow step with its configuration.
  """
  defmacro step(name, opts \\ [], do: block) do
    # Parse at compile time
    step_config = parse_step_block(block)
    merged_config = Keyword.merge(opts, step_config)

    quote do
      @workflow_steps {unquote(name), unquote(Macro.escape(merged_config))}
    end
  end

  # Parse step configuration from AST at compile time
  defp parse_step_block(block) do
    parse_ast(block, [])
  end

  defp parse_ast({:__block__, _, statements}, acc) do
    Enum.reduce(statements, acc, &parse_ast/2)
  end

  defp parse_ast({:run, _, [module]}, acc) do
    [{:run, module} | acc]
  end

  defp parse_ast({:max_retries, _, [count]}, acc) do
    [{:max_retries, count} | acc]
  end

  defp parse_ast({:argument, _, [name, source]}, acc) do
    arg =
      case source do
        {:result, _, [step_name]} ->
          %{name: name, source: {:result, step_name}}

        _ ->
          %{name: name, source: source}
      end

    existing_args = Keyword.get(acc, :arguments, [])
    Keyword.put(acc, :arguments, existing_args ++ [arg])
  end

  defp parse_ast({:compensate, _, [module]}, acc) do
    [{:compensate, module} | acc]
  end

  defp parse_ast({:async?, _, [value]}, acc) do
    [{:async?, value} | acc]
  end

  defp parse_ast(_, acc), do: acc

  defmacro __before_compile__(env) do
    steps = Module.get_attribute(env.module, :workflow_steps, [])

    quote do
      def steps do
        unquote(Macro.escape(steps))
        |> Enum.map(fn {name, config} ->
          build_reactor_step(name, config)
        end)
      end

      @doc """
      Executes this workflow with the given input.
      """
      def run(input \\ %{}, opts \\ []) do
        RubberDuck.Workflows.Executor.run(__MODULE__, input, opts)
      end

      @doc """
      Executes this workflow asynchronously.
      """
      def run_async(input \\ %{}, opts \\ []) do
        RubberDuck.Workflows.Executor.run_async(__MODULE__, input, opts)
      end

      # Private helpers

      defp build_reactor_step(name, config) do
        # Convert our step config to Reactor.Step struct
        impl =
          if compensate = config[:compensate] do
            # If there's compensation, wrap the implementation
            {config[:run], compensate: compensate}
          else
            config[:run]
          end

        %Reactor.Step{
          name: name,
          impl: impl,
          arguments: config[:arguments] || [],
          max_retries: config[:max_retries] || 0,
          async?: config[:async?] || true
        }
      end
    end
  end

  @doc """
  Creates a new dynamic workflow.
  """
  def new(name, opts \\ []) do
    %{
      name: name,
      steps: [],
      metadata: opts[:metadata] || %{},
      version: opts[:version] || "1.0.0"
    }
  end

  @doc """
  Adds a step to a dynamic workflow.
  """
  def add_step(workflow, name, implementation, opts \\ []) do
    step = %{
      name: name,
      impl: implementation,
      arguments: opts[:arguments] || [],
      depends_on: opts[:depends_on] || [],
      max_retries: opts[:max_retries] || 0,
      compensate: opts[:compensate],
      async?: opts[:async?] || true
    }

    %{workflow | steps: workflow.steps ++ [step]}
  end

  @doc """
  Builds a dynamic workflow for execution.
  """
  def build(workflow) do
    # Convert to Reactor-compatible format
    reactor_steps =
      Enum.map(workflow.steps, fn step ->
        impl =
          if compensate = step[:compensate] do
            {step.impl, compensate: compensate}
          else
            step.impl
          end

        %Reactor.Step{
          name: step.name,
          impl: impl,
          arguments: build_arguments(step),
          max_retries: step.max_retries || 0,
          async?: Map.get(step, :async?, true)
        }
      end)

    %{workflow | steps: reactor_steps}
  end

  defp build_arguments(step) do
    # Convert arguments with dependency resolution
    Enum.map(step.arguments, fn
      {:result, dep_name} -> %Reactor.Argument{name: :input, source: %Reactor.Template.Result{name: dep_name}}
      {name, value} -> %Reactor.Argument{name: name, source: %Reactor.Template.Value{value: value}}
    end)
  end
end
