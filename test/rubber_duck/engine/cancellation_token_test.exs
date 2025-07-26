defmodule RubberDuck.Engine.CancellationTokenTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Engine.CancellationToken
  
  describe "create/1" do
    test "creates a new cancellation token" do
      token = CancellationToken.create("conv_123")
      
      assert %CancellationToken{} = token
      assert token.conversation_id == "conv_123"
      assert token.cancelled == false
      assert is_nil(token.cancelled_at)
      assert is_nil(token.reason)
    end
  end
  
  describe "cancelled?/1" do
    test "returns false for non-cancelled token" do
      token = CancellationToken.create("conv_123")
      refute CancellationToken.cancelled?(token)
    end
    
    test "returns true for cancelled token" do
      token = CancellationToken.create("conv_123")
      CancellationToken.cancel(token)
      
      assert CancellationToken.cancelled?(token)
    end
    
    test "returns false for invalid input" do
      refute CancellationToken.cancelled?(nil)
      refute CancellationToken.cancelled?(%{})
      refute CancellationToken.cancelled?("not a token")
    end
  end
  
  describe "cancel/2" do
    test "cancels token with default reason" do
      token = CancellationToken.create("conv_123")
      
      assert :ok = CancellationToken.cancel(token)
      assert CancellationToken.cancelled?(token)
      
      {:ok, state} = CancellationToken.get_state(token)
      assert state.cancelled == true
      assert state.reason == :user_cancelled
      assert not is_nil(state.cancelled_at)
    end
    
    test "cancels token with custom reason" do
      token = CancellationToken.create("conv_123")
      
      assert :ok = CancellationToken.cancel(token, :timeout)
      
      {:ok, state} = CancellationToken.get_state(token)
      assert state.reason == :timeout
    end
    
    test "cancelling already cancelled token is idempotent" do
      token = CancellationToken.create("conv_123")
      
      # First cancel
      CancellationToken.cancel(token, :reason1)
      {:ok, state1} = CancellationToken.get_state(token)
      
      # Second cancel
      CancellationToken.cancel(token, :reason2)
      {:ok, state2} = CancellationToken.get_state(token)
      
      # State should not change
      assert state1.reason == state2.reason
      assert state1.cancelled_at == state2.cancelled_at
    end
    
    test "returns error for invalid token" do
      assert {:error, :invalid_token} = CancellationToken.cancel(nil)
      assert {:error, :invalid_token} = CancellationToken.cancel(%{})
    end
  end
  
  describe "check!/1" do
    test "returns :ok for non-cancelled token" do
      token = CancellationToken.create("conv_123")
      assert :ok = CancellationToken.check!(token)
    end
    
    test "returns error for cancelled token" do
      token = CancellationToken.create("conv_123")
      CancellationToken.cancel(token)
      
      assert {:error, :cancelled} = CancellationToken.check!(token)
    end
  end
  
  describe "add_to_input/2" do
    test "adds token to input map" do
      token = CancellationToken.create("conv_123")
      input = %{query: "test"}
      
      result = CancellationToken.add_to_input(input, token)
      
      assert result.cancellation_token == token
      assert result.query == "test"
    end
    
    test "returns input unchanged for nil token" do
      input = %{query: "test"}
      result = CancellationToken.add_to_input(input, nil)
      
      assert result == input
    end
  end
  
  describe "from_input/1" do
    test "extracts token from input" do
      token = CancellationToken.create("conv_123")
      input = %{cancellation_token: token, query: "test"}
      
      assert CancellationToken.from_input(input) == token
    end
    
    test "returns nil when no token present" do
      assert is_nil(CancellationToken.from_input(%{query: "test"}))
      assert is_nil(CancellationToken.from_input(%{}))
    end
  end
  
  describe "stop/1" do
    test "stops the token agent" do
      token = CancellationToken.create("conv_123")
      {_token_id, pid} = token.id
      
      assert Process.alive?(pid)
      
      CancellationToken.stop(token)
      
      # Give it a moment to stop
      Process.sleep(10)
      
      refute Process.alive?(pid)
    end
    
    test "handles invalid token gracefully" do
      assert :ok = CancellationToken.stop(nil)
      assert :ok = CancellationToken.stop(%{})
    end
  end
  
  describe "with_cancellation/4" do
    test "executes function with cancellation checks" do
      token = CancellationToken.create("conv_123")
      
      result = CancellationToken.with_cancellation(token, 0, 10, fn state ->
        if state >= 5 do
          {:ok, state}
        else
          {:cont, state + 1}
        end
      end)
      
      assert {:ok, 5} = result
    end
    
    test "stops execution when token is cancelled" do
      token = CancellationToken.create("conv_123")
      
      # Cancel token after a delay
      Task.async(fn ->
        Process.sleep(50)
        CancellationToken.cancel(token)
      end)
      
      result = CancellationToken.with_cancellation(token, 0, 20, fn state ->
        {:cont, state + 1}
      end)
      
      assert {:error, :cancelled} = result
    end
    
    test "handles halt response" do
      token = CancellationToken.create("conv_123")
      
      result = CancellationToken.with_cancellation(token, 0, 10, fn state ->
        if state == 3 do
          {:halt, :stopped_early}
        else
          {:cont, state + 1}
        end
      end)
      
      assert {:ok, :stopped_early} = result
    end
  end
end