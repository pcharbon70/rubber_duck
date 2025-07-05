# Base Tower configuration
import Config

# Common ignored exceptions across all environments
config :tower,
  # Capture errors at :error level and above
  log_level: :error,
  
  # Common metadata to capture with all errors
  logger_metadata: [
    :request_id,
    :trace_id,
    :user_id,
    :project_id,
    :engine,
    :action
  ],
  
  # Exceptions to ignore across all environments
  ignored_exceptions: [
    # Ecto errors that are expected in normal operation
    Ecto.NoResultsError,
    Ecto.StaleEntryError,
    
    # Phoenix routing errors for 404s
    Phoenix.Router.NoRouteError,
    
    # Expected websocket disconnections
    Phoenix.Socket.InvalidMessageError
  ]

# Environment-specific configurations are in:
# - config/dev.exs
# - config/test.exs  
# - config/prod.exs