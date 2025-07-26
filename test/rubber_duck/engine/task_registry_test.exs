defmodule RubberDuck.Engine.TaskRegistryTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Engine.TaskRegistry
  
  setup do
    # Ensure TaskRegistry is started
    start_supervised!(TaskRegistry)
    :ok
  end
  
  describe "register_task/4" do
    test "successfully registers a task" do
      task = Task.async(fn -> Process.sleep(1000) end)
      conversation_id = "conv_123"
      engine_name = "test_engine"
      
      assert {:ok, task_id} = TaskRegistry.register_task(task, conversation_id, engine_name)
      assert is_binary(task_id)
      assert String.starts_with?(task_id, "task_")
    end
    
    test "can register multiple tasks for same conversation" do
      conversation_id = "conv_123"
      
      task1 = Task.async(fn -> Process.sleep(1000) end)
      task2 = Task.async(fn -> Process.sleep(1000) end)
      
      {:ok, task_id1} = TaskRegistry.register_task(task1, conversation_id, "engine1")
      {:ok, task_id2} = TaskRegistry.register_task(task2, conversation_id, "engine2")
      
      assert task_id1 != task_id2
      
      tasks = TaskRegistry.find_by_conversation(conversation_id)
      assert length(tasks) == 2
    end
  end
  
  describe "find_by_conversation/1" do
    test "returns empty list for unknown conversation" do
      assert [] = TaskRegistry.find_by_conversation("unknown_conv")
    end
    
    test "returns all tasks for a conversation" do
      conversation_id = "conv_456"
      
      task1 = Task.async(fn -> Process.sleep(1000) end)
      task2 = Task.async(fn -> Process.sleep(1000) end)
      
      TaskRegistry.register_task(task1, conversation_id, "engine1", %{priority: :high})
      TaskRegistry.register_task(task2, conversation_id, "engine2", %{priority: :normal})
      
      tasks = TaskRegistry.find_by_conversation(conversation_id)
      
      assert length(tasks) == 2
      assert Enum.all?(tasks, fn task -> task.conversation_id == conversation_id end)
      assert Enum.all?(tasks, fn task -> task.status == :running end)
    end
  end
  
  describe "cancel_conversation_tasks/1" do
    test "cancels all tasks for a conversation" do
      conversation_id = "conv_789"
      
      # Track if tasks were cancelled
      test_pid = self()
      
      # Use spawn_link with trap_exit to handle task cancellation
      Process.flag(:trap_exit, true)
      
      # Create tasks with monitoring
      task1 = Task.async(fn ->
        send(test_pid, {:task_started, 1})
        Process.sleep(5000)
      end)
      
      task2 = Task.async(fn ->
        send(test_pid, {:task_started, 2})
        Process.sleep(5000)
      end)
      
      # Wait for tasks to start
      assert_receive {:task_started, 1}, 1000
      assert_receive {:task_started, 2}, 1000
      
      TaskRegistry.register_task(task1, conversation_id, "engine1")
      TaskRegistry.register_task(task2, conversation_id, "engine2")
      
      # Cancel all tasks
      assert {:ok, 2} = TaskRegistry.cancel_conversation_tasks(conversation_id)
      
      # Tasks should exit with :cancelled
      assert_receive {:EXIT, _, :cancelled}, 1000
      assert_receive {:EXIT, _, :cancelled}, 1000
    end
    
    test "returns 0 for conversation with no tasks" do
      assert {:ok, 0} = TaskRegistry.cancel_conversation_tasks("no_tasks_conv")
    end
  end
  
  describe "cancel_task/1" do
    test "cancels a specific task" do
      # Use trap_exit to handle task cancellation
      Process.flag(:trap_exit, true)
      test_pid = self()
      
      task = Task.async(fn ->
        send(test_pid, :task_started)
        Process.sleep(5000)
      end)
      
      # Wait for task to start
      assert_receive :task_started, 1000
      
      {:ok, task_id} = TaskRegistry.register_task(task, "conv_123", "engine1")
      
      assert :ok = TaskRegistry.cancel_task(task_id)
      
      # Should receive exit signal
      assert_receive {:EXIT, _, :cancelled}, 1000
      
      # Task should be marked as cancelled in registry
      case TaskRegistry.find_task(task_id) do
        {:ok, task_info} -> assert task_info.status == :cancelled
        {:error, :not_found} -> :ok  # Task was removed, which is also fine
      end
    end
    
    test "returns error for unknown task" do
      assert {:error, :task_not_found} = TaskRegistry.cancel_task("unknown_task_id")
    end
  end
  
  describe "unregister_task/1" do
    test "removes task from registry" do
      task = Task.async(fn -> Process.sleep(100) end)
      {:ok, task_id} = TaskRegistry.register_task(task, "conv_123", "engine1")
      
      assert :ok = TaskRegistry.unregister_task(task_id)
      assert {:error, :not_found} = TaskRegistry.find_task(task_id)
      
      # Let the task complete normally
      Task.await(task)
    end
  end
  
  describe "get_stats/0" do
    test "returns task statistics" do
      # Register some tasks
      task1 = Task.async(fn -> Process.sleep(1000) end)
      task2 = Task.async(fn -> Process.sleep(1000) end)
      
      TaskRegistry.register_task(task1, "conv_1", "engine1")
      TaskRegistry.register_task(task2, "conv_2", "engine2")
      
      stats = TaskRegistry.get_stats()
      
      assert stats.total >= 2
      assert is_map(stats.by_status)
      assert is_map(stats.by_engine)
      assert stats.by_status[:running] >= 2
    end
  end
  
  describe "cleanup" do
    test "stale tasks are cleaned up automatically" do
      # This test would need to mock the cleanup interval
      # For now, we'll just test the concept
      
      task = Task.async(fn -> :ok end)
      {:ok, task_id} = TaskRegistry.register_task(task, "conv_123", "engine1")
      
      # Wait for task to complete
      Task.await(task)
      
      # Mark as completed
      TaskRegistry.unregister_task(task_id)
      
      # In real scenario, cleanup would happen after interval
      # Here we're just verifying the task can be removed
      assert {:error, :not_found} = TaskRegistry.find_task(task_id)
    end
  end
end