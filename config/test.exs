import Config

config :rubber_duck, token_signing_secret: "/3CPTIsKiAZ6a1sx+Qi1twAJNxRi1lNK"
config :bcrypt_elixir, log_rounds: 1
config :logger, level: :warning
config :ash, disable_async?: true

config :rubber_duck, RubberDuck.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOSTNAME", "localhost"),
  database: "rubber_duck_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Tower configuration for testing
# Minimal configuration to avoid noise during tests
config :tower,
  reporters: []
