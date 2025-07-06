# Feature 3.4: Context Building and Caching - Implementation Plan

## Phase 1: Foundation

### 1.1 Create Context Domain and Base Modules
- [ ] Create `lib/rubber_duck/context.ex` domain module
- [ ] Define Context.Builder behavior with callbacks
- [ ] Create Context.Strategy protocol for extensibility
- [ ] Set up basic module structure

### 1.2 Implement Context Cache
- [ ] Create `lib/rubber_duck/context/cache.ex` using ETS
- [ ] Implement cache key generation based on query + memory state
- [ ] Add TTL support (default 15 minutes)
- [ ] Create cache statistics tracking

## Phase 2: Strategy Implementation

### 2.1 FIM (Fill-in-the-Middle) Strategy
- [ ] Create `lib/rubber_duck/context/strategies/fim.ex`
- [ ] Implement prefix/suffix extraction logic
- [ ] Add language-specific token handling
- [ ] Create window size configuration

### 2.2 RAG (Retrieval Augmented Generation) Strategy
- [ ] Create `lib/rubber_duck/context/strategies/rag.ex`
- [ ] Implement semantic search integration
- [ ] Add relevance scoring for retrieved chunks
- [ ] Create context assembly from multiple sources

### 2.3 Long Context Strategy
- [ ] Create `lib/rubber_duck/context/strategies/long_context.ex`
- [ ] Implement sliding window approach
- [ ] Add importance-based filtering
- [ ] Create hierarchical summarization

## Phase 3: Embeddings Service

### 3.1 Create Embeddings Service
- [ ] Create `lib/rubber_duck/embeddings/service.ex` GenServer
- [ ] Add support for multiple embedding models
- [ ] Implement batch processing for efficiency
- [ ] Create embedding cache layer

### 3.2 pgvector Integration
- [ ] Add pgvector queries to Memory resources
- [ ] Create similarity search functions
- [ ] Implement k-nearest neighbor search
- [ ] Add hybrid search (keyword + semantic)

## Phase 4: Optimization and Scoring

### 4.1 Context Optimizer
- [ ] Create `lib/rubber_duck/context/optimizer.ex`
- [ ] Implement token counting for different models
- [ ] Add smart truncation strategies
- [ ] Create importance-based filtering

### 4.2 Context Scorer
- [ ] Create `lib/rubber_duck/context/scorer.ex`
- [ ] Implement relevance scoring metrics
- [ ] Add diversity scoring
- [ ] Create completeness scoring

### 4.3 Adaptive Selector
- [ ] Create `lib/rubber_duck/context/adaptive_selector.ex`
- [ ] Implement query type classification
- [ ] Add strategy selection logic
- [ ] Create learning mechanism from feedback

## Phase 5: Integration and Testing

### 5.1 Integration with Memory System
- [ ] Connect to Memory.Retriever for data access
- [ ] Implement cross-tier context building
- [ ] Add memory-aware cache invalidation

### 5.2 Comprehensive Testing
- [ ] Unit tests for each strategy
- [ ] Integration tests for full context building
- [ ] Performance benchmarks with caching
- [ ] Quality evaluation tests

## Technical Decisions

### Caching Strategy
- Use ETS with TTL for fast in-memory caching
- Cache key: hash of {query, user_id, session_id, memory_snapshot}
- Invalidate on memory updates or after 15 minutes

### Embedding Model
- Start with OpenAI's text-embedding-ada-002
- Design for easy model switching
- Cache embeddings in PostgreSQL alongside content

### Token Limits
- Configurable per model (e.g., 4k, 8k, 16k, 128k)
- Reserve 20% for response generation
- Implement graceful degradation for oversized contexts

### Quality Metrics
- Relevance: cosine similarity scores
- Diversity: avoid redundant information
- Completeness: coverage of query aspects
- Recency: time-based weighting

## Implementation Order
1. Context domain and cache (foundation)
2. FIM strategy (simplest, most common use case)
3. Embeddings service
4. RAG strategy
5. Optimizer and scorer
6. Long context strategy
7. Adaptive selector
8. Full integration and testing

## Estimated Timeline
- Foundation: 2-3 hours
- Each strategy: 3-4 hours
- Embeddings service: 4-5 hours
- Optimization/scoring: 3-4 hours
- Integration/testing: 4-5 hours
- Total: ~25-30 hours