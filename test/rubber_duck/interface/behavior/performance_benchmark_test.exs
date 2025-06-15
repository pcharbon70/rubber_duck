defmodule RubberDuck.Interface.Behavior.PerformanceBenchmarkTest do
  @moduledoc """
  Performance benchmark tests for interface adapters.
  
  This module provides comprehensive performance testing and benchmarking
  for interface adapters to ensure they meet performance requirements
  and identify optimization opportunities.
  """
  
  use ExUnit.Case, async: false  # Performance tests should not run concurrently
  
  alias RubberDuck.Interface.Adapters.CLI
  alias RubberDuck.Interface.Behaviour
  
  # Test configuration optimized for performance testing
  @test_config %{
    colors: false,
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,
    config_dir: System.tmp_dir!() <> "/perf_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/perf_sessions_#{System.unique_integer()}"
  }
  
  # Performance thresholds (in milliseconds)
  @performance_thresholds %{
    single_request: 100,      # Single request should complete in < 100ms
    batch_requests: 5000,     # 100 requests should complete in < 5 seconds
    concurrent_requests: 3000, # 50 concurrent requests in < 3 seconds
    memory_growth: 10,        # Memory should not grow more than 10x
    initialization: 50        # Adapter initialization should be < 50ms
  }
  
  setup do
    # Clean test directories
    [@test_config.config_dir, @test_config.sessions_dir]
    |> Enum.each(fn dir ->
      if File.exists?(dir) do
        File.rm_rf!(dir)
      end
    end)
    
    on_exit(fn ->
      [@test_config.config_dir, @test_config.sessions_dir]
      |> Enum.each(fn dir ->
        if File.exists?(dir) do
          File.rm_rf!(dir)
        end
      end)
    end)
    
    :ok
  end
  
  describe "Initialization Performance" do
    test "adapter initialization is fast" do
      # Measure initialization time
      {time_micro, {:ok, _state}} = :timer.tc(fn ->
        CLI.init(config: @test_config)
      end)
      
      time_ms = time_micro / 1000
      
      assert time_ms < @performance_thresholds.initialization,
        "Initialization took #{time_ms}ms, expected < #{@performance_thresholds.initialization}ms"
      
      # Test multiple initializations
      times = for _i <- 1..10 do
        {time, {:ok, _state}} = :timer.tc(fn ->
          CLI.init(config: @test_config)
        end)
        time / 1000
      end
      
      avg_time = Enum.sum(times) / length(times)
      assert avg_time < @performance_thresholds.initialization,
        "Average initialization time #{avg_time}ms exceeds threshold"
    end
    
    test "initialization memory usage is reasonable" do
      # Measure memory before and after initialization
      initial_memory = :erlang.memory(:total)
      
      {:ok, state} = CLI.init(config: @test_config)
      
      final_memory = :erlang.memory(:total)
      memory_used = final_memory - initial_memory
      
      # Memory usage should be reasonable (< 1MB for initialization)
      assert memory_used < 1_000_000,
        "Initialization used #{memory_used} bytes, expected < 1MB"
      
      # State size should be reasonable
      state_size = :erlang.external_size(state)
      assert state_size < 10_000,
        "State size #{state_size} bytes is too large"
    end
  end
  
  describe "Single Request Performance" do
    test "individual requests are processed quickly" do
      {:ok, state} = CLI.init(config: @test_config)
      
      operations = [:chat, :complete, :analyze, :status, :help]
      
      for operation <- operations do
        request = create_test_request(operation)
        context = %{interface: :cli}
        
        {time_micro, result} = :timer.tc(fn ->
          CLI.handle_request(request, context, state)
        end)
        
        time_ms = time_micro / 1000
        
        assert {:ok, _response, _new_state} = result
        assert time_ms < @performance_thresholds.single_request,
          "#{operation} took #{time_ms}ms, expected < #{@performance_thresholds.single_request}ms"
      end
    end
    
    test "response formatting is fast" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create a sample response
      response = %{
        id: "format_perf_test",
        status: :success,
        data: %{
          message: String.duplicate("Performance test response content. ", 100),
          session_id: "test_session"
        },
        metadata: %{
          timestamp: DateTime.utc_now(),
          processing_time: 50
        }
      }
      
      request = %{operation: :chat}
      
      {time_micro, {:ok, _formatted}} = :timer.tc(fn ->
        CLI.format_response(response, request, state)
      end)
      
      time_ms = time_micro / 1000
      
      assert time_ms < 10,  # Formatting should be very fast
        "Response formatting took #{time_ms}ms, expected < 10ms"
    end
    
    test "request validation is fast" do
      requests = [
        create_test_request(:chat),
        create_test_request(:complete),
        create_test_request(:analyze),
        %{invalid: :request}  # Invalid request for testing
      ]
      
      for request <- requests do
        {time_micro, _result} = :timer.tc(fn ->
          CLI.validate_request(request)
        end)
        
        time_ms = time_micro / 1000
        
        assert time_ms < 1,  # Validation should be extremely fast
          "Request validation took #{time_ms}ms, expected < 1ms"
      end
    end
  end
  
  describe "Batch Processing Performance" do
    test "sequential request processing scales linearly" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Test with different batch sizes
      batch_sizes = [10, 50, 100]
      
      for batch_size <- batch_sizes do
        requests = for i <- 1..batch_size do
          %{
            id: "batch_test_#{i}",
            operation: :chat,
            params: %{message: "Batch test #{i}"},
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
        end
        
        context = %{interface: :cli}
        
        {time_micro, final_state} = :timer.tc(fn ->
          Enum.reduce(requests, initial_state, fn request, state ->
            {:ok, _response, new_state} = CLI.handle_request(request, context, state)
            new_state
          end)
        end)
        
        time_ms = time_micro / 1000
        time_per_request = time_ms / batch_size
        
        # Time per request should remain relatively constant
        assert time_per_request < 20,
          "#{batch_size} requests: #{time_per_request}ms per request, expected < 20ms"
        
        # Total time should be reasonable for large batches
        if batch_size == 100 do
          assert time_ms < @performance_thresholds.batch_requests,
            "100 requests took #{time_ms}ms, expected < #{@performance_thresholds.batch_requests}ms"
        end
        
        # State should be properly maintained
        assert final_state.request_count == batch_size
      end
    end
    
    test "memory usage remains stable during batch processing" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      initial_memory = :erlang.memory(:total)
      
      # Process many requests
      final_state = Enum.reduce(1..200, initial_state, fn i, state ->
        request = %{
          id: "memory_test_#{i}",
          operation: :chat,
          params: %{message: "Memory test #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        {:ok, _response, new_state} = CLI.handle_request(request, context, state)
        new_state
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # State size should not grow excessively
      initial_state_size = :erlang.external_size(initial_state)
      final_state_size = :erlang.external_size(final_state)
      state_growth_factor = final_state_size / initial_state_size
      
      assert state_growth_factor < @performance_thresholds.memory_growth,
        "State grew by factor of #{state_growth_factor}, expected < #{@performance_thresholds.memory_growth}"
      
      # Memory usage should be reasonable
      assert memory_growth < 10_000_000,  # < 10MB growth
        "Memory grew by #{memory_growth} bytes during batch processing"
      
      # Request count should be accurate
      assert final_state.request_count == 200
    end
  end
  
  describe "Concurrent Processing Performance" do
    test "concurrent requests are handled efficiently" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create concurrent tasks
      num_tasks = 50
      
      start_time = System.monotonic_time(:millisecond)
      
      tasks = for i <- 1..num_tasks do
        Task.async(fn ->
          request = %{
            id: "concurrent_test_#{i}",
            operation: :chat,
            params: %{message: "Concurrent test #{i}"},
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
          
          context = %{interface: :cli}
          
          {time_micro, result} = :timer.tc(fn ->
            CLI.handle_request(request, context, state)
          end)
          
          {time_micro / 1000, result}
        end)
      end
      
      results = Task.await_many(tasks, 10_000)
      end_time = System.monotonic_time(:millisecond)
      
      total_time = end_time - start_time
      
      # All tasks should complete successfully
      for {_time, result} <- results do
        assert {:ok, _response, _state} = result
      end
      
      # Total time should meet threshold
      assert total_time < @performance_thresholds.concurrent_requests,
        "#{num_tasks} concurrent requests took #{total_time}ms, expected < #{@performance_thresholds.concurrent_requests}ms"
      
      # Calculate performance statistics
      times = Enum.map(results, fn {time, _result} -> time end)
      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)
      min_time = Enum.min(times)
      
      # Individual request times should be reasonable
      assert avg_time < @performance_thresholds.single_request,
        "Average concurrent request time #{avg_time}ms exceeds threshold"
      
      assert max_time < @performance_thresholds.single_request * 3,
        "Maximum concurrent request time #{max_time}ms is too high"
    end
    
    test "adapter handles request bursts gracefully" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate burst patterns
      burst_patterns = [
        {10, 100},   # 10 requests every 100ms
        {25, 250},   # 25 requests every 250ms
        {5, 50}      # 5 requests every 50ms
      ]
      
      for {burst_size, interval_ms} <- burst_patterns do
        # Create burst of requests
        burst_tasks = for i <- 1..burst_size do
          Task.async(fn ->
            request = %{
              id: "burst_test_#{burst_size}_#{i}",
              operation: :chat,
              params: %{message: "Burst test #{i}"},
              interface: :cli,
              timestamp: DateTime.utc_now()
            }
            
            context = %{interface: :cli}
            CLI.handle_request(request, context, state)
          end)
        end
        
        # Wait for burst to complete
        start_time = System.monotonic_time(:millisecond)
        results = Task.await_many(burst_tasks, 5000)
        end_time = System.monotonic_time(:millisecond)
        
        burst_time = end_time - start_time
        
        # All requests in burst should succeed
        for result <- results do
          assert {:ok, _response, _state} = result
        end
        
        # Burst should complete in reasonable time
        assert burst_time < interval_ms * 2,
          "Burst of #{burst_size} took #{burst_time}ms, expected < #{interval_ms * 2}ms"
        
        # Wait before next burst
        Process.sleep(interval_ms)
      end
    end
  end
  
  describe "Resource Utilization Benchmarks" do
    test "CPU usage is reasonable under load" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Monitor CPU-intensive operations
      cpu_intensive_operations = [
        {:analyze, %{content: String.duplicate("def function():\n    pass\n", 100)}},
        {:complete, %{prompt: String.duplicate("class Example:\n", 50)}},
        {:chat, %{message: String.duplicate("Analyze this complex code. ", 20)}}
      ]
      
      for {operation, params} <- cpu_intensive_operations do
        request = %{
          id: "cpu_test_#{operation}",
          operation: operation,
          params: params,
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        
        # Measure processing time for resource-intensive operations
        {time_micro, {:ok, _response, _new_state}} = :timer.tc(fn ->
          CLI.handle_request(request, context, state)
        end)
        
        time_ms = time_micro / 1000
        
        # Even complex operations should complete reasonably quickly
        assert time_ms < 500,
          "CPU-intensive #{operation} took #{time_ms}ms, expected < 500ms"
      end
    end
    
    test "memory allocation patterns are efficient" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Track memory allocations during different operations
      operations = [:chat, :complete, :analyze, :session_management]
      
      for operation <- operations do
        initial_memory = :erlang.memory(:total)
        
        # Process multiple requests of the same type
        final_state = Enum.reduce(1..20, state, fn i, acc_state ->
          request = create_test_request(operation, %{iteration: i})
          context = %{interface: :cli}
          
          {:ok, _response, new_state} = CLI.handle_request(request, context, acc_state)
          new_state
        end)
        
        final_memory = :erlang.memory(:total)
        memory_used = final_memory - initial_memory
        
        # Memory usage should be bounded
        assert memory_used < 5_000_000,  # < 5MB per operation type
          "#{operation} operations used #{memory_used} bytes, expected < 5MB"
        
        # Cleanup should work properly
        CLI.shutdown(:normal, final_state)
      end
    end
    
    test "garbage collection impact is minimal" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Force garbage collection before test
      :erlang.garbage_collect()
      initial_gc_count = :erlang.statistics(:garbage_collection) |> elem(0)
      
      # Process many requests to trigger GC
      final_state = Enum.reduce(1..100, state, fn i, acc_state ->
        request = %{
          id: "gc_test_#{i}",
          operation: :chat,
          params: %{message: "GC test #{i} " <> String.duplicate("data", 100)},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        {:ok, _response, new_state} = CLI.handle_request(request, context, acc_state)
        new_state
      end)
      
      final_gc_count = :erlang.statistics(:garbage_collection) |> elem(0)
      gc_triggered = final_gc_count - initial_gc_count
      
      # GC should not be triggered excessively
      assert gc_triggered < 50,
        "#{gc_triggered} garbage collections triggered, expected < 50"
      
      # State should still be functional after GC pressure
      assert final_state.request_count == 100
    end
  end
  
  describe "Scalability Benchmarks" do
    test "performance degrades gracefully with state size" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Test performance with different state sizes
      state_sizes = [10, 50, 100, 200]
      performance_results = []
      
      for target_size <- state_sizes do
        # Build up state to target size
        state = Enum.reduce(1..target_size, initial_state, fn i, acc_state ->
          request = %{
            id: "state_size_test_#{i}",
            operation: :chat,
            params: %{message: "State size test #{i}"},
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
          
          context = %{interface: :cli}
          {:ok, _response, new_state} = CLI.handle_request(request, context, acc_state)
          new_state
        end)
        
        # Measure performance with current state size
        test_request = create_test_request(:chat)
        context = %{interface: :cli}
        
        {time_micro, {:ok, _response, _final_state}} = :timer.tc(fn ->
          CLI.handle_request(test_request, context, state)
        end)
        
        time_ms = time_micro / 1000
        performance_results = [{target_size, time_ms} | performance_results]
        
        # Performance should not degrade significantly
        assert time_ms < @performance_thresholds.single_request * 2,
          "Request with state size #{target_size} took #{time_ms}ms"
      end
      
      # Check that performance degradation is linear, not exponential
      performance_results = Enum.reverse(performance_results)
      
      # Compare first and last measurements
      {_size1, time1} = List.first(performance_results)
      {_size2, time2} = List.last(performance_results)
      
      # Performance should not degrade more than 3x even with 20x state size
      assert time2 < time1 * 3,
        "Performance degraded too much: #{time1}ms -> #{time2}ms"
    end
  end
  
  # Helper functions
  
  defp create_test_request(operation, extra_params \\\\ %{}) do
    base_params = case operation do
      :chat -> %{message: "Test message"}
      :complete -> %{prompt: "def test():"}
      :analyze -> %{content: "test content"}
      :session_management -> %{action: :list}
      :configuration -> %{action: :show}
      :help -> %{topic: :general}
      :status -> %{}
      :version -> %{}
    end
    
    params = Map.merge(base_params, extra_params)
    
    %{
      id: "perf_test_#{operation}_#{System.unique_integer()}",
      operation: operation,
      params: params,
      interface: :cli,
      timestamp: DateTime.utc_now()
    }
  end
  
  # Performance reporting helper
  defp report_performance(operation, time_ms, threshold) do
    status = if time_ms <= threshold, do: "✓", else: "✗"
    IO.puts("#{status} #{operation}: #{Float.round(time_ms, 2)}ms (threshold: #{threshold}ms)")
  end
end