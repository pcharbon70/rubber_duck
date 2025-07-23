defmodule RubberDuckWeb.Components.ContextPanelComponent do
  @moduledoc """
  An intelligent context panel that displays relevant project information,
  analysis results, and system status.

  Features:
  - Current file analysis with symbol outline
  - Code metrics and complexity indicators
  - System status monitoring (LLM, resources)
  - Quick actions for common tasks
  - Integrated search functionality
  - Real-time updates via PubSub
  """
  use RubberDuckWeb, :live_component

  alias Phoenix.PubSub

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       # Context displays
       current_file: nil,
       file_analysis: nil,
       symbol_outline: [],
       related_files: [],
       documentation: nil,

       # Metrics
       code_metrics: %{
         complexity: nil,
         test_coverage: nil,
         performance: nil,
         security_score: nil
       },

       # Status monitoring
       llm_status: %{
         provider: nil,
         model: nil,
         available: true,
         rate_limit: nil,
         tokens_used: 0,
         tokens_limit: nil
       },
       analysis_queue: %{
         pending: 0,
         processing: 0,
         completed: 0
       },
       system_resources: %{
         cpu_usage: 0,
         memory_usage: 0,
         disk_usage: 0
       },
       error_count: 0,
       warning_count: 0,

       # UI state
       active_tab: :context,
       search_query: "",
       search_results: [],
       show_search: false,
       notifications: [],
       loading: false
     )
     |> assign_new(:project_id, fn -> nil end)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_load_file_analysis()
      |> maybe_subscribe()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="context-panel-component h-full flex flex-col bg-white dark:bg-gray-900" id={@id}>
      <!-- Header with Tabs -->
      <div class="panel-header border-b border-gray-200 dark:border-gray-700">
        <div class="flex items-center justify-between px-4 py-2">
          <div class="flex items-center gap-1">
            <button
              class={tab_class(@active_tab == :context)}
              phx-click="switch_tab"
              phx-value-tab="context"
              phx-target={@myself}
            >
              📋 Context
            </button>
            <button
              class={tab_class(@active_tab == :metrics)}
              phx-click="switch_tab"
              phx-value-tab="metrics"
              phx-target={@myself}
            >
              📊 Metrics
            </button>
            <button
              class={tab_class(@active_tab == :status)}
              phx-click="switch_tab"
              phx-value-tab="status"
              phx-target={@myself}
            >
              🔧 Status
            </button>
            <button
              class={tab_class(@active_tab == :actions)}
              phx-click="switch_tab"
              phx-value-tab="actions"
              phx-target={@myself}
            >
              ⚡ Actions
            </button>
          </div>
          
          <button
            class="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-800"
            phx-click="toggle_search"
            phx-target={@myself}
            title="Search (Ctrl+Shift+F)"
          >
            🔍
          </button>
        </div>
        
        <!-- Search Bar -->
        <div :if={@show_search} class="px-4 pb-2">
          <div class="relative">
            <input
              type="text"
              name="search"
              value={@search_query}
              phx-change="search"
              phx-target={@myself}
              phx-debounce="300"
              placeholder="Search symbols, files, or documentation..."
              class="w-full px-3 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded-md dark:bg-gray-800 dark:text-gray-100"
              id={"#{@id}-search"}
              phx-hook="FocusOnMount"
            />
            <button
              :if={@search_query != ""}
              class="absolute right-2 top-1.5 text-gray-400 hover:text-gray-600"
              phx-click="clear_search"
              phx-target={@myself}
            >
              ✕
            </button>
          </div>
        </div>
      </div>
      
      <!-- Content Area -->
      <div class="flex-1 overflow-hidden">
        <%= case @active_tab do %>
          <% :context -> %>
            <.context_tab {assigns} />
          <% :metrics -> %>
            <.metrics_tab {assigns} />
          <% :status -> %>
            <.status_tab {assigns} />
          <% :actions -> %>
            <.actions_tab {assigns} />
        <% end %>
      </div>
      
      <!-- Notifications -->
      <%= if @notifications != [] do %>
        <div class="notifications absolute bottom-4 right-4 space-y-2 max-w-sm">
          <%= for notification <- Enum.take(@notifications, 3) do %>
            <div class={notification_class(notification.type)} role="alert">
              <span class="text-sm"><%= notification.message %></span>
              <button
                class="ml-2 text-xs opacity-70 hover:opacity-100"
                phx-click="dismiss_notification"
                phx-value-id={notification.id}
                phx-target={@myself}
              >
                ✕
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Tab Components

  defp context_tab(assigns) do
    ~H"""
    <div class="context-content h-full overflow-y-auto">
      <!-- Current File Analysis -->
      <div class="section px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Current File
        </h3>
        <%= if @current_file do %>
          <div class="text-sm text-gray-600 dark:text-gray-400">
            <div class="font-mono mb-1"><%= Path.basename(@current_file) %></div>
            <%= if @file_analysis do %>
              <div class="space-y-1 text-xs">
                <div>Lines: <%= @file_analysis.lines %></div>
                <div>Functions: <%= @file_analysis.function_count %></div>
                <div>Complexity: <%= @file_analysis.complexity %></div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-gray-500 italic">No file selected</p>
        <% end %>
      </div>
      
      <!-- Symbol Outline -->
      <div class="section px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Symbols
        </h3>
        <%= if @symbol_outline != [] do %>
          <div class="space-y-1">
            <%= for symbol <- @symbol_outline do %>
              <button
                class="w-full text-left px-2 py-1 text-sm hover:bg-gray-100 dark:hover:bg-gray-800 rounded"
                phx-click="goto_symbol"
                phx-value-line={symbol.line}
                phx-target={@myself}
              >
                <span class="text-xs text-gray-500 mr-2"><%= symbol_icon(symbol.type) %></span>
                <span class="font-mono text-xs"><%= symbol.name %></span>
              </button>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-gray-500 italic">No symbols found</p>
        <% end %>
      </div>
      
      <!-- Related Files -->
      <div class="section px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Related Files
        </h3>
        <%= if @related_files != [] do %>
          <div class="space-y-1">
            <%= for file <- Enum.take(@related_files, 5) do %>
              <button
                class="w-full text-left px-2 py-1 text-sm hover:bg-gray-100 dark:hover:bg-gray-800 rounded"
                phx-click="open_file"
                phx-value-path={file.path}
                phx-target={@myself}
              >
                <span class="text-xs truncate"><%= Path.basename(file.path) %></span>
                <span class="text-xs text-gray-500 ml-1">(<%= file.relationship %>)</span>
              </button>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-gray-500 italic">No related files</p>
        <% end %>
      </div>
      
      <!-- Documentation -->
      <div class="section px-4 py-3">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Documentation
        </h3>
        <%= if @documentation do %>
          <div class="prose prose-sm dark:prose-invert max-w-none">
            <%= raw(@documentation) %>
          </div>
        <% else %>
          <p class="text-sm text-gray-500 italic">
            Hover over code or select a symbol to see documentation
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp metrics_tab(assigns) do
    ~H"""
    <div class="metrics-content h-full overflow-y-auto p-4 space-y-4">
      <!-- Code Complexity -->
      <div class="metric-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Code Complexity
        </h3>
        <%= if @code_metrics.complexity do %>
          <div class="space-y-2">
            <.metric_bar 
              label="Cyclomatic" 
              value={@code_metrics.complexity.cyclomatic} 
              max={20}
              color={complexity_color(@code_metrics.complexity.cyclomatic)}
            />
            <.metric_bar 
              label="Cognitive" 
              value={@code_metrics.complexity.cognitive} 
              max={30}
              color={complexity_color(@code_metrics.complexity.cognitive)}
            />
            <div class="text-xs text-gray-600 dark:text-gray-400 mt-2">
              <%= complexity_advice(@code_metrics.complexity) %>
            </div>
          </div>
        <% else %>
          <p class="text-sm text-gray-500">No complexity data available</p>
        <% end %>
      </div>
      
      <!-- Test Coverage -->
      <div class="metric-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Test Coverage
        </h3>
        <%= if @code_metrics.test_coverage do %>
          <div class="space-y-2">
            <.metric_bar 
              label="Line Coverage" 
              value={@code_metrics.test_coverage.lines} 
              max={100}
              suffix="%"
              color={coverage_color(@code_metrics.test_coverage.lines)}
            />
            <.metric_bar 
              label="Function Coverage" 
              value={@code_metrics.test_coverage.functions} 
              max={100}
              suffix="%"
              color={coverage_color(@code_metrics.test_coverage.functions)}
            />
            <div class="text-xs text-gray-600 dark:text-gray-400 mt-2">
              <%= @code_metrics.test_coverage.uncovered_lines %> uncovered lines
            </div>
          </div>
        <% else %>
          <p class="text-sm text-gray-500">No coverage data available</p>
        <% end %>
      </div>
      
      <!-- Performance Metrics -->
      <div class="metric-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Performance
        </h3>
        <%= if @code_metrics.performance do %>
          <div class="space-y-2">
            <div class="flex justify-between text-sm">
              <span class="text-gray-600 dark:text-gray-400">Avg Response Time</span>
              <span class="font-mono"><%= @code_metrics.performance.avg_response_time %>ms</span>
            </div>
            <div class="flex justify-between text-sm">
              <span class="text-gray-600 dark:text-gray-400">Memory Usage</span>
              <span class="font-mono"><%= format_bytes(@code_metrics.performance.memory_usage) %></span>
            </div>
            <div class="flex justify-between text-sm">
              <span class="text-gray-600 dark:text-gray-400">SQL Queries</span>
              <span class="font-mono"><%= @code_metrics.performance.query_count %></span>
            </div>
          </div>
        <% else %>
          <p class="text-sm text-gray-500">No performance data available</p>
        <% end %>
      </div>
      
      <!-- Security Score -->
      <div class="metric-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Security
        </h3>
        <%= if @code_metrics.security_score do %>
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <span class={["text-2xl font-bold", security_color(@code_metrics.security_score)]}>
                <%= security_grade(@code_metrics.security_score) %>
              </span>
              <span class="text-sm text-gray-600 dark:text-gray-400">
                <%= @code_metrics.security_score %>/100
              </span>
            </div>
            <%= if @code_metrics.security_issues do %>
              <div class="text-xs space-y-1 mt-2">
                <div class="text-red-600">
                  🔴 <%= @code_metrics.security_issues.critical %> critical
                </div>
                <div class="text-orange-600">
                  🟠 <%= @code_metrics.security_issues.high %> high
                </div>
                <div class="text-yellow-600">
                  🟡 <%= @code_metrics.security_issues.medium %> medium
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-gray-500">No security scan available</p>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_tab(assigns) do
    ~H"""
    <div class="status-content h-full overflow-y-auto p-4 space-y-4">
      <!-- LLM Status -->
      <div class="status-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          LLM Provider Status
        </h3>
        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">Provider</span>
            <span class="text-sm font-mono">
              <%= @llm_status.provider || "Not configured" %>
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">Model</span>
            <span class="text-sm font-mono">
              <%= @llm_status.model || "Not selected" %>
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">Status</span>
            <span class={["text-sm", if(@llm_status.available, do: "text-green-600", else: "text-red-600")]}>
              <%= if @llm_status.available, do: "✅ Available", else: "❌ Unavailable" %>
            </span>
          </div>
          <%= if @llm_status.tokens_limit do %>
            <div class="mt-2">
              <div class="flex justify-between text-xs text-gray-600 dark:text-gray-400 mb-1">
                <span>Token Usage</span>
                <span><%= format_number(@llm_status.tokens_used) %> / <%= format_number(@llm_status.tokens_limit) %></span>
              </div>
              <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                <div 
                  class="bg-blue-500 h-2 rounded-full"
                  style={"width: #{min(100, @llm_status.tokens_used / @llm_status.tokens_limit * 100)}%"}
                />
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Analysis Queue -->
      <div class="status-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Analysis Queue
        </h3>
        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              🔄 Processing
            </span>
            <span class="text-sm font-mono">
              <%= @analysis_queue.processing %>
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              ⏳ Pending
            </span>
            <span class="text-sm font-mono">
              <%= @analysis_queue.pending %>
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-sm text-gray-600 dark:text-gray-400">
              ✅ Completed
            </span>
            <span class="text-sm font-mono">
              <%= @analysis_queue.completed %>
            </span>
          </div>
        </div>
      </div>
      
      <!-- System Resources -->
      <div class="status-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          System Resources
        </h3>
        <div class="space-y-3">
          <div>
            <div class="flex justify-between text-sm text-gray-600 dark:text-gray-400 mb-1">
              <span>CPU Usage</span>
              <span><%= @system_resources.cpu_usage %>%</span>
            </div>
            <.progress_bar value={@system_resources.cpu_usage} color={resource_color(@system_resources.cpu_usage)} />
          </div>
          <div>
            <div class="flex justify-between text-sm text-gray-600 dark:text-gray-400 mb-1">
              <span>Memory</span>
              <span><%= @system_resources.memory_usage %>%</span>
            </div>
            <.progress_bar value={@system_resources.memory_usage} color={resource_color(@system_resources.memory_usage)} />
          </div>
          <div>
            <div class="flex justify-between text-sm text-gray-600 dark:text-gray-400 mb-1">
              <span>Disk</span>
              <span><%= @system_resources.disk_usage %>%</span>
            </div>
            <.progress_bar value={@system_resources.disk_usage} color={resource_color(@system_resources.disk_usage)} />
          </div>
        </div>
      </div>
      
      <!-- Errors & Warnings -->
      <div class="status-card bg-gray-50 dark:bg-gray-800 rounded-lg p-4">
        <h3 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Issues
        </h3>
        <div class="flex items-center justify-around">
          <button
            class="text-center p-2 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
            phx-click="show_errors"
            phx-target={@myself}
          >
            <div class="text-2xl font-bold text-red-600"><%= @error_count %></div>
            <div class="text-xs text-gray-600 dark:text-gray-400">Errors</div>
          </button>
          <button
            class="text-center p-2 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
            phx-click="show_warnings"
            phx-target={@myself}
          >
            <div class="text-2xl font-bold text-yellow-600"><%= @warning_count %></div>
            <div class="text-xs text-gray-600 dark:text-gray-400">Warnings</div>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp actions_tab(assigns) do
    ~H"""
    <div class="actions-content h-full overflow-y-auto p-4 space-y-4">
      <!-- Quick Actions -->
      <div class="space-y-3">
        <button
          class="w-full action-button"
          phx-click="run_analysis"
          phx-target={@myself}
          disabled={!@current_file}
        >
          <span class="text-lg mr-2">🔍</span>
          <div class="text-left">
            <div class="font-medium">Run Full Analysis</div>
            <div class="text-xs text-gray-500">Analyze current file for issues and improvements</div>
          </div>
        </button>
        
        <button
          class="w-full action-button"
          phx-click="generate_tests"
          phx-target={@myself}
          disabled={!@current_file}
        >
          <span class="text-lg mr-2">🧪</span>
          <div class="text-left">
            <div class="font-medium">Generate Tests</div>
            <div class="text-xs text-gray-500">Create test cases for selected code</div>
          </div>
        </button>
        
        <button
          class="w-full action-button"
          phx-click="suggest_refactoring"
          phx-target={@myself}
          disabled={!@current_file}
        >
          <span class="text-lg mr-2">🔧</span>
          <div class="text-left">
            <div class="font-medium">Suggest Refactoring</div>
            <div class="text-xs text-gray-500">Get AI-powered refactoring suggestions</div>
          </div>
        </button>
        
        <button
          class="w-full action-button"
          phx-click="generate_docs"
          phx-target={@myself}
          disabled={!@current_file}
        >
          <span class="text-lg mr-2">📝</span>
          <div class="text-left">
            <div class="font-medium">Generate Documentation</div>
            <div class="text-xs text-gray-500">Auto-generate docs for functions and modules</div>
          </div>
        </button>
        
        <button
          class="w-full action-button"
          phx-click="security_scan"
          phx-target={@myself}
        >
          <span class="text-lg mr-2">🛡️</span>
          <div class="text-left">
            <div class="font-medium">Security Scan</div>
            <div class="text-xs text-gray-500">Check for security vulnerabilities</div>
          </div>
        </button>
        
        <button
          class="w-full action-button"
          phx-click="optimize_performance"
          phx-target={@myself}
          disabled={!@current_file}
        >
          <span class="text-lg mr-2">⚡</span>
          <div class="text-left">
            <div class="font-medium">Optimize Performance</div>
            <div class="text-xs text-gray-500">Find and fix performance bottlenecks</div>
          </div>
        </button>
      </div>
      
      <!-- Export Options -->
      <div class="border-t border-gray-200 dark:border-gray-700 pt-4">
        <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Export
        </h4>
        <div class="space-y-2">
          <button
            class="w-full text-left px-3 py-2 text-sm bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
            phx-click="export_metrics"
            phx-target={@myself}
          >
            📊 Export Metrics Report
          </button>
          <button
            class="w-full text-left px-3 py-2 text-sm bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
            phx-click="export_analysis"
            phx-target={@myself}
          >
            📄 Export Analysis Results
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
  end

  @impl true
  def handle_event("toggle_search", _params, socket) do
    socket =
      socket
      |> update(:show_search, &(!&1))
      |> assign(:search_query, "")
      |> assign(:search_results, [])

    if socket.assigns.show_search do
      {:noreply, push_event(socket, "focus", %{id: "#{socket.assigns.id}-search"})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> perform_search(query)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, assign(socket, search_query: "", search_results: [])}
  end

  @impl true
  def handle_event("goto_symbol", %{"line" => line}, socket) do
    line_number = String.to_integer(line)
    send(self(), {:goto_line, socket.assigns.current_file, line_number})
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_file", %{"path" => path}, socket) do
    send(self(), {:open_file, path})
    {:noreply, socket}
  end

  @impl true
  def handle_event("run_analysis", _params, socket) do
    socket = run_action(socket, :analysis, "Running full analysis...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_tests", _params, socket) do
    socket = run_action(socket, :generate_tests, "Generating test cases...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("suggest_refactoring", _params, socket) do
    socket = run_action(socket, :refactoring, "Analyzing for refactoring opportunities...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_docs", _params, socket) do
    socket = run_action(socket, :generate_docs, "Generating documentation...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("security_scan", _params, socket) do
    socket = run_action(socket, :security_scan, "Running security scan...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("optimize_performance", _params, socket) do
    socket = run_action(socket, :performance, "Analyzing performance...")
    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_notification", %{"id" => id}, socket) do
    notifications = Enum.reject(socket.assigns.notifications, &(&1.id == id))
    {:noreply, assign(socket, :notifications, notifications)}
  end

  # Public Functions

  @doc """
  Updates the current file and triggers analysis.
  """
  def update_current_file(component_id, file_path) do
    send_update(__MODULE__,
      id: component_id,
      current_file: file_path,
      file_analysis: nil,
      symbol_outline: [],
      related_files: []
    )
  end

  @doc """
  Updates metrics data.
  """
  def update_metrics(component_id, metrics) do
    send_update(__MODULE__,
      id: component_id,
      code_metrics: metrics
    )
  end

  @doc """
  Updates LLM status.
  """
  def update_llm_status(component_id, status) do
    send_update(__MODULE__,
      id: component_id,
      llm_status: status
    )
  end

  @doc """
  Adds a notification.
  """
  def add_notification(component_id, type, message) do
    notification = %{
      id: Ecto.UUID.generate(),
      type: type,
      message: message,
      timestamp: DateTime.utc_now()
    }

    send_update(__MODULE__,
      id: component_id,
      notifications: fn notifications ->
        [notification | notifications] |> Enum.take(5)
      end
    )
  end

  # Private Functions

  defp maybe_load_file_analysis(socket) do
    if socket.assigns.current_file && !socket.assigns.file_analysis do
      send(self(), {:analyze_file, socket.assigns.id, socket.assigns.current_file})
      assign(socket, :loading, true)
    else
      socket
    end
  end

  defp maybe_subscribe(socket) do
    if connected?(socket) && socket.assigns.project_id do
      PubSub.subscribe(RubberDuck.PubSub, "project:#{socket.assigns.project_id}:metrics")
      PubSub.subscribe(RubberDuck.PubSub, "system:status")
    end

    socket
  end

  defp perform_search(socket, "") do
    assign(socket, :search_results, [])
  end

  defp perform_search(socket, _query) do
    # TODO: Implement actual search
    # For now, return mock results
    results = [
      %{type: :symbol, name: "search_result", file: "lib/example.ex", line: 42},
      %{type: :file, name: "search_file.ex", path: "lib/search_file.ex"}
    ]

    assign(socket, :search_results, results)
  end

  defp run_action(socket, action, message) do
    # Send action request to parent
    send(self(), {:run_action, action, socket.assigns.current_file})

    # Add notification
    add_notification(socket.assigns.id, :info, message)

    socket
  end

  # UI Helpers

  defp tab_class(active) do
    base = "px-3 py-1.5 text-sm font-medium rounded-md transition-colors"

    if active do
      base <> " bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300"
    else
      base <> " text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800"
    end
  end

  defp notification_class(type) do
    base = "px-4 py-3 rounded-lg shadow-lg flex items-center justify-between"

    case type do
      :info -> base <> " bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
      :success -> base <> " bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
      :warning -> base <> " bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
      :error -> base <> " bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
      _ -> base <> " bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-200"
    end
  end

  defp symbol_icon(:function), do: "ƒ"
  defp symbol_icon(:module), do: "M"
  defp symbol_icon(:struct), do: "S"
  defp symbol_icon(:macro), do: "μ"
  defp symbol_icon(:callback), do: "@"
  defp symbol_icon(:type), do: "T"
  defp symbol_icon(_), do: "•"

  defp complexity_color(value) when value < 10, do: "text-green-600"
  defp complexity_color(value) when value < 20, do: "text-yellow-600"
  defp complexity_color(_), do: "text-red-600"

  defp coverage_color(value) when value >= 80, do: "text-green-600"
  defp coverage_color(value) when value >= 60, do: "text-yellow-600"
  defp coverage_color(_), do: "text-red-600"

  defp security_color(score) when score >= 90, do: "text-green-600"
  defp security_color(score) when score >= 70, do: "text-yellow-600"
  defp security_color(_), do: "text-red-600"

  defp security_grade(score) when score >= 90, do: "A"
  defp security_grade(score) when score >= 80, do: "B"
  defp security_grade(score) when score >= 70, do: "C"
  defp security_grade(score) when score >= 60, do: "D"
  defp security_grade(_), do: "F"

  defp resource_color(value) when value < 50, do: "bg-green-500"
  defp resource_color(value) when value < 80, do: "bg-yellow-500"
  defp resource_color(_), do: "bg-red-500"

  defp complexity_advice(%{cyclomatic: c, cognitive: cog}) when c < 10 and cog < 15 do
    "Good complexity levels. Code is easy to understand and maintain."
  end

  defp complexity_advice(%{cyclomatic: c, cognitive: cog}) when c < 20 and cog < 30 do
    "Moderate complexity. Consider refactoring complex methods."
  end

  defp complexity_advice(_) do
    "High complexity detected. Refactoring recommended to improve maintainability."
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: to_string(n)

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"

  # Component Functions

  defp metric_bar(assigns) do
    assigns =
      assigns
      |> assign_new(:suffix, fn -> "" end)
      |> assign_new(:color, fn -> "text-gray-600" end)

    ~H"""
    <div>
      <div class="flex justify-between text-sm mb-1">
        <span class="text-gray-600 dark:text-gray-400"><%= @label %></span>
        <span class={[@color, "font-mono"]}><%= @value %><%= @suffix %></span>
      </div>
      <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
        <div 
          class="bg-blue-500 h-2 rounded-full transition-all duration-300"
          style={"width: #{min(100, @value / @max * 100)}%"}
        />
      </div>
    </div>
    """
  end

  defp progress_bar(assigns) do
    assigns = assign_new(assigns, :color, fn -> "bg-blue-500" end)

    ~H"""
    <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
      <div 
        class={[@color, "h-2 rounded-full transition-all duration-300"]}
        style={"width: #{@value}%"}
      />
    </div>
    """
  end
end
