defmodule RubberDuckEngines.Engine do
  @moduledoc """
  Behavior for defining analysis engines in the RubberDuck system.

  All analysis engines must implement this behavior to provide consistent
  interfaces for discovery, configuration, and analysis capabilities.
  """

  @type engine_state :: term()
  @type analysis_request :: RubberDuckCore.Analysis.t()
  @type analysis_result :: {:ok, map()} | {:error, String.t()}
  @type capability :: %{
          name: atom(),
          description: String.t(),
          input_types: [atom()],
          output_format: atom()
        }
  @type health_status :: :healthy | :degraded | :unhealthy

  @doc """
  Initializes the engine with the given configuration.

  Returns the initial state for the engine.
  """
  @callback init_engine(config :: map()) :: {:ok, engine_state()} | {:error, String.t()}

  @doc """
  Performs analysis on the given request.

  Takes an analysis request and the current engine state,
  returns the analysis result.
  """
  @callback analyze(analysis_request(), engine_state()) ::
              {analysis_result(), engine_state()}

  @doc """
  Returns the capabilities of this engine.

  Describes what types of analysis this engine can perform.
  """
  @callback capabilities() :: [capability()]

  @doc """
  Performs a health check on the engine.

  Returns the current health status and any diagnostic information.
  """
  @callback health_check(engine_state()) ::
              {health_status(), map(), engine_state()}

  @doc """
  Optional callback for handling configuration updates.

  If not implemented, engine restarts on configuration changes.
  """
  @callback handle_config_change(new_config :: map(), engine_state()) ::
              {:ok, engine_state()} | {:restart, map()}

  @optional_callbacks handle_config_change: 2

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour RubberDuckEngines.Engine

      use RubberDuckCore.BaseServer, Keyword.put(opts, :registry, RubberDuckEngines.Registry)

      alias RubberDuckCore.Analysis
      alias RubberDuckEngines.Engine

      # Override the BaseServer init to call engine init
      def initial_state(args) do
        config = Keyword.get(args, :config, %{})
        {:ok, state} = init_engine(config)
        state
      end

      # GenServer call handlers for engine operations
      def handle_call({:analyze, analysis_request}, _from, state) do
        {result, new_state} = analyze(analysis_request, state)
        {:reply, result, new_state}
      end

      def handle_call(:capabilities, _from, state) do
        {:reply, capabilities(), state}
      end

      def handle_call(:health_check, _from, state) do
        {health_status, diagnostics, new_state} = health_check(state)
        result = %{status: health_status, diagnostics: diagnostics}
        {:reply, result, new_state}
      end

      def handle_call({:config_change, new_config}, _from, state) do
        if function_exported?(__MODULE__, :handle_config_change, 2) do
          case __MODULE__.handle_config_change(new_config, state) do
            {:ok, new_state} -> {:reply, :ok, new_state}
            {:restart, restart_config} -> {:reply, {:restart, restart_config}, state}
          end
        else
          {:reply, {:restart, new_config}, state}
        end
      end

      # Default implementations that can be overridden
      def health_check(state) do
        {:healthy, %{timestamp: DateTime.utc_now()}, state}
      end

      defoverridable health_check: 1
    end
  end
end
