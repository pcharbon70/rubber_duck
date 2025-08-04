# Signal Processing Pipeline Documentation

This document describes the signal processing pipeline that provides transformation, enrichment, validation, security filtering, and monitoring for signals in the RubberDuck platform. All signals remain CloudEvents-compliant through Jido.Signal.

## Overview

The signal processing pipeline ensures consistent signal handling through a series of transformers and monitors. Signals flow through normalization, enrichment, validation, and security filtering while being monitored for delivery and performance.

## Architecture

```
Signal Input
    ↓
[Pipeline Orchestrator]
    ↓
[Transformers]
    ├── Normalizer (priority: 100)
    ├── Enricher (priority: 90)
    ├── Schema Validator (priority: 80)
    └── Security Filter (priority: 70)
    ↓
[Monitors]
    ├── Delivery Tracker
    └── Metrics Collector
    ↓
Processed Signal Output
```

## Components

### Signal Transformers

Transformers modify signals as they flow through the pipeline. Each transformer implements the `SignalTransformer` behaviour.

#### 1. Signal Normalizer

Ensures consistent signal structure and CloudEvents compliance.

**Features:**
- Converts string/atom keys consistently
- Maps common field variations to standard names
- Adds missing required fields with defaults
- Ensures hierarchical type format (domain.action)
- Validates CloudEvents requirements

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.SignalNormalizer

# Normalize a signal
{:ok, normalized} = SignalNormalizer.transform(signal, [
  key_format: :atom,  # or :string
  field_mappings: %{"eventType" => :type},
  defaults: %{id: fn -> generate_id() end}
])
```

#### 2. Signal Enricher

Adds contextual information and metadata to signals.

**Enrichment Types:**
- **Metadata**: Node info, enrichment timestamps
- **Category**: Infers and adds signal category
- **Correlation**: Adds correlation and trace IDs
- **Context**: Adds environment, version, tenant info
- **Routing**: Generates routing keys
- **Security**: Adds auth context
- **Telemetry**: Adds sampling flags

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.SignalEnricher

{:ok, enriched} = SignalEnricher.transform(signal, [
  enrichers: [:metadata, :category, :correlation],
  context: %{
    environment: "production",
    version: "1.0.0",
    tenant: "acme"
  },
  correlation_id: "corr_123"
])
```

#### 3. Schema Validator

Validates signals against defined schemas.

**Features:**
- Required field validation
- Type checking
- Constraint validation (min/max, regex, etc.)
- Nested data schema validation
- Versioned schema support
- Strict/non-strict modes

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.SchemaValidator

# Define a schema
schema = %{
  required_fields: [:type, :source, :data],
  field_types: %{
    type: :string,
    source: :string,
    data: :map
  },
  data_schema: %{
    user_id: %{type: :string, required: true},
    email: %{type: :string, constraint: {:regex, ~r/@/}}
  }
}

{:ok, validated} = SchemaValidator.transform(signal, [
  schema_registry: %{{"user.created", "1.0"} => schema},
  strict: false  # Log warnings but continue
])
```

#### 4. Security Filter

Removes or masks sensitive data from signals.

**Features:**
- Field-level filtering (passwords, tokens, keys)
- Pattern-based masking (emails, SSNs, credit cards)
- PII detection and redaction
- High-entropy field detection
- Configurable masking strategies
- Emergency filtering on errors

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.SecurityFilter

{:ok, filtered} = SecurityFilter.transform(signal, [
  sensitive_fields: [:password, :api_key, :ssn],
  patterns: %{
    ~r/\d{3}-\d{2}-\d{4}/ => :ssn,
    ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/ => :email
  },
  masking_strategy: :partial,  # :full or :partial
  pii_detection: true,
  whitelist: [:user_id]  # Fields to never filter
])
```

### Signal Monitors

Monitors observe signals and collect metrics without modifying them.

#### 1. Delivery Tracker

Tracks signal delivery status and confirmation.

**Metrics:**
- Total signals processed
- Delivery success/failure rates
- Average delivery latency
- Stuck signals (pending too long)
- Per-type delivery statistics

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.DeliveryTracker

# Track successful delivery
DeliveryTracker.track_delivery(signal_id, handler, latency_ms)

# Track failure
DeliveryTracker.track_failure(signal_id, error, attempts)

# Get metrics
metrics = DeliveryTracker.get_current_metrics()
# => %{
#   delivery_rate: 95.5,
#   stuck_signals: 3,
#   average_latency_ms: 125
# }

# Check health
{status, details} = DeliveryTracker.check_health()
```

#### 2. Metrics Collector

Collects performance metrics for signal processing.

**Metrics:**
- Throughput (current and average)
- Latency percentiles (p50, p90, p95, p99)
- Error rates
- Per-type breakdowns
- Processing time statistics

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.MetricsCollector

# Metrics are collected automatically
metrics = MetricsCollector.get_current_metrics()
# => %{
#   throughput: %{
#     current_per_second: 125.5,
#     average_per_second: 100.2
#   },
#   latency: %{
#     p50: 10,
#     p99: 250
#   },
#   error_rate: 0.5
# }
```

