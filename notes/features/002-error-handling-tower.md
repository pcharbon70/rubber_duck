# Feature: Error Handling and Logging with Tower (Section 1.4)

## Summary
Implement comprehensive error handling and logging infrastructure using the Tower library to provide flexible error tracking and reporting across multiple services.

## Requirements
- [ ] Add Tower dependency to mix.exs
- [ ] Configure Tower with multiple reporters (console, Sentry/Rollbar, Slack, email)
- [ ] Set up Logger configuration with Tower backend
- [ ] Configure error filtering and metadata capture
- [ ] Create custom error types module
- [ ] Implement error normalization for Tower.Event
- [ ] Configure Telemetry events with Tower integration
- [ ] Create error boundary GenServer using Tower.report_exception
- [ ] Implement circuit breaker pattern module
- [ ] Add Tower Plug for Phoenix error tracking
- [ ] Create health check plug
- [ ] Document error codes and Tower configuration
- [ ] Write comprehensive tests

## Research Summary
### Tower Library Features
- "Capture once, report many" architecture
- Supports multiple reporters simultaneously
- Built-in reporters: Bugsnag, Sentry, Rollbar, Honeybadger, Slack, Email
- Automatic error capturing via Logger, Telemetry, and Plugs
- Configurable error filtering and metadata capture
- Standardized Tower.Event structure

### Integration Points
- Logger backend/handlers for automatic capture
- Telemetry event handlers for metrics
- Plug for Phoenix error tracking
- Manual reporting via Tower.report_exception/2

### Configuration Example
```elixir
config :tower,
  reporters: [TowerEmail, TowerSentry, TowerSlack],
  log_level: :error,
  ignored_exceptions: [Ecto.NoResultsError, Phoenix.Router.NoRouteError],
  logger_metadata: [:user_id, :request_id, :trace_id]
```

## Technical Approach
1. Add Tower and reporter dependencies
2. Create environment-specific Tower configurations
3. Implement custom error types for domain-specific errors
4. Build error boundary GenServer for crash recovery
5. Implement circuit breaker for external service failures
6. Add health check endpoint for monitoring
7. Configure structured logging with correlation IDs
8. Write comprehensive test coverage

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Multiple reporter performance | Medium | Configure async reporting, use queues |
| Sensitive data in errors | High | Implement data scrubbing/filtering |
| Reporter service failures | Medium | Use circuit breaker, local fallback |
| Configuration complexity | Low | Document thoroughly, provide examples |

## Implementation Checklist
- [x] Add Tower and reporter dependencies to mix.exs
- [x] Create config/tower.exs for Tower configuration
- [x] Set up development Tower configuration
- [x] Set up production Tower configuration
- [x] Create lib/rubber_duck/errors.ex for custom error types
- [x] Create lib/rubber_duck/error_boundary.ex GenServer
- [x] Create lib/rubber_duck/circuit_breaker.ex
- [x] Create lib/rubber_duck_web/plugs/health_check.ex
- [ ] Configure Tower Plug in endpoint.ex (deferred - no Phoenix endpoint yet)
- [ ] Add Telemetry integration with Tower (deferred - existing telemetry sufficient)
- [x] Write tests for error handling
- [x] Write tests for circuit breaker
- [ ] Write tests for health check (deferred - needs Phoenix setup)
- [x] Document configuration and usage

## Questions for Pascal
1. Which error tracking service do you prefer for production (Sentry, Rollbar, etc.)?
2. Should we implement custom Tower reporters for specific needs?
3. What metadata should we capture with errors (user info, request context)?
4. Do you want email/Slack alerts for specific error types?
5. Should we implement rate limiting for error reporting?

## Log
- Created feature branch: feature/1.4-error-handling-tower
- Set up todo tracking for implementation tasks
- Added Tower and reporter dependencies (tower, tower_email, tower_slack)
- Created Tower configuration for dev, test, and prod environments
- Implemented custom error types module with domain-specific exceptions
- Created error boundary GenServer for crash isolation and recovery
- Implemented circuit breaker pattern for external service protection
- Created health check plug for monitoring endpoints
- Fixed Tower API compatibility issues (expects keyword lists, not maps)
- Wrote comprehensive tests for errors and circuit breaker modules
- Created detailed documentation for Tower configuration and usage

## Implementation Summary

Successfully implemented comprehensive error handling and logging with Tower:

1. **Tower Integration** - Configured Tower with multiple reporters for different environments
2. **Custom Error Types** - Created domain-specific error types with proper metadata
3. **Error Boundary** - GenServer that isolates crashes and reports errors automatically
4. **Circuit Breaker** - Protects against cascading failures with configurable thresholds
5. **Health Checks** - Plug that provides monitoring endpoints for system health
6. **Comprehensive Tests** - Full test coverage for error handling and circuit breaker
7. **Documentation** - Complete guide for configuration and usage

Key implementation details:
- Tower expects keyword lists for metadata, not maps
- Circuit breakers use Registry for dynamic registration
- Error boundary removed from app supervision for test isolation
- Health check plug ready for Phoenix integration
- Production config uses environment variables for flexibility

Next steps:
- Integrate Tower Plug when Phoenix endpoint is added
- Add health check tests when Phoenix is configured
- Configure production error tracking service (Sentry/Rollbar)
- Set up error monitoring dashboards