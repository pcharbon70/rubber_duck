defmodule RubberDuckWeb.WorkspaceChannel do
  @moduledoc """
  Channel for workspace-level operations including file management,
  project updates, and workspace-wide notifications.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Workspace

  require Logger

  @impl true
  def join("workspace:user:" <> user_id, _params, socket) do
    if socket.assigns.user_id == user_id do
      socket =
        socket
        |> assign(:workspace_channel, "user")
        |> assign(:workspace_id, user_id)

      # Send initial workspace state
      send(self(), :after_join)

      {:ok, %{status: "joined", workspace_type: "user"}, socket}
    else
      {:error, %{reason: "Unauthorized"}}
    end
  end

  def join("workspace:project:" <> project_id, _params, socket) do
    with {:ok, project} <- authorize_project_access(project_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:workspace_channel, "project")
        |> assign(:workspace_id, project_id)
        |> assign(:project, project)

      # Send initial project state
      send(self(), :after_join)

      {:ok, %{status: "joined", workspace_type: "project", project_id: project_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # File operations
  @impl true
  def handle_in("create_file", params, socket) do
    %{"path" => path, "content" => content} = params

    with {:ok, project} <- get_current_project(socket),
         {:ok, file} <-
           Workspace.create_code_file(%{
             project_id: project.id,
             path: path,
             content: content,
             language: detect_language(path)
           }) do
      # Broadcast file creation to all users in workspace
      broadcast!(socket, "file_created", %{
        file: serialize_file(file),
        created_by: socket.assigns.user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{file: serialize_file(file)}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("update_file", %{"file_id" => file_id, "content" => content}, socket) do
    with {:ok, file} <- Workspace.get_code_file(file_id),
         :ok <- authorize_file_access(file, socket.assigns.user_id),
         {:ok, updated_file} <- Workspace.update_code_file(file, %{content: content}) do
      # Broadcast file update
      broadcast_from!(socket, "file_updated", %{
        file: serialize_file(updated_file),
        updated_by: socket.assigns.user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{file: serialize_file(updated_file)}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("delete_file", %{"file_id" => file_id}, socket) do
    with {:ok, file} <- Workspace.get_code_file(file_id),
         :ok <- authorize_file_access(file, socket.assigns.user_id),
         {:ok, _} <- Workspace.delete_code_file(file) do
      # Broadcast file deletion
      broadcast!(socket, "file_deleted", %{
        file_id: file_id,
        deleted_by: socket.assigns.user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("list_files", _params, socket) do
    with {:ok, project} <- get_current_project(socket),
         {:ok, files} <- Workspace.list_code_files(%{project_id: project.id}) do
      serialized_files = Enum.map(files, &serialize_file/1)
      {:reply, {:ok, %{files: serialized_files}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Project operations
  def handle_in("update_project", params, socket) do
    with {:ok, project} <- get_current_project(socket),
         {:ok, updated_project} <- Workspace.update_project(project, params) do
      broadcast!(socket, "project_updated", %{
        project: serialize_project(updated_project),
        updated_by: socket.assigns.user_id,
        timestamp: DateTime.utc_now()
      })

      {:reply, {:ok, %{project: serialize_project(updated_project)}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Handle after join
  @impl true
  def handle_info(:after_join, socket) do
    case socket.assigns.workspace_channel do
      "user" ->
        # Send user's projects
        push_user_workspace(socket)

      "project" ->
        # Send project details and files
        push_project_workspace(socket)
    end

    {:noreply, socket}
  end

  # Private functions

  defp push_user_workspace(socket) do
    case Workspace.list_projects(%{user_id: socket.assigns.user_id}) do
      {:ok, projects} ->
        push(socket, "workspace_state", %{
          type: "user",
          projects: Enum.map(projects, &serialize_project/1),
          timestamp: DateTime.utc_now()
        })

      {:error, _} ->
        push(socket, "workspace_error", %{
          error: "Failed to load workspace"
        })
    end
  end

  defp push_project_workspace(socket) do
    with {:ok, files} <- Workspace.list_code_files(%{project_id: socket.assigns.workspace_id}) do
      push(socket, "workspace_state", %{
        type: "project",
        project: serialize_project(socket.assigns.project),
        files: Enum.map(files, &serialize_file/1),
        timestamp: DateTime.utc_now()
      })
    else
      {:error, _} ->
        push(socket, "workspace_error", %{
          error: "Failed to load project workspace"
        })
    end
  end

  defp get_current_project(socket) do
    case socket.assigns do
      %{project: project} ->
        {:ok, project}

      %{workspace_channel: "project", workspace_id: id} ->
        Workspace.get_project(id)

      _ ->
        {:error, "No project context"}
    end
  end

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement real authorization
    Workspace.get_project(project_id)
  end

  defp authorize_file_access(_file, _user_id) do
    # TODO: Implement real authorization
    :ok
  end

  defp serialize_file(file) do
    %{
      id: file.id,
      path: file.path,
      language: file.language,
      size: byte_size(file.content || ""),
      created_at: file.created_at,
      updated_at: file.updated_at
    }
  end

  defp serialize_project(project) do
    %{
      id: project.id,
      name: project.name,
      description: project.description,
      created_at: project.created_at,
      updated_at: project.updated_at
    }
  end

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".rs" -> "rust"
      _ -> "text"
    end
  end
end
