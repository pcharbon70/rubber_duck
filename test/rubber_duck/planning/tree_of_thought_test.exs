defmodule RubberDuck.Planning.TreeOfThoughtTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.TaskDecomposer
  
  describe "tree-of-thought approach evaluation" do
    test "calculates approach scores correctly" do
      approach = %{
        "approach_name" => "Iterative Development",
        "confidence_score" => 0.8,
        "risk_level" => "low",
        "estimated_total_effort" => "1w",
        "pros" => ["Fast feedback", "Low risk", "Easy to adjust"],
        "cons" => ["May miss big picture"],
        "best_when" => "Quick delivery is important"
      }
      
      input = %{
        context: %{
          risk_tolerance: :low,
          time_constraint: "2w"
        }
      }
      
      score = TaskDecomposer.calculate_approach_score(approach, input, %{})
      
      assert is_map(score)
      assert score.total > 0
      assert score.confidence > 0
      assert score.risk_alignment > 0.5  # Low risk aligns with low tolerance
      assert score.effort_efficiency > 0.7  # 1w is well under 2w constraint
    end
    
    test "selects best approach from multiple options" do
      approaches = [
        %{
          "approach_name" => "Conservative",
          "confidence_score" => 0.9,
          "risk_level" => "low",
          "estimated_total_effort" => "3w",
          "pros" => ["Very safe", "Predictable"],
          "cons" => ["Slow"],
          "tasks" => [
            %{"name" => "Detailed planning", "complexity" => "medium"},
            %{"name" => "Careful implementation", "complexity" => "medium"}
          ]
        },
        %{
          "approach_name" => "Aggressive",
          "confidence_score" => 0.6,
          "risk_level" => "high",
          "estimated_total_effort" => "1w",
          "pros" => ["Fast delivery"],
          "cons" => ["High risk", "May need rework"],
          "tasks" => [
            %{"name" => "Quick prototype", "complexity" => "simple"},
            %{"name" => "Rapid iteration", "complexity" => "complex"}
          ]
        },
        %{
          "approach_name" => "Balanced",
          "confidence_score" => 0.75,
          "risk_level" => "medium",
          "estimated_total_effort" => "2w",
          "pros" => ["Good balance", "Manageable risk"],
          "cons" => ["Not the fastest"],
          "tasks" => [
            %{"name" => "Modular design", "complexity" => "medium"},
            %{"name" => "Incremental delivery", "complexity" => "medium"}
          ]
        }
      ]
      
      input = %{
        query: "Build a new feature",
        context: %{
          risk_tolerance: :medium,
          time_constraint: "2w"
        }
      }
      
      {:ok, best, comparison} = TaskDecomposer.evaluate_and_select_approach(approaches, input, %{})
      
      # With medium risk tolerance and 2w constraint, Balanced should win
      assert best["approach_name"] == "Balanced"
      assert comparison["selected_approach"] == "Balanced"
      assert is_binary(comparison["selection_reason"])
      assert length(comparison["scores"]) == 3
      assert length(comparison["alternatives"]) == 2
    end
    
    test "handles different risk tolerances" do
      approaches = [
        %{
          "approach_name" => "Safe",
          "confidence_score" => 0.9,
          "risk_level" => "low",
          "estimated_total_effort" => "2w",
          "tasks" => []
        },
        %{
          "approach_name" => "Risky",
          "confidence_score" => 0.7,
          "risk_level" => "high", 
          "estimated_total_effort" => "1w",
          "tasks" => []
        }
      ]
      
      # Test with low risk tolerance
      input_low_risk = %{context: %{risk_tolerance: :low}}
      {:ok, best_low, _} = TaskDecomposer.evaluate_and_select_approach(approaches, input_low_risk, %{})
      assert best_low["approach_name"] == "Safe"
      
      # Test with high risk tolerance
      input_high_risk = %{context: %{risk_tolerance: :high}}
      {:ok, best_high, _} = TaskDecomposer.evaluate_and_select_approach(approaches, input_high_risk, %{})
      assert best_high["approach_name"] == "Risky"
    end
    
    test "formats tasks with approach metadata" do
      approach = %{
        "approach_name" => "Test Approach",
        "philosophy" => "Test first",
        "risk_level" => "low",
        "confidence_score" => 0.85,
        "tasks" => [
          %{
            "name" => "Write tests",
            "description" => "Create test suite",
            "complexity" => "medium"
          },
          %{
            "name" => "Implement feature",
            "description" => "Build the feature",
            "complexity" => "complex",
            "risk" => "medium"
          }
        ]
      }
      
      comparison = %{
        "selection_reason" => "Best approach for testing"
      }
      
      tasks = TaskDecomposer.format_approach_tasks(approach, comparison)
      
      assert length(tasks) == 2
      
      # Check first task
      task1 = Enum.at(tasks, 0)
      assert task1["name"] == "Write tests"
      assert task1["position"] == 0
      assert task1["metadata"]["approach_name"] == "Test Approach"
      assert task1["metadata"]["philosophy"] == "Test first"
      assert task1["metadata"]["approach_confidence"] == 0.85
      
      # Check second task  
      task2 = Enum.at(tasks, 1)
      assert task2["position"] == 1
      assert task2["depends_on"] == [0]
      assert task2["metadata"]["task_risk"] == "medium"  # Task-specific risk
    end
  end
  
  describe "effort calculations" do
    test "converts effort strings to days" do
      assert TaskDecomposer.effort_to_days("1d") == 1
      assert TaskDecomposer.effort_to_days("1w") == 5
      assert TaskDecomposer.effort_to_days("2w") == 10
      assert TaskDecomposer.effort_to_days("1m") == 20
    end
    
    test "calculates effort efficiency" do
      # Under time constraint
      efficiency = TaskDecomposer.calculate_effort_efficiency("1w", "2w")
      assert efficiency > 0.7
      
      # Exactly at constraint
      efficiency = TaskDecomposer.calculate_effort_efficiency("2w", "2w")
      assert efficiency == 0.7
      
      # Over time constraint
      efficiency = TaskDecomposer.calculate_effort_efficiency("3w", "2w")
      assert efficiency < 0.3
    end
  end
end

