defmodule RubberDuck.Jido.Agent.Helpers do
  @moduledoc """
  Common helper functions for Jido agents.
  
  Provides utilities for signal emission, subscription, and state management.
  """
  
  require Logger
  alias RubberDuck.Jido.SignalDispatcher
  
  @doc """
  Emits a signal to a specific agent.
  """
  @spec emit_signal(pid(), map()) :: :ok
  def emit_signal(agent_pid, signal) when is_pid(agent_pid) and is_map(signal) do
    send(agent_pid, {:signal, signal})
    :ok
  end
  
  @doc """
  Subscribes an agent to a signal pattern.
  """
  @spec subscribe(pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def subscribe(agent_pid, pattern) when is_pid(agent_pid) and is_binary(pattern) do
    subscription_id = generate_subscription_id()
    
    # Register subscription with SignalDispatcher
    case SignalDispatcher.subscribe(pattern, agent_pid, subscription_id) do
      :ok -> {:ok, subscription_id}
      error -> error
    end
  end
  
  @doc """
  Unsubscribes an agent from a signal pattern.
  """
  @spec unsubscribe(pid(), String.t()) :: :ok
  def unsubscribe(agent_pid, subscription_id) when is_pid(agent_pid) and is_binary(subscription_id) do
    SignalDispatcher.unsubscribe(subscription_id)
    :ok
  end
  
  @doc """
  Gets the current state of an agent.
  """
  @spec get_state(pid()) :: term()
  def get_state(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :get_state)
  end
  
  @doc """
  Updates the state of an agent.
  """
  @spec update_state(pid(), map()) :: :ok | {:error, term()}
  def update_state(agent_pid, new_state) when is_pid(agent_pid) and is_map(new_state) do
    GenServer.call(agent_pid, {:update_state, new_state})
  end
  
  @doc """
  Checks the health of an agent.
  """
  @spec health_check(pid()) :: {:healthy, map()} | {:unhealthy, map()}
  def health_check(agent_pid) when is_pid(agent_pid) do
    GenServer.call(agent_pid, :health_check)
  end
  
  # Private functions
  
  defp generate_subscription_id do
    "sub_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end