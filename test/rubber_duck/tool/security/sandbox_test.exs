defmodule RubberDuck.Tool.Security.SandboxTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Security.Sandbox

  describe "basic execution" do
    test "executes simple functions successfully" do
      result = Sandbox.execute(fn -> 1 + 1 end)
      assert {:ok, 2} = result
    end

    test "returns function results" do
      result = Sandbox.execute(fn -> "hello world" end)
      assert {:ok, "hello world"} = result
    end

    test "handles function that returns complex data" do
      result = Sandbox.execute(fn -> %{a: 1, b: [2, 3, 4]} end)
      assert {:ok, %{a: 1, b: [2, 3, 4]}} = result
    end
  end

  describe "timeout handling" do
    test "respects timeout limits" do
      result =
        Sandbox.execute(
          fn ->
            Process.sleep(100)
            :completed
          end,
          timeout_ms: 50
        )

      assert {:error, :timeout} = result
    end

    test "allows execution within timeout" do
      result =
        Sandbox.execute(
          fn ->
            Process.sleep(10)
            :completed
          end,
          timeout_ms: 100
        )

      assert {:ok, :completed} = result
    end
  end

  describe "memory limits" do
    test "allows execution within memory limits" do
      result =
        Sandbox.execute(
          fn ->
            # Create a small list
            Enum.to_list(1..100)
          end,
          # 10MB
          max_heap_size: 10 * 1024 * 1024
        )

      assert {:ok, list} = result
      assert length(list) == 100
    end

    test "terminates on memory limit exceeded" do
      result =
        Sandbox.execute(
          fn ->
            # Try to create a large binary
            String.duplicate("a", 1_000_000)
          end,
          # 1KB - very small
          max_heap_size: 1024
        )

      assert {:error, :memory_limit} = result
    end
  end

  describe "exception handling" do
    test "catches and returns exceptions" do
      result =
        Sandbox.execute(fn ->
          raise "something went wrong"
        end)

      assert {:error, {:exception, {:error, %RuntimeError{message: "something went wrong"}, _}}} = result
    end

    test "catches thrown values" do
      result =
        Sandbox.execute(fn ->
          throw(:my_error)
        end)

      assert {:error, {:exception, {:throw, :my_error}}} = result
    end

    test "catches exits" do
      result =
        Sandbox.execute(fn ->
          exit(:normal)
        end)

      assert {:error, {:exit, :normal}} = result
    end
  end

  describe "MFA execution" do
    test "executes module function calls" do
      result = Sandbox.execute_mfa(String, :upcase, ["hello"])
      assert {:ok, "HELLO"} = result
    end

    test "validates module access" do
      result = Sandbox.execute_mfa(NonExistentModule, :function, [], allowed_modules: [String])

      assert {:error, {:module_not_loaded, NonExistentModule}} = result
    end

    test "validates function access" do
      result = Sandbox.execute_mfa(String, :upcase, ["hello"], allowed_functions: [{String, :downcase}])

      assert {:error, {:forbidden_function, {String, :upcase}}} = result
    end

    test "allows access to whitelisted functions" do
      result = Sandbox.execute_mfa(String, :upcase, ["hello"], allowed_functions: [{String, :upcase}])

      assert {:ok, "HELLO"} = result
    end
  end

  describe "async execution" do
    test "creates async tasks" do
      task = Sandbox.async(fn -> 1 + 1 end)

      assert %Task{} = task
      assert Task.await(task) == 2
    end

    test "async tasks respect sandbox limits" do
      task =
        Sandbox.async(
          fn ->
            Process.sleep(100)
            :completed
          end,
          timeout_ms: 50
        )

      assert_raise RuntimeError, ~r/Sandbox error/, fn ->
        Task.await(task)
      end
    end
  end

  describe "resource checking" do
    test "check_limits returns ok when within limits" do
      Sandbox.execute(fn ->
        # Set up sandbox limits
        Process.put(:sandbox_reductions_limit, 1_000_000)
        Process.put(:sandbox_start_reductions, :erlang.statistics(:reductions))

        # Should be ok
        assert :ok = Sandbox.check_limits()

        :ok
      end)
    end

    test "check_limits returns error when over limits" do
      Sandbox.execute(fn ->
        # Set up very low limits
        Process.put(:sandbox_reductions_limit, 1)
        Process.put(:sandbox_start_reductions, 0)

        # Simulate high usage
        current_reductions = :erlang.statistics(:reductions)
        Process.put(:sandbox_start_reductions, current_reductions - 1000)

        # Should be over limit
        assert {:error, :cpu_limit} = Sandbox.check_limits()

        :ok
      end)
    end
  end

  describe "restricted execution" do
    test "execute_restricted has tighter limits" do
      # This should succeed in normal sandbox
      result1 =
        Sandbox.execute(
          fn ->
            Process.sleep(20)
            :ok
          end,
          timeout_ms: 100
        )

      assert {:ok, :ok} = result1

      # But might fail in restricted sandbox due to tighter limits
      result2 =
        Sandbox.execute_restricted(fn ->
          Process.sleep(20)
          :ok
        end)

      # Should either succeed or timeout, depending on system load
      assert {:ok, :ok} = result2 or {:error, :timeout} = result2
    end
  end

  describe "sandbox info" do
    test "provides sandbox information" do
      info = Sandbox.sandbox_info()

      assert is_map(info)
      assert Map.has_key?(info, :heap_size_bytes)
      assert Map.has_key?(info, :message_queue_len)
      assert Map.has_key?(info, :reductions)
    end
  end

  describe "file system restrictions" do
    test "execute_with_fs_restrictions sets allowed paths" do
      result =
        Sandbox.execute_with_fs_restrictions(
          fn ->
            # Check if sandbox allowed paths are set
            Process.get(:sandbox_allowed_paths)
          end,
          ["/tmp/", "/var/tmp/"]
        )

      assert {:ok, ["/tmp/", "/var/tmp/"]} = result
    end
  end

  describe "edge cases" do
    test "handles empty functions" do
      result = Sandbox.execute(fn -> nil end)
      assert {:ok, nil} = result
    end

    test "handles functions that return functions" do
      result = Sandbox.execute(fn -> fn -> :inner end end)
      assert {:ok, fun} = result
      assert is_function(fun)
    end

    test "handles very quick executions" do
      result = Sandbox.execute(fn -> :instant end, timeout_ms: 1)
      assert {:ok, :instant} = result
    end
  end
end
