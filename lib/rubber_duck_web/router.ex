defmodule RubberDuckWeb.Router do
  use RubberDuckWeb, :router

  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RubberDuckWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug AshAuthentication.Strategy.ApiKey.Plug,
      resource: RubberDuck.Accounts.User,
      # if you want to require an api key to be supplied, set `required?` to true
      required?: false

    plug :load_from_bearer
  end

  scope "/", RubberDuckWeb do
    pipe_through :browser
    
    get "/", PageController, :home

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {RubberDuckWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", RubberDuckWeb do
    pipe_through [:browser]
    auth_routes AuthController, RubberDuck.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{RubberDuckWeb.LiveUserAuth, :live_no_user}],
                  overrides: [RubberDuckWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [RubberDuckWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
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
