defmodule RubberDuck.LLMAbstraction.MonitoringSupervisor do
  @moduledoc """
  Supervisor for LLM monitoring and telemetry components.
  
  This supervisor manages the lifecycle of monitoring components including
  metrics collection, performance monitoring, and telemetry systems.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, %{})
    
    children = [
      # Metrics collector for aggregating telemetry data
      {RubberDuck.LLMAbstraction.MetricsCollector, [config: config]},
      
      # Performance monitor for real-time monitoring and alerting
      {RubberDuck.LLMAbstraction.PerformanceMonitor, [config: config]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end