defmodule RubberDuckWeb.Router do
  @moduledoc """
  Router for RubberDuckWeb application.

  Defines the HTTP routes and websocket endpoints for the RubberDuck
  coding assistant system.
  """

  use RubberDuckWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", RubberDuckWeb do
    pipe_through(:api)

    get("/health", HealthController, :index)
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:rubber_duck_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:api)

      live_dashboard("/dashboard", metrics: RubberDuckWeb.Telemetry)
    end
  end
end
