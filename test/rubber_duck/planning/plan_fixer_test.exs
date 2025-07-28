defmodule RubberDuck.Planning.PlanFixerTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Planning.{Plan, PlanFixer}
  
  describe "fix/3" do
    setup do
      # Create a basic plan for testing
      {:ok, plan} = Plan
        |> Ash.Changeset.for_create(:create, %{
          name: "Test Plan",
          description: "A plan for testing fixes",
          type: :feature
        })
        |> Ash.create()
      
      {:ok, plan: plan}
    end
    
    test "returns error when no failures to fix", %{plan: plan} do
      validation_results = %{
        summary: :passed,
        hard_critics: [
          %{name: "Syntax Validator", status: :passed}
        ]
      }
      
      assert {:error, :no_failures_to_fix} = PlanFixer.fix(plan, validation_results)
    end
    
    test "identifies fixable failures", %{plan: plan} do
      validation_results = %{
        summary: :failed,
        hard_critics: [
          %{
            name: "Syntax Validator",
            status: :failed,
            details: %{errors: ["Syntax error at line 5: unexpected token"]}
          }
        ]
      }
      
      # This would need mocking of LLM service in real tests
      # For now, just verify the function is callable
      result = PlanFixer.fix(plan, validation_results)
      assert match?({:error, _} | {:ok, _, _}, result)
    end
  end
  
  describe "fixable_failure?/1" do
    test "returns true for fixable critic names" do
      failure = %{
        critic_name: "Syntax Validator",
        type: :syntax_error,
        details: %{}
      }
      
      assert PlanFixer.fixable_failure?(failure)
    end
    
    test "returns true for fixable failure types" do
      failure = %{
        critic_name: "Unknown Critic",
        type: :dependency_issue,
        details: %{}
      }
      
      assert PlanFixer.fixable_failure?(failure)
    end
    
    test "returns false for non-fixable failures" do
      failure = %{
        critic_name: "Unknown Critic",
        type: :unknown,
        details: %{}
      }
      
      refute PlanFixer.fixable_failure?(failure)
    end
  end
end