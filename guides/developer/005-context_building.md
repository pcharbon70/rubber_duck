# RubberDuck Context Building and Caching System - Comprehensive Guide

## Overview

The Context Building and Caching System in RubberDuck is a sophisticated mechanism designed to efficiently construct and manage context for Large Language Model (LLM) interactions. This system is crucial for providing relevant information to LLMs while optimizing token usage and response quality. The implementation leverages Elixir's concurrent processing capabilities and ETS (Erlang Term Storage) for high-performance caching.

## Architecture Overview

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Context.Builder    │────▶│ Context Strategies│────▶│  ETS Cache      │
│                     │     │  - FIM           │     │                 │
│  - build/2          │     │  - RAG           │     │  - Storage      │
│  - optimize/2       │     │  - Long Context  │     │  - Retrieval    │
│  - score/1          │     └──────────────────┘     │  - Invalidation │
└─────────────────────┘                               └─────────────────┘
         │                                                     │
         ▼                                                     ▼
┌─────────────────────┐                               ┌─────────────────┐
│ Embedding Service   │                               │ Memory Manager   │
│                     │                               │                 │
│ - generate/1        │                               │ - Short-term    │
│ - similarity/2      │                               │ - Mid-term      │
└─────────────────────┘                               │ - Long-term     │
                                                      └─────────────────┘
```

## Core Components

### 1. Context.Builder Module

The `RubberDuck.Context.Builder` module serves as the main entry point for context construction. It orchestrates different context strategies based on the task requirements.

```elixir
defmodule RubberDuck.Context.Builder do
  @moduledoc """
  Builds optimized context for LLM interactions using various strategies.
  """
  
  # Main context building function
  def build(query, opts \\ []) do
    strategy = determine_strategy(query, opts)
    
    case get_cached_context(query, strategy) do
      {:ok, context} -> {:ok, context}
      :miss -> build_fresh_context(query, strategy, opts)
    end
  end
  
  # Context optimization based on token limits
  def optimize(context, max_tokens) do
    # Implementation for context size optimization
  end
  
  # Quality scoring for context relevance
  def score(context) do
    # Implementation for context quality assessment
  end
end
```

### 2. Context Strategies

The system implements three primary context strategies, each optimized for different use cases:

#### 2.1 FIM (Fill-in-the-Middle) Strategy

Used primarily for code completion tasks where the system needs to understand code before and after the cursor position.

```elixir
defmodule RubberDuck.Context.Strategies.FIM do
  @moduledoc """
  Fill-in-the-Middle context strategy for code completion.
  """
  
  @default_prefix_size 1500  # tokens
  @default_suffix_size 500   # tokens
  
  def build(params) do
    %{
      file_content: content,
      cursor_position: position,
      language: language
    } = params
    
    prefix = extract_prefix(content, position)
    suffix = extract_suffix(content, position)
    
    %{
      strategy: :fim,
      prefix: optimize_prefix(prefix, @default_prefix_size),
      suffix: optimize_suffix(suffix, @default_suffix_size),
      language: language,
      metadata: build_metadata(content, position)
    }
  end
end
```

#### 2.2 RAG (Retrieval Augmented Generation) Strategy

Leverages semantic search to find relevant code snippets and documentation to enhance generation quality.

```elixir
defmodule RubberDuck.Context.Strategies.RAG do
  @moduledoc """
  Retrieval Augmented Generation context strategy.
  """
  
  def build(params) do
    %{
      query: query,
      project_id: project_id,
      options: opts
    } = params
    
    # Retrieve relevant documents
    relevant_docs = retrieve_relevant_documents(query, project_id, opts)
    
    # Rerank and filter
    ranked_docs = rerank_documents(relevant_docs, query)
    
    # Build context from top documents
    %{
      strategy: :rag,
      query: query,
      documents: Enum.take(ranked_docs, opts[:max_documents] || 5),
      metadata: build_retrieval_metadata(ranked_docs)
    }
  end
  
  defp retrieve_relevant_documents(query, project_id, opts) do
    # Semantic search implementation
    embeddings = RubberDuck.Embeddings.generate(query)
    
    RubberDuck.VectorStore.search(%{
      embeddings: embeddings,
      project_id: project_id,
      limit: opts[:retrieval_limit] || 20
    })
  end
