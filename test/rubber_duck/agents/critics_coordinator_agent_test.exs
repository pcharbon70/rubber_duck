defmodule RubberDuck.Agents.CriticsCoordinatorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.CriticsCoordinatorAgent
  
  describe "agent initialization" do
    test "starts with proper initial state" do
      agent = %{
        id: "test_coordinator",
        state: %{
          active_validations: %{},
          critic_registry: %{},
          cache: %{},
          cache_enabled: true,
          parallel_execution: true,
          timeout: 30_000,
          max_retries: 3,
          metrics: %{
            total_validations: 0,
            cache_hits: 0,
            cache_misses: 0,
            critic_performance: %{}
          }
        }
      }
      
      assert agent.state.active_validations == %{}
      assert agent.state.critic_registry == %{}
      assert agent.state.cache_enabled == true
    end
  end
  
  describe "critic registration" do
    setup do
      agent = %{
        id: "test_coordinator",
        state: %{
          active_validations: %{},
          critic_registry: %{},
          cache: %{},
          cache_enabled: true,
          parallel_execution: true,
          timeout: 30_000,
          max_retries: 3,
          metrics: %{
            total_validations: 0,
            cache_hits: 0,
            cache_misses: 0,
            critic_performance: %{}
          }
        }
      }
      %{agent: agent}
    end
    
    test "registers a new critic", %{agent: agent} do
      signal = %{
        "type" => "register_critic",
        "critic_id" => "syntax_validator",
        "critic_type" => "hard",
        "capabilities" => %{
          "targets" => ["task", "plan"],
          "languages" => ["elixir", "javascript"],
          "priority" => 10
        }
      }
      
      assert {:ok, updated_agent} = CriticsCoordinatorAgent.handle_signal(agent, signal)
      assert Map.has_key?(updated_agent.state.critic_registry, "syntax_validator")
      
      critic = updated_agent.state.critic_registry["syntax_validator"]
      assert critic["critic_type"] == "hard"
      assert critic["capabilities"]["languages"] == ["elixir", "javascript"]
    end
    
    test "unregisters a critic", %{agent: agent} do
      # First register a critic
      agent_with_critic = put_in(agent.state.critic_registry["test_critic"], %{
        "critic_type" => "soft",
        "capabilities" => %{}
      })
      
      signal = %{
        "type" => "unregister_critic",
        "critic_id" => "test_critic"
      }
      
      assert {:ok, updated_agent} = CriticsCoordinatorAgent.handle_signal(agent_with_critic, signal)
      refute Map.has_key?(updated_agent.state.critic_registry, "test_critic")
    end
  end
  
  describe "validation requests" do
    setup do
      agent = %{
        id: "test_coordinator",
        state: %{
          active_validations: %{},
          critic_registry: %{
            "mock_hard_critic" => %{
              "critic_type" => "hard",
              "capabilities" => %{
                "targets" => ["task", "plan"],
                "priority" => 10
              }
            },
            "mock_soft_critic" => %{
              "critic_type" => "soft", 
              "capabilities" => %{
                "targets" => ["task", "plan"],
                "priority" => 20
              }
            }
          },
          cache: %{},
          cache_enabled: true,
          parallel_execution: true,
          timeout: 30_000,
          max_retries: 3,
          metrics: %{
            total_validations: 0,
            cache_hits: 0,
            cache_misses: 0,
            critic_performance: %{}
          }
        }
      }
      %{agent: agent}
    end
    
    test "starts validation for a target", %{agent: agent} do
      signal = %{
        "type" => "validate_target",
        "target_type" => "task",
        "target_id" => "task_123",
        "target_data" => %{
          "name" => "Test Task",
          "description" => "A task for testing",
          "complexity" => "medium"
        }
      }
      
      assert {:ok, updated_agent} = CriticsCoordinatorAgent.handle_signal(agent, signal)
      
      # Should track active validation
      assert Map.has_key?(updated_agent.state.active_validations, "task_123")
      validation = updated_agent.state.active_validations["task_123"]
      assert validation.status == :in_progress
      assert validation.target_type == "task"
    end
    
    test "uses cached results when available", %{agent: agent} do
      # Pre-populate cache
      cache_key = "task:task_456:#{:erlang.phash2(%{})}"
      cached_result = %{
        "status" => "passed",
        "critics_run" => ["mock_hard_critic"],
        "timestamp" => DateTime.utc_now()
      }
      
      agent_with_cache = put_in(agent.state.cache[cache_key], cached_result)
      
      signal = %{
        "type" => "validate_target",
        "target_type" => "task",
        "target_id" => "task_456",
        "target_data" => %{
          "name" => "Cached Task"
        }
      }
      
      assert {:ok, updated_agent} = CriticsCoordinatorAgent.handle_signal(agent_with_cache, signal)
      
      # Should use cache and not create active validation
      refute Map.has_key?(updated_agent.state.active_validations, "task_456")
      assert updated_agent.state.metrics.cache_hits == 1
    end
  end
  
  describe "result aggregation" do
    test "aggregates results from multiple critics" do
      results = [
        %{
          "critic_id" => "syntax_validator",
          "critic_type" => "hard",
          "status" => "passed",
          "message" => "Syntax is valid"
        },
        %{
          "critic_id" => "style_checker",
          "critic_type" => "soft",
          "status" => "warning",
          "message" => "Consider using pattern matching",
          "suggestions" => ["Replace if-else with case statement"]
        }
      ]
      
      aggregated = CriticsCoordinatorAgent.aggregate_results(results)
      
      assert aggregated["overall_status"] == "warning"
      assert length(aggregated["hard_critics"]) == 1
      assert length(aggregated["soft_critics"]) == 1
      assert length(aggregated["all_suggestions"]) == 1
    end
    
    test "handles critic failures in aggregation" do
      results = [
        %{
          "critic_id" => "failing_critic",
          "critic_type" => "hard",
          "status" => "failed",
          "message" => "Critical issue found"
        },
        %{
          "critic_id" => "passing_critic",
          "critic_type" => "soft",
          "status" => "passed",
          "message" => "Looks good"
        }
      ]
      
      aggregated = CriticsCoordinatorAgent.aggregate_results(results)
      
      assert aggregated["overall_status"] == "failed"
      assert length(aggregated["blocking_issues"]) == 1
    end
  end
  
  describe "critic selection" do
    setup do
      critics = %{
        "elixir_critic" => %{
          "critic_type" => "hard",
          "capabilities" => %{
            "targets" => ["task"],
            "languages" => ["elixir"],
            "priority" => 10
          }
        },
        "js_critic" => %{
          "critic_type" => "hard",
          "capabilities" => %{
            "targets" => ["task"],
            "languages" => ["javascript"],
            "priority" => 15
          }
        },
        "general_critic" => %{
          "critic_type" => "soft",
          "capabilities" => %{
            "targets" => ["task", "plan"],
            "priority" => 20
          }
        }
      }
      %{critics: critics}
    end
    
    test "selects critics based on target type", %{critics: critics} do
      selected = CriticsCoordinatorAgent.select_critics(critics, %{
        "target_type" => "plan",
        "critic_types" => nil
      })
      
      # Only general_critic supports plans
      assert length(selected) == 1
      assert hd(selected) == {"general_critic", critics["general_critic"]}
    end
    
    test "filters by critic type when specified", %{critics: critics} do
      selected = CriticsCoordinatorAgent.select_critics(critics, %{
        "target_type" => "task",
        "critic_types" => ["hard"]
      })
      
      # Only hard critics
      assert length(selected) == 2
      assert Enum.all?(selected, fn {_, critic} -> critic["critic_type"] == "hard" end)
    end
    
    test "sorts critics by priority", %{critics: critics} do
      selected = CriticsCoordinatorAgent.select_critics(critics, %{
        "target_type" => "task",
        "critic_types" => nil
      })
      
      priorities = Enum.map(selected, fn {_, c} -> c["capabilities"]["priority"] end)
      assert priorities == [10, 15, 20]
    end
  end
end