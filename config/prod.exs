import Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.

config :rubber_duck_web, RubberDuckWeb.Endpoint,
  url: [host: "example.com", port: 80],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: RubberDuckWeb.Finch

# Do not print debug messages in production
config :logger, level: :info

# Production-specific configurations for each app

# Core - Production-optimized settings
config :rubber_duck_core,
  debug_mode: false,
  log_level: :info,
  # Production limits
  max_conversation_messages: 1000,
  conversation_retention_days: 90,
  # Production PubSub
  pubsub: [
    name: RubberDuckCore.PubSub,
    adapter: Phoenix.PubSub.PG2,
    pool_size: 5
  ]

# Storage - Production cache and pool settings
config :rubber_duck_storage,
  cache_ttl: :timer.hours(1),
  cache_max_size: 10_000,
  # Disable query logging in production
  log_queries: false

# Engines - Production pool sizes
config :rubber_duck_engines,
  engine_pool_size: 20,
  engine_timeout: :timer.seconds(30),
  max_concurrent_analyses: 10,
  # Production engine configuration
  engines: [
    code_analysis: %{
      enabled: true,
      max_file_size: 5_000_000,  # 5MB
      debug: false
    },
    documentation: %{
      enabled: true,
      cache_results: true
    },
    testing: %{
      enabled: true,
      test_frameworks: [:ex_unit, :espec],
      verbose: false
    }
  ]

# Web - Production WebSocket settings
config :rubber_duck_web,
  debug_websockets: false,
  websocket_timeout: :timer.hours(1),
  # Enable gzip compression
  gzip: true,
  # Force SSL in production
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
