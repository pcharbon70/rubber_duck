defmodule RubberDuckWeb.CodeChannel do
  @moduledoc """
  Channel for real-time code-related operations including streaming
  completions, live analysis, and collaborative features.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Analysis.Analyzer
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
        |> assign(:active_completions, %{})
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
        |> assign(:active_completions, %{})

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Handle completion requests
  @impl true
  def handle_in("request_completion", params, socket) do
    %{
      "code" => code,
      "cursor_position" => cursor_position,
      "file_type" => file_type
    } = params

    completion_id = generate_completion_id()

    # Start async completion
    Task.start_link(fn ->
      stream_completion(
        socket,
        completion_id,
        code,
        cursor_position,
        file_type,
        params["options"] || %{}
      )
    end)

    {:reply, {:ok, %{completion_id: completion_id}}, socket}
  end

  # Handle analysis requests
  def handle_in("request_analysis", %{"code" => code, "file_type" => file_type}, socket) do
    analysis_id = generate_analysis_id()

    Task.start_link(fn ->
      perform_analysis(socket, analysis_id, code, file_type)
    end)

    {:reply, {:ok, %{analysis_id: analysis_id}}, socket}
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

  # Handle completion streaming results
  def handle_info({:completion_chunk, completion_id, chunk}, socket) do
    push(socket, "completion_chunk", %{
      completion_id: completion_id,
      chunk: chunk,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  def handle_info({:completion_done, completion_id, final_result}, socket) do
    push(socket, "completion_done", %{
      completion_id: completion_id,
      result: final_result,
      timestamp: DateTime.utc_now()
    })

    # Clean up tracking
    active = Map.delete(socket.assigns.active_completions, completion_id)
    {:noreply, assign(socket, :active_completions, active)}
  end

  def handle_info({:completion_error, completion_id, error}, socket) do
    push(socket, "completion_error", %{
      completion_id: completion_id,
      error: error,
      timestamp: DateTime.utc_now()
    })

    # Clean up tracking
    active = Map.delete(socket.assigns.active_completions, completion_id)
    {:noreply, assign(socket, :active_completions, active)}
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

  defp stream_completion(socket, completion_id, code, cursor_position, file_type, _options) do
    try do
      # Build context
      _context = build_completion_context(socket, code, cursor_position, file_type)

      # TODO: Implement streaming completion properly
      # For now, send a placeholder response
      push(socket, "completion", %{
        completion_id: completion_id,
        suggestions: [],
        error: "Streaming completion not yet implemented"
      })

      # Signal completion done
      send(self(), {:completion_done, completion_id, %{status: "completed"}})
    rescue
      error ->
        Logger.error("Completion streaming error: #{inspect(error)}")
        send(self(), {:completion_error, completion_id, Exception.message(error)})
    end
  end

  defp perform_analysis(socket, analysis_id, code, file_type) do
    try do
      # Run analysis
      result = Analyzer.analyze_source(code, file_type)

      # Send results
      push(socket, "analysis_result", %{
        analysis_id: analysis_id,
        result: result,
        timestamp: DateTime.utc_now()
      })
    rescue
      error ->
        Logger.error("Analysis error: #{inspect(error)}")

        push(socket, "analysis_error", %{
          analysis_id: analysis_id,
          error: Exception.message(error),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp build_completion_context(socket, code, cursor_position, file_type) do
    # Build context from available information
    %{
      user_id: socket.assigns.user_id,
      project_id: socket.assigns[:project_id],
      file_id: socket.assigns[:file_id],
      code: code,
      cursor_position: cursor_position,
      file_type: file_type,
      timestamp: DateTime.utc_now()
    }
  end

  defp generate_completion_id do
    "completion_#{:crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)}"
  end

  defp generate_analysis_id do
    "analysis_#{:crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)}"
  end
end