end
```

#### 2.3 Long Context Window Strategy

Optimized for models with extended context windows, allowing for more comprehensive information inclusion.

```elixir
defmodule RubberDuck.Context.Strategies.LongContext do
  @moduledoc """
  Strategy for models supporting extended context windows.
  """
  
  @max_context_tokens 100_000
  
  def build(params) do
    %{
      files: files,
      query: query,
      focus_file: focus_file
    } = params
    
    # Prioritize files based on relevance
    prioritized_files = prioritize_files(files, query, focus_file)
    
    # Build layered context
    context_layers = build_context_layers(prioritized_files)
    
    %{
      strategy: :long_context,
      layers: context_layers,
      total_tokens: calculate_tokens(context_layers),
      metadata: build_layer_metadata(context_layers)
    }
  end
end
```

### 3. Context Caching System

The caching system uses ETS for high-performance storage and retrieval of computed contexts.

```elixir
defmodule RubberDuck.Context.Cache do
  @moduledoc """
  ETS-based caching for computed contexts.
  """
  
  use GenServer
  
  @table_name :context_cache
  @default_ttl :timer.minutes(30)
  @max_cache_size 1000
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    schedule_cleanup()
    {:ok, %{table: table, size: 0}}
  end
  
  # Cache operations
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] ->
        if :os.system_time(:millisecond) < expiry do
          {:ok, value}
        else
          :ets.delete(@table_name, key)
          :miss
        end
      [] ->
        :miss
    end
  end
  
  def put(key, value, ttl \\ @default_ttl) do
    expiry = :os.system_time(:millisecond) + ttl
    
    GenServer.call(__MODULE__, {:put, key, value, expiry})
  end
  
  # Cache invalidation
  def invalidate(pattern) do
    GenServer.cast(__MODULE__, {:invalidate, pattern})
  end
  
  # Cleanup process
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(5))
  end
  
  def handle_info(:cleanup, state) do
    now = :os.system_time(:millisecond)
    
    expired_keys = :ets.select(@table_name, [
      {{'$1', '_', '$3'}, [{:<, '$3', now}], ['$1']}
    ])
    
    Enum.each(expired_keys, &:ets.delete(@table_name, &1))
    
    schedule_cleanup()
    {:noreply, state}
  end
