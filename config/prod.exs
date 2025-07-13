import Config

# Tower configuration for production
# Configure based on your production error tracking needs
config :tower,
  reporters: [
    # Example Sentry configuration (requires tower_sentry)
    # TowerSentry,

    # Email reporter for critical errors
    TowerEmail

    # Slack reporter for errors
    # TowerSlack
  ],
  log_level: :critical

# TowerEmail configuration
config :tower_email,
  otp_app: :rubber_duck,
  to: System.get_env("ERROR_EMAIL_TO"),
  from: System.get_env("ERROR_EMAIL_FROM", "errors@rubberduck.ai"),
  environment: "production"
