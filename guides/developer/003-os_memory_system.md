# RubberDuck Hierarchical Memory System: Comprehensive Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Memory Tiers](#memory-tiers)
4. [Implementation Details](#implementation-details)
5. [Usage Guide](#usage-guide)
6. [Performance Considerations](#performance-considerations)
7. [Future Enhancements](#future-enhancements)

## Overview

The RubberDuck memory system is a sophisticated three-tier hierarchical memory architecture designed to maintain context and learning across AI-powered coding assistant interactions. It mimics human cognitive processes by organizing information into short-term, mid-term, and long-term memory stores, each serving specific purposes and optimized for different access patterns.

### Key Features
- **Three-tier architecture**: Short-term, mid-term, and long-term memory
- **Automatic memory consolidation**: Patterns are promoted from short to long-term memory
- **Relevance-based retrieval**: Heat scoring for efficient context selection
- **Persistent storage**: PostgreSQL for long-term memory with pgvector support
- **High-performance caching**: ETS for short and mid-term memory
- **Pattern learning**: Automatic extraction of user preferences and code patterns

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Memory Manager                           │
│  (RubberDuck.Memory.Manager)                                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐│
│  │  Short-term     │  │   Mid-term      │  │  Long-term  ││
│  │   Memory        │  │    Memory       │  │   Memory    ││
│  │                 │  │                 │  │             ││
│  │  - ETS Table    │  │  - ETS Table    │  │ - PostgreSQL││
│  │  - FIFO (20)    │  │  - Heat Score   │  │ - pgvector  ││
│  │  - Session      │  │  - Patterns     │  │ - Permanent ││
│  └────────┬────────┘  └────────┬────────┘  └──────┬──────┘│
│           │                     │                   │       │
│           └─────────────────────┴───────────────────┘       │
│                             │                               │
│                    ┌────────┴────────┐                      │
│                    │    Updater      │                      │
│                    │  (Consolidation)│                      │
│                    └─────────────────┘                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┤
│  │                    Retriever                             │
│  │              (Memory Search & Retrieval)                 │
│  └─────────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────────┘
```

## Memory Tiers

### 1. Short-term Memory
**Purpose**: Immediate context for current session interactions

**Characteristics**:
- **Storage**: ETS table with FIFO eviction
- **Capacity**: 20 most recent interactions
- **Lifetime**: Session-scoped
- **Access Speed**: Microseconds
- **Data Types**: Raw interactions, immediate context

**Implementation**:
```elixir
defmodule RubberDuck.Memory.ShortTerm do
  use GenServer
  
  @max_entries 20
  @table_name :rubber_duck_short_term_memory
  
  def store_interaction(session_id, interaction) do
    # FIFO implementation with automatic expiration
    entries = :ets.lookup(@table_name, session_id)
    updated = Enum.take([interaction | entries], @max_entries)
    :ets.insert(@table_name, {session_id, updated})
  end
end
```

### 2. Mid-term Memory
**Purpose**: Pattern extraction and session summarization

**Characteristics**:
- **Storage**: ETS table with relevance scoring
- **Capacity**: Dynamic based on heat score
- **Lifetime**: Hours to days
- **Access Speed**: Milliseconds
- **Data Types**: Extracted patterns, session summaries

**Heat Score Algorithm**:
```elixir
defmodule RubberDuck.Memory.HeatScore do
  def calculate(pattern) do
    base_score = pattern.frequency * 0.4
    recency_score = calculate_recency_decay(pattern.last_access) * 0.3
    relevance_score = pattern.relevance_count * 0.3
    
    base_score + recency_score + relevance_score
  end
  
  defp calculate_recency_decay(last_access) do
    hours_ago = DateTime.diff(DateTime.utc_now(), last_access, :hour)
    :math.exp(-0.1 * hours_ago)
  end
end
```

### 3. Long-term Memory
**Purpose**: Persistent storage of learned patterns and preferences

**Characteristics**:
- **Storage**: PostgreSQL with pgvector extension
- **Capacity**: Unlimited (database constrained)
- **Lifetime**: Permanent
- **Access Speed**: 10-100ms
- **Data Types**: User profiles, code patterns, project preferences

**Schema Design**:
```elixir
defmodule RubberDuck.Memory.UserProfile do
  use Ash.Resource,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    attribute :user_id, :uuid, allow_nil?: false
    attribute :preferences, :map, default: %{}
    attribute :code_style_patterns, {:array, :map}, default: []
    attribute :language_preferences, {:array, :string}, default: []
    attribute :common_imports, :map, default: %{}
    timestamps()
  end
end

defmodule RubberDuck.Memory.CodePattern do
  use Ash.Resource,
    domain: RubberDuck.Memory,
    data_layer: AshPostgres.DataLayer
    
  attributes do
    uuid_primary_key :id
    attribute :pattern_type, :atom  # :function, :class, :import, etc.
    attribute :language, :string
    attribute :pattern_signature, :string
    attribute :usage_count, :integer, default: 0
    attribute :embedding, {:array, :float}  # For pgvector similarity
    attribute :metadata, :map
    timestamps()
  end
end
```

## Implementation Details

### Memory Manager
The central coordinator for all memory operations:

```elixir
defmodule RubberDuck.Memory.Manager do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize ETS tables for short and mid-term memory
    :ets.new(:short_term_memory, [:set, :public, :named_table])
    :ets.new(:mid_term_memory, [:set, :public, :named_table])
    
    # Schedule periodic consolidation
    schedule_consolidation()
    
    {:ok, %{}}
  end
  
  def store(level, key, value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:store, level, key, value, metadata})
  end
  
  def retrieve(query, opts \\ []) do
    GenServer.call(__MODULE__, {:retrieve, query, opts})
  end
  
  # Handles hierarchical retrieval across all memory levels
  def handle_call({:retrieve, query, opts}, _from, state) do
    results = RubberDuck.Memory.Retriever.search(query, opts)
    {:reply, results, state}
  end
end
```

### Memory Consolidation (Updater)
Automatically promotes patterns from short-term to long-term memory:

```elixir
defmodule RubberDuck.Memory.Updater do
  use GenServer
  
  @consolidation_interval :timer.hours(1)
  
  def consolidate do
    # Extract patterns from short-term memory
    patterns = extract_patterns_from_short_term()
    
    # Update mid-term memory with heat scores
    update_mid_term_patterns(patterns)
    
    # Promote high-value patterns to long-term
    promote_to_long_term(patterns)
  end
  
  defp extract_patterns_from_short_term do
    :ets.tab2list(:short_term_memory)
    |> Enum.flat_map(&analyze_interactions/1)
    |> group_and_score_patterns()
  end
  
  defp analyze_interactions({_session_id, interactions}) do
    interactions
    |> Enum.flat_map(&extract_patterns/1)
  end
  
  defp extract_patterns(interaction) do
    [
      extract_code_patterns(interaction),
      extract_language_preferences(interaction),
      extract_import_patterns(interaction)
    ]
    |> List.flatten()
  end
end
```

### Memory Retriever
Efficient search and retrieval across memory hierarchies:

```elixir
defmodule RubberDuck.Memory.Retriever do
  def search(query, opts \\ []) do
    levels = Keyword.get(opts, :levels, [:short, :mid, :long])
    limit = Keyword.get(opts, :limit, 10)
    
    levels
    |> Enum.map(&search_level(&1, query, limit))
    |> merge_and_rank_results(limit)
  end
  
  defp search_level(:short, query, limit) do
    # Fast ETS lookup for recent interactions
    :ets.match_object(:short_term_memory, {:_, :_})
    |> filter_by_query(query)
    |> Enum.take(limit)
  end
  
  defp search_level(:mid, query, limit) do
    # Heat score based retrieval
    :ets.tab2list(:mid_term_memory)
    |> Enum.sort_by(&calculate_relevance(&1, query), :desc)
    |> Enum.take(limit)
  end
  
  defp search_level(:long, query, limit) do
    # PostgreSQL with pgvector similarity search
    embedding = generate_embedding(query)
    
    CodePattern
    |> Ash.Query.order_by(similarity: {:embedding, embedding})
    |> Ash.Query.limit(limit)
    |> Ash.read!()
  end
end
```

## Usage Guide

### Basic Operations

1. **Storing an Interaction**:
```elixir
# Store in short-term memory
RubberDuck.Memory.Manager.store(:short, session_id, %{
  type: :completion,
  language: "elixir",
  code: "def hello do...",
  timestamp: DateTime.utc_now()
})
```

2. **Retrieving Context**:
```elixir
# Get relevant context for code generation
context = RubberDuck.Memory.Manager.retrieve(%{
  type: :code_generation,
  language: "elixir",
  intent: "create genserver"
}, levels: [:all], limit: 5)
```

3. **Manual Pattern Promotion**:
```elixir
# Force consolidation (usually automatic)
RubberDuck.Memory.Updater.consolidate()
```

### Integration with Engines

The memory system integrates seamlessly with the engine system:

```elixir
defmodule RubberDuck.Engines.Generation do
  def execute(input, state) do
    # Retrieve relevant context from memory
    context = RubberDuck.Memory.Manager.retrieve(%{
      type: :code_patterns,
      language: input.language,
      similarity: input.prompt
    })
    
    # Use context in generation
    enhanced_prompt = build_prompt_with_context(input.prompt, context)
    
    # Generate code...
    result = generate_with_llm(enhanced_prompt)
    
    # Store successful generation for learning
    RubberDuck.Memory.Manager.store(:short, state.session_id, %{
      type: :generation,
      input: input,
      output: result,
      success: true
    })
    
    result
  end
end
```

## Performance Considerations

### Memory Usage
- **Short-term**: ~100KB per session (20 interactions)
- **Mid-term**: ~10MB total (depends on pattern count)
- **Long-term**: Database dependent

### Access Patterns
- **Short-term**: O(1) access, no disk I/O
- **Mid-term**: O(log n) with heat score indexing
- **Long-term**: O(log n) with proper PostgreSQL indexes

### Optimization Strategies

1. **ETS Table Configuration**:
```elixir
:ets.new(:short_term_memory, [
  :set,           # Key-value store
  :public,        # Accessible from all processes
  :named_table,   # Named for easy access
  {:read_concurrency, true},  # Optimize for reads
  {:write_concurrency, true}  # Handle concurrent writes
])
```

2. **PostgreSQL Indexes**:
```sql
-- Index for fast pattern lookup
CREATE INDEX idx_code_patterns_type_language 
ON code_patterns(pattern_type, language);

-- pgvector index for similarity search
CREATE INDEX idx_code_patterns_embedding 
ON code_patterns USING ivfflat (embedding vector_cosine_ops);
```

3. **Batch Operations**:
```elixir
# Batch insert for long-term memory
patterns
|> Enum.chunk_every(100)
|> Enum.each(&RubberDuck.Memory.CodePattern.bulk_create!/1)
```

## Future Enhancements

### 1. Semantic Similarity (pgvector)
Currently prepared but not fully implemented:
```elixir
# Future implementation
defmodule RubberDuck.Memory.Similarity do
  def find_similar_code(code_snippet, opts \\ []) do
    embedding = RubberDuck.Embeddings.generate(code_snippet)
    
    CodePattern
    |> Ash.Query.filter(language: opts[:language])
    |> Ash.Query.order_by_similarity(:embedding, embedding)
    |> Ash.Query.limit(opts[:limit] || 10)
    |> Ash.read!()
  end
end
```

### 2. Memory Compression
Planned but deferred:
- Automatic summarization of old interactions
- Pattern merging for similar code styles
- Compression of embedding vectors

### 3. Privacy Controls
To be implemented in Phase 6:
- User-controlled memory retention policies
- Sensitive data filtering
- Export/import of memory snapshots
- GDPR compliance features

### 4. Advanced Learning
- Cross-project pattern learning
- Team-shared memory pools
- Transfer learning from public repositories
- Adaptive memory sizing based on usage

## Conclusion

The RubberDuck hierarchical memory system provides a sophisticated foundation for maintaining context and learning user patterns over time. By leveraging Elixir's concurrent capabilities with ETS for high-speed access and PostgreSQL for persistence, it achieves an optimal balance between performance and functionality. The three-tier architecture ensures that relevant information is always accessible while maintaining system efficiency, making it a crucial component of the AI-powered coding assistant's ability to provide personalized and context-aware assistance.
