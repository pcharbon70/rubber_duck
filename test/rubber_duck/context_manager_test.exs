defmodule RubberDuck.ContextManagerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.ContextManager

  setup do
    # Stop the application to control GenServer lifecycle in tests
    Application.stop(:rubber_duck)
    on_exit(fn -> Application.start(:rubber_duck) end)
    :ok
  end

  describe "start_link/1" do
    test "starts the ContextManager GenServer" do
      assert {:ok, pid} = ContextManager.start_link([])
      assert Process.alive?(pid)
    end

    test "registers the process with its module name" do
      assert {:ok, _pid} = ContextManager.start_link([])
      assert Process.whereis(ContextManager) != nil
    end

    test "accepts initial state options" do
      initial_state = %{session_id: "test-123"}
      assert {:ok, pid} = ContextManager.start_link(initial_state: initial_state)
      assert Process.alive?(pid)
    end
  end

  describe "session management" do
    setup do
      {:ok, pid} = ContextManager.start_link([])
      %{pid: pid}
    end

    test "creates a new session with unique ID", %{pid: pid} do
      assert {:ok, session_id} = ContextManager.create_session(pid)
      assert is_binary(session_id)
      assert String.length(session_id) > 0
    end

    test "retrieves session context", %{pid: pid} do
      {:ok, session_id} = ContextManager.create_session(pid)
      
      assert {:ok, context} = ContextManager.get_context(pid, session_id)
      assert %{
        session_id: ^session_id,
        messages: [],
        metadata: %{}
      } = context
    end

    test "returns error for non-existent session", %{pid: pid} do
      assert {:error, :session_not_found} = ContextManager.get_context(pid, "non-existent")
    end

    test "adds messages to session context", %{pid: pid} do
      {:ok, session_id} = ContextManager.create_session(pid)
      
      message = %{role: "user", content: "Hello"}
      assert :ok = ContextManager.add_message(pid, session_id, message)
      
      {:ok, context} = ContextManager.get_context(pid, session_id)
      assert [^message] = context.messages
    end

    test "updates session metadata", %{pid: pid} do
      {:ok, session_id} = ContextManager.create_session(pid)
      
      metadata = %{model: "gpt-4", temperature: 0.7}
      assert :ok = ContextManager.update_metadata(pid, session_id, metadata)
      
      {:ok, context} = ContextManager.get_context(pid, session_id)
      assert context.metadata == metadata
    end

    test "clears session context", %{pid: pid} do
      {:ok, session_id} = ContextManager.create_session(pid)
      ContextManager.add_message(pid, session_id, %{role: "user", content: "Test"})
      
      assert :ok = ContextManager.clear_session(pid, session_id)
      
      {:ok, context} = ContextManager.get_context(pid, session_id)
      assert context.messages == []
    end

    test "deletes a session", %{pid: pid} do
      {:ok, session_id} = ContextManager.create_session(pid)
      
      assert :ok = ContextManager.delete_session(pid, session_id)
      assert {:error, :session_not_found} = ContextManager.get_context(pid, session_id)
    end

    test "lists all active sessions", %{pid: pid} do
      {:ok, session1} = ContextManager.create_session(pid)
      {:ok, session2} = ContextManager.create_session(pid)
      
      sessions = ContextManager.list_sessions(pid)
      assert length(sessions) == 2
      assert session1 in sessions
      assert session2 in sessions
    end
  end

  describe "process registration" do
    setup do
      # Ensure application is started
      {:ok, _} = Application.ensure_all_started(:rubber_duck)
      on_exit(fn -> Application.stop(:rubber_duck) end)
      :ok
    end

    test "registers with Registry on start" do
      {:ok, pid} = ContextManager.start_link(name: :test_context_manager)
      
      # Should be findable via Registry
      assert [{^pid, _}] = Registry.lookup(RubberDuck.Registry, :test_context_manager)
      assert Process.alive?(pid)
      
      # Stop the process
      GenServer.stop(pid)
    end

    test "supports multiple named instances" do
      {:ok, pid1} = ContextManager.start_link(name: :context1)
      {:ok, pid2} = ContextManager.start_link(name: :context2)
      
      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      
      # Stop the processes
      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  describe "graceful shutdown" do
    test "handles normal shutdown gracefully" do
      {:ok, pid} = ContextManager.start_link([])
      {:ok, session_id} = ContextManager.create_session(pid)
      
      # Add some state
      ContextManager.add_message(pid, session_id, %{role: "user", content: "Test"})
      
      # Shutdown should complete without error
      assert :ok = GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end

    test "handles terminate callback" do
      # Trap exits to prevent test process from dying
      Process.flag(:trap_exit, true)
      
      {:ok, pid} = ContextManager.start_link([])
      ref = Process.monitor(pid)
      
      # Force abnormal termination
      Process.exit(pid, :kill)
      
      # Wait for the process to terminate
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1000
      refute Process.alive?(pid)
      
      # Reset trap_exit
      Process.flag(:trap_exit, false)
    end
  end

  describe "monitoring and health checks" do
    setup do
      {:ok, pid} = ContextManager.start_link([])
      %{pid: pid}
    end

    test "responds to health check", %{pid: pid} do
      assert :ok = ContextManager.health_check(pid)
    end

    test "returns process info", %{pid: pid} do
      info = ContextManager.get_info(pid)
      
      assert %{
        status: :running,
        session_count: 0,
        memory: _,
        uptime: _
      } = info
    end

    test "tracks session count in info", %{pid: pid} do
      ContextManager.create_session(pid)
      ContextManager.create_session(pid)
      
      info = ContextManager.get_info(pid)
      assert info.session_count == 2
    end
  end
end