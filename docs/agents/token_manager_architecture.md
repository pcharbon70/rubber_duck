# Token Manager Agent Architecture

## Overview

The Token Manager Agent provides centralized token usage tracking, budget management, cost optimization, and comprehensive analytics for all LLM operations across the RubberDuck system. It acts as a financial controller for AI resource consumption, ensuring efficient and cost-effective use of language models.

## Core Components

### 1. Token Manager Agent

The main agent (`TokenManagerAgent`) coordinates all token management activities:

- **Real-time Usage Tracking**: Records every LLM request with detailed attribution
- **Budget Enforcement**: Checks and enforces spending limits before approving requests
- **Cost Calculation**: Computes costs based on provider-specific pricing models
- **Analytics Generation**: Produces reports and recommendations
- **Buffer Management**: Efficiently batches usage data for persistence

### 2. Data Models

#### TokenUsage
Represents a single LLM request's token consumption:
```elixir
%TokenUsage{
  id: String.t(),
  timestamp: DateTime.t(),
  provider: String.t(),
  model: String.t(),
  prompt_tokens: integer(),
  completion_tokens: integer(),
  total_tokens: integer(),
  cost: Decimal.t(),
  currency: String.t(),
  user_id: String.t(),
  project_id: String.t(),
  team_id: String.t(),
  feature: String.t(),
  request_id: String.t(),
  metadata: map()
}
```

#### Budget
Manages spending limits with flexible time periods:
```elixir
%Budget{
  id: String.t(),
  name: String.t(),
  type: :global | :team | :user | :project,
  entity_id: String.t(),
  period: :daily | :weekly | :monthly | :yearly,
  limit: Decimal.t(),
  spent: Decimal.t(),
  remaining: Decimal.t(),
  alert_thresholds: [integer()],
  override_policy: map(),
  active: boolean()
}
```

#### UsageReport
Comprehensive analytics report:
```elixir
%UsageReport{
  period_start: DateTime.t(),
  period_end: DateTime.t(),
  total_tokens: integer(),
  total_cost: Decimal.t(),
  provider_breakdown: map(),
  model_breakdown: map(),
  trends: map(),
  recommendations: [map()],
  anomalies: [map()]
}
```

### 3. Processing Pipeline

#### Usage Tracking Flow
1. **Signal Reception**: Receives `track_usage` signal from provider agents
2. **Cost Calculation**: Computes cost based on pricing models
3. **Buffer Update**: Adds to in-memory buffer for efficiency
4. **Metrics Update**: Updates real-time metrics
5. **Buffer Flush**: Periodically persists to storage

#### Budget Checking Flow
1. **Request Validation**: Receives `check_budget` signal
2. **Budget Discovery**: Finds all applicable budgets (user, project, global)
3. **Availability Check**: Verifies sufficient funds in all budgets
4. **Request Tracking**: Records active request for reconciliation
5. **Approval/Denial**: Returns decision with violations if any

### 4. Cost Calculation System

#### Pricing Models
Provider-specific pricing with per-token rates:
```elixir
%{
  "openai" => %{
    "gpt-4" => %{prompt: 0.03, completion: 0.06, unit: 1000},
    "gpt-3.5-turbo" => %{prompt: 0.0015, completion: 0.002, unit: 1000}
  },
  "anthropic" => %{
    "claude-3-opus" => %{prompt: 0.015, completion: 0.075, unit: 1000},
    "claude-3-sonnet" => %{prompt: 0.003, completion: 0.015, unit: 1000}
  }
}
```

#### Cost Optimization
- **Model Comparison**: Analyzes cost differences between models
- **Usage Pattern Analysis**: Identifies optimization opportunities
- **ROI Calculation**: Evaluates implementation cost vs. savings

### 5. Analytics Engine

#### Report Types
1. **Usage Reports**: Token consumption patterns and breakdowns
2. **Cost Reports**: Financial analysis and projections
3. **Optimization Reports**: Recommendations for cost reduction

#### Trend Analysis
- **Hourly Distribution**: Peak usage times identification
- **Growth Rate**: Usage trend calculation
- **Cost per Token**: Efficiency tracking over time

#### Anomaly Detection
- **Usage Spikes**: Unusual consumption patterns
- **Cost Anomalies**: Expensive requests identification
- **Pattern Deviations**: Behavioral changes detection

## Signal Interface

### Usage Tracking Signals
- `track_usage`: Record token consumption from providers
- `get_usage`: Query historical usage data
- `aggregate_usage`: Get aggregated metrics

### Budget Management Signals
- `check_budget`: Verify budget availability
- `create_budget`: Set up new spending limits
- `update_budget`: Modify existing budgets
- `get_budget_status`: Check current budget state
- `request_override`: Request budget limit override

