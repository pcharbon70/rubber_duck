defmodule RubberDuck.TestSupport.MockAgent do
  @moduledoc """
  Mock agent for testing purposes
  """

  defstruct [:id, :state, :pid]

  def start_agent(agent_module, initial_state) do
    pid = self()
    
    agent = %__MODULE__{
      id: "test-agent-#{:rand.uniform(1000)}",
      state: %{
        agent_module: agent_module,
        state: initial_state
      },
      pid: pid
    }
    
    {:ok, agent}
  end
  
  def stop_agent(_agent) do
    :ok
  end
end