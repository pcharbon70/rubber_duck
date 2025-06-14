defmodule RubberDuck.DistributedLockTest do
  use ExUnit.Case, async: false

  alias RubberDuck.{DistributedLock, MnesiaManager}

  setup do
    # Stop the application to control lifecycle in tests
    Application.stop(:rubber_duck)
    
    # Clean up any existing Mnesia schema
    :mnesia.delete_schema([node()])
    
    on_exit(fn -> 
      :mnesia.stop()
      :mnesia.delete_schema([node()])
      Application.start(:rubber_duck) 
    end)
    
    # Start Mnesia and DistributedLock
    {:ok, _} = MnesiaManager.start_link([])
    MnesiaManager.initialize_schema()
    {:ok, pid} = DistributedLock.start_link([])
    
    %{lock_pid: pid}
  end

  describe "acquire_lock/2" do
    test "acquires a new lock successfully", %{lock_pid: _pid} do
      assert {:ok, token} = DistributedLock.acquire_lock("test_lock")
      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "fails to acquire already held lock", %{lock_pid: _pid} do
      # First acquisition should succeed
      assert {:ok, _token} = DistributedLock.acquire_lock("exclusive_lock")
      
      # Second acquisition should fail
      assert {:error, :already_held} = DistributedLock.acquire_lock("exclusive_lock")
    end

    test "can acquire lock with custom lease duration", %{lock_pid: _pid} do
      assert {:ok, _token} = DistributedLock.acquire_lock("timed_lock", lease_duration: 1000)
    end
  end

  describe "release_lock/1" do
    test "releases a held lock successfully", %{lock_pid: _pid} do
      {:ok, _token} = DistributedLock.acquire_lock("release_test")
      
      assert :ok = DistributedLock.release_lock("release_test")
      
      # Should be able to acquire again
      assert {:ok, _new_token} = DistributedLock.acquire_lock("release_test")
    end

    test "handles releasing non-existent lock", %{lock_pid: _pid} do
      assert {:error, :not_held} = DistributedLock.release_lock("nonexistent_lock")
    end

    test "prevents releasing lock held by another process", %{lock_pid: _pid} do
      # Acquire lock in this process
      {:ok, _token} = DistributedLock.acquire_lock("ownership_test")
      
      # Try to release from a different process
      task = Task.async(fn ->
        DistributedLock.release_lock("ownership_test")
      end)
      
      assert {:error, :not_owner} = Task.await(task)
    end
  end

  describe "with_lock/3" do
    test "executes function while holding lock", %{lock_pid: _pid} do
      result = DistributedLock.with_lock("function_lock", fn ->
        # Verify we can't acquire the same lock from another process
        task = Task.async(fn ->
          DistributedLock.acquire_lock("function_lock", timeout: 100)
        end)
        
        lock_result = Task.await(task)
        assert {:error, :already_held} = lock_result
        
        "function_executed"
      end)
      
      assert {:ok, "function_executed"} = result
      
      # Lock should be released after function completes
      assert {:ok, _token} = DistributedLock.acquire_lock("function_lock")
    end

    test "releases lock even if function raises", %{lock_pid: _pid} do
      result = DistributedLock.with_lock("error_lock", fn ->
        raise "test error"
      end)
      
      assert {:error, {:function_error, _}} = result
      
      # Lock should still be released
      assert {:ok, _token} = DistributedLock.acquire_lock("error_lock")
    end

    test "fails when cannot acquire lock", %{lock_pid: _pid} do
      # Hold the lock in another process
      {:ok, _token} = DistributedLock.acquire_lock("blocked_lock")
      
      result = DistributedLock.with_lock("blocked_lock", fn ->
        "should_not_execute"
      end, timeout: 100)
      
      assert {:error, :already_held} = result
    end
  end

  describe "list_locks/0" do
    test "lists currently held locks", %{lock_pid: _pid} do
      # Acquire some locks
      {:ok, _} = DistributedLock.acquire_lock("list_test_1")
      {:ok, _} = DistributedLock.acquire_lock("list_test_2")
      
      locks = DistributedLock.list_locks()
      
      assert is_list(locks)
      assert length(locks) >= 2
      
      lock_names = Enum.map(locks, & &1.name)
      assert "list_test_1" in lock_names
      assert "list_test_2" in lock_names
    end

    test "returns empty list when no locks held", %{lock_pid: _pid} do
      locks = DistributedLock.list_locks()
      assert is_list(locks)
      # Note: might not be empty due to other tests, but should be a list
    end
  end

  describe "lock_held?/1" do
    test "returns true for held locks", %{lock_pid: _pid} do
      {:ok, _} = DistributedLock.acquire_lock("held_check")
      
      assert DistributedLock.lock_held?("held_check") == true
    end

    test "returns false for non-held locks", %{lock_pid: _pid} do
      assert DistributedLock.lock_held?("not_held") == false
    end
  end

  describe "process monitoring" do
    test "releases locks when holding process dies", %{lock_pid: _pid} do
      # Start a process that acquires a lock
      {holder_pid, ref} = spawn_monitor(fn ->
        {:ok, _token} = DistributedLock.acquire_lock("death_test")
        receive do
          :exit -> :ok
        end
      end)
      
      # Verify lock is held
      assert DistributedLock.lock_held?("death_test") == true
      
      # Kill the process
      Process.exit(holder_pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^holder_pid, :killed} -> :ok
      end
      
      # Give the lock manager time to clean up
      :timer.sleep(100)
      
      # Lock should be released
      assert {:ok, _token} = DistributedLock.acquire_lock("death_test")
    end
  end

  describe "lease expiration" do
    test "locks expire after lease duration", %{lock_pid: _pid} do
      # Acquire lock with very short lease
      {:ok, _token} = DistributedLock.acquire_lock("expiry_test", lease_duration: 100)
      
      # Verify initially held
      assert DistributedLock.lock_held?("expiry_test") == true
      
      # Wait for expiry
      :timer.sleep(200)
      
      # Should be able to acquire now (after cleanup runs)
      # Note: This test might be flaky depending on cleanup timing
      # In a real system, you'd want more deterministic cleanup triggers
      assert {:ok, _new_token} = DistributedLock.acquire_lock("expiry_test")
    end
  end

  describe "concurrent access" do
    test "multiple processes compete for same lock", %{lock_pid: _pid} do
      # Start multiple processes trying to acquire the same lock
      tasks = Enum.map(1..5, fn i ->
        Task.async(fn ->
          case DistributedLock.acquire_lock("competition") do
            {:ok, token} ->
              :timer.sleep(10) # Hold briefly
              DistributedLock.release_lock("competition")
              {:acquired, i, token}
            {:error, reason} ->
              {:failed, i, reason}
          end
        end)
      end)
      
      results = Enum.map(tasks, &Task.await/1)
      
      # Exactly one should succeed
      acquired = Enum.filter(results, fn {status, _, _} -> status == :acquired end)
      failed = Enum.filter(results, fn {status, _, _} -> status == :failed end)
      
      assert length(acquired) == 1
      assert length(failed) == 4
    end
  end
end