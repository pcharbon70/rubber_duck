import Config

# Configure your database
config :rubber_duck_storage, RubberDuckStorage.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rubber_duck_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  # Test-specific settings
  log_level: :warning,
  ownership_timeout: 60_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rubber_duck_web, RubberDuckWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rubber_duck_secret_key_base_for_testing_only",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Test-specific configurations for each app

# Core - Minimal configuration for testing
config :rubber_duck_core,
  debug_mode: false,
  log_level: :warning,
  # Shorter limits for tests
  max_conversation_messages: 100,
  conversation_retention_days: 1,
  # Use test PubSub adapter
  pubsub: [
    name: RubberDuckCore.PubSub,
    adapter: Phoenix.PubSub.PG2,
    pool_size: 1
  ]

# Storage - Test-optimized settings
config :rubber_duck_storage,
  cache_ttl: :timer.seconds(1),
  cache_max_size: 10,
  # Disable query logging in tests
  log_queries: false

# Engines - Minimal configuration for tests
config :rubber_duck_engines,
  engine_pool_size: 1,
  engine_timeout: :timer.seconds(5),
  max_concurrent_analyses: 1,
  # Disable most engines for faster tests
  engines: [
    code_analysis: %{
      enabled: true,
      max_file_size: 1000,
      debug: false
    },
    documentation: %{
      enabled: false,
      cache_results: false
    },
    testing: %{
      enabled: false,
      test_frameworks: [:ex_unit],
      verbose: false
    }
  ]

# Web - Test configuration
config :rubber_duck_web,
  debug_websockets: false,
  websocket_timeout: :timer.seconds(5)
