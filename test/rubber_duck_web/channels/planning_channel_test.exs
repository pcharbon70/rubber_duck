defmodule RubberDuckWeb.PlanningChannelTest do
  use RubberDuckWeb.ChannelCase
  
  alias RubberDuckWeb.PlanningChannel
  
  setup do
    {:ok, _, socket} =
      socket(RubberDuckWeb.UserSocket, "user_id", %{user_id: "test-user"})
      |> subscribe_and_join(PlanningChannel, "planning:lobby")
    
    %{socket: socket}
  end
  
  describe "decompose_task" do
    test "successfully decomposes a task description", %{socket: socket} do
      params = %{
        "description" => "Implement a REST API for user management with CRUD operations",
        "context" => %{"language" => "elixir"}
      }
      
      ref = push(socket, "decompose_task", params)
      
      assert_reply ref, :ok, %{tasks: tasks}
      assert is_list(tasks)
      assert length(tasks) > 0
      
      # Verify task structure
      Enum.each(tasks, fn task ->
        assert Map.has_key?(task, :name)
        assert Map.has_key?(task, :description)
        assert Map.has_key?(task, :position)
        assert Map.has_key?(task, :complexity)
      end)
    end
    
    test "handles missing description", %{socket: socket} do
      params = %{"context" => %{}}
      
      ref = push(socket, "decompose_task", params)
      
      assert_reply ref, :error, %{message: "Missing required field: description"}
    end
    
    test "includes user context in decomposition", %{socket: socket} do
      params = %{
        "description" => "Create a simple to-do list application",
        "context" => %{
          "framework" => "phoenix",
          "database" => "postgres"
        },
        "constraints" => %{
          "time_limit" => "1 week",
          "team_size" => 1
        }
      }
      
      ref = push(socket, "decompose_task", params)
      
      assert_reply ref, :ok, %{tasks: tasks}
      assert length(tasks) > 0
      
      # Tasks should be appropriately scoped for constraints
      complexities = Enum.map(tasks, & &1[:complexity])
      # With 1 week time limit and single developer, shouldn't have too many complex tasks
      complex_count = Enum.count(complexities, &(&1 in [:complex, :very_complex]))
      assert complex_count <= length(tasks) / 2
    end
  end
  
  describe "create_plan with automatic decomposition" do
    test "creates plan and decomposes tasks for feature type", %{socket: socket} do
      params = %{
        "name" => "User Authentication System",
        "description" => "Build a complete authentication system with registration, login, and password reset",
        "type" => "feature"
      }
      
      ref = push(socket, "create_plan", params)
      
      assert_reply ref, :ok, %{plan: plan, validation: validation}
      
      assert plan.name == "User Authentication System"
      assert plan.type == :feature
      assert plan.task_count > 0  # Should have decomposed tasks
      assert validation.summary in [:passed, :warning]
    end
  end
end