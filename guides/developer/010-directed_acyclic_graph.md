# RubberDuck Reactor Workflow System Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture & Design Principles](#architecture--design-principles)
3. [Core Components](#core-components)
4. [Workflow Definition](#workflow-definition)
5. [Execution Model](#execution-model)
6. [Error Handling & Compensation](#error-handling--compensation)
7. [Concurrency & Parallelization](#concurrency--parallelization)
8. [Testing Workflows](#testing-workflows)
9. [Usage Examples](#usage-examples)
10. [Best Practices](#best-practices)
11. [Performance Considerations](#performance-considerations)
12. [Troubleshooting](#troubleshooting)

## Overview

The RubberDuck Reactor Workflow System is a sophisticated orchestration framework that enables complex, multi-step operations with automatic parallelization, dependency resolution, and transaction semantics. Built on Elixir's OTP principles, it provides a robust foundation for coordinating the various engines and analysis tasks within the coding assistant.

### Key Features

- **Dynamic Workflow Composition**: Build workflows at runtime based on task requirements
- **Automatic Parallelization**: Concurrent execution of independent steps
- **Dependency Resolution**: Smart ordering of steps based on data dependencies
- **Transaction Semantics**: All-or-nothing execution with rollback support
- **Saga Pattern**: Compensation logic for distributed transactions
- **Step Result Caching**: Avoid redundant computations
- **Workflow Versioning**: Track and manage workflow evolution
- **Comprehensive Metrics**: Built-in telemetry and performance tracking

## Architecture & Design Principles

### Core Design Principles

1. **Composability**: Workflows can be composed from smaller workflows
2. **Idempotency**: Steps can be safely retried without side effects
3. **Isolation**: Steps execute in isolated contexts
4. **Observability**: Every action is tracked and measurable
5. **Fault Tolerance**: Graceful handling of failures with compensation

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Registry                         │
├─────────────────────────────────────────────────────────────┤
│                    Execution Engine                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Dependency   │  │  Scheduler   │  │ Compensation │     │
│  │  Resolver    │  │              │  │   Manager    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
├─────────────────────────────────────────────────────────────┤
│                      Step Executors                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Analysis   │  │  Generation  │  │ Enhancement  │     │
│  │    Steps     │  │    Steps     │  │    Steps     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
├─────────────────────────────────────────────────────────────┤
│                    State Management                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ Result Cache │  │   Context    │  │   Metrics    │     │
│  │              │  │   Storage    │  │  Collector   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Workflow Registry (`RubberDuck.Workflows.Registry`)

Manages workflow definitions and provides lookup capabilities.

```elixir
defmodule RubberDuck.Workflows.Registry do
  use GenServer

  # Register a workflow definition
  def register_workflow(name, definition) do
    GenServer.call(__MODULE__, {:register, name, definition})
  end

  # Retrieve a workflow by name
  def get_workflow(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  # List all available workflows
  def list_workflows() do
    GenServer.call(__MODULE__, :list)
  end
end
```

### 2. Execution Engine (`RubberDuck.Workflows.Engine`)

Orchestrates workflow execution with dependency resolution and parallelization.

```elixir
defmodule RubberDuck.Workflows.Engine do
  use GenServer

  defstruct [:workflow, :context, :status, :results, :errors]

  # Start workflow execution
  def execute(workflow_name, initial_context) do
    {:ok, execution_id} = start_execution(workflow_name, initial_context)
    monitor_execution(execution_id)
  end

  # Get execution status
  def get_status(execution_id) do
    GenServer.call(via_tuple(execution_id), :get_status)
  end
end
```

### 3. Step Executor (`RubberDuck.Workflows.StepExecutor`)

Handles individual step execution with isolation and error handling.

```elixir
defmodule RubberDuck.Workflows.StepExecutor do
  @callback execute(context :: map()) :: {:ok, result :: any()} | {:error, reason :: any()}
  @callback compensate(context :: map(), error :: any()) :: :ok | {:error, reason :: any()}
  @callback validate_input(context :: map()) :: :ok | {:error, reason :: any()}
end
```

### 4. Dependency Resolver (`RubberDuck.Workflows.DependencyResolver`)

Analyzes step dependencies and creates execution plans.

```elixir
defmodule RubberDuck.Workflows.DependencyResolver do
  # Build execution graph from workflow definition
  def build_execution_graph(workflow) do
    workflow.steps
    |> analyze_dependencies()
    |> topological_sort()
    |> identify_parallel_groups()
  end
end
```

## Workflow Definition

### DSL for Workflow Definition

Workflows are defined using a declarative DSL that makes dependencies and flow explicit:

```elixir
defmodule MyWorkflows do
  use RubberDuck.Workflows.DSL

  workflow :code_analysis do
    description "Comprehensive code analysis workflow"
    
    step :parse_files do
      module FileParser
      inputs [:file_paths]
      outputs [:ast_trees]
      timeout 5_000
    end
    
    step :semantic_analysis do
      module SemanticAnalyzer
      depends_on [:parse_files]
      inputs [:ast_trees]
      outputs [:semantic_results]
      retry_count 3
    end
    
    step :security_scan do
      module SecurityScanner
      depends_on [:parse_files]
      inputs [:ast_trees]
      outputs [:security_issues]
      parallel true
    end
    
    step :generate_report do
      module ReportGenerator
      depends_on [:semantic_analysis, :security_scan]
      inputs [:semantic_results, :security_issues]
      outputs [:analysis_report]
    end
    
    on_error :compensate_all
    cache_results true
  end
end
```

### Workflow Configuration Options

```elixir
workflow :my_workflow do
  # Workflow metadata
  description "Workflow description"
  version "1.0.0"
  tags [:analysis, :critical]
  
  # Execution settings
  timeout 60_000  # Overall workflow timeout
  max_retries 3   # Global retry limit
  
  # Error handling
  on_error :compensate_all | :fail_fast | :continue
  
  # Performance settings
  cache_results true
  parallel_limit 10  # Max concurrent steps
  
  # Telemetry
  emit_metrics true
  trace_execution true
end
```

## Execution Model

### Execution Lifecycle

1. **Initialization**: Workflow definition is loaded and validated
2. **Planning**: Dependencies are resolved and execution plan created
3. **Execution**: Steps are executed according to the plan
4. **Monitoring**: Progress and metrics are tracked
5. **Completion**: Results are aggregated and cached
6. **Cleanup**: Resources are released

### Execution Context

The execution context flows through all steps and accumulates results:

```elixir
defmodule RubberDuck.Workflows.Context do
  defstruct [
    :workflow_id,
    :execution_id,
    :initial_input,
    :step_results,
    :metadata,
    :start_time,
    :status
  ]
  
  # Add step result to context
  def add_result(context, step_name, result) do
    %{context | 
      step_results: Map.put(context.step_results, step_name, result)
    }
  end
  
  # Get input for a step from previous results
  def get_step_input(context, step_name, input_mapping) do
    Enum.reduce(input_mapping, %{}, fn {key, source}, acc ->
      value = get_in(context.step_results, source)
      Map.put(acc, key, value)
    end)
  end
end
```

### Step Execution

Each step is executed in isolation with its own process:

```elixir
defmodule RubberDuck.Workflows.StepRunner do
  def run_step(step_definition, context) do
    Task.Supervisor.async_nolink(
      RubberDuck.TaskSupervisor,
      fn ->
        with :ok <- validate_inputs(step_definition, context),
             {:ok, result} <- execute_step_module(step_definition, context),
             :ok <- validate_outputs(step_definition, result) do
          {:ok, result}
        end
      end,
      timeout: step_definition.timeout
    )
  end
end
```

## Error Handling & Compensation

### Saga Pattern Implementation

The workflow system implements the Saga pattern for distributed transaction management:

```elixir
defmodule RubberDuck.Workflows.Saga do
  defstruct [:forward_steps, :compensation_steps, :state]
  
  # Execute saga with automatic compensation on failure
  def execute(saga, initial_state) do
    case execute_forward(saga, initial_state) do
      {:ok, final_state} -> 
        {:ok, final_state}
      {:error, failed_step, partial_state} ->
        compensate_from(saga, failed_step, partial_state)
        {:error, failed_step}
    end
  end
end
```

### Compensation Strategies

1. **Compensate All**: Rollback all completed steps
2. **Compensate Failed**: Only compensate the failed step
3. **Partial Compensation**: Compensate based on business logic

```elixir
defmodule MyStep do
  use RubberDuck.Workflows.Step
  
  def execute(context) do
    # Forward operation
    {:ok, create_resource(context.input)}
  end
  
  def compensate(context, _error) do
    # Compensation operation
    delete_resource(context.step_results[__MODULE__])
    :ok
  end
end
```

### Error Recovery

```elixir
defmodule RubberDuck.Workflows.ErrorRecovery do
  # Retry with exponential backoff
  def retry_step(step, context, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay, 1000)
    
    Stream.iterate(0, &(&1 + 1))
    |> Enum.take(max_attempts)
    |> Enum.reduce_while({:error, :not_started}, fn attempt, _acc ->
      case execute_step(step, context) do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, reason} ->
          if attempt < max_attempts - 1 do
            delay = base_delay * :math.pow(2, attempt)
            Process.sleep(round(delay))
            {:cont, {:error, reason}}
          else
            {:halt, {:error, {:max_retries_exceeded, reason}}}
          end
      end
    end)
  end
end
```

## Concurrency & Parallelization

### Automatic Parallelization

The system automatically identifies steps that can run in parallel:

```elixir
defmodule RubberDuck.Workflows.Parallelizer do
  def identify_parallel_groups(execution_graph) do
    execution_graph
    |> group_by_depth()
    |> Enum.map(fn {_depth, steps} ->
      %{
        parallel: true,
        steps: steps,
        max_concurrency: calculate_optimal_concurrency(steps)
      }
    end)
  end
  
  defp calculate_optimal_concurrency(steps) do
    # Consider system resources and step characteristics
    system_cores = System.schedulers_online()
    step_intensity = estimate_step_intensity(steps)
    
    min(length(steps), max(1, div(system_cores, step_intensity)))
  end
end
```

### Parallel Execution

```elixir
defmodule RubberDuck.Workflows.ParallelExecutor do
  def execute_parallel_group(steps, context, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    
    Task.async_stream(
      steps,
      fn step -> execute_step(step, context) end,
      max_concurrency: max_concurrency,
      on_timeout: :kill_task,
      timeout: calculate_group_timeout(steps)
    )
    |> Enum.reduce({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, results} -> 
        {:ok, [result | results]}
      {:ok, {:error, reason}}, _acc -> 
        {:error, reason}
      {:exit, reason}, _acc -> 
        {:error, {:step_crashed, reason}}
    end)
  end
end
```

## Testing Workflows

### Unit Testing Individual Steps

```elixir
defmodule MyStepTest do
  use ExUnit.Case
  
  test "executes successfully with valid input" do
    context = %Context{
      step_results: %{
        previous_step: %{data: "test"}
      }
    }
    
    assert {:ok, result} = MyStep.execute(context)
    assert result.processed == true
  end
  
  test "compensates correctly on failure" do
    context = %Context{
      step_results: %{
        my_step: %{resource_id: "123"}
      }
    }
    
    assert :ok = MyStep.compensate(context, :some_error)
    refute resource_exists?("123")
  end
end
```

### Integration Testing Workflows

```elixir
defmodule WorkflowIntegrationTest do
  use ExUnit.Case
  
  test "complete workflow executes successfully" do
    input = %{
      file_paths: ["lib/example.ex"],
      options: %{deep_analysis: true}
    }
    
    assert {:ok, result} = 
      RubberDuck.Workflows.execute(:code_analysis, input)
    
    assert result.analysis_report
    assert length(result.semantic_results) > 0
    assert result.execution_time < 10_000
  end
  
  test "workflow handles step failure with compensation" do
    input = %{file_paths: ["invalid.ex"]}
    
    assert {:error, :file_not_found} = 
      RubberDuck.Workflows.execute(:code_analysis, input)
    
    # Verify compensation occurred
    assert_no_partial_results()
  end
end
```

### Testing Parallel Execution

```elixir
defmodule ParallelExecutionTest do
  use ExUnit.Case
  
  test "parallel steps execute concurrently" do
    workflow = build_parallel_workflow(10)
    
    {time, {:ok, _result}} = :timer.tc(fn ->
      RubberDuck.Workflows.execute(workflow, %{})
    end)
    
    # Should take ~1 second, not 10
    assert time < 2_000_000  # microseconds
  end
end
```

## Usage Examples

### Example 1: Simple Sequential Workflow

```elixir
# Define a simple workflow
defmodule SimpleWorkflows do
  use RubberDuck.Workflows.DSL
  
  workflow :generate_documentation do
    step :analyze_code do
      module CodeAnalyzer
      inputs [:source_files]
      outputs [:analysis]
    end
    
    step :generate_docs do
      module DocGenerator
      depends_on [:analyze_code]
      inputs [:analysis]
      outputs [:documentation]
    end
  end
end

# Execute the workflow
{:ok, result} = RubberDuck.Workflows.execute(
  :generate_documentation,
  %{source_files: ["lib/**/*.ex"]}
)
```

### Example 2: Complex Analysis Workflow

```elixir
defmodule AnalysisWorkflows do
  use RubberDuck.Workflows.DSL
  
  workflow :comprehensive_analysis do
    description "Full project analysis with multiple engines"
    
    # Parallel parsing
    step :parse_elixir do
      module ElixirParser
      inputs [:elixir_files]
      outputs [:elixir_ast]
      parallel true
    end
    
    step :parse_javascript do
      module JavaScriptParser
      inputs [:js_files]
      outputs [:js_ast]
      parallel true
    end
    
    # Parallel analysis
    step :semantic_analysis do
      module SemanticEngine
      depends_on [:parse_elixir, :parse_javascript]
      inputs [:elixir_ast, :js_ast]
      outputs [:semantic_issues]
    end
    
    step :security_analysis do
      module SecurityEngine
      depends_on [:parse_elixir, :parse_javascript]
      inputs [:elixir_ast, :js_ast]
      outputs [:security_issues]
    end
    
    step :style_analysis do
      module StyleEngine
      depends_on [:parse_elixir, :parse_javascript]
      inputs [:elixir_ast, :js_ast]
      outputs [:style_issues]
    end
    
    # LLM Enhancement
    step :llm_review do
      module LLMReviewEngine
      depends_on [:semantic_analysis, :security_analysis]
      inputs [:semantic_issues, :security_issues]
      outputs [:llm_insights]
      timeout 30_000
    end
    
    # Final report
    step :generate_report do
      module ReportGenerator
      depends_on [:semantic_analysis, :security_analysis, 
                  :style_analysis, :llm_review]
      inputs [:semantic_issues, :security_issues, 
              :style_issues, :llm_insights]
      outputs [:final_report]
    end
    
    on_error :compensate_all
    cache_results true
    parallel_limit 5
  end
end
```

### Example 3: Dynamic Workflow Generation

```elixir
defmodule DynamicWorkflowBuilder do
  use RubberDuck.Workflows.DSL
  
  def build_custom_workflow(requirements) do
    workflow :dynamic do
      description "Dynamically generated workflow"
      
      # Always start with parsing
      step :parse do
        module Parser
        inputs [:files]
        outputs [:ast]
      end
      
      # Add analysis steps based on requirements
      if requirements.semantic_analysis do
        step :semantic do
          module SemanticAnalyzer
          depends_on [:parse]
          inputs [:ast]
          outputs [:semantic_results]
        end
      end
      
      if requirements.security_scan do
        step :security do
          module SecurityScanner
          depends_on [:parse]
          inputs [:ast]
          outputs [:security_results]
        end
      end
      
      # Add LLM enhancement if requested
      if requirements.llm_enhancement do
        deps = [:parse]
        deps = if requirements.semantic_analysis, do: [:semantic | deps], else: deps
        deps = if requirements.security_scan, do: [:security | deps], else: deps
        
        step :llm_enhance do
          module LLMEnhancer
          depends_on deps
          inputs [:all_results]
          outputs [:enhanced_results]
        end
      end
      
      # Always generate a report
      step :report do
        module Reporter
        depends_on :all
        inputs [:all_results]
        outputs [:report]
      end
    end
  end
end
```

### Example 4: Workflow with Compensation

```elixir
defmodule TransactionalWorkflow do
  use RubberDuck.Workflows.DSL
  
  workflow :code_generation_transaction do
    step :reserve_resources do
      module ResourceManager
      inputs [:requirements]
      outputs [:reservation_id]
      
      compensate fn context, _error ->
        ResourceManager.release(context.step_results.reserve_resources.reservation_id)
      end
    end
    
    step :generate_code do
      module CodeGenerator
      depends_on [:reserve_resources]
      inputs [:requirements, :reservation_id]
      outputs [:generated_code]
      
      compensate fn context, _error ->
        CodeGenerator.cleanup(context.step_results.generate_code.temp_files)
      end
    end
    
    step :validate_code do
      module CodeValidator
      depends_on [:generate_code]
      inputs [:generated_code]
      outputs [:validation_result]
    end
    
    step :commit_code do
      module CodeCommitter
      depends_on [:validate_code]
      inputs [:generated_code, :validation_result]
      outputs [:commit_id]
      
      compensate fn context, _error ->
        CodeCommitter.rollback(context.step_results.commit_code.commit_id)
      end
    end
    
    on_error :compensate_all
  end
end
```

## Best Practices

### 1. Workflow Design

- **Keep Steps Focused**: Each step should have a single responsibility
- **Minimize Dependencies**: Reduce coupling between steps
- **Use Parallel Execution**: Identify independent steps for parallelization
- **Plan for Failure**: Always implement compensation logic

### 2. Error Handling

```elixir
# Good: Specific error handling
step :risky_operation do
  module RiskyOperation
  
  on_error fn
    {:network_error, _} -> {:retry, max_attempts: 5}
    {:invalid_input, _} -> :fail_fast
    _ -> :compensate
  end
end

# Bad: Generic error handling
step :risky_operation do
  module RiskyOperation
  on_error :continue  # Too permissive
end
```

### 3. Context Management

```elixir
# Good: Explicit input/output mapping
step :process_data do
  inputs %{
    raw_data: [:fetch_data, :result],
    config: [:load_config, :settings]
  }
  outputs [:processed_data, :metrics]
end

# Bad: Implicit context access
step :process_data do
  module ProcessData  # Accesses context directly
end
```

### 4. Performance Optimization

```elixir
# Good: Cache expensive operations
workflow :analysis do
  cache_key fn context ->
    :crypto.hash(:md5, context.source_files)
  end
  cache_ttl :timer.hours(24)
  
  step :expensive_analysis do
    module ExpensiveAnalyzer
    cache true
  end
end

# Good: Set appropriate timeouts
step :external_api_call do
  module ExternalAPI
  timeout 5_000  # Don't wait forever
  retry_count 3
end
```

### 5. Testing

```elixir
# Good: Test both success and failure paths
test "workflow handles partial failure" do
  # Arrange
  mock_step_failure(:validate_code, :syntax_error)
  
  # Act
  result = Workflows.execute(:code_generation, input)
  
  # Assert
  assert {:error, {:step_failed, :validate_code}} = result
  assert_compensation_executed(:generate_code)
  assert_compensation_executed(:reserve_resources)
end
```

## Performance Considerations

### 1. Caching Strategy

```elixir
defmodule RubberDuck.Workflows.Cache do
  def cache_key(workflow_name, input) do
    {workflow_name, :erlang.phash2(input)}
  end
  
  def get_cached_result(key) do
    case :ets.lookup(:workflow_cache, key) do
      [{^key, result, expiry}] when expiry > System.monotonic_time() ->
        {:ok, result}
      _ ->
        :miss
    end
  end
end
```

### 2. Resource Management

```elixir
defmodule RubberDuck.Workflows.ResourceManager do
  def allocate_resources(workflow) do
    %{
      max_memory: estimate_memory_usage(workflow),
      max_processes: count_parallel_steps(workflow),
      timeout_buffer: calculate_timeout_buffer(workflow)
    }
  end
end
```

### 3. Monitoring and Metrics

```elixir
defmodule RubberDuck.Workflows.Metrics do
  def track_execution(workflow_name, execution_time, status) do
    :telemetry.execute(
      [:workflow, :execution],
      %{duration: execution_time},
      %{workflow: workflow_name, status: status}
    )
  end
  
  def track_step(step_name, duration, status) do
    :telemetry.execute(
      [:workflow, :step],
      %{duration: duration},
      %{step: step_name, status: status}
    )
  end
end
```

## Troubleshooting

### Common Issues

1. **Workflow Timeout**
   - Check individual step timeouts
   - Verify parallel execution limits
   - Review resource allocation

2. **Compensation Failures**
   - Ensure compensation logic is idempotent
   - Check for resource cleanup order dependencies
   - Verify error handling in compensation

3. **Memory Issues**
   - Review context size growth
   - Check for large intermediate results
   - Consider streaming for large data

### Debug Mode

```elixir
# Enable debug mode for detailed execution trace
{:ok, result} = RubberDuck.Workflows.execute(
  :my_workflow,
  input,
  debug: true,
  trace_steps: true
)

# Access execution trace
IO.inspect(result.metadata.execution_trace)
```

### Performance Profiling

```elixir
# Profile workflow execution
:fprof.trace([:start])
{:ok, result} = RubberDuck.Workflows.execute(:my_workflow, input)
:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse(dest: 'workflow_profile.txt')
```

## Conclusion

The RubberDuck Reactor Workflow System provides a powerful, flexible foundation for orchestrating complex operations in the coding assistant. By leveraging Elixir's concurrency model and OTP principles, it delivers reliable, performant workflow execution with sophisticated error handling and compensation capabilities.

Key takeaways:
- Design workflows with clear dependencies and parallel opportunities
- Implement proper error handling and compensation logic
- Use caching strategically for expensive operations
- Monitor and measure workflow performance
- Test both success and failure scenarios

The system's extensibility ensures it can grow with the coding assistant's capabilities, while its robust error handling and transaction semantics provide the reliability needed for production use.
