# RubberDuck DAG-Based Workflow Subsystem Design

## Executive Summary

This design document presents a comprehensive architecture for implementing a DAG-based workflow subsystem for RubberDuck's distributed AI coding assistant. The solution leverages Elixir's OTP strengths, integrates with the existing multi-LLM coordination layer, and provides enterprise-grade workflow orchestration capabilities for complex, parallel, and conditional LLM collaboration patterns.

## Core Architecture Overview

### System Components

The workflow subsystem consists of five key components working in concert:

**1. Workflow Engine (Built on Reactor Framework)**
- Manages DAG execution using Reactor's built-in compensation and error handling
- Supports dynamic workflow modification and runtime step addition
- Implements conditional branching, parallel execution, and loop constructs
- Integrates with GenStateMachine for complex state management

**2. Distributed Coordination Layer**
- Uses Horde for distributed supervision across nodes
- Leverages Syn registry for workflow process discovery
- Implements leader election for workflow schedulers
- Handles network partitions and split-brain scenarios gracefully

**3. Persistence Layer**
- Multi-tiered storage strategy using Mnesia, Nebulex, and external storage
- ETF-based serialization for performance with JSON fallback for compatibility
- Checkpoint/restore capabilities for long-running workflows
- Session management across distributed nodes

**4. LLM Orchestration Integration**
- Seamless integration with LLM.Coordinator for capability-based model selection
- Support for parallel LLM execution with fan-out/fan-in patterns
- Ensemble processing with conflict resolution
- Cost-aware routing and optimization

**5. Monitoring & Observability**
- Comprehensive telemetry integration
- Distributed tracing for DAG execution
- Health checks and performance metrics
- Real-time workflow visualization

## Implementation Architecture

### DAG Definition and Execution

The system uses a hybrid approach combining Reactor framework capabilities with custom DAG management:

```elixir
defmodule RubberDuck.Workflow do
  use Reactor
  
  defstruct [:id, :name, :version, :dag_structure, :metadata, :created_at]
  
  # Example workflow definition
  def create_multi_llm_workflow do
    input :document_content
    input :analysis_requirements
    
    # Parallel LLM analysis
    step :gpt4_analysis, LLM.AnalysisStep,
      model: "gpt-4",
      content: input(:document_content),
      requirements: input(:analysis_requirements),
      async?: true
    
    step :claude_analysis, LLM.AnalysisStep,
      model: "claude-3",
      content: input(:document_content),
      requirements: input(:analysis_requirements),
      async?: true
    
    step :gemini_analysis, LLM.AnalysisStep,
      model: "gemini-pro",
      content: input(:document_content),
      requirements: input(:analysis_requirements),
      async?: true
    
    # Ensemble processing with conflict resolution
    step :synthesize_results, LLM.EnsembleStep,
      inputs: [
        result(:gpt4_analysis),
        result(:claude_analysis),
        result(:gemini_analysis)
      ],
      conflict_resolution: :weighted_voting
    
    return :synthesize_results
  end
end
```

### State Management with GenStateMachine

The workflow state machine manages execution lifecycle and recovery:

```elixir
defmodule RubberDuck.WorkflowStateMachine do
  use GenStateMachine
  
  def init({workflow, initial_data}) do
    state_data = %{
      workflow: workflow,
      dag: build_dag(workflow),
      step_results: %{},
      running_steps: MapSet.new(),
      completed_steps: MapSet.new(),
      checkpoints: []
    }
    {:ok, :initialized, state_data}
  end
  
  # Handles parallel step execution
  def handle_event(:cast, :start, :initialized, data) do
    ready_steps = find_ready_steps(data.dag, data.completed_steps)
    start_parallel_steps(ready_steps, data)
    {:next_state, :running, update_running_steps(data, ready_steps)}
  end
  
  # Manages step completion and triggers dependent steps
  def handle_event(:cast, {:step_complete, step_id, result}, :running, data) do
    new_data = mark_step_complete(data, step_id, result)
    
    if workflow_complete?(new_data) do
      {:next_state, :completed, new_data}
    else
      next_steps = find_ready_steps(new_data.dag, new_data.completed_steps)
      start_parallel_steps(next_steps, new_data)
      {:keep_state, update_running_steps(new_data, next_steps)}
    end
  end
end
```

