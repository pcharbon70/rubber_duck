defmodule RubberDuck.Jido.Agents.TelemetryPoller do
  @moduledoc """
  Custom telemetry measurements for the Jido agent system.
  
  This module provides periodic measurements of:
  - Active workflows
  - Agent pool statistics
  - System resource usage
  - Queue depths
  """
  
  alias RubberDuck.Jido.Agents.{Registry, WorkflowMonitor, PoolManager}
  alias RubberDuck.Workflows.Workflow
  
  @doc """
  Dispatches system metrics via telemetry.
  """
  def dispatch_system_metrics do
    # Workflow metrics
    dispatch_workflow_metrics()
    
    # Agent metrics
    dispatch_agent_metrics()
    
    # System metrics
    dispatch_system_resource_metrics()
  end
  
  defp dispatch_workflow_metrics do
    # Get active workflow count
    {:ok, dashboard} = WorkflowMonitor.get_dashboard_data()
    
    :telemetry.execute(
      [:rubber_duck, :workflows, :active],
      %{count: dashboard.active_workflows},
      %{}
    )
    
    :telemetry.execute(
      [:rubber_duck, :workflows, :total],
      %{count: dashboard.total_workflows},
      %{}
    )
    
    # Get workflow statistics from database
    case Ash.read(Workflow) do
      {:ok, workflows} ->
        by_status = Enum.group_by(workflows, & &1.status)
        
        Enum.each([:running, :completed, :failed, :halted], fn status ->
          count = length(Map.get(by_status, status, []))
          
          :telemetry.execute(
            [:rubber_duck, :workflows, :by_status],
            %{count: count},
            %{status: status}
          )
        end)
      _ ->
        :ok
    end
  end
  
  defp dispatch_agent_metrics do
    # Get agent count from registry
    agents = Registry.list_agents()
    
    :telemetry.execute(
      [:rubber_duck, :agents, :total],
      %{count: length(agents)},
      %{}
    )
    
    # Group by status
    by_status = Enum.group_by(agents, & &1.metadata[:status] || :unknown)
    
    Enum.each([:active, :idle, :busy, :error], fn status ->
      count = length(Map.get(by_status, status, []))
      
      :telemetry.execute(
        [:rubber_duck, :agents, :by_status],
        %{count: count},
        %{status: status}
      )
    end)
    
    # Pool metrics if pool manager is running
    case Process.whereis(PoolManager) do
      nil ->
        :ok
      _pid ->
        pools = PoolManager.list_pools()
        
        Enum.each(pools, fn pool ->
          :telemetry.execute(
            [:rubber_duck, :agent_pool, :size],
            %{
              size: pool.size,
              available: pool.available,
              busy: pool.size - pool.available
            },
            %{pool_name: pool.name}
          )
        end)
    end
  end
  
  defp dispatch_system_resource_metrics do
    # Memory usage
    memory_data = :erlang.memory()
    
    :telemetry.execute(
      [:rubber_duck, :system, :memory],
      %{
        total: memory_data[:total],
        processes: memory_data[:processes],
        ets: memory_data[:ets],
        binary: memory_data[:binary]
      },
      %{}
    )
    
    # Process count
    process_count = length(Process.list())
    
    :telemetry.execute(
      [:rubber_duck, :system, :processes],
      %{count: process_count},
      %{}
    )
    
    # Scheduler utilization
    scheduler_usage = :scheduler.utilization(1)
    
    :telemetry.execute(
      [:rubber_duck, :system, :scheduler_usage],
      %{utilization: scheduler_usage},
      %{}
    )
  rescue
    _ ->
      # Ignore errors in metrics collection
      :ok
  end
end