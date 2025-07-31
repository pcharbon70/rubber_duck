defmodule RubberDuck.Jido.Actions.Base.InitializeAgentAction do
  @moduledoc """
  Base action for initializing agents in the Jido pattern.
  
  This action handles agent initialization, including setting up
  default state, running pre/post initialization hooks, and
  emitting initialization signals.
  """
  
  use Jido.Action,
    name: "initialize_agent",
    description: "Initializes an agent with proper state and lifecycle hooks",
    schema: [
      initial_state: [
        type: :map,
        default: %{},
        doc: "Initial state to merge with defaults"
      ],
      skip_hooks: [
        type: :boolean,
        default: false,
        doc: "Skip pre_init and post_init hooks"
      ],
      emit_signal: [
        type: :boolean,
        default: true,
        doc: "Whether to emit initialization signal"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    initial_state = params.initial_state || %{}
    skip_hooks? = params.skip_hooks
    emit_signal? = params.emit_signal != false
    
    try do
      # Get default state from schema
      default_state = get_default_state(agent)
      
      # Run pre_init hook if not skipped
      pre_init_state = if !skip_hooks? && function_exported?(agent.module, :pre_init, 1) do
        case agent.module.pre_init(Map.merge(default_state, initial_state)) do
          {:ok, state} -> state
          {:error, reason} ->
            Logger.error("pre_init failed: #{inspect(reason)}")
            Map.merge(default_state, initial_state)
        end
      else
        Map.merge(default_state, initial_state)
      end
      
      # Update agent with initialized state
      initialized_agent = %{agent | 
        state: pre_init_state,
        metadata: Map.merge(agent.metadata || %{}, %{
          initialized_at: DateTime.utc_now(),
          initialization_params: params
        })
      }
      
      # Run post_init hook if not skipped
      final_agent = if !skip_hooks? && function_exported?(agent.module, :post_init, 1) do
        case agent.module.post_init(initialized_agent) do
          {:ok, updated_agent} -> updated_agent
          {:error, reason} ->
            Logger.error("post_init failed: #{inspect(reason)}")
            initialized_agent
        end
      else
        initialized_agent
      end
      
      # Emit initialization signal if requested
      if emit_signal? do
        signal = Jido.Signal.new!(%{
          type: "agent.initialized",
          source: "agent:#{final_agent.id}",
          data: %{
            agent_id: final_agent.id,
            agent_module: inspect(final_agent.module),
            state_keys: Map.keys(final_agent.state),
            timestamp: DateTime.utc_now()
          }
        })
        
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
      end
      
      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :agent, :initialized],
        %{count: 1},
        %{
          agent_id: final_agent.id,
          agent_module: final_agent.module
        }
      )
      
      {:ok, %{
        initialized: true,
        state_keys: Map.keys(final_agent.state),
        hooks_run: !skip_hooks?
      }, %{agent: final_agent}}
      
    rescue
      error ->
        Logger.error("Agent initialization failed: #{inspect(error)}")
        {:error, {:initialization_failed, error}}
    end
  end
  
  # Private functions
  
  defp get_default_state(agent) do
    if function_exported?(agent.module, :__schema__, 0) do
      agent.module.__schema__()
      |> Enum.reduce(%{}, fn {key, opts}, acc ->
        if Keyword.has_key?(opts, :default) do
          Map.put(acc, key, opts[:default])
        else
          acc
        end
      end)
    else
      %{}
    end
  end
end