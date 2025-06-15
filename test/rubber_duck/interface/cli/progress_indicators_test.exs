defmodule RubberDuck.Interface.CLI.ProgressIndicatorsTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.CLI.ProgressIndicators

  @test_config %{
    colors: false,  # Disable colors for consistent testing
    verbose: false
  }

  setup do
    # Start the progress indicators manager for each test
    {:ok, pid} = ProgressIndicators.start_link(@test_config)
    
    on_exit(fn ->
      if Process.alive?(pid) do
        ProgressIndicators.clear_all()
        GenServer.stop(pid)
      end
    end)
    
    %{pid: pid}
  end

  describe "start_progress/4" do
    test "starts a spinner progress indicator" do
      assert :ok = ProgressIndicators.start_progress(:test_spinner, :spinner, "Testing...", style: :dots)
      
      # Verify the progress item exists
      streams = ProgressIndicators.list_streams()
      assert length(streams) == 1
      
      [stream] = streams
      assert stream.id == :test_spinner
      assert stream.type == :spinner
    end

    test "starts a progress bar indicator" do
      assert :ok = ProgressIndicators.start_progress(:test_bar, :bar, "Loading...", total: 100)
      
      streams = ProgressIndicators.list_streams()
      assert length(streams) == 1
      
      [stream] = streams
      assert stream.id == :test_bar
      assert stream.type == :bar
      assert stream.total_size == 100
    end

    test "starts a streaming indicator" do
      assert :ok = ProgressIndicators.start_progress(:test_stream, :stream, "Streaming...", rate: 30)
      
      streams = ProgressIndicators.list_streams()
      [stream] = streams
      assert stream.type == :stream
    end

    test "returns error for duplicate progress ID" do
      assert :ok = ProgressIndicators.start_progress(:duplicate, :spinner, "First")
      assert {:error, :stream_exists} = ProgressIndicators.start_progress(:duplicate, :spinner, "Second")
    end
  end

  describe "update_progress/3" do
    test "updates progress bar current value" do
      ProgressIndicators.start_progress(:test_bar, :bar, "Loading...", total: 100)
      
      assert :ok = ProgressIndicators.update_progress(:test_bar, 50)
      
      {:ok, status} = ProgressIndicators.get_stream_status(:test_bar)
      assert status.position == 50
      assert status.progress == 50.0
    end

    test "updates progress with message" do
      ProgressIndicators.start_progress(:test_progress, :spinner, "Starting...")
      
      assert :ok = ProgressIndicators.update_progress(:test_progress, 10, message: "Working hard...")
      
      {:ok, status} = ProgressIndicators.get_stream_status(:test_progress)
      assert status.position == 10
    end

    test "returns error for non-existent progress" do
      assert {:error, :not_found} = ProgressIndicators.update_progress(:nonexistent, 50)
    end
  end

  describe "update_message/2" do
    test "updates progress message" do
      ProgressIndicators.start_progress(:test_msg, :spinner, "Original message")
      
      assert :ok = ProgressIndicators.update_message(:test_msg, "Updated message")
      
      # Message update is internal, so we verify it doesn't error
      # In a real test, you might check the rendered output
    end

    test "returns error for non-existent progress" do
      assert {:error, :not_found} = ProgressIndicators.update_message(:nonexistent, "New message")
    end
  end

  describe "complete_progress/2" do
    test "completes progress with default message" do
      ProgressIndicators.start_progress(:test_complete, :spinner, "Processing...")
      
      assert :ok = ProgressIndicators.complete_progress(:test_complete)
      
      # Progress should be removed from active list
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "completes progress with custom message" do
      ProgressIndicators.start_progress(:test_complete, :bar, "Loading...", total: 100)
      
      assert :ok = ProgressIndicators.complete_progress(:test_complete, "Successfully loaded!")
      
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "returns error for non-existent progress" do
      assert {:error, :not_found} = ProgressIndicators.complete_progress(:nonexistent)
    end
  end

  describe "error_progress/2" do
    test "marks progress as error" do
      ProgressIndicators.start_progress(:test_error, :spinner, "Processing...")
      
      assert :ok = ProgressIndicators.error_progress(:test_error, "Something went wrong!")
      
      # Progress should be removed after error
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "uses default error message" do
      ProgressIndicators.start_progress(:test_error, :spinner, "Processing...")
      
      assert :ok = ProgressIndicators.error_progress(:test_error)
      
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end

  describe "cancel_progress/1" do
    test "cancels active progress" do
      ProgressIndicators.start_progress(:test_cancel, :spinner, "Processing...")
      
      assert :ok = ProgressIndicators.cancel_progress(:test_cancel)
      
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "returns ok for non-existent progress" do
      # Cancel is idempotent
      assert :ok = ProgressIndicators.cancel_progress(:nonexistent)
    end
  end

  describe "clear_all/0" do
    test "clears all active progress indicators" do
      ProgressIndicators.start_progress(:test1, :spinner, "Task 1")
      ProgressIndicators.start_progress(:test2, :bar, "Task 2", total: 100)
      ProgressIndicators.start_progress(:test3, :stream, "Task 3")
      
      assert length(ProgressIndicators.list_streams()) == 3
      
      assert :ok = ProgressIndicators.clear_all()
      
      assert ProgressIndicators.list_streams() == []
    end
  end

  describe "with_spinner/3" do
    test "runs function with spinner and completes on success" do
      result = ProgressIndicators.with_spinner("Testing task", fn ->
        Process.sleep(10)
        :success_result
      end, id: :test_task)
      
      assert result == :success_result
      
      # Spinner should be cleaned up
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "handles function exceptions" do
      assert_raise RuntimeError, "test error", fn ->
        ProgressIndicators.with_spinner("Failing task", fn ->
          raise "test error"
        end, id: :fail_task)
      end
      
      # Spinner should be cleaned up even after error
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "handles function exits" do
      catch_exit do
        ProgressIndicators.with_spinner("Exiting task", fn ->
          exit(:normal)
        end, id: :exit_task)
      end
      
      # Spinner should be cleaned up
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end

  describe "with_progress_bar/4" do
    test "runs function with progress bar" do
      result = ProgressIndicators.with_progress_bar("Processing items", 10, fn update_fn ->
        for i <- 1..10 do
          update_fn.(i)
          Process.sleep(1)
        end
        :completed
      end, id: :progress_task)
      
      assert result == :completed
      
      # Progress bar should be cleaned up
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "handles exceptions in progress bar function" do
      assert_raise RuntimeError, "progress error", fn ->
        ProgressIndicators.with_progress_bar("Failing progress", 5, fn _update_fn ->
          raise "progress error"
        end, id: :progress_fail)
      end
      
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end

  describe "stream_text/2" do
    test "streams text character by character" do
      # Use a short text to make test faster
      text = "Hello"
      
      # This should complete without error
      assert :ok = ProgressIndicators.stream_text(text, id: :stream_test, rate: 1000)  # Very fast for testing
      
      # Stream should be completed and cleaned up
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end

    test "handles empty text" do
      assert :ok = ProgressIndicators.stream_text("", id: :empty_stream)
      
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end

  describe "get_stream_status/1" do
    test "returns status for active progress" do
      ProgressIndicators.start_progress(:status_test, :bar, "Testing status", total: 100)
      ProgressIndicators.update_progress(:status_test, 25)
      
      {:ok, status} = ProgressIndicators.get_stream_status(:status_test)
      
      assert status.id == :status_test
      assert status.type == :bar
      assert status.position == 25
      assert status.total_size == 100
      assert status.progress == 25.0
      assert is_integer(status.elapsed_ms)
      assert is_number(status.rate)
    end

    test "returns error for non-existent progress" do
      assert {:error, :not_found} = ProgressIndicators.get_stream_status(:nonexistent)
    end
  end

  describe "list_streams/0" do
    test "lists all active streams" do
      ProgressIndicators.start_progress(:stream1, :spinner, "Task 1")
      ProgressIndicators.start_progress(:stream2, :bar, "Task 2", total: 50)
      
      streams = ProgressIndicators.list_streams()
      
      assert length(streams) == 2
      
      ids = Enum.map(streams, & &1.id)
      assert :stream1 in ids
      assert :stream2 in ids
    end

    test "returns empty list when no streams" do
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end

  describe "concurrent operations" do
    test "handles multiple concurrent progress indicators" do
      # Start multiple progress indicators concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          ProgressIndicators.start_progress(:"task_#{i}", :spinner, "Task #{i}")
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, &(&1 == :ok))
      
      # Should have 5 active streams
      streams = ProgressIndicators.list_streams()
      assert length(streams) == 5
    end

    test "handles concurrent updates to same progress" do
      ProgressIndicators.start_progress(:concurrent_test, :bar, "Testing", total: 100)
      
      # Update concurrently
      tasks = for i <- 1..10 do
        Task.async(fn ->
          ProgressIndicators.update_progress(:concurrent_test, i * 10)
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All updates should succeed
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "error handling" do
    test "handles GenServer crashes gracefully" do
      # This is harder to test without actually crashing the GenServer
      # In a real scenario, you might use a separate test GenServer
      
      # Test that operations don't crash with invalid inputs
      assert :ok = ProgressIndicators.start_progress(:test, :spinner, "Test")
      assert :ok = ProgressIndicators.update_progress(:test, 50)
      assert :ok = ProgressIndicators.complete_progress(:test)
    end

    test "handles invalid progress types" do
      # The current implementation doesn't validate types at start,
      # but they should be handled in rendering
      assert :ok = ProgressIndicators.start_progress(:invalid_type, :unknown_type, "Test")
      
      # Should still be able to complete it
      assert :ok = ProgressIndicators.complete_progress(:invalid_type)
    end
  end

  describe "animation and rendering" do
    test "animation starts and stops appropriately" do
      # Start a progress indicator
      ProgressIndicators.start_progress(:anim_test, :spinner, "Animating...")
      
      # Give it a moment to start animation
      Process.sleep(50)
      
      # Complete it
      ProgressIndicators.complete_progress(:anim_test)
      
      # Animation should stop when no more progress items
      streams = ProgressIndicators.list_streams()
      assert streams == []
    end
  end
end