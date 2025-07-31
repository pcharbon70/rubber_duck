defmodule RubberDuck.Jido.Registries.SignalActionRegistry do
  @moduledoc """
  Registry for managing signal-to-action mappings across all agents.
  
  This registry provides a centralized place to configure how signals
  are routed to actions, supporting the migration from handle_signal
  callbacks to the action pattern.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Adapters.SignalAdapter
  
  @table_name :signal_action_mappings
  
  # Client API
  
  @doc """
  Starts the registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers signal mappings for an agent type.
  """
  def register_agent_mappings(agent_module, mappings) do
    GenServer.call(__MODULE__, {:register_mappings, agent_module, mappings})
  end
  
  @doc """
  Gets the signal adapter for an agent type.
  """
  def get_adapter(agent_module) do
    case :ets.lookup(@table_name, agent_module) do
      [{^agent_module, adapter}] -> {:ok, adapter}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Routes a signal to the appropriate actions for an agent.
  """
  def route_signal(agent_id, agent_module, signal) do
    with {:ok, adapter} <- get_adapter(agent_module) do
      SignalAdapter.route_signal(adapter, agent_id, signal)
    else
      {:error, :not_found} ->
        # Fallback to generic adapter
        default_adapter()
        |> SignalAdapter.route_signal(agent_id, signal)
    end
  end
  
  @doc """
  Lists all registered agent mappings.
  """
  def list_mappings do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {module, adapter} ->
      %{
        agent_module: module,
        rules_count: length(adapter.routing_rules),
        rules: Enum.map(adapter.routing_rules, & &1.name)
      }
    end)
  end
  
  @doc """
  Clears all mappings (useful for testing).
  """
  def clear_mappings do
    GenServer.call(__MODULE__, :clear_mappings)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    
    # Initialize default mappings
    initialize_default_mappings()
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register_mappings, agent_module, mappings}, _from, state) do
    adapter = build_adapter_from_mappings(mappings)
    :ets.insert(@table_name, {agent_module, adapter})
    
    Logger.info("Registered #{length(mappings)} signal mappings for #{inspect(agent_module)}")
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:clear_mappings, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end
  
  # Private functions
  
  defp initialize_default_mappings do
    # Register base mappings that apply to all agents
    base_mappings = [
      # Agent lifecycle signals
      %{
        pattern: "agent.initialize",
        action: RubberDuck.Jido.Actions.Base.InitializeAgentAction,
        extractor: &extract_initialize_params/1
      },
      
      # State management signals
      %{
        pattern: "agent.state.update",
        action: RubberDuck.Jido.Actions.Base.UpdateStateAction,
        extractor: &extract_state_update_params/1
      },
      
      # Signal emission
      %{
        pattern: "agent.signal.emit",
        action: RubberDuck.Jido.Actions.Base.EmitSignalAction,
        extractor: &extract_emit_params/1
      }
    ]
    
    # Create adapter for base mappings
    adapter = build_adapter_from_mappings(base_mappings)
    :ets.insert(@table_name, {:base, adapter})
  end
  
  defp build_adapter_from_mappings(mappings) do
    rules = Enum.map(mappings, fn mapping ->
      SignalAdapter.rule(
        mapping.pattern || mapping[:pattern],
        mapping.action || mapping[:action],
        extractor: mapping.extractor || mapping[:extractor],
        filter: mapping.filter || mapping[:filter],
        priority: mapping.priority || mapping[:priority]
      )
    end)
    
    SignalAdapter.new(routing_rules: rules)
  end
  
  defp default_adapter do
    # Get base adapter or create minimal one
    case :ets.lookup(@table_name, :base) do
      [{:base, adapter}] -> adapter
      [] -> SignalAdapter.new()
    end
  end
  
  # Default parameter extractors
  
  defp extract_initialize_params(signal) do
    %{
      initial_state: signal["data"]["initial_state"] || %{},
      emit_signal: true
    }
  end
  
  defp extract_state_update_params(signal) do
    %{
      updates: signal["data"]["updates"] || %{},
      merge_strategy: String.to_atom(signal["data"]["merge_strategy"] || "merge")
    }
  end
  
  defp extract_emit_params(signal) do
    data = signal["data"] || %{}
    %{
      signal_type: data["signal_type"],
      data: data["payload"] || %{},
      source: data["source"],
      subject: data["subject"]
    }
  end
end