end
```

### 4. Embedding Service

The embedding service handles vector generation for semantic similarity operations.

```elixir
defmodule RubberDuck.Context.Embeddings do
  @moduledoc """
  Service for generating and managing embeddings.
  """
  
  # For now, using mock embeddings - will integrate with LLM service
  def generate(text) when is_binary(text) do
    # Mock implementation - returns random vectors
    # In production, this would call the LLM embedding API
    vector_size = 1536  # OpenAI ada-002 dimension
    for _ <- 1..vector_size, do: :rand.uniform()
  end
  
  def generate(texts) when is_list(texts) do
    Enum.map(texts, &generate/1)
  end
  
  # Cosine similarity calculation
  def similarity(vec1, vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    magnitude1 = :math.sqrt(Enum.map(vec1, &(&1 * &1)) |> Enum.sum())
    magnitude2 = :math.sqrt(Enum.map(vec2, &(&1 * &1)) |> Enum.sum())
    
    dot_product / (magnitude1 * magnitude2)
  end
end
```

### 5. Context Size Optimization

The optimization system ensures contexts fit within token limits while preserving maximum relevant information.

```elixir
defmodule RubberDuck.Context.Optimizer do
  @moduledoc """
  Optimizes context size while maintaining relevance.
  """
  
  def optimize(context, max_tokens) do
    current_tokens = estimate_tokens(context)
    
    if current_tokens <= max_tokens do
      context
    else
      apply_optimization_strategies(context, max_tokens)
    end
  end
  
  defp apply_optimization_strategies(context, max_tokens) do
    context
    |> remove_comments()
    |> truncate_long_strings()
    |> prioritize_relevant_sections()
    |> compress_whitespace()
    |> trim_to_token_limit(max_tokens)
  end
  
  # Token estimation (rough approximation)
  defp estimate_tokens(context) do
    # Rough estimate: 1 token ≈ 4 characters
    String.length(format_context(context)) / 4
  end
end
```

### 6. Quality Scoring System

The quality scoring system evaluates context relevance and completeness.

```elixir
defmodule RubberDuck.Context.QualityScorer do
  @moduledoc """
  Scores context quality for LLM consumption.
  """
  
  def score(context) do
    %{
      relevance_score: calculate_relevance(context),
      completeness_score: calculate_completeness(context),
      coherence_score: calculate_coherence(context),
      diversity_score: calculate_diversity(context)
    }
    |> calculate_overall_score()
  end
  
  defp calculate_relevance(context) do
    # Score based on:
    # - Keyword matches
    # - Semantic similarity
    # - Recency of information
  end
  
  defp calculate_completeness(context) do
    # Score based on:
    # - Coverage of related concepts
    # - Presence of necessary imports/dependencies
    # - Context boundaries (start/end of functions, etc.)
  end
  
  defp calculate_coherence(context) do
    # Score based on:
    # - Logical flow of information
    # - Syntactic correctness
    # - Semantic consistency
  end
  
  defp calculate_diversity(context) do
    # Score based on:
    # - Variety of examples
    # - Different coding patterns
    # - Multiple perspectives
  end
end
```

### 7. Adaptive Context Selection

The adaptive selection system learns from usage patterns to improve context quality over time.

```elixir
defmodule RubberDuck.Context.AdaptiveSelector do
  @moduledoc """
  Adapts context selection based on historical effectiveness.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    {:ok, %{
      strategy_scores: %{},
      selection_history: []
    }}
  end
  
  def select_strategy(query_type, user_preferences) do
    GenServer.call(__MODULE__, {:select_strategy, query_type, user_preferences})
  end
  
  def record_effectiveness(strategy, query_type, score) do
    GenServer.cast(__MODULE__, {:record_effectiveness, strategy, query_type, score})
  end
  
  def handle_call({:select_strategy, query_type, preferences}, _from, state) do
    strategy = determine_best_strategy(query_type, preferences, state.strategy_scores)
    
    {:reply, strategy, update_history(state, strategy, query_type)}
  end
  
  defp determine_best_strategy(query_type, preferences, scores) do
    # Use multi-armed bandit algorithm for exploration vs exploitation
    available_strategies = [:fim, :rag, :long_context]
    
    if :rand.uniform() < 0.1 do  # 10% exploration
      Enum.random(available_strategies)
    else
      # Select based on historical performance
      select_by_scores(available_strategies, query_type, scores)
    end
  end
end
```

## Usage Patterns

### 1. Basic Context Building

```elixir
# For code completion
{:ok, context} = RubberDuck.Context.Builder.build(
  %{
    type: :completion,
    file_content: file_content,
    cursor_position: 1234,
    language: "elixir"
  },
  strategy: :fim
)

# For code generation with RAG
{:ok, context} = RubberDuck.Context.Builder.build(
  %{
    type: :generation,
    query: "Create a GenServer that manages user sessions",
    project_id: project_id
  },
  strategy: :rag
)
```

### 2. Context Optimization

```elixir
# Optimize context for specific model limits
optimized_context = RubberDuck.Context.Builder.optimize(context, 4096)

# Check context quality
quality_score = RubberDuck.Context.Builder.score(optimized_context)
```

### 3. Cache Management

```elixir
# Manual cache invalidation
RubberDuck.Context.Cache.invalidate({:project, project_id})

# Cache with custom TTL
RubberDuck.Context.Cache.put(
  cache_key,
  context,
  :timer.hours(1)
)
```

## Performance Considerations

### 1. Caching Strategy

- **Cache Key Generation**: Uses a combination of query hash, strategy type, and relevant parameters
- **TTL Management**: Default 30 minutes, adjustable based on content volatility
- **Size Limits**: Maximum 1000 cached contexts with LRU eviction
- **Concurrent Access**: ETS tables configured for high read/write concurrency

### 2. Optimization Techniques

- **Lazy Loading**: Context components loaded only when needed
- **Parallel Processing**: Multiple context sources fetched concurrently
- **Incremental Building**: Contexts built progressively to fail fast
- **Resource Pooling**: Reuses embedding computations across requests

### 3. Memory Management

- **Bounded Caches**: All caches have size limits to prevent memory bloat
- **Periodic Cleanup**: Automated cleanup processes for expired entries
- **Weak References**: Used for large context objects when appropriate
- **Stream Processing**: Large documents processed as streams

## Integration Points

### 1. Memory System Integration

The context builder integrates with the hierarchical memory system to include relevant historical information:

```elixir
defp enrich_with_memory(context, user_id, project_id) do
  memories = RubberDuck.Memory.Manager.retrieve_relevant(
    user_id,
    project_id,
    context.query
  )
  
  Map.put(context, :memories, memories)
end
```

### 2. LLM Service Integration

Contexts are formatted according to specific LLM provider requirements:

```elixir
defp format_for_provider(context, :openai) do
  # OpenAI-specific formatting
end

defp format_for_provider(context, :anthropic) do
  # Anthropic-specific formatting
end
```

### 3. Enhancement Integration

The context system supports enhancement techniques like CoT and RAG:

```elixir
defp apply_enhancements(context, [:cot, :rag]) do
  context
  |> RubberDuck.CoT.enrich()
  |> RubberDuck.RAG.augment()
end
```

## Monitoring and Debugging

### 1. Telemetry Events

The system emits telemetry events for monitoring:

```elixir
:telemetry.execute(
  [:rubber_duck, :context, :build],
  %{duration: duration, cache_hit: cache_hit},
  %{strategy: strategy, tokens: token_count}
)
```

### 2. Debug Mode

Enable detailed logging for troubleshooting:

```elixir
# In config
config :rubber_duck, :context_debug, true

# Logs will include:
# - Strategy selection reasoning
# - Cache hit/miss details
# - Optimization steps
# - Quality scores
```

## Best Practices

### 1. Strategy Selection

- Use FIM for code completion within files
- Use RAG for generating new code with examples
- Use Long Context for refactoring or analysis tasks

### 2. Cache Invalidation

- Invalidate on file changes
- Use pattern-based invalidation for project-wide changes
- Consider time-based invalidation for volatile content

### 3. Performance Optimization

- Pre-warm caches for frequently accessed content
- Use background jobs for expensive embedding generation
- Monitor cache hit rates and adjust TTLs accordingly

## Future Enhancements

### 1. Planned Improvements

- **Semantic Caching**: Cache based on semantic similarity, not just exact matches
- **Compression**: Implement context compression techniques
- **Multi-Modal Context**: Support for diagrams, documentation, and other media
- **Federated Context**: Share context across team members

### 2. Advanced Features

- **Context Streaming**: Stream large contexts progressively
- **Differential Context**: Send only context changes for updates
- **Context Templates**: Predefined context patterns for common tasks
- **Learning System**: Improve context selection based on outcome quality

## Conclusion

The RubberDuck Context Building and Caching System provides a robust foundation for efficient LLM interactions. By combining multiple strategies, intelligent caching, and adaptive selection, it ensures optimal context delivery while managing resource constraints. The system's modular design allows for easy extension and customization as requirements evolve.
