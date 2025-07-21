defmodule RubberDuckWeb.Components.ChatPanelComponent do
  @moduledoc """
  A comprehensive chat panel component for AI-powered coding assistance.
  
  Features:
  - Rich message rendering with markdown and syntax highlighting
  - Real-time streaming support
  - Command palette with slash commands
  - Message history and actions
  - LLM integration controls
  """
  use RubberDuckWeb, :live_component
  
  import RubberDuckWeb.CoreComponents
  
  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       messages: [],
       input_value: "",
       streaming_message: nil,
       selected_model: "gpt-4",
       selected_provider: "openai",
       show_model_settings: false,
       typing_users: [],
       command_suggestions: [],
       show_commands: false,
       search_query: "",
       search_results: [],
       uploading_files: []
     )
     |> assign_new(:current_user, fn -> nil end)}
  end
  
  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:conversation_connected, fn -> false end)
     |> maybe_subscribe_to_chat()}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="chat-panel flex flex-col h-full bg-white dark:bg-gray-900" id={@id}>
      <!-- Header -->
      <div class="chat-header border-b border-gray-200 dark:border-gray-700 px-4 py-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
              AI Assistant
            </h2>
            <.model_selector {assigns} />
          </div>
          
          <div class="flex items-center gap-2">
            <.connection_indicator connected={@conversation_connected} />
            <.token_usage messages={@messages} />
            <.chat_actions {assigns} />
          </div>
        </div>
        
        <.typing_indicator typing_users={@typing_users} />
      </div>
      
      <!-- Messages Area -->
      <div
        class="chat-messages flex-1 overflow-y-auto px-4 py-4 space-y-4"
        id={"#{@id}-messages"}
        phx-hook="ChatScroll"
        phx-update="stream"
      >
        <div :for={{dom_id, message} <- @messages} id={dom_id}>
          <.message message={message} current_user={@current_user} />
        </div>
        
        <.streaming_message :if={@streaming_message} message={@streaming_message} />
      </div>
      
      <!-- Search Results Overlay -->
      <.search_overlay :if={@search_results != []} results={@search_results} />
      
      <!-- Input Area -->
      <div class="chat-input border-t border-gray-200 dark:border-gray-700 px-4 py-3">
        <.file_upload_area uploading_files={@uploading_files} />
        
        <form phx-submit="send_message" phx-change="update_input" phx-target={@myself}>
          <div class="relative">
            <textarea
              name="message"
              value={@input_value}
              rows={calculate_rows(@input_value)}
              class="w-full px-3 py-2 pr-24 border border-gray-300 dark:border-gray-600 rounded-lg resize-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-800 dark:text-gray-100"
              placeholder="Type a message or / for commands..."
              phx-keydown="keydown"
              phx-target={@myself}
              id={"#{@id}-input"}
              phx-hook="AutoResize"
            />
            
            <div class="absolute bottom-2 right-2 flex items-center gap-2">
              <button
                type="button"
                class="p-1.5 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                phx-click="toggle_file_upload"
                phx-target={@myself}
              >
                📎
              </button>
              
              <button
                type="submit"
                class="px-3 py-1 bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
                disabled={@input_value == "" || @streaming_message != nil}
              >
                ✈️
              </button>
            </div>
          </div>
        </form>
        
        <.command_palette
          :if={@show_commands}
          suggestions={@command_suggestions}
          target={@myself}
        />
      </div>
      
      <!-- Model Settings Modal -->
      <.model_settings_modal :if={@show_model_settings} {assigns} />
    </div>
    """
  end
  
  # Event Handlers
  
  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    content = String.trim(content)
    
    if content != "" do
      message = create_message(content, :user, socket.assigns.current_user)
      
      socket =
        socket
        |> add_message(message)
        |> assign(input_value: "")
      
      # Check if it's a command or regular message
      if String.starts_with?(content, "/") do
        socket = handle_command(socket, message)
        {:noreply, socket}
      else
        # Send to parent LiveView to handle through ConversationChannel
        send(self(), {:send_to_conversation, message})
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("update_input", %{"message" => value}, socket) do
    socket =
      socket
      |> assign(input_value: value)
      |> maybe_show_commands(value)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
    if socket.assigns.input_value != "" && socket.assigns.streaming_message == nil do
      send(self(), {:submit_message})
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, show_commands: false, search_results: [])}
  end
  
  @impl true
  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("select_command", %{"command" => command}, socket) do
    socket =
      socket
      |> assign(input_value: command <> " ", show_commands: false)
      |> push_event("focus_input", %{id: "#{socket.assigns.id}-input"})
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("cancel_streaming", _params, socket) do
    # TODO: Implement streaming cancellation
    {:noreply, assign(socket, streaming_message: nil)}
  end
  
  @impl true
  def handle_event("retry_message", %{"message_id" => _message_id}, socket) do
    # TODO: Implement message retry
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("copy_message", %{"message_id" => message_id}, socket) do
    message = Enum.find(socket.assigns.messages, fn {_id, msg} -> msg.id == message_id end)
    
    if message do
      {:noreply, push_event(socket, "copy_to_clipboard", %{text: elem(message, 1).content})}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("toggle_model_settings", _params, socket) do
    {:noreply, update(socket, :show_model_settings, &(!&1))}
  end
  
  @impl true
  def handle_event("update_model", %{"provider" => provider, "model" => model}, socket) do
    # Notify parent to update conversation channel preferences
    send(self(), {:update_llm_preferences, %{provider: provider, model: model}})
    
    {:noreply,
     assign(socket,
       selected_provider: provider,
       selected_model: model,
       show_model_settings: false
     )}
  end
  
  # PubSub Handlers
  
  # Note: LiveComponents don't support handle_info
  # These would need to be handled by the parent LiveView
  # The parent LiveView should handle PubSub messages and update the component's assigns
  
  # Helper Functions
  
  defp maybe_subscribe_to_chat(socket) do
    # Subscription should be handled by the parent LiveView
    # since LiveComponents can't receive handle_info messages
    socket
  end
  
  defp create_message(content, type, user) do
    %{
      id: Ecto.UUID.generate(),
      type: type,
      content: content,
      user_id: user && user.id,
      username: user && user.username,
      metadata: %{
        timestamp: DateTime.utc_now(),
        status: :complete
      }
    }
  end
  
  defp add_message(socket, message) do
    update(socket, :messages, fn messages ->
      messages ++ [{"message-#{message.id}", message}]
    end)
  end
  
  
  defp handle_command(socket, message) do
    parts = String.split(message.content, " ", trim: true)
    [command | args] = parts
    
    case command do
      "/help" ->
        help_message = create_help_message()
        add_message(socket, help_message)
        
      "/login" ->
        handle_login_command(socket, args)
        
      "/logout" ->
        handle_logout_command(socket)
        
      "/api-key" ->
        handle_api_key_command(socket, args)
        
      "/clear" ->
        assign(socket, messages: [])
        
      "/export" ->
        # TODO: Implement export
        error_message = create_message("Export functionality coming soon!", :system, nil)
        add_message(socket, error_message)
        
      "/model" ->
        assign(socket, show_model_settings: true)
        
      "/retry" ->
        # TODO: Implement retry
        error_message = create_message("Retry functionality coming soon!", :system, nil)
        add_message(socket, error_message)
        
      "/status" ->
        handle_status_command(socket)
        
      _ ->
        error_message = create_message(
          "Unknown command: #{command}. Type /help for available commands.",
          :system,
          nil
        )
        add_message(socket, error_message)
    end
  end
  
  
  
  defp maybe_show_commands(socket, value) do
    if String.starts_with?(value, "/") && String.length(value) > 1 do
      query = String.slice(value, 1..-1//1) |> String.downcase()
      suggestions = filter_commands(query)
      assign(socket, show_commands: true, command_suggestions: suggestions)
    else
      assign(socket, show_commands: false, command_suggestions: [])
    end
  end
  
  defp filter_commands(query) do
    commands = [
      %{command: "/help", description: "Show available commands"},
      %{command: "/login", description: "Login with username/password"},
      %{command: "/logout", description: "Logout from current session"},
      %{command: "/api-key", description: "Manage API keys"},
      %{command: "/clear", description: "Clear chat history"},
      %{command: "/export", description: "Export conversation"},
      %{command: "/model", description: "Change model settings"},
      %{command: "/retry", description: "Retry last message"},
      %{command: "/status", description: "Show connection status"}
    ]
    
    Enum.filter(commands, fn cmd ->
      String.contains?(String.downcase(cmd.command), query)
    end)
  end
  
  defp calculate_rows(value) do
    lines = String.split(value, "\n") |> length()
    min(max(lines, 1), 10)
  end
  
  defp handle_login_command(socket, args) do
    case args do
      [username, password] ->
        # Send login request to parent
        send(self(), {:auth_login, %{username: username, password: password}})
        message = create_message("Attempting to login as #{username}...", :system, nil)
        add_message(socket, message)
        
      _ ->
        message = create_message(
          "Usage: /login <username> <password>\nExample: /login myuser mypassword",
          :system,
          nil
        )
        add_message(socket, message)
    end
  end
  
  defp handle_logout_command(socket) do
    send(self(), {:auth_logout})
    message = create_message("Logging out...", :system, nil)
    add_message(socket, message)
  end
  
  defp handle_api_key_command(socket, args) do
    case args do
      ["generate" | rest] ->
        name = Enum.join(rest, " ")
        send(self(), {:api_key_generate, %{name: name}})
        message = create_message("Generating new API key#{if name != "", do: ": #{name}", else: ""}...", :system, nil)
        add_message(socket, message)
        
      ["list"] ->
        send(self(), {:api_key_list})
        message = create_message("Fetching API keys...", :system, nil)
        add_message(socket, message)
        
      ["revoke", key_id] ->
        send(self(), {:api_key_revoke, key_id})
        message = create_message("Revoking API key #{key_id}...", :system, nil)
        add_message(socket, message)
        
      _ ->
        message = create_message(
          """
          API Key Commands:
          - `/api-key generate [name]` - Generate a new API key
          - `/api-key list` - List all your API keys
          - `/api-key revoke <key_id>` - Revoke an API key
          """,
          :system,
          nil
        )
        add_message(socket, message)
    end
  end
  
  defp handle_status_command(socket) do
    status_content = """
    Connection Status:
    - Chat: #{if socket.assigns.conversation_connected, do: "✅ Connected", else: "❌ Disconnected"}
    - Model: #{socket.assigns.selected_provider}/#{socket.assigns.selected_model}
    - Messages: #{length(socket.assigns.messages)}
    """
    
    message = create_message(status_content, :system, nil)
    add_message(socket, message)
  end
  
  defp create_help_message do
    content = """
    Available commands:
    - `/help` - Show this help message
    - `/login <username> <password>` - Login to your account
    - `/logout` - Logout from current session
    - `/api-key` - Manage API keys (generate/list/revoke)
    - `/clear` - Clear chat history
    - `/export` - Export conversation (coming soon)
    - `/model` - Open model settings
    - `/retry` - Retry the last message (coming soon)
    - `/status` - Show connection status
    
    You can also use @ to mention files or # to reference code blocks.
    """
    
    create_message(content, :system, nil)
  end
  
  # Components
  
  defp message(assigns) do
    ~H"""
    <div class={"message flex gap-3 #{message_classes(@message.type)}"}>
      <div class="avatar flex-shrink-0">
        <.user_avatar user={@message.username} type={@message.type} />
      </div>
      
      <div class="flex-1">
        <div class="message-header flex items-center gap-2 mb-1">
          <span class="font-medium text-sm text-gray-900 dark:text-gray-100">
            <%= display_name(@message) %>
          </span>
          <span class="text-xs text-gray-500 dark:text-gray-400">
            <%= format_timestamp(@message.metadata.timestamp) %>
          </span>
          <%= if @message.metadata[:model] do %>
            <span class="text-xs text-gray-500 dark:text-gray-400">
              • <%= @message.metadata.model %>
            </span>
          <% end %>
        </div>
        
        <div class="message-content prose prose-sm dark:prose-invert max-w-none">
          <%= render_content(@message.content) %>
        </div>
        
        <div class="message-actions mt-2 flex items-center gap-2">
          <button
            class="text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
            phx-click="copy_message"
            phx-value-message_id={@message.id}
            phx-target={@current_user}
          >
            📋
            Copy
          </button>
          
          <%= if @message.type == :assistant do %>
            <button
              class="text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
              phx-click="retry_message"
              phx-value-message_id={@message.id}
              phx-target={@current_user}
            >
              🔄
              Retry
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
  
  defp streaming_message(assigns) do
    ~H"""
    <div class="message flex gap-3 assistant-message">
      <div class="avatar flex-shrink-0">
        <.user_avatar user={nil} type={:assistant} />
      </div>
      
      <div class="flex-1">
        <div class="message-header flex items-center gap-2 mb-1">
          <span class="font-medium text-sm text-gray-900 dark:text-gray-100">
            AI Assistant
          </span>
          <span class="text-xs text-gray-500 dark:text-gray-400">
            ✨
            Thinking...
          </span>
        </div>
        
        <div class="message-content prose prose-sm dark:prose-invert max-w-none">
          <%= render_content(@message.content) %>
          <span class="inline-block w-2 h-4 bg-gray-400 dark:bg-gray-600 animate-pulse" />
        </div>
        
        <div class="mt-2">
          <button
            class="text-xs text-red-500 hover:text-red-700"
            phx-click="cancel_streaming"
            phx-target={@current_user}
          >
            ❌
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end
  
  defp model_selector(assigns) do
    ~H"""
    <button
      class="flex items-center gap-2 px-3 py-1.5 text-sm bg-gray-100 dark:bg-gray-800 rounded-md hover:bg-gray-200 dark:hover:bg-gray-700"
      phx-click="toggle_model_settings"
      phx-target={@myself}
    >
      🤖
      <%= @selected_model %>
      ▼
    </button>
    """
  end
  
  defp token_usage(assigns) do
    assigns = assign(assigns, :total_tokens, calculate_total_tokens(assigns.messages))
    
    ~H"""
    <div class="text-xs text-gray-500 dark:text-gray-400">
      <%= format_number(@total_tokens) %> tokens
    </div>
    """
  end
  
  defp chat_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <button
        class="p-1.5 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 rounded"
        phx-click="search_messages"
        phx-target={@myself}
      >
        🔍
      </button>
      
      <button
        class="p-1.5 text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 rounded"
        phx-click="export_chat"
        phx-target={@myself}
      >
        ⬇️
      </button>
    </div>
    """
  end
  
  defp typing_indicator(assigns) do
    ~H"""
    <div :if={@typing_users != []} class="mt-2 text-xs text-gray-500 dark:text-gray-400">
      <%= format_typing_users(@typing_users) %> typing...
    </div>
    """
  end
  
  defp connection_indicator(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <div class={[
        "w-2 h-2 rounded-full",
        @connected && "bg-green-500",
        !@connected && "bg-red-500"
      ]} />
      <span class="text-xs text-gray-500 dark:text-gray-400">
        <%= if @connected, do: "Connected", else: "Disconnected" %>
      </span>
    </div>
    """
  end
  
  defp command_palette(assigns) do
    ~H"""
    <div class="absolute bottom-full left-0 right-0 mb-2 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 max-h-48 overflow-y-auto">
      <button
        :for={cmd <- @suggestions}
        class="w-full px-3 py-2 text-left hover:bg-gray-100 dark:hover:bg-gray-700 flex items-center justify-between"
        phx-click="select_command"
        phx-value-command={cmd.command}
        phx-target={@target}
      >
        <span class="font-mono text-sm text-blue-600 dark:text-blue-400">
          <%= cmd.command %>
        </span>
        <span class="text-xs text-gray-500 dark:text-gray-400">
          <%= cmd.description %>
        </span>
      </button>
    </div>
    """
  end
  
  defp user_avatar(assigns) do
    ~H"""
    <div class={"w-8 h-8 rounded-full flex items-center justify-center #{avatar_bg_class(@type)}"}>
      <%= if @type == :user && @user do %>
        <span class="text-sm font-medium text-white">
          <%= String.first(@user) |> String.upcase() %>
        </span>
      <% else %>
        <%= avatar_emoji(@type) %>
      <% end %>
    </div>
    """
  end
  
  # Helper functions for components
  
  defp message_classes(:user), do: "user-message"
  defp message_classes(:assistant), do: "assistant-message"
  defp message_classes(:system), do: "system-message"
  defp message_classes(:error), do: "error-message"
  
  defp avatar_bg_class(:user), do: "bg-blue-500"
  defp avatar_bg_class(:assistant), do: "bg-green-500"
  defp avatar_bg_class(:system), do: "bg-gray-500"
  defp avatar_bg_class(:error), do: "bg-red-500"
  
  defp avatar_emoji(:assistant), do: "✨"
  defp avatar_emoji(:system), do: "ℹ️"
  defp avatar_emoji(:error), do: "⚠️"
  defp avatar_emoji(_), do: "👤"
  
  defp display_name(%{type: :user, username: username}), do: username || "User"
  defp display_name(%{type: :assistant}), do: "AI Assistant"
  defp display_name(%{type: :system}), do: "System"
  defp display_name(%{type: :error}), do: "Error"
  
  defp format_timestamp(_timestamp) do
    # TODO: Implement proper timestamp formatting
    "just now"
  end
  
  defp render_content(content) do
    # TODO: Implement markdown rendering with syntax highlighting
    # For now, just return the raw content
    raw(content)
  end
  
  defp calculate_total_tokens(messages) do
    Enum.reduce(messages, 0, fn {_id, msg}, acc ->
      tokens = get_in(msg, [:metadata, :tokens])
      if tokens do
        acc + Map.get(tokens, :prompt, 0) + Map.get(tokens, :completion, 0)
      else
        acc
      end
    end)
  end
  
  defp format_number(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n), do: to_string(n)
  
  defp format_typing_users([user]), do: user
  defp format_typing_users([u1, u2]), do: "#{u1} and #{u2} are"
  defp format_typing_users([u | _rest]), do: "#{u} and others are"
  
  # Placeholder components
  
  defp file_upload_area(assigns) do
    ~H"""
    <div :if={@uploading_files != []} class="mb-2">
      <!-- TODO: Implement file upload UI -->
    </div>
    """
  end
  
  defp search_overlay(assigns) do
    ~H"""
    <div class="absolute inset-0 bg-white dark:bg-gray-900 z-10">
      <!-- TODO: Implement search UI -->
    </div>
    """
  end
  
  defp model_settings_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-md w-full">
        <h3 class="text-lg font-semibold mb-4">Model Settings</h3>
        <!-- TODO: Implement model settings UI -->
        <button
          class="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          phx-click="toggle_model_settings"
          phx-target={@myself}
        >
          Close
        </button>
      </div>
    </div>
    """
  end
end