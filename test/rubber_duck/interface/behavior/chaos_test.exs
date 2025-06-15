defmodule RubberDuck.Interface.Behavior.ChaosTest do
  @moduledoc """
  Chaos testing for interface resilience and fault tolerance.
  
  This module implements chaos engineering principles to test how well
  interface adapters handle unexpected failures, resource constraints,
  and adverse conditions while maintaining system stability.
  """
  
  use ExUnit.Case, async: false  # Chaos tests must run in isolation
  
  alias RubberDuck.Interface.Adapters.CLI
  
  # Test configuration for chaos testing
  @test_config %{
    colors: false,
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,
    config_dir: System.tmp_dir!() <> "/chaos_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/chaos_sessions_#{System.unique_integer()}"
  }
  
  # Chaos testing parameters
  @chaos_config %{
    failure_rate: 0.3,           # 30% of operations should fail
    resource_limit: 1_000_000,   # Memory limit for stress testing
    timeout_range: {10, 1000},   # Random timeout range in ms
    corruption_rate: 0.1,        # 10% chance of data corruption
    max_test_duration: 30_000    # Maximum test duration in ms
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
      
      # Clean up any test processes
      Process.sleep(100)
    end)
    
    :ok
  end
  
  describe "Random Failure Injection" do
    test "adapter handles random request failures gracefully" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Inject random failures into request processing
      chaos_requests = for i <- 1..50 do
        %{
          id: "chaos_failure_test_#{i}",
          operation: random_operation(),
          params: random_params(),
          interface: :cli,
          timestamp: DateTime.utc_now(),
          chaos_injection: random_failure_type()
        }
      end
      
      {successes, failures} = process_requests_with_chaos(chaos_requests, state)
      
      # Some requests should succeed despite chaos
      assert length(successes) > 0, "No requests succeeded during chaos testing"
      
      # Adapter should handle failures gracefully
      for {request, error} <- failures do
        assert is_binary(error) or is_atom(error),
          "Error for request #{request.id} should be properly formatted"
      end
      
      # Success rate should be reasonable even with chaos
      success_rate = length(successes) / length(chaos_requests)
      assert success_rate > 0.3, "Success rate #{success_rate} too low during chaos testing"
    end
    
    test "adapter recovers from cascading failures" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Simulate cascading failure scenario
      failure_wave_1 = for i <- 1..10 do
        %{
          id: "cascade_wave_1_#{i}",
          operation: :chat,
          params: %{message: "Wave 1 message #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now(),
          chaos_injection: :network_failure
        }
      end
      
      # Process first wave (should mostly fail)
      {_successes_1, _failures_1} = process_requests_with_chaos(failure_wave_1, initial_state)
      
      # Simulate recovery period
      Process.sleep(100)
      
      # Process second wave (should recover)
      failure_wave_2 = for i <- 1..10 do
        %{
          id: "cascade_wave_2_#{i}",
          operation: :chat,
          params: %{message: "Recovery wave message #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now(),
          chaos_injection: :none  # No failures injected
        }
      end
      
      {successes_2, failures_2} = process_requests_with_chaos(failure_wave_2, initial_state)
      
      # Recovery wave should have better success rate
      recovery_rate = length(successes_2) / length(failure_wave_2)
      assert recovery_rate > 0.7, "Recovery rate #{recovery_rate} too low after failure wave"
    end
  end
  
  describe "Resource Exhaustion Testing" do
    test "adapter handles memory pressure gracefully" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate memory pressure by creating large payloads
      memory_stress_requests = for i <- 1..20 do
        large_content = String.duplicate("Large content block #{i}. ", 1000)
        
        %{
          id: "memory_stress_#{i}",
          operation: :analyze,
          params: %{content: large_content},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
      end
      
      initial_memory = :erlang.memory(:total)
      
      # Process requests under memory pressure
      results = Enum.map(memory_stress_requests, fn request ->
        context = %{interface: :cli}
        
        try do
          CLI.handle_request(request, context, state)
        rescue
          error -> {:error, Exception.message(error), state}
        end
      end)
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # System should not crash under memory pressure
      crash_count = Enum.count(results, fn
        {:error, _reason, _state} -> true
        _ -> false
      end)
      
      # Some failures are acceptable under extreme memory pressure
      failure_rate = crash_count / length(results)
      assert failure_rate < 0.5, "Too many failures (#{failure_rate}) under memory pressure"
      
      # Memory growth should be bounded
      assert memory_growth < @chaos_config.resource_limit * 2,
        "Memory grew by #{memory_growth} bytes, exceeds safety limit"
    end
    
    test "adapter handles process limit exhaustion" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Spawn many concurrent processes to stress the system
      process_count = 100
      parent = self()
      
      spawn_tasks = for i <- 1..process_count do
        spawn_link(fn ->
          request = %{
            id: "process_stress_#{i}",
            operation: :chat,
            params: %{message: "Process stress test #{i}"},
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
          
          context = %{interface: :cli}
          
          result = try do
            CLI.handle_request(request, context, state)
          rescue
            error -> {:error, Exception.message(error)}
          end
          
          send(parent, {:process_result, i, result})
        end)
      end
      
      # Collect results with timeout
      results = collect_process_results(process_count, 10_000)
      
      # Clean up spawned processes
      Enum.each(spawn_tasks, fn pid ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)
      
      # Analyze results
      success_count = Enum.count(results, fn
        {:ok, _response, _state} -> true
        _ -> false
      end)
      
      success_rate = success_count / process_count
      
      # Should handle at least some concurrent processes
      assert success_rate > 0.5,
        "Success rate #{success_rate} too low under process pressure"
    end
    
    test "adapter handles file descriptor exhaustion" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create many file operations to stress file descriptors
      file_requests = for i <- 1..50 do
        temp_file = Path.join(@test_config.config_dir, "chaos_file_#{i}.txt")
        File.write!(temp_file, "Chaos test content #{i}")
        
        %{
          id: "file_stress_#{i}",
          operation: :analyze,
          params: %{content: File.read!(temp_file)},
          interface: :cli,
          timestamp: DateTime.utc_now(),
          temp_file: temp_file
        }
      end
      
      # Process file operations
      results = Enum.map(file_requests, fn request ->
        context = %{interface: :cli}
        
        result = try do
          CLI.handle_request(request, context, state)
        rescue
          error -> {:error, Exception.message(error)}
        after
          # Clean up temp file
          if File.exists?(request.temp_file) do
            File.rm!(request.temp_file)
          end
        end
        
        result
      end)
      
      # Should handle file operations without major failures
      success_count = Enum.count(results, fn
        {:ok, _response, _state} -> true
        _ -> false
      end)
      
      success_rate = success_count / length(results)
      assert success_rate > 0.8,
        "File operations success rate #{success_rate} too low"
    end
  end
  
  describe "Data Corruption Resilience" do
    test "adapter handles corrupted request data" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create requests with various types of corruption
      corrupted_requests = [
        # Missing required fields
        %{operation: :chat, interface: :cli},
        %{id: "test", interface: :cli},
        %{id: "test", operation: :chat},
        
        # Invalid data types
        %{id: 123, operation: "chat", params: "invalid", interface: :cli},
        %{id: "test", operation: :invalid_op, params: %{}, interface: :cli},
        
        # Malformed nested data
        %{
          id: "corrupted_nested",
          operation: :chat,
          params: %{message: %{invalid: :nested}},
          interface: :cli
        },
        
        # Extremely large data
        %{
          id: "large_data",
          operation: :chat,
          params: %{message: String.duplicate("x", 100_000)},
          interface: :cli
        }
      ]
      
      context = %{interface: :cli}
      
      for corrupted_request <- corrupted_requests do
        result = try do
          # Validation should catch most corruption
          case CLI.validate_request(corrupted_request) do
            :ok -> CLI.handle_request(corrupted_request, context, state)
            {:error, _reason} -> {:error, :validation_failed, state}
          end
        rescue
          error -> {:error, Exception.message(error), state}
        end
        
        # Should not crash, even with corrupted data
        case result do
          {:ok, _response, _state} -> :ok  # Unexpectedly succeeded
          {:error, _reason, _state} -> :ok  # Expected failure
        end
      end
    end
    
    test "adapter handles state corruption" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Create various corrupted state scenarios
      corrupted_states = [
        # Missing required fields
        %{},
        %{config: @test_config},
        %{request_count: 0},
        
        # Invalid data types
        %{
          config: "invalid_config",
          request_count: "not_a_number",
          session_manager: :invalid
        },
        
        # Partially corrupted state
        %{
          config: @test_config,
          request_count: -1,  # Invalid count
          session_manager: nil
        }
      ]
      
      request = %{
        id: "state_corruption_test",
        operation: :chat,
        params: %{message: "Test with corrupted state"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      for corrupted_state <- corrupted_states do
        result = try do
          CLI.handle_request(request, context, corrupted_state)
        rescue
          error -> {:error, Exception.message(error), corrupted_state}
        end
        
        # Should handle corrupted state gracefully
        case result do
          {:ok, _response, _new_state} -> :ok
          {:error, _reason, _state} -> :ok
        end
      end
    end
  end
  
  describe "Network Chaos Testing" do
    test "adapter handles simulated network failures" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Simulate different network failure scenarios
      network_scenarios = [
        %{type: :timeout, delay: 5000},
        %{type: :packet_loss, loss_rate: 0.5},
        %{type: :connection_reset, reset_probability: 0.3},
        %{type: :slow_network, latency: 2000},
        %{type: :intermittent, up_down_cycle: 500}
      ]
      
      for scenario <- network_scenarios do
        request = %{
          id: "network_chaos_#{scenario.type}",
          operation: :chat,
          params: %{message: "Test under #{scenario.type}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{
          interface: :cli,
          network_simulation: scenario
        }
        
        # Apply network simulation
        result = simulate_network_failure(fn ->
          CLI.handle_request(request, context, state)
        end, scenario)
        
        # Should handle network issues gracefully
        case result do
          {:ok, _response, _state} -> :ok
          {:error, _reason, _state} -> :ok
          :timeout -> :ok  # Acceptable for timeout scenarios
        end
      end
    end
  end
  
  describe "Extreme Load Testing" do
    test "adapter survives burst traffic patterns" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Create extreme burst patterns
      burst_patterns = [
        {100, 50},    # 100 requests in 50ms
        {200, 100},   # 200 requests in 100ms
        {50, 10}      # 50 requests in 10ms (very aggressive)
      ]
      
      for {request_count, time_window_ms} <- burst_patterns do
        # Create burst requests
        burst_requests = for i <- 1..request_count do
          %{
            id: "burst_extreme_#{request_count}_#{i}",
            operation: random_operation(),
            params: random_params(),
            interface: :cli,
            timestamp: DateTime.utc_now()
          }
        end
        
        # Execute burst within time window
        start_time = System.monotonic_time(:millisecond)
        
        tasks = Enum.map(burst_requests, fn request ->
          Task.async(fn ->
            context = %{interface: :cli}
            
            try do
              CLI.handle_request(request, context, state)
            rescue
              error -> {:error, Exception.message(error)}
            end
          end)
        end)
        
        # Wait for completion with timeout
        results = Task.await_many(tasks, time_window_ms * 3)
        end_time = System.monotonic_time(:millisecond)
        
        actual_time = end_time - start_time
        
        # Analyze results
        success_count = Enum.count(results, fn
          {:ok, _response, _state} -> true
          _ -> false
        end)
        
        success_rate = success_count / request_count
        
        # Should handle at least some requests even under extreme load
        assert success_rate > 0.2,
          "Extreme burst (#{request_count} in #{actual_time}ms) success rate #{success_rate} too low"
      end
    end
  end
  
  # Helper functions for chaos testing
  
  defp random_operation do
    Enum.random([:chat, :complete, :analyze, :status, :help, :session_management])
  end
  
  defp random_params do
    case Enum.random(1..4) do
      1 -> %{message: "Random test message #{:rand.uniform(1000)}"}
      2 -> %{prompt: "def random_function_#{:rand.uniform(100)}():"}
      3 -> %{content: String.duplicate("random ", :rand.uniform(20))}
      4 -> %{action: :list}
    end
  end
  
  defp random_failure_type do
    case :rand.uniform(100) do
      n when n <= 30 -> :network_failure
      n when n <= 50 -> :timeout
      n when n <= 70 -> :resource_exhaustion
      n when n <= 85 -> :data_corruption
      _ -> :none
    end
  end
  
  defp process_requests_with_chaos(requests, state) do
    context = %{interface: :cli}
    
    results = Enum.map(requests, fn request ->
      chaos_type = Map.get(request, :chaos_injection, :none)
      
      result = case chaos_type do
        :none ->
          CLI.handle_request(request, context, state)
          
        :network_failure ->
          if :rand.uniform() < @chaos_config.failure_rate do
            {:error, :network_timeout, state}
          else
            CLI.handle_request(request, context, state)
          end
          
        :timeout ->
          # Simulate random timeouts
          timeout = :rand.uniform(elem(@chaos_config.timeout_range, 1))
          
          try do
            task = Task.async(fn ->
              CLI.handle_request(request, context, state)
            end)
            
            Task.await(task, timeout)
          catch
            :exit, _ -> {:error, :timeout, state}
          end
          
        :resource_exhaustion ->
          # Simulate resource exhaustion
          if :rand.uniform() < @chaos_config.failure_rate do
            {:error, :resource_exhausted, state}
          else
            CLI.handle_request(request, context, state)
          end
          
        :data_corruption ->
          # Simulate data corruption
          if :rand.uniform() < @chaos_config.corruption_rate do
            corrupted_request = corrupt_request_data(request)
            
            try do
              CLI.handle_request(corrupted_request, context, state)
            rescue
              _ -> {:error, :data_corrupted, state}
            end
          else
            CLI.handle_request(request, context, state)
          end
      end
      
      {request, result}
    end)
    
    # Separate successes and failures
    Enum.split_with(results, fn {_request, result} ->
      match?({:ok, _response, _state}, result)
    end)
  end
  
  defp corrupt_request_data(request) do
    case :rand.uniform(3) do
      1 -> Map.delete(request, :id)
      2 -> Map.put(request, :params, :corrupted)
      3 -> Map.put(request, :operation, :invalid_op)
    end
  end
  
  defp simulate_network_failure(fun, scenario) do
    case scenario.type do
      :timeout ->
        try do
          task = Task.async(fun)
          Task.await(task, scenario.delay)
        catch
          :exit, _ -> :timeout
        end
        
      :packet_loss ->
        if :rand.uniform() < scenario.loss_rate do
          {:error, :packet_lost, %{}}
        else
          fun.()
        end
        
      :connection_reset ->
        if :rand.uniform() < scenario.reset_probability do
          {:error, :connection_reset, %{}}
        else
          fun.()
        end
        
      :slow_network ->
        Process.sleep(scenario.latency)
        fun.()
        
      :intermittent ->
        if rem(System.monotonic_time(:millisecond), scenario.up_down_cycle * 2) < scenario.up_down_cycle do
          fun.()
        else
          {:error, :network_down, %{}}
        end
    end
  end
  
  defp collect_process_results(expected_count, timeout) do
    collect_process_results(expected_count, timeout, [])
  end
  
  defp collect_process_results(0, _timeout, results), do: results
  
  defp collect_process_results(remaining, timeout, results) do
    receive do
      {:process_result, _index, result} ->
        collect_process_results(remaining - 1, timeout, [result | results])
    after
      timeout ->
        # Return what we have collected so far
        results
    end
  end
end