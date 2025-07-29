defmodule RubberDuck.Jido.Proper.SignalAdapter do
  @moduledoc """
  Adapter to bridge CloudEvents signals with Jido actions.
  
  This demonstrates how signals should trigger actions in the Jido pattern,
  rather than being sent as GenServer messages.
  """
  
  alias RubberDuck.Jido.Proper.Core
  
  @doc """
  Processes a CloudEvent signal by converting it to appropriate Jido actions.
  """
  def process_signal(agent_id, signal) do
    with {:ok, agent} <- Core.get_agent(agent_id),
         {:ok, action, params} <- signal_to_action(signal),
         {:ok, result, updated_agent} <- Core.execute_action(agent, action, params) do
      {:ok, updated_agent}
    end
  end
  
  @doc """
  Subscribes an agent to signal patterns.
  
  In proper Jido, this would register handlers that convert
  signals to actions.
  """
  def subscribe(agent_id, pattern) do
    # Store subscription pattern
    subscriptions = get_subscriptions()
    updated = Map.update(subscriptions, pattern, [agent_id], &[agent_id | &1])
    store_subscriptions(updated)
    
    {:ok, generate_subscription_id(agent_id, pattern)}
  end
  
  @doc """
  Broadcasts a signal to all subscribed agents.
  """
  def broadcast_signal(signal) do
    pattern = signal["type"] || signal[:type]
    
    # Find matching subscriptions
    get_subscriptions()
    |> Enum.filter(fn {sub_pattern, _agents} ->
      pattern_matches?(pattern, sub_pattern)
    end)
    |> Enum.flat_map(fn {_pattern, agent_ids} -> agent_ids end)
    |> Enum.uniq()
    |> Enum.each(fn agent_id ->
      process_signal(agent_id, signal)
    end)
    
    :ok
  end
  
  # Private functions
  
  defp signal_to_action(signal) do
    # Map signal types to actions
    # This is where you'd implement your signal -> action mapping
    case signal["type"] || signal[:type] do
      "increment" ->
        {:ok, RubberDuck.Jido.Actions.Increment, %{amount: signal["amount"] || 1}}
        
      "task.create" ->
        {:ok, RubberDuck.Jido.Actions.CreateTask, signal["data"] || %{}}
        
      _ ->
        {:error, :unknown_signal_type}
    end
  end
  
  defp pattern_matches?(signal_type, pattern) do
    regex_pattern = 
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")
      |> Regex.compile!()
    
    Regex.match?(regex_pattern, signal_type)
  end
  
  defp get_subscriptions do
    case :ets.lookup(subscription_table(), :subscriptions) do
      [{:subscriptions, subs}] -> subs
      [] -> %{}
    end
  end
  
  defp store_subscriptions(subscriptions) do
    :ets.insert(subscription_table(), {:subscriptions, subscriptions})
  end
  
  defp generate_subscription_id(agent_id, pattern) do
    "sub_#{agent_id}_#{Base.encode16(:crypto.hash(:sha, pattern), case: :lower)}"
  end
  
  defp subscription_table do
    table_name = :rubber_duck_jido_subscriptions
    
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:named_table, :public, :set])
      ref ->
        ref
    end
  end
end