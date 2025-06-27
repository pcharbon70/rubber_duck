defmodule RubberDuckCore.Application do
  @moduledoc """
  The RubberDuckCore Application.

  This is the main OTP application for the core business logic of the RubberDuck
  coding assistant system. It provides the central supervision tree and manages
  core services that other applications depend on.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for process discovery
      {Registry, keys: :unique, name: RubberDuckCore.Registry},

      # Core supervisor for business logic processes
      RubberDuckCore.Supervisor
    ]

    opts = [strategy: :one_for_one, name: RubberDuckCore.Application.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Returns the list of child specifications for the application supervisor.
  """
  def children do
    [
      {Registry, keys: :unique, name: RubberDuckCore.Registry},
      RubberDuckCore.Supervisor
    ]
  end
end
