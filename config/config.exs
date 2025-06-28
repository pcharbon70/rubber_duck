import Config

# Configuration for the umbrella project and its applications

# Core application configuration
config :rubber_duck_core,
  ecto_repos: [RubberDuckStorage.Repo],
  # PubSub configuration
  pubsub: [
    name: RubberDuckCore.PubSub,
    adapter: Phoenix.PubSub.PG2
  ],
  # Conversation limits
  max_conversation_messages: 1000,
  conversation_retention_days: 90

# Storage application configuration
config :rubber_duck_storage,
  ecto_repos: [RubberDuckStorage.Repo],
  # Cache configuration
  cache_ttl: :timer.hours(1),
  cache_max_size: 1000

# Engines application configuration
config :rubber_duck_engines,
  # Engine pool configuration
  engine_pool_size: 10,
  engine_timeout: :timer.seconds(30),
  max_concurrent_analyses: 5,
  # Engine-specific settings
  engines: [
    code_analysis: %{
      enabled: true,
      max_file_size: 1_000_000  # 1MB
    },
    documentation: %{
      enabled: true,
      cache_results: true
    },
    testing: %{
      enabled: true,
      test_frameworks: [:ex_unit, :espec]
    }
  ]

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
