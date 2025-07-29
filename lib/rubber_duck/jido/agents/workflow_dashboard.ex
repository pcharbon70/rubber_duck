defmodule RubberDuck.Jido.Agents.WorkflowDashboard do
  @moduledoc """
  Dashboard view for workflow monitoring.
  
  This module provides formatted views of workflow metrics
  suitable for display in various formats (terminal, web, etc).
  
  ## Example
  
      # Get dashboard summary
      {:ok, summary} = WorkflowDashboard.get_summary()
      
      # Print to terminal
      WorkflowDashboard.print_summary()
      
      # Get JSON representation
      {:ok, json} = WorkflowDashboard.to_json()
  """
  
  alias RubberDuck.Jido.Agents.WorkflowMonitor
  alias RubberDuck.Workflows.{Workflow, Checkpoint}
  
  @doc """
  Gets a formatted dashboard summary.
  """
  def get_summary do
    with {:ok, monitor_data} <- WorkflowMonitor.get_dashboard_data(),
         {:ok, stats} <- WorkflowMonitor.get_statistics(:hour),
         {:ok, db_stats} <- get_database_stats() do
      
      summary = %{
        overview: format_overview(monitor_data, db_stats),
        performance: format_performance(stats, monitor_data),
        health: format_health(monitor_data.health_indicators),
        recent_workflows: format_recent_workflows(monitor_data.recent_metrics),
        alerts: monitor_data.health_indicators.alerts
      }
      
      {:ok, summary}
    end
  end
  
  @doc """
  Prints a formatted summary to the console.
  """
  def print_summary do
    case get_summary() do
      {:ok, summary} ->
        IO.puts(format_terminal_output(summary))
        :ok
      error ->
        error
    end
  end
  
  @doc """
  Returns dashboard data as JSON.
  """
  def to_json do
    case get_summary() do
      {:ok, summary} ->
        {:ok, Jason.encode!(summary)}
      error ->
        error
    end
  end
  
  @doc """
  Gets a real-time stream of workflow updates.
  """
  def subscribe_to_updates do
    WorkflowMonitor.subscribe(self())
  end
  
  @doc """
  Formats workflow metrics for charting.
  """
  def get_chart_data(metric_type, time_window \\ :hour) do
    case WorkflowMonitor.get_statistics(time_window) do
      {:ok, stats} ->
        chart_data = format_chart_data(stats, metric_type)
        {:ok, chart_data}
      error ->
        error
    end
  end
  
  # Private functions
  
  defp get_database_stats do
    # Get stats from database
    workflow_count = case Ash.count(Workflow) do
      {:ok, count} -> count
      _ -> 0
    end
    
    checkpoint_count = case Ash.count(Checkpoint) do
      {:ok, count} -> count
      _ -> 0
    end
    
    # Get recent workflows
    recent_workflows = case Workflow
                           |> Ash.Query.sort(created_at: :desc)
                           |> Ash.Query.limit(10)
                           |> Ash.read() do
      {:ok, workflows} -> workflows
      _ -> []
    end
    
    {:ok, %{
      total_workflows: workflow_count,
      total_checkpoints: checkpoint_count,
      recent_workflows: recent_workflows
    }}
  end
  
  defp format_overview(monitor_data, db_stats) do
    %{
      active_workflows: monitor_data.active_workflows,
      total_workflows: db_stats.total_workflows,
      total_checkpoints: db_stats.total_checkpoints,
      success_rate: monitor_data.aggregate_stats.success_rate,
      health_score: monitor_data.health_indicators.health_score
    }
  end
  
  defp format_performance(stats, monitor_data) do
    %{
      avg_execution_time: format_duration(stats.avg_execution_time),
      throughput: Float.round(stats.throughput, 2),
      success_rate: Float.round(stats.success_rate, 2),
      error_rate: Float.round(stats.error_rate, 2),
      active_count: monitor_data.active_workflows
    }
  end
  
  defp format_health(health_indicators) do
    %{
      score: health_indicators.health_score,
      status: health_status_from_score(health_indicators.health_score),
      trends: health_indicators.trends,
      alerts_count: length(health_indicators.alerts)
    }
  end
  
  defp format_recent_workflows(recent_metrics) do
    Enum.map(recent_metrics, fn workflow ->
      %{
        workflow_id: workflow.workflow_id,
        status: workflow.status,
        started_at: workflow.started_at,
        duration: format_duration(workflow[:duration] || 0),
        steps: %{
          total: workflow.total_steps,
          completed: workflow.completed_steps,
          failed: workflow.failed_steps
        }
      }
    end)
  end
  
  defp format_terminal_output(summary) do
    """
    ╔═══════════════════════════════════════════════════════════════╗
    ║                    Workflow Dashboard                          ║
    ╚═══════════════════════════════════════════════════════════════╝
    
    📊 Overview
    ├─ Active Workflows: #{summary.overview.active_workflows}
    ├─ Total Workflows: #{summary.overview.total_workflows}
    ├─ Total Checkpoints: #{summary.overview.total_checkpoints}
    ├─ Success Rate: #{Float.round(summary.overview.success_rate, 1)}%
    └─ Health Score: #{summary.overview.health_score}/100 #{health_emoji(summary.overview.health_score)}
    
    ⚡ Performance (Last Hour)
    ├─ Avg Execution Time: #{summary.performance.avg_execution_time}
    ├─ Throughput: #{summary.performance.throughput} workflows/min
    ├─ Success Rate: #{summary.performance.success_rate}%
    └─ Error Rate: #{summary.performance.error_rate}%
    
    🏥 Health Status: #{summary.health.status}
    ├─ Execution Time Trend: #{trend_arrow(summary.health.trends.execution_time)}
    ├─ Success Rate Trend: #{trend_arrow(summary.health.trends.success_rate)}
    └─ Throughput Trend: #{trend_arrow(summary.health.trends.throughput)}
    
    #{format_alerts(summary.alerts)}
    
    📋 Recent Workflows
    #{format_recent_workflows_table(summary.recent_workflows)}
    """
  end
  
  defp format_alerts([]), do: "✅ No Active Alerts"
  defp format_alerts(alerts) do
    """
    ⚠️  Active Alerts (#{length(alerts)})
    #{Enum.map_join(alerts, "\n", fn {type, message} ->
      "├─ [#{type}] #{message}"
    end)}
    """
  end
  
  defp format_recent_workflows_table(workflows) do
    if Enum.empty?(workflows) do
      "No recent workflows"
    else
      header = "ID              Status      Duration    Steps"
      separator = "─" |> String.duplicate(50)
      
      rows = Enum.map(workflows, fn wf ->
        id = String.slice(wf.workflow_id, 0..12)
        status = wf.status |> Atom.to_string() |> String.pad_trailing(10)
        duration = String.pad_trailing(wf.duration, 10)
        steps = "#{wf.steps.completed}/#{wf.steps.total}"
        
        "#{id}  #{status}  #{duration}  #{steps}"
      end)
      
      [header, separator | rows] |> Enum.join("\n")
    end
  end
  
  defp format_duration(microseconds) when is_number(microseconds) do
    milliseconds = div(microseconds, 1000)
    
    cond do
      milliseconds < 1000 -> "#{milliseconds}ms"
      milliseconds < 60_000 -> "#{Float.round(milliseconds / 1000, 1)}s"
      true -> "#{Float.round(milliseconds / 60_000, 1)}m"
    end
  end
  defp format_duration(_), do: "N/A"
  
  defp health_status_from_score(score) when score >= 90, do: "Excellent"
  defp health_status_from_score(score) when score >= 70, do: "Good"
  defp health_status_from_score(score) when score >= 50, do: "Fair"
  defp health_status_from_score(_), do: "Poor"
  
  defp health_emoji(score) when score >= 90, do: "🟢"
  defp health_emoji(score) when score >= 70, do: "🟡"
  defp health_emoji(score) when score >= 50, do: "🟠"
  defp health_emoji(_), do: "🔴"
  
  defp trend_arrow(:improving), do: "↗️ "
  defp trend_arrow(:declining), do: "↘️ "
  defp trend_arrow(:stable), do: "➡️ "
  defp trend_arrow(_), do: "？"
  
  defp format_chart_data(stats, metric_type) do
    case metric_type do
      :execution_time ->
        %{
          type: "line",
          data: %{
            labels: generate_time_labels(:hour),
            datasets: [%{
              label: "Average Execution Time",
              data: [stats.avg_execution_time]
            }]
          }
        }
      
      :success_rate ->
        %{
          type: "line",
          data: %{
            labels: generate_time_labels(:hour),
            datasets: [%{
              label: "Success Rate",
              data: [stats.success_rate]
            }]
          }
        }
      
      :throughput ->
        %{
          type: "bar",
          data: %{
            labels: generate_time_labels(:hour),
            datasets: [%{
              label: "Workflows/min",
              data: [stats.throughput]
            }]
          }
        }
      
      _ ->
        %{error: "Unknown metric type"}
    end
  end
  
  defp generate_time_labels(:hour) do
    # Generate labels for the last hour
    Enum.map(0..5, fn i ->
      DateTime.utc_now()
      |> DateTime.add(-i * 10, :minute)
      |> DateTime.to_time()
      |> Time.to_string()
      |> String.slice(0..4)
    end)
    |> Enum.reverse()
  end
end