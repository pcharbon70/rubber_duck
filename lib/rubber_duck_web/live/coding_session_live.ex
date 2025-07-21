defmodule RubberDuckWeb.CodingSessionLive do
  @moduledoc """
  Main LiveView coordinator for the collaborative coding interface.
  
  Provides a chat-centric interface with toggleable file tree and editor panels,
  real-time collaboration features, and AI-powered assistance.
  """
  
  use RubberDuckWeb, :live_view
  
  require Logger
  
  alias Phoenix.PubSub
  alias RubberDuckWeb.Presence
  
  # Require authentication
  on_mount {RubberDuckWeb.LiveUserAuth, :live_user_required}
  
  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    user = socket.assigns.current_user
    
    if connected?(socket) do
      # Subscribe to PubSub topics
      subscribe_to_project_updates(project_id)
      
      # Track presence
      track_user_presence(project_id, user)
      
      # Set up periodic presence updates
      :timer.send_interval(30_000, self(), :update_presence)
    end
    
    socket =
      socket
      |> assign(:page_title, "Coding Session")
      |> assign(:project_id, project_id)
      |> assign(:user, user)
      |> assign_initial_state()
      |> assign_layout_preferences()
      |> fetch_project_data()
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="coding-session h-screen flex flex-col bg-gray-50" phx-window-keydown="window_keydown">
      <!-- Header -->
      <header class="bg-white shadow-sm border-b border-gray-200 px-4 py-2">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <h1 class="text-lg font-semibold text-gray-900">
              <%= @project_name %>
            </h1>
            <.connection_status status={@connection_status} />
          </div>
          
          <div class="flex items-center space-x-2">
            <.panel_toggles layout={@layout} />
            <.user_presence users={@presence_users} current_user={@user} />
          </div>
        </div>
      </header>
      
      <!-- Main Content -->
      <div class="flex-1 flex overflow-hidden">
        <!-- File Tree Panel (Left) -->
        <%= if @layout.show_file_tree do %>
          <aside class={"#{@layout.tree_width} bg-white border-r border-gray-200 overflow-hidden flex flex-col"}>
            <div class="p-4 border-b border-gray-200">
              <h2 class="text-sm font-medium text-gray-700">Files</h2>
            </div>
            <div class="flex-1 overflow-y-auto p-2">
              <.file_tree_placeholder />
            </div>
          </aside>
        <% end %>
        
        <!-- Chat Panel (Center - Primary) -->
        <main class={@layout.chat_width <> " bg-white flex flex-col"}>
          <div class="flex-1 overflow-hidden flex flex-col">
            <!-- Chat Messages -->
            <div class="flex-1 overflow-y-auto p-4" id="chat-messages" phx-hook="ChatScroll">
              <div class="space-y-4">
                <%= for message <- @chat_messages do %>
                  <.chat_message message={message} current_user={@user} />
                <% end %>
                
                <%= if @streaming_message do %>
                  <.streaming_message message={@streaming_message} />
                <% end %>
              </div>
            </div>
            
            <!-- Chat Input -->
            <div class="border-t border-gray-200 p-4">
              <form phx-submit="send_message" class="flex space-x-2">
                <input
                  type="text"
                  name="message"
                  value={@chat_input}
                  phx-change="update_chat_input"
                  placeholder="Type a message or / for commands..."
                  class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                  phx-keydown="chat_keydown"
                />
                <button
                  type="submit"
                  disabled={@chat_input == ""}
                  class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Send
                </button>
              </form>
            </div>
          </div>
        </main>
        
        <!-- Editor Panel (Right) -->
        <%= if @layout.show_editor do %>
          <aside class={"#{@layout.editor_width} bg-white border-l border-gray-200 overflow-hidden flex flex-col"}>
            <div class="p-4 border-b border-gray-200">
              <h2 class="text-sm font-medium text-gray-700">
                <%= @current_file || "No file selected" %>
              </h2>
            </div>
            <div class="flex-1 overflow-hidden">
              <.editor_placeholder />
            </div>
          </aside>
        <% end %>
      </div>
      
      <!-- Loading Overlay -->
      <%= if @loading do %>
        <.loading_overlay />
      <% end %>
    </div>
    """
  end
  
  # Event Handlers
  
  @impl true
  def handle_event("window_keydown", %{"key" => key, "ctrlKey" => true}, socket) do
    socket = handle_keyboard_shortcut(key, socket)
    {:noreply, socket}
  end
  
  def handle_event("toggle_panel", %{"panel" => panel}, socket) do
    layout = update_layout_visibility(socket.assigns.layout, panel)
    {:noreply, assign(socket, :layout, layout)}
  end
  
  def handle_event("send_message", %{"message" => content}, socket) do
    socket = 
      socket
      |> send_chat_message(content)
      |> assign(:chat_input, "")
    
    {:noreply, socket}
  end
  
  def handle_event("update_chat_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :chat_input, value)}
  end
  
  def handle_event("chat_keydown", %{"key" => "Enter", "shiftKey" => true}, socket) do
    # Allow multiline with Shift+Enter
    {:noreply, socket}
  end
  
  # PubSub Handlers
  
  @impl true
  def handle_info({:project_update, update}, socket) do
    socket = apply_project_update(socket, update)
    {:noreply, socket}
  end
  
  def handle_info({:chat_message, message}, socket) do
    socket = append_chat_message(socket, message)
    {:noreply, socket}
  end
  
  def handle_info({:editor_update, update}, socket) do
    socket = apply_editor_update(socket, update)
    {:noreply, socket}
  end
  
  def handle_info({:presence_diff, diff}, socket) do
    socket = handle_presence_diff(socket, diff)
    {:noreply, socket}
  end
  
  def handle_info(:update_presence, socket) do
    Presence.update(
      self(),
      "project:#{socket.assigns.project_id}",
      socket.assigns.user.id,
      %{
        online_at: System.system_time(:second),
        current_file: socket.assigns.current_file
      }
    )
    {:noreply, socket}
  end
  
  # Private Functions
  
  defp assign_initial_state(socket) do
    socket
    |> assign(:project_name, "Loading...")
    |> assign(:current_file, nil)
    |> assign(:file_tree, [])
    |> assign(:chat_messages, [])
    |> assign(:chat_input, "")
    |> assign(:editor_content, "")
    |> assign(:presence_users, %{})
    |> assign(:streaming_message, nil)
    |> assign(:connection_status, :connected)
    |> assign(:loading, false)
  end
  
  defp assign_layout_preferences(socket) do
    # TODO: Load from user preferences
    layout = %{
      show_file_tree: true,
      show_editor: true,
      chat_width: calculate_chat_width(true, true),
      tree_width: "w-64",
      editor_width: "w-1/2"
    }
    
    assign(socket, :layout, layout)
  end
  
  defp calculate_chat_width(show_tree, show_editor) do
    case {show_tree, show_editor} do
      {false, false} -> "flex-1"
      {true, false} -> "flex-1"
      {false, true} -> "flex-1"
      {true, true} -> "flex-1"
    end
  end
  
  defp subscribe_to_project_updates(project_id) do
    PubSub.subscribe(RubberDuck.PubSub, "project:#{project_id}")
    PubSub.subscribe(RubberDuck.PubSub, "editor:#{project_id}")
    PubSub.subscribe(RubberDuck.PubSub, "chat:#{project_id}")
  end
  
  defp track_user_presence(project_id, user) do
    {:ok, _} = Presence.track(
      self(),
      "project:#{project_id}",
      user.id,
      %{
        username: user.username,
        email: user.email,
        online_at: System.system_time(:second),
        current_file: nil
      }
    )
  end
  
  defp fetch_project_data(socket) do
    # TODO: Implement actual project data fetching
    socket
    |> assign(:project_name, "Sample Project")
    |> assign(:file_tree, [
      %{id: "1", name: "src", type: :folder, children: []},
      %{id: "2", name: "README.md", type: :file}
    ])
  end
  
  defp handle_keyboard_shortcut("f", socket) do
    # Ctrl+F: Toggle file tree
    update_in(socket.assigns.layout.show_file_tree, &(!&1))
    |> recalculate_layout()
  end
  
  defp handle_keyboard_shortcut("e", socket) do
    # Ctrl+E: Toggle editor
    update_in(socket.assigns.layout.show_editor, &(!&1))
    |> recalculate_layout()
  end
  
  defp handle_keyboard_shortcut("/", socket) do
    # Ctrl+/: Focus chat input
    push_event(socket, "focus_chat", %{})
  end
  
  defp handle_keyboard_shortcut(_, socket), do: socket
  
  defp recalculate_layout(socket) do
    layout = socket.assigns.layout
    chat_width = calculate_chat_width(layout.show_file_tree, layout.show_editor)
    put_in(socket.assigns.layout.chat_width, chat_width)
  end
  
  defp update_layout_visibility(layout, "file_tree") do
    Map.put(layout, :show_file_tree, !layout.show_file_tree)
  end
  
  defp update_layout_visibility(layout, "editor") do
    Map.put(layout, :show_editor, !layout.show_editor)
  end
  
  defp send_chat_message(socket, content) do
    message = %{
      id: Ecto.UUID.generate(),
      user_id: socket.assigns.user.id,
      username: socket.assigns.user.username,
      content: content,
      timestamp: DateTime.utc_now(),
      type: determine_message_type(content)
    }
    
    # Broadcast to all users
    PubSub.broadcast(
      RubberDuck.PubSub,
      "chat:#{socket.assigns.project_id}",
      {:chat_message, message}
    )
    
    # Add to local state immediately
    append_chat_message(socket, message)
  end
  
  defp determine_message_type("/" <> _command), do: :command
  defp determine_message_type(_), do: :user
  
  defp append_chat_message(socket, message) do
    update(socket, :chat_messages, &(&1 ++ [message]))
  end
  
  defp apply_project_update(socket, update) do
    Logger.debug("Received project update: #{inspect(update)}")
    socket
  end
  
  defp apply_editor_update(socket, update) do
    Logger.debug("Received editor update: #{inspect(update)}")
    socket
  end
  
  defp handle_presence_diff(socket, %{joins: joins, leaves: leaves}) do
    presence_users = 
      socket.assigns.presence_users
      |> Map.merge(joins)
      |> Map.drop(Map.keys(leaves))
    
    assign(socket, :presence_users, presence_users)
  end
  
  # Components
  
  defp connection_status(assigns) do
    ~H"""
    <div class="flex items-center space-x-2">
      <div class={[
        "w-2 h-2 rounded-full",
        @status == :connected && "bg-green-500",
        @status == :connecting && "bg-yellow-500 animate-pulse",
        @status == :disconnected && "bg-red-500"
      ]} />
      <span class="text-xs text-gray-600">
        <%= case @status do %>
          <% :connected -> %> Connected
          <% :connecting -> %> Connecting...
          <% :disconnected -> %> Disconnected
        <% end %>
      </span>
    </div>
    """
  end
  
  defp panel_toggles(assigns) do
    ~H"""
    <div class="flex items-center space-x-1">
      <button
        phx-click="toggle_panel"
        phx-value-panel="file_tree"
        class={[
          "p-2 rounded hover:bg-gray-100",
          @layout.show_file_tree && "bg-gray-100"
        ]}
        title="Toggle file tree (Ctrl+F)"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
        </svg>
      </button>
      
      <button
        phx-click="toggle_panel"
        phx-value-panel="editor"
        class={[
          "p-2 rounded hover:bg-gray-100",
          @layout.show_editor && "bg-gray-100"
        ]}
        title="Toggle editor (Ctrl+E)"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" />
        </svg>
      </button>
    </div>
    """
  end
  
  defp user_presence(assigns) do
    ~H"""
    <div class="flex items-center -space-x-2">
      <%= for {_id, %{metas: [meta | _]}} <- @users |> Enum.take(3) do %>
        <div
          class="w-8 h-8 rounded-full bg-indigo-500 border-2 border-white flex items-center justify-center"
          title={meta.username}
        >
          <span class="text-xs text-white font-medium">
            <%= String.first(meta.username) |> String.upcase() %>
          </span>
        </div>
      <% end %>
      
      <%= if map_size(@users) > 3 do %>
        <div class="w-8 h-8 rounded-full bg-gray-300 border-2 border-white flex items-center justify-center">
          <span class="text-xs text-gray-700 font-medium">
            +<%= map_size(@users) - 3 %>
          </span>
        </div>
      <% end %>
    </div>
    """
  end
  
  defp chat_message(assigns) do
    ~H"""
    <div class="flex space-x-3">
      <div class="flex-shrink-0">
        <div class="w-8 h-8 rounded-full bg-gray-400 flex items-center justify-center">
          <span class="text-xs text-white font-medium">
            <%= String.first(@message.username) |> String.upcase() %>
          </span>
        </div>
      </div>
      
      <div class="flex-1">
        <div class="flex items-baseline space-x-2">
          <span class="font-medium text-gray-900"><%= @message.username %></span>
          <span class="text-xs text-gray-500">
            <%= Calendar.strftime(@message.timestamp, "%H:%M") %>
          </span>
        </div>
        <div class="mt-1 text-gray-700">
          <%= @message.content %>
        </div>
      </div>
    </div>
    """
  end
  
  defp streaming_message(assigns) do
    ~H"""
    <div class="flex space-x-3">
      <div class="flex-shrink-0">
        <div class="w-8 h-8 rounded-full bg-indigo-500 flex items-center justify-center">
          <span class="text-xs text-white font-medium">AI</span>
        </div>
      </div>
      
      <div class="flex-1">
        <div class="flex items-baseline space-x-2">
          <span class="font-medium text-gray-900">Assistant</span>
          <span class="text-xs text-gray-500">typing...</span>
        </div>
        <div class="mt-1 text-gray-700">
          <%= @message.content %>
          <span class="inline-block w-2 h-4 bg-gray-400 animate-pulse"></span>
        </div>
      </div>
    </div>
    """
  end
  
  defp file_tree_placeholder(assigns) do
    ~H"""
    <div class="text-sm text-gray-500 italic p-4">
      File tree component will be implemented in Phase 12.3
    </div>
    """
  end
  
  defp editor_placeholder(assigns) do
    ~H"""
    <div class="text-sm text-gray-500 italic p-4">
      Editor component will be implemented in Phase 12.4
    </div>
    """
  end
  
  defp loading_overlay(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 shadow-xl">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600 mx-auto"></div>
        <p class="mt-4 text-gray-700">Loading...</p>
      </div>
    </div>
    """
  end
end