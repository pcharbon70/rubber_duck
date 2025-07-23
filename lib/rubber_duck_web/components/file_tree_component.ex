defmodule RubberDuckWeb.Components.FileTreeComponent do
  @moduledoc """
  An interactive file tree component for project navigation.

  Features:
  - Recursive folder structure display with expand/collapse
  - File type icons and visual indicators
  - File selection and multi-selection support
  - Search and filter capabilities
  - Real-time updates via PubSub
  - Keyboard navigation
  - Git status integration
  """
  use RubberDuckWeb, :live_component

  alias Phoenix.PubSub

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       tree_nodes: [],
       expanded_paths: MapSet.new(),
       selected_paths: MapSet.new(),
       active_path: nil,
       search_query: "",
       filter_extensions: [],
       show_hidden: false,
       show_search: false,
       loading: true,
       error: nil,
       git_status: %{}
     )
     |> assign_new(:project_id, fn -> nil end)
     |> assign_new(:current_file, fn -> nil end)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_load_tree()
      |> maybe_subscribe()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="file-tree-component h-full flex flex-col bg-white dark:bg-gray-900" id={@id}>
      <!-- Header -->
      <div class="file-tree-header px-3 py-2 border-b border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between mb-2">
          <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300">
            Files
          </h3>
          <div class="flex items-center gap-1">
            <button
              class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-800"
              phx-click="toggle_search"
              phx-target={@myself}
              title="Search files (Ctrl+P)"
            >
              🔍
            </button>
            <button
              class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-800"
              phx-click="refresh_tree"
              phx-target={@myself}
              title="Refresh file tree"
            >
              🔄
            </button>
            <button
              class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-800"
              phx-click="toggle_hidden"
              phx-target={@myself}
              title={if @show_hidden, do: "Hide hidden files", else: "Show hidden files"}
            >
              <%= if @show_hidden, do: "👁", else: "👁‍🗨" %>
            </button>
          </div>
        </div>
        
        <!-- Search Input -->
        <div :if={@show_search} class="relative">
          <input
            type="text"
            name="search"
            value={@search_query}
            phx-change="search_files"
            phx-target={@myself}
            phx-debounce="300"
            placeholder="Search files..."
            class="w-full px-2 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-800 dark:text-gray-100"
            id={"#{@id}-search"}
            phx-hook="FocusOnMount"
          />
          <button
            :if={@search_query != ""}
            class="absolute right-1 top-1 p-0.5 text-gray-400 hover:text-gray-600"
            phx-click="clear_search"
            phx-target={@myself}
          >
            ✕
          </button>
        </div>
      </div>
      
      <!-- Tree Content -->
      <div 
        class="file-tree-content flex-1 overflow-y-auto px-1 py-1"
        phx-keydown="tree_keydown"
        phx-target={@myself}
        tabindex="0"
      >
        <%= if @loading do %>
          <div class="flex items-center justify-center py-8">
            <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-500"></div>
          </div>
        <% else %>
          <%= if @error do %>
            <div class="px-3 py-2 text-sm text-red-600 dark:text-red-400">
              <%= @error %>
            </div>
          <% else %>
            <%= if @tree_nodes == [] do %>
              <div class="px-3 py-2 text-sm text-gray-500 dark:text-gray-400 italic">
                No files found
              </div>
            <% else %>
              <div class="tree-nodes">
                <%= for node <- filter_nodes(@tree_nodes, @search_query, @filter_extensions, @show_hidden) do %>
                  <.tree_node 
                    node={node} 
                    level={0}
                    expanded_paths={@expanded_paths}
                    selected_paths={@selected_paths}
                    active_path={@active_path}
                    current_file={@current_file}
                    git_status={@git_status}
                    search_query={@search_query}
                    show_hidden={@show_hidden}
                    filter_extensions={@filter_extensions}
                    myself={@myself}
                  />
                <% end %>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
      
      <!-- Status Bar -->
      <div class="file-tree-status px-3 py-1 border-t border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between text-xs text-gray-500 dark:text-gray-400">
          <span>
            <%= count_visible_files(@tree_nodes, @search_query, @filter_extensions, @show_hidden) %> files
          </span>
          <span :if={@selected_paths != MapSet.new()}>
            <%= MapSet.size(@selected_paths) %> selected
          </span>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("toggle_search", _params, socket) do
    socket =
      socket
      |> update(:show_search, &(!&1))
      |> assign(:search_query, "")

    if socket.assigns.show_search do
      {:noreply, push_event(socket, "focus", %{id: "#{socket.assigns.id}-search"})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search_files", %{"search" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, :search_query, "")}
  end

  @impl true
  def handle_event("toggle_hidden", _params, socket) do
    {:noreply, update(socket, :show_hidden, &(!&1))}
  end

  @impl true
  def handle_event("refresh_tree", _params, socket) do
    {:noreply, load_file_tree(socket)}
  end

  @impl true
  def handle_event("toggle_node", %{"path" => path}, socket) do
    expanded_paths =
      if MapSet.member?(socket.assigns.expanded_paths, path) do
        MapSet.delete(socket.assigns.expanded_paths, path)
      else
        MapSet.put(socket.assigns.expanded_paths, path)
      end

    {:noreply, assign(socket, :expanded_paths, expanded_paths)}
  end

  @impl true
  def handle_event("select_file", %{"path" => path} = params, socket) do
    shift_key = params["shiftKey"] == "true"
    ctrl_key = params["ctrlKey"] == "true" || params["metaKey"] == "true"

    socket = handle_file_selection(socket, path, shift_key, ctrl_key)

    # Notify parent about file selection
    send(self(), {:file_selected, path})

    {:noreply, socket}
  end

  @impl true
  def handle_event("tree_keydown", %{"key" => key} = params, socket) do
    socket = handle_keyboard_navigation(socket, key, params)
    {:noreply, socket}
  end

  # Public Functions

  @doc """
  Updates the file tree data from the parent LiveView.
  """
  def update_tree_data(component_id, tree_nodes, git_status) do
    send_update(__MODULE__,
      id: component_id,
      tree_nodes: tree_nodes,
      git_status: git_status,
      loading: false,
      error: nil
    )
  end

  @doc """
  Updates the file tree with an error from the parent LiveView.
  """
  def update_tree_error(component_id, error) do
    send_update(__MODULE__,
      id: component_id,
      error: error,
      loading: false
    )
  end

  # Private Functions

  defp maybe_load_tree(socket) do
    if socket.assigns.project_id && socket.assigns.tree_nodes == [] do
      load_file_tree(socket)
    else
      socket
    end
  end

  defp maybe_subscribe(socket) do
    if connected?(socket) && socket.assigns.project_id do
      PubSub.subscribe(RubberDuck.PubSub, "project:#{socket.assigns.project_id}:files")
    end

    socket
  end

  defp load_file_tree(socket) do
    project_id = socket.assigns.project_id

    if project_id do
      # Request the parent LiveView to load the file tree
      send(self(), {:load_file_tree, socket.assigns.id, socket.assigns.show_hidden})

      socket
      |> assign(:loading, true)
      |> assign(:error, nil)
    else
      socket
      |> assign(:tree_nodes, [])
      |> assign(:loading, false)
      |> assign(:error, "No project selected")
    end
  end

  defp handle_file_selection(socket, path, shift_key, ctrl_key) do
    cond do
      ctrl_key ->
        # Toggle selection
        selected_paths =
          if MapSet.member?(socket.assigns.selected_paths, path) do
            MapSet.delete(socket.assigns.selected_paths, path)
          else
            MapSet.put(socket.assigns.selected_paths, path)
          end

        socket
        |> assign(:selected_paths, selected_paths)
        |> assign(:active_path, path)

      shift_key && socket.assigns.active_path ->
        # Range selection
        # TODO: Implement range selection logic
        socket
        |> assign(:active_path, path)

      true ->
        # Single selection
        socket
        |> assign(:selected_paths, MapSet.new([path]))
        |> assign(:active_path, path)
    end
  end

  defp handle_keyboard_navigation(socket, "ArrowDown", _params) do
    # TODO: Implement down navigation
    socket
  end

  defp handle_keyboard_navigation(socket, "ArrowUp", _params) do
    # TODO: Implement up navigation
    socket
  end

  defp handle_keyboard_navigation(socket, "ArrowRight", _params) do
    # Expand directory or move to first child
    if socket.assigns.active_path do
      case find_node_by_path(socket.assigns.tree_nodes, socket.assigns.active_path) do
        %{type: :directory} = node ->
          update(socket, :expanded_paths, &MapSet.put(&1, node.path))

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp handle_keyboard_navigation(socket, "ArrowLeft", _params) do
    # Collapse directory or move to parent
    if socket.assigns.active_path do
      case find_node_by_path(socket.assigns.tree_nodes, socket.assigns.active_path) do
        %{type: :directory} = node ->
          if MapSet.member?(socket.assigns.expanded_paths, node.path) do
            update(socket, :expanded_paths, &MapSet.delete(&1, node.path))
          else
            # Move to parent
            socket
          end

        _ ->
          # Move to parent
          socket
      end
    else
      socket
    end
  end

  defp handle_keyboard_navigation(socket, "Enter", _params) do
    if socket.assigns.active_path do
      send(self(), {:file_selected, socket.assigns.active_path})
    end

    socket
  end

  defp handle_keyboard_navigation(socket, _key, _params), do: socket

  defp filter_nodes(nodes, search_query, filter_extensions, show_hidden) do
    nodes
    |> Enum.filter(&should_show_node(&1, search_query, filter_extensions, show_hidden))
    |> Enum.map(fn node ->
      if node.type == :directory && node[:children] do
        %{node | children: filter_nodes(node.children, search_query, filter_extensions, show_hidden)}
      else
        node
      end
    end)
  end

  defp should_show_node(node, search_query, filter_extensions, show_hidden) do
    # Hidden file check
    if !show_hidden && String.starts_with?(node.name, ".") do
      false
    else
      # Search query check
      search_match =
        if search_query == "" do
          true
        else
          String.contains?(String.downcase(node.name), String.downcase(search_query))
        end

      # Extension filter check
      extension_match =
        if filter_extensions == [] || node.type == :directory do
          true
        else
          extension = Path.extname(node.name)
          Enum.member?(filter_extensions, extension)
        end

      search_match && extension_match
    end
  end

  defp find_node_by_path(nodes, path) do
    Enum.find_value(nodes, fn node ->
      if node.path == path do
        node
      else
        if node.type == :directory && node[:children] do
          find_node_by_path(node.children, path)
        end
      end
    end)
  end

  defp count_visible_files(nodes, search_query, filter_extensions, show_hidden) do
    nodes
    |> filter_nodes(search_query, filter_extensions, show_hidden)
    |> count_files_recursive()
  end

  defp count_files_recursive(nodes) do
    Enum.reduce(nodes, 0, fn node, acc ->
      if node.type == :file do
        acc + 1
      else
        acc + count_files_recursive(node[:children] || [])
      end
    end)
  end

  # Components

  defp tree_node(assigns) do
    ~H"""
    <div class="tree-node">
      <div
        class={[
          "tree-node-content flex items-center px-1 py-0.5 text-sm cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800 rounded",
          @active_path == @node.path && "bg-blue-50 dark:bg-blue-900/20",
          MapSet.member?(@selected_paths, @node.path) && "bg-blue-100 dark:bg-blue-900/30",
          @current_file == @node.path && "font-medium text-blue-600 dark:text-blue-400"
        ]}
        style={"padding-left: #{@level * 1.25}rem"}
        phx-click={if @node.type == :file, do: "select_file", else: "toggle_node"}
        phx-value-path={@node.path}
        phx-target={@myself}
      >
        <!-- Expand/Collapse Icon -->
        <%= if @node.type == :directory do %>
          <span
            class="inline-block w-4 h-4 mr-1 text-gray-400"
            phx-click="toggle_node"
            phx-value-path={@node.path}
            phx-target={@myself}
          >
            <%= if MapSet.member?(@expanded_paths, @node.path) do %>
              ▼
            <% else %>
              ▶
            <% end %>
          </span>
        <% else %>
          <span class="inline-block w-4 h-4 mr-1"></span>
        <% end %>
        
        <!-- File/Folder Icon -->
        <span class="mr-2">
          <%= file_icon(@node) %>
        </span>
        
        <!-- File Name -->
        <span class="flex-1 truncate">
          <%= highlight_search(@node.name, @search_query) %>
        </span>
        
        <!-- Git Status -->
        <%= if status = Map.get(@git_status, @node.path) do %>
          <span class="ml-1" title={git_status_title(status)}>
            <%= git_status_icon(status) %>
          </span>
        <% end %>
        
        <!-- File Size (for files) -->
        <%= if @node.type == :file && @node[:size] do %>
          <span class="ml-2 text-xs text-gray-500 dark:text-gray-400">
            <%= format_file_size(@node.size) %>
          </span>
        <% end %>
      </div>
      
      <!-- Children -->
      <%= if @node.type == :directory && MapSet.member?(@expanded_paths, @node.path) && @node[:children] do %>
        <div class="tree-node-children">
          <%= for child <- filter_nodes(@node.children, @search_query, @filter_extensions, @show_hidden) do %>
            <.tree_node 
              node={child} 
              level={@level + 1}
              expanded_paths={@expanded_paths}
              selected_paths={@selected_paths}
              active_path={@active_path}
              current_file={@current_file}
              git_status={@git_status}
              search_query={@search_query}
              show_hidden={@show_hidden}
              filter_extensions={@filter_extensions}
              myself={@myself}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper Functions

  defp file_icon(%{type: :directory}), do: "📁"

  defp file_icon(%{name: name}) do
    case Path.extname(name) do
      ".ex" -> "💧"
      ".exs" -> "💧"
      ".js" -> "📜"
      ".ts" -> "📘"
      ".json" -> "📋"
      ".md" -> "📝"
      ".txt" -> "📄"
      ".css" -> "🎨"
      ".html" -> "🌐"
      ".heex" -> "🌐"
      ".eex" -> "🌐"
      ".yml" -> "⚙️"
      ".yaml" -> "⚙️"
      ".toml" -> "⚙️"
      ".lock" -> "🔒"
      ".gitignore" -> "🚫"
      _ -> "📄"
    end
  end

  defp git_status_icon(:modified), do: "●"
  defp git_status_icon(:added), do: "+"
  defp git_status_icon(:deleted), do: "✕"
  defp git_status_icon(:renamed), do: "➜"
  defp git_status_icon(:untracked), do: "?"
  defp git_status_icon(_), do: nil

  defp git_status_title(:modified), do: "Modified"
  defp git_status_title(:added), do: "Added"
  defp git_status_title(:deleted), do: "Deleted"
  defp git_status_title(:renamed), do: "Renamed"
  defp git_status_title(:untracked), do: "Untracked"
  defp git_status_title(_), do: ""

  defp format_file_size(size) when size < 1024, do: "#{size} B"
  defp format_file_size(size) when size < 1024 * 1024, do: "#{Float.round(size / 1024, 1)} KB"
  defp format_file_size(size), do: "#{Float.round(size / 1024 / 1024, 1)} MB"

  defp highlight_search(text, ""), do: text

  defp highlight_search(text, query) do
    case :binary.match(String.downcase(text), String.downcase(query)) do
      {start, length} ->
        prefix = String.slice(text, 0, start)
        match = String.slice(text, start, length)
        suffix = String.slice(text, (start + length)..-1//1)

        assigns = %{prefix: prefix, match: match, suffix: suffix}

        ~H"""
        <%= @prefix %><span class="bg-yellow-200 dark:bg-yellow-700"><%= @match %></span><%= @suffix %>
        """

      :nomatch ->
        text
    end
  end
end
