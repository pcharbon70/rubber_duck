defmodule RubberDuck.Agents.CriticsCoordinatorIntegrationTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.CriticsCoordinatorAgent
  alias RubberDuck.Agents.Critics.SyntaxValidatorAgent
  
  describe "coordinator and critic agent integration" do
    test "coordinator can work with critic agents" do
      # Create coordinator
      coordinator = %{
        id: "test_coordinator",
        state: %{
          active_validations: %{},
          critic_registry: %{},
          cache: %{},
          cache_enabled: false, # Disable for testing
          parallel_execution: false,
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
      
      # Create syntax validator agent
      syntax_validator = %{
        id: "syntax_validator_1",
        state: %{
          validations_performed: 0,
          last_validation_at: nil,
          supported_languages: ["elixir"]
        }
      }
      
      # Register the critic with coordinator
      registration = SyntaxValidatorAgent.registration_signal(syntax_validator.id)
      {:ok, coordinator} = CriticsCoordinatorAgent.handle_signal(coordinator, registration)
      
      # Verify registration
      assert Map.has_key?(coordinator.state.critic_registry, "syntax_validator_1")
      
      # Create a validation request
      validation_signal = %{
        "type" => "validate_target",
        "target_type" => "task",
        "target_id" => "task_with_code",
        "target_data" => %{
          "name" => "Parse JSON",
          "description" => "Parse JSON data with error handling",
          "code" => """
          defmodule JsonParser do
            def parse(json_string) do
              case Jason.decode(json_string) do
                {:ok, data} -> {:ok, data}
                {:error, reason} -> {:error, "Failed to parse: \#{reason}"}
              end
            end
          end
          """
        }
      }
      
      # Send validation request to coordinator
      {:ok, coordinator} = CriticsCoordinatorAgent.handle_signal(coordinator, validation_signal)
      
      # Verify validation was started
      assert Map.has_key?(coordinator.state.active_validations, "task_with_code")
    end
    
    test "syntax validator detects syntax errors" do
      validator = %{
        id: "syntax_validator",
        state: %{
          validations_performed: 0,
          last_validation_at: nil,
          supported_languages: ["elixir"]
        }
      }
      
      # Create validation request with syntax error
      validation_signal = %{
        "type" => "validate",
        "request_id" => "req_123",
        "target_type" => "task",
        "target_id" => "task_with_error",
        "target_data" => %{
          "name" => "Broken code",
          "code" => """
          defmodule Broken do
            def missing_end(x) do
              x + 1
            # Missing 'end' here
          end
          """
        }
      }
      
      {:ok, updated_validator} = SyntaxValidatorAgent.handle_signal(validator, validation_signal)
      
      # Verify validation was performed
      assert updated_validator.state.validations_performed == 1
      assert updated_validator.state.last_validation_at != nil
    end
    
    test "coordinator aggregates results correctly" do
      results = [
        %{
          "critic_id" => "syntax_validator",
          "critic_type" => "hard",
          "status" => "passed",
          "message" => "Syntax is valid"
        },
        %{
          "critic_id" => "complexity_checker",
          "critic_type" => "soft",
          "status" => "warning",
          "message" => "Function is too complex",
          "suggestions" => ["Consider breaking into smaller functions"]
        }
      ]
      
      aggregated = CriticsCoordinatorAgent.aggregate_results(results)
      
      assert aggregated["overall_status"] == "warning"
      assert length(aggregated["all_suggestions"]) == 1
      assert aggregated["summary"] =~ "1 passed"
      assert aggregated["summary"] =~ "1 warnings"
    end
  end
  
  describe "multiple critic types" do
    test "coordinator selects appropriate critics by type" do
      critics = %{
        "hard_critic_1" => %{
          "critic_type" => "hard",
          "capabilities" => %{"targets" => ["task"], "priority" => 10}
        },
        "hard_critic_2" => %{
          "critic_type" => "hard", 
          "capabilities" => %{"targets" => ["task"], "priority" => 20}
        },
        "soft_critic_1" => %{
          "critic_type" => "soft",
          "capabilities" => %{"targets" => ["task"], "priority" => 30}
        }
      }
      
      # Request only hard critics
      selected = CriticsCoordinatorAgent.select_critics(critics, %{
        "target_type" => "task",
        "critic_types" => ["hard"]
      })
      
      assert length(selected) == 2
      assert Enum.all?(selected, fn {_, c} -> c["critic_type"] == "hard" end)
      
      # Verify priority ordering
      [first, second] = selected
      assert elem(first, 1)["capabilities"]["priority"] < elem(second, 1)["capabilities"]["priority"]
    end
  end
end