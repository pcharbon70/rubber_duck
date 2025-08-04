# Reactor Workflow Integration (Section 15.1.5)

## Overview

The Reactor workflow integration provides a robust DSL for defining and executing complex agent workflows with built-in compensation, retry, and dependency resolution capabilities. This integration bridges the gap between Reactor's powerful workflow engine and RubberDuck's Jido agent system.

## Architecture

### Core Components

1. **WorkflowCoordinator** - Central orchestrator for workflow execution
2. **Workflow Modules** - Reactor-based workflow definitions
3. **Agent Steps** - Specialized Reactor steps for agent interaction
4. **Persistence Layer** - State management and recovery
5. **Monitoring Middleware** - Telemetry and debugging

## Implementation Status

### ✅ Completed Components

#### 15.1.5.1 Reactor-based Workflows
- **SimplePipeline** - Sequential data processing through agents
- **ValidationWorkflow** - Multi-stage validation with error handling
- **TransactionalWorkflow** - ACID-compliant operations across agents
- **ScatterGather** - Parallel execution with result aggregation
- **CompositeWorkflow** - Nested workflow composition

#### 15.1.5.2 Agent Workflow Coordinator
- Full Reactor execution integration
- Context passing for agent state
- Middleware for telemetry and monitoring
- Workflow-to-agent signal translation
- Synchronous and asynchronous execution modes

#### 15.1.5.3 Workflow Persistence
- Reactor's built-in state management integration
- Agent-specific state persistence via WorkflowPersistence module
- Checkpoint integration with recovery mechanisms
- Version management for workflow definitions
- Multiple storage backends (ETS, DETS, future PostgreSQL)

#### 15.1.5.4 Workflow Monitoring
- Custom middleware for agent metrics (WorkflowMiddleware)
- Integration with existing telemetry system
- Step-level timing and performance tracking
- Agent interaction monitoring
- Error and recovery tracking

#### 15.1.5.5 Agent Workflow Library

##### Sequential Patterns
- **Pipeline** - Linear processing with data transformation
- **Waterfall** - Dependent sequential execution

##### Parallel Patterns
- **FanOut** - Broadcast to multiple agents
- **MapReduce** - Distributed computation pattern
- **ScatterGather** - Parallel execution with aggregation

##### Control Flow Patterns
- **CircuitBreaker** - Failure protection with automatic recovery
- **RetryWorkflow** - Configurable retry strategies
- **Saga** - Distributed transactions with compensation

##### Advanced Patterns
- **Consensus** - Multi-agent agreement protocols
- **DynamicWorkflow** - Runtime workflow composition

## Usage Examples

### Simple Pipeline Workflow

```elixir
defmodule MyPipeline do
  use Reactor
  
  alias RubberDuck.Jido.Steps.{SelectAgent, ExecuteAgentAction}
  
  input :data
  
  step :validate, ExecuteAgentAction do
    argument :agent_id, value("validator_agent")
    argument :action, value(ValidateAction)
    argument :params, input(:data)
  end
  
  step :transform, ExecuteAgentAction do
    argument :agent_id, value("transformer_agent")
    argument :action, value(TransformAction)
    argument :params, result(:validate)
  end
  
  return :transform
end

# Execute the workflow
{:ok, result} = WorkflowCoordinator.execute_workflow(
  MyPipeline,
  %{data: input_data}
)
```

### Saga Pattern with Compensation

```elixir
defmodule OrderWorkflow do
  use RubberDuck.Jido.Workflows.Library.Saga
  
  transactions [
    %{
      name: :reserve_inventory,
      agent_capability: :inventory,
      forward: &reserve_items/1,
      compensate: &release_items/1
    },
    %{
      name: :charge_payment,
      agent_capability: :payment,
      forward: &charge_card/1,
      compensate: &refund_payment/1
    },
    %{
      name: :ship_order,
      agent_capability: :shipping,
      forward: &create_shipment/1,
      compensate: &cancel_shipment/1
    }
  ]
end
```

### Async Workflow with Persistence

```elixir
# Start workflow asynchronously
{:ok, workflow_id} = WorkflowCoordinator.start_workflow(
  ComplexWorkflow,
  %{params: data},
  persist: true
)

# Check status
{:ok, status} = WorkflowCoordinator.get_workflow_status(workflow_id)

# Resume if halted
{:ok, result} = WorkflowCoordinator.resume_workflow(workflow_id)
```

## Custom Reactor Steps

### Agent Selection Step

```elixir
step :select_processor, SelectAgent do
  argument :criteria, value({:capability, :processing})
  argument :strategy, value(:least_loaded)
  argument :fallback, value(:round_robin)
end
```

### Signal Emission Step

```elixir
step :notify, SendAgentSignal do
  argument :signal_type, value("workflow.completed")
  argument :data, result(:previous_step)
  argument :target_agents, value([:monitor, :logger])
end
```

### Wait for Response Step

```elixir
step :wait_for_approval, WaitForAgentResponse do
  argument :signal_type, value("approval.request")
  argument :timeout, value(30_000)
  argument :required_agents, value([:supervisor, :manager])
end
```

## Middleware Configuration

### Telemetry Middleware

