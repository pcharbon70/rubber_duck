defmodule RubberDuck.CodingAssistant.EngineTest do
  @moduledoc """
  Tests for the base Engine GenServer implementation.
  """
  
  use ExUnit.Case, async: true
  
  # Test engine implementation
  defmodule TestEngine do
    use RubberDuck.CodingAssistant.Engine
    
    @impl true
    def init(config) do
      {:ok, %{config: config, call_count: 0}}
    end
    
    @impl true
    def process_real_time(data, state) do
      new_state = %{state | call_count: state.call_count + 1}
      result = %{status: :success, data: %{processed: data, call: state.call_count}}
      {:ok, result, new_state}
    end
    
    @impl true
    def process_batch(data_list, state) do
      new_state = %{state | call_count: state.call_count + 1}
      results = Enum.map(data_list, fn data ->
        %{status: :success, data: %{processed: data, batch: true}}
      end)
      {:ok, results, new_state}
    end
    
    @impl true
    def capabilities, do: [:test, :example]
    
    @impl true
    def health_check(_state), do: :healthy
    
    @impl true
    def handle_engine_event(_event, state), do: {:ok, state}
    
    @impl true
    def terminate(_reason, _state), do: :ok
  end
  
  test "Engine can be started with configuration" do
    config = %{test: true}
    
    assert {:ok, pid} = TestEngine.start_link(config)
    assert Process.alive?(pid)
    
    # Clean up
    GenServer.stop(pid)
  end
  
  test "Engine responds to capabilities request" do
    {:ok, pid} = TestEngine.start_link(%{})
    
    capabilities = GenServer.call(pid, :capabilities)
    assert capabilities == [:test, :example]
    
    GenServer.stop(pid)
  end
  
  test "Engine handles real-time processing" do
    {:ok, pid} = TestEngine.start_link(%{})
    
    test_data = %{input: "test data"}
    assert {:ok, result} = GenServer.call(pid, {:process_real_time, test_data})
    
    assert result.status == :success
    assert result.data.processed == test_data
    assert result.data.call == 1
    assert is_integer(result.processing_time)
    
    GenServer.stop(pid)
  end
  
  test "Engine handles batch processing" do
    {:ok, pid} = TestEngine.start_link(%{})
    
    test_data = [%{input: "item1"}, %{input: "item2"}]
    assert {:ok, results} = GenServer.call(pid, {:process_batch, test_data})
    
    assert length(results) == 2
    assert Enum.all?(results, fn result -> result.status == :success end)
    assert Enum.all?(results, fn result -> result.data.batch == true end)
    
    GenServer.stop(pid)
  end
  
  test "Engine reports health status" do
    {:ok, pid} = TestEngine.start_link(%{})
    
    health = GenServer.call(pid, :health_status)
    assert health == :healthy
    
    GenServer.stop(pid)
  end
  
  test "Engine tracks statistics" do
    {:ok, pid} = TestEngine.start_link(%{})
    
    # Perform some operations
    GenServer.call(pid, {:process_real_time, %{test: 1}})
    GenServer.call(pid, {:process_batch, [%{test: 2}]})
    
    stats = GenServer.call(pid, :statistics)
    
    assert stats.real_time.total_requests == 1
    assert stats.real_time.successful_requests == 1
    assert stats.batch.total_requests == 1
    assert stats.batch.successful_requests == 1
    
    GenServer.stop(pid)
  end
  
  # Error handling engine for testing failures
  defmodule ErrorEngine do
    use RubberDuck.CodingAssistant.Engine
    
    @impl true
    def init(_config), do: {:ok, %{}}
    
    @impl true
    def process_real_time(_data, state) do
      {:error, :processing_failed, state}
    end
    
    @impl true
    def process_batch(_data_list, state) do
      {:error, :batch_failed, state}
    end
    
    @impl true
    def capabilities, do: [:error_test]
    
    @impl true
    def health_check(_state), do: :unhealthy
    
    @impl true
    def handle_engine_event(_event, state), do: {:error, :event_error}
    
    @impl true
    def terminate(_reason, _state), do: :ok
  end
  
  test "Engine handles real-time processing errors" do
    {:ok, pid} = ErrorEngine.start_link(%{})
    
    assert {:error, :processing_failed} = GenServer.call(pid, {:process_real_time, %{}})
    
    # Check error statistics
    stats = GenServer.call(pid, :statistics)
    assert stats.real_time.failed_requests == 1
    
    GenServer.stop(pid)
  end
  
  test "Engine handles batch processing errors" do
    {:ok, pid} = ErrorEngine.start_link(%{})
    
    assert {:error, :batch_failed} = GenServer.call(pid, {:process_batch, [%{}]})
    
    # Check error statistics
    stats = GenServer.call(pid, :statistics)
    assert stats.batch.failed_requests == 1
    
    GenServer.stop(pid)
  end
  
  test "Engine reports unhealthy status" do
    {:ok, pid} = ErrorEngine.start_link(%{})
    
    health = GenServer.call(pid, :health_status)
    assert health == :unhealthy
    
    GenServer.stop(pid)
  end
  
  # Timeout testing engine
  defmodule TimeoutEngine do
    use RubberDuck.CodingAssistant.Engine
    
    @impl true
    def init(_config), do: {:ok, %{}}
    
    @impl true
    def process_real_time(_data, state) do
      # Sleep longer than the 100ms timeout
      Process.sleep(200)
      {:ok, %{status: :success, data: %{}}, state}
    end
    
    @impl true
    def process_batch(_data_list, state) do
      {:ok, [], state}
    end
    
    @impl true
    def capabilities, do: [:timeout_test]
    
    @impl true
    def health_check(_state), do: :healthy
    
    @impl true
    def handle_engine_event(_event, state), do: {:ok, state}
    
    @impl true
    def terminate(_reason, _state), do: :ok
  end
  
  test "Engine handles real-time processing timeouts" do
    {:ok, pid} = TimeoutEngine.start_link(%{})
    
    assert {:error, :timeout} = GenServer.call(pid, {:process_real_time, %{}})
    
    # Check timeout statistics
    stats = GenServer.call(pid, :statistics)
    assert stats.real_time.timeout_requests == 1
    
    GenServer.stop(pid)
  end
end