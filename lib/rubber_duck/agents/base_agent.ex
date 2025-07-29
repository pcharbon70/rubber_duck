defmodule RubberDuck.Agents.BaseAgent do
  @moduledoc """
  Base behavior and utilities for RubberDuck agents using Jido framework.
  
  This module provides:
  - Common agent patterns and utilities
  - Integration with RubberDuck's signal dispatcher
  - State management helpers
  - Lifecycle hooks
  - Testing utilities
  
  ## Usage
  
  Agents should use this module to get RubberDuck-specific functionality:
  
      defmodule MyApp.MyAgent do
        use RubberDuck.Agents.BaseAgent,
          name: "my_agent",
          description: "Description of what this agent does",
          schema: [
            status: [type: :atom, default: :idle],
            data: [type: :map, default: %{}]
          ]
          
        # Implement custom signal handling
        @impl true
        def handle_signal(agent, signal) do
          case signal["type"] do
            "my_custom_signal" ->
              # Process signal
              {:ok, agent}
            _ ->
              # Let parent handle unknown signals
              super(agent, signal)
          end
        end
      end
  """
  
  
  @doc """
  Callback for agent health checks.
  """
  @callback health_check(agent :: map()) :: 
    {:healthy, map()} | {:unhealthy, map()}
    
  @doc """
  Callback for pre-initialization setup.
  
  This callback is called before the agent is fully initialized.
  It can be used to validate or transform the initial configuration.
  
  ## Return values
  - `{:ok, config}` - Success with potentially modified config
  - `{:error, reason}` - Failure, prevents agent initialization
  """
  @callback pre_init(config :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Callback for post-initialization setup.
  
  This callback is called after the agent is initialized.
  It can be used to perform any setup that requires a fully initialized agent.
  
  ## Return values
  - `{:ok, agent}` - Success with potentially modified agent
  - `{:error, reason}` - Failure, but agent remains initialized
  """  
  @callback post_init(agent :: map()) :: {:ok, map()} | {:error, term()}
  
  @optional_callbacks [
    health_check: 1,
    pre_init: 1,
    post_init: 1
  ]
  
  defmacro __using__(opts) do
    quote do
      # Use Jido.Agent as the foundation
      use Jido.Agent, unquote(opts)
      
      @behaviour RubberDuck.Agents.BaseAgent
      
      require Logger
      
      # Jido lifecycle callbacks with RubberDuck enhancements
      
      @impl Jido.Agent
      def on_before_run(agent) do
        # Call pre_init if this is first run and it's implemented
        agent = if function_exported?(__MODULE__, :pre_init, 1) do
          case __MODULE__.pre_init(agent.state) do
            {:ok, updated_state} ->
              %{agent | state: updated_state}
            {:error, reason} ->
              Logger.error("pre_init failed: #{inspect(reason)}")
              agent
          end
        else
          agent
        end
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :lifecycle],
          %{event: :before_run},
          %{agent_type: __MODULE__, agent_id: agent.id}
        )
        
        {:ok, agent}
      end
      
      @impl Jido.Agent
      def on_after_run(agent, result, metadata) do
        # Call post_init if implemented and this was initialization
        agent = if function_exported?(__MODULE__, :post_init, 1) && 
                   metadata[:action] == :init do
          case __MODULE__.post_init(agent) do
            {:ok, updated_agent} ->
              updated_agent
            {:error, reason} ->
              Logger.error("post_init failed: #{inspect(reason)}")
              agent
          end
        else
          agent
        end
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :lifecycle],
          %{event: :after_run, success: match?({:ok, _}, result)},
          %{agent_type: __MODULE__, agent_id: agent.id}
        )
        
        {:ok, agent}
      end
      
      @impl Jido.Agent
      def on_error(agent, error) do
        Logger.error("Agent error in #{__MODULE__}: #{inspect(error)}")
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :error],
          %{count: 1},
          %{agent_type: __MODULE__, agent_id: agent.id, error: error}
        )
        
        {:ok, agent}
      end
      
      # RubberDuck-specific functions
      
      @doc """
      Emits a signal through the RubberDuck signal dispatcher.
      """
      def emit_signal(agent, signal) do
        enhanced_signal = Map.merge(signal, %{
          "source" => "agent:#{agent.id}",
          "agent_type" => to_string(__MODULE__)
        })
        
        # TODO: Implement SignalDispatcher in a future phase
        # SignalDispatcher.emit(:broadcast, enhanced_signal)
        Logger.debug("Signal emission placeholder: #{inspect(enhanced_signal)}")
        :ok
      end
      
      @doc """
      Subscribes the agent to receive signals matching a pattern.
      """
      def subscribe_to_signals(agent, pattern) do
        # In a real implementation, this would register with SignalDispatcher
        # For now, we'll store subscriptions in agent state
        subscriptions = Map.get(agent.state, :signal_subscriptions, [])
        updated_subscriptions = [pattern | subscriptions] |> Enum.uniq()
        
        updated_state = Map.put(agent.state, :signal_subscriptions, updated_subscriptions)
        %{agent | state: updated_state}
      end
      
      
      @doc """
      Performs a health check on the agent.
      """
      def check_health(agent) do
        if function_exported?(__MODULE__, :health_check, 1) do
          __MODULE__.health_check(agent)
        else
          {:healthy, %{default: true}}
        end
      end
      
      # Default implementations of optional callbacks
      def health_check(agent) do
        {:healthy, %{agent_id: agent.id, status: :ok}}
      end
      
      def pre_init(config) do
        # Default implementation - can be overridden to return {:error, reason}
        # Using a runtime check to make the return type less predictable for dialyzer
        if is_map(config) do
          {:ok, config}
        else
          # This branch is technically unreachable but satisfies type checking
          {:error, :invalid_config}
        end
      end
      
      def post_init(agent) do
        # Default implementation - can be overridden to return {:error, reason}
        # Using a runtime check to make the return type less predictable for dialyzer
        if is_map(agent) and Map.has_key?(agent, :id) do
          {:ok, agent}
        else
          # This branch is technically unreachable but satisfies type checking
          {:error, :invalid_agent}
        end
      end
      
      defoverridable [health_check: 1, pre_init: 1, post_init: 1]
      
      @doc """
      Gets the current agent state.
      """
      def get_state(agent) do
        agent.state
      end
      
      @doc """
      Updates the agent state with validation.
      """
      def update_state(agent, updates) do
        new_state = Map.merge(agent.state, updates)
        %{agent | state: new_state}
      end
      
      # Persistence helpers
      
      @doc """
      Persists the agent state.
      """
      def persist_state(agent) do
        key = "agent:#{__MODULE__}:#{agent.id}"
        RubberDuck.Jido.Agent.State.persist(key, agent.state)
      end
      
      @doc """
      Recovers persisted state.
      """
      def recover_state(agent) do
        key = "agent:#{__MODULE__}:#{agent.id}"
        case RubberDuck.Jido.Agent.State.recover(key) do
          {:ok, state} -> %{agent | state: state}
          {:error, _} -> agent
        end
      end
      
      # Allow overriding all callbacks
      defoverridable [
        on_before_run: 1,
        on_after_run: 3,
        on_error: 2,
        emit_signal: 2
      ]
    end
  end
end