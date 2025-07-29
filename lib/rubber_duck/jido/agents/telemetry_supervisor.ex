defmodule RubberDuck.Jido.Agents.TelemetrySupervisor do
  @moduledoc """
  Supervisor for telemetry-related processes.
  
  This supervisor manages:
  - WorkflowMonitor for workflow metrics
  - Telemetry event handlers
  - Metrics reporters
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    children = [
      # Workflow Monitor
      {RubberDuck.Jido.Agents.WorkflowMonitor, []},
      
      # Telemetry poller for system metrics
      {:telemetry_poller,
       measurements: [
         {RubberDuck.Jido.Agents.TelemetryPoller, :dispatch_system_metrics, []}
       ],
       period: :timer.seconds(10),
       name: :rubber_duck_telemetry_poller}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end