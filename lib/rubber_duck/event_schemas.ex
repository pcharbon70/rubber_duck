defmodule RubberDuck.EventSchemas do
  @moduledoc """
  Unified event schemas and topic organization for the distributed system.
  
  This module defines standardized event structures and topic hierarchies
  for consistent event broadcasting across all system components.
  
  ## Topic Organization
  
  Topics follow a hierarchical dot-notation structure:
  
  - `context.*` - Session and context management events
  - `model.*` - Model coordination and health events  
  - `provider.*` - LLM provider status and performance events
  - `cluster.*` - Node membership and coordination events
  - `metrics.*` - Performance and usage metrics events
  - `system.*` - General system events and notifications
  
  ## Event Types
  
  All events include:
  - `id` - Unique event identifier
  - `topic` - Hierarchical topic string
  - `payload` - Event-specific data
  - `timestamp` - Event creation time
  - `source_node` - Originating cluster node
  - `priority` - Event priority level
  - `metadata` - Additional context information
  """

  @type event_priority :: :low | :normal | :high | :critical
  @type event_id :: String.t()
  @type topic :: String.t()
  
  @type base_event :: %{
    id: event_id(),
    topic: topic(),
    payload: map(),
    timestamp: non_neg_integer(),
    source_node: node(),
    priority: event_priority(),
    metadata: map()
  }

  # Context Management Events

  @doc """
  Session lifecycle events.
  
  Topics: context.session.created, context.session.updated, context.session.deleted
  """
  @type session_event :: %{
    session_id: String.t(),
    user_id: String.t() | nil,
    operation: :created | :updated | :deleted,
    changes: map() | nil,
    timestamp: DateTime.t()
  }

  @doc """
  Message events for context updates.
  
  Topics: context.message.added, context.message.updated
  """
  @type message_event :: %{
    session_id: String.t(),
    message_id: String.t(),
    role: :user | :assistant | :system,
    content: String.t(),
    metadata: map(),
    timestamp: DateTime.t()
  }

  @doc """
  Context synchronization events.
  
  Topics: context.sync.requested, context.sync.completed, context.sync.failed
  """
  @type context_sync_event :: %{
    session_id: String.t(),
    sync_type: :full | :incremental,
    source_node: node(),
    target_node: node() | :all,
    status: :requested | :in_progress | :completed | :failed,
    error_reason: String.t() | nil
  }

  # Model Coordination Events

  @doc """
  Model health status changes.
  
  Topics: model.health.changed, model.health.warning, model.health.critical
  """
  @type model_health_event :: %{
    model_name: String.t(),
    provider: String.t(),
    health_status: :healthy | :degraded | :unhealthy,
    previous_status: :healthy | :degraded | :unhealthy | nil,
    reason: String.t() | nil,
    metrics: map(),
    timestamp: DateTime.t()
  }

  @doc """
  Model selection and assignment events.
  
  Topics: model.selection.requested, model.selection.assigned, model.selection.failed
  """
  @type model_selection_event :: %{
    session_id: String.t(),
    requested_criteria: map(),
    selected_model: String.t() | nil,
    selection_reason: String.t(),
    fallback_used: boolean(),
    timestamp: DateTime.t()
  }

  @doc """
  Model usage tracking events.
  
  Topics: model.usage.start, model.usage.end, model.usage.error
  """
  @type model_usage_event :: %{
    session_id: String.t(),
    model_name: String.t(),
    operation: String.t(),
    status: :started | :completed | :failed,
    duration_ms: non_neg_integer() | nil,
    token_count: non_neg_integer() | nil,
    cost: float() | nil,
    error_details: map() | nil
  }

  # Provider Management Events

  @doc """
  Provider status and availability changes.
  
  Topics: provider.status.changed, provider.status.unavailable, provider.status.recovered
  """
  @type provider_status_event :: %{
    provider_name: String.t(),
    status: :available | :degraded | :unavailable,
    previous_status: :available | :degraded | :unavailable | nil,
    reason: String.t() | nil,
    affected_models: [String.t()],
    estimated_recovery: DateTime.t() | nil
  }

  @doc """
  Provider performance metrics.
  
  Topics: provider.metrics.latency, provider.metrics.throughput, provider.metrics.cost
  """
  @type provider_metrics_event :: %{
    provider_name: String.t(),
    metric_type: :latency | :throughput | :error_rate | :cost,
    value: float(),
    unit: String.t(),
    window_size: non_neg_integer(),
    timestamp: DateTime.t()
  }

  @doc """
  Load balancer routing decisions.
  
  Topics: provider.routing.selected, provider.routing.failed, provider.routing.fallback
  """
  @type provider_routing_event :: %{
    request_id: String.t(),
    selected_provider: String.t() | nil,
    routing_strategy: String.t(),
    selection_criteria: map(),
    fallback_used: boolean(),
    routing_time_ms: non_neg_integer()
  }

  # Cluster Coordination Events

  @doc """
  Node membership changes.
  
  Topics: cluster.node.joined, cluster.node.left, cluster.node.partitioned
  """
  @type cluster_node_event :: %{
    node_name: node(),
    event_type: :joined | :left | :partitioned | :recovered,
    cluster_size: non_neg_integer(),
    affected_services: [String.t()],
    timestamp: DateTime.t()
  }

  @doc """
  Distributed coordination events.
  
  Topics: cluster.coordination.election, cluster.coordination.failover, cluster.coordination.rebalance
  """
  @type cluster_coordination_event :: %{
    coordination_type: :leader_election | :failover | :rebalance | :split_brain,
    affected_nodes: [node()],
    coordinator_node: node() | nil,
    status: :started | :completed | :failed,
    details: map()
  }

  # Metrics and Monitoring Events

  @doc """
  System performance metrics.
  
  Topics: metrics.performance.cpu, metrics.performance.memory, metrics.performance.network
  """
  @type system_metrics_event :: %{
    metric_name: String.t(),
    value: float(),
    unit: String.t(),
    node: node(),
    tags: map(),
    timestamp: DateTime.t()
  }

  @doc """
  Application-level metrics.
  
  Topics: metrics.application.requests, metrics.application.errors, metrics.application.latency
  """
  @type application_metrics_event :: %{
    service: String.t(),
    metric_type: :counter | :gauge | :histogram,
    name: String.t(),
    value: float(),
    labels: map(),
    timestamp: DateTime.t()
  }

  # System Events

  @doc """
  General system notifications.
  
  Topics: system.startup, system.shutdown, system.error, system.warning
  """
  @type system_event :: %{
    event_type: :startup | :shutdown | :error | :warning | :info,
    component: String.t(),
    message: String.t(),
    details: map() | nil,
    severity: :low | :medium | :high | :critical,
    timestamp: DateTime.t()
  }

  # Event Creation Helpers

  @doc """
  Create a session lifecycle event.
  """
  def session_event(session_id, operation, changes \\ nil, opts \\ []) do
    %{
      session_id: session_id,
      user_id: Keyword.get(opts, :user_id),
      operation: operation,
      changes: changes,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a message event.
  """
  def message_event(session_id, message_id, role, content, metadata \\ %{}) do
    %{
      session_id: session_id,
      message_id: message_id,
      role: role,
      content: content,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a model health event.
  """
  def model_health_event(model_name, provider, health_status, opts \\ []) do
    %{
      model_name: model_name,
      provider: provider,
      health_status: health_status,
      previous_status: Keyword.get(opts, :previous_status),
      reason: Keyword.get(opts, :reason),
      metrics: Keyword.get(opts, :metrics, %{}),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a model selection event.
  """
  def model_selection_event(session_id, criteria, selected_model, reason, fallback \\ false) do
    %{
      session_id: session_id,
      requested_criteria: criteria,
      selected_model: selected_model,
      selection_reason: reason,
      fallback_used: fallback,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a model usage event.
  """
  def model_usage_event(session_id, model_name, operation, status, opts \\ []) do
    %{
      session_id: session_id,
      model_name: model_name,
      operation: operation,
      status: status,
      duration_ms: Keyword.get(opts, :duration_ms),
      token_count: Keyword.get(opts, :token_count),
      cost: Keyword.get(opts, :cost),
      error_details: Keyword.get(opts, :error_details)
    }
  end

  @doc """
  Create a provider status event.
  """
  def provider_status_event(provider_name, status, opts \\ []) do
    %{
      provider_name: provider_name,
      status: status,
      previous_status: Keyword.get(opts, :previous_status),
      reason: Keyword.get(opts, :reason),
      affected_models: Keyword.get(opts, :affected_models, []),
      estimated_recovery: Keyword.get(opts, :estimated_recovery)
    }
  end

  @doc """
  Create a provider metrics event.
  """
  def provider_metrics_event(provider_name, metric_type, value, unit, window_size \\ 60) do
    %{
      provider_name: provider_name,
      metric_type: metric_type,
      value: value,
      unit: unit,
      window_size: window_size,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a cluster node event.
  """
  def cluster_node_event(node_name, event_type, cluster_size, affected_services \\ []) do
    %{
      node_name: node_name,
      event_type: event_type,
      cluster_size: cluster_size,
      affected_services: affected_services,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a system event.
  """
  def system_event(event_type, component, message, opts \\ []) do
    %{
      event_type: event_type,
      component: component,
      message: message,
      details: Keyword.get(opts, :details),
      severity: Keyword.get(opts, :severity, :medium),
      timestamp: DateTime.utc_now()
    }
  end

  # Topic Helpers

  @doc """
  Get all defined topic patterns.
  """
  def topic_patterns do
    [
      # Context management
      "context.session.*",
      "context.message.*", 
      "context.sync.*",
      
      # Model coordination
      "model.health.*",
      "model.selection.*",
      "model.usage.*",
      
      # Provider management  
      "provider.status.*",
      "provider.metrics.*",
      "provider.routing.*",
      
      # Cluster coordination
      "cluster.node.*",
      "cluster.coordination.*",
      
      # Metrics and monitoring
      "metrics.performance.*",
      "metrics.application.*",
      
      # System events
      "system.*"
    ]
  end

  @doc """
  Validate topic format.
  """
  def valid_topic?(topic) when is_binary(topic) do
    String.match?(topic, ~r/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$/)
  end
  def valid_topic?(_), do: false

  @doc """
  Get suggested topic for an event type.
  """
  def suggest_topic(:session_created), do: "context.session.created"
  def suggest_topic(:session_updated), do: "context.session.updated"
  def suggest_topic(:session_deleted), do: "context.session.deleted"
  def suggest_topic(:message_added), do: "context.message.added"
  def suggest_topic(:model_health_changed), do: "model.health.changed"
  def suggest_topic(:model_selected), do: "model.selection.assigned"
  def suggest_topic(:provider_status_changed), do: "provider.status.changed"
  def suggest_topic(:node_joined), do: "cluster.node.joined"
  def suggest_topic(:system_startup), do: "system.startup"
  def suggest_topic(_), do: "system.general"
end