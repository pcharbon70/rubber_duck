defmodule RubberDuckWeb.CodeChannel do
  @moduledoc """
  Channel for real-time code-related operations including streaming
  completions, live analysis, and collaborative features.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Commands.{Parser, Processor, Context}
  alias RubberDuck.Workspace

  require Logger

  # 1MB
  @max_message_size 1_000_000

  @impl true
  def join("code:project:" <> project_id, params, socket) do
    with {:ok, project} <- authorize_project_access(project_id, socket.assigns.user_id),
         :ok <- validate_join_params(params) do
      socket =
        socket
        |> assign(:project_id, project_id)
        |> assign(:project, project)
        |> assign(:cursor_position, params["cursor_position"] || %{})

      # Track user presence
      send(self(), :after_join)

      {:ok, %{status: "joined", project_id: project_id}, socket}
    else
      {:error, :unauthorized} ->
        {:error, %{reason: "Unauthorized access to project"}}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def join("code:file:" <> file_id, params, socket) do
    with {:ok, file} <- authorize_file_access(file_id, socket.assigns.user_id),
         :ok <- validate_join_params(params) do
      socket =
        socket
        |> assign(:file_id, file_id)
        |> assign(:file, file)

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Handle completion requests
  @impl true
  def handle_in("complete", params, socket) do
    with {:ok, context} <- build_context(socket, params),
         {:ok, command} <- Parser.parse(["complete"] ++ build_args(params), :websocket, context),
         {:ok, result} <- Processor.execute_async(command) do
      
      # Monitor the async execution
      monitor_completion(result.request_id, socket)
      
      {:reply, {:ok, %{request_id: result.request_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Handle analysis requests
  def handle_in("analyze", params, socket) do
    with {:ok, context} <- build_context(socket, params),
         {:ok, command} <- Parser.parse(["analyze"] ++ build_args(params), :websocket, context),
         {:ok, result} <- Processor.execute_async(command) do
      
      # Monitor the async execution
      monitor_analysis(result.request_id, socket)
      
      {:reply, {:ok, %{request_id: result.request_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Handle cursor position updates for collaborative features
  def handle_in("cursor_position", %{"position" => position}, socket) do
    socket = assign(socket, :cursor_position, position)

    # Broadcast to other users in the same file/project
    broadcast_from!(socket, "cursor_update", %{
      user_id: socket.assigns.user_id,
      position: position,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  # Handle code changes for collaborative editing
  def handle_in("code_change", %{"changes" => changes}, socket) do
    # Validate changes
    with :ok <- validate_changes(changes, socket) do
      # Broadcast changes to other users
      broadcast_from!(socket, "code_updated", %{
        user_id: socket.assigns.user_id,
        changes: changes,
        timestamp: DateTime.utc_now()
      })

      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Cancel an active completion
  def handle_in("cancel_completion", %{"completion_id" => _completion_id}, socket) do
    # TODO: Implement completion cancellation
    {:reply, :ok, socket}
  end

  # Intercept outgoing messages to add user-specific data
  intercept(["completion_chunk", "analysis_result", "cursor_update", "code_updated"])

  @impl true
  def handle_out(event, payload, socket) do
    # Add user context to outgoing messages
    enhanced_payload = Map.put(payload, :from_user_id, socket.assigns.user_id)
    push(socket, event, enhanced_payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Set up presence tracking
    {:ok, _} =
      RubberDuckWeb.Presence.track(
        socket,
        socket.assigns.user_id,
        %{
          online_at: DateTime.utc_now(),
          cursor_position: socket.assigns[:cursor_position] || %{}
        }
      )

    # Push current presence state
    push(socket, "presence_state", RubberDuckWeb.Presence.list(socket))

    {:noreply, socket}
  end


  # Private functions

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement real authorization logic
    # For now, just verify the project exists
    case Workspace.get_project(project_id) do
      {:ok, project} -> {:ok, project}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_file_access(file_id, _user_id) do
    # TODO: Implement real authorization logic
    # For now, just verify the file exists
    case Workspace.get_code_file(file_id) do
      {:ok, file} -> {:ok, file}
      _ -> {:error, :unauthorized}
    end
  end

  defp validate_join_params(_params) do
    # Add any parameter validation logic here
    :ok
  end

  defp validate_changes(changes, _socket) do
    # Validate change format and size
    if byte_size(:erlang.term_to_binary(changes)) > @max_message_size do
      {:error, "Changes exceed maximum message size"}
    else
      :ok
    end
  end

  defp build_context(socket, params) do
    context_data = %{
      user_id: socket.assigns[:user_id] || "websocket_user_#{socket.id}",
      project_id: socket.assigns[:project_id],
      session_id: "websocket_session_#{socket.id}_#{System.system_time(:millisecond)}",
      permissions: [:read, :write, :execute],
      metadata: %{
        socket_id: socket.id,
        transport: "websocket",
        channel_topic: socket.topic,
        params: params
      }
    }
    
    Context.new(context_data)
  end

  defp build_args(params) do
    args = []
    
    # Add file path if present
    args = if params["file_path"], do: args ++ [params["file_path"]], else: args
    
    # Add type if present
    args = if params["type"], do: args ++ ["--type", params["type"]], else: args
    
    # Add line and column for completions
    args = if params["line"] do
      args ++ ["--line", to_string(params["line"])]
    else
      args
    end
    
    args = if params["column"] do
      args ++ ["--column", to_string(params["column"])]
    else
      args
    end
    
    args
  end

  defp monitor_completion(request_id, socket) do
    Task.start_link(fn ->
      poll_status(request_id, socket, "completion", 0)
    end)
  end

  defp monitor_analysis(request_id, socket) do
    Task.start_link(fn ->
      poll_status(request_id, socket, "analysis", 0)
    end)
  end

  defp poll_status(request_id, socket, type, attempts) do
    case Processor.get_status(request_id) do
      {:ok, %{status: :completed, result: result}} ->
        push(socket, "#{type}_result", %{
          request_id: request_id,
          result: result,
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: :failed, result: {:error, reason}}} ->
        push(socket, "#{type}_error", %{
          request_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: status}} when status in [:pending, :running] ->
        # Continue polling
        if attempts < 120 do  # Max 60 seconds
          Process.sleep(500)
          poll_status(request_id, socket, type, attempts + 1)
        else
          push(socket, "#{type}_error", %{
            request_id: request_id,
            error: "Request timed out",
            timestamp: DateTime.utc_now()
          })
        end

      {:error, reason} ->
        push(socket, "#{type}_error", %{
          request_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })
    end
  end
end
