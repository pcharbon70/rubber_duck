defmodule RubberDuck.TestSupport.SignalCapture do
  @moduledoc """
  Captures signals for testing purposes
  """
  
  use Agent
  
  def start_link(opts \\ []) do
    Agent.start_link(fn -> [] end, name: opts[:name] || __MODULE__)
  end
  
  def capture_signal(signal) do
    Agent.update(__MODULE__, fn signals ->
      [signal | signals]
    end)
  end
  
  def get_signals do
    Agent.get(__MODULE__, & &1)
    |> Enum.reverse()
  end
  
  def clear do
    Agent.update(__MODULE__, fn _ -> [] end)
  end
  
  def stop do
    if Process.whereis(__MODULE__) do
      Agent.stop(__MODULE__)
    end
  end
end