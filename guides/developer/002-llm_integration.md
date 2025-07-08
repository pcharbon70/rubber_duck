# RubberDuck LLM Integration System - Comprehensive Guide

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Core Components](#core-components)
4. [Provider Integration](#provider-integration)
5. [Hierarchical Memory System](#hierarchical-memory-system)
6. [Context Management](#context-management)
7. [Enhancement Techniques](#enhancement-techniques)
8. [Implementation Examples](#implementation-examples)
9. [Configuration](#configuration)
10. [Performance Optimization](#performance-optimization)
11. [Testing Strategy](#testing-strategy)
12. [Best Practices](#best-practices)

## Overview

The RubberDuck LLM Integration System is a sophisticated, fault-tolerant architecture built on Elixir/OTP principles. It provides multi-provider support, intelligent context management, and advanced LLM enhancement techniques to deliver state-of-the-art AI-powered coding assistance.

### Key Features

- **Multi-Provider Support**: Seamless integration with OpenAI, Anthropic, and local models
- **Fault Tolerance**: Circuit breakers, automatic fallback, and retry mechanisms
- **Hierarchical Memory**: Three-tier memory system for context preservation
- **Enhancement Stack**: Chain-of-Thought (CoT), RAG, and Self-Correction techniques
- **Concurrent Processing**: Leverages Elixir's actor model for parallel operations
- **Cost Optimization**: Token usage tracking and rate limiting

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    RubberDuck LLM System                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ Enhancement     │  │ Context Builder │  │   Memory    │ │
│  │ Coordinator     │  │                 │  │   Manager   │ │
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘ │
│           │                     │                   │        │
│  ┌────────▼─────────────────────▼───────────────────▼──────┐ │
│  │                   LLM Service Layer                      │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             │ │
│  │  │ OpenAI   │  │Anthropic │  │  Local   │             │ │
│  │  │ Provider │  │ Provider │  │ Provider │             │ │
│  │  └──────────┘  └──────────┘  └──────────┘             │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

1. **Request Initiation**: User request enters through Engine System
2. **Context Building**: Context Builder assembles relevant information
3. **Memory Retrieval**: Memory Manager provides historical context
4. **Enhancement Selection**: Coordinator chooses appropriate techniques
5. **LLM Processing**: Service routes to appropriate provider
6. **Response Enhancement**: Post-processing and validation
7. **Memory Update**: Results stored in hierarchical memory

## Core Components

### 1. LLM Service (`RubberDuck.LLM.Service`)

The central GenServer managing all LLM interactions:

```elixir
defmodule RubberDuck.LLM.Service do
  use GenServer
  
  @type provider :: :openai | :anthropic | :local
  @type model :: String.t()
  
  @type request :: %{
    prompt: String.t(),
    model: model(),
    max_tokens: pos_integer(),
    temperature: float(),
    options: map()
  }
  
  @type response :: %{
    content: String.t(),
    usage: %{
      prompt_tokens: pos_integer(),
      completion_tokens: pos_integer(),
      total_tokens: pos_integer()
    },
    provider: provider(),
    model: model()
  }
end
```

**Key Features:**
- Provider selection based on model availability
- Automatic fallback on provider failure
- Request queuing and rate limiting
- Cost tracking per provider
- Circuit breaker pattern implementation

### 2. Provider Adapters

Each provider implements a common behavior:

```elixir
defmodule RubberDuck.LLM.Provider do
  @callback complete(request :: map()) :: {:ok, response :: map()} | {:error, term()}
  @callback stream(request :: map()) :: {:ok, stream :: Enumerable.t()} | {:error, term()}
  @callback available_models() :: [String.t()]
  @callback count_tokens(text :: String.t()) :: pos_integer()
end
```

**Supported Providers:**
- **OpenAI**: GPT-4, GPT-4o with function calling
- **Anthropic**: Claude 3.5 with system prompts
- **Mock**: Testing and development

### 3. Circuit Breaker

Prevents cascading failures:

```elixir
defmodule RubberDuck.LLM.CircuitBreaker do
  @states [:closed, :open, :half_open]
  
  def call(provider, fun) do
    case get_state(provider) do
      :open -> {:error, :circuit_open}
      :closed -> execute_with_monitoring(provider, fun)
      :half_open -> execute_with_caution(provider, fun)
    end
  end
end
```

## Provider Integration

### OpenAI Integration

```elixir
# Configuration
config :rubber_duck, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  organization: System.get_env("OPENAI_ORG_ID"),
  base_url: "https://api.openai.com/v1"

# Usage
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  prompt: "Generate a function to calculate fibonacci",
  model: "gpt-4",
  max_tokens: 500,
  temperature: 0.7
})
```

### Anthropic Integration

```elixir
# Configuration
config :rubber_duck, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  base_url: "https://api.anthropic.com/v1"

# Usage with system prompt
{:ok, response} = RubberDuck.LLM.Service.complete(%{
  prompt: "Explain this code",
  model: "claude-3-5-sonnet",
  system: "You are an expert Elixir developer",
  max_tokens: 1000
})
```

### Streaming Responses

```elixir
{:ok, stream} = RubberDuck.LLM.Service.stream(%{
  prompt: "Write a comprehensive test suite",
  model: "gpt-4",
  max_tokens: 2000
})

stream
|> Stream.each(fn chunk ->
  IO.write(chunk.content)
end)
|> Stream.run()
```

## Hierarchical Memory System

### Architecture

The memory system consists of three tiers:

1. **Short-term Memory**: Session-based, ETS storage
2. **Mid-term Memory**: Pattern extraction, heat scoring
3. **Long-term Memory**: Persistent patterns, PostgreSQL

### Memory Manager

```elixir
defmodule RubberDuck.Memory.Manager do
  use GenServer
  
  # Store interaction
  def store_interaction(session_id, interaction) do
    GenServer.call(__MODULE__, {:store, session_id, interaction})
  end
  
  # Retrieve context
  def get_context(session_id, query_type) do
    GenServer.call(__MODULE__, {:get_context, session_id, query_type})
  end
  
  # Consolidate memory
  def consolidate(session_id) do
    GenServer.cast(__MODULE__, {:consolidate, session_id})
  end
end
```

### Memory Flow

```
User Interaction
       │
       ▼
┌─────────────────┐
│ Short-term (ETS)│ ← Recent 20 interactions
└────────┬────────┘
         │ Pattern extraction
         ▼
┌─────────────────┐
│ Mid-term (ETS)  │ ← Session patterns, heat scores
└────────┬────────┘
         │ Consolidation
         ▼
┌─────────────────┐
│Long-term (PG)   │ ← User profiles, code patterns
└─────────────────┘
```

### Usage Example

```elixir
# Store interaction
RubberDuck.Memory.Manager.store_interaction(session_id, %{
  type: :code_generation,
  input: "Create a GenServer",
  output: "defmodule MyServer do...",
  timestamp: DateTime.utc_now()
})

# Retrieve hierarchical context
context = RubberDuck.Memory.Manager.get_context(session_id, :code_generation)
# Returns relevant patterns from all memory tiers
```

## Context Management

### Context Builder

The Context Builder assembles optimal context for LLM requests:

```elixir
defmodule RubberDuck.Context.Builder do
  @strategies [:fim, :rag, :long_context]
  
  def build(type, params) do
    strategy = select_strategy(type)
    
    context = 
      params
      |> apply_strategy(strategy)
      |> optimize_size()
      |> add_memory_context()
      |> cache_if_appropriate()
    
    {:ok, context}
  end
end
```

### Context Strategies

#### 1. Fill-in-the-Middle (FIM)

For code completion:

```elixir
def build_fim_context(cursor_position, file_content) do
  %{
    prefix: extract_prefix(file_content, cursor_position),
    suffix: extract_suffix(file_content, cursor_position),
    language: detect_language(file_content),
    tokens: %{
      prefix_token: "<fim_prefix>",
      suffix_token: "<fim_suffix>",
      middle_token: "<fim_middle>"
    }
  }
end
```

#### 2. Retrieval Augmented Generation (RAG)

For context-aware generation:

```elixir
def build_rag_context(query, project_id) do
  # Semantic search
  similar_code = search_similar_code(query, project_id)
  
  # Pattern extraction
  patterns = extract_patterns(similar_code)
  
  # Context assembly
  %{
    query: query,
    similar_code: similar_code,
    patterns: patterns,
    project_context: get_project_context(project_id)
  }
end
```

#### 3. Long Context Window

For complex analysis:

```elixir
def build_long_context(files, analysis_type) do
  files
  |> Enum.map(&extract_relevant_sections/1)
  |> combine_with_priority()
  |> fit_to_window(max_tokens: 8000)
end
```

### Context Caching

```elixir
# ETS-based caching
def cache_context(key, context) do
  :ets.insert(:context_cache, {key, context, :os.system_time(:second)})
end

def get_cached_context(key) do
  case :ets.lookup(:context_cache, key) do
    [{^key, context, timestamp}] ->
      if fresh?(timestamp), do: {:ok, context}, else: :miss
    [] -> :miss
  end
end
```

## Enhancement Techniques

### 1. Chain-of-Thought (CoT)

Structured reasoning for complex tasks:

```elixir
defmodule RubberDuck.CoT.Engine do
  use RubberDuck.CoT.Dsl
  
  reasoning_chain :code_analysis do
    step :understand_requirements do
      prompt "What is the main goal of this code?"
    end
    
    step :identify_patterns do
      prompt "What design patterns are used?"
      depends_on :understand_requirements
    end
    
    step :suggest_improvements do
      prompt "Based on patterns, what improvements can be made?"
      depends_on :identify_patterns
    end
  end
end
```

**Execution:**

```elixir
{:ok, result} = RubberDuck.CoT.Engine.execute(:code_analysis, %{
  code: file_content,
  language: "elixir"
})

# Result includes step-by-step reasoning
%{
  steps: [
    %{name: :understand_requirements, output: "..."},
    %{name: :identify_patterns, output: "..."},
    %{name: :suggest_improvements, output: "..."}
  ],
  final_output: "...",
  confidence: 0.85
}
```

### 2. Enhanced RAG

Advanced retrieval with reranking:

```elixir
defmodule RubberDuck.RAG.Pipeline do
  def process(query, options \\ []) do
    query
    |> generate_embeddings()
    |> search_documents(options)
    |> rerank_results()
    |> prepare_context()
    |> generate_with_citations()
  end
  
  defp rerank_results(documents) do
    documents
    |> score_relevance()
    |> apply_diversity()
    |> take_top_k()
  end
end
```

**Document Processing:**

```elixir
# Chunking strategies
chunks = RubberDuck.RAG.Chunker.chunk(document, 
  strategy: :semantic,
  max_size: 500,
  overlap: 50
)

# Embedding generation
embeddings = RubberDuck.RAG.Embeddings.generate(chunks)

# Store in vector database
RubberDuck.RAG.VectorStore.insert(embeddings)
```

### 3. Iterative Self-Correction

Automatic output refinement:

```elixir
defmodule RubberDuck.SelfCorrection.Engine do
  def refine(output, options \\ []) do
    output
    |> validate()
    |> identify_issues()
    |> generate_corrections()
    |> apply_corrections()
    |> iterate_until_satisfied()
  end
  
  defp iterate_until_satisfied(output, iteration \\ 1) do
    if satisfied?(output) or iteration > max_iterations() do
      {:ok, output}
    else
      output
      |> generate_improvement_prompt()
      |> request_llm_refinement()
      |> iterate_until_satisfied(iteration + 1)
    end
  end
end
```

### Enhancement Coordination

The Enhancement Coordinator intelligently combines techniques:

```elixir
defmodule RubberDuck.Enhancement.Coordinator do
  def enhance(task, input) do
    # Analyze task complexity
    complexity = analyze_complexity(task, input)
    
    # Select techniques
    techniques = select_techniques(complexity)
    
    # Build pipeline
    pipeline = build_pipeline(techniques, complexity.type)
    
    # Execute
    execute_pipeline(pipeline, input)
  end
  
  defp select_techniques(complexity) do
    cond do
      complexity.reasoning_required -> [:cot, :self_correction]
      complexity.context_needed -> [:rag, :self_correction]
      complexity.simple -> [:direct]
      true -> [:cot, :rag, :self_correction]
    end
  end
end
```

## Implementation Examples

### Example 1: Code Generation with Full Enhancement

```elixir
defmodule MyApp.CodeGenerator do
  alias RubberDuck.{Enhancement, Memory, Context}
  
  def generate_code(prompt, project_id, user_id) do
    # Build context
    {:ok, context} = Context.Builder.build(:generation, %{
      prompt: prompt,
      project_id: project_id,
      strategy: :rag
    })
    
    # Enhance with CoT + RAG + Self-Correction
    {:ok, result} = Enhancement.Coordinator.enhance(:code_generation, %{
      prompt: prompt,
      context: context,
      techniques: [:cot, :rag, :self_correction]
    })
    
    # Store in memory
    Memory.Manager.store_interaction(user_id, %{
      type: :generation,
      input: prompt,
      output: result.code,
      metadata: result.metadata
    })
    
    result
  end
end
```

### Example 2: Streaming Code Completion

```elixir
defmodule MyApp.CodeCompletion do
  alias RubberDuck.{LLM, Context}
  
  def complete(prefix, suffix, language) do
    # Build FIM context
    {:ok, context} = Context.Builder.build(:completion, %{
      prefix: prefix,
      suffix: suffix,
      language: language,
      strategy: :fim
    })
    
    # Stream completion
    {:ok, stream} = LLM.Service.stream(%{
      prompt: format_fim_prompt(context),
      model: "gpt-4",
      max_tokens: 150,
      temperature: 0.2,
      stop: ["\n\n", "end"]
    })
    
    stream
  end
end
```

### Example 3: Code Analysis with Memory

```elixir
defmodule MyApp.CodeAnalyzer do
  alias RubberDuck.{Workflows, Memory}
  
  def analyze_with_history(file_path, user_id) do
    # Get historical context
    context = Memory.Manager.get_context(user_id, :analysis)
    
    # Run analysis workflow
    {:ok, result} = Workflows.CompleteAnalysis.run(%{
      file: file_path,
      context: context,
      include_llm_review: true
    })
    
    # Update memory with patterns
    Memory.Manager.consolidate(user_id)
    
    result
  end
end
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs
config :rubber_duck, :llm,
  default_provider: :openai,
  timeout: 30_000,
  max_retries: 3,
  retry_delay: 1_000

config :rubber_duck, :memory,
  short_term_ttl: 3600,        # 1 hour
  mid_term_ttl: 86_400,        # 1 day
  consolidation_interval: 300   # 5 minutes

config :rubber_duck, :context,
  max_tokens: 4000,
  cache_ttl: 600,              # 10 minutes
  embedding_model: "text-embedding-ada-002"
```

### Provider-Specific Configuration

```elixir
# config/prod.exs
config :rubber_duck, :providers,
  openai: [
    api_key: {:system, "OPENAI_API_KEY"},
    models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
    rate_limit: 100_000  # tokens per minute
  ],
  anthropic: [
    api_key: {:system, "ANTHROPIC_API_KEY"},
    models: ["claude-3-5-sonnet"],
    rate_limit: 50_000
  ]
```

### Circuit Breaker Configuration

```elixir
config :rubber_duck, :circuit_breaker,
  failure_threshold: 5,
  reset_timeout: 60_000,      # 1 minute
  half_open_requests: 3
```

## Performance Optimization

### 1. Concurrent Processing

Leverage Elixir's concurrency:

```elixir
defmodule RubberDuck.Parallel do
  def process_files(files, fun) do
    files
    |> Task.async_stream(fun, 
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
    |> Enum.reduce({[], []}, fn
      {:ok, result}, {results, errors} -> 
        {[result | results], errors}
      {:error, error}, {results, errors} -> 
        {results, [error | errors]}
    end)
  end
end
```

### 2. Caching Strategy

Multi-level caching:

```elixir
defmodule RubberDuck.Cache do
  # L1: Process dictionary (request-scoped)
  def get_l1(key), do: Process.get(key)
  def put_l1(key, value), do: Process.put(key, value)
  
  # L2: ETS (node-scoped)
  def get_l2(key) do
    case :ets.lookup(:cache, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
  end
  
  # L3: Redis (cluster-scoped)
  def get_l3(key) do
    case Redis.get(key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, :erlang.binary_to_term(value)}
      error -> error
    end
  end
end
```

### 3. Token Optimization

Intelligent token management:

```elixir
defmodule RubberDuck.TokenOptimizer do
  def optimize_prompt(prompt, max_tokens) do
    current_tokens = count_tokens(prompt)
    
    if current_tokens <= max_tokens do
      prompt
    else
      prompt
      |> prioritize_sections()
      |> trim_to_fit(max_tokens)
      |> add_continuation_marker()
    end
  end
end
```

## Testing Strategy

### 1. Unit Tests

Test individual components:

```elixir
defmodule RubberDuck.LLM.ServiceTest do
  use ExUnit.Case
  import Mox
  
  setup :verify_on_exit!
  
  test "completes request with primary provider" do
    expect(MockProvider, :complete, fn request ->
      assert request.model == "gpt-4"
      {:ok, %{content: "Generated code"}}
    end)
    
    assert {:ok, response} = Service.complete(%{
      prompt: "Test",
      model: "gpt-4"
    })
  end
  
  test "falls back to secondary provider on failure" do
    expect(MockOpenAI, :complete, fn _ ->
      {:error, :rate_limit}
    end)
    
    expect(MockAnthropic, :complete, fn _ ->
      {:ok, %{content: "Fallback response"}}
    end)
    
    assert {:ok, response} = Service.complete(%{
      prompt: "Test",
      model: "gpt-4"
    })
    
    assert response.provider == :anthropic
  end
end
```

### 2. Integration Tests

Test component interactions:

```elixir
defmodule RubberDuck.Integration.EnhancementTest do
  use RubberDuck.DataCase
  
  test "complete enhancement pipeline" do
    # Setup
    project = insert(:project)
    insert_list(10, :code_file, project: project)
    
    # Execute
    result = Enhancement.Coordinator.enhance(:code_generation, %{
      prompt: "Create a GenServer",
      project_id: project.id,
      techniques: [:cot, :rag, :self_correction]
    })
    
    # Verify
    assert {:ok, enhanced} = result
    assert enhanced.cot_steps
    assert enhanced.rag_context
    assert enhanced.corrections_applied > 0
  end
end
```

### 3. Property-Based Tests

Test invariants:

```elixir
defmodule RubberDuck.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "context never exceeds token limit" do
    check all content <- string(:alphanumeric, min_length: 100),
              max_tokens <- integer(500..4000) do
      
      context = Context.Builder.build(:any, %{
        content: content,
        max_tokens: max_tokens
      })
      
      assert count_tokens(context) <= max_tokens
    end
  end
end
```

## Best Practices

### 1. Error Handling

Always handle LLM failures gracefully:

```elixir
def safe_generate(prompt) do
  with {:ok, context} <- build_context(prompt),
       {:ok, enhanced} <- enhance_prompt(context),
       {:ok, response} <- call_llm(enhanced) do
    {:ok, process_response(response)}
  else
    {:error, :rate_limit} -> 
      {:error, "Service temporarily unavailable"}
    {:error, :invalid_response} -> 
      {:error, "Could not generate valid code"}
    error -> 
      Logger.error("Unexpected error: #{inspect(error)}")
      {:error, "An unexpected error occurred"}
  end
end
```

### 2. Cost Management

Track and limit token usage:

```elixir
defmodule RubberDuck.CostManager do
  def check_budget(user_id, estimated_tokens) do
    current_usage = get_usage(user_id)
    budget = get_budget(user_id)
    
    if current_usage + estimated_tokens <= budget do
      :ok
    else
      {:error, :budget_exceeded}
    end
  end
  
  def track_usage(user_id, provider, tokens, cost) do
    Usage.create(%{
      user_id: user_id,
      provider: provider,
      tokens: tokens,
      cost: cost,
      timestamp: DateTime.utc_now()
    })
  end
end
```

### 3. Monitoring

Comprehensive telemetry:

```elixir
defmodule RubberDuck.Telemetry do
  def setup do
    events = [
      [:rubber_duck, :llm, :request, :start],
      [:rubber_duck, :llm, :request, :stop],
      [:rubber_duck, :enhancement, :cot, :stop],
      [:rubber_duck, :enhancement, :rag, :stop],
      [:rubber_duck, :memory, :consolidation, :stop]
    ]
    
    :telemetry.attach_many(
      "rubber-duck-handler",
      events,
      &handle_event/4,
      nil
    )
  end
  
  defp handle_event(event, measurements, metadata, _config) do
    # Log to your metrics system
    Metrics.record(event, measurements, metadata)
  end
end
```

### 4. Security Considerations

- **API Key Management**: Use environment variables or secrets management
- **Input Validation**: Sanitize all user inputs before LLM processing
- **Rate Limiting**: Implement per-user and per-IP rate limits
- **Content Filtering**: Screen for malicious prompts
- **Audit Logging**: Track all LLM interactions

### 5. Scalability Patterns

```elixir
# Use connection pooling
defmodule RubberDuck.LLM.Pool do
  use Supervisor
  
  def start_link(opts) do
    children = for i <- 1..pool_size() do
      {RubberDuck.LLM.Worker, name: :"llm_worker_#{i}"}
    end
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end

# Implement backpressure
defmodule RubberDuck.LLM.Queue do
  def enqueue(request) do
    if queue_size() < max_queue_size() do
      do_enqueue(request)
    else
      {:error, :queue_full}
    end
  end
end
```

## Conclusion

The RubberDuck LLM Integration System provides a robust, scalable foundation for AI-powered coding assistance. By leveraging Elixir's strengths in concurrency and fault tolerance, combined with advanced LLM enhancement techniques, it delivers enterprise-grade reliability with state-of-the-art AI capabilities.

Key takeaways:
- Multi-provider support ensures availability
- Hierarchical memory enables context-aware assistance
- Enhancement techniques improve output quality
- Fault tolerance patterns prevent system failures
- Comprehensive monitoring enables optimization

For more information, refer to the specific implementation modules in the codebase and the extensive test suites that demonstrate usage patterns.
