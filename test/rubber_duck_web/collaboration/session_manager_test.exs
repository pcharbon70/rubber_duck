defmodule RubberDuckWeb.Collaboration.SessionManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuckWeb.Collaboration.SessionManager

  setup do
    {:ok, _pid} = start_supervised(SessionManager)

    project_id = "test-project-#{Ecto.UUID.generate()}"
    owner_id = "owner-#{Ecto.UUID.generate()}"

    {:ok, project_id: project_id, owner_id: owner_id}
  end

  describe "create_session/3" do
    test "creates a new collaborative session", %{project_id: project_id, owner_id: owner_id} do
      params = %{
        name: "Test Session",
        description: "A test collaborative session",
        record: false,
        max_participants: 5
      }

      assert {:ok, session} = SessionManager.create_session(project_id, owner_id, params)

      assert session.project_id == project_id
      assert session.owner_id == owner_id
      assert session.name == "Test Session"
      assert session.state == :active
      assert map_size(session.participants) == 1
      assert session.participants[owner_id].role == :owner
    end

    test "starts recording if requested", %{project_id: project_id, owner_id: owner_id} do
      params = %{name: "Recorded Session", record: true}

      assert {:ok, session} = SessionManager.create_session(project_id, owner_id, params)
      assert session.is_recording == true
      assert session.recording_id != nil
    end
  end

  describe "join_session/3" do
    setup %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{})
      {:ok, session: session}
    end

    test "allows users to join session", %{session: session} do
      user_id = "user-#{Ecto.UUID.generate()}"

      assert {:ok, updated_session} = SessionManager.join_session(session.id, user_id, :editor)
      assert map_size(updated_session.participants) == 2
      assert updated_session.participants[user_id].role == :editor
    end

    test "prevents duplicate joins", %{session: session} do
      user_id = "user-#{Ecto.UUID.generate()}"

      {:ok, _} = SessionManager.join_session(session.id, user_id, :editor)
      assert {:error, :already_in_session} = SessionManager.join_session(session.id, user_id, :viewer)
    end

    test "enforces max participants", %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{max_participants: 2})

      # Owner is already participant 1
      {:ok, _} = SessionManager.join_session(session.id, "user1", :editor)

      # Third user should be rejected
      assert {:error, :session_full} = SessionManager.join_session(session.id, "user2", :editor)
    end
  end

  describe "update_participant_role/3" do
    setup %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{})
      user_id = "user-#{Ecto.UUID.generate()}"
      {:ok, _} = SessionManager.join_session(session.id, user_id, :viewer)

      {:ok, session: session, user_id: user_id}
    end

    test "owner can update roles", %{session: session, user_id: user_id, owner_id: owner_id} do
      # In real implementation, would pass caller info
      assert :ok = SessionManager.update_participant_role(session.id, user_id, :editor)

      {:ok, updated_session} = SessionManager.get_session(session.id)
      participant = Enum.find(updated_session.participants, fn p -> p.user_id == user_id end)
      assert participant.role == :editor
    end
  end

  describe "recording functions" do
    setup %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{record: false})
      {:ok, session: session}
    end

    test "start_recording/1", %{session: session} do
      assert {:ok, recording_id} = SessionManager.start_recording(session.id)
      assert recording_id != nil

      {:ok, updated} = SessionManager.get_session(session.id)
      assert updated.is_recording == true
    end

    test "stop_recording/1", %{session: session} do
      {:ok, _} = SessionManager.start_recording(session.id)
      assert {:ok, recording} = SessionManager.stop_recording(session.id)

      assert recording.session_id == session.id
      assert recording.events != nil

      {:ok, updated} = SessionManager.get_session(session.id)
      assert updated.is_recording == false
    end

    test "prevents double recording", %{session: session} do
      {:ok, _} = SessionManager.start_recording(session.id)
      assert {:error, :already_recording} = SessionManager.start_recording(session.id)
    end
  end

  describe "invite management" do
    setup %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{})
      {:ok, session: session}
    end

    test "generate_invite_link/3", %{session: session} do
      assert {:ok, invite_data} = SessionManager.generate_invite_link(session.id, :viewer, 3600)

      assert invite_data.token != nil
      assert invite_data.link =~ "/collaborate/join?token="
      assert invite_data.expires_at != nil
    end

    test "join_via_invite/2", %{session: session} do
      {:ok, invite_data} = SessionManager.generate_invite_link(session.id, :editor)
      user_id = "invited-user"

      assert {:ok, joined_session} = SessionManager.join_via_invite(invite_data.token, user_id)
      assert joined_session.id == session.id
      assert joined_session.participants |> Enum.any?(fn p -> p.user_id == user_id and p.role == :editor end)
    end

    test "expired invites are rejected", %{session: session} do
      {:ok, invite_data} = SessionManager.generate_invite_link(session.id, :viewer, -1)

      assert {:error, :invite_expired} = SessionManager.join_via_invite(invite_data.token, "user")
    end
  end

  describe "end_session/2" do
    setup %{project_id: project_id, owner_id: owner_id} do
      {:ok, session} = SessionManager.create_session(project_id, owner_id, %{})
      {:ok, session: session}
    end

    test "owner can end session", %{session: session, owner_id: owner_id} do
      assert :ok = SessionManager.end_session(session.id, owner_id)

      {:ok, ended} = SessionManager.get_session(session.id)
      assert ended.state == :ended
      assert ended.ended_at != nil
    end

    test "non-owner cannot end session", %{session: session} do
      assert {:error, :unauthorized} = SessionManager.end_session(session.id, "other-user")
    end
  end

  describe "list_project_sessions/1" do
    test "returns active sessions for project", %{project_id: project_id, owner_id: owner_id} do
      # Create multiple sessions
      {:ok, _} = SessionManager.create_session(project_id, owner_id, %{name: "Session 1"})
      {:ok, _} = SessionManager.create_session(project_id, owner_id, %{name: "Session 2"})
      {:ok, session3} = SessionManager.create_session(project_id, owner_id, %{name: "Session 3"})

      # End one session
      SessionManager.end_session(session3.id, owner_id)

      {:ok, sessions} = SessionManager.list_project_sessions(project_id)
      assert length(sessions) == 2
      assert Enum.all?(sessions, &(&1.state == :active))
    end
  end
end
