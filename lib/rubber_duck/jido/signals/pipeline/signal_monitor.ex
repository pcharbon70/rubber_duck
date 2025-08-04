defmodule RubberDuck.Jido.Signals.Pipeline.SignalMonitor do
  @moduledoc """
  Behaviour for signal monitoring in the processing pipeline.
  
  Signal monitors observe and collect metrics about signal flow,
  providing insights into system health, performance, and patterns.
  """
  
  @type monitor_result :: :ok | {:error, term()}
  @type metrics :: map()
  
  @doc """
  Observes a signal and collects relevant metrics.
  """
  @callback observe(signal :: map(), metadata :: map()) :: monitor_result()
  
  @doc """
  Returns current metrics collected by the monitor.
  """
  @callback get_metrics() :: metrics()
  
  @doc """
  Resets monitor metrics.
  """
  @callback reset_metrics() :: :ok
  
  @doc """
  Returns monitor health status.
  """
  @callback health_check() :: {:healthy | :degraded | :unhealthy, map()}
  
  @optional_callbacks [reset_metrics: 0, health_check: 0]
  
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour RubberDuck.Jido.Signals.Pipeline.SignalMonitor
      
      use GenServer
      require Logger
      
      @monitor_name unquote(Keyword.get(opts, :name, __MODULE__))
      @flush_interval unquote(Keyword.get(opts, :flush_interval, :timer.seconds(30)))
      
      # Client API
      
      def start_link(init_opts \\ []) do
        GenServer.start_link(__MODULE__, init_opts, name: __MODULE__)
      end
      
      def observe_signal(signal, metadata \\ %{}) do
        GenServer.cast(__MODULE__, {:observe, signal, metadata})
      end
      
      def get_current_metrics do
        GenServer.call(__MODULE__, :get_metrics)
      end
      
      def reset do
        GenServer.call(__MODULE__, :reset_metrics)
      end
      
      def check_health do
        GenServer.call(__MODULE__, :health_check)
      end
      
      # Server callbacks
      
      @impl GenServer
      def init(opts) do
        schedule_flush()
        {:ok, initialize_state(opts)}
      end
      
      @impl GenServer
      def handle_cast({:observe, signal, metadata}, state) do
        case observe(signal, metadata) do
          :ok ->
            {:noreply, update_state(state, signal, metadata)}
          {:error, reason} ->
            Logger.error("Monitor observation failed: #{inspect(reason)}")
            {:noreply, state}
        end
      end
      
      @impl GenServer
      def handle_call(:get_metrics, _from, state) do
        {:reply, get_metrics(), state}
      end
      
      @impl GenServer
      def handle_call(:reset_metrics, _from, state) do
        reset_metrics()
        {:reply, :ok, initialize_state([])}
      end
      
      @impl GenServer
      def handle_call(:health_check, _from, state) do
        {:reply, health_check(), state}
      end
      
      @impl GenServer
      def handle_info(:flush_metrics, state) do
        flush_to_telemetry(state)
        schedule_flush()
        {:noreply, state}
      end
      
      # Default implementations
      
      @impl true
      def reset_metrics, do: :ok
      
      @impl true
      def health_check do
        metrics = get_metrics()
        status = determine_health(metrics)
        {status, metrics}
      end
      
      defp initialize_state(opts), do: %{opts: opts}
      defp update_state(state, _signal, _metadata), do: state
      
      defp schedule_flush do
        Process.send_after(self(), :flush_metrics, @flush_interval)
      end
      
      defp flush_to_telemetry(state) do
        :telemetry.execute(
          [:rubber_duck, :signal, :monitor, @monitor_name],
          get_metrics(),
          %{monitor: @monitor_name}
        )
      end
      
      defp determine_health(metrics) do
        # Override in implementation
        :healthy
      end
      
      defoverridable [
        reset_metrics: 0,
        health_check: 0,
        initialize_state: 1,
        update_state: 3,
        determine_health: 1
      ]
    end
  end
end