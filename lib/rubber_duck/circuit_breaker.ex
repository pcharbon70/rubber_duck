defmodule RubberDuck.CircuitBreaker do
  @moduledoc """
  Implements a circuit breaker pattern for external service calls.

  The circuit breaker prevents cascading failures by monitoring
  service health and temporarily blocking calls to failing services.

  ## States

  - **Closed**: Normal operation, requests pass through
  - **Open**: Service is failing, requests are blocked
  - **Half-Open**: Testing if service has recovered

  ## Usage

      # Define a circuit breaker for an LLM service
      defmodule MyApp.LLMBreaker do
        use RubberDuck.CircuitBreaker,
          name: :llm_service,
          failure_threshold: 5,
          timeout: 30_000,
          reset_timeout: 60_000
      end
      
      # Use the circuit breaker
      case MyApp.LLMBreaker.call(fn -> make_llm_request() end) do
        {:ok, response} -> handle_response(response)
        {:error, :circuit_open} -> handle_circuit_open()
        {:error, reason} -> handle_error(reason)
      end
  """

  use GenServer
  require Logger
  alias RubberDuck.Errors

  @default_failure_threshold 5
  @default_success_threshold 2
  @default_timeout 30_000
  @default_reset_timeout 60_000

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :state,
      :failure_count,
      :success_count,
      :last_failure_time,
      :failure_threshold,
      :success_threshold,
      :timeout,
      :reset_timeout,
      :half_open_calls
    ]
  end

  # Macro for defining circuit breakers

  defmacro __using__(opts) do
    quote do
      @circuit_breaker_opts unquote(opts)

      def child_spec(opts) do
        opts = Keyword.merge(@circuit_breaker_opts, opts)
        RubberDuck.CircuitBreaker.child_spec(opts)
      end

      def start_link(opts \\ []) do
        opts = Keyword.merge(@circuit_breaker_opts, opts)
        RubberDuck.CircuitBreaker.start_link(opts)
      end

      def call(fun, opts \\ []) do
        name = Keyword.get(@circuit_breaker_opts, :name, __MODULE__)
        RubberDuck.CircuitBreaker.call(name, fun, opts)
      end

      def state do
        name = Keyword.get(@circuit_breaker_opts, :name, __MODULE__)
        RubberDuck.CircuitBreaker.state(name)
      end

      def reset do
        name = Keyword.get(@circuit_breaker_opts, :name, __MODULE__)
        RubberDuck.CircuitBreaker.reset(name)
      end
    end
  end

  # Client API

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc """
  Executes a function through the circuit breaker.

  Returns:
  - `{:ok, result}` if the function succeeds
  - `{:error, :circuit_open}` if the circuit is open
  - `{:error, reason}` if the function fails
  """
  def call(name, fun, opts \\ []) when is_function(fun, 0) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(name), {:call, fun, timeout}, timeout + 1_000)
  end

  @doc """
  Returns the current state of the circuit breaker.
  """
  def state(name) do
    GenServer.call(via_tuple(name), :state)
  end

  @doc """
  Manually resets the circuit breaker to closed state.
  """
  def reset(name) do
    GenServer.call(via_tuple(name), :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %State{
      name: Keyword.get(opts, :name, __MODULE__),
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      success_threshold: Keyword.get(opts, :success_threshold, @default_success_threshold),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      reset_timeout: Keyword.get(opts, :reset_timeout, @default_reset_timeout),
      half_open_calls: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun, timeout}, _from, %State{state: :open} = state) do
    if should_attempt_reset?(state) do
      state = %{state | state: :half_open, half_open_calls: 0, success_count: 0}
      execute_call(fun, timeout, state)
    else
      report_circuit_open(state)
      {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call({:call, fun, timeout}, _from, %State{state: :half_open} = state) do
    if state.half_open_calls >= state.success_threshold do
      report_circuit_open(state)
      {:reply, {:error, :circuit_open}, state}
    else
      state = %{state | half_open_calls: state.half_open_calls + 1}
      execute_call(fun, timeout, state)
    end
  end

  def handle_call({:call, fun, timeout}, _from, %State{state: :closed} = state) do
    execute_call(fun, timeout, state)
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, format_state(state), state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        half_open_calls: 0
    }

    Logger.info("Circuit breaker #{state.name} manually reset")
    {:reply, :ok, new_state}
  end

  # Private Functions

  defp via_tuple(name) do
    {:via, Registry, {RubberDuck.CircuitBreakerRegistry, name}}
  end

  defp execute_call(fun, timeout, state) do
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          error -> {:error, error}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        state = handle_success(state)
        {:reply, {:ok, result}, state}

      {:ok, {:error, error}} ->
        state = handle_failure(state, error)
        {:reply, {:error, error}, state}

      nil ->
        state = handle_failure(state, :timeout)
        {:reply, {:error, :timeout}, state}
    end
  end

  defp handle_success(%State{state: :half_open} = state) do
    state = %{state | success_count: state.success_count + 1}

    if state.success_count >= state.success_threshold do
      Logger.info("Circuit breaker #{state.name} closed after successful recovery")
      %{state | state: :closed, failure_count: 0, success_count: 0}
    else
      state
    end
  end

  defp handle_success(state) do
    %{state | failure_count: 0}
  end

  defp handle_failure(%State{state: :half_open} = state, error) do
    Logger.warning("Circuit breaker #{state.name} failed in half-open state, reopening")
    report_failure(state, error)

    %{
      state
      | state: :open,
        last_failure_time: System.monotonic_time(:millisecond),
        failure_count: state.failure_count + 1
    }
  end

  defp handle_failure(state, error) do
    state = %{state | failure_count: state.failure_count + 1, last_failure_time: System.monotonic_time(:millisecond)}

    if state.failure_count >= state.failure_threshold do
      Logger.error("Circuit breaker #{state.name} opened after #{state.failure_count} failures")
      report_failure(state, error)
      %{state | state: :open}
    else
      state
    end
  end

  defp should_attempt_reset?(state) do
    time_since_failure = System.monotonic_time(:millisecond) - state.last_failure_time
    time_since_failure >= state.reset_timeout
  end

  defp report_circuit_open(state) do
    Errors.report_message(:warning, "Circuit breaker open", %{
      circuit_breaker: state.name,
      failure_count: state.failure_count,
      last_failure_time: state.last_failure_time
    })
  end

  defp report_failure(state, error) do
    error_info =
      case error do
        %{__struct__: _} = ex -> Errors.normalize_error(ex)
        other -> %{type: :unknown, message: inspect(other)}
      end

    Errors.report_message(:error, "Circuit breaker failure", %{
      circuit_breaker: state.name,
      failure_count: state.failure_count,
      error: error_info
    })
  end

  defp format_state(state) do
    %{
      name: state.name,
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      last_failure_time: state.last_failure_time,
      configuration: %{
        failure_threshold: state.failure_threshold,
        success_threshold: state.success_threshold,
        timeout: state.timeout,
        reset_timeout: state.reset_timeout
      }
    }
  end
end
