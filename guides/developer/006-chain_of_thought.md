# RubberDuck Chain-of-Thought (CoT) System - Comprehensive Guide

## Table of Contents
1. [Introduction to Chain-of-Thought](#introduction)
2. [Architecture Overview](#architecture)
3. [Core Components](#core-components)
4. [Using the CoT DSL](#using-the-cot-dsl)
5. [ConversationManager Deep Dive](#conversationmanager)
6. [Prompt Templates](#prompt-templates)
7. [Integration with Other Systems](#integration)
8. [Examples and Use Cases](#examples)
9. [Performance and Optimization](#performance)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

## 1. Introduction to Chain-of-Thought {#introduction}

### What is Chain-of-Thought?

Chain-of-Thought (CoT) is a prompting technique that improves Large Language Model (LLM) reasoning by breaking down complex problems into intermediate steps. Instead of asking an LLM to jump directly to an answer, CoT guides it through a logical sequence of thoughts, similar to how humans solve problems step-by-step.

### Why CoT in RubberDuck?

In the context of a coding assistant, CoT is crucial for:

- **Complex Code Generation**: Breaking down requirements into logical steps
- **Debugging**: Systematically analyzing code issues
- **Refactoring**: Planning changes through structured reasoning
- **Architecture Decisions**: Evaluating options methodically

### Key Benefits

1. **Improved Accuracy**: Step-by-step reasoning reduces errors
2. **Explainability**: Users can understand the AI's thought process
3. **Consistency**: Structured approach ensures reliable results
4. **Flexibility**: Customizable reasoning chains for different tasks

## 2. Architecture Overview {#architecture}

The RubberDuck CoT system is now integrated with the conversation engine system:

```
┌─────────────────────────────────────────────────────────────┐
│                    Conversation Engines                      │
│        (ComplexConversation, AnalysisConversation, etc.)    │
├─────────────────────────────────────────────────────────────┤
│                              │                              │
│                              ▼                              │
│  ┌─────────────┐    ┌──────────────────┐   ┌─────────────┐│
│  │   CoT DSL   │───▶│ ConversationMgr  │──▶│   Caching   ││
│  │  (Spark)    │    │   (GenServer)    │   │    (ETS)    ││
│  └─────────────┘    └──────────────────┘   └─────────────┘│
│         │                    │                      │       │
│         ▼                    ▼                      │       │
│  ┌─────────────┐    ┌──────────────────┐          │       │
│  │   Steps &   │    │    Execution     │          │       │
│  │  Templates  │    │   Engine (CoT)   │◀─────────┘       │
│  └─────────────┘    └──────────────────┘                  │
│                              │                             │
│                              ▼                             │
│                     ┌──────────────────┐                  │
│                     │  Engine Manager  │                  │
│                     └──────────────────┘                  │
│                              │                             │
│                              ▼                             │
│                     ┌──────────────────┐                  │
│                     │   LLM Service    │                  │
│                     │ (Provider Mgmt)  │                  │
│                     └──────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

- **Conversation Engines**: High-level engines that use CoT for complex reasoning
- **CoT DSL**: Declarative configuration of reasoning chains
- **ConversationManager**: Manages CoT sessions and state
- **Execution Engine**: Processes reasoning steps sequentially, now calls EngineManager
- **Caching Layer**: Optimizes performance with ETS-based caching
- **Engine Manager**: Routes requests to appropriate engines
- **LLM Service**: Manages provider connections without embedded CoT logic

## 3. Core Components {#core-components}

### 3.1 RubberDuck.CoT.Dsl Module

The DSL module uses Spark to provide a declarative interface for defining reasoning chains:

```elixir
defmodule MyReasoningChain do
  use RubberDuck.CoT.Dsl

  reasoning_chain do
    name :code_review
    description "Comprehensive code review analysis"
    
    step :syntax_analysis do
      template :syntax_check
      validates :code_syntax
    end
    
    step :logic_analysis do
      template :logic_review
      depends_on :syntax_analysis
    end
    
    step :performance_review do
      template :performance_check
      depends_on :logic_analysis
      optional true
    end
  end
end
```

### 3.2 ConversationManager GenServer

The ConversationManager maintains state across reasoning sessions:

```elixir
# Starting a new conversation
{:ok, session_id} = RubberDuck.CoT.ConversationManager.start_conversation(
  user_id: "user123",
  chain: :code_review,
  context: %{code: file_content}
)

# Executing the chain
{:ok, result} = RubberDuck.CoT.ConversationManager.execute_chain(session_id)
```

### 3.3 Execution Engine

The execution engine processes steps sequentially, managing:
- Step dependencies
- Intermediate results
- Error handling and recovery
- Progress tracking

### 3.4 Caching Strategy

The system uses a multi-level caching approach:
- **Step-level caching**: Individual step results
- **Chain-level caching**: Complete chain results
- **Template caching**: Compiled prompt templates

## 4. Using the CoT DSL {#using-the-cot-dsl}

### Basic Chain Definition

```elixir
defmodule RubberDuck.Chains.DebugChain do
  use RubberDuck.CoT.Dsl

  reasoning_chain do
    name :debug_assistant
    description "Helps debug code issues systematically"
    
    # Define configuration
    config do
      max_iterations 3
      timeout_ms 30_000
      cache_ttl 3600
    end
    
    # Define steps
    step :identify_symptoms do
      template :symptom_analysis
      prompt "What are the observable symptoms of the bug?"
    end
    
    step :analyze_context do
      template :context_analysis
      depends_on :identify_symptoms
      prompt "Analyze the code context around the symptoms"
    end
    
    step :form_hypothesis do
      template :hypothesis_formation
      depends_on [:identify_symptoms, :analyze_context]
      prompt "Form hypotheses about potential causes"
    end
    
    step :test_hypothesis do
      template :hypothesis_testing
      depends_on :form_hypothesis
      iterative true
      max_iterations 3
    end
    
    step :propose_solution do
      template :solution_proposal
      depends_on :test_hypothesis
      validates :solution_validity
    end
  end
end
```

### Advanced Features

#### Conditional Steps

```elixir
step :performance_optimization do
  template :performance_analysis
  condition fn context ->
    context.metrics.response_time > 1000
  end
end
```

#### Dynamic Templates

```elixir
step :language_specific_analysis do
  template fn context ->
    case context.language do
      "elixir" -> :elixir_analysis
      "javascript" -> :js_analysis
      _ -> :generic_analysis
    end
  end
end
```

#### Custom Validators

```elixir
step :validate_solution do
  template :solution_check
  validates fn result, context ->
    # Custom validation logic
    {:ok, validated_result}
  end
end
```

## 5. ConversationManager Deep Dive {#conversationmanager}

### Session Management

```elixir
# Start a conversation with options
{:ok, session_id} = ConversationManager.start_conversation(
  user_id: "user123",
  chain: MyReasoningChain,
  context: %{
    code: "defmodule Example do...",
    language: "elixir",
    requirements: ["performance", "maintainability"]
  },
  options: [
    timeout: 60_000,
    priority: :high
  ]
)
```

### Execution Control

```elixir
# Execute with callbacks
ConversationManager.execute_chain(session_id,
  on_step_start: fn step_name ->
    Logger.info("Starting step: #{step_name}")
  end,
  on_step_complete: fn step_name, result ->
    Logger.info("Completed step: #{step_name}")
    broadcast_progress(step_name, result)
  end,
  on_error: fn step_name, error ->
    Logger.error("Error in step #{step_name}: #{inspect(error)}")
  end
)
```

### State Inspection

```elixir
# Get current state
{:ok, state} = ConversationManager.get_state(session_id)

# Get step history
{:ok, history} = ConversationManager.get_history(session_id)

# Get specific step result
{:ok, result} = ConversationManager.get_step_result(session_id, :analyze_context)
```

### Session Lifecycle

```elixir
# Pause execution
ConversationManager.pause(session_id)

# Resume execution
ConversationManager.resume(session_id)

# Cancel execution
ConversationManager.cancel(session_id)

# Clean up session
ConversationManager.end_conversation(session_id)
```

## 6. Prompt Templates {#prompt-templates}

### Built-in Templates

RubberDuck provides several built-in templates:

```elixir
# Default reasoning template
:default_reasoning
# Analyzes problems step-by-step

# Domain-specific templates
:code_analysis      # For code review and analysis
:bug_diagnosis      # For debugging scenarios
:architecture_planning  # For system design
:refactoring_guide     # For code refactoring
:test_generation      # For test case creation
```

### Custom Template Definition

```elixir
defmodule RubberDuck.Templates.CustomTemplates do
  use RubberDuck.CoT.Templates

  template :security_analysis do
    system_prompt """
    You are a security expert analyzing code for vulnerabilities.
    Focus on: injection attacks, authentication issues, data exposure.
    """
    
    user_prompt """
    Analyze the following code for security vulnerabilities:
    
    <%= @code %>
    
    Consider:
    1. Input validation
    2. Authentication/Authorization
    3. Data sanitization
    4. Error handling
    """
  end
  
  template :performance_optimization do
    system_prompt """
    You are a performance optimization specialist.
    """
    
    user_prompt """
    Previous analysis: <%= @previous_result %>
    
    Identify performance bottlenecks and suggest optimizations:
    1. Algorithm complexity
    2. Database queries
    3. Memory usage
    4. Concurrency opportunities
    """
  end
end
```

### Template Variables

Templates support EEx-style variables:

```elixir
template :contextual_analysis do
  user_prompt """
  Language: <%= @language %>
  Framework: <%= @framework %>
  Requirements: <%= Enum.join(@requirements, ", ") %>
  
  Code to analyze:
  ```<%= @language %>
  <%= @code %>
  ```
  
  Previous steps:
  <%= for {step, result} <- @history do %>
    - <%= step %>: <%= result.summary %>
  <% end %>
  """
end
```

## 7. Integration with Other Systems {#integration}

### Integration with Conversation Engines

CoT is now primarily used by conversation engines for complex reasoning:

```elixir
# ComplexConversation engine uses CoT internally
defmodule RubberDuck.Engines.Conversation.ComplexConversation do
  def execute(input, state) do
    # Uses ConversationChain with CoT reasoning
    case ConversationManager.execute_chain(ConversationChain, input.query, context) do
      {:ok, result} -> format_cot_response(result)
      {:error, reason} -> handle_error(reason)
    end
  end
end

# AnalysisConversation uses AnalysisChain
defmodule RubberDuck.Engines.Conversation.AnalysisConversation do
  def execute(input, state) do
    case ConversationManager.execute_chain(AnalysisChain, input.query, context) do
      {:ok, result} -> extract_analysis_insights(result)
      {:error, reason} -> handle_error(reason)
    end
  end
end
```

### Integration with Engine System

The CoT Executor now routes through EngineManager instead of calling LLM Service directly:

```elixir
# In CoT Executor - calls EngineManager
defp execute_with_retries(prompt, step, context_opts, llm_config, engine_name, retries_left) do
  engine_input = %{
    query: prompt,
    context: context_opts,
    options: %{
      temperature: Map.get(step, :temperature, 0.7),
      max_tokens: Map.get(step, :max_tokens, 1000)
    },
    llm_config: llm_config
  }
  
  # Routes through EngineManager
  case EngineManager.execute(engine_name, engine_input, timeout) do
    {:ok, response} -> 
      result = extract_engine_result(response)
      validate_step_result(result, step)
    {:error, reason} -> 
      handle_retry(reason, retries_left)
  end
end
```

### Integration with Memory System

```elixir
# CoT automatically stores reasoning patterns in memory
# Access previous reasoning chains
{:ok, similar_chains} = Memory.Manager.retrieve_patterns(
  type: :reasoning_chain,
  context: current_context
)
```

### Integration with RAG System

```elixir
step :context_enrichment do
  template :rag_enhanced
  # Automatically retrieves relevant documents
  rag_config %{
    collection: "project_docs",
    top_k: 5,
    similarity_threshold: 0.8
  }
end
```

### Integration with Self-Correction

```elixir
step :validated_solution do
  template :solution_generation
  # Enable self-correction for this step
  self_correct %{
    max_iterations: 3,
    validators: [:syntax, :logic, :requirements]
  }
end
```

## 8. Examples and Use Cases {#examples}

### Example 1: Code Review Assistant

```elixir
defmodule RubberDuck.Chains.CodeReview do
  use RubberDuck.CoT.Dsl

  reasoning_chain do
    name :comprehensive_code_review
    
    step :initial_assessment do
      template :code_overview
      prompt "Provide a high-level assessment of the code structure"
    end
    
    step :style_check do
      template :style_analysis
      depends_on :initial_assessment
      prompt "Check code style and formatting issues"
    end
    
    step :logic_review do
      template :logic_analysis
      depends_on :initial_assessment
      prompt "Analyze logic flow and potential bugs"
    end
    
    step :performance_analysis do
      template :performance_check
      depends_on :logic_review
      prompt "Identify performance bottlenecks"
    end
    
    step :security_scan do
      template :security_analysis
      depends_on :logic_review
      prompt "Check for security vulnerabilities"
    end
    
    step :recommendations do
      template :recommendation_synthesis
      depends_on [:style_check, :logic_review, :performance_analysis, :security_scan]
      prompt "Synthesize findings and provide actionable recommendations"
    end
  end
end

# Usage
{:ok, session} = ConversationManager.start_conversation(
  chain: RubberDuck.Chains.CodeReview,
  context: %{
    code: File.read!("lib/my_module.ex"),
    language: "elixir",
    project_standards: load_project_standards()
  }
)

{:ok, review_result} = ConversationManager.execute_chain(session)
```

### Example 2: Bug Diagnosis Assistant

```elixir
defmodule RubberDuck.Chains.BugDiagnosis do
  use RubberDuck.CoT.Dsl

  reasoning_chain do
    name :bug_diagnosis
    
    step :symptom_collection do
      template :symptom_gathering
      interactive true  # Allows user input
    end
    
    step :reproduction_steps do
      template :reproduction_analysis
      depends_on :symptom_collection
    end
    
    step :hypothesis_generation do
      template :hypothesis_formation
      depends_on [:symptom_collection, :reproduction_steps]
      # Generate multiple hypotheses
      multiple_outputs 3
    end
    
    step :hypothesis_testing do
      template :hypothesis_validation
      depends_on :hypothesis_generation
      iterative true
      # Test each hypothesis
      for_each :hypothesis
    end
    
    step :root_cause_analysis do
      template :root_cause_identification
      depends_on :hypothesis_testing
    end
    
    step :solution_proposal do
      template :fix_generation
      depends_on :root_cause_analysis
      self_correct %{validators: [:syntax, :logic]}
    end
  end
end
```

### Example 3: Architecture Planning

```elixir
defmodule RubberDuck.Chains.ArchitecturePlanning do
  use RubberDuck.CoT.Dsl

  reasoning_chain do
    name :system_architecture
    
    step :requirements_analysis do
      template :requirement_breakdown
      prompt "Analyze and categorize system requirements"
    end
    
    step :component_identification do
      template :component_analysis
      depends_on :requirements_analysis
      prompt "Identify necessary system components"
    end
    
    step :technology_selection do
      template :tech_stack_evaluation
      depends_on :component_identification
      # Use RAG to find similar architectures
      rag_enhanced true
    end
    
    step :interaction_design do
      template :component_interaction
      depends_on [:component_identification, :technology_selection]
    end
    
    step :scalability_planning do
      template :scalability_analysis
      depends_on :interaction_design
    end
    
    step :architecture_validation do
      template :architecture_review
      depends_on [:interaction_design, :scalability_planning]
      # Multiple validation passes
      validators [
        :requirement_coverage,
        :scalability_check,
        :security_review,
        :cost_analysis
      ]
    end
  end
end
```

## 9. Performance and Optimization {#performance}

### Caching Strategies

```elixir
# Configure cache TTL per chain
reasoning_chain do
  config do
    cache_ttl 3600  # 1 hour
    cache_key_prefix "v1"
  end
end

# Invalidate cache when needed
ConversationManager.invalidate_cache(chain: :code_review)
```

### Parallel Execution

```elixir
# Define parallel steps
step :parallel_analysis do
  parallel_group [
    :syntax_check,
    :style_analysis,
    :complexity_metrics
  ]
end
```

### Resource Management

```elixir
# Set resource limits
reasoning_chain do
  config do
    max_memory_mb 512
    timeout_ms 60_000
    max_concurrent_llm_calls 3
  end
end
```

### Telemetry and Metrics

```elixir
# Built-in telemetry events
:telemetry.attach(
  "cot-metrics",
  [:rubber_duck, :cot, :step, :complete],
  fn _event, measurements, metadata, _config ->
    Logger.info("Step #{metadata.step} took #{measurements.duration}ms")
    StatsD.histogram("cot.step.duration", measurements.duration,
      tags: ["step:#{metadata.step}", "chain:#{metadata.chain}"]
    )
  end,
  nil
)
```

## 10. Best Practices {#best-practices}

### 1. Design Focused Chains

Keep reasoning chains focused on specific tasks:

```elixir
# Good: Specific purpose
reasoning_chain do
  name :elixir_genserver_review
  # Focused on GenServer patterns
end

# Avoid: Too broad
reasoning_chain do
  name :general_code_assistant
  # Too many responsibilities
end
```

### 2. Use Appropriate Templates

Match templates to step purposes:

```elixir
step :security_check do
  # Use specific security template
  template :security_analysis
  # Not a generic template
end
```

### 3. Handle Errors Gracefully

```elixir
step :external_analysis do
  template :external_tool_check
  on_error :skip  # or :retry, :fail
  fallback_template :basic_analysis
end
```

### 4. Optimize Step Dependencies

```elixir
# Minimize dependencies for parallel execution
step :independent_check do
  # No dependencies = can run immediately
  template :quick_check
end

step :dependent_analysis do
  # Only depend on what's necessary
  depends_on :independent_check
  # Not depends_on [:a, :b, :c, :d]
end
```

### 5. Use Caching Wisely

```elixir
# Cache expensive operations
step :expensive_analysis do
  template :deep_analysis
  cache_key fn context ->
    # Include relevant context in cache key
    "#{context.file_hash}-#{context.analysis_version}"
  end
end
```

### 6. Monitor Performance

```elixir
# Add custom metrics
step :critical_step do
  template :important_analysis
  
  before_execute fn context ->
    :telemetry.execute(
      [:my_app, :cot, :critical_step, :start],
      %{system_time: System.system_time()},
      %{context: context}
    )
  end
end
```

## 11. Troubleshooting {#troubleshooting}

### Common Issues and Solutions

#### 1. Chain Execution Timeout

**Problem**: Chain exceeds configured timeout
```elixir
{:error, :timeout}
```

**Solution**:
```elixir
reasoning_chain do
  config do
    timeout_ms 120_000  # Increase timeout
  end
  
  # Or set per-step timeouts
  step :slow_step do
    timeout_ms 60_000
  end
end
```

#### 2. Circular Dependencies

**Problem**: Steps have circular dependencies
```elixir
** (CompileError) Circular dependency detected: step_a -> step_b -> step_a
```

**Solution**: Review and restructure dependencies
```elixir
# Instead of circular dependencies
# Use sequential steps or merge related logic
```

#### 3. Cache Invalidation Issues

**Problem**: Stale cache results
**Solution**:
```elixir
# Manual invalidation
ConversationManager.invalidate_cache(
  chain: :my_chain,
  context_match: %{user_id: "user123"}
)

# Or use versioned cache keys
cache_key fn context ->
  "#{context.version}-#{context.file_hash}"
end
```

#### 4. Memory Leaks in Long Sessions

**Problem**: Memory usage grows over time
**Solution**:
```elixir
# Set session limits
ConversationManager.start_conversation(
  chain: :my_chain,
  options: [
    max_history_size: 50,
    cleanup_interval: :timer.minutes(5)
  ]
)
```

### Debugging Tools

```elixir
# Enable debug mode
{:ok, session} = ConversationManager.start_conversation(
  chain: :my_chain,
  debug: true
)

# Inspect execution plan
{:ok, plan} = ConversationManager.get_execution_plan(session)

# Trace execution
ConversationManager.trace_execution(session, fn event ->
  IO.inspect(event, label: "CoT Event")
end)
```

### Performance Profiling

```elixir
# Profile chain execution
:fprof.trace([:start])
{:ok, result} = ConversationManager.execute_chain(session)
:fprof.trace([:stop])
:fprof.analyse()

# Or use built-in profiling
ConversationManager.execute_chain(session, profile: true)
```

## Conclusion

The Chain-of-Thought system in RubberDuck provides a powerful framework for structured reasoning in AI-assisted coding tasks. By leveraging Elixir's concurrent processing capabilities and the declarative Spark DSL, it offers:

- **Flexibility**: Customizable reasoning chains for any task
- **Performance**: Efficient caching and parallel execution
- **Reliability**: Built on OTP principles with proper supervision
- **Integration**: Seamless integration with other RubberDuck systems
- **Observability**: Comprehensive telemetry and debugging tools

Whether you're building simple code reviews or complex architectural planning workflows, the CoT system provides the tools needed to create sophisticated, explainable AI reasoning chains that enhance the coding assistant's capabilities.