### Analytics Signals
- `generate_report`: Create comprehensive reports
- `get_trends`: Analyze usage patterns
- `forecast_usage`: Predict future consumption
- `get_recommendations`: Get optimization suggestions

### Configuration Signals
- `update_pricing`: Modify provider pricing models
- `configure_manager`: Update system settings
- `get_status`: Health and status check

## Performance Characteristics

### Efficiency Features
- **Buffer Management**: Batches usage data to reduce I/O
- **Asynchronous Processing**: Non-blocking budget checks
- **Caching**: Frequently accessed data cached in memory
- **Scheduled Tasks**: Background maintenance operations

### Scalability Design
- **Horizontal Scaling**: Stateless design allows multiple instances
- **Time-Series Optimization**: Efficient storage for historical data
- **Aggregation Strategies**: Pre-computed metrics for fast queries
- **Resource Limits**: Automatic cleanup of old data

## Configuration Options

```elixir
%{
  buffer_size: 100,              # Usage records before flush
  flush_interval: 5_000,         # Milliseconds between flushes
  retention_days: 90,            # Historical data retention
  alert_channels: ["email"],     # Alert delivery methods
  budget_check_mode: :async,     # Async or sync budget checks
  optimization_enabled: true     # Enable recommendations
}
```

## Integration Architecture

### With Provider Agents
- **Usage Data Flow**: Provider agents send usage after each request
- **Cost Attribution**: Detailed metadata for granular tracking
- **Real-time Updates**: Immediate budget impact calculation

### With LLM Router
- **Budget Pre-approval**: Router checks budgets before routing
- **Cost-based Routing**: Influence routing based on costs
- **Efficiency Metrics**: Track router decision quality

### With Client Applications
- **Dashboard Integration**: Real-time usage visualization
- **Alert Delivery**: Budget warnings and notifications
- **Report Access**: On-demand analytics generation

## Security and Compliance

### Access Control
- **Role-based Permissions**: Budget management by role
- **Entity Isolation**: Users see only their data
- **Override Workflow**: Approval required for limit bypass

### Audit Trail
- **Complete History**: All usage tracked permanently
- **Budget Changes**: Modification history maintained
- **Override Records**: Approval documentation stored

### Data Privacy
- **Anonymization**: User data can be anonymized
- **Retention Policies**: Automatic old data cleanup
- **Export Controls**: Secure data export mechanisms

## Optimization Strategies

### Model Selection
- **Task Complexity Analysis**: Match model to task difficulty
- **Cost-Performance Trade-offs**: Balance quality vs. cost
- **Provider Comparison**: Choose most economical provider

### Usage Patterns
- **Caching Opportunities**: Identify repeated requests
- **Batch Processing**: Group similar requests
- **Off-peak Scheduling**: Utilize lower-cost periods

### Prompt Engineering
- **Token Reduction**: Optimize prompt length
- **Response Limiting**: Control completion length
- **Template Optimization**: Efficient reusable prompts

## Monitoring and Alerting

### Key Metrics
- **Usage Rate**: Tokens per minute/hour/day
- **Cost Burn Rate**: Spending velocity
- **Budget Utilization**: Percentage consumed
- **Efficiency Scores**: Tokens per dollar

### Alert Conditions
- **Budget Thresholds**: 50%, 80%, 90% warnings
- **Anomaly Detection**: Unusual usage patterns
- **Cost Spikes**: Sudden expense increases
- **Quota Exhaustion**: Approaching limits

## Future Enhancements

### Planned Features
1. **ML-based Forecasting**: Advanced usage prediction
2. **Automated Optimization**: Self-adjusting parameters
3. **Multi-currency Support**: Global cost tracking
4. **Provider Negotiation**: Volume-based pricing

### Integration Opportunities
1. **Finance Systems**: Direct billing integration
2. **Project Management**: Task-based attribution
3. **CI/CD Pipelines**: Development cost tracking
4. **Analytics Platforms**: Enhanced reporting

## Best Practices

### Budget Management
1. **Hierarchical Limits**: Set cascading budgets
2. **Regular Reviews**: Monthly budget assessments
3. **Alert Response**: Act on threshold warnings
4. **Override Documentation**: Record all exceptions

### Cost Optimization
1. **Model Right-sizing**: Use appropriate models
2. **Prompt Efficiency**: Minimize token usage
3. **Response Caching**: Avoid duplicate requests
4. **Regular Audits**: Review usage patterns

### Monitoring
1. **Dashboard Usage**: Regular monitoring
2. **Report Generation**: Weekly/monthly reports
3. **Anomaly Investigation**: Quick response to alerts
4. **Trend Analysis**: Identify long-term patterns