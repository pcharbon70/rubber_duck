# Section 4.2: Mnesia Integration for LLM Data

## Overview

Extended the existing Mnesia schema to support LLM-specific data patterns including response storage, provider metrics, and distributed cache coordination. This implementation provides persistent storage for LLM responses with intelligent caching integration, comprehensive provider health tracking, and automated data lifecycle management.

## Implementation Details

### New Mnesia Tables

#### 1. `llm_responses` Table
**Purpose**: Persistent storage for LLM responses with deduplication and cache integration.

**Schema**:
```elixir
llm_responses: [
  attributes: [
    :response_id,      # Unique response identifier
    :prompt_hash,      # SHA256 hash of prompt for deduplication  
    :provider,         # LLM provider (openai, anthropic, etc.)
    :model,           # Model name (gpt-4, claude-3, etc.)
    :prompt,          # Original prompt text
    :response,        # LLM response text
    :tokens_used,     # Token consumption count
    :cost,            # API call cost in dollars
    :latency,         # Response latency in milliseconds
    :created_at,      # Timestamp when stored
    :expires_at,      # Expiration timestamp for cleanup
    :session_id,      # Session ID for context grouping
    :node             # Node that created the record
  ],
  type: :set,
  storage_type: :disc_copies,
  indexes: [:prompt_hash, :provider, :model, :created_at, :session_id]
]
```

**Key Features**:
- **Deduplication**: Uses prompt hash to identify similar requests
- **Cache Integration**: Automatic integration with Nebulex cache
- **Cost Tracking**: Comprehensive cost and usage metrics
- **Persistent Storage**: Uses `:disc_copies` for durability
- **Indexed Queries**: Optimized for prompt, provider, and temporal queries

#### 2. `llm_provider_status` Table  
**Purpose**: Health and performance metrics for LLM providers.

**Schema**:
```elixir
llm_provider_status: [
  attributes: [
    :provider_id,           # Unique provider identifier
    :provider_name,         # Human-readable provider name
    :status,               # :active, :inactive, :error
    :health_score,         # Health score (0-100)
    :total_requests,       # Total request count
    :successful_requests,  # Successful request count
    :failed_requests,      # Failed request count
    :average_latency,      # Average response latency
    :cost_total,          # Total cost accumulated
    :rate_limit_remaining, # Remaining rate limit
    :rate_limit_reset,     # Rate limit reset timestamp
    :last_updated,         # Last update timestamp
    :node                  # Node managing this provider
  ],
  type: :set,
  storage_type: :disc_copies,
  indexes: [:provider_name, :status, :last_updated]
]
```

**Key Features**:
- **Real-time Health**: Continuous health score monitoring
- **Rate Limit Tracking**: API rate limit awareness
- **Cost Management**: Total cost tracking per provider
- **Performance Metrics**: Latency and success rate tracking

### Data Manager Module

#### `RubberDuck.LLMDataManager`
High-level operations for storing and retrieving LLM data with built-in caching integration and performance optimization.

**Core Functions**:

- **`store_response/2`**: Store LLM response with automatic deduplication
- **`get_response_by_prompt/3`**: Retrieve response by prompt with cache fallback
- **`get_response_stats/1`**: Analytics and usage statistics
- **`update_provider_status/1`**: Update provider health and metrics
- **`get_provider_status/1`**: Retrieve current provider status
- **`find_similar_responses/3`**: Find responses by prompt similarity
- **`get_session_responses/2`**: Get responses for session context
- **`cleanup_expired_data/0`**: Remove expired responses and old metrics

**Integration Features**:
- **Cache-First Strategy**: Checks Nebulex cache before database
- **Automatic Caching**: Stores responses in cache for fast retrieval
- **Smart Expiration**: Content-aware TTL calculation
- **Transaction Safety**: All operations use distributed transactions

### Background Maintenance

#### `RubberDuck.LLMDataMaintenance`
Automated background service for data lifecycle management.

**Features**:
- **Periodic Cleanup**: Removes expired responses every 4 hours
- **Automated Backup**: Creates backups every 24 hours
- **Health Monitoring**: Tracks table sizes and performance metrics
- **Retention Policies**: 30-day response retention, 7-day provider status retention

**Monitoring Capabilities**:
- Table size and memory usage tracking
- Recent activity statistics
- Provider status distribution
- Cleanup and backup success rates

### Backup and Recovery

#### `RubberDuck.LLMBackupManager`
Specialized backup system for LLM data with selective restore capabilities.

**Features**:
- **Selective Backup**: Filter by provider, time range, status
- **Compression**: Automatic backup compression
- **Format Versioning**: Schema migration support
- **Selective Restore**: Choose what data to restore
- **Integrity Verification**: Backup validation and corruption detection

