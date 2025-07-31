# Token Provenance Enhancement

## Overview

The Token Provenance Enhancement adds comprehensive lineage tracking to the Token Manager Agent, enabling detailed audit trails, cost attribution, and optimization analysis for all token usage across the RubberDuck system.

## Implementation Summary

### 1. Core Components

#### TokenProvenance Module (`lib/rubber_duck/agents/token_manager/token_provenance.ex`)
- Captures complete lineage, context, and purpose of every token request
- Tracks hierarchical relationships (parent/root request IDs)
- Records agent context, task types, and intent
- Maintains content hashes for deduplication detection
- Includes system context and metadata

Key features:
- Request lineage tracking with depth calculation
- Workflow and session association
- Signal trail recording
- Content hash generation for deduplication
- Comprehensive validation

#### ProvenanceRelationship Module (`lib/rubber_duck/agents/token_manager/provenance_relationship.ex`)
- Manages relationships between token usage requests
- Supports multiple relationship types:
  - `triggered_by` - Direct causation
  - `part_of` - Workflow membership
  - `derived_from` - Based on previous work
  - `retry_of` - Retry attempts
  - `fallback_for` - Fallback operations
  - `enhancement_of` - Enhancements
  - `validation_of` - Validation checks
  - `continuation_of` - Multi-turn continuations
- Provides graph traversal capabilities
- Cycle detection and prevention
- DOT graph export for visualization

#### ProvenanceAnalyzer Module (`lib/rubber_duck/agents/token_manager/provenance_analyzer.ex`)
- Advanced analytics and insights from provenance data
- Pattern detection:
  - Duplicate request identification
  - Retry storm detection
  - Deep chain analysis
  - Circular dependency detection
  - Expensive pattern identification
- Cost attribution analysis by multiple dimensions
- Optimization recommendation generation
- Agent performance analysis
- Workflow bottleneck identification

### 2. TokenManagerAgent Updates

The Token Manager Agent was enhanced with:

#### State Changes
- Added `provenance_buffer` for storing provenance records
- Added `provenance_graph` for relationship tracking

#### Signal Updates
- Modified `track_usage` to require provenance data
- Added new query signals:
  - `get_provenance` - Retrieve provenance for a specific request
  - `get_lineage` - Get complete lineage tree
  - `get_workflow_usage` - Analyze workflow token usage
  - `analyze_task_costs` - Analyze costs by task type

#### Helper Functions
- `update_provenance_buffer` - Manages provenance buffer
- `get_root_request_id` - Finds root of request chain
- `calculate_request_depth` - Calculates depth in lineage
- Various analysis helpers for provenance queries

### 3. Budget Module Enhancement

Added `add_usage/2` function to support post-facto usage tracking without budget enforcement.

## Usage Examples

### Tracking Usage with Provenance

```elixir
# When tracking token usage, include provenance data
emit_signal("track_usage", %{
  "request_id" => "req_123",
  "provider" => "openai",
  "model" => "gpt-4",
  "prompt_tokens" => 100,
  "completion_tokens" => 50,
  "user_id" => "user_456",
  "project_id" => "proj_789",
  "metadata" => %{},
  "provenance" => %{
    "parent_request_id" => "req_122",
    "workflow_id" => "wf_001",
    "agent_id" => "agent_456",
    "agent_type" => "provider",
    "signal_type" => "generate_response",
    "task_type" => "code_generation",
    "intent" => "implement_feature",
    "input_hash" => "abc123...",
    "tags" => ["feature", "backend"]
  }
})
```

### Querying Provenance

```elixir
# Get provenance for a specific request
{:ok, result, _agent} = handle_signal("get_provenance", %{
  "request_id" => "req_123"
}, agent)

# Get complete lineage tree
{:ok, lineage, _agent} = handle_signal("get_lineage", %{
  "request_id" => "req_123"
}, agent)

# Analyze workflow usage
{:ok, usage, _agent} = handle_signal("get_workflow_usage", %{
  "workflow_id" => "wf_001"
}, agent)

# Analyze task costs
{:ok, analysis, _agent} = handle_signal("analyze_task_costs", %{
  "task_type" => "code_generation"
}, agent)
```

## Benefits

1. **Complete Audit Trail**: Every token usage is tracked with full context
2. **Cost Attribution**: Accurate cost allocation to workflows, tasks, and intents
3. **Pattern Detection**: Identify inefficiencies like duplicate requests and retry storms
4. **Optimization Insights**: Data-driven recommendations for reducing token usage
5. **Workflow Analysis**: Understand token usage across complex workflows
6. **Debugging Support**: Trace request chains to identify issues

## Architecture Notes

- Provenance data is stored in-memory with configurable buffer size
- Relationships are maintained as a graph structure for efficient traversal
- The system emits signals for persistence, allowing external storage
- Analysis is performed on-demand to avoid performance impact
- Provenance tracking is required but lightweight

## Future Enhancements

1. Persistent storage integration
2. Real-time anomaly detection
3. Machine learning-based optimization
4. Visual lineage explorer
5. Automated cost optimization actions