import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

if config_env() == :prod do
  # Database configuration
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :rubber_duck_storage, RubberDuckStorage.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    # Increase timeout for cloud databases
    connect_timeout: String.to_integer(System.get_env("DB_CONNECT_TIMEOUT") || "15000"),
    handshake_timeout: String.to_integer(System.get_env("DB_HANDSHAKE_TIMEOUT") || "15000"),
    queue_target: String.to_integer(System.get_env("DB_QUEUE_TARGET") || "5000"),
    queue_interval: String.to_integer(System.get_env("DB_QUEUE_INTERVAL") || "10000")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :rubber_duck_web, RubberDuckWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :rubber_duck_web, RubberDuckWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :rubber_duck_web, RubberDuckWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :rubber_duck_web, RubberDuckWeb.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Production-specific runtime configurations

  # Core runtime config
  config :rubber_duck_core,
    max_conversation_messages: 
      String.to_integer(System.get_env("MAX_CONVERSATION_MESSAGES") || "1000"),
    conversation_retention_days: 
      String.to_integer(System.get_env("CONVERSATION_RETENTION_DAYS") || "90")

  # Storage runtime config
  config :rubber_duck_storage,
    cache_ttl: 
      String.to_integer(System.get_env("CACHE_TTL_HOURS") || "1") * 60 * 60 * 1000,
    cache_max_size: 
      String.to_integer(System.get_env("CACHE_MAX_SIZE") || "10000")

  # Engines runtime config
  config :rubber_duck_engines,
    engine_pool_size: 
      String.to_integer(System.get_env("ENGINE_POOL_SIZE") || "20"),
    max_concurrent_analyses: 
      String.to_integer(System.get_env("MAX_CONCURRENT_ANALYSES") || "10")

  # Configure telemetry and monitoring
  if appsignal_key = System.get_env("APPSIGNAL_PUSH_API_KEY") do
    config :appsignal, :config,
      active: true,
      push_api_key: appsignal_key,
      env: :prod,
      hostname: System.get_env("HOSTNAME")
  end

  # Configure error tracking
  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: :prod,
      enable_source_code_context: true,
      root_source_code_path: File.cwd!(),
      tags: %{
        env: "production"
      }
  end
end

# Common runtime configurations for all environments

# Configure the Endpoint
config :rubber_duck_web, RubberDuckWeb.Endpoint,
  server: true

# Configure cluster for distributed deployments
if System.get_env("RELEASE_NODE") do
  config :rubber_duck_core,
    cluster_strategy: :dns,
    cluster_name: System.get_env("CLUSTER_NAME") || "rubber_duck"
end