**Backup Options**:
```elixir
# Full backup
LLMBackupManager.create_llm_backup("/path/to/backup.llm")

# Filtered backup (OpenAI only)
LLMBackupManager.create_llm_backup("/path/to/backup.llm", 
  filters: %{provider: "openai"}
)

# Selective restore (responses only)
LLMBackupManager.restore_llm_backup("/path/to/backup.llm",
  restore_responses: true,
  restore_provider_status: false
)
```

### Transaction Integration

Enhanced the existing `TransactionWrapper` to support custom transaction functions for complex operations like cleanup:

```elixir
# Custom transaction function support
TransactionWrapper.write_transaction(:llm_responses, :cleanup, nil, cleanup_fun)
```

This enables complex multi-table operations with proper retry logic and error handling.

## Performance Optimizations

### 1. **Intelligent Indexing**
- Prompt hash index for fast deduplication
- Provider and model indexes for filtered queries
- Temporal indexes for time-based analytics
- Session indexes for context reconstruction

### 2. **Cache Integration**
- Automatic Nebulex cache population
- Cache-first retrieval strategy
- TTL-aware cache expiration
- Response deduplication across cache and database

### 3. **Storage Strategy**
- `:disc_copies` for LLM data persistence
- `:ram_copies` for frequently accessed provider status
- Automatic cleanup of expired data
- Batch operations for bulk inserts

### 4. **Query Optimization**
- Mnesia select operations with proper guards
- Chunked data exports for backup operations
- Efficient pattern matching for cleanup operations

## Data Lifecycle Management

### 1. **Response Lifecycle**
1. **Creation**: Store with prompt hash and expiration
2. **Caching**: Automatic cache population with TTL
3. **Retrieval**: Cache-first with database fallback
4. **Expiration**: Automatic cleanup after TTL
5. **Archival**: Backup before deletion (optional)

### 2. **Provider Status Lifecycle**
1. **Registration**: Initial provider status record
2. **Updates**: Real-time metrics and health updates
3. **Monitoring**: Continuous health score calculation
4. **Cleanup**: Remove old status records after 7 days

### 3. **Backup Lifecycle**
1. **Creation**: Automated daily backups
2. **Compression**: Automatic compression for storage efficiency
3. **Retention**: Keep backups for configurable period
4. **Cleanup**: Remove old backups automatically

## Integration Points

### 1. **Nebulex Cache Integration**
- Seamless cache population and retrieval
- TTL synchronization between cache and database
- Cache invalidation on data updates

### 2. **StateSynchronizer Integration**
- Distributed state change broadcasting
- Conflict resolution for concurrent updates
- Cross-node data synchronization

### 3. **Core Supervisor Integration**
- Automatic startup of LLM data maintenance service
- Proper supervision tree integration
- Graceful shutdown handling

## Configuration Options

```elixir
# Application configuration
config :rubber_duck,
  # Backup settings
  backup_dir: "./backups",
  backup_retention_days: 7,
  
  # Data retention
  llm_response_retention_days: 30,
  llm_provider_status_retention_days: 7,
  
  # Maintenance intervals
  llm_maintenance_interval: :timer.hours(4),
  llm_backup_interval: :timer.hours(24)
```

## Testing Coverage

Comprehensive test suites covering:

### 1. **LLMDataManager Tests**
- Response storage and retrieval
- Deduplication verification
- Statistics calculation
- Provider status management
- Query operations
- Cleanup operations

### 2. **LLMBackupManager Tests**
- Backup creation and verification
- Selective backup with filters
- Compression testing
- Restore operations with options
- Migration between format versions
- Corruption detection

### 3. **Integration Tests**
- Cross-module interaction testing
- Cache integration verification
- Transaction safety validation

## Benefits

### 1. **Performance**
- Fast response retrieval through caching
- Optimized database queries with proper indexing
- Efficient data lifecycle management

### 2. **Reliability**
- Persistent storage with distributed replication
- Automatic backup and recovery
- Transaction safety with retry logic

### 3. **Observability**
- Comprehensive provider health monitoring
- Detailed usage and cost analytics
- Performance metrics and trends

### 4. **Scalability**
- Distributed storage across cluster nodes
- Efficient data partitioning and cleanup
- Configurable retention policies

## Future Enhancements

### 1. **Semantic Search**
- Replace exact hash matching with semantic similarity
- Vector embeddings for prompt similarity
- Advanced response recommendation engine

### 2. **Advanced Analytics**
- Cost optimization recommendations
- Usage pattern analysis
- Provider performance comparison

### 3. **Data Migration**
- Hot migration between storage backends
- Schema evolution with zero downtime
- Cross-environment data synchronization

This implementation provides a robust foundation for LLM data management in distributed environments, with comprehensive features for storage, retrieval, monitoring, and lifecycle management.