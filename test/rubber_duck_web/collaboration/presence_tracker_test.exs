defmodule RubberDuckWeb.Collaboration.PresenceTrackerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuckWeb.Collaboration.PresenceTracker
  
  setup do
    # Start the GenServer for tests
    {:ok, _pid} = start_supervised(PresenceTracker)
    
    project_id = "test-project-#{Ecto.UUID.generate()}"
    user_id = "user-#{Ecto.UUID.generate()}"
    user_data = %{
      username: "testuser",
      email: "test@example.com",
      avatar_url: nil
    }
    
    {:ok, project_id: project_id, user_id: user_id, user_data: user_data}
  end
  
  describe "track_user/3" do
    test "tracks a new user", %{project_id: project_id, user_id: user_id, user_data: user_data} do
      assert :ok = PresenceTracker.track_user(project_id, user_id, user_data)
      
      users = PresenceTracker.get_users(project_id)
      assert length(users) == 1
      
      [user] = users
      assert user.id == user_id
      assert user.username == "testuser"
      assert user.color != nil
      assert user.status == :active
    end
    
    test "assigns consistent colors to users", %{project_id: project_id, user_data: user_data} do
      # Same user should get same color
      user_id = "consistent-user"
      PresenceTracker.track_user(project_id, user_id, user_data)
      [user1] = PresenceTracker.get_users(project_id)
      
      # Track again (simulate rejoin)
      PresenceTracker.track_user(project_id, user_id, user_data)
      [user2] = PresenceTracker.get_users(project_id)
      
      assert user1.color == user2.color
    end
    
    test "generates avatar URL from email", %{project_id: project_id, user_id: user_id} do
      user_data = %{
        username: "testuser",
        email: "test@example.com",
        avatar_url: nil
      }
      
      PresenceTracker.track_user(project_id, user_id, user_data)
      [user] = PresenceTracker.get_users(project_id)
      
      assert user.avatar_url =~ "gravatar.com"
      assert user.avatar_url =~ "d=identicon"
    end
  end
  
  describe "update_cursor/4" do
    test "updates user cursor position", %{project_id: project_id, user_id: user_id, user_data: user_data} do
      PresenceTracker.track_user(project_id, user_id, user_data)
      
      position = %{line: 10, column: 5}
      assert :ok = PresenceTracker.update_cursor(project_id, user_id, "test.ex", position)
      
      user_info = PresenceTracker.get_user_info(project_id, user_id)
      assert user_info.cursor.line == 10
      assert user_info.cursor.column == 5
      assert user_info.cursor.file == "test.ex"
      assert user_info.current_file == "test.ex"
    end
    
    test "ignores cursor update for untracked user", %{project_id: project_id} do
      position = %{line: 10, column: 5}
      assert :ok = PresenceTracker.update_cursor(project_id, "unknown-user", "test.ex", position)
      
      # Should not crash, just ignore
      users = PresenceTracker.get_users(project_id)
      assert users == []
    end
  end
  
  describe "update_selection/4" do
    test "updates user selection", %{project_id: project_id, user_id: user_id, user_data: user_data} do
      PresenceTracker.track_user(project_id, user_id, user_data)
      
      selection = %{
        start_line: 5,
        start_column: 1,
        end_line: 10,
        end_column: 20
      }
      
      assert :ok = PresenceTracker.update_selection(project_id, user_id, "test.ex", selection)
      
      user_info = PresenceTracker.get_user_info(project_id, user_id)
      assert user_info.selection.start_line == 5
      assert user_info.selection.end_line == 10
    end
  end
  
  describe "update_activity/3" do
    test "updates user activity", %{project_id: project_id, user_id: user_id, user_data: user_data} do
      PresenceTracker.track_user(project_id, user_id, user_data)
      
      assert :ok = PresenceTracker.update_activity(project_id, user_id, :typing)
      
      user_info = PresenceTracker.get_user_info(project_id, user_id)
      assert user_info.activity.type == :typing
      assert user_info.status == :active
    end
    
    test "idle activity changes status", %{project_id: project_id, user_id: user_id, user_data: user_data} do
      PresenceTracker.track_user(project_id, user_id, user_data)
      
      assert :ok = PresenceTracker.update_activity(project_id, user_id, :idle)
      
      user_info = PresenceTracker.get_user_info(project_id, user_id)
      assert user_info.status == :idle
    end
  end
  
  describe "get_users/1" do
    test "returns all active users", %{project_id: project_id, user_data: user_data} do
      # Track multiple users
      PresenceTracker.track_user(project_id, "user1", user_data)
      PresenceTracker.track_user(project_id, "user2", %{user_data | username: "user2"})
      PresenceTracker.track_user(project_id, "user3", %{user_data | username: "user3"})
      
      users = PresenceTracker.get_users(project_id)
      assert length(users) == 3
      
      usernames = Enum.map(users, & &1.username)
      assert "testuser" in usernames
      assert "user2" in usernames
      assert "user3" in usernames
    end
    
    test "returns empty list for unknown project" do
      users = PresenceTracker.get_users("unknown-project")
      assert users == []
    end
  end
end