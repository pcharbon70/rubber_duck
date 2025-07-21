defmodule RubberDuckWeb.Components.MonacoEditorComponent do
  @moduledoc """
  A Phoenix LiveView component that integrates Monaco Editor for rich code editing.
  
  Features:
  - Syntax highlighting with automatic language detection
  - IntelliSense and code completion
  - Real-time bidirectional data sync
  - AI-powered code suggestions
  - Collaborative editing support
  - Customizable themes and settings
  """
  use RubberDuckWeb, :live_component
  
  alias Phoenix.PubSub
  
  @default_options %{
    theme: "vs-dark",
    fontSize: 14,
    fontFamily: "Fira Code, Consolas, 'Courier New', monospace",
    fontLigatures: true,
    minimap: %{enabled: true},
    lineNumbers: "on",
    renderWhitespace: "selection",
    rulers: [80, 120],
    wordWrap: "off",
    tabSize: 2,
    insertSpaces: true,
    formatOnPaste: true,
    formatOnType: true,
    automaticLayout: true,
    scrollBeyondLastLine: false,
    smoothScrolling: true,
    cursorBlinking: "smooth",
    cursorSmoothCaretAnimation: true,
    suggestOnTriggerCharacters: true,
    acceptSuggestionOnEnter: "on",
    quickSuggestions: %{
      other: true,
      comments: false,
      strings: false
    }
  }
  
  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       content: "",
       language: "plaintext",
       options: @default_options,
       read_only: false,
       modified: false,
       cursor_position: nil,
       selection: nil,
       decorations: [],
       ai_suggestions: [],
       collaborators: %{},
       loading: false,
       error: nil
     )
     |> assign_new(:file_path, fn -> nil end)
     |> assign_new(:project_id, fn -> nil end)}
  end
  
  @impl true
  def update(assigns, socket) do
    socket = 
      socket
      |> assign(assigns)
      |> maybe_load_file()
      |> maybe_detect_language()
      |> maybe_subscribe()
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="monaco-editor-component h-full flex flex-col bg-gray-900" id={@id}>
      <!-- Editor Header -->
      <div class="editor-header px-3 py-2 border-b border-gray-700 bg-gray-800">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <span class="text-sm text-gray-400">
              <%= format_file_path(@file_path) %>
            </span>
            <%= if @modified do %>
              <span class="text-xs text-yellow-500">●</span>
            <% end %>
            <span class="text-xs text-gray-500">
              <%= @language %>
            </span>
          </div>
          
          <div class="flex items-center gap-2">
            <!-- AI Assistant Toggle -->
            <button
              class="p-1.5 rounded hover:bg-gray-700 text-gray-400 hover:text-gray-200"
              phx-click="toggle_ai_assistant"
              phx-target={@myself}
              title="Toggle AI Assistant"
            >
              🤖
            </button>
            
            <!-- Settings -->
            <button
              class="p-1.5 rounded hover:bg-gray-700 text-gray-400 hover:text-gray-200"
              phx-click="open_settings"
              phx-target={@myself}
              title="Editor Settings"
            >
              ⚙️
            </button>
            
            <!-- Format Document -->
            <button
              class="p-1.5 rounded hover:bg-gray-700 text-gray-400 hover:text-gray-200"
              phx-click="format_document"
              phx-target={@myself}
              title="Format Document"
            >
              📐
            </button>
          </div>
        </div>
        
        <!-- Breadcrumb / Symbol Path -->
        <div :if={@cursor_position} class="mt-1">
          <span class="text-xs text-gray-500">
            Line <%= @cursor_position[:line] %>, Column <%= @cursor_position[:column] %>
          </span>
        </div>
      </div>
      
      <!-- Monaco Editor Container -->
      <div 
        id={"#{@id}-editor"}
        class="flex-1"
        phx-hook="MonacoEditor"
        phx-update="ignore"
        data-content={@content}
        data-language={@language}
        data-options={Jason.encode!(@options)}
        data-read-only={to_string(@read_only)}
        data-file-path={@file_path}
      >
        <%= if @loading do %>
          <div class="flex items-center justify-center h-full">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          </div>
        <% end %>
      </div>
      
      <!-- Status Bar -->
      <div class="editor-status-bar px-3 py-1 border-t border-gray-700 bg-gray-800">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-4">
            <!-- File Info -->
            <span class="text-gray-400">
              <%= format_encoding() %> • <%= format_line_ending() %>
            </span>
            
            <!-- Git Status -->
            <span :if={@git_status} class="text-gray-400">
              <%= format_git_status(@git_status) %>
            </span>
          </div>
          
          <div class="flex items-center gap-4">
            <!-- Collaborators -->
            <%= if map_size(@collaborators) > 0 do %>
              <div class="flex items-center gap-1">
                <%= for {_id, collaborator} <- @collaborators |> Enum.take(5) do %>
                  <div 
                    class="w-6 h-6 rounded-full flex items-center justify-center text-xs font-medium"
                    style={"background-color: #{collaborator.color}"}
                    title={collaborator.name}
                  >
                    <%= String.first(collaborator.name) %>
                  </div>
                <% end %>
                <%= if map_size(@collaborators) > 5 do %>
                  <span class="text-gray-400">+<%= map_size(@collaborators) - 5 %></span>
                <% end %>
              </div>
            <% end %>
            
            <!-- Language Mode -->
            <button
              class="text-gray-400 hover:text-gray-200"
              phx-click="change_language"
              phx-target={@myself}
            >
              <%= @language %>
            </button>
          </div>
        </div>
      </div>
      
      <!-- AI Suggestions Panel (Overlay) -->
      <%= if @show_ai_suggestions do %>
        <div class="absolute bottom-16 right-4 w-80 bg-gray-800 border border-gray-600 rounded-lg shadow-xl p-4">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-gray-200">AI Suggestions</h3>
            <button
              class="text-gray-400 hover:text-gray-200"
              phx-click="close_ai_suggestions"
              phx-target={@myself}
            >
              ✕
            </button>
          </div>
          
          <%= if @ai_suggestions == [] do %>
            <p class="text-sm text-gray-400">No suggestions available</p>
          <% else %>
            <div class="space-y-2">
              <%= for suggestion <- @ai_suggestions do %>
                <div 
                  class="p-2 bg-gray-700 rounded cursor-pointer hover:bg-gray-600"
                  phx-click="apply_suggestion"
                  phx-value-id={suggestion.id}
                  phx-target={@myself}
                >
                  <div class="text-xs text-blue-400 mb-1"><%= suggestion.type %></div>
                  <div class="text-sm text-gray-200"><%= suggestion.description %></div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
  
  # Event Handlers
  
  @impl true
  def handle_event("editor_mounted", _params, socket) do
    # Editor is ready, load content if we have a file
    socket = 
      if socket.assigns.file_path do
        load_file_content(socket)
      else
        socket
      end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("content_changed", %{"content" => content, "changes" => changes}, socket) do
    socket = 
      socket
      |> assign(:content, content)
      |> assign(:modified, true)
      |> broadcast_changes(changes)
    
    # Auto-save after a delay
    Process.send_after(self(), {:auto_save, socket.assigns.id}, 2000)
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("cursor_changed", %{"position" => position, "selection" => selection}, socket) do
    socket = 
      socket
      |> assign(:cursor_position, atomize_keys(position))
      |> assign(:selection, atomize_keys(selection))
      |> broadcast_cursor_position()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("format_document", _params, socket) do
    # Request formatting from the editor
    {:noreply, push_event(socket, "format_document", %{editor_id: "#{socket.assigns.id}-editor"})}
  end
  
  @impl true
  def handle_event("change_language", _params, socket) do
    # TODO: Show language picker
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("toggle_ai_assistant", _params, socket) do
    socket = 
      socket
      |> update(:show_ai_suggestions, &(!&1))
      |> maybe_request_ai_suggestions()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("apply_suggestion", %{"id" => suggestion_id}, socket) do
    suggestion = Enum.find(socket.assigns.ai_suggestions, &(&1.id == suggestion_id))
    
    if suggestion do
      # Apply the suggestion to the editor
      {:noreply, push_event(socket, "apply_edit", %{
        editor_id: "#{socket.assigns.id}-editor",
        edit: suggestion.edit
      })}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("request_completions", %{"position" => _position, "context" => _context}, socket) do
    # Request AI completions
    Task.async(fn ->
      # TODO: Call AI service for completions
      {:completions, [
        %{
          label: "console.log",
          kind: "Function",
          detail: "Log to console",
          insertText: "console.log($1)",
          insertTextRules: 4 # Snippet
        }
      ]}
    end)
    
    {:noreply, socket}
  end
  
  # Public Functions
  
  @doc """
  Updates the editor content from the parent LiveView.
  """
  def update_content(component_id, content, language \\ nil) do
    send_update(__MODULE__, 
      id: component_id,
      content: content,
      language: language || detect_language_from_content(content),
      modified: false
    )
  end
  
  @doc """
  Applies decorations to the editor (e.g., error highlights).
  """
  def apply_decorations(component_id, decorations) do
    send_update(__MODULE__, 
      id: component_id,
      decorations: decorations
    )
  end
  
  # Private Functions
  
  defp maybe_load_file(socket) do
    if socket.assigns.file_path && socket.assigns.content == "" do
      load_file_content(socket)
    else
      socket
    end
  end
  
  defp maybe_detect_language(socket) do
    if socket.assigns.language == "plaintext" && socket.assigns.file_path do
      language = detect_language_from_path(socket.assigns.file_path)
      assign(socket, :language, language)
    else
      socket
    end
  end
  
  defp maybe_subscribe(socket) do
    if connected?(socket) && socket.assigns.project_id && socket.assigns.file_path do
      # Subscribe to file changes
      PubSub.subscribe(RubberDuck.PubSub, "file:#{socket.assigns.file_path}")
      
      # Subscribe to collaborative editing
      PubSub.subscribe(RubberDuck.PubSub, "editor:#{socket.assigns.project_id}:#{socket.assigns.file_path}")
    end
    
    socket
  end
  
  defp load_file_content(socket) do
    # Request parent to load file content
    send(self(), {:load_file_content, socket.assigns.id, socket.assigns.file_path})
    assign(socket, :loading, true)
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
      ".java" -> "java"
      ".c" -> "c"
      ".cpp" -> "cpp"
      ".h" -> "c"
      ".hpp" -> "cpp"
      ".cs" -> "csharp"
      ".php" -> "php"
      ".html" -> "html"
      ".heex" -> "html"
      ".eex" -> "html"
      ".css" -> "css"
      ".scss" -> "scss"
      ".sass" -> "sass"
      ".less" -> "less"
      ".json" -> "json"
      ".xml" -> "xml"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".toml" -> "toml"
      ".md" -> "markdown"
      ".sql" -> "sql"
      ".sh" -> "shell"
      ".bash" -> "shell"
      ".zsh" -> "shell"
      ".fish" -> "shell"
      ".ps1" -> "powershell"
      ".r" -> "r"
      ".R" -> "r"
      ".swift" -> "swift"
      ".kt" -> "kotlin"
      ".scala" -> "scala"
      ".lua" -> "lua"
      ".vim" -> "vim"
      ".dockerfile" -> "dockerfile"
      "Dockerfile" -> "dockerfile"
      ".gitignore" -> "gitignore"
      _ -> "plaintext"
    end
  end
  
  defp detect_language_from_content(content) do
    cond do
      String.starts_with?(content, "#!/usr/bin/env python") -> "python"
      String.starts_with?(content, "#!/usr/bin/env ruby") -> "ruby"
      String.starts_with?(content, "#!/usr/bin/env node") -> "javascript"
      String.starts_with?(content, "#!/bin/bash") -> "shell"
      String.starts_with?(content, "#!/bin/sh") -> "shell"
      String.contains?(content, "defmodule") -> "elixir"
      String.contains?(content, "<?php") -> "php"
      true -> "plaintext"
    end
  end
  
  defp broadcast_changes(socket, changes) do
    if socket.assigns.project_id && socket.assigns.file_path do
      PubSub.broadcast(
        RubberDuck.PubSub,
        "editor:#{socket.assigns.project_id}:#{socket.assigns.file_path}",
        {:editor_changes, %{
          user_id: socket.assigns[:current_user_id],
          changes: changes,
          timestamp: DateTime.utc_now()
        }}
      )
    end
    
    socket
  end
  
  defp broadcast_cursor_position(socket) do
    if socket.assigns.project_id && socket.assigns.file_path && socket.assigns[:current_user_id] do
      PubSub.broadcast(
        RubberDuck.PubSub,
        "editor:#{socket.assigns.project_id}:#{socket.assigns.file_path}",
        {:cursor_position, %{
          user_id: socket.assigns.current_user_id,
          position: socket.assigns.cursor_position,
          selection: socket.assigns.selection
        }}
      )
    end
    
    socket
  end
  
  defp maybe_request_ai_suggestions(socket) do
    if socket.assigns[:show_ai_suggestions] && socket.assigns.content != "" do
      # Request AI suggestions based on current context
      Task.async(fn ->
        # TODO: Implement AI suggestion logic
        {:ai_suggestions, [
          %{
            id: Ecto.UUID.generate(),
            type: "Refactor",
            description: "Extract method from lines 10-20",
            edit: %{
              range: %{startLine: 10, endLine: 20},
              text: "def extracted_method do\n  # extracted code\nend"
            }
          }
        ]}
      end)
      
      socket
    else
      socket
    end
  end
  
  defp format_file_path(nil), do: "Untitled"
  defp format_file_path(path) do
    # Show just the filename and parent directory
    parts = Path.split(path)
    case length(parts) do
      1 -> path
      2 -> Path.join(parts)
      _ -> 
        parent = Enum.at(parts, -2)
        file = Enum.at(parts, -1)
        ".../" <> Path.join([parent, file])
    end
  end
  
  defp format_encoding, do: "UTF-8"
  defp format_line_ending, do: "LF"
  
  defp format_git_status(status) do
    case status do
      :modified -> "Modified"
      :added -> "Added"
      :deleted -> "Deleted"
      _ -> ""
    end
  end
  
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
  defp atomize_keys(other), do: other
end