defmodule RubberDuckWeb.StatusDashboardLive do
  @moduledoc """
  Live dashboard for monitoring the Status Broadcasting System.
  
  Provides real-time visualization of:
  - System health metrics
  - Message throughput
  - Channel activity
  - Performance optimization status
  - Alert monitoring
  """
  
  use RubberDuckWeb, :live_view
  
  on_mount {RubberDuckWeb.LiveUserAuth, :live_user_required}
  
  alias RubberDuck.Status.{Monitor, Optimizer, Debug}
  
  @refresh_interval 1000  # Update every second
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
      
      # Subscribe to telemetry events
      subscribe_to_telemetry()
    end
    
    socket =
      socket
      |> assign(:page_title, "Status System Dashboard")
      |> assign_initial_state()
      |> fetch_metrics()
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="status-dashboard">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Status Broadcasting System Dashboard</h1>
        <p class="mt-2 text-sm text-gray-600">Real-time monitoring and performance metrics</p>
      </div>
      
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <.metric_card title="Health Status" value={@health_status} type="status" />
        <.metric_card title="Queue Depth" value={@queue_depth} type="number" />
        <.metric_card title="Active Channels" value={@active_channels} type="number" />
        <.metric_card title="Throughput" value="#{@throughput} msg/s" type="rate" />
      </div>
      
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <.panel title="System Metrics">
          <.metrics_table metrics={@metrics} />
        </.panel>
        
        <.panel title="Active Alerts">
          <.alerts_list alerts={@alerts} />
        </.panel>
      </div>
      
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <.panel title="Optimization Settings">
          <.optimization_status optimizations={@optimizations} />
        </.panel>
        
        <.panel title="Channel Activity">
          <.channel_list channels={@top_channels} />
        </.panel>
      </div>
      
      <div class="mt-6">
        <.panel title="System Health Check">
          <.health_check_results health_check={@health_check} />
        </.panel>
      </div>
    </div>
    """
  end
  
  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, fetch_metrics(socket)}
  end
  
  @impl true
  def handle_info({:telemetry_event, event, measurements, metadata}, socket) do
    socket = update_from_telemetry(socket, event, measurements, metadata)
    {:noreply, socket}
  end
  
  # Private Functions
  
  defp assign_initial_state(socket) do
    socket
    |> assign(:health_status, :unknown)
    |> assign(:queue_depth, 0)
    |> assign(:active_channels, 0)
    |> assign(:throughput, 0)
    |> assign(:metrics, %{})
    |> assign(:alerts, [])
    |> assign(:optimizations, %{})
    |> assign(:top_channels, [])
    |> assign(:health_check, %{})
  end
  
  defp fetch_metrics(socket) do
    # Fetch health status
    health_status = 
      case Monitor.health_status() do
        {:ok, status} -> status.status
        _ -> :unknown
      end
    
    # Fetch queue stats
    queue_stats = Debug.dump_queue()
    
    # Fetch metrics summary
    metrics_summary = 
      case Monitor.metrics_summary() do
        {:ok, summary} -> summary
        _ -> %{}
      end
    
    # Fetch recent alerts
    alerts = 
      case Monitor.recent_alerts(5) do
        {:ok, alerts} -> alerts
        _ -> []
      end
    
    # Fetch optimization settings
    optimizations = 
      case Optimizer.get_optimizations() do
        {:ok, opts} -> opts
        _ -> %{}
      end
    
    # Fetch top channels
    top_channels = Debug.list_channels(limit: 5)
    
    # Perform health check
    health_check = Debug.health_check()
    
    socket
    |> assign(:health_status, health_status)
    |> assign(:queue_depth, queue_stats.queue_size)
    |> assign(:active_channels, length(top_channels))
    |> assign(:throughput, calculate_throughput(metrics_summary))
    |> assign(:metrics, format_metrics(metrics_summary))
    |> assign(:alerts, alerts)
    |> assign(:optimizations, optimizations)
    |> assign(:top_channels, top_channels)
    |> assign(:health_check, health_check)
  end
  
  defp calculate_throughput(metrics_summary) do
    throughput_stats = Map.get(metrics_summary, :throughput, %{})
    Map.get(throughput_stats, :current, 0) |> Float.round(2)
  end
  
  defp format_metrics(metrics_summary) do
    Enum.map(metrics_summary, fn {metric_type, stats} ->
      %{
        type: format_metric_name(metric_type),
        current: format_metric_value(metric_type, Map.get(stats, :current)),
        average: format_metric_value(metric_type, Map.get(stats, :average)),
        min: format_metric_value(metric_type, Map.get(stats, :min)),
        max: format_metric_value(metric_type, Map.get(stats, :max))
      }
    end)
  end
  
  defp format_metric_name(metric_type) do
    metric_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
  
  defp format_metric_value(:error_rate, value) when is_number(value) do
    "#{Float.round(value * 100, 2)}%"
  end
  defp format_metric_value(:latency, value) when is_number(value) do
    "#{round(value)}ms"
  end
  defp format_metric_value(:throughput, value) when is_number(value) do
    "#{Float.round(value, 2)} msg/s"
  end
  defp format_metric_value(_, value) when is_number(value) do
    if is_float(value), do: Float.round(value, 2), else: value
  end
  defp format_metric_value(_, value), do: value || "-"
  
  defp subscribe_to_telemetry do
    events = [
      [:rubber_duck, :status, :monitor, :health],
      [:rubber_duck, :status, :monitor, :alert],
      [:rubber_duck, :status, :optimizer, :adjusted]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "dashboard-#{Enum.join(event, "-")}",
        event,
        &handle_telemetry_event/4,
        self()
      )
    end)
  end
  
  defp handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
  
  defp update_from_telemetry(socket, event, _measurements, _metadata) do
    case event do
      [:rubber_duck, :status, :monitor, :health] ->
        # Trigger immediate refresh on health change
        fetch_metrics(socket)
        
      [:rubber_duck, :status, :monitor, :alert] ->
        # Refresh alerts
        fetch_metrics(socket)
        
      [:rubber_duck, :status, :optimizer, :adjusted] ->
        # Refresh optimization settings
        fetch_metrics(socket)
        
      _ ->
        socket
    end
  end
  
  # Component Functions
  
  defp metric_card(assigns) do
    ~H"""
    <div class="bg-white overflow-hidden shadow rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-1">
            <dt class="text-sm font-medium text-gray-500 truncate">
              <%= @title %>
            </dt>
            <dd class={"mt-1 text-3xl font-semibold text-gray-900 #{status_color(@type, @value)}"}>
              <%= @value %>
            </dd>
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp panel(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">
          <%= @title %>
        </h3>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
  
  defp metrics_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead>
          <tr>
            <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Metric</th>
            <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Current</th>
            <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Average</th>
            <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Min/Max</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200">
          <tr :for={metric <- @metrics}>
            <td class="px-3 py-2 text-sm text-gray-900"><%= metric.type %></td>
            <td class="px-3 py-2 text-sm text-gray-500"><%= metric.current %></td>
            <td class="px-3 py-2 text-sm text-gray-500"><%= metric.average %></td>
            <td class="px-3 py-2 text-sm text-gray-500"><%= metric.min %> / <%= metric.max %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
  
  defp alerts_list(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @alerts == [] do %>
        <p class="text-sm text-gray-500">No active alerts</p>
      <% else %>
        <div :for={alert <- @alerts} class={"p-3 rounded-md #{alert_bg_color(alert.level)}"}>
          <div class="flex">
            <div class="flex-1">
              <p class={"text-sm font-medium #{alert_text_color(alert.level)}"}>
                <%= alert.message %>
              </p>
              <p class={"text-xs #{alert_text_color(alert.level)} opacity-75"}>
                <%= format_timestamp(alert.timestamp) %>
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
  
  defp optimization_status(assigns) do
    ~H"""
    <dl class="space-y-2">
      <div class="flex justify-between">
        <dt class="text-sm font-medium text-gray-500">Batch Size</dt>
        <dd class="text-sm text-gray-900"><%= @optimizations[:batch_size] || "-" %></dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-sm font-medium text-gray-500">Flush Interval</dt>
        <dd class="text-sm text-gray-900"><%= @optimizations[:flush_interval] || "-" %>ms</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-sm font-medium text-gray-500">Compression</dt>
        <dd class="text-sm text-gray-900">
          <%= if @optimizations[:compression], do: "Enabled", else: "Disabled" %>
        </dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-sm font-medium text-gray-500">Sharding</dt>
        <dd class="text-sm text-gray-900">
          <%= if @optimizations[:sharding], do: "Enabled", else: "Disabled" %>
        </dd>
      </div>
    </dl>
    """
  end
  
  defp channel_list(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if @channels == [] do %>
        <p class="text-sm text-gray-500">No active channels</p>
      <% else %>
        <div :for={channel <- @channels} class="flex justify-between items-center py-2">
          <div>
            <p class="text-sm font-medium text-gray-900">
              <%= String.slice(channel.conversation_id, 0..7) %>...
            </p>
            <p class="text-xs text-gray-500">
              <%= channel.subscribers %> subscribers
            </p>
          </div>
          <span class="text-sm text-gray-500">
            <%= channel.message_count %> messages
          </span>
        </div>
      <% end %>
    </div>
    """
  end
  
  defp health_check_results(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium text-gray-900">Overall Status</span>
        <span class={"px-2 py-1 text-xs rounded-full #{health_badge_class(@health_check.healthy)}"}>
          <%= if @health_check.healthy, do: "Healthy", else: "Issues Detected" %>
        </span>
      </div>
      
      <div class="space-y-2">
        <div :for={check <- @health_check[:checks] || []} class="flex items-center justify-between py-1">
          <span class="text-sm text-gray-600"><%= format_component_name(check.component) %></span>
          <span class={"text-sm #{if check.healthy, do: "text-green-600", else: "text-red-600"}"}>
            <%= check.message %>
          </span>
        </div>
      </div>
      
      <%= if @health_check[:recommendations] && @health_check[:recommendations] != [] do %>
        <div class="mt-4 p-3 bg-yellow-50 rounded-md">
          <h4 class="text-sm font-medium text-yellow-800 mb-2">Recommendations</h4>
          <ul class="text-sm text-yellow-700 space-y-1">
            <li :for={rec <- @health_check[:recommendations]}>• <%= rec %></li>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end
  
  # Helper Functions
  
  defp status_color("status", :healthy), do: "text-green-600"
  defp status_color("status", :degraded), do: "text-yellow-600"
  defp status_color("status", :unhealthy), do: "text-red-600"
  defp status_color("status", _), do: "text-gray-600"
  defp status_color(_, _), do: ""
  
  defp alert_bg_color(:critical), do: "bg-red-50"
  defp alert_bg_color(:warning), do: "bg-yellow-50"
  defp alert_bg_color(_), do: "bg-blue-50"
  
  defp alert_text_color(:critical), do: "text-red-800"
  defp alert_text_color(:warning), do: "text-yellow-800"
  defp alert_text_color(_), do: "text-blue-800"
  
  defp health_badge_class(true), do: "bg-green-100 text-green-800"
  defp health_badge_class(false), do: "bg-red-100 text-red-800"
  
  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.to_string()
    |> String.split(".")
    |> List.first()
  end
  
  defp format_component_name(component) do
    component
    |> to_string()
    |> String.capitalize()
  end
end