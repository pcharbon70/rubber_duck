defmodule RubberDuck.Jido.Agent.TestHelper do
  @moduledoc """
  Testing utilities for Jido agents.
  
  Provides helpers for creating test agents, mocking signals, and assertions.
  """
  
  alias RubberDuck.Jido.BaseAgent
  
  @doc """
  Creates a test agent with the given module and config.
  
  Returns the agent pid.
  """
  def create_test_agent(module, config \\ %{}) do
    default_config = %{
      id: "test-#{:rand.uniform(9999)}",
      type: :test
    }
    
    merged_config = Map.merge(default_config, config)
    
    # Start the agent using its own start_link function
    case module.start_link(merged_config) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end
  
  @doc """
  Waits for a signal to be processed.
  
  Useful for async signal processing in tests.
  """
  def wait_for_signal(timeout \\ 100) do
    Process.sleep(timeout)
  end
  
  @doc """
  Creates a test signal with defaults.
  """
  def create_signal(type, data \\ %{}, opts \\ []) do
    %{
      "type" => type,
      "data" => data,
      "source" => Keyword.get(opts, :source, "test"),
      "id" => Keyword.get(opts, :id, "test-signal-#{:rand.uniform(9999)}")
    }
  end
  
  @doc """
  Asserts agent state matches expected values.
  """
  defmacro assert_agent_state(agent, expected) do
    quote do
      actual = BaseAgent.get_state(unquote(agent))
      
      Enum.each(unquote(expected), fn {key, value} ->
        assert Map.get(actual, key) == value,
          "Expected state.#{key} to be #{inspect(value)}, but got #{inspect(Map.get(actual, key))}"
      end)
    end
  end
  
  @doc """
  Sets up telemetry capture for tests.
  """
  def capture_telemetry(event_names) do
    test_pid = self()
    
    handler_id = "test-handler-#{:rand.uniform(9999)}"
    
    :telemetry.attach_many(
      handler_id,
      event_names,
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event_name, measurements, metadata})
      end,
      nil
    )
    
    handler_id
  end
  
  @doc """
  Cleans up telemetry handler.
  """
  def cleanup_telemetry(handler_id) do
    :telemetry.detach(handler_id)
  end
end