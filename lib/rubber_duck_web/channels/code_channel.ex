defmodule RubberDuckWeb.CodeChannel do
  @moduledoc """
  Channel for real-time code-related operations including streaming
  completions, live analysis, and collaborative features.
  
  NOTE: This channel's functionality has been temporarily disabled
  due to the removal of the Commands system. It needs to be
  reimplemented to work directly with the code engines.
  """

  use RubberDuckWeb, :channel

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
      {:error, :unauthorized} ->
        {:error, %{reason: "Unauthorized access to file"}}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Handle presence tracking after join
  @impl true
  def handle_info(:after_join, socket) do
    # Track presence for collaborative features
    if project_id = socket.assigns[:project_id] do
      {:ok, _} =
        RubberDuckWeb.Presence.track(socket, socket.assigns.user_id, %{
          online_at: inspect(System.system_time(:second)),
          project_id: project_id
        })

      push(socket, "presence_state", RubberDuckWeb.Presence.list(socket))
    end

    {:noreply, socket}
  end

  # Temporarily disabled handlers - need reimplementation
  @impl true
  def handle_in("generate", _params, socket) do
    {:reply, {:error, %{reason: "Code generation temporarily unavailable"}}, socket}
  end

  def handle_in("complete", _params, socket) do
    {:reply, {:error, %{reason: "Code completion temporarily unavailable"}}, socket}
  end

  def handle_in("refactor", _params, socket) do
    {:reply, {:error, %{reason: "Code refactoring temporarily unavailable"}}, socket}
  end

  def handle_in("analyze", _params, socket) do
    {:reply, {:error, %{reason: "Code analysis temporarily unavailable"}}, socket}
  end

  def handle_in("cancel", _params, socket) do
    {:reply, {:error, %{reason: "Cancel functionality temporarily unavailable"}}, socket}
  end

  def handle_in("get_status", _params, socket) do
    {:reply, {:error, %{reason: "Status functionality temporarily unavailable"}}, socket}
  end

  # Private functions

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement proper authorization
    case Workspace.get_project(project_id) do
      {:ok, project} -> {:ok, project}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_file_access(file_id, _user_id) do
    # TODO: Implement proper authorization
    case Workspace.get_code_file(file_id) do
      {:ok, file} -> {:ok, file}
      _ -> {:error, :unauthorized}
    end
  end

  defp validate_join_params(params) do
    cond do
      is_map(params) -> :ok
      true -> {:error, "Invalid join parameters"}
    end
  end
end