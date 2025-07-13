import Config

config :rubber_duck, RubberDuck.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOSTNAME", "localhost"),
  database: "rubber_duck_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Tower configuration for development
# Reports errors to console for easy debugging
config :tower,
  reporters: [
    # Console reporter for development
    %{
      module: Tower.LogReporter,
      level: :error
    }
  ]

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :rubber_duck, RubberDuckWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 5555],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "PqJKNgP5kH+qWGVfNgCjKRv8RvRqvO8u4OJFkqUQxPqnYdqXy8vHJOe7L3fKCXhI",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :rubber_duck, RubberDuckWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/rubber_duck_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard
config :rubber_duck, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# LLM Provider configuration for development
config :rubber_duck, :llm,
  providers: [
    # Mock provider for testing without external dependencies
    %{
      name: :mock,
      adapter: RubberDuck.LLM.Providers.Mock,
      default: true,
      models: ["mock-gpt", "mock-codellama"],
      responses: [
        # Add mock responses for development
        %{
          pattern: ~r/hello world/i,
          response: "def hello_world do\n  IO.puts(\"Hello, World!\")\nend"
        },
        %{
          pattern: ~r/genserver/i,
          response: """
          defmodule MyServer do
            use GenServer
            
            def start_link(opts) do
              GenServer.start_link(__MODULE__, opts, name: __MODULE__)
            end
            
            @impl true
            def init(opts) do
              {:ok, %{}}
            end
          end
          """
        }
      ]
    },
    # Ollama provider for local LLM
    %{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: "http://localhost:11434",
      models: ["llama2", "codellama", "mistral"],
      timeout: 60_000
    }
  ]
