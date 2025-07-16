defmodule RubberDuck.MCP.Server.Streaming do
  @moduledoc """
  Provides streaming and progress support for MCP server operations.
  
  This module enables tools and resources to stream responses and report
  progress for long-running operations, improving the user experience
  for AI assistants.
  """
  
  require Logger
  
  alias Hermes.Server.Frame
  
  @type progress_token :: String.t()
  @type progress_info :: %{
    required(:progress) => number(),
    optional(:total) => number(),
    optional(:message) => String.t()
  }
  
  @doc """
  Starts a streaming operation and returns a progress token.
  
  The token can be used to send progress updates and streamed content.
  """
  def start_stream(frame, operation_name) do
    token = generate_progress_token()
    
    # Store the streaming context in the frame
    streaming_context = %{
      token: token,
      operation: operation_name,
      started_at: System.monotonic_time(:millisecond),
      progress: 0
    }
    
    frame = Frame.put_private(frame, :streaming_contexts, Map.put(frame.private[:streaming_contexts] || %{}, token, streaming_context))
    
    Logger.debug("Started streaming operation #{operation_name} with token #{token}")
    
    {:ok, token, frame}
  end
  
  @doc """
  Sends a progress update for a streaming operation.
  """
  def send_progress(frame, token, progress_info) do
    case get_in(frame.private, [:streaming_contexts, token]) do
      nil ->
        {:error, :invalid_token}
        
      context ->
        # Validate progress info
        with :ok <- validate_progress(progress_info) do
          # Send progress notification
          send_progress_notification(frame, token, progress_info)
          
          # Update context
          updated_context = Map.put(context, :progress, progress_info.progress)
          contexts = Map.put(frame.private[:streaming_contexts] || %{}, token, updated_context)
          frame = Frame.put_private(frame, :streaming_contexts, contexts)
          
          {:ok, frame}
        end
    end
  end
  
  @doc """
  Streams a chunk of content for the operation.
  """
  def stream_chunk(frame, token, chunk) do
    case get_in(frame.private, [:streaming_contexts, token]) do
      nil ->
        {:error, :invalid_token}
        
      _context ->
        # Send the chunk as a notification
        notification = %{
          "method" => "progress/update",
          "params" => %{
            "progressToken" => token,
            "kind" => "content",
            "content" => chunk
          }
        }
        
        # Notification sending should be done through transport layer
        Logger.debug("Progress notification: #{inspect(notification)}")
        {:ok, frame}
    end
  end
  
  @doc """
  Completes a streaming operation.
  """
  def complete_stream(frame, token, final_result \\ nil) do
    case get_in(frame.private, [:streaming_contexts, token]) do
      nil ->
        {:error, :invalid_token}
        
      context ->
        duration = System.monotonic_time(:millisecond) - context.started_at
        
        Logger.debug("Completed streaming operation #{context.operation} in #{duration}ms")
        
        # Send completion notification
        notification = %{
          "method" => "progress/update",
          "params" => %{
            "progressToken" => token,
            "kind" => "end",
            "result" => final_result
          }
        }
        
        # Notification sending should be done through transport layer
        Logger.debug("Progress notification: #{inspect(notification)}")
        
        # Clean up the streaming context
        contexts = Map.delete(frame.private[:streaming_contexts] || %{}, token)
        frame = Frame.put_private(frame, :streaming_contexts, contexts)
        
        {:ok, frame}
    end
  end
  
  @doc """
  Creates a streaming response wrapper for tools that support streaming.
  """
  def streaming_response(initial_content, token) do
    %{
      "content" => initial_content,
      "isPartial" => true,
      "progressToken" => token
    }
  end
  
  @doc """
  Wraps a function to automatically handle streaming.
  
  ## Example
  
      def execute(params, frame) do
        Streaming.with_stream(frame, "my_operation", fn frame, token ->
          # Send progress updates
          {:ok, frame} = Streaming.send_progress(frame, token, %{progress: 0.5, message: "Half way"})
          
          # Stream content
          {:ok, frame} = Streaming.stream_chunk(frame, token, "First chunk")
          {:ok, frame} = Streaming.stream_chunk(frame, token, "Second chunk")
          
          # Return final result
          {:ok, "Complete result", frame}
        end)
      end
  """
  def with_stream(frame, operation_name, fun) when is_function(fun, 2) do
    case start_stream(frame, operation_name) do
      {:ok, token, frame} ->
        try do
          case fun.(frame, token) do
            {:ok, result, frame} ->
              {:ok, _frame} = complete_stream(frame, token, result)
              {:ok, streaming_response(result, token), frame}
              
            {:error, reason} ->
              # Clean up on error
              {:ok, _frame} = complete_stream(frame, token, nil)
              {:error, reason}
              
            other ->
              # Clean up on unexpected return
              {:ok, _frame} = complete_stream(frame, token, nil)
              other
          end
        rescue
          error ->
            # Clean up on exception
            {:ok, _frame} = complete_stream(frame, token, nil)
            reraise error, __STACKTRACE__
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private functions
  
  defp generate_progress_token do
    "prog_" <> Base.encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
  
  defp validate_progress(%{progress: p} = info) when is_number(p) and p >= 0 and p <= 1 do
    if total = info[:total] do
      if is_number(total) and total > 0 do
        :ok
      else
        {:error, "Total must be a positive number"}
      end
    else
      :ok
    end
  end
  
  defp validate_progress(_) do
    {:error, "Progress must be a number between 0 and 1"}
  end
  
  defp send_progress_notification(frame, token, progress_info) do
    notification = %{
      "method" => "progress/update", 
      "params" => %{
        "progressToken" => token,
        "kind" => "progress",
        "progress" => progress_info.progress,
        "total" => progress_info[:total],
        "message" => progress_info[:message]
      }
    }
    
    Hermes.Server.Frame.send_notification(frame, notification)
  end
end