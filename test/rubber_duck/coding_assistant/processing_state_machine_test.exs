defmodule RubberDuck.CodingAssistant.ProcessingStateMachineTest do
  @moduledoc """
  Tests for the ProcessingStateMachine dual-mode processing logic.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.CodingAssistant.ProcessingStateMachine
  
  describe "initialization" do
    test "creates initial state with default configuration" do
      {:ok, state} = ProcessingStateMachine.init()
      
      assert state.current_mode == :idle
      assert state.previous_mode == :idle
      assert state.transition_count == 0
      assert state.request_queue == []
      assert state.health_status == :healthy
      assert is_float(state.overload_threshold)
      assert is_float(state.recovery_threshold)
    end
    
    test "accepts custom configuration" do
      config = %{overload_threshold: 0.9, recovery_threshold: 0.3}
      {:ok, state} = ProcessingStateMachine.init(config)
      
      assert state.overload_threshold == 0.9
      assert state.recovery_threshold == 0.3
    end
  end
  
  describe "request handling" do
    test "handles real-time request in idle state" do
      {:ok, state} = ProcessingStateMachine.init()
      
      request = %{
        type: :real_time,
        priority: :normal,
        estimated_complexity: 0.5,
        deadline: nil,
        data_size: 100
      }
      
      {:ok, new_state, actions} = ProcessingStateMachine.handle_request(state, request)
      
      assert new_state.current_mode == :real_time
      assert length(new_state.request_queue) == 1
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :real_time}, action) end)
    end
    
    test "transitions to batch mode with multiple requests" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Add multiple batch requests
      batch_request = %{
        type: :batch,
        priority: :low,
        estimated_complexity: 0.3,
        deadline: nil,
        data_size: 50
      }
      
      # Simulate adding multiple requests
      {:ok, state1, _} = ProcessingStateMachine.handle_request(state, batch_request)
      {:ok, state2, _} = ProcessingStateMachine.handle_request(state1, batch_request)
      {:ok, state3, _} = ProcessingStateMachine.handle_request(state2, batch_request)
      {:ok, state4, _} = ProcessingStateMachine.handle_request(state3, batch_request)
      {:ok, final_state, actions} = ProcessingStateMachine.handle_request(state4, batch_request)
      
      assert final_state.current_mode == :batch
      assert length(final_state.request_queue) == 5
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :batch}, action) end)
    end
    
    test "prioritizes urgent real-time requests" do
      {:ok, state} = ProcessingStateMachine.init()
      
      urgent_request = %{
        type: :real_time,
        priority: :urgent,
        estimated_complexity: 0.8,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second),
        data_size: 200
      }
      
      {:ok, new_state, actions} = ProcessingStateMachine.handle_request(state, urgent_request)
      
      assert new_state.current_mode == :real_time
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :real_time}, action) end)
    end
  end
  
  describe "health-based transitions" do
    test "transitions to degraded mode on health degradation" do
      {:ok, state} = ProcessingStateMachine.init()
      
      {:ok, new_state, actions} = ProcessingStateMachine.update_health(state, :degraded)
      
      assert new_state.current_mode == :degraded
      assert new_state.health_status == :degraded
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :degraded}, action) end)
      assert Enum.any?(actions, fn action -> match?({:alert, :degraded, _}, action) end)
    end
    
    test "transitions to recovery mode on health failure" do
      {:ok, state} = ProcessingStateMachine.init()
      
      {:ok, new_state, actions} = ProcessingStateMachine.update_health(state, :unhealthy)
      
      assert new_state.current_mode == :recovery
      assert new_state.health_status == :unhealthy
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :recovery}, action) end)
      assert Enum.any?(actions, fn action -> match?({:decrease_concurrency, _}, action) end)
    end
    
    test "recovers from degraded to healthy" do
      {:ok, state} = ProcessingStateMachine.init()
      {:ok, degraded_state, _} = ProcessingStateMachine.update_health(state, :degraded)
      
      # Wait for cooldown (simulate time passage)
      old_time = DateTime.add(DateTime.utc_now(), -10, :second)
      degraded_state_with_old_time = %{degraded_state | mode_start_time: old_time}
      
      {:ok, recovered_state, actions} = ProcessingStateMachine.update_health(degraded_state_with_old_time, :healthy)
      
      assert recovered_state.current_mode == :idle
      assert recovered_state.health_status == :healthy
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :idle}, action) end)
    end
  end
  
  describe "metrics updates" do
    test "updates processing metrics from results" do
      {:ok, state} = ProcessingStateMachine.init()
      
      processing_result = %{
        processing_time: 75_000,  # 75ms
        success: true
      }
      
      updated_state = ProcessingStateMachine.update_metrics(state, processing_result)
      
      assert updated_state.processing_metrics.average_response_time > 0
      assert updated_state.processing_metrics.success_rate > 0
    end
    
    test "tracks error rates" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Simulate failed processing
      failed_result = %{
        processing_time: 150_000,
        success: false
      }
      
      updated_state = ProcessingStateMachine.update_metrics(state, failed_result)
      
      assert updated_state.processing_metrics.error_rate > 0
      assert updated_state.processing_metrics.success_rate < 1.0
    end
  end
  
  describe "mode effectiveness" do
    test "calculates effectiveness based on metrics" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Set good metrics
      good_metrics = %{
        average_response_time: 30_000,  # 30ms
        success_rate: 0.95,
        queue_depth: 2,
        error_rate: 0.02,
        cpu_usage: 0.4,
        memory_usage: 0.3,
        throughput: 50.0
      }
      
      state_with_metrics = %{state | processing_metrics: good_metrics}
      summary = ProcessingStateMachine.get_state_summary(state_with_metrics)
      
      assert summary.effectiveness > 0.7
    end
    
    test "detects poor effectiveness" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Set poor metrics
      poor_metrics = %{
        average_response_time: 250_000,  # 250ms
        success_rate: 0.6,
        queue_depth: 25,
        error_rate: 0.3,
        cpu_usage: 0.9,
        memory_usage: 0.85,
        throughput: 5.0
      }
      
      state_with_metrics = %{state | processing_metrics: poor_metrics}
      summary = ProcessingStateMachine.get_state_summary(state_with_metrics)
      
      assert summary.effectiveness < 0.5
    end
  end
  
  describe "overload handling" do
    test "detects overload condition" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Create overload conditions
      overload_metrics = %{
        average_response_time: 300_000,  # 300ms
        success_rate: 0.7,
        queue_depth: 85,  # Near max queue depth
        error_rate: 0.15,
        cpu_usage: 0.95,
        memory_usage: 0.9,
        throughput: 2.0
      }
      
      overloaded_state = %{state | processing_metrics: overload_metrics}
      
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
  
  describe "forced transitions" do
    test "allows manual mode transitions" do
      {:ok, state} = ProcessingStateMachine.init()
      
      {:ok, new_state, actions} = ProcessingStateMachine.force_mode_transition(state, :batch, :manual)
      
      assert new_state.current_mode == :batch
      assert new_state.previous_mode == :idle
      assert new_state.transition_count == 1
      assert Enum.any?(actions, fn action -> match?({:switch_mode, :batch}, action) end)
    end
  end
  
  describe "state history" do
    test "maintains mode history" do
      {:ok, state} = ProcessingStateMachine.init()
      
      # Perform several transitions
      {:ok, state1, _} = ProcessingStateMachine.force_mode_transition(state, :real_time)
      {:ok, state2, _} = ProcessingStateMachine.force_mode_transition(state1, :batch)
      {:ok, final_state, _} = ProcessingStateMachine.force_mode_transition(state2, :idle)
      
      assert length(final_state.mode_history) == 4  # Initial + 3 transitions
      assert final_state.transition_count == 3
      
      # Check history order (most recent first)
      [recent | _] = final_state.mode_history
      assert elem(recent, 0) == :idle
    end
  end
  
  describe "queue management" do
    test "limits queue size" do
      {:ok, state} = ProcessingStateMachine.init()
      
      request = %{
        type: :batch,
        priority: :low,
        estimated_complexity: 0.1,
        deadline: nil,
        data_size: 10
      }
      
      # Add many requests to exceed queue limit
      final_state = Enum.reduce(1..150, state, fn _, acc_state ->
        {:ok, new_state, _} = ProcessingStateMachine.handle_request(acc_state, request)
        new_state
      end)
      
      # Queue should be limited to max size
      assert length(final_state.request_queue) <= 100
    end
    
    test "prioritizes urgent requests in queue" do
      {:ok, state} = ProcessingStateMachine.init()
      
      low_priority = %{
        type: :batch,
        priority: :low,
        estimated_complexity: 0.1,
        deadline: nil,
        data_size: 10
      }
      
      urgent_request = %{
        type: :real_time,
        priority: :urgent,
        estimated_complexity: 0.5,
        deadline: DateTime.add(DateTime.utc_now(), 2, :second),
        data_size: 100
      }
      
      # Fill queue with low priority requests
      {:ok, state1, _} = ProcessingStateMachine.handle_request(state, low_priority)
      {:ok, state2, _} = ProcessingStateMachine.handle_request(state1, low_priority)
      
      # Add urgent request
      {:ok, final_state, _} = ProcessingStateMachine.handle_request(state2, urgent_request)
      
      # Urgent request should influence mode decision
      assert final_state.current_mode == :real_time
    end
  end
end