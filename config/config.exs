import Config

# Configuration for the umbrella project and its applications

# Configure Phoenix for the web application
config :rubber_duck_web,
  generators: [context_app: :rubber_duck_core]

# Configures the endpoint
config :rubber_duck_web, RubberDuckWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: RubberDuckWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: RubberDuckWeb.PubSub,
  live_view: [signing_salt: "rubber_duck_live_view_salt"]

# Asset building configuration would go here in a full web application
# For now, we're focusing on WebSocket/API functionality

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"