### Persistence Strategy

The system implements a three-tier persistence architecture:

**Tier 1: Hot State (Nebulex Cache)**
```elixir
defmodule RubberDuck.WorkflowCache do
  use Nebulex.Cache,
    otp_app: :rubber_duck,
    adapter: Nebulex.Adapters.Partitioned
  
  @decorate cacheable(key: {:workflow_state, instance_id}, ttl: :timer.minutes(30))
  def get_workflow_state(instance_id) do
    Memento.transaction!(fn -> 
      Memento.Query.read(WorkflowInstance, instance_id)
    end)
  end
end
```

**Tier 2: Warm State (Mnesia)**
```elixir
defmodule RubberDuck.WorkflowPersistence do
  use Memento.Table,
    attributes: [:id, :workflow_id, :state, :checkpoints, :metadata],
    index: [:workflow_id],
    type: :ordered_set,
    storage_properties: [{:disc_copies, [node()]}]
  
  def checkpoint_workflow(instance_id, state) do
    checkpoint = %{
      timestamp: DateTime.utc_now(),
      state_snapshot: :erlang.term_to_binary(state, [:compressed]),
      node_positions: extract_node_positions(state)
    }
    
    Memento.transaction!(fn ->
      record = Memento.Query.read(__MODULE__, instance_id) || %__MODULE__{id: instance_id}
      updated = %{record | checkpoints: [checkpoint | record.checkpoints]}
      Memento.Query.write(updated)
    end)
  end
end
```

### LLM Orchestration Integration

The workflow subsystem seamlessly integrates with the existing LLM coordination layer:

```elixir
defmodule RubberDuck.LLM.WorkflowIntegration do
  def execute_llm_step(step_config, inputs, context) do
    # Leverage existing LLM.Coordinator for model selection
    model = LLM.Coordinator.select_model(
      task_type: step_config.task_type,
      performance_requirements: step_config.requirements,
      cost_constraints: context.cost_budget
    )
    
    # Execute with automatic retries and circuit breaking
    with_circuit_breaker(model, fn ->
      LLM.Coordinator.execute(
        model: model,
        prompt: build_prompt(step_config, inputs),
        options: step_config.options
      )
    end)
  end
  
  # Parallel LLM execution with resource management
  def execute_parallel_llm_tasks(tasks, context) do
    tasks
    |> Task.async_stream(
      fn task -> execute_llm_step(task, task.inputs, context) end,
      max_concurrency: context.max_concurrent_llms,
      timeout: context.llm_timeout
    )
    |> Enum.map(&handle_task_result/1)
  end
end
```

### Advanced Workflow Patterns

**Conditional Branching**
```elixir
defmodule ConditionalWorkflow do
  use RubberDuck.Workflow
  
  step :analyze_complexity, ComplexityAnalyzer,
    input: input(:code_snippet)
  
  step :determine_path, PathSelector,
    complexity: result(:analyze_complexity),
    transform: &dynamic_branch/1
  
  defp dynamic_branch(%{complexity: :high}) do
    additional_steps = [
      {:deep_analysis, DeepCodeAnalyzer, [code: input(:code_snippet)]},
      {:expert_review, ExpertLLMReview, [analysis: {:result, :deep_analysis}]}
    ]
    {:ok, :high_complexity_path, additional_steps}
  end
  
  defp dynamic_branch(_) do
    additional_steps = [
      {:quick_review, FastCodeReview, [code: input(:code_snippet)]}
    ]
    {:ok, :standard_path, additional_steps}
  end
end
```

**Loop Constructs**
```elixir
defmodule IterativeRefinementWorkflow do
  use RubberDuck.Workflow
  
  step :initial_generation, LLM.GenerateCode,
    requirements: input(:requirements)
  
  step :iterative_improvement, IterativeImprover,
    initial_code: result(:initial_generation),
    max_iterations: 5,
    improvement_threshold: 0.85
  
  defmodule IterativeImprover do
    use Reactor.Step
    
    def run(%{initial_code: code, max_iterations: max} = args, context, _opts) do
      improve_iteratively(code, 0, max, args.improvement_threshold)
    end
    
    defp improve_iteratively(code, iteration, max, threshold) when iteration < max do
      quality_score = assess_code_quality(code)
      
      if quality_score >= threshold do
        {:ok, code}
      else
        improved_code = run_improvement_cycle(code)
        improve_iteratively(improved_code, iteration + 1, max, threshold)
      end
    end
  end
end
```

### Error Handling and Recovery

The system implements comprehensive error handling with compensation:

```elixir
defmodule RubberDuck.WorkflowErrorHandler do
  use GenServer
  
  def handle_step_failure(workflow_id, step_id, error) do
    case classify_error(error) do
      :transient ->
        # Retry with exponential backoff
        schedule_retry(workflow_id, step_id, calculate_backoff(error))
        
      :llm_timeout ->
        # Switch to faster model and retry
        switch_to_fallback_model(workflow_id, step_id)
        
      :permanent ->
        # Execute compensation logic
        execute_compensation(workflow_id, step_id)
        
      :network_partition ->
        # Wait for cluster reconciliation
        defer_execution(workflow_id, step_id)
    end
  end
  
  defp execute_compensation(workflow_id, failed_step_id) do
    workflow = get_workflow(workflow_id)
    completed_steps = get_completed_steps_before(workflow, failed_step_id)
    
    # Execute compensation in reverse order
    Enum.reverse(completed_steps)
    |> Enum.each(fn step ->
      step.module.compensate(step.result, step.arguments, %{})
    end)
  end
end
```

### Distributed Coordination

The system uses Horde for distributed workflow management:

```elixir
defmodule RubberDuck.DistributedWorkflowSupervisor do
  use Horde.DynamicSupervisor
  
  def start_workflow(workflow_spec) do
    child_spec = %{
      id: workflow_spec.id,
      start: {WorkflowExecutor, :start_link, [workflow_spec]},
      restart: :transient
    }
    
    Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def init(_) do
    [
      strategy: :one_for_one,
      members: :auto,
      distribution_strategy: Horde.UniformQuorumDistribution
    ]
    |> Horde.DynamicSupervisor.init()
  end
end
```

### Session Management

Workflows can be suspended and resumed across sessions:

```elixir
defmodule RubberDuck.WorkflowSessionManager do
  def suspend_workflow(instance_id) do
    with {:ok, state} <- get_current_state(instance_id),
         :ok <- create_checkpoint(state),
         :ok <- pause_active_tasks(state) do
      
      # Store session information
      session = %WorkflowSession{
        id: instance_id,
        suspended_at: DateTime.utc_now(),
        checkpoint_id: state.latest_checkpoint,
        node: node()
      }
      
      Memento.transaction!(fn ->
        Memento.Query.write(session)
      end)
      
      {:ok, session}
    end
  end
  
  def resume_workflow(instance_id) do
    with {:ok, session} <- load_session(instance_id),
         {:ok, checkpoint} <- load_checkpoint(session.checkpoint_id),
         {:ok, workflow_state} <- restore_from_checkpoint(checkpoint) do
      
      # Restart on appropriate node
      target_node = select_node_for_resume(session)
      start_workflow_on_node(workflow_state, target_node)
    end
  end
end
```

### Monitoring and Observability

Comprehensive telemetry for workflow execution:

```elixir
defmodule RubberDuck.WorkflowTelemetry do
  def setup do
    events = [
      [:workflow, :started],
      [:workflow, :completed],
      [:workflow, :failed],
      [:step, :started],
      [:step, :completed],
      [:step, :failed],
      [:llm, :call, :start],
      [:llm, :call, :stop]
    ]
    
    :telemetry.attach_many(
      "workflow-metrics",
      events,
      &handle_event/4,
      %{}
    )
  end
  
  def handle_event([:workflow, :completed], measurements, metadata, _config) do
    duration_ms = measurements.duration / 1_000_000
    
    # Export metrics
    :telemetry.execute(
      [:rubber_duck, :metrics],
      %{
        workflow_duration_ms: duration_ms,
        steps_executed: metadata.step_count,
        llm_calls: metadata.llm_call_count,
        total_cost: metadata.total_cost
      },
      metadata
    )
  end
end
```

## DSL and API Design

### Elixir DSL for Workflow Definition

```elixir
defmodule CodeReviewWorkflow do
  use RubberDuck.Workflow
  
  workflow "comprehensive_code_review" do
    description "Multi-stage code review with multiple LLMs"
    
    # Define inputs
    input :code_files, type: :list
    input :review_criteria, type: :map
    
    # Parallel static analysis
    parallel :static_analysis do
      step :syntax_check, SyntaxAnalyzer,
        files: input(:code_files)
        
      step :security_scan, SecurityScanner,
        files: input(:code_files),
        rules: input(:review_criteria, :security_rules)
        
      step :performance_analysis, PerformanceAnalyzer,
        files: input(:code_files)
    end
    
    # LLM-based review with different models
    step :llm_review_ensemble, LLMEnsembleReview,
      code: input(:code_files),
      analysis_results: result(:static_analysis),
      models: ["gpt-4", "claude-3", "gemini-pro"],
      strategy: :consensus
    
    # Conditional deep dive based on findings
    branch :severity_check,
      condition: fn results -> 
        Enum.any?(results.findings, & &1.severity == :critical)
      end,
      on_true: [
        step: :expert_review, ExpertLLMReview,
          findings: result(:llm_review_ensemble),
          model: "gpt-4-turbo"
      ],
      on_false: [
        step: :standard_report, StandardReportGenerator,
          findings: result(:llm_review_ensemble)
      ]
    
    # Final report generation
    step :generate_report, ReportGenerator,
      all_results: collect_all_results()
  end
end
```

### JSON/YAML Workflow Definition Support

```yaml
workflow:
  id: "code_review_workflow"
  version: "1.0"
  inputs:
    - name: "code_files"
      type: "array"
    - name: "review_criteria"
      type: "object"
  
  steps:
    - id: "static_analysis"
      type: "parallel_group"
      steps:
        - id: "syntax_check"
          module: "SyntaxAnalyzer"
          inputs:
            files: "$input.code_files"
        
        - id: "security_scan"
          module: "SecurityScanner"
          inputs:
            files: "$input.code_files"
            rules: "$input.review_criteria.security_rules"
    
    - id: "llm_ensemble"
      type: "llm_ensemble"
      depends_on: ["static_analysis"]
      config:
        models: ["gpt-4", "claude-3", "gemini-pro"]
        strategy: "consensus"
      inputs:
        code: "$input.code_files"
        analysis: "$result.static_analysis"
```

## Integration with Existing RubberDuck Architecture

### Event System Integration

```elixir
defmodule RubberDuck.WorkflowEventBridge do
  use GenServer
  
  def init(_) do
    # Subscribe to pg events
    :pg.join(:workflow_events, self())
    {:ok, %{}}
  end
  
  def handle_info({:workflow_event, event}, state) do
    case event do
      {:workflow_completed, workflow_id, results} ->
        # Broadcast to other RubberDuck components
        Phoenix.PubSub.broadcast(
          RubberDuck.PubSub,
          "workflows:#{workflow_id}",
          {:workflow_completed, results}
        )
        
      {:step_failed, workflow_id, step_id, error} ->
        # Notify error handling system
        RubberDuck.ErrorTracker.track_workflow_error(
          workflow_id,
          step_id,
          error
        )
    end
    
    {:noreply, state}
  end
end
```

### Multi-LLM Coordination Layer Integration

```elixir
defmodule RubberDuck.LLM.WorkflowAdapter do
  @behaviour RubberDuck.LLM.CoordinatorAdapter
  
  def route_to_model(task, context) do
    # Use existing LLM.Coordinator routing logic
    LLM.Coordinator.select_optimal_model(
      task_type: task.type,
      complexity: estimate_complexity(task),
      latency_requirements: context.sla,
      cost_budget: context.remaining_budget
    )
  end
  
  def execute_with_ensemble(task, models, strategy) do
    # Leverage existing ensemble processing
    LLM.Coordinator.ensemble_execute(
      task: task,
      models: models,
      conflict_resolution: strategy,
      timeout: calculate_ensemble_timeout(models)
    )
  end
end
```

## Implementation Roadmap

### Phase 1: MVP (Weeks 1-4)
1. **Core Workflow Engine**
   - Basic Reactor integration
   - Simple DAG execution
   - PostgreSQL-backed persistence
   - Manual workflow triggering

2. **Essential Task Types**
   - LLM call tasks
   - Data transformation tasks
   - Basic parallel execution

3. **Minimal DSL**
   - Elixir-based workflow definitions
   - Simple dependency management

### Phase 2: Enhanced Features (Weeks 5-8)
1. **Advanced Orchestration**
   - Event-driven triggers
   - Conditional execution
   - Loop support
   - Dynamic workflow modification

2. **Distributed Capabilities**
   - Horde supervision integration
   - Multi-node execution
   - Syn-based process registry

3. **Persistence & Recovery**
   - Checkpoint/restore functionality
   - Session management
   - Mnesia integration

### Phase 3: Production Readiness (Weeks 9-12)
1. **Enterprise Features**
   - Comprehensive monitoring
   - Performance optimization
   - Security and access control

2. **UI and Developer Experience**
   - Workflow visualization
   - Debugging tools
   - REST/GraphQL APIs

3. **Advanced LLM Features**
   - Multi-model coordination
   - Cost optimization
   - Human-in-the-loop workflows

## Performance Considerations

### Resource Management
- **Concurrent LLM Limits**: Configurable per-workflow and global limits
- **Memory Management**: Streaming for large datasets, garbage collection tuning
- **CPU Allocation**: Process priority management for critical workflows

### Optimization Strategies
- **Caching**: Multi-layer caching with semantic similarity for LLM responses
- **Batching**: Automatic request batching for similar LLM calls
- **Preemption**: Priority-based workflow scheduling and resource allocation

## Security Considerations

### Access Control
- **Workflow-level Permissions**: RBAC for workflow creation and execution
- **Data Isolation**: Separate data spaces for different tenants
- **Audit Logging**: Comprehensive logging of all workflow operations

### LLM Security
- **Prompt Injection Prevention**: Input sanitization and validation
- **Output Filtering**: Content moderation for LLM responses
- **Rate Limiting**: Per-user and per-workflow rate limits

## Conclusion

This DAG-based workflow subsystem design provides RubberDuck with a robust, scalable, and flexible foundation for orchestrating complex multi-LLM workflows. By leveraging Elixir's OTP capabilities, the Reactor framework, and battle-tested distributed systems patterns, the architecture supports the full spectrum of workflow requirements while maintaining high performance and reliability.

The modular design allows for incremental adoption and future extensibility, while the deep integration with RubberDuck's existing components ensures a seamless user experience. The system is designed to scale from simple linear workflows to complex, distributed, multi-agent AI orchestrations, making it suitable for both current needs and future growth.
