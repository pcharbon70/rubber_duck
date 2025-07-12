defmodule RubberDuck.Commands.Adapters.WebSocket do
  @moduledoc """
  WebSocket adapter for the unified command system.
  
  Provides an interface for WebSocket channels to interact with the command
  processor, handling message parsing and response formatting.
  """

  alias RubberDuck.Commands.{Parser, Processor, Command, Context}

  @doc """
  Handle a WebSocket command message.
  
  ## Parameters
  - `event` - The WebSocket event name (e.g., "cli:commands")
  - `payload` - The message payload containing command and parameters
  - `socket` - The Phoenix socket for context information
  
  ## Returns
  - `{:ok, formatted_result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  def handle_message(event, payload, socket) do
    with {:ok, context} <- build_context(socket, payload),
         {:ok, command} <- parse_websocket_message(event, payload, context),
         {:ok, result} <- Processor.execute(command) do
      {:ok, result}
    end
  end

  @doc """
  Handle an async WebSocket command message.
  
  Returns a request ID for tracking the async execution.
  """
  def handle_async_message(event, payload, socket) do
    with {:ok, context} <- build_context(socket, payload),
         {:ok, command} <- parse_websocket_message(event, payload, context),
         {:ok, result} <- Processor.execute_async(command) do
      {:ok, result}
    end
  end

  @doc """
  Parse a WebSocket message into a Command struct without executing.
  """
  def parse_message(event, payload, socket) do
    with {:ok, context} <- build_context(socket, payload),
         {:ok, command} <- parse_websocket_message(event, payload, context) do
      {:ok, command}
    end
  end

  @doc """
  Get the status of an async command execution.
  """
  def get_status(request_id) do
    Processor.get_status(request_id)
  end

  @doc """
  Cancel an async command execution.
  """
  def cancel(request_id) do
    Processor.cancel(request_id)
  end

  @doc """
  Build a response message for WebSocket clients.
  
  Formats the result according to WebSocket message conventions.
  """
  def build_response(result, request_id \\ nil) do
    base_response = %{
      "status" => "ok",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    response = if request_id do
      Map.put(base_response, "request_id", request_id)
    else
      base_response
    end
    
    case result do
      {:ok, data} ->
        Map.put(response, "data", data)
        
      {:error, reason} ->
        %{response | 
          "status" => "error",
          "error" => to_string(reason)
        }
    end
  end

  @doc """
  Build an error response for WebSocket clients.
  """
  def build_error_response(reason, request_id \\ nil) do
    build_response({:error, reason}, request_id)
  end

  # Private functions

  defp build_context(socket, payload) do
    user_id = get_user_id(socket)
    session_id = get_session_id(socket)
    
    context_data = %{
      user_id: user_id,
      project_id: Map.get(payload, "project_id"),
      conversation_id: Map.get(payload, "conversation_id"),
      session_id: session_id,
      permissions: get_user_permissions(socket),
      metadata: %{
        socket_id: socket.id,
        transport: "websocket",
        channel_topic: socket.topic,
        remote_ip: get_remote_ip(socket)
      }
    }
    
    Context.new(context_data)
  end

  defp parse_websocket_message(event, payload, context) do
    # Convert WebSocket message to unified input format
    input = %{
      "event" => event,
      "payload" => payload,
      "command" => Map.get(payload, "command"),
      "params" => Map.get(payload, "params", %{})
    }
    
    Parser.parse(input, :websocket, context)
  end

  defp get_user_id(socket) do
    case Map.get(socket.assigns, :user_id) do
      nil -> "websocket_user_#{socket.id}"
      user_id -> user_id
    end
  end

  defp get_session_id(socket) do
    case Map.get(socket.assigns, :session_id) do
      nil -> "websocket_session_#{socket.id}_#{System.system_time(:millisecond)}"
      session_id -> session_id
    end
  end

  defp get_user_permissions(socket) do
    Map.get(socket.assigns, :permissions, [:read, :write])
  end

  defp get_remote_ip(socket) do
    case Map.get(socket, :transport_pid) do
      nil -> "unknown"
      transport_pid ->
        try do
          {:ok, {ip, _port}} = :inet.peername(transport_pid)
          :inet.ntoa(ip) |> to_string()
        rescue
          _ -> "unknown"
        end
    end
  end
end