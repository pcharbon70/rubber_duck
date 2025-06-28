# Environment Configuration Guide

This guide explains how to configure RubberDuck for different environments (development, test, and production).

## Configuration Structure

RubberDuck uses a hierarchical configuration system:

1. **Base Configuration** (`config/config.exs`) - Shared settings for all environments
2. **Environment-specific** (`config/dev.exs`, `config/test.exs`, `config/prod.exs`) - Override base settings
3. **Runtime Configuration** (`config/runtime.exs`) - Production runtime configuration from environment variables

## Application Configuration

### Core Application (rubber_duck_core)

```elixir
config :rubber_duck_core,
  ecto_repos: [RubberDuckStorage.Repo],
  pubsub: [
    name: RubberDuckCore.PubSub,
    adapter: Phoenix.PubSub.PG2
  ],
  max_conversation_messages: 1000,        # Maximum messages per conversation
  conversation_retention_days: 90,        # Days to retain conversations
  debug_mode: false,                      # Enable debug logging
  log_level: :info                        # Logging level
```

### Storage Application (rubber_duck_storage)

```elixir
config :rubber_duck_storage,
  ecto_repos: [RubberDuckStorage.Repo],
  cache_ttl: :timer.hours(1),            # Cache time-to-live
  cache_max_size: 1000,                  # Maximum cache entries
  log_queries: false                     # Log database queries
```

### Engines Application (rubber_duck_engines)

```elixir
config :rubber_duck_engines,
  engine_pool_size: 10,                  # Worker pool size
  engine_timeout: :timer.seconds(30),    # Analysis timeout
  max_concurrent_analyses: 5,            # Concurrent analysis limit
  engines: [
    code_analysis: %{
      enabled: true,
      max_file_size: 1_000_000
    },
    documentation: %{
      enabled: true,
      cache_results: true
    },
    testing: %{
      enabled: true,
      test_frameworks: [:ex_unit, :espec]
    }
  ]
```

### Web Application (rubber_duck_web)

```elixir
config :rubber_duck_web,
  debug_websockets: false,               # WebSocket debug logging
  websocket_timeout: :timer.hours(1),    # WebSocket connection timeout
  dev_routes: false                      # Enable development routes
```

## Environment-Specific Settings

### Development (`config/dev.exs`)

- Database: Local PostgreSQL with debug logging
- Smaller pool sizes for resource efficiency
- Shorter cache TTLs for rapid development
- Debug mode enabled
- All engines enabled with verbose output

### Test (`config/test.exs`)

- Database: Sandboxed connections for parallel testing
- Minimal pool sizes and timeouts
- Disabled caching
- Only essential engines enabled
- Warning-level logging

### Production (`config/prod.exs`)

- Database: Configured via environment variables
- Larger pool sizes for performance
- Longer cache TTLs
- All engines enabled with production settings
- Info-level logging
- SSL/TLS support

## Runtime Configuration

For production deployments, use environment variables:

### Required Variables

```bash
# Database
DATABASE_URL=ecto://user:pass@host/database
SECRET_KEY_BASE=<64+ character secret>

# Web Server
PHX_HOST=example.com
PORT=4000
```

### Optional Variables

```bash
# Pool Configuration
POOL_SIZE=10
DB_CONNECT_TIMEOUT=15000
DB_HANDSHAKE_TIMEOUT=15000
DB_QUEUE_TARGET=5000
DB_QUEUE_INTERVAL=10000

# Application Settings
MAX_CONVERSATION_MESSAGES=1000
CONVERSATION_RETENTION_DAYS=90
CACHE_TTL_HOURS=1
CACHE_MAX_SIZE=10000
ENGINE_POOL_SIZE=20
MAX_CONCURRENT_ANALYSES=10

# Monitoring
APPSIGNAL_PUSH_API_KEY=your_key
SENTRY_DSN=your_dsn
HOSTNAME=your_hostname

# Clustering
RELEASE_NODE=rubber_duck@host
CLUSTER_NAME=rubber_duck_prod
```

## Configuration Helpers

### Getting Configuration Values

```elixir
# Get with default
RubberDuckCore.Config.get(:rubber_duck_core, :debug_mode, false)

# Get required (raises if missing)
RubberDuckCore.Config.get!(:rubber_duck_core, :max_conversation_messages)

# App-specific helpers
RubberDuckStorage.Config.cache_ttl()
RubberDuckEngines.Config.enabled_engines()
RubberDuckWeb.Config.websocket_timeout()
```

### Environment Detection

```elixir
# Check current environment
RubberDuckCore.Environment.dev?()
RubberDuckCore.Environment.test?()
RubberDuckCore.Environment.prod?()

# Execute environment-specific code
RubberDuckCore.Environment.when_dev(fn ->
  IO.puts("Development only code")
end)

# Get environment-specific values
timeout = RubberDuckCore.Environment.if_env(
  dev: :timer.minutes(5),
  test: :timer.seconds(1),
  prod: :timer.hours(1)
)
```

## Validation

Configuration is validated at startup:

1. Required keys must be present
2. Values must be the correct type
3. Numeric values must be positive
4. Production requires additional security settings

Validation happens automatically when the application starts. Any configuration errors will prevent startup with a clear error message.

## Best Practices

1. **Never commit secrets** - Use environment variables for sensitive data
2. **Use configuration helpers** - Don't access Application.get_env directly
3. **Validate early** - Fail fast with clear error messages
4. **Document changes** - Update this guide when adding new configuration
5. **Test all environments** - Ensure configuration works in dev, test, and prod