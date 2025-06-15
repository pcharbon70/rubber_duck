defmodule RubberDuck.Interface.CLI.SessionManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.CLI.SessionManager

  # Test configuration with temporary directory
  @test_config %{
    storage_path: System.tmp_dir!() <> "/rubber_duck_test_sessions_#{System.unique_integer()}",
    auto_save: true,
    max_history: 100
  }

  setup do
    # Clean up any existing test sessions
    if File.exists?(@test_config.storage_path) do
      File.rm_rf!(@test_config.storage_path)
    end
    
    # Initialize session manager
    {:ok, initial_state} = SessionManager.init(@test_config)
    
    on_exit(fn ->
      # Clean up test directory
      if File.exists?(@test_config.storage_path) do
        File.rm_rf!(@test_config.storage_path)
      end
    end)
    
    %{state: initial_state}
  end

  describe "init/1" do
    test "initializes with default configuration" do
      {:ok, state} = SessionManager.init()
      
      assert Map.has_key?(state, :sessions)
      assert Map.has_key?(state, :storage_path)
      assert Map.has_key?(state, :auto_save)
      assert state.sessions == %{}
    end

    test "initializes with custom configuration" do
      custom_config = %{storage_path: "/tmp/test", max_history: 50}
      {:ok, state} = SessionManager.init(custom_config)
      
      assert state.storage_path == "/tmp/test"
      assert state.max_history == 50
    end

    test "creates storage directory if it doesn't exist", %{state: state} do
      assert File.exists?(state.storage_path)
      assert File.dir?(state.storage_path)
    end
  end

  describe "create_session/3" do
    test "creates session with name", %{state: state} do
      context = %{user_id: "test_user"}
      
      {:ok, session, new_state} = SessionManager.create_session("test-session", context, state)
      
      assert session.name == "test-session"
      assert is_binary(session.id)
      assert session.id =~ "session_"
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at
      assert session.history == []
      assert session.context == context
      
      # Check that session is stored in state
      assert Map.has_key?(new_state.sessions, session.id)
      assert new_state.sessions[session.id] == session
    end

    test "creates session without name", %{state: state} do
      {:ok, session, new_state} = SessionManager.create_session(nil, %{}, state)
      
      assert session.name == nil
      assert is_binary(session.id)
      assert Map.has_key?(new_state.sessions, session.id)
    end

    test "creates session file when auto_save is enabled", %{state: state} do
      {:ok, session, _new_state} = SessionManager.create_session("file-test", %{}, state)
      
      session_file = Path.join(state.storage_path, "#{session.id}.json")
      assert File.exists?(session_file)
      
      # Verify file content
      {:ok, content} = File.read(session_file)
      {:ok, data} = Jason.decode(content)
      
      assert data["id"] == session.id
      assert data["name"] == "file-test"
    end

    test "generates unique session IDs", %{state: state} do
      {:ok, session1, state} = SessionManager.create_session("session1", %{}, state)
      {:ok, session2, _state} = SessionManager.create_session("session2", %{}, state)
      
      assert session1.id != session2.id
    end
  end

  describe "get_session/2" do
    test "retrieves existing session", %{state: state} do
      {:ok, created_session, new_state} = SessionManager.create_session("test", %{}, state)
      
      {:ok, retrieved_session} = SessionManager.get_session(created_session.id, new_state)
      
      assert retrieved_session.id == created_session.id
      assert retrieved_session.name == created_session.name
    end

    test "returns error for non-existent session", %{state: state} do
      assert {:error, :not_found} = SessionManager.get_session("non_existent", state)
    end
  end

  describe "list_sessions/1" do
    test "lists all sessions sorted by update time", %{state: state} do
      # Create multiple sessions
      {:ok, session1, state} = SessionManager.create_session("first", %{}, state)
      Process.sleep(10)  # Ensure different timestamps
      {:ok, session2, state} = SessionManager.create_session("second", %{}, state)
      
      sessions = SessionManager.list_sessions(state)
      
      assert length(sessions) == 2
      # Should be sorted by updated_at descending (newest first)
      assert List.first(sessions).name == "second"
      assert List.last(sessions).name == "first"
    end

    test "returns empty list when no sessions exist", %{state: state} do
      sessions = SessionManager.list_sessions(state)
      assert sessions == []
    end
  end

  describe "update_session/3" do
    test "updates session metadata", %{state: state} do
      {:ok, session, state} = SessionManager.create_session("test", %{}, state)
      
      updates = %{context: %{new_data: "updated"}}
      {:ok, updated_session, new_state} = SessionManager.update_session(session.id, updates, state)
      
      assert updated_session.context.new_data == "updated"
      assert DateTime.compare(updated_session.updated_at, session.updated_at) == :gt
      
      # Verify state is updated
      assert new_state.sessions[session.id].context.new_data == "updated"
    end

    test "returns error for non-existent session", %{state: state} do
      assert {:error, :not_found} = SessionManager.update_session("fake_id", %{}, state)
    end

    test "saves updated session to disk when auto_save enabled", %{state: state} do
      {:ok, session, state} = SessionManager.create_session("test", %{}, state)
      
      updates = %{context: %{disk_test: true}}
      {:ok, _updated_session, _new_state} = SessionManager.update_session(session.id, updates, state)
      
      # Verify file is updated
      session_file = Path.join(state.storage_path, "#{session.id}.json")
      {:ok, content} = File.read(session_file)
      {:ok, data} = Jason.decode(content)
      
      assert data["context"]["disk_test"] == true
    end
  end

  describe "add_to_history/3" do
    test "adds message to session history", %{state: state} do
      {:ok, session, state} = SessionManager.create_session("test", %{}, state)
      
      message = %{type: :user_input, content: "Hello AI"}
      {:ok, updated_session, new_state} = SessionManager.add_to_history(session.id, message, state)
      
      assert length(updated_session.history) == 1
      history_entry = List.first(updated_session.history)
      
      assert history_entry.type == :user_input
      assert history_entry.content == message
      assert %DateTime{} = history_entry.timestamp
      assert is_binary(history_entry.id)
      
      # Verify state is updated
      assert length(new_state.sessions[session.id].history) == 1
    end

    test "maintains history order (newest first)", %{state: state} do
      {:ok, session, state} = SessionManager.create_session("test", %{}, state)
      
      message1 = %{content: "first message"}
      {:ok, _session, state} = SessionManager.add_to_history(session.id, message1, state)
      
      Process.sleep(10)  # Ensure different timestamps
      
      message2 = %{content: "second message"}
      {:ok, updated_session, _state} = SessionManager.add_to_history(session.id, message2, state)
      
      assert length(updated_session.history) == 2
      assert List.first(updated_session.history).content.content == "second message"
      assert List.last(updated_session.history).content.content == "first message"
    end

    test "respects max_history limit", %{state: state} do
      # Create state with small history limit
      limited_state = %{state | max_history: 2}
      {:ok, session, limited_state} = SessionManager.create_session("test", %{}, limited_state)
      
      # Add more messages than the limit
      {:ok, _session, limited_state} = SessionManager.add_to_history(session.id, %{content: "msg1"}, limited_state)
      {:ok, _session, limited_state} = SessionManager.add_to_history(session.id, %{content: "msg2"}, limited_state)
      {:ok, updated_session, _limited_state} = SessionManager.add_to_history(session.id, %{content: "msg3"}, limited_state)
      
      # Should only keep the latest 2 messages
      assert length(updated_session.history) == 2
      assert List.first(updated_session.history).content.content == "msg3"
      assert List.last(updated_session.history).content.content == "msg2"
    end

    test "returns error for non-existent session", %{state: state} do
      message = %{content: "test"}
      assert {:error, :not_found} = SessionManager.add_to_history("fake_id", message, state)
    end
  end

  describe "delete_session/2" do
    test "deletes session from memory and disk", %{state: state} do
      {:ok, session, state} = SessionManager.create_session("test", %{}, state)
      session_file = Path.join(state.storage_path, "#{session.id}.json")
      
      # Verify session exists
      assert File.exists?(session_file)
      assert Map.has_key?(state.sessions, session.id)
      
      {:ok, new_state} = SessionManager.delete_session(session.id, state)
      
      # Verify session is removed
      assert not Map.has_key?(new_state.sessions, session.id)
      assert not File.exists?(session_file)
    end

    test "returns error for non-existent session", %{state: state} do
      assert {:error, :not_found} = SessionManager.delete_session("fake_id", state)
    end
  end

  describe "save_session/2" do
    test "saves session to disk", %{state: state} do
      {:ok, session, _state} = SessionManager.create_session("test", %{manual_save: true}, state)
      
      # Modify session without auto-save by creating new state
      no_auto_save_state = %{state | auto_save: false}
      updated_session = %{session | context: %{updated: true}}
      
      # Manually save
      :ok = SessionManager.save_session(updated_session, no_auto_save_state)
      
      # Verify file content
      session_file = Path.join(state.storage_path, "#{session.id}.json")
      {:ok, content} = File.read(session_file)
      {:ok, data} = Jason.decode(content)
      
      assert data["context"]["updated"] == true
    end
  end

  describe "get_session_stats/1" do
    test "returns statistics about sessions", %{state: state} do
      # Create some test sessions
      {:ok, session1, state} = SessionManager.create_session("active1", %{}, state)
      {:ok, session2, state} = SessionManager.create_session("active2", %{}, state)
      
      # Add history to one session
      {:ok, _session, state} = SessionManager.add_to_history(session1.id, %{content: "test"}, state)
      
      stats = SessionManager.get_session_stats(state)
      
      assert stats.total_sessions == 2
      assert stats.total_history_entries == 1
      assert stats.storage_path == state.storage_path
      assert %{} = stats.oldest_session
      assert %{} = stats.newest_session
    end

    test "handles empty session list", %{state: state} do
      stats = SessionManager.get_session_stats(state)
      
      assert stats.total_sessions == 0
      assert stats.total_history_entries == 0
      assert stats.oldest_session == nil
      assert stats.newest_session == nil
    end
  end

  describe "session persistence" do
    test "loads existing sessions from disk" do
      # Create a session file manually
      session_data = %{
        "id" => "test_session_123",
        "name" => "loaded_session",
        "created_at" => "2024-01-01T12:00:00Z",
        "updated_at" => "2024-01-01T12:30:00Z",
        "metadata" => %{},
        "history" => [],
        "context" => %{"loaded" => true}
      }
      
      File.mkdir_p!(@test_config.storage_path)
      session_file = Path.join(@test_config.storage_path, "test_session_123.json")
      File.write!(session_file, Jason.encode!(session_data))
      
      # Initialize session manager (should load existing sessions)
      {:ok, state} = SessionManager.init(@test_config)
      
      # Verify session was loaded
      assert Map.has_key?(state.sessions, "test_session_123")
      loaded_session = state.sessions["test_session_123"]
      
      assert loaded_session.name == "loaded_session"
      assert loaded_session.context["loaded"] == true
    end

    test "handles corrupted session files gracefully" do
      # Create a corrupted session file
      File.mkdir_p!(@test_config.storage_path)
      corrupted_file = Path.join(@test_config.storage_path, "corrupted.json")
      File.write!(corrupted_file, "invalid json content")
      
      # Should not crash and should skip the corrupted file
      {:ok, state} = SessionManager.init(@test_config)
      
      # Should initialize successfully despite corrupted file
      assert state.sessions == %{}
    end
  end

  describe "GenServer integration" do
    test "can be started as a GenServer" do
      {:ok, pid} = SessionManager.start_link(@test_config)
      
      # Test basic operations through GenServer
      {:ok, session, _state} = SessionManager.create_session("genserver_test", %{}, pid)
      
      {:ok, retrieved} = SessionManager.get_session(session.id, pid)
      assert retrieved.name == "genserver_test"
      
      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "concurrent access" do
    test "handles concurrent session creation" do
      # Create multiple sessions concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          SessionManager.create_session("concurrent_#{i}", %{index: i}, @test_config)
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed and have unique IDs
      session_ids = results
      |> Enum.map(fn {:ok, session, _state} -> session.id end)
      |> Enum.uniq()
      
      assert length(session_ids) == 5
    end
  end
end