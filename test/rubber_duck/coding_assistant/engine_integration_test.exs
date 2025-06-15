defmodule RubberDuck.CodingAssistant.EngineIntegrationTest do
  @moduledoc """
  Integration tests for the complete engine architecture and behavior framework.
  
  These tests verify that all components work together correctly:
  - EngineBehaviour contract compliance
  - Engine GenServer implementation
  - Registry and discovery
  - State machine integration
  - Health monitoring
  """
  
  use ExUnit.Case, async: false  # Not async due to registry usage
  
  alias RubberDuck.CodingAssistant.{
    EngineBehaviour,
    Engine,
    EngineRegistry,
    ProcessingStateMachine
  }
  
  # Complete test engine implementation
  defmodule TestCodeAnalyser do
    use RubberDuck.CodingAssistant.Engine
    
    @impl true
    def init(config) do
      {:ok, %{
        config: config,
        processed_count: 0,
        last_analysis: nil,
        health: :healthy
      }}
    end
    
    @impl true
    def process_real_time(data, state) do
      # Simulate code analysis
      analysis_result = %{
        status: :success,
        data: %{
          type: :code_analysis,
          input: data,
          analysis: %{
            lines: count_lines(data),
            complexity: calculate_complexity(data),
            suggestions: generate_suggestions(data)
          },
          processed_at: DateTime.utc_now()
        }
      }
      
      new_state = %{state |
        processed_count: state.processed_count + 1,
        last_analysis: analysis_result
      }
      
      {:ok, analysis_result, new_state}
    end
    
    @impl true
    def process_batch(data_list, state) do
      results = Enum.map(data_list, fn data ->
        %{
          status: :success,
          data: %{
            type: :batch_analysis,
            input: data,
            analysis: %{
              lines: count_lines(data),
              complexity: calculate_complexity(data)
            }
          }
        }
      end)
      
      new_state = %{state |
        processed_count: state.processed_count + length(data_list)
      }
      
      {:ok, results, new_state}
    end
    
    @impl true
    def capabilities do
      [:code_analysis, :complexity_analysis, :suggestion_generation]
    end
    
    @impl true
    def health_check(state) do
      cond do
        state.processed_count > 1000 -> :degraded
        state.processed_count > 100 -> :healthy
        true -> :healthy
      end
    end
    
    @impl true
    def handle_engine_event(event, state) do
      case event do
        {:update_health, new_health} ->
          {:ok, %{state | health: new_health}}
        _ ->
          {:ok, state}
      end
    end
    
    @impl true
    def terminate(_reason, _state), do: :ok
    
    # Helper functions
    defp count_lines(%{code: code}) when is_binary(code) do
      String.split(code, "\n") |> length()
    end
    defp count_lines(_), do: 1
    
    defp calculate_complexity(%{code: code}) when is_binary(code) do
      # Simple complexity based on keywords
      keywords = ["if", "for", "while", "def", "case"]
      keyword_count = Enum.reduce(keywords, 0, fn keyword, acc ->
        acc + (String.split(code, keyword) |> length()) - 1
      end)
      min(keyword_count / 10.0, 1.0)
    end
    defp calculate_complexity(_), do: 0.1
    
    defp generate_suggestions(%{code: code}) when is_binary(code) do
      suggestions = []
      
      suggestions = if String.contains?(code, "TODO") do
        ["Consider implementing TODO items" | suggestions]
      else
        suggestions
      end
      
      suggestions = if String.length(code) > 1000 do
        ["Consider breaking down large functions" | suggestions]
      else
        suggestions
      end
      
      suggestions
    end
    defp generate_suggestions(_), do: []
  end
  
  # Failing engine for error testing
  defmodule FailingEngine do
    use RubberDuck.CodingAssistant.Engine
    
    @impl true
    def init(_config), do: {:ok, %{fail_count: 0}}
    
    @impl true
    def process_real_time(_data, state) do
      {:error, :intentional_failure, %{state | fail_count: state.fail_count + 1}}
    end
    
    @impl true
    def process_batch(_data_list, state) do
      {:error, :batch_failure, %{state | fail_count: state.fail_count + 1}}
    end
    
    @impl true
    def capabilities, do: [:failure_testing]
    
    @impl true
    def health_check(state) do
      if state.fail_count > 5, do: :unhealthy, else: :degraded
    end
    
    @impl true
    def handle_engine_event(_event, state), do: {:ok, state}
    
    @impl true
    def terminate(_reason, _state), do: :ok
  end
  
  setup do
    # Start registry for testing
    {:ok, registry_pid} = EngineRegistry.start_link()
    
    on_exit(fn ->
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)
    
    %{registry: registry_pid}
  end
  
  describe "complete engine lifecycle" do
    test "can start, use, and stop an engine", %{registry: _registry} do
      # Start the engine
      config = %{model: "test-model", timeout: 5000}
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(config)
      assert Process.alive?(engine_pid)
      
      # Test capabilities
      capabilities = GenServer.call(engine_pid, :capabilities)
      assert :code_analysis in capabilities
      assert :complexity_analysis in capabilities
      
      # Test real-time processing
      test_data = %{code: "def hello do\n  :world\nend"}
      assert {:ok, result} = GenServer.call(engine_pid, {:process_real_time, test_data})
      
      assert result.status == :success
      assert result.data.type == :code_analysis
      assert result.data.analysis.lines == 3
      assert is_float(result.data.analysis.complexity)
      assert is_integer(result.processing_time)
      
      # Test batch processing
      batch_data = [
        %{code: "x = 1"},
        %{code: "y = 2"},
        %{code: "z = x + y"}
      ]
      assert {:ok, batch_results} = GenServer.call(engine_pid, {:process_batch, batch_data})
      
      assert length(batch_results) == 3
      assert Enum.all?(batch_results, fn r -> r.status == :success end)
      
      # Test health status
      health = GenServer.call(engine_pid, :health_status)
      assert health in [:healthy, :degraded, :unhealthy]
      
      # Test statistics
      stats = GenServer.call(engine_pid, :statistics)
      assert stats.real_time.total_requests == 1
      assert stats.real_time.successful_requests == 1
      assert stats.batch.total_requests == 1
      assert stats.batch.successful_requests == 1
      
      # Clean up
      GenServer.stop(engine_pid)
    end
    
    test "handles engine failures gracefully", %{registry: _registry} do
      # Start failing engine
      assert {:ok, engine_pid} = FailingEngine.start_link(%{})
      
      # Test failed real-time processing
      assert {:error, :intentional_failure} = GenServer.call(engine_pid, {:process_real_time, %{}})
      
      # Test failed batch processing
      assert {:error, :batch_failure} = GenServer.call(engine_pid, {:process_batch, [%{}]})
      
      # Verify statistics track failures
      stats = GenServer.call(engine_pid, :statistics)
      assert stats.real_time.failed_requests == 1
      assert stats.batch.failed_requests == 1
      
      # Health should degrade
      health = GenServer.call(engine_pid, :health_status)
      assert health in [:degraded, :unhealthy]
      
      GenServer.stop(engine_pid)
    end
    
    test "handles real-time timeouts", %{registry: _registry} do
      # Create a slow engine for timeout testing
      defmodule SlowEngine do
        use RubberDuck.CodingAssistant.Engine
        
        @impl true
        def init(_config), do: {:ok, %{}}
        
        @impl true
        def process_real_time(_data, state) do
          Process.sleep(150)  # Longer than 100ms timeout
          {:ok, %{status: :success, data: %{}}, state}
        end
        
        @impl true
        def process_batch(_data_list, state), do: {:ok, [], state}
        @impl true
        def capabilities, do: [:slow_processing]
        @impl true
        def health_check(_state), do: :healthy
        @impl true
        def handle_engine_event(_event, state), do: {:ok, state}
        @impl true
        def terminate(_reason, _state), do: :ok
      end
      
      assert {:ok, engine_pid} = SlowEngine.start_link(%{})
      
      # Should timeout
      assert {:error, :timeout} = GenServer.call(engine_pid, {:process_real_time, %{}})
      
      # Check timeout statistics
      stats = GenServer.call(engine_pid, :statistics)
      assert stats.real_time.timeout_requests == 1
      
      GenServer.stop(engine_pid)
    end
  end
  
  describe "registry integration" do
    test "engines register automatically with registry", %{registry: _registry} do
      # Start engine
      config = %{auto_register: true}
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(config)
      
      # Give registry time to process registration
      Process.sleep(100)
      
      # Verify engine appears in registry
      engines = EngineRegistry.list_engines()
      engine_modules = Enum.map(engines, & &1.engine)
      assert TestCodeAnalyser in engine_modules
      
      GenServer.stop(engine_pid)
    end
    
    test "can find engines by capability", %{registry: _registry} do
      # Start multiple engines
      assert {:ok, analyzer_pid} = TestCodeAnalyser.start_link(%{})
      assert {:ok, failing_pid} = FailingEngine.start_link(%{})
      
      Process.sleep(100)  # Allow registration
      
      # Find by specific capability
      code_analysis_engines = EngineRegistry.find_engines_by_capability([:code_analysis])
      assert length(code_analysis_engines) >= 1
      
      failure_engines = EngineRegistry.find_engines_by_capability([:failure_testing])
      assert length(failure_engines) >= 1
      
      # Cleanup
      GenServer.stop(analyzer_pid)
      GenServer.stop(failing_pid)
    end
    
    test "registry provides best engine selection", %{registry: _registry} do
      # Start test engine
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(%{})
      Process.sleep(100)
      
      # Request best engine for code analysis
      case EngineRegistry.get_best_engine([:code_analysis]) do
        {:ok, engine_info} ->
          assert engine_info.engine == TestCodeAnalyser
          assert :code_analysis in engine_info.capabilities
          
        {:error, :no_engines_available} ->
          # This might happen if registry doesn't have the engine yet
          flunk("Expected to find at least one code analysis engine")
      end
      
      GenServer.stop(engine_pid)
    end
  end
  
  describe "state machine integration" do
    test "state machine handles engine requests properly" do
      {:ok, state_machine} = ProcessingStateMachine.init()
      
      # Test real-time request
      real_time_request = %{
        type: :real_time,
        priority: :normal,
        estimated_complexity: 0.5,
        deadline: nil,
        data_size: 100
      }
      
      {:ok, new_state, actions} = ProcessingStateMachine.handle_request(state_machine, real_time_request)
      
      assert new_state.current_mode == :real_time
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :real_time}, action) end)
      
      # Test batch processing mode
      batch_request = %{
        type: :batch,
        priority: :low,
        estimated_complexity: 0.2,
        deadline: nil,
        data_size: 50
      }
      
      # Add multiple batch requests
      final_state = Enum.reduce(1..6, new_state, fn _, acc_state ->
        {:ok, updated_state, _} = ProcessingStateMachine.handle_request(acc_state, batch_request)
        updated_state
      end)
      
      assert final_state.current_mode == :batch
      assert length(final_state.request_queue) >= 6
    end
    
    test "state machine responds to health changes" do
      {:ok, state_machine} = ProcessingStateMachine.init()
      
      # Simulate health degradation
      {:ok, degraded_state, actions} = ProcessingStateMachine.update_health(state_machine, :degraded)
      
      assert degraded_state.current_mode == :degraded
      assert degraded_state.health_status == :degraded
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :degraded}, action) end)
      
      # Simulate recovery
      old_time = DateTime.add(DateTime.utc_now(), -10, :second)
      degraded_with_old_time = %{degraded_state | mode_start_time: old_time}
      
      {:ok, recovered_state, recovery_actions} = ProcessingStateMachine.update_health(degraded_with_old_time, :healthy)
      
      assert recovered_state.current_mode == :idle
      assert recovered_state.health_status == :healthy
      assert Enum.any?(recovery_actions, fn action -> match?({:switch_mode, :idle}, action) end)
    end
  end
  
  describe "performance and monitoring" do
    test "engines report accurate performance metrics", %{registry: _registry} do
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(%{})
      
      # Perform multiple operations
      test_data = %{code: "def test do\n  if true do\n    :ok\n  end\nend"}
      
      # Real-time processing
      Enum.each(1..5, fn _ ->
        GenServer.call(engine_pid, {:process_real_time, test_data})
      end)
      
      # Batch processing
      batch_data = Enum.map(1..3, fn i -> %{code: "x#{i} = #{i}"} end)
      GenServer.call(engine_pid, {:process_batch, batch_data})
      
      # Check statistics
      stats = GenServer.call(engine_pid, :statistics)
      
      assert stats.real_time.total_requests == 5
      assert stats.real_time.successful_requests == 5
      assert stats.real_time.average_processing_time > 0
      
      assert stats.batch.total_requests == 1
      assert stats.batch.successful_requests == 1
      assert stats.batch.total_items_processed == 3
      
      GenServer.stop(engine_pid)
    end
    
    test "registry tracks engine health and performance", %{registry: _registry} do
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(%{})
      Process.sleep(100)
      
      # Update engine status
      EngineRegistry.update_engine_status(TestCodeAnalyser, "test_id", :healthy, %{
        real_time: %{total_requests: 10, successful_requests: 9},
        batch: %{total_requests: 2, successful_requests: 2}
      })
      
      # Check registry stats
      registry_stats = EngineRegistry.get_registry_stats()
      
      assert registry_stats.total_engines >= 1
      assert is_map(registry_stats.engines_by_type)
      assert is_map(registry_stats.engines_by_health)
      
      GenServer.stop(engine_pid)
    end
  end
  
  describe "error handling and recovery" do
    test "engines handle malformed data gracefully", %{registry: _registry} do
      assert {:ok, engine_pid} = TestCodeAnalyser.start_link(%{})
      
      # Test with various malformed inputs
      malformed_inputs = [
        nil,
        %{},
        %{not_code: "invalid"},
        %{code: nil},
        %{code: 12345}
      ]
      
      Enum.each(malformed_inputs, fn input ->
        # Should not crash, but may return error or handle gracefully
        result = GenServer.call(engine_pid, {:process_real_time, input})
        assert is_tuple(result)  # Either {:ok, ...} or {:error, ...}
      end)
      
      # Engine should still be alive
      assert Process.alive?(engine_pid)
      
      GenServer.stop(engine_pid)
    end
    
    test "state machine handles overload scenarios" do
      {:ok, state_machine} = ProcessingStateMachine.init()
      
      # Create overload conditions
      overload_metrics = %{
        average_response_time: 300_000,  # 300ms
        success_rate: 0.6,
        queue_depth: 90,
        error_rate: 0.2,
        cpu_usage: 0.95,
        memory_usage: 0.9,
        throughput: 1.0
      }
      
      overloaded_state = %{state_machine | processing_metrics: overload_metrics}
      
      # New request should trigger overload mode
      request = %{
        type: :real_time,
        priority: :normal,
        estimated_complexity: 0.5,
        deadline: nil,
        data_size: 100
      }
      
      {:ok, new_state, actions} = ProcessingStateMachine.handle_request(overloaded_state, request)
      
      assert new_state.current_mode == :overloaded
      assert Enum.any?(actions, fn action -> match?({:shed_load, _}, action) end)
      assert Enum.any?(actions, fn action -> match?({:alert, :overload, _}, action) end)
    end
  end
end