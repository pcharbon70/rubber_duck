defmodule RubberDuckWeb.Live.CacheMonitorLive do
  @moduledoc """
  LiveView dashboard for monitoring cache performance and statistics.
  
  Provides real-time visibility into:
  - Cache hit/miss ratios
  - Memory usage
  - Hot keys
  - Performance metrics
  - Per-project statistics
  """
  
  use RubberDuckWeb, :live_view
  alias RubberDuck.Projects.CacheStats
  alias RubberDuck.Projects.FileCacheWrapper
  alias Phoenix.PubSub
  
  @refresh_interval :timer.seconds(5)
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to cache events
      PubSub.subscribe(RubberDuck.PubSub, "cache:stats")
      
      # Schedule periodic refresh
      schedule_refresh()
    end
    
    socket = socket
    |> assign(:page_title, "Cache Monitor")
    |> assign(:loading, true)
    |> load_stats()
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-8">Cache Performance Monitor</h1>
      
      <div :if={@loading} class="text-center py-12">
        <div class="inline-flex items-center">
          <svg class="animate-spin h-5 w-5 mr-3" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          Loading cache statistics...
        </div>
      </div>
      
      <div :if={!@loading}>
        <!-- Global Stats -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Global Statistics</h2>
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Hit Rate</dt>
              <dd class="mt-1 text-3xl font-semibold text-gray-900">
                <%= @global_stats.hit_rate %>%
              </dd>
            </div>
            
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Total Operations</dt>
              <dd class="mt-1 text-3xl font-semibold text-gray-900">
                <%= format_number(@global_stats.total_hits + @global_stats.total_misses) %>
              </dd>
            </div>
            
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Memory Usage</dt>
              <dd class="mt-1 text-3xl font-semibold text-gray-900">
                <%= format_bytes(@global_stats.total_memory_bytes) %>
              </dd>
            </div>
            
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Cache Entries</dt>
              <dd class="mt-1 text-3xl font-semibold text-gray-900">
                <%= format_number(@file_cache_stats.size) %>
              </dd>
            </div>
          </div>
        </div>
        
        <!-- Performance Metrics -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Performance Metrics</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Operations/Second</dt>
              <dd class="mt-1 text-2xl font-semibold text-gray-900">
                <%= @metrics.operations_per_second %>
              </dd>
            </div>
            
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Avg Memory/Entry</dt>
              <dd class="mt-1 text-2xl font-semibold text-gray-900">
                <%= format_bytes(@metrics.average_memory_per_entry) %>
              </dd>
            </div>
            
            <div class="metric-card">
              <dt class="text-sm font-medium text-gray-500">Efficiency Score</dt>
              <dd class="mt-1 text-2xl font-semibold text-gray-900">
                <%= @metrics.cache_efficiency_score %>%
              </dd>
            </div>
          </div>
        </div>
        
        <!-- Hot Keys -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-xl font-semibold mb-4">Hot Keys (Most Accessed)</h2>
            <div class="space-y-2">
              <div :for={hot_key <- @hot_keys} class="flex items-center justify-between py-2 border-b">
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-gray-900 truncate">
                    <%= hot_key.key %>
                  </p>
                  <p class="text-xs text-gray-500">
                    Hit Rate: <%= hot_key.hit_rate %>%
                  </p>
                </div>
                <div class="ml-4 flex-shrink-0">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    <%= hot_key.access_count %> accesses
                  </span>
                </div>
              </div>
            </div>
          </div>
          
          <!-- Project Statistics -->
          <div class="bg-white shadow rounded-lg p-6">
            <h2 class="text-xl font-semibold mb-4">Project Statistics</h2>
            <div class="space-y-2">
              <div :for={project <- @project_stats} class="flex items-center justify-between py-2 border-b">
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-gray-900">
                    Project <%= project.project_id %>
                  </p>
                  <p class="text-xs text-gray-500">
                    <%= format_bytes(project.memory_bytes) %> • <%= project.hit_rate %>% hit rate
                  </p>
                </div>
                <div class="ml-4 flex-shrink-0 text-right">
                  <p class="text-sm text-gray-900">
                    <%= format_number(project.total_hits + project.total_misses) %>
                  </p>
                  <p class="text-xs text-gray-500">operations</p>
                </div>
              </div>
            </div>
          </div>
        </div>
        
        <!-- Actions -->
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Cache Management</h2>
          <div class="flex space-x-4">
            <button phx-click="reset_stats" class="px-4 py-2 bg-yellow-600 text-white rounded hover:bg-yellow-700">
              Reset Statistics
            </button>
            <button phx-click="clear_cache" data-confirm="Are you sure you want to clear all cache entries?" 
                    class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700">
              Clear Cache
            </button>
            <button phx-click="refresh" class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700">
              Refresh Now
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_stats(socket)}
  end
  
  @impl true
  def handle_event("reset_stats", _params, socket) do
    CacheStats.reset_stats(:all)
    {:noreply, load_stats(socket)}
  end
  
  @impl true
  def handle_event("clear_cache", _params, socket) do
    FileCacheWrapper.clear()
    CacheStats.reset_stats(:all)
    {:noreply, load_stats(socket)}
  end
  
  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_stats(socket)}
  end
  
  @impl true
  def handle_info({:cache_event, _event}, socket) do
    # Handle real-time cache events
    {:noreply, load_stats(socket)}
  end
  
  defp load_stats(socket) do
    # Get global statistics
    {:ok, global_stats} = CacheStats.get_stats(:all)
    {:ok, metrics} = CacheStats.get_metrics()
    
    # Get hot keys for all projects
    hot_keys = get_all_hot_keys()
    
    # Get file cache stats
    file_cache_stats = FileCacheWrapper.stats()
    
    # Extract project stats
    project_stats = Map.get(global_stats, :projects, [])
    
    socket
    |> assign(:loading, false)
    |> assign(:global_stats, global_stats)
    |> assign(:metrics, metrics)
    |> assign(:hot_keys, hot_keys)
    |> assign(:project_stats, project_stats)
    |> assign(:file_cache_stats, file_cache_stats)
  end
  
  defp get_all_hot_keys do
    # Get unique project IDs from stats
    # For now, return an empty list if no projects
    []
  end
  
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
  
  defp format_number(num) when is_number(num) do
    num
    |> round()
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end
  defp format_number(_), do: "0"
  
  defp format_bytes(bytes) when is_number(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 ->
        "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
      bytes >= 1024 * 1024 ->
        "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      bytes >= 1024 ->
        "#{Float.round(bytes / 1024, 2)} KB"
      true ->
        "#{bytes} B"
    end
  end
  defp format_bytes(_), do: "0 B"
end