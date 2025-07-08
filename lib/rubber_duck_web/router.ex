defmodule RubberDuckWeb.Router do
  use RubberDuckWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RubberDuckWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check endpoint
  scope "/", RubberDuckWeb do
    pipe_through :api

    get "/health", HealthCheckController, :index
  end

  # API routes
  scope "/api", RubberDuckWeb do
    pipe_through :api

    # Add API routes here
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:rubber_duck, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard("/dashboard", metrics: RubberDuckWeb.Telemetry)
    end
  end
end