### Pipeline Orchestrator

Coordinates the entire processing pipeline.

**Features:**
- Transformer ordering and execution
- Monitor notification
- Batch processing support
- Health monitoring
- Configuration management
- Telemetry emission

**Usage:**
```elixir
alias RubberDuck.Jido.Signals.Pipeline.PipelineOrchestrator

# Start the orchestrator
{:ok, _pid} = PipelineOrchestrator.start_link([
  transformers: [
    SignalNormalizer,
    SignalEnricher,
    SchemaValidator,
    SecurityFilter
  ],
  monitors: [
    DeliveryTracker,
    MetricsCollector
  ],
  max_concurrency: 10,
  strict_validation: false,
  security_enabled: true
])

# Process a single signal
{:ok, processed} = PipelineOrchestrator.process(signal)

# Process a batch
{:ok, processed_batch} = PipelineOrchestrator.process_batch(signals)

# Check health
health = PipelineOrchestrator.health_check()
# => %{
#   status: :healthy,
#   monitors: [...],
#   stats: %{processed: 1000, errors: 5}
# }

# Get metrics
metrics = PipelineOrchestrator.get_metrics()
```

## Creating Custom Transformers

```elixir
defmodule MyCustomTransformer do
  use RubberDuck.Jido.Signals.Pipeline.SignalTransformer,
    name: "MyTransformer",
    priority: 75
  
  @impl true
  def transform(signal, opts) do
    # Your transformation logic
    transformed = Map.put(signal, :custom_field, "value")
    {:ok, transformed}
  end
  
  @impl true
  def should_transform?(signal, _opts) do
    # Conditional transformation
    Map.get(signal, :type) == "my.signal.type"
  end
end
```

## Creating Custom Monitors

```elixir
defmodule MyCustomMonitor do
  use RubberDuck.Jido.Signals.Pipeline.SignalMonitor,
    name: :my_monitor
  
  @impl true
  def observe(signal, metadata) do
    # Your observation logic
    record_metric(signal.type, metadata.latency)
    :ok
  end
  
  @impl true
  def get_metrics do
    %{
      custom_metric: calculate_metric()
    }
  end
end
```

## Configuration

Configure the pipeline through application config:

```elixir
config :rubber_duck, :signal_pipeline,
  transformers: [
    SignalNormalizer,
    SignalEnricher,
    SchemaValidator,
    SecurityFilter
  ],
  monitors: [
    DeliveryTracker,
    MetricsCollector
  ],
  config: %{
    max_concurrency: 20,
    strict_validation: true,
    security_enabled: true,
    enrichment_ttl: :timer.minutes(10)
  }
```

## Telemetry Events

The pipeline emits telemetry events for monitoring:

- `[:rubber_duck, :signal, :transformer]` - Transformer execution
- `[:rubber_duck, :signal, :pipeline]` - Pipeline processing
- `[:rubber_duck, :signal, :delivery]` - Delivery tracking
- `[:rubber_duck, :signal, :monitor, :*]` - Monitor metrics

## Best Practices

1. **Transformer Ordering**: Use priority values to ensure correct execution order
2. **Error Handling**: Decide between strict validation (fail fast) or lenient (log and continue)
3. **Security First**: Always enable SecurityFilter in production
4. **Monitor Everything**: Use monitors to track pipeline health
5. **Schema Versioning**: Version your schemas for backward compatibility
6. **Batch Processing**: Use batch processing for high-volume scenarios
7. **Custom Enrichment**: Add domain-specific enrichers as needed
8. **Performance**: Monitor latency percentiles, not just averages

## Examples

### Complete Pipeline Setup

```elixir
# Start all components
{:ok, _} = PipelineOrchestrator.start_link([
  transformers: [
    SignalNormalizer,
    {SignalEnricher, [
      context: %{environment: "prod"},
      enrichers: [:metadata, :category, :correlation]
    ]},
    {SchemaValidator, [strict: true]},
    {SecurityFilter, [masking_strategy: :partial]}
  ],
  monitors: [
    DeliveryTracker,
    MetricsCollector
  ]
])

# Process signals
signal = %{
  type: "user.created",
  source: "auth:service",
  data: %{
    user_id: "u123",
    email: "user@example.com",
    password: "secret123"  # Will be filtered
  }
}

{:ok, processed} = PipelineOrchestrator.process(signal)

# Check results
processed.category  # => :event
processed.data.password  # => nil (filtered)
processed.correlation_id  # => "corr_..."
```

### Monitoring Pipeline Health

```elixir
# Set up health monitoring
defmodule PipelineHealthCheck do
  def check do
    health = PipelineOrchestrator.health_check()
    metrics = PipelineOrchestrator.get_metrics()
    
    cond do
      health.status == :unhealthy ->
        alert("Pipeline unhealthy: #{inspect(health)}")
        
      metrics.pipeline_stats.errors > 100 ->
        alert("High error count: #{metrics.pipeline_stats.errors}")
        
      true ->
        :ok
    end
  end
end

# Schedule periodic checks
:timer.apply_interval(:timer.minutes(1), PipelineHealthCheck, :check, [])
```