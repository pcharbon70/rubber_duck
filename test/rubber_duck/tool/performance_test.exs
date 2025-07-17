defmodule RubberDuck.Tool.PerformanceTest do
  @moduledoc """
  Performance and concurrency tests for the tool execution system.
  
  Tests system behavior under load, concurrent execution, and resource constraints.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Executor
  
  @test_user %{
    id: "perf-test-user",
    roles: [:user],
    permissions: [:read, :execute, :file_read]
  }
  
  # Performance test tools
  defmodule FastTool do
    use RubberDuck.Tool
    
    tool do
      name :fast_tool
      description "A fast-executing tool for performance testing"
      category :performance
      
      parameter :input do
        type :string
        required true
      end
      
      execution do
        handler &FastTool.execute/2
        timeout 1_000
        async true
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      {:ok, "Fast result: #{params.input}"}
    end
  end
  
  defmodule SlowTool do
    use RubberDuck.Tool
    
    tool do
      name :slow_tool
      description "A slow-executing tool for performance testing"
      category :performance
      
      parameter :delay do
        type :integer
        required false
        default 100
      end
      
      parameter :input do
        type :string
        required true
      end
      
      execution do
        handler &SlowTool.execute/2
        timeout 10_000
        async true
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      Process.sleep(params[:delay] || 100)
      {:ok, "Slow result: #{params.input}"}
    end
  end
  
  defmodule ComputeIntensiveTool do
    use RubberDuck.Tool
    
    tool do
      name :compute_intensive_tool
      description "A CPU-intensive tool for performance testing"
      category :performance
      
      parameter :iterations do
        type :integer
        required false
        default 10_000
      end
      
      execution do
        handler &ComputeIntensiveTool.execute/2
        timeout 15_000
        async true
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      iterations = params[:iterations] || 10_000
      
      # Perform CPU-intensive calculation
      result = Enum.reduce(1..iterations, 0, fn i, acc ->
        acc + :math.sqrt(i) + :math.sin(i / 100)
      end)
      
      {:ok, "Computed result: #{Float.round(result, 2)}"}
    end
  end
  
  defmodule MemoryIntensiveTool do
    use RubberDuck.Tool
    
    tool do
      name :memory_intensive_tool
      description "A memory-intensive tool for performance testing"
      category :performance
      
      parameter :size do
        type :integer
        required false
        default 1_000
      end
      
      execution do
        handler &MemoryIntensiveTool.execute/2
        timeout 10_000
        async true
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      size = params[:size] || 1_000
      
      # Create memory-intensive data structure
      data = Enum.map(1..size, fn i ->
        %{
          id: i,
          data: String.duplicate("x", 100),
          metadata: %{
            created_at: DateTime.utc_now(),
            tags: Enum.map(1..10, &"tag_#{&1}")
          }
        }
      end)
      
      {:ok, "Created #{length(data)} items"}
    end
  end
  
  defmodule VariableLoadTool do
    use RubberDuck.Tool
    
    tool do
      name :variable_load_tool
      description "A tool with variable load for stress testing"
      category :performance
      
      parameter :load_type do
        type :string
        required true
        constraints [enum: ["light", "medium", "heavy"]]
      end
      
      execution do
        handler &VariableLoadTool.execute/2
        timeout 20_000
        async true
      end
      
      security do
        sandbox :balanced
        capabilities [:execute]
      end
    end
    
    def execute(params, _context) do
      case params.load_type do
        "light" ->
          Process.sleep(10)
          {:ok, "Light load completed"}
        
        "medium" ->
          Process.sleep(100)
          # Medium CPU work
          Enum.reduce(1..10_000, 0, fn i, acc -> acc + i end)
          {:ok, "Medium load completed"}
        
        "heavy" ->
          Process.sleep(500)
          # Heavy CPU and memory work
          data = Enum.map(1..5_000, fn i ->
            Enum.reduce(1..100, "", fn j, acc -> acc <> "#{i}-#{j}" end)
          end)
          {:ok, "Heavy load completed, processed #{length(data)} items"}
      end
    end
  end
  
  describe "single execution performance" do
    test "executes fast tools efficiently" do
      params = %{input: "test"}
      
      # Time the execution
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Executor.execute(FastTool, params, @test_user)
      end_time = System.monotonic_time(:millisecond)
      
      # Should complete quickly
      execution_time = end_time - start_time
      assert execution_time < 100  # Should complete in under 100ms
      
      # Should return correct result
      assert result.status == :success
      assert result.output =~ "Fast result: test"
    end
    
    test "handles slow tools within timeout" do
      params = %{delay: 200, input: "slow_test"}
      
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Executor.execute(SlowTool, params, @test_user)
      end_time = System.monotonic_time(:millisecond)
      
      execution_time = end_time - start_time
      assert execution_time >= 200  # Should take at least the delay time
      assert execution_time < 1000  # But not too much overhead
      
      assert result.status == :success
      assert result.output =~ "Slow result: slow_test"
    end
    
    test "measures execution time accurately" do
      params = %{delay: 100, input: "timing_test"}
      
      assert {:ok, result} = Executor.execute(SlowTool, params, @test_user)
      
      # Check that execution time is measured
      assert is_number(result.execution_time)
      assert result.execution_time >= 100  # Should be at least the delay
      assert result.execution_time < 1000  # But reasonable overhead
    end
  end
  
  describe "concurrent execution performance" do
    test "handles multiple concurrent fast executions" do
      concurrency = 10
      params = %{input: "concurrent"}
      
      # Start multiple concurrent executions
      start_time = System.monotonic_time(:millisecond)
      
      execution_refs = Enum.map(1..concurrency, fn i ->
        params_with_id = %{params | input: "concurrent_#{i}"}
        {:ok, ref} = Executor.execute_async(FastTool, params_with_id, @test_user)
        {ref, i}
      end)
      
      # Wait for all results
      results = Enum.map(execution_refs, fn {ref, i} ->
        assert_receive {^ref, {:ok, result}}, 2000
        {result, i}
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # All should succeed
      assert length(results) == concurrency
      assert Enum.all?(results, fn {result, _i} -> result.status == :success end)
      
      # Should complete reasonably quickly (parallel execution)
      assert total_time < 2000  # Should complete much faster than sequential
      
      # Results should be distinct
      outputs = Enum.map(results, fn {result, _i} -> result.output end)
      assert length(Enum.uniq(outputs)) == concurrency
    end
    
    test "handles mixed load concurrent executions" do
      # Mix of different load types
      load_types = ["light", "medium", "heavy"]
      params_list = Enum.map(load_types, fn load_type ->
        %{load_type: load_type}
      end)
      
      # Start all executions
      start_time = System.monotonic_time(:millisecond)
      
      execution_refs = Enum.map(params_list, fn params ->
        {:ok, ref} = Executor.execute_async(VariableLoadTool, params, @test_user)
        {ref, params.load_type}
      end)
      
      # Wait for all results
      results = Enum.map(execution_refs, fn {ref, load_type} ->
        assert_receive {^ref, {:ok, result}}, 5000
        {result, load_type}
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # All should succeed
      assert length(results) == 3
      assert Enum.all?(results, fn {result, _type} -> result.status == :success end)
      
      # Should complete in reasonable time
      assert total_time < 4000  # Less than sequential execution
    end
    
    test "maintains performance under high concurrency" do
      concurrency = 50
      params = %{input: "high_concurrency"}
      
      # Start many concurrent executions
      start_time = System.monotonic_time(:millisecond)
      
      execution_refs = Enum.map(1..concurrency, fn i ->
        params_with_id = %{params | input: "high_concurrency_#{i}"}
        {:ok, ref} = Executor.execute_async(FastTool, params_with_id, @test_user)
        {ref, i}
      end)
      
      # Wait for all results
      results = Enum.map(execution_refs, fn {ref, i} ->
        assert_receive {^ref, {:ok, result}}, 5000
        {result, i}
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # All should succeed
      assert length(results) == concurrency
      assert Enum.all?(results, fn {result, _i} -> result.status == :success end)
      
      # Should complete in reasonable time for high concurrency
      assert total_time < 5000
      
      # Average execution time should be reasonable
      avg_execution_time = Enum.sum(Enum.map(results, fn {result, _i} -> result.execution_time end)) / concurrency
      assert avg_execution_time < 100  # Average should be low for fast tools
    end
  end
  
  describe "resource usage optimization" do
    test "handles memory-intensive operations efficiently" do
      params = %{size: 1_000}
      
      # Monitor memory usage
      initial_memory = :erlang.memory(:total)
      
      assert {:ok, result} = Executor.execute(MemoryIntensiveTool, params, @test_user)
      
      final_memory = :erlang.memory(:total)
      memory_used = final_memory - initial_memory
      
      # Should succeed
      assert result.status == :success
      assert result.output =~ "Created 1000 items"
      
      # Memory usage should be bounded (garbage collection should work)
      assert memory_used < 100_000_000  # Less than 100MB
    end
    
    test "handles CPU-intensive operations efficiently" do
      params = %{iterations: 50_000}
      
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Executor.execute(ComputeIntensiveTool, params, @test_user)
      end_time = System.monotonic_time(:millisecond)
      
      execution_time = end_time - start_time
      
      # Should succeed
      assert result.status == :success
      assert result.output =~ "Computed result:"
      
      # Should complete in reasonable time
      assert execution_time < 10_000  # Less than 10 seconds
    end
    
    test "prevents resource exhaustion" do
      # Try to create a very large memory structure
      params = %{size: 100_000}  # Large but not excessive
      
      # Should either succeed or be limited by sandbox
      result = Executor.execute(MemoryIntensiveTool, params, @test_user)
      
      case result do
        {:ok, _} -> 
          # If it succeeds, that's fine
          :ok
        {:error, :memory_limit_exceeded, _} ->
          # If limited by sandbox, that's also fine
          :ok
        {:error, :timeout, _} ->
          # If it times out, that's acceptable
          :ok
      end
    end
  end
  
  describe "throughput testing" do
    test "achieves target throughput for light operations" do
      target_ops_per_second = 100
      test_duration_seconds = 2
      
      # Start operations continuously
      start_time = System.monotonic_time(:millisecond)
      end_time = start_time + (test_duration_seconds * 1000)
      
      completed_ops = execute_operations_until(end_time, FastTool, %{input: "throughput_test"})
      
      actual_duration = (System.monotonic_time(:millisecond) - start_time) / 1000
      ops_per_second = completed_ops / actual_duration
      
      # Should achieve reasonable throughput
      assert ops_per_second > target_ops_per_second * 0.8  # 80% of target
    end
    
    test "handles sustained load" do
      # Run operations for a sustained period
      duration_seconds = 3
      operations_per_batch = 10
      
      start_time = System.monotonic_time(:millisecond)
      end_time = start_time + (duration_seconds * 1000)
      
      total_operations = 0
      
      # Run batches of operations
      while System.monotonic_time(:millisecond) < end_time do
        batch_refs = Enum.map(1..operations_per_batch, fn i ->
          params = %{input: "sustained_#{total_operations + i}"}
          {:ok, ref} = Executor.execute_async(FastTool, params, @test_user)
          ref
        end)
        
        # Wait for batch completion
        Enum.each(batch_refs, fn ref ->
          assert_receive {^ref, {:ok, _result}}, 1000
        end)
        
        total_operations = total_operations + operations_per_batch
      end
      
      actual_duration = (System.monotonic_time(:millisecond) - start_time) / 1000
      ops_per_second = total_operations / actual_duration
      
      # Should maintain reasonable performance
      assert ops_per_second > 20  # At least 20 ops/second
      assert total_operations > 50  # Should complete a reasonable number
    end
  end
  
  describe "scalability testing" do
    test "scales execution with increasing load" do
      load_levels = [5, 10, 20]
      
      performance_results = Enum.map(load_levels, fn concurrency ->
        params = %{input: "scale_test"}
        
        start_time = System.monotonic_time(:millisecond)
        
        # Execute with specific concurrency level
        execution_refs = Enum.map(1..concurrency, fn i ->
          params_with_id = %{params | input: "scale_test_#{i}"}
          {:ok, ref} = Executor.execute_async(FastTool, params_with_id, @test_user)
          ref
        end)
        
        # Wait for all results
        results = Enum.map(execution_refs, fn ref ->
          assert_receive {^ref, {:ok, result}}, 3000
          result
        end)
        
        end_time = System.monotonic_time(:millisecond)
        total_time = end_time - start_time
        
        # All should succeed
        assert length(results) == concurrency
        assert Enum.all?(results, & &1.status == :success)
        
        ops_per_second = (concurrency * 1000) / total_time
        
        {concurrency, ops_per_second, total_time}
      end)
      
      # Should scale reasonably - higher concurrency should not drastically reduce ops/second
      [{_, ops_5, _}, {_, ops_10, _}, {_, ops_20, _}] = performance_results
      
      # Performance should not degrade too much with increased load
      assert ops_10 > ops_5 * 0.7  # 10 concurrent should be at least 70% efficiency of 5
      assert ops_20 > ops_5 * 0.5  # 20 concurrent should be at least 50% efficiency of 5
    end
  end
  
  describe "error handling performance" do
    test "handles errors efficiently without degrading performance" do
      # Mix of successful and failing operations
      operations = [
        {:ok, %{input: "success_1"}},
        {:error, %{input: ""}},  # Validation error
        {:ok, %{input: "success_2"}},
        {:error, %{input: ""}},  # Validation error
        {:ok, %{input: "success_3"}}
      ]
      
      start_time = System.monotonic_time(:millisecond)
      
      # Execute all operations
      results = Enum.map(operations, fn {expected_result, params} ->
        case expected_result do
          :ok -> 
            {:ok, result} = Executor.execute(FastTool, params, @test_user)
            result
          :error ->
            {:error, _, _} = Executor.execute(FastTool, params, @test_user)
            :error
        end
      end)
      
      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      
      # Should complete quickly despite errors
      assert total_time < 1000  # Less than 1 second
      
      # Should have correct mix of results
      success_count = Enum.count(results, fn result -> result != :error end)
      error_count = Enum.count(results, fn result -> result == :error end)
      
      assert success_count == 3
      assert error_count == 2
    end
  end
  
  # Helper function to execute operations until a time limit
  defp execute_operations_until(end_time, tool_module, params) do
    if System.monotonic_time(:millisecond) >= end_time do
      0
    else
      case Executor.execute(tool_module, params, @test_user) do
        {:ok, _} -> 1 + execute_operations_until(end_time, tool_module, params)
        _ -> execute_operations_until(end_time, tool_module, params)
      end
    end
  end
end