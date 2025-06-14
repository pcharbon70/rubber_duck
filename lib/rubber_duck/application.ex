defmodule RubberDuck.Application do
  @moduledoc """
  The RubberDuck Application.

  This is the main application module that starts the supervision tree
  for the distributed OTP AI assistant system.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for local process management (must start before processes that use it)
      {Registry, keys: :unique, name: RubberDuck.Registry},
      # Global process monitor for automatic cleanup and recovery
      {RubberDuck.Registry.ProcessMonitor, []},
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