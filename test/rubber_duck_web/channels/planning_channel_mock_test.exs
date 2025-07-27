defmodule RubberDuckWeb.PlanningChannelMockTest do
  use RubberDuckWeb.ChannelCase
  
  alias RubberDuckWeb.PlanningChannel
  alias RubberDuck.Planning.Plan
  
  setup do
    {:ok, _, socket} =
      socket(RubberDuckWeb.UserSocket, "user_id", %{user_id: "test-user"})
      |> subscribe_and_join(PlanningChannel, "planning:lobby")
    
    %{socket: socket}
  end
  
  describe "plan creation" do
    test "successfully creates a plan", %{socket: socket} do
      params = %{
        "name" => "Test Plan",
        "description" => "A simple test plan",
        "type" => "feature",
        "skip_validation" => true  # Skip validation to avoid engine dependencies
      }
      
      ref = push(socket, "create_plan", params)
      
      assert_reply ref, :ok, response
      assert response.plan.name == "Test Plan"
      assert response.plan.type == :feature
      assert response.validation.summary == :skipped
      # When validation is skipped, plan can still be ready for execution
      assert response.ready_for_execution == true
    end
    
    test "handles invalid plan type", %{socket: socket} do
      params = %{
        "name" => "Invalid Plan",
        "description" => "Test description",
        "type" => "invalid_type"
      }
      
      ref = push(socket, "create_plan", params)
      
      assert_reply ref, :error, %{message: message}
      assert message =~ "Invalid plan type"
    end
  end
  
  describe "plan listing" do
    test "lists plans with filters", %{socket: socket} do
      # Create a test plan first
      {:ok, plan} = Plan
        |> Ash.Changeset.for_create(:create, %{
          name: "List Test Plan",
          description: "Plan for testing list functionality",
          type: :feature,
          metadata: %{"created_by" => "test-user"}
        })
        |> Ash.create()
      
      params = %{
        "status" => "draft",
        "limit" => 10
      }
      
      ref = push(socket, "list_plans", params)
      
      assert_reply ref, :ok, %{plans: plans}
      assert is_list(plans)
      
      # Should include our created plan
      plan_ids = Enum.map(plans, & &1.id)
      assert plan.id in plan_ids
    end
  end
  
  describe "plan retrieval" do
    test "gets plan details", %{socket: socket} do
      # Create a test plan
      {:ok, plan} = Plan
        |> Ash.Changeset.for_create(:create, %{
          name: "Get Test Plan",
          description: "Plan for testing get functionality",
          type: :bugfix,
          metadata: %{"created_by" => "test-user"}
        })
        |> Ash.create()
      
      ref = push(socket, "get_plan", %{"plan_id" => plan.id})
      
      assert_reply ref, :ok, %{plan: retrieved_plan}
      assert retrieved_plan.id == plan.id
      assert retrieved_plan.name == "Get Test Plan"
      assert retrieved_plan.type == :bugfix
    end
    
    test "handles non-existent plan", %{socket: socket} do
      fake_id = Ecto.UUID.generate()
      
      ref = push(socket, "get_plan", %{"plan_id" => fake_id})
      
      assert_reply ref, :error, %{message: _}
    end
  end
end