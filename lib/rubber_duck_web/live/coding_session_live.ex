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
  alias RubberDuckWeb.Components.ChatPanelComponent
  alias RubberDuckWeb.Components.FileTreeComponent
  alias RubberDuckWeb.Components.MonacoEditorComponent
  alias RubberDuckWeb.Components.ContextPanelComponent
  alias RubberDuck.Projects.FileTree
  alias RubberDuck.Analysis.CodeAnalyzer
  alias RubberDuck.Analysis.MetricsCollector
  
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
    
    # Generate conversation ID for this project session
    conversation_id = "project-#{project_id}-#{Ecto.UUID.generate()}"
    
    socket =
      socket
      |> assign(:page_title, "Coding Session")
      |> assign(:project_id, project_id)
      |> assign(:user, user)
      |> assign(:conversation_id, conversation_id)
      |> assign(:conversation_connected, false)
      |> assign_initial_state()
      |> assign_layout_preferences()
      |> fetch_project_data()
    
    # Push event to join conversation channel after socket is established
    if connected?(socket) do
      {:ok, push_event(socket, "join_conversation", %{
        conversation_id: conversation_id,
        project_id: project_id
      })}
    else
      {:ok, socket}
    end
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="coding-session h-screen flex flex-col bg-gray-50" 
         phx-window-keydown="window_keydown"
         id="coding-session"
         phx-hook="ConversationChannel">
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
            <div class="flex-1 overflow-hidden">
              <.live_component
                module={FileTreeComponent}
                id="file-tree"
                project_id={@project_id}
                current_file={@current_file}
              />
            </div>
          </aside>
        <% end %>
        
        <!-- Chat Panel (Center - Primary) -->
        <main class={@layout.chat_width <> " flex flex-col"}>
          <.live_component
            module={ChatPanelComponent}
            id="chat-panel"
            project_id={@project_id}
            conversation_id={@conversation_id}
            conversation_connected={@conversation_connected}
            current_user={@user}
            messages={@chat_messages}
            streaming_message={@streaming_message}
          />
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
              <.live_component
                module={MonacoEditorComponent}
                id="monaco-editor"
                project_id={@project_id}
                file_path={@current_file}
                current_user_id={@user.id}
              />
            </div>
          </aside>
        <% end %>
        
        <!-- Context Panel (Far Right) -->
        <%= if @layout.show_context do %>
          <aside class={"#{@layout.context_width} bg-white border-l border-gray-200 overflow-hidden flex flex-col"}>
            <.live_component
              module={ContextPanelComponent}
              id="context-panel"
              project_id={@project_id}
              current_file={@current_file}
            />
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
  
  
  # Channel event handlers from client
  
  @impl true
  def handle_event("conversation_joined", %{"conversation_id" => _conv_id}, socket) do
    {:noreply, assign(socket, :conversation_connected, true)}
  end
  
  @impl true
  def handle_event("conversation_response", %{"response" => response}, socket) do
    # Create assistant message from channel response
    message = %{
      id: Map.get(response, "id", Ecto.UUID.generate()),
      type: :assistant,
      content: response["content"],
      user_id: nil,
      username: "AI Assistant",
      metadata: %{
        timestamp: DateTime.utc_now(),
        status: :complete,
        model: response["model"],
        provider: response["provider"],
        tokens: response["tokens"]
      }
    }
    
    socket = 
      socket
      |> update(:chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
      |> update(:streaming_message, fn _ -> nil end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("conversation_thinking", _params, socket) do
    # Show thinking indicator
    streaming_message = %{
      id: "thinking-#{Ecto.UUID.generate()}",
      type: :assistant,
      content: "",
      metadata: %{
        timestamp: DateTime.utc_now(),
        status: :streaming
      }
    }
    
    {:noreply, assign(socket, :streaming_message, streaming_message)}
  end
  
  @impl true
  def handle_event("conversation_error", %{"error" => error}, socket) do
    # Create error message
    message = %{
      id: Ecto.UUID.generate(),
      type: :error,
      content: error["message"] || "An error occurred",
      metadata: %{
        timestamp: DateTime.utc_now(),
        status: :error,
        details: error["details"]
      }
    }
    
    socket = 
      socket
      |> update(:chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
      |> update(:streaming_message, fn _ -> nil end)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("auth_success", %{"user" => user, "token" => token}, socket) do
    message = %{
      id: Ecto.UUID.generate(),
      type: :system,
      content: "✅ Successfully logged in as #{user["username"]}",
      metadata: %{timestamp: DateTime.utc_now(), status: :complete}
    }
    
    socket = 
      socket
      |> assign(:auth_token, token)
      |> assign(:authenticated_user, user)
      |> update(:chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("auth_error", %{"message" => msg}, socket) do
    message = %{
      id: Ecto.UUID.generate(),
      type: :error,
      content: "❌ Authentication failed: #{msg}",
      metadata: %{timestamp: DateTime.utc_now(), status: :error}
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("api_key_generated", %{"api_key" => api_key, "warning" => warning}, socket) do
    message = %{
      id: Ecto.UUID.generate(),
      type: :system,
      content: """
      ✅ API Key Generated:
      
      Name: #{api_key["name"]}
      Key: `#{api_key["key"]}`
      Expires: #{api_key["expires_at"] || "Never"}
      
      ⚠️ #{warning}
      """,
      metadata: %{timestamp: DateTime.utc_now(), status: :complete}
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("api_key_list", %{"api_keys" => keys}, socket) do
    keys_text = Enum.map_join(keys, "\n", fn key ->
      "- #{key["name"]} (ID: #{key["id"]}, Created: #{key["created_at"]})"
    end)
    
    message = %{
      id: Ecto.UUID.generate(),
      type: :system,
      content: """
      📋 Your API Keys:
      
      #{if keys_text == "", do: "No API keys found.", else: keys_text}
      """,
      metadata: %{timestamp: DateTime.utc_now(), status: :complete}
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("api_key_revoked", %{"api_key_id" => key_id}, socket) do
    message = %{
      id: Ecto.UUID.generate(),
      type: :system,
      content: "✅ API Key #{key_id} has been revoked successfully.",
      metadata: %{timestamp: DateTime.utc_now(), status: :complete}
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("api_key_error", %{"message" => msg}, socket) do
    message = %{
      id: Ecto.UUID.generate(),
      type: :error,
      content: "❌ API Key Error: #{msg}",
      metadata: %{timestamp: DateTime.utc_now(), status: :error}
    }
    
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
    {:noreply, socket}
  end
  
  # PubSub Handlers
  
  @impl true
  def handle_info({:project_update, update}, socket) do
    socket = apply_project_update(socket, update)
    {:noreply, socket}
  end
  
  def handle_info({:chat_message, message}, socket) do
    # The ChatPanelComponent will handle its own messages via PubSub
    # We just need to update our local state for the component
    socket = update(socket, :chat_messages, &(&1 ++ [{"message-#{message.id}", message}]))
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
  
  def handle_info({:send_to_conversation, message}, socket) do
    # Push event to client to send through ConversationChannel
    socket = push_event(socket, "send_to_conversation", %{
      content: message.content,
      conversation_id: socket.assigns.conversation_id
    })
    
    {:noreply, socket}
  end
  
  def handle_info({:update_llm_preferences, preferences}, socket) do
    # Push event to update preferences through ConversationChannel
    socket = push_event(socket, "update_llm_preferences", preferences)
    
    {:noreply, socket}
  end
  
  def handle_info({:auth_login, %{username: username, password: password}}, socket) do
    # Push event to handle login through AuthChannel
    socket = push_event(socket, "auth_login", %{username: username, password: password})
    {:noreply, socket}
  end
  
  def handle_info({:auth_logout}, socket) do
    # Push event to handle logout through AuthChannel
    socket = push_event(socket, "auth_logout", %{})
    {:noreply, socket}
  end
  
  def handle_info({:api_key_generate, params}, socket) do
    # Push event to generate API key
    socket = push_event(socket, "api_key_generate", params)
    {:noreply, socket}
  end
  
  def handle_info({:api_key_list}, socket) do
    # Push event to list API keys
    socket = push_event(socket, "api_key_list", %{})
    {:noreply, socket}
  end
  
  def handle_info({:api_key_revoke, key_id}, socket) do
    # Push event to revoke API key
    socket = push_event(socket, "api_key_revoke", %{key_id: key_id})
    {:noreply, socket}
  end
  
  def handle_info({:file_selected, file_path}, socket) do
    # Handle file selection from FileTreeComponent
    socket = 
      socket
      |> assign(:current_file, file_path)
      |> push_event("file_opened", %{path: file_path})
    
    # Update context panel with new file
    ContextPanelComponent.update_current_file("context-panel", file_path)
    
    # Broadcast file selection to other users
    PubSub.broadcast(
      RubberDuck.PubSub,
      "project:#{socket.assigns.project_id}",
      {:user_opened_file, %{
        user_id: socket.assigns.user.id,
        file_path: file_path
      }}
    )
    
    {:noreply, socket}
  end
  
  def handle_info({:load_file_tree, component_id, show_hidden}, socket) do
    # Load file tree asynchronously
    project_path = File.cwd!() # TODO: Get from project record
    
    Task.async(fn ->
      case FileTree.list_tree(project_path, show_hidden: show_hidden) do
        {:ok, tree} ->
          # Get git status
          git_status = 
            case FileTree.get_git_status(project_path) do
              {:ok, status} -> status
              _ -> %{}
            end
            
          {:ok, component_id, tree.children || [], git_status}
          
        {:error, reason} ->
          {:error, component_id, "Failed to load file tree: #{inspect(reason)}"}
      end
    end)
    
    {:noreply, socket}
  end
  
  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Handle async task results
    Process.demonitor(ref, [:flush])
    
    case result do
      {:ok, component_id, tree_nodes, git_status} ->
        FileTreeComponent.update_tree_data(component_id, tree_nodes, git_status)
        
      {:error, component_id, error} ->
        FileTreeComponent.update_tree_error(component_id, error)
        
      {:file_content, component_id, content, language} ->
        MonacoEditorComponent.update_content(component_id, content, language)
        
      {:file_analysis, component_id, analysis, related_files, metrics} ->
        # Update context panel with analysis results
        send_update(ContextPanelComponent,
          id: component_id,
          file_analysis: analysis,
          symbol_outline: analysis.symbols,
          related_files: related_files,
          code_metrics: metrics,
          loading: false
        )
        
      {:file_analysis_error, component_id, reason} ->
        ContextPanelComponent.add_notification(component_id, :error, "Analysis failed: #{reason}")
    end
    
    {:noreply, socket}
  end
  
  def handle_info({:load_file_content, component_id, file_path}, socket) do
    # Load file content asynchronously
    Task.async(fn ->
      case File.read(file_path) do
        {:ok, content} ->
          # Detect language from file extension
          language = detect_language_from_path(file_path)
          {:file_content, component_id, content, language}
          
        {:error, reason} ->
          {:file_content, component_id, "# Error loading file: #{inspect(reason)}", "plaintext"}
      end
    end)
    
    {:noreply, socket}
  end
  
  def handle_info({:auto_save, component_id}, socket) do
    # Auto-save functionality can be implemented here
    # For now, just log
    Logger.debug("Auto-save triggered for component: #{component_id}")
    {:noreply, socket}
  end
  
  def handle_info({:analyze_file, component_id, file_path}, socket) do
    # Analyze file asynchronously
    Task.async(fn ->
      case CodeAnalyzer.analyze_file(file_path) do
        {:ok, analysis} ->
          # Get related files
          project_path = File.cwd!()
          related_files = CodeAnalyzer.find_related_files(file_path, project_path)
          
          # Get metrics
          metrics = %{
            complexity: %{
              cyclomatic: analysis.complexity,
              cognitive: analysis.complexity + 5 # Mock cognitive complexity
            },
            test_coverage: MetricsCollector.get_test_coverage(socket.assigns.project_id),
            performance: MetricsCollector.get_performance_metrics(socket.assigns.project_id),
            security_score: elem(MetricsCollector.get_security_score(socket.assigns.project_id), 0),
            security_issues: elem(MetricsCollector.get_security_score(socket.assigns.project_id), 1)
          }
          
          {:file_analysis, component_id, analysis, related_files, metrics}
          
        {:error, reason} ->
          {:file_analysis_error, component_id, reason}
      end
    end)
    
    {:noreply, socket}
  end
  
  def handle_info({:run_action, action, file_path}, socket) do
    # Handle context panel actions
    case action do
      :analysis ->
        # Trigger full analysis
        send(self(), {:analyze_file, "context-panel", file_path})
        
      :generate_tests ->
        # TODO: Implement test generation
        ContextPanelComponent.add_notification("context-panel", :info, "Test generation not yet implemented")
        
      :refactoring ->
        # TODO: Implement refactoring suggestions
        ContextPanelComponent.add_notification("context-panel", :info, "Refactoring suggestions coming soon")
        
      :generate_docs ->
        # TODO: Implement documentation generation
        ContextPanelComponent.add_notification("context-panel", :info, "Documentation generation coming soon")
        
      :security_scan ->
        # TODO: Implement security scanning
        ContextPanelComponent.add_notification("context-panel", :info, "Security scan coming soon")
        
      :performance ->
        # TODO: Implement performance analysis
        ContextPanelComponent.add_notification("context-panel", :info, "Performance analysis coming soon")
    end
    
    {:noreply, socket}
  end
  
  def handle_info({:goto_line, _file_path, line_number}, socket) do
    # Send event to Monaco editor to go to line
    push_event(socket, "goto_line", %{
      editor_id: "monaco-editor-editor",
      line: line_number
    })
    
    {:noreply, socket}
  end
  
  def handle_info({:open_file, file_path}, socket) do
    # Simulate file selection
    send(self(), {:file_selected, file_path})
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
      show_context: true,
      chat_width: calculate_chat_width(true, true, true),
      tree_width: "w-64",
      editor_width: "flex-1",
      context_width: "w-80"
    }
    
    assign(socket, :layout, layout)
  end
  
  defp calculate_chat_width(_show_tree, _show_editor, _show_context \\ false) do
    # Chat panel takes remaining space after fixed-width panels
    "flex-1"
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
  
  defp handle_keyboard_shortcut("i", socket) do
    # Ctrl+I: Toggle context panel
    update_in(socket.assigns.layout.show_context, &(!&1))
    |> recalculate_layout()
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
  
  defp update_layout_visibility(layout, "context") do
    Map.put(layout, :show_context, !layout.show_context)
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
      
      <button
        phx-click="toggle_panel"
        phx-value-panel="context"
        class={[
          "p-2 rounded hover:bg-gray-100",
          @layout.show_context && "bg-gray-100"
        ]}
        title="Toggle context panel (Ctrl+I)"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" 
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
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
  
  
  defp detect_language_from_path(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".jsx" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".rs" -> "rust"
      ".json" -> "json"
      ".html" -> "html"
      ".heex" -> "html"
      ".css" -> "css"
      ".md" -> "markdown"
      _ -> "plaintext"
    end
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