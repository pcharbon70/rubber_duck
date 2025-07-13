defmodule RubberDuckWeb.CLIChannel do
  @moduledoc """
  Channel for handling CLI commands via WebSocket connection.

  This channel provides a real-time interface for CLI clients to execute
  commands without requiring compilation or losing server state.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Commands.Adapters.WebSocket, as: CommandAdapter
  alias RubberDuck.LLM.ConnectionManager

  require Logger

  @doc """
  Joins the CLI channel with authentication.
  """
  @impl true
  def join("cli:commands", _params, socket) do
    # CLI client authenticated via API key in UserSocket
    if socket.assigns[:user_id] do
      socket =
        socket
        |> assign(:request_count, 0)
        |> assign(:connected_at, DateTime.utc_now())

      Logger.info("CLI client connected: #{socket.assigns.user_id}")
      {:ok, %{status: "connected", server_time: DateTime.utc_now()}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle unified commands through the adapter
  @impl true
  def handle_in(command, params, socket) when command in ["analyze", "generate", "complete", "refactor", "test"] do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    Task.start_link(fn ->
      case CommandAdapter.handle_async_message(command, params, socket) do
        {:ok, %{request_id: async_request_id}} ->
          # Monitor the async request and push updates
          monitor_async_command(command, async_request_id, request_id, socket)
          
        {:error, reason} ->
          push(socket, "#{command}:error", %{
            status: "error",
            reason: to_string(reason),
            request_id: request_id
          })
      end
    end)

    {:reply, {:ok, %{status: "processing"}}, socket}
  end


  # Handle LLM commands
  @impl true
  def handle_in("llm", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    # Handle synchronously for LLM commands as they are typically quick
    case CommandAdapter.handle_message("llm", params, socket) do
      {:ok, result} ->
        # Handle formatted results - decode JSON strings back to maps
        parsed_result = parse_formatted_result(result)
        response = CommandAdapter.build_response({:ok, parsed_result}, request_id)
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        response = CommandAdapter.build_error_response(reason, request_id)
        {:reply, {:error, response}, socket}
    end
  end
  
  # Handle conversation commands
  @impl true
  def handle_in("conversation", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    # Handle synchronously but with longer timeout to prevent WebSocket timeouts
    case CommandAdapter.handle_message("conversation", params, socket) do
      {:ok, result} ->
        # Handle formatted results - decode JSON strings back to maps
        parsed_result = parse_formatted_result(result)
        response = CommandAdapter.build_response({:ok, parsed_result}, request_id)
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        response = CommandAdapter.build_error_response(reason, request_id)
        {:reply, {:error, response}, socket}
    end
  end

  # Handle streaming requests
  @impl true
  def handle_in("stream:" <> command, params, socket) do
    socket = increment_request_count(socket)
    stream_id = generate_stream_id()

    # Start streaming in a separate process
    Task.start_link(fn ->
      handle_streaming_command(command, params, stream_id, socket)
    end)

    {:reply, {:ok, %{stream_id: stream_id}}, socket}
  end

  # Handle ping to keep connection alive
  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: System.system_time(:millisecond)}}, socket}
  end

  # Handle health check request
  @impl true
  def handle_in("health", params, socket) do
    socket = increment_request_count(socket)
    request_id = Map.get(params, "request_id")

    case CommandAdapter.handle_message("health", params, socket) do
      {:ok, result} ->
        # Handle formatted results - decode JSON strings back to maps
        parsed_result = parse_formatted_result(result)
        response = CommandAdapter.build_response({:ok, parsed_result}, request_id)
        {:reply, {:ok, response}, socket}

      {:error, reason} ->
        response = CommandAdapter.build_error_response(reason, request_id)
        {:reply, {:error, response}, socket}
    end
  end

  # Handle stats request
  @impl true
  def handle_in("stats", _params, socket) do
    stats = %{
      request_count: socket.assigns.request_count,
      connected_at: socket.assigns.connected_at,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), socket.assigns.connected_at)
    }

    {:reply, {:ok, stats}, socket}
  end

  # Catch-all handler for debugging
  @impl true
  def handle_in(event, params, socket) do
    Logger.warning("Unhandled CLI channel event: #{event}, params: #{inspect(params)}")
    {:reply, {:error, %{reason: "Unknown command: #{event}"}}, socket}
  end

  # Private functions

  defp increment_request_count(socket) do
    assign(socket, :request_count, socket.assigns.request_count + 1)
  end

  defp monitor_async_command(command, async_request_id, client_request_id, socket) do
    # Poll for status updates and push to client
    Task.start_link(fn ->
      poll_async_status(command, async_request_id, client_request_id, socket, 0)
    end)
  end

  defp poll_async_status(command, async_request_id, client_request_id, socket, attempts) do
    case CommandAdapter.get_status(async_request_id) do
      {:ok, %{status: :completed, result: result}} ->
        # Handle formatted results - decode JSON strings back to maps
        parsed_result = case result do
          {:ok, json_string} when is_binary(json_string) ->
            case Jason.decode(json_string) do
              {:ok, decoded} -> decoded
              {:error, _} -> json_string  # Fallback to string if not valid JSON
            end
          {:ok, data} -> data
          other -> other
        end
        
        push(socket, "#{command}:result", %{
          status: "success",
          result: parsed_result,
          request_id: client_request_id
        })

      {:ok, %{status: :failed, result: {:error, reason}}} ->
        push(socket, "#{command}:error", %{
          status: "error",
          reason: to_string(reason),
          request_id: client_request_id
        })

      {:ok, %{status: status, progress: progress}} when status in [:pending, :running] ->
        # Optionally push progress updates
        if rem(attempts, 5) == 0 do  # Every 5th attempt (2.5 seconds)
          push(socket, "#{command}:progress", %{
            status: to_string(status),
            progress: progress,
            request_id: client_request_id
          })
        end
        
        # Continue polling
        if attempts < 120 do  # Max 60 seconds of polling
          Process.sleep(500)
          poll_async_status(command, async_request_id, client_request_id, socket, attempts + 1)
        else
          push(socket, "#{command}:error", %{
            status: "error",
            reason: "Command timed out",
            request_id: client_request_id
          })
        end

      {:error, reason} ->
        push(socket, "#{command}:error", %{
          status: "error",
          reason: to_string(reason),
          request_id: client_request_id
        })
    end
  end


  defp generate_stream_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp parse_formatted_result(result) do
    case result do
      json_string when is_binary(json_string) ->
        case Jason.decode(json_string) do
          {:ok, decoded} -> decoded
          {:error, _} -> result  # Return as-is if not valid JSON
        end
      _ -> result
    end
  end

  defp handle_streaming_command(command, _params, stream_id, socket) do
    # This is a placeholder for streaming command implementation
    # Each command type would handle its own streaming logic
    push(socket, "stream:start", %{stream_id: stream_id, command: command})

    # Simulate streaming data
    for i <- 1..5 do
      Process.sleep(500)

      push(socket, "stream:data", %{
        stream_id: stream_id,
        chunk: "Processing #{command} - step #{i}/5"
      })
    end

    push(socket, "stream:end", %{stream_id: stream_id, status: "completed"})
  end

end
