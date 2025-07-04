import Config

config :rubber_duck, RubberDuck.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rubber_duck_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