```elixir
defmodule MyWorkflow do
  use Reactor
  
  middleware [
    {RubberDuck.Jido.Agents.WorkflowMiddleware, 
     telemetry: true,
     metrics: [:duration, :step_count, :agent_interactions]}
  ]
  
  # ... workflow steps
end
```

### Custom Middleware

```elixir
defmodule CustomMiddleware do
  use Reactor.Middleware
  
  @impl true
  def init(context) do
    # Initialize custom tracking
    {:ok, Map.put(context, :custom_data, %{})}
  end
  
  @impl true
  def event({:complete_step, step, result}, context, _opts) do
    # Track custom metrics
    :telemetry.execute(
      [:my_app, :workflow, :custom],
      %{value: extract_metric(result)},
      %{step: step.name}
    )
    {:ok, context}
  end
end
```

## Persistence and Recovery

### Checkpoint Management

```elixir
# Save checkpoint
{:ok, checkpoint_id} = WorkflowPersistence.save_checkpoint(
  workflow_id,
  reactor_state,
  %{step: "payment", progress: 0.5}
)

# Load checkpoint
{:ok, state} = WorkflowPersistence.load_checkpoint(workflow_id)

# List all checkpoints
{:ok, checkpoints} = WorkflowPersistence.list_checkpoints(workflow_id)
```

### Recovery Strategies

```elixir
# Automatic recovery on failure
config :rubber_duck, :workflow_recovery,
  enabled: true,
  max_retries: 3,
  retry_delay: 5_000,
  checkpoint_interval: :after_each_step
```

## Performance Considerations

### Optimization Tips

1. **Agent Selection Caching** - Cache agent selections for repeated workflows
2. **Parallel Execution** - Use async steps when dependencies allow
3. **Batch Operations** - Group related operations to reduce overhead
4. **Connection Pooling** - Reuse agent connections across steps

### Monitoring Metrics

- **Workflow Duration** - Total execution time
- **Step Latency** - Individual step execution times
- **Agent Response Time** - Time spent waiting for agents
- **Queue Depth** - Pending workflow backlog
- **Error Rate** - Failure frequency and patterns

## Testing Workflows

### Unit Testing

```elixir
defmodule MyWorkflowTest do
  use ExUnit.Case
  
  test "workflow completes successfully" do
    assert {:ok, result} = WorkflowCoordinator.execute_workflow(
      MyWorkflow,
      %{input: "test_data"},
      timeout: 5_000
    )
    
    assert result.status == :completed
  end
  
  test "workflow handles errors gracefully" do
    assert {:error, _} = WorkflowCoordinator.execute_workflow(
      MyWorkflow,
      %{input: nil}
    )
  end
end
```

### Integration Testing

```elixir
test "end-to-end workflow with real agents" do
  # Start required agents
  {:ok, _} = start_supervised(RequiredAgent)
  
  # Execute workflow
  {:ok, result} = WorkflowCoordinator.execute_workflow(
    IntegrationWorkflow,
    %{real_data: data}
  )
  
  # Verify side effects
  assert agent_state_updated?()
  assert signals_emitted?()
end
```

## Migration Guide

### Converting GenServer Workflows to Reactor

#### Before (GenServer-based)
```elixir
def handle_call({:process, data}, _from, state) do
  with {:ok, validated} <- validate(data),
       {:ok, transformed} <- transform(validated),
       {:ok, stored} <- store(transformed) do
    {:reply, {:ok, stored}, state}
  else
    error -> {:reply, error, state}
  end
end
```

#### After (Reactor-based)
```elixir
defmodule ProcessingWorkflow do
  use Reactor
  
  input :data
  
  step :validate do
    argument :data, input(:data)
    run &Validator.validate/1
  end
  
  step :transform do
    argument :data, result(:validate)
    run &Transformer.transform/1
  end
  
  step :store do
    argument :data, result(:transform)
    run &Storage.store/1
  end
  
  return :store
end
```

## Best Practices

1. **Keep Workflows Simple** - Break complex workflows into composable pieces
2. **Use Compensation** - Always define rollback logic for critical operations
3. **Monitor Everything** - Add telemetry to track workflow health
4. **Test Failure Paths** - Ensure workflows handle errors gracefully
5. **Document Dependencies** - Clearly specify required agents and capabilities
6. **Version Workflows** - Use version management for production workflows
7. **Cache Strategically** - Cache expensive operations but maintain consistency

## Troubleshooting

### Common Issues

1. **Workflow Timeout**
   - Increase timeout in workflow options
   - Check agent availability and response times
   - Review step dependencies for bottlenecks

2. **State Recovery Failure**
   - Verify persistence backend is accessible
   - Check checkpoint integrity
   - Review error logs for corruption

3. **Agent Selection Failures**
   - Ensure required agents are started
   - Verify capability matching
   - Check agent health status

4. **Memory Leaks**
   - Monitor workflow state size
   - Implement cleanup in compensation
   - Use streaming for large datasets

## Future Enhancements

- PostgreSQL persistence backend
- Workflow visualization tools
- Advanced debugging interface
- Performance profiling dashboard
- Workflow versioning UI
- Automated workflow generation from specifications

## References

- [Reactor Documentation](https://hexdocs.pm/reactor)
- [Jido Agent System](./agent_system.md)
- [Signal Architecture](./signal_architecture.md)
- [Telemetry Guide](./telemetry.md)