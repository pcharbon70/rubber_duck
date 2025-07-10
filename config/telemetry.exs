import Config

# Telemetry configuration for RubberDuck
config :rubber_duck, :telemetry,
  # Enable/disable telemetry
  enabled: true,

  # Console reporter configuration
  console_reporter: [
    enabled: false,
    level: :info
  ],

  # Polling configuration
  poller: [
    period: :timer.seconds(10),
    measurements: [
      {:process_info, :memory},
      {:process_info, :message_queue_len},
      {:process_info, :reductions}
    ]
  ],

  # Custom metric tags
  default_tags: %{
    environment: to_string(Mix.env()),
    node: node()
  }

# Configure Ecto telemetry
config :rubber_duck, RubberDuck.Repo,
  telemetry_prefix: [:rubber_duck, :repo],
  telemetry_event_prefix: [:rubber_duck, :repo]

# Configure Phoenix telemetry
config :rubber_duck, RubberDuckWeb.Endpoint, instrumenters: [RubberDuck.Telemetry.PhoenixInstrumenter]
