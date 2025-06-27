import Config

# Configure your database
# config :rubber_duck_storage, RubberDuckStorage.Repo,
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   database: "rubber_duck_test#{System.get_env("MIX_TEST_PARTITION")}",
#   pool: Ecto.Adapters.SQL.Sandbox,
#   pool_size: 10

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
