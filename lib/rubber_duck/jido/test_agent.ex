defmodule TestAgent do
  @moduledoc """
  Simple test agent for Jido integration testing.
  
  This is a temporary implementation until we have proper
  agent types defined.
  """
  
  use RubberDuck.Jido.BaseAgent
  
  require Logger
  
  @impl true
  def init(config) do
    Logger.info("TestAgent initialized with config: #{inspect(config)}")
    {:ok, %{config: config, status: :ready}}
  end
  
  @impl true
  def handle_signal(signal, state) do
    Logger.info("TestAgent received signal: #{inspect(signal.type)}")
    {:ok, Map.put(state, :last_signal, signal)}
  end
end