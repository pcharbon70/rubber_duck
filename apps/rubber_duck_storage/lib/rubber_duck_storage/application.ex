defmodule RubberDuckStorage.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database repository
      RubberDuckStorage.Repo,

      # Context management GenServer
      RubberDuckStorage.ContextManager,

      # Caching layer
      RubberDuckStorage.Cache
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RubberDuckStorage.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
