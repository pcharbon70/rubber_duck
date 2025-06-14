defmodule RubberDuck.Application do
  @moduledoc """
  The RubberDuck Application.

  This is the main application module that starts the supervision tree
  for the distributed OTP AI assistant system.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Configure Mnesia for AI workloads before starting supervisors
    # Note: Commented out for now to allow tests to run
    # RubberDuck.MnesiaOptimizer.configure_for_ai_workloads()
    
    children = [
      # Registry for local process management (must start before processes that use it)
      {Registry, keys: :unique, name: RubberDuck.Registry},
      # Query cache for intelligent caching
      {RubberDuck.QueryCache, []},
      # Background tasks for maintenance and optimization
      {RubberDuck.BackgroundTasks, []},
      # Cluster supervisor for distributed operations
      {RubberDuck.ClusterSupervisor, []},
      # Core supervisor for different domains
      {RubberDuck.CoreSupervisor, []},
      # Telemetry supervisor for metrics and monitoring
      {RubberDuck.TelemetrySupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    :ok
  end
end