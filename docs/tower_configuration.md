# Tower Error Tracking Configuration

This document describes how error tracking is configured in RubberDuck using the Tower library.

## Overview

RubberDuck uses [Tower](https://hexdocs.pm/tower) for centralized error tracking and reporting. Tower provides a "capture once, report many" architecture that allows us to send errors to multiple services simultaneously.

## Configuration

### Base Configuration

The base Tower configuration is in `config/tower.exs`:

```elixir
config :tower,
  log_level: :error,
  logger_metadata: [
    :request_id,
    :trace_id,
    :user_id,
    :project_id,
    :engine,
    :action
  ],
  ignored_exceptions: [
    Ecto.NoResultsError,
    Ecto.StaleEntryError,
    Phoenix.Router.NoRouteError,
    Phoenix.Socket.InvalidMessageError
  ]
```

### Environment-Specific Configuration

#### Development (`config/dev.exs`)
- Reports errors to console using `Tower.LogReporter`
- Minimal configuration for local debugging

#### Test (`config/test.exs`)
- No reporters configured to avoid noise during tests
- Errors can still be captured but won't be reported

#### Production (`config/prod.exs`)
- Email reporter for critical errors
- Commented examples for Sentry and Slack integration
- Configure with environment variables

## Usage

### Custom Error Types

RubberDuck defines custom error types in `lib/rubber_duck/errors.ex`:

- `RubberDuckError` - Base error type
- `EngineError` - Engine processing errors
- `LLMError` - LLM API errors
- `ConfigurationError` - Configuration errors
- `ServiceUnavailableError` - Service availability errors

### Reporting Errors

```elixir
# Report an exception
try do
  risky_operation()
rescue
  error ->
    RubberDuck.Errors.report_exception(error, __STACKTRACE__,
      user_id: user.id,
      action: "risky_operation"
    )
end

# Report a message
RubberDuck.Errors.report_message(:error, "Something went wrong",
  context: "data_processing",
  details: %{input: input}
)
```

### Error Boundary

The `RubberDuck.ErrorBoundary` GenServer provides crash isolation:

```elixir
{:ok, result} = ErrorBoundary.run(fn ->
  # potentially crashing code
end, timeout: 10_000, retry: 3)
```

### Circuit Breaker

Use circuit breakers for external services:

```elixir
defmodule MyApp.LLMBreaker do
  use RubberDuck.CircuitBreaker,
    name: :llm_service,
    failure_threshold: 5,
    reset_timeout: 60_000
end

case MyApp.LLMBreaker.call(fn -> make_llm_request() end) do
  {:ok, response} -> handle_response(response)
  {:error, :circuit_open} -> handle_circuit_open()
  {:error, reason} -> handle_error(reason)
end
```

## Adding New Reporters

To add a new error tracking service:

1. Add the reporter dependency to `mix.exs`
2. Configure in the appropriate environment config:

```elixir
config :tower,
  reporters: [
    [
      module: TowerSentry,
      dsn: System.get_env("SENTRY_DSN"),
      environment: "production"
    ]
  ]
```

## Monitoring

### Health Checks

The health check endpoint provides system status:

- `/health` - Basic health check
- `/health/ready` - Readiness check (all services ready)
- `/health/live` - Liveness check (app is running)

### Error Statistics

Get error boundary statistics:

```elixir
stats = ErrorBoundary.stats()
# %{success_count: 100, error_count: 5, last_error: {...}}
```

Get circuit breaker state:

```elixir
state = MyApp.LLMBreaker.state()
# %{state: :closed, failure_count: 0, ...}
```

## Best Practices

1. **Use appropriate error types** - Create specific error types for different failure modes
2. **Include metadata** - Always include relevant context when reporting errors
3. **Configure ignored exceptions** - Don't report expected errors like 404s
4. **Use circuit breakers** - Protect against cascading failures in external services
5. **Monitor error rates** - Set up alerts for high error rates
6. **Test error handling** - Ensure error paths are tested

## Environment Variables

Production configuration uses these environment variables:

- `ERROR_EMAIL_TO` - Email address for critical error notifications
- `ERROR_EMAIL_FROM` - From address for error emails (default: errors@rubberduck.ai)
- `SENTRY_DSN` - Sentry DSN (if using Sentry)
- `SLACK_WEBHOOK_URL` - Slack webhook URL (if using Slack)

## Troubleshooting

### Errors not being reported

1. Check Tower configuration for the current environment
2. Verify reporters are properly configured
3. Check if the error type is in `ignored_exceptions`
4. Ensure Tower dependencies are installed

### Circuit breaker issues

1. Check failure threshold configuration
2. Verify reset timeout is appropriate
3. Monitor circuit breaker state
4. Check error reporting for circuit breaker failures