defmodule RubberDuckEngines.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for engine process discovery
      {Registry, keys: :unique, name: RubberDuckEngines.Registry},

      # Dynamic supervisor for engine processes
      RubberDuckEngines.EngineSupervisor,

      # Engine pool supervisor with rest_for_one strategy
      RubberDuckEngines.EnginePool.Supervisor,

      # Engine manager for coordination
      {RubberDuckEngines.EngineManager, [name: RubberDuckEngines.EngineManager]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RubberDuckEngines.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
