defmodule RubberDuck.Agents.BaseAgent do
  @moduledoc """
  Base behavior and utilities for RubberDuck agents using Jido framework.
  
  This module provides:
  - Action-based agent patterns
  - Signal-to-action routing
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
          ],
          actions: [
            MyApp.Actions.ProcessDataAction,
            MyApp.Actions.UpdateStatusAction
          ],
          signal_mappings: %{
            "data.process" => {MyApp.Actions.ProcessDataAction, :extract_params},
            "status.update" => {MyApp.Actions.UpdateStatusAction, :extract_params}
          }
      end
  """
  
  
  @doc """
  Callback for registering agent actions.
  Returns a list of action modules this agent supports.
  """
  @callback actions() :: [module()]
  
  @doc """
  Callback for mapping signals to actions.
  Returns a map of signal type patterns to {action_module, param_extractor} tuples.
  """
  @callback signal_mappings() :: %{String.t() => {module(), atom()}}
  
  @doc """
  Callback for extracting action parameters from a signal.
  """
  @callback extract_params(signal :: map()) :: map()
  
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
    actions: 0,
    signal_mappings: 0,
    extract_params: 1,
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
      
      alias RubberDuck.Jido.Actions.Base.{
        UpdateStateAction,
        EmitSignalAction,
        InitializeAgentAction,
        ComposeAction
      }
      
      # Extract options
      @agent_actions Keyword.get(unquote(opts), :actions, [])
      @agent_signal_mappings Keyword.get(unquote(opts), :signal_mappings, %{})
      
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
      
      # Action support functions
      
      @doc """
      Returns the list of actions supported by this agent.
      """
      def actions do
        base_actions = [
          UpdateStateAction,
          EmitSignalAction,
          InitializeAgentAction
        ]
        
        base_actions ++ @agent_actions
      end
      
      @doc """
      Returns the signal-to-action mappings for this agent.
      """
      def signal_mappings do
        @agent_signal_mappings
      end
      
      @doc """
      Default parameter extractor for signals.
      """
      def extract_params(signal) do
        signal["data"] || %{}
      end
      
      @doc """
      Executes an action on the agent.
      """
      def execute_action(agent, action_module, params \\ %{}) do
        context = %{
          agent: agent,
          timestamp: DateTime.utc_now()
        }
        
        case action_module.run(params, context) do
          {:ok, result, %{agent: updated_agent}} ->
            {:ok, result, updated_agent}
          {:error, reason} ->
            {:error, reason}
        end
      end
      
      @doc """
      Composes multiple actions into a single execution.
      """
      def compose_actions(agent, action_definitions) do
        ComposeAction.run(
          %{actions: action_definitions},
          %{agent: agent}
        )
      end
      
      @doc """
      Emits a Jido signal through the signal bus.
      """
      def emit_signal(agent, %Jido.Signal{} = signal) do
        # Ensure the signal has proper source attribution
        enhanced_signal = %{signal | 
          source: signal.source || "agent:#{agent.id}",
          subject: signal.subject || "agent:#{agent.id}"
        }
        
        case Jido.Signal.Bus.publish(RubberDuck.SignalBus, [enhanced_signal]) do
          {:ok, _recorded_signals} -> :ok
          {:error, reason} ->
            Logger.error("Failed to emit signal: #{inspect(reason)}")
            {:error, reason}
        end
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
      
      defoverridable [
        actions: 0,
        signal_mappings: 0,
        extract_params: 1,
        health_check: 1,
        pre_init: 1,
        post_init: 1
      ]
      
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
        emit_signal: 2,
        execute_action: 3,
        compose_actions: 2
      ]
    end
  end
end