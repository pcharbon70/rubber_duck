defmodule RubberDuck.Engine.CancellationToken do
  @moduledoc """
  Provides cancellation tokens for tracking and cancelling async operations.
  
  A cancellation token is a lightweight mechanism to signal that an operation
  should be cancelled. Tokens are checked at various checkpoints during processing.
  """
  
  use Agent
  require Logger
  
  @type t :: %__MODULE__{
    id: String.t(),
    conversation_id: String.t(),
    cancelled: boolean(),
    cancelled_at: DateTime.t() | nil,
    reason: any()
  }
  
  defstruct [:id, :conversation_id, :cancelled, :cancelled_at, :reason]
  
  @doc """
  Creates a new cancellation token for a conversation.
  """
  def create(conversation_id) do
    token_id = "cancel_token_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
    
    token = %__MODULE__{
      id: token_id,
      conversation_id: conversation_id,
      cancelled: false,
      cancelled_at: nil,
      reason: nil
    }
    
    # Start an Agent to hold the token state
    {:ok, pid} = Agent.start_link(fn -> token end)
    
    # Store the pid in the token for reference
    %{token | id: {token_id, pid}}
  end
  
  @doc """
  Checks if a token has been cancelled.
  
  This is a fast, non-blocking check that should be called frequently
  during long-running operations.
  """
  def cancelled?(%__MODULE__{id: {_token_id, pid}}) when is_pid(pid) do
    try do
      Agent.get(pid, & &1.cancelled, 100)
    catch
      :exit, _ -> true  # If the agent is dead, consider it cancelled
    end
  end
  
  def cancelled?(_), do: false
  
  @doc """
  Cancels a token with an optional reason.
  """
  def cancel(token, reason \\ :user_cancelled)
  
  def cancel(%__MODULE__{id: {token_id, pid}}, reason) when is_pid(pid) do
    try do
      Agent.update(pid, fn state ->
        if state.cancelled do
          state
        else
          Logger.info("Cancelling token #{token_id} for conversation #{state.conversation_id}, reason: #{inspect(reason)}")
          %{state | cancelled: true, cancelled_at: DateTime.utc_now(), reason: reason}
        end
      end)
      :ok
    catch
      :exit, _ -> {:error, :token_not_found}
    end
  end
  
  def cancel(_, _), do: {:error, :invalid_token}
  
  @doc """
  Gets the current state of a token.
  """
  def get_state(%__MODULE__{id: {_token_id, pid}}) when is_pid(pid) do
    try do
      {:ok, Agent.get(pid, & &1)}
    catch
      :exit, _ -> {:error, :token_not_found}
    end
  end
  
  def get_state(_), do: {:error, :invalid_token}
  
  @doc """
  Stops the token agent, cleaning up resources.
  """
  def stop(%__MODULE__{id: {_token_id, pid}}) when is_pid(pid) do
    Agent.stop(pid)
  end
  
  def stop(_), do: :ok
  
  @doc """
  Checks if the token is cancelled and raises if it is.
  
  This is useful for guard-style checks in pipelines:
  
      with :ok <- CancellationToken.check!(token),
           {:ok, result} <- do_work() do
        {:ok, result}
      end
  """
  def check!(%__MODULE__{} = token) do
    if cancelled?(token) do
      {:error, :cancelled}
    else
      :ok
    end
  end
  
  @doc """
  Adds a cancellation token to an input map.
  
  This is a convenience function for adding tokens to engine inputs.
  """
  def add_to_input(input, %__MODULE__{} = token) when is_map(input) do
    Map.put(input, :cancellation_token, token)
  end
  
  def add_to_input(input, nil), do: input
  
  @doc """
  Extracts a cancellation token from an input map.
  """
  def from_input(%{cancellation_token: %__MODULE__{} = token}), do: token
  def from_input(_), do: nil
  
  @doc """
  Performs an operation with periodic cancellation checks.
  
  This is useful for wrapping operations that don't naturally have cancellation points.
  The check_fn should return {:ok, result} or {:cont, state} to continue, or {:halt, result} to stop.
  """
  def with_cancellation(%__MODULE__{} = token, initial_state, check_interval_ms, check_fn) do
    do_with_cancellation(token, initial_state, check_interval_ms, check_fn)
  end
  
  defp do_with_cancellation(token, state, interval, check_fn) do
    if cancelled?(token) do
      {:error, :cancelled}
    else
      case check_fn.(state) do
        {:ok, result} -> 
          {:ok, result}
          
        {:cont, new_state} ->
          Process.sleep(interval)
          do_with_cancellation(token, new_state, interval, check_fn)
          
        {:halt, result} -> 
          {:ok, result}
          
        other -> 
          other
      end
    end
  end
end