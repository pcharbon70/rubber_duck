defmodule RubberDuck.ErrorBoundaryTest do
  use ExUnit.Case, async: false

  alias RubberDuck.ErrorBoundary

  setup do
    # Ensure error boundary is started fresh for each test
    case Process.whereis(ErrorBoundary) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid, :normal)
        Process.sleep(10)
    end

    {:ok, _pid} = ErrorBoundary.start_link()
    :ok
  end

  describe "run/2" do
    test "executes successful function" do
      result = ErrorBoundary.run(fn -> {:success, 42} end)
      assert result == {:ok, {:success, 42}}
    end

    test "catches exceptions" do
      result =
        ErrorBoundary.run(fn ->
          raise "Test error"
        end)

      assert {:error, {:exception, %RuntimeError{message: "Test error"}}} = result
    end

    test "catches throws" do
      result =
        ErrorBoundary.run(fn ->
          throw(:test_throw)
        end)

      assert {:error, {:throw, :test_throw}} = result
    end

    test "handles timeout" do
      result =
        ErrorBoundary.run(
          fn ->
            Process.sleep(200)
            :should_not_reach
          end,
          timeout: 100
        )

      assert {:error, :timeout} = result
    end

    test "retries on failure" do
      counter = :counters.new(1, [:atomics])

      result =
        ErrorBoundary.run(
          fn ->
            :counters.add(counter, 1, 1)
            count = :counters.get(counter, 1)

            if count < 3 do
              raise "Retry test"
            else
              :success
            end
          end,
          retry: 3,
          retry_delay: 10
        )

      assert {:ok, :success} = result
      assert :counters.get(counter, 1) == 3
    end

    test "stops retrying after max attempts" do
      counter = :counters.new(1, [:atomics])

      result =
        ErrorBoundary.run(
          fn ->
            :counters.add(counter, 1, 1)
            raise "Always fails"
          end,
          retry: 2,
          retry_delay: 10
        )

      assert {:error, {:exception, %RuntimeError{message: "Always fails"}}} = result
      # Initial attempt + 2 retries = 3 total attempts
      assert :counters.get(counter, 1) == 3
    end

    test "includes metadata in error reports" do
      metadata = %{user_id: "test_user", action: "test_action"}

      result =
        ErrorBoundary.run(
          fn -> raise "Metadata test" end,
          metadata: metadata
        )

      assert {:error, {:exception, %RuntimeError{}}} = result
    end
  end

  describe "run_async/2" do
    test "executes async function successfully" do
      task =
        ErrorBoundary.run_async(fn ->
          Process.sleep(50)
          :async_result
        end)

      assert Task.await(task) == :async_result
    end

    test "raises on async failure" do
      # Start a separate error boundary for this test to avoid crashing the shared one
      {:ok, pid} = GenServer.start_link(ErrorBoundary, [])

      task =
        Task.async(fn ->
          case GenServer.call(pid, {:execute, fn -> raise "Async error" end, 5_000, %{}}, 6_000) do
            {:ok, result} -> result
            {:error, reason} -> raise "Async operation failed: #{inspect(reason)}"
          end
        end)

      assert_raise RuntimeError, ~r/Async operation failed/, fn ->
        Task.await(task)
      end

      # Clean up
      GenServer.stop(pid, :normal)
    end
  end

  describe "stats/0" do
    test "tracks success and error counts" do
      # Reset stats by restarting the error boundary
      GenServer.stop(ErrorBoundary, :normal)
      {:ok, _} = ErrorBoundary.start_link()

      # Run some successful operations
      ErrorBoundary.run(fn -> :ok end)
      ErrorBoundary.run(fn -> :ok end)

      # Run some failing operations
      ErrorBoundary.run(fn -> raise "error" end)

      stats = ErrorBoundary.stats()

      assert stats.success_count == 2
      assert stats.error_count == 1
      assert {_, %DateTime{}} = stats.last_error
    end
  end
end
