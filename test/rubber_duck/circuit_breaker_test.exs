defmodule RubberDuck.CircuitBreakerTest do
  use ExUnit.Case, async: false

  # Test circuit breaker module
  defmodule TestBreaker do
    use RubberDuck.CircuitBreaker,
      name: :test_breaker,
      failure_threshold: 3,
      success_threshold: 2,
      timeout: 100,
      reset_timeout: 200
  end

  setup do
    # Stop if already running
    case Registry.lookup(RubberDuck.CircuitBreakerRegistry, :test_breaker) do
      [{pid, _}] -> 
        if Process.alive?(pid) do
          GenServer.stop(pid, :normal)
          Process.sleep(10)
        end
      [] -> :ok
    end
    
    {:ok, _pid} = TestBreaker.start_link()
    :ok
  end

  describe "circuit breaker states" do
    test "starts in closed state" do
      state = TestBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "successful calls in closed state" do
      assert {:ok, :success} = TestBreaker.call(fn -> :success end)
      assert {:ok, 42} = TestBreaker.call(fn -> 42 end)
      
      state = TestBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "opens after failure threshold" do
      # First two failures don't open the circuit
      assert {:error, %RuntimeError{message: "fail"}} = TestBreaker.call(fn -> raise "fail" end)
      assert {:error, %RuntimeError{message: "fail"}} = TestBreaker.call(fn -> raise "fail" end)
      
      state = TestBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 2
      
      # Third failure opens the circuit
      assert {:error, %RuntimeError{message: "fail"}} = TestBreaker.call(fn -> raise "fail" end)
      
      state = TestBreaker.state()
      assert state.state == :open
      assert state.failure_count == 3
    end

    test "rejects calls when open" do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        TestBreaker.call(fn -> raise "fail" end)
      end)
      
      # Subsequent calls are rejected
      assert {:error, :circuit_open} = TestBreaker.call(fn -> :should_not_run end)
      assert {:error, :circuit_open} = TestBreaker.call(fn -> :should_not_run end)
    end

    test "transitions to half-open after reset timeout" do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        TestBreaker.call(fn -> raise "fail" end)
      end)
      
      # Wait for reset timeout
      Process.sleep(250)
      
      # Next call should be allowed (half-open state)
      assert {:ok, :recovered} = TestBreaker.call(fn -> :recovered end)
      
      state = TestBreaker.state()
      assert state.state == :half_open
    end

    test "closes from half-open after success threshold" do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        TestBreaker.call(fn -> raise "fail" end)
      end)
      
      # Wait for reset timeout
      Process.sleep(250)
      
      # First success in half-open
      assert {:ok, :success1} = TestBreaker.call(fn -> :success1 end)
      state = TestBreaker.state()
      assert state.state == :half_open
      assert state.success_count == 1
      
      # Second success closes the circuit
      assert {:ok, :success2} = TestBreaker.call(fn -> :success2 end)
      state = TestBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
    end

    test "reopens from half-open on failure" do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        TestBreaker.call(fn -> raise "fail" end)
      end)
      
      # Wait for reset timeout
      Process.sleep(250)
      
      # Failure in half-open reopens immediately
      assert {:error, %RuntimeError{message: "fail again"}} = TestBreaker.call(fn -> raise "fail again" end)
      
      state = TestBreaker.state()
      assert state.state == :open
      assert state.failure_count == 4
    end

    test "handles timeout" do
      # Timeouts count as failures
      assert {:error, :timeout} = TestBreaker.call(
        fn -> Process.sleep(200) end,
        timeout: 50
      )
      
      state = TestBreaker.state()
      assert state.failure_count == 1
    end

    test "manual reset" do
      # Open the circuit
      Enum.each(1..3, fn _ ->
        TestBreaker.call(fn -> raise "fail" end)
      end)
      
      assert TestBreaker.state().state == :open
      
      # Manual reset
      assert :ok = TestBreaker.reset()
      
      state = TestBreaker.state()
      assert state.state == :closed
      assert state.failure_count == 0
      
      # Can call again
      assert {:ok, :success} = TestBreaker.call(fn -> :success end)
    end
  end

  describe "error handling" do
    test "handles different error types" do
      # Exception
      assert {:error, %RuntimeError{}} = TestBreaker.call(fn -> 
        raise "runtime error"
      end)
      
      # Throw
      assert {:error, {:throw, :something}} = TestBreaker.call(fn -> 
        throw(:something)
      end)
      
      # Exit
      assert {:error, {:exit, :normal}} = TestBreaker.call(fn -> 
        exit(:normal)
      end)
    end
  end
end