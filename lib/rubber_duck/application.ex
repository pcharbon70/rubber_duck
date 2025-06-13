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
      # Core supervisor for different domains
      {RubberDuck.CoreSupervisor, []},
      # Registry for local process management
      {Registry, keys: :unique, name: RubberDuck.Registry},
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