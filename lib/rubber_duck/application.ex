defmodule RubberDuck.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RubberDuck.Repo,
      RubberDuck.Telemetry
    ]

    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
