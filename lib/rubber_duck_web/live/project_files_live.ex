defmodule RubberDuckWeb.Live.ProjectFilesLive do
  @moduledoc """
  LiveView module for real-time project file management.
  
  Provides a collaborative file browser with real-time updates,
  presence tracking, and file operations.
  """
  
  use RubberDuckWeb, :live_view
  
  alias RubberDuck.Workspace
  alias RubberDuck.Projects.{FileTree, WatcherManager, FileOperations}
  alias RubberDuckWeb.Presence
  alias Phoenix.PubSub
  
  require Logger
  
  on_mount {RubberDuckWeb.LiveUserAuth, :live_user_required}
  
  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    if connected?(socket) do
      # Load project and verify access
      case load_and_authorize_project(project_id, socket.assigns.current_user) do
        {:ok, project} ->
          # Subscribe to file events
          topic = "file_watcher:#{project_id}"
          PubSub.subscribe(RubberDuck.PubSub, topic)
          
          # Join presence tracking
          presence_topic = "project_files:#{project_id}"
          {:ok, _} = Presence.track(self(), presence_topic, socket.assigns.current_user.id, %{
            username: socket.assigns.current_user.username,
            joined_at: DateTime.utc_now()
          })
          
          # Subscribe to presence events
          PubSub.subscribe(RubberDuck.PubSub, presence_topic)
          
          # Ensure file watcher is running
          ensure_file_watcher(project)
          
          # Load initial file tree
          file_tree = FileTree.build_tree(project.root_path)
          
          socket =
            socket
            |> assign(:project, project)
            |> assign(:file_tree, file_tree)
            |> assign(:selected_files, MapSet.new())
            |> assign(:expanded_folders, MapSet.new(["/"]))
            |> assign(:users_present, %{})
            |> assign(:file_operations, %{
              creating: false,
              renaming: nil,
              deleting: nil
            })
            |> assign(:search_query, nil)
            |> assign(:loading, false)
            |> assign(:error, nil)
            |> assign(:presence_topic, presence_topic)
            |> assign(:lazy_load_paths, MapSet.new())
            |> assign(:performance_mode, should_use_performance_mode?(file_tree))
            |> handle_presence()
          
          {:ok, socket}
          
        {:error, reason} ->
          socket =
            socket
            |> put_flash(:error, "Unable to access project: #{reason}")
            |> redirect(to: ~p"/")
          
          {:ok, socket}
      end
    else
      {:ok, assign(socket, :loading, true)}
    end
  end
  
  @impl true
  def handle_event("toggle_folder", %{"path" => path}, socket) do
    expanded = socket.assigns.expanded_folders
    
    {expanded, socket} = 
      if MapSet.member?(expanded, path) do
        {MapSet.delete(expanded, path), socket}
      else
        # Load children if not already loaded (lazy loading)
        socket = ensure_children_loaded(socket, path)
        {MapSet.put(expanded, path), socket}
      end
    
    {:noreply, assign(socket, :expanded_folders, expanded)}
  end
  
  def handle_event("select_file", %{"path" => path, "multi" => multi}, socket) do
    selected = socket.assigns.selected_files
    
    selected =
      cond do
        multi == "true" ->
          if MapSet.member?(selected, path) do
            MapSet.delete(selected, path)
          else
            MapSet.put(selected, path)
          end
          
        true ->
          MapSet.new([path])
      end
    
    {:noreply, assign(socket, :selected_files, selected)}
  end
  
  def handle_event("create_file", %{"type" => type, "parent" => parent_path}, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :creating, %{
      type: type,
      parent: parent_path
    })
    
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("confirm_create", %{"name" => name}, socket) do
    case socket.assigns.file_operations.creating do
      %{type: type, parent: parent_path} ->
        result = create_file_or_folder(
          socket.assigns.project,
          parent_path,
          name,
          type
        )
        
        socket = case result do
          {:ok, _} ->
            socket
            |> put_flash(:info, "#{String.capitalize(type)} created successfully")
            |> assign(:file_operations, Map.put(socket.assigns.file_operations, :creating, false))
            
          {:error, reason} ->
            put_flash(socket, :error, "Failed to create #{type}: #{reason}")
        end
        
        {:noreply, socket}
        
      _ ->
        {:noreply, socket}
    end
  end
  
  def handle_event("cancel_create", _params, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :creating, false)
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("rename_file", %{"path" => path}, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :renaming, path)
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("confirm_rename", %{"name" => new_name}, socket) do
    case socket.assigns.file_operations.renaming do
      nil -> 
        {:noreply, socket}
        
      old_path ->
        result = rename_file(socket.assigns.project, old_path, new_name)
        
        socket = case result do
          {:ok, _} ->
            socket
            |> put_flash(:info, "File renamed successfully")
            |> assign(:file_operations, Map.put(socket.assigns.file_operations, :renaming, nil))
            
          {:error, reason} ->
            put_flash(socket, :error, "Failed to rename: #{reason}")
        end
        
        {:noreply, socket}
    end
  end
  
  def handle_event("cancel_rename", _params, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :renaming, nil)
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("delete_file", %{"path" => path}, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :deleting, path)
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("confirm_delete", _params, socket) do
    case socket.assigns.file_operations.deleting do
      nil ->
        {:noreply, socket}
        
      path ->
        result = delete_file(socket.assigns.project, path)
        
        socket = case result do
          {:ok, _} ->
            socket
            |> put_flash(:info, "File deleted successfully")
            |> assign(:file_operations, Map.put(socket.assigns.file_operations, :deleting, nil))
            |> assign(:selected_files, MapSet.delete(socket.assigns.selected_files, path))
            
          {:error, reason} ->
            put_flash(socket, :error, "Failed to delete: #{reason}")
        end
        
        {:noreply, socket}
    end
  end
  
  def handle_event("cancel_delete", _params, socket) do
    file_operations = Map.put(socket.assigns.file_operations, :deleting, nil)
    {:noreply, assign(socket, :file_operations, file_operations)}
  end
  
  def handle_event("search", %{"query" => query}, socket) do
    query = if query == "", do: nil, else: query
    {:noreply, assign(socket, :search_query, query)}
  end
  
  def handle_event("key_pressed", %{"key" => key, "ctrlKey" => ctrl, "metaKey" => meta}, socket) do
    cmd_key = ctrl or meta
    
    case {key, cmd_key} do
      {"n", true} ->
        # Ctrl/Cmd+N - New file
        if socket.assigns.selected_files |> MapSet.to_list() |> List.first() do
          selected_path = socket.assigns.selected_files |> MapSet.to_list() |> List.first()
          parent = if is_directory?(selected_path, socket.assigns.file_tree), 
            do: selected_path, 
            else: Path.dirname(selected_path)
          
          handle_event("create_file", %{"type" => "file", "parent" => parent}, socket)
        else
          {:noreply, socket}
        end
        
      {"Delete", false} ->
        # Delete key - Delete selected file
        if socket.assigns.selected_files |> MapSet.to_list() |> List.first() do
          selected_path = socket.assigns.selected_files |> MapSet.to_list() |> List.first()
          handle_event("delete_file", %{"path" => selected_path}, socket)
        else
          {:noreply, socket}
        end
        
      {"F2", false} ->
        # F2 - Rename selected file
        if socket.assigns.selected_files |> MapSet.to_list() |> List.first() do
          selected_path = socket.assigns.selected_files |> MapSet.to_list() |> List.first()
          handle_event("rename_file", %{"path" => selected_path}, socket)
        else
          {:noreply, socket}
        end
        
      _ ->
        {:noreply, socket}
    end
  end
  
  def handle_event("open_file", %{"path" => path}, socket) do
    # Broadcast file open event for integration with editor
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{socket.assigns.project.id}:editor",
      {:open_file, %{path: path, user_id: socket.assigns.current_user.id}}
    )
    
    {:noreply, put_flash(socket, :info, "Opening #{Path.basename(path)}...")}
  end
  
  @impl true
  def handle_info(%{event: :file_changed, changes: changes}, socket) do
    # Update file tree with changes
    file_tree = apply_changes_to_tree(socket.assigns.file_tree, changes, socket.assigns.project.root_path)
    
    # Update activity in watcher manager
    WatcherManager.touch_activity(socket.assigns.project.id)
    
    {:noreply, assign(socket, :file_tree, file_tree)}
  end
  
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    socket = handle_presence_diff(socket, diff)
    {:noreply, socket}
  end
  
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end
  
  # Private functions
  
  defp load_and_authorize_project(project_id, user) do
    # The authorization happens through Ash policies
    case Workspace.get_project(project_id, actor: user) do
      {:ok, project} ->
        {:ok, project}
        
      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, "Project not found"}
        
      {:error, %Ash.Error.Forbidden{}} ->
        {:error, "You don't have access to this project"}
        
      error ->
        Logger.error("Failed to load project: #{inspect(error)}")
        {:error, "Unable to load project"}
    end
  end
  
  
  defp ensure_file_watcher(project) do
    case WatcherManager.start_watcher(project.id, %{root_path: project.root_path}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> 
        Logger.warning("Failed to start file watcher: #{inspect(error)}")
        error
    end
  end
  
  defp handle_presence(socket) do
    users = Presence.list(socket.assigns.presence_topic)
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      {user_id, meta}
    end)
    |> Enum.into(%{})
    
    assign(socket, :users_present, users)
  end
  
  defp handle_presence_diff(socket, %{joins: joins, leaves: leaves}) do
    users = socket.assigns.users_present
    
    users = 
      users
      |> Map.drop(Map.keys(leaves))
      |> Map.merge(
        joins
        |> Enum.map(fn {user_id, %{metas: [meta | _]}} -> {user_id, meta} end)
        |> Enum.into(%{})
      )
    
    assign(socket, :users_present, users)
  end
  
  defp apply_changes_to_tree(tree, changes, root_path) do
    Enum.reduce(changes, tree, fn change, acc_tree ->
      case change do
        %{type: :created, path: path} ->
          FileTree.add_path(acc_tree, path, root_path)
          
        %{type: :deleted, path: path} ->
          FileTree.remove_path(acc_tree, path)
          
        %{type: :renamed, path: old_path, new_path: new_path} ->
          acc_tree
          |> FileTree.remove_path(old_path)
          |> FileTree.add_path(new_path, root_path)
          
        _ ->
          acc_tree
      end
    end)
  end
  
  defp create_file_or_folder(project, parent_path, name, type) do
    type_atom = String.to_atom(type)
    FileOperations.create(project, parent_path, name, type_atom)
  end
  
  defp rename_file(project, old_path, new_name) do
    FileOperations.rename(project, old_path, new_name)
  end
  
  defp delete_file(project, path) do
    FileOperations.delete(project, path)
  end
  
  defp is_directory?(path, tree) do
    find_node_by_path(tree, path).type == :directory
  end
  
  defp find_node_by_path(tree, "/"), do: tree
  
  defp find_node_by_path(tree, path) do
    segments = Path.split(path)
    do_find_node(tree, segments)
  end
  
  defp do_find_node(node, []), do: node
  
  defp do_find_node(node, [name | rest]) do
    case Enum.find(node[:children] || [], &(&1.name == name)) do
      nil -> nil
      child -> do_find_node(child, rest)
    end
  end
  
  defp should_use_performance_mode?(tree) do
    # Enable performance mode for large file trees
    count_nodes(tree) > 1000
  end
  
  defp count_nodes(node) do
    children_count = 
      (node[:children] || [])
      |> Enum.map(&count_nodes/1)
      |> Enum.sum()
    
    1 + children_count
  end
  
  defp ensure_children_loaded(socket, path) do
    if socket.assigns.performance_mode and not MapSet.member?(socket.assigns.lazy_load_paths, path) do
      # In performance mode, load children on demand
      case load_directory_contents(socket.assigns.project, path) do
        {:ok, children} ->
          # Update the tree with loaded children
          file_tree = update_tree_children(socket.assigns.file_tree, path, children)
          
          socket
          |> assign(:file_tree, file_tree)
          |> assign(:lazy_load_paths, MapSet.put(socket.assigns.lazy_load_paths, path))
          
        {:error, _} ->
          socket
      end
    else
      socket
    end
  end
  
  defp load_directory_contents(project, path) do
    full_path = Path.join(project.root_path, path)
    
    case File.ls(full_path) do
      {:ok, entries} ->
        children = 
          entries
          |> Enum.take(100)  # Limit to 100 entries per directory in performance mode
          |> Enum.map(fn entry ->
            entry_path = Path.join(full_path, entry)
            relative_path = Path.join(path, entry)
            
            case File.stat(entry_path) do
              {:ok, %File.Stat{type: :directory}} ->
                %{
                  name: entry,
                  path: relative_path,
                  type: :directory,
                  children: []  # Lazy load children
                }
                
              {:ok, stat} ->
                %{
                  name: entry,
                  path: relative_path,
                  type: :file,
                  size: stat.size,
                  modified: stat.mtime |> elem(0) |> DateTime.from_unix!()
                }
                
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(fn node ->
            {node.type != :directory, String.downcase(node.name)}
          end)
          
        {:ok, children}
        
      error -> error
    end
  end
  
  defp update_tree_children(tree, "/", children) do
    Map.put(tree, :children, children)
  end
  
  defp update_tree_children(tree, path, children) do
    segments = Path.split(path)
    do_update_tree_children(tree, segments, children)
  end
  
  defp do_update_tree_children(tree, [name], children) do
    updated_children = 
      (tree[:children] || [])
      |> Enum.map(fn child ->
        if child.name == name do
          Map.put(child, :children, children)
        else
          child
        end
      end)
      
    Map.put(tree, :children, updated_children)
  end
  
  defp do_update_tree_children(tree, [name | rest], children) do
    updated_children = 
      (tree[:children] || [])
      |> Enum.map(fn child ->
        if child.name == name do
          do_update_tree_children(child, rest, children)
        else
          child
        end
      end)
      
    Map.put(tree, :children, updated_children)
  end
  
  # Component functions
  
  defp file_tree_node(assigns) do
    filtered = filter_tree_node(assigns.node, assigns.search_query)
    
    if filtered do
      if assigns.node.type == :directory do
        assigns = assign(assigns, :filtered, filtered)
        ~H"""
        <div>
          <div
            class={"flex items-center px-2 py-1 hover:bg-gray-100 dark:hover:bg-gray-800 rounded cursor-pointer group #{if MapSet.member?(@selected_files, @path), do: "bg-blue-50 dark:bg-blue-900/20"}"}
            phx-click="toggle_folder"
            phx-value-path={@path}
          >
            <.icon
              name={if MapSet.member?(@expanded_folders, @path), do: "hero-chevron-down", else: "hero-chevron-right"}
              class="w-4 h-4 mr-1 text-gray-400"
            />
            <.icon name="hero-folder" class="w-4 h-4 mr-2 text-yellow-500" />
            <span class="flex-1 text-sm"><%= @node.name %></span>
            
            <!-- Folder Actions -->
            <div class="hidden group-hover:flex items-center space-x-1">
              <button
                type="button"
                phx-click="create_file"
                phx-value-type="file"
                phx-value-parent={@path}
                class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                title="New file"
              >
                <.icon name="hero-document-plus" class="w-4 h-4" />
              </button>
              <button
                type="button"
                phx-click="create_file"
                phx-value-type="folder"
                phx-value-parent={@path}
                class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                title="New folder"
              >
                <.icon name="hero-folder-plus" class="w-4 h-4" />
              </button>
            </div>
          </div>
          
          <%= if MapSet.member?(@expanded_folders, @path) do %>
            <div class="ml-4">
              <%= for child <- limited_children(@node[:children] || [], @performance_mode) do %>
                <.file_tree_node
                  node={child}
                  path={Path.join(@path, child.name)}
                  expanded_folders={@expanded_folders}
                  selected_files={@selected_files}
                  file_operations={@file_operations}
                  search_query={@search_query}
                  performance_mode={@performance_mode}
                  myself={@myself}
                />
              <% end %>
              <%= if @performance_mode && length(@node[:children] || []) > 50 do %>
                <div class="ml-2 text-xs text-gray-500 italic">
                  ... and <%= length(@node[:children] || []) - 50 %> more items
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        """
      else
        assigns = assign(assigns, :filtered, filtered)
        ~H"""
        <div
          class={"flex items-center px-2 py-1 hover:bg-gray-100 dark:hover:bg-gray-800 rounded cursor-pointer group #{if MapSet.member?(@selected_files, @path), do: "bg-blue-50 dark:bg-blue-900/20"}"}
          phx-click="select_file"
          phx-value-path={@path}
          phx-value-multi={false}
          phx-dblclick="open_file"
          phx-value-path={@path}
        >
          <.icon name={file_icon(@node.name)} class={"w-4 h-4 mr-2 #{file_icon_color(@node.name)}"} />
          <span class="flex-1 text-sm"><%= highlight_search(@node.name, @search_query) %></span>
          
          <!-- File Actions -->
          <div class="hidden group-hover:flex items-center space-x-1">
            <button
              type="button"
              phx-click="rename_file"
              phx-value-path={@path}
              class="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              title="Rename"
            >
              <.icon name="hero-pencil" class="w-4 h-4" />
            </button>
            <button
              type="button"
              phx-click="delete_file"
              phx-value-path={@path}
              class="p-1 text-gray-400 hover:text-red-600 dark:hover:text-red-400"
              title="Delete"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>
        """
      end
    else
      ~H"""
      """
    end
  end
  
  defp filter_tree_node(node, nil), do: node
  defp filter_tree_node(node, query) do
    query = String.downcase(query)
    
    if node.type == :directory do
      # Check if any children match
      children = (node[:children] || [])
      |> Enum.any?(fn child -> 
        String.contains?(String.downcase(child.name), query) or
        (child.type == :directory and filter_tree_node(child, query))
      end)
      
      if children, do: node, else: nil
    else
      # Check if file name matches
      if String.contains?(String.downcase(node.name), query), do: node, else: nil
    end
  end
  
  defp file_icon(name) do
    cond do
      String.ends_with?(name, [".ex", ".exs"]) -> "hero-beaker"
      String.ends_with?(name, [".js", ".jsx", ".ts", ".tsx"]) -> "hero-code-bracket"
      String.ends_with?(name, [".css", ".scss", ".sass"]) -> "hero-paint-brush"
      String.ends_with?(name, [".html", ".heex"]) -> "hero-globe-alt"
      String.ends_with?(name, [".json", ".yaml", ".yml"]) -> "hero-cog"
      String.ends_with?(name, [".md", ".txt"]) -> "hero-document-text"
      String.ends_with?(name, [".jpg", ".png", ".gif", ".svg"]) -> "hero-photo"
      true -> "hero-document"
    end
  end
  
  defp file_icon_color(name) do
    cond do
      String.ends_with?(name, [".ex", ".exs"]) -> "text-purple-500"
      String.ends_with?(name, [".js", ".jsx", ".ts", ".tsx"]) -> "text-yellow-500"
      String.ends_with?(name, [".css", ".scss", ".sass"]) -> "text-blue-500"
      String.ends_with?(name, [".html", ".heex"]) -> "text-orange-500"
      String.ends_with?(name, [".json", ".yaml", ".yml"]) -> "text-gray-500"
      String.ends_with?(name, [".md", ".txt"]) -> "text-gray-600"
      String.ends_with?(name, [".jpg", ".png", ".gif", ".svg"]) -> "text-green-500"
      true -> "text-gray-400"
    end
  end
  
  defp highlight_search(text, nil), do: text
  defp highlight_search(text, query) do
    if String.contains?(String.downcase(text), String.downcase(query)) do
      parts = String.split(text, ~r/#{Regex.escape(query)}/i, include_captures: true)
      
      assigns = %{parts: parts, query: query}
      
      ~H"""
      <%= for part <- @parts do %><%= if String.downcase(part) == String.downcase(@query) do %><mark class="bg-yellow-200 dark:bg-yellow-800"><%= part %></mark><% else %><%= part %><% end %><% end %>
      """
    else
      text
    end
  end
  
  defp limited_children(children, true) when length(children) > 50 do
    Enum.take(children, 50)
  end
  
  defp limited_children(children, _), do: children
end