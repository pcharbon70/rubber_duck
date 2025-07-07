defmodule RubberDuck.Workflows.Step do
  @moduledoc """
  Behavior and utilities for workflow steps.

  Steps are the atomic units of work in a workflow. Each step should:
  - Perform a single, well-defined operation
  - Be idempotent when possible
  - Handle errors gracefully
  - Support compensation for rollback
  """

  @type input :: map()
  @type output :: term()
  @type context :: map()
  @type step_result :: {:ok, output()} | {:error, term()} | {:halt, term()}

  @doc """
  Executes the step with the given input and context.
  """
  @callback run(input(), context()) :: step_result()

  @doc """
  Compensates for this step during rollback.
  Optional callback - only needed if the step has side effects.
  """
  @callback compensate(input(), output(), context()) :: :ok | {:error, term()}

  @doc """
  Validates the input before execution.
  Optional callback - defaults to always valid.
  """
  @callback validate(input()) :: :ok | {:error, term()}

  @doc """
  Returns metadata about this step.
  Optional callback.
  """
  @callback metadata() :: map()

  @optional_callbacks [compensate: 3, validate: 1, metadata: 0]

  defmacro __using__(opts) do
    quote do
      @behaviour RubberDuck.Workflows.Step
      @behaviour Reactor.Step

      @step_opts unquote(opts)

      # Reactor.Step required callbacks
      @impl Reactor.Step
      def run(arguments, context, _options) do
        input = arguments_to_input(arguments)

        # Run validation if implemented
        with :ok <- validate_input(input) do
          # Call our run callback
          case run(input, context) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
            {:halt, reason} -> {:halt, reason}
          end
        end
      end

      @impl Reactor.Step
      def compensate(_reason, arguments, context, _options) do
        if function_exported?(__MODULE__, :compensate, 3) do
          input = arguments_to_input(arguments)
          output = context[:step_output] || nil

          case __MODULE__.compensate(input, output, context) do
            :ok -> :ok
            {:error, _reason} = error -> error
          end
        else
          # No compensation needed
          :ok
        end
      end

      @impl Reactor.Step
      def async?(_step) do
        # By default, steps can run asynchronously
        true
      end

      @impl Reactor.Step
      def can?(_step, :compensate) do
        # Check if the module implements compensate/3
        function_exported?(__MODULE__, :compensate, 3)
      end

      def can?(_step, _capability), do: false

      # Default implementations
      def validate(_input), do: :ok
      def metadata, do: %{}

      defoverridable validate: 1, metadata: 0

      # Private helpers

      defp arguments_to_input(arguments) do
        # Convert Reactor arguments to a map
        Enum.reduce(arguments, %{}, fn arg, acc ->
          Map.put(acc, arg.name, arg.value)
        end)
      end

      defp validate_input(input) do
        if function_exported?(__MODULE__, :validate, 1) do
          validate(input)
        else
          :ok
        end
      end
    end
  end

  @doc """
  Creates a simple step from a function.
  """
  def from_function(name, fun, opts \\ []) when is_function(fun, 2) do
    %{
      __struct__: Reactor.Step,
      name: name,
      impl: {__MODULE__.FunctionStep, function: fun},
      arguments: opts[:arguments] || [],
      max_retries: opts[:max_retries] || 0,
      compensate: opts[:compensate],
      async?: opts[:async?] || true
    }
  end

  @doc """
  Helper to create a step that transforms its input.
  """
  def transform(name, transformer, opts \\ []) do
    from_function(
      name,
      fn input, _context ->
        case transformer.(input) do
          {:ok, _} = success -> success
          {:error, _} = error -> error
          result -> {:ok, result}
        end
      end,
      opts
    )
  end

  @doc """
  Helper to create a step that filters/validates input.
  """
  def filter(name, predicate, opts \\ []) do
    error_message = opts[:error_message] || "Filter failed"

    from_function(
      name,
      fn input, _context ->
        if predicate.(input) do
          {:ok, input}
        else
          {:error, error_message}
        end
      end,
      opts
    )
  end

  @doc """
  Helper to create a step that logs and passes through.
  """
  def log(name, opts \\ []) do
    level = opts[:level] || :info
    message = opts[:message] || "Step: #{name}"

    from_function(
      name,
      fn input, context ->
        require Logger

        Logger.log(level, message,
          workflow_id: context[:workflow_id],
          step: name,
          input: inspect(input)
        )

        {:ok, input}
      end,
      opts
    )
  end

  defmodule FunctionStep do
    @moduledoc false

    @behaviour RubberDuck.Workflows.Step
    @behaviour Reactor.Step

    @impl RubberDuck.Workflows.Step
    def run(input, context) do
      fun = Keyword.fetch!(Application.get_env(:rubber_duck, __MODULE__), :function)
      fun.(input, context)
    end

    @impl Reactor.Step
    def run(arguments, context, _options) do
      input = arguments_to_input(arguments)
      run(input, context)
    end

    @impl Reactor.Step
    def compensate(_reason, _arguments, _context, _options) do
      :ok
    end

    @impl Reactor.Step
    def async?(_step) do
      true
    end

    @impl Reactor.Step
    def can?(_step, :compensate), do: false
    def can?(_step, _capability), do: false

    defp arguments_to_input(arguments) do
      Enum.reduce(arguments, %{}, fn arg, acc ->
        Map.put(acc, arg.name, arg.value)
      end)
    end
  end
end
