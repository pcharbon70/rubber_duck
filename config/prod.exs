import Config

# Tower configuration for production
# Configure based on your production error tracking needs
config :tower,
  reporters: [
    # Example Sentry configuration (requires tower_sentry)
    # [
    #   module: TowerSentry,
    #   dsn: System.get_env("SENTRY_DSN"),
    #   environment: "production"
    # ],
    
    # Email reporter for critical errors
    [
      module: TowerEmail,
      to: System.get_env("ERROR_EMAIL_TO"),
      from: System.get_env("ERROR_EMAIL_FROM", "errors@rubberduck.ai"),
      # Only email on critical errors
      level: :critical
    ],
    
    # Slack reporter for errors
    # [
    #   module: TowerSlack,
    #   webhook_url: System.get_env("SLACK_WEBHOOK_URL"),
    #   channel: "#errors",
    #   level: :error
    # ]
  ]
