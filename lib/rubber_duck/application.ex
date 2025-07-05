defmodule RubberDuck.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RubberDuck.Repo,
      RubberDuck.Telemetry,
      # Registry for circuit breakers
      {Registry, keys: :unique, name: RubberDuck.CircuitBreakerRegistry}
      # Error boundary GenServer - started manually in tests
      # RubberDuck.ErrorBoundary
    ]

    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
