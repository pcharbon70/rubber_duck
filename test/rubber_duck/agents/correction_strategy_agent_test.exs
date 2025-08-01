defmodule RubberDuck.Agents.CorrectionStrategyAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.CorrectionStrategyAgent
  
  describe "CorrectionStrategyAgent" do
    test "handles strategy selection request signal" do
      # This test should fail initially since the agent doesn't exist yet
      agent = %{
        id: "test-correction-strategy-agent",
        state: %{
          strategy_status: :idle,
          active_evaluations: %{},
          strategy_library: %{},
          cost_models: %{},
          learning_data: %{},
          performance_metrics: %{}
        }
      }
      
      error_data = %{
        "error_id" => "test-error-1",
        "error_type" => "syntax_error",
        "severity" => 8,
        "category" => "elixir_syntax",
        "context" => %{
          "file_path" => "lib/test.ex",
          "line" => 42,
          "description" => "Missing end keyword"
        }
      }
      
      signal = %{
        "type" => "strategy_selection_request",
        "id" => "test-selection-001",
        "data" => %{
          "error_data" => error_data,
          "constraints" => %{
            "max_cost" => 10.0,
            "time_limit" => 5000,
            "confidence_threshold" => 0.7
          }
        }
      }
      
      # This should return strategy recommendations
      assert {:ok, updated_agent} = CorrectionStrategyAgent.handle_signal(agent, signal)
      assert updated_agent.state.strategy_status == :idle
      
      # Should have processed the selection request (active_evaluations are cleaned up after completion)
      assert updated_agent.state.active_evaluations == %{}
    end
    
    test "provides cost estimation for correction strategies" do
      agent = %{
        id: "test-correction-strategy-agent",
        state: %{
          strategy_status: :idle,
          strategy_library: %{
            "syntax_fix_basic" => %{
              name: "Basic Syntax Fix",
              category: "syntax",
              base_cost: 2.0,
              success_rate: 0.85,
              prerequisites: [],
              constraints: [],
              metadata: %{
                "avg_execution_time" => 1500,
                "risk_level" => "low"
              }
            }
          },
          cost_models: %{
            "time_based" => %{
              "weight" => 0.4,
              "base_rate" => 0.10
            },
            "complexity_based" => %{
              "weight" => 0.3,
              "multipliers" => %{"low" => 1.0, "medium" => 1.5, "high" => 2.0}
            },
            "risk_based" => %{
              "weight" => 0.3,
              "multipliers" => %{"low" => 1.0, "medium" => 1.3, "high" => 1.8}
            }
          },
          learning_data: %{},
          performance_metrics: %{}
        }
      }
      
      error_context = %{
        "error_type" => "syntax_error",
        "complexity" => "low",
        "file_size" => 150
      }
      
      # This should fail initially since cost estimation logic doesn't exist
      # The agent should provide cost estimates for available strategies
      # Expected structure: {:ok, %{strategy_id => %{estimated_cost, confidence, time_estimate}}}
      result = CorrectionStrategyAgent.estimate_costs(agent, error_context)
      
      assert {:ok, cost_estimates} = result
      assert Map.has_key?(cost_estimates, "syntax_fix_basic")
      assert cost_estimates["syntax_fix_basic"]["estimated_cost"] > 0
    end
    
    test "learns from correction outcomes" do
      agent = %{
        id: "test-correction-strategy-agent", 
        state: %{
          strategy_status: :idle,
          learning_data: %{},
          performance_metrics: %{
            "syntax_fix_basic" => %{
              "success_count" => 10,
              "total_attempts" => 12,
              "avg_cost" => 2.3
            }
          }
        }
      }
      
      outcome_data = %{
        "strategy_id" => "syntax_fix_basic",
        "success" => true,
        "actual_cost" => 2.1,
        "execution_time" => 1200,
        "error_context" => %{"error_type" => "syntax_error"}
      }
      
      signal = %{
        "type" => "strategy_outcome_feedback",
        "id" => "feedback-001", 
        "data" => outcome_data
      }
      
      # This should fail initially - agent should process learning feedback
      assert {:ok, updated_agent} = CorrectionStrategyAgent.handle_signal(agent, signal)
      
      # Performance metrics should be updated
      updated_metrics = updated_agent.state.performance_metrics["syntax_fix_basic"]
      assert updated_metrics["success_count"] == 11
      assert updated_metrics["total_attempts"] == 13
    end
  end
end