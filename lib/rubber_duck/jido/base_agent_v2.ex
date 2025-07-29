defmodule RubberDuck.Jido.BaseAgentV2 do
  @moduledoc """
  Base module for creating Jido agents in RubberDuck.
  
  This module provides a foundation for building Jido agents with:
  - Standard lifecycle callbacks
  - State management utilities
  - Signal handling integration
  - Telemetry support
  
  ## Usage
  
      defmodule MyAgent do
        use RubberDuck.Jido.BaseAgentV2,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            counter: [type: :integer, default: 0],
            status: [type: :atom, default: :idle]
          ]
      end
  """
  
  @doc """
  Macro to set up a Jido agent with RubberDuck enhancements.
  """
  defmacro __using__(opts) do
    quote do
      use Jido.Agent, unquote(opts)
      
      alias RubberDuck.Jido.Agent.{State, Helpers}
      alias RubberDuck.Jido.SignalDispatcher
      require Logger
      
      # Default lifecycle callbacks that can be overridden
      
      @impl Jido.Agent
      def on_before_validate_state(state) do
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :lifecycle],
          %{event: :before_validate_state},
          %{agent: __MODULE__, state: state}
        )
        
        {:ok, state}
      end
      
      @impl Jido.Agent
      def on_after_validate_state(state) do
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :lifecycle],
          %{event: :after_validate_state},
          %{agent: __MODULE__, state: state}
        )
        
        {:ok, state}
      end
      
      @impl Jido.Agent
      def on_before_plan(agent, instructions, opts) do
        Logger.debug("Agent #{inspect(__MODULE__)} planning: #{inspect(instructions)}")
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :planning],
          %{instructions_count: length(instructions)},
          %{agent: __MODULE__, opts: opts}
        )
        
        {:ok, agent, instructions, opts}
      end
      
      @impl Jido.Agent
      def on_before_run(agent) do
        Logger.debug("Agent #{inspect(__MODULE__)} starting execution")
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :execution],
          %{event: :before_run},
          %{agent: __MODULE__}
        )
        
        {:ok, agent}
      end
      
      @impl Jido.Agent
      def on_after_run(agent, result, _metadata) do
        Logger.debug("Agent #{inspect(__MODULE__)} completed execution: #{inspect(result)}")
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :execution],
          %{event: :after_run, success: match?({:ok, _}, result)},
          %{agent: __MODULE__, result: result}
        )
        
        {:ok, agent}
      end
      
      @impl Jido.Agent
      def on_error(agent, error) do
        Logger.error("Agent #{inspect(__MODULE__)} error: #{inspect(error)}")
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :error],
          %{count: 1},
          %{agent: __MODULE__, error: error}
        )
        
        {:ok, agent}
      end
      
      # Additional helper functions
      
      @doc """
      Emits a signal from this agent.
      """
      def emit_signal(agent, signal) do
        enhanced_signal = Map.merge(signal, %{
          "source" => "#{__MODULE__}:#{agent.id}",
          "agent_type" => __MODULE__
        })
        
        SignalDispatcher.emit(:broadcast, enhanced_signal)
      end
      
      @doc """
      Handles incoming signals for this agent.
      """
      def handle_signal(agent, signal) do
        Logger.debug("Agent #{inspect(__MODULE__)} received signal: #{inspect(signal)}")
        {:ok, agent}
      end
      
      # Allow overriding all callbacks
      defoverridable [
        on_before_validate_state: 1,
        on_after_validate_state: 1,
        on_before_plan: 3,
        on_before_run: 1,
        on_after_run: 3,
        on_error: 2,
        emit_signal: 2,
        handle_signal: 2
      ]
    end
  end
end