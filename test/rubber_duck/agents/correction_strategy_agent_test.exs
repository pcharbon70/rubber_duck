defmodule RubberDuck.Agents.CorrectionStrategyAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.CorrectionStrategyAgent
  
  setup do
    # Start the agent with test configuration
    {:ok, agent} = CorrectionStrategyAgent.start_link(
      id: "test_strategy_agent",
      strategy_library: %{
        "test_strategy_1" => %{
          name: "Test Strategy 1",
          category: "syntax",
          description: "Test strategy for syntax errors",
          base_cost: 5.0,
          success_rate: 0.9,
          prerequisites: [],
          constraints: ["complexity == low"],
          metadata: %{
            "risk_level" => "low",
            "avg_execution_time" => 1000,
            "reversible" => true
          }
        },
        "test_strategy_2" => %{
          name: "Test Strategy 2",
          category: "logic",
          description: "Test strategy for logic errors",
          base_cost: 10.0,
          success_rate: 0.7,
          prerequisites: [],
          constraints: ["complexity <= high"],
          metadata: %{
            "risk_level" => "medium",
            "avg_execution_time" => 3000,
            "uses_llm" => true
          }
        }
      }
    )
    
    on_exit(fn ->
      if Process.alive?(agent), do: GenServer.stop(agent)
    end)
    
    {:ok, agent: agent}
  end
  
  describe "signal_mappings/0" do
    test "returns correct action mappings" do
      mappings = CorrectionStrategyAgent.signal_mappings()
      
      assert Map.has_key?(mappings, "strategy_selection_request")
      assert Map.has_key?(mappings, "strategy_outcome_feedback")
      assert Map.has_key?(mappings, "cost_estimation_request")
      assert Map.has_key?(mappings, "performance_metrics_request")
      
      # Verify each mapping has an action and extractor
      Enum.each(mappings, fn {_signal_type, {action, extractor}} ->
        assert is_atom(action)
        assert is_function(extractor, 1)
      end)
    end
  end
  
  describe "strategy selection via action" do
    test "selects appropriate strategy for error", %{agent: agent} do
      # Create test signal
      signal = %{
        "id" => "test_selection_1",
        "type" => "strategy_selection_request",
        "data" => %{
          "error_data" => %{
            "error_id" => "err_123",
            "error_type" => "syntax_error",
            "complexity" => "low"
          },
          "constraints" => %{
            "max_cost" => 50.0,
            "confidence_threshold" => 0.5
          }
        }
      }
      
      # Extract parameters using the agent's extractor
      mappings = CorrectionStrategyAgent.signal_mappings()
      {action_module, extractor} = mappings["strategy_selection_request"]
      params = extractor.(signal)
      
      # Verify extracted parameters
      assert params.error_data == signal["data"]["error_data"]
      assert params.constraints == signal["data"]["constraints"]
      assert params.selection_id == "test_selection_1"
      
      # Execute the action
      context = %{agent: agent}
      {:ok, result} = action_module.run(params, context)
      
      # Verify results
      assert result.selection_id == "test_selection_1"
      assert is_list(result.strategies)
      assert is_map(result.cost_estimates)
      assert is_map(result.confidence_scores)
      assert is_map(result.recommendation)
    end
  end
  
  describe "strategy feedback via action" do
    test "processes outcome feedback", %{agent: agent} do
      # Create feedback signal
      signal = %{
        "id" => "feedback_1",
        "type" => "strategy_outcome_feedback",
        "data" => %{
          "strategy_id" => "test_strategy_1",
          "success" => true,
          "actual_cost" => 4.5,
          "execution_time" => 950,
          "error_context" => %{
            "error_type" => "syntax_error",
            "complexity" => "low"
          },
          "predicted_cost" => 5.0,
          "user_satisfaction" => "satisfied"
        }
      }
      
      # Extract parameters
      mappings = CorrectionStrategyAgent.signal_mappings()
      {action_module, extractor} = mappings["strategy_outcome_feedback"]
      params = extractor.(signal)
      
      # Verify extracted parameters
      assert params.strategy_id == "test_strategy_1"
      assert params.success == true
      assert params.actual_cost == 4.5
      assert params.user_satisfaction == :satisfied
      
      # Execute the action
      context = %{agent: agent}
      {:ok, result, state_updates} = action_module.run(params, context)
      
      # Verify results
      assert result.feedback_id == "feedback_1"
      assert result.learning_applied == true
      assert is_map(result.insights)
      assert is_map(state_updates)
    end
  end
  
  describe "cost estimation via action" do
    test "estimates costs for strategies", %{agent: agent} do
      # Create estimation signal
      signal = %{
        "id" => "estimation_1",
        "type" => "cost_estimation_request",
        "data" => %{
          "error_context" => %{
            "error_type" => "logic_error",
            "complexity" => "medium",
            "file_size" => 500
          },
          "strategies" => ["test_strategy_1", "test_strategy_2"]
        }
      }
      
      # Extract parameters
      mappings = CorrectionStrategyAgent.signal_mappings()
      {action_module, extractor} = mappings["cost_estimation_request"]
      params = extractor.(signal)
      
      # Verify extracted parameters
      assert params.strategies == ["test_strategy_1", "test_strategy_2"]
      assert params.error_context == signal["data"]["error_context"]
      assert params.include_breakdown == true
      assert params.include_roi == true
      
      # Execute the action
      context = %{agent: agent}
      {:ok, result} = action_module.run(params, context)
      
      # Verify results
      assert result.estimation_id == "estimation_1"
      assert is_map(result.cost_estimates)
      assert Map.has_key?(result.cost_estimates, "test_strategy_1")
      assert Map.has_key?(result.cost_estimates, "test_strategy_2")
      
      # Check estimate structure
      estimate = result.cost_estimates["test_strategy_1"]
      assert is_float(estimate.estimated_cost)
      assert is_float(estimate.confidence)
      assert is_map(estimate.time_estimate)
    end
  end
  
  describe "performance metrics via action" do
    test "collects performance metrics", %{agent: agent} do
      # Create metrics signal
      signal = %{
        "id" => "metrics_1",
        "type" => "performance_metrics_request",
        "data" => %{
          "time_range" => "all_time",
          "include_trends" => true,
          "group_by" => "strategy"
        }
      }
      
      # Extract parameters
      mappings = CorrectionStrategyAgent.signal_mappings()
      {action_module, extractor} = mappings["performance_metrics_request"]
      params = extractor.(signal)
      
      # Verify extracted parameters
      assert params.time_range == :all_time
      assert params.include_trends == true
      assert params.group_by == :strategy
      
      # Execute the action
      context = %{agent: agent}
      {:ok, result} = action_module.run(params, context)
      
      # Verify results
      assert result.metrics_id == "metrics_1"
      assert is_map(result.metrics)
      assert is_map(result.insights)
      assert result.time_range == :all_time
    end
  end
  
  describe "lifecycle hooks" do
    test "on_before_init sets default strategy library" do
      config = %{}
      updated_config = CorrectionStrategyAgent.on_before_init(config)
      
      assert Map.has_key?(updated_config, :strategy_library)
      assert is_map(updated_config.strategy_library)
      assert map_size(updated_config.strategy_library) > 0
    end
    
    test "on_after_start logs agent information", %{agent: agent} do
      # This should not fail
      result = CorrectionStrategyAgent.on_after_start(agent)
      assert result == agent
    end
    
    test "on_after_run updates state for feedback action", %{agent: agent} do
      # Simulate feedback action result
      action = RubberDuck.Jido.Actions.Correction.StrategyFeedbackAction
      result = {:ok, %{}, %{learning_data: %{"test" => "data"}}}
      
      {:ok, updated_agent} = CorrectionStrategyAgent.on_after_run(agent, action, result)
      
      # The state should be updated with the new learning data
      assert is_map(updated_agent.state)
    end
  end
  
  describe "health_check/1" do
    test "reports healthy status with valid configuration", %{agent: agent} do
      {:healthy, status} = CorrectionStrategyAgent.health_check(agent)
      
      assert status.status == "All systems operational"
      assert status.strategy_count > 0
      assert is_struct(status.last_check, DateTime)
    end
    
    test "reports unhealthy status with empty strategy library" do
      {:ok, agent} = CorrectionStrategyAgent.start_link(
        id: "unhealthy_agent",
        strategy_library: %{}
      )
      
      try do
        {:unhealthy, status} = CorrectionStrategyAgent.health_check(agent)
        assert "Empty strategy library" in status.issues
      after
        GenServer.stop(agent)
      end
    end
  end
  
  describe "estimate_costs/2 public API" do
    test "estimates costs for available strategies", %{agent: agent} do
      error_context = %{
        "error_type" => "syntax_error",
        "complexity" => "low",
        "file_size" => 500
      }
      
      {:ok, estimates} = CorrectionStrategyAgent.estimate_costs(agent, error_context)
      
      assert is_map(estimates)
      assert Map.has_key?(estimates, "test_strategy_1")
      
      estimate = estimates["test_strategy_1"]
      assert estimate["estimated_cost"] > 0
      assert estimate["confidence"] >= 0 and estimate["confidence"] <= 1
      assert estimate["time_estimate"] > 0
    end
  end
end