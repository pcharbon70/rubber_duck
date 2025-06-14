import Config

# Configure Hammer for rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2, cleanup_interval_ms: 60_000]}

# Disable logger during test to reduce noise
config :logger, level: :warning

# Configure test environment
config :rubber_duck, 
  test_mode: true