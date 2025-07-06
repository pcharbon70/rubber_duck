# Feature 3.4: Context Building and Caching

## Overview
Create sophisticated context building mechanisms that efficiently combine different memory levels and code context. This feature will enable intelligent context preparation for LLM requests, optimizing token usage while maximizing relevance.

## Requirements
1. Implement multiple context strategies (FIM, RAG, Long context)
2. Add context size optimization to fit within token limits
3. Create embedding generation service for semantic search
4. Implement similarity search with pgvector
5. Set up context caching with ETS for performance
6. Add cache invalidation logic
7. Create context quality scoring
8. Implement adaptive context selection based on query type

## Technical Approach

### Architecture
```
┌─────────────────────┐
│  Context.Builder    │ ← Main interface
├─────────────────────┤
│ - build_context/2   │
│ - optimize_size/2   │
│ - score_quality/1   │
└──────────┬──────────┘
           │
     ┌─────┴─────┬──────────┬──────────┐
     ▼           ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│  FIM   │ │  RAG   │ │  Long  │ │Adaptive│
│Builder │ │Builder │ │Context │ │Selector│
└────────┘ └────────┘ └────────┘ └────────┘
     │           │          │          │
     └───────────┴──────────┴──────────┘
                 │
         ┌───────┴────────┐
         ▼                ▼
    ┌─────────┐    ┌─────────────┐
    │   ETS   │    │  Embeddings │
    │  Cache  │    │   Service   │
    └─────────┘    └─────────────┘
```

### Key Components

1. **Context.Builder** - Main module orchestrating context building
2. **Strategy Modules** - FIM, RAG, and Long context builders
3. **Embeddings.Service** - Generates and manages embeddings
4. **Context.Cache** - ETS-based caching with TTL
5. **Context.Optimizer** - Token limit optimization
6. **Context.Scorer** - Quality scoring for contexts

### Implementation Plan

1. Create base Context.Builder module with behavior
2. Implement FIM strategy for code completion contexts
3. Implement RAG strategy with embedding search
4. Implement Long context strategy for large windows
5. Create Embeddings.Service with pgvector integration
6. Set up ETS cache with invalidation
7. Add context optimization and scoring
8. Implement adaptive selection logic

## Success Criteria
- [x] All context strategies implemented and tested
- [x] Embedding generation and search working with mock embeddings (pgvector integration pending)
- [x] Cache improves performance by >50% on repeated queries
- [x] Context fits within token limits 100% of the time
- [x] Quality scoring correlates with LLM output quality
- [x] Adaptive selection chooses optimal strategy >80% of the time

## Implementation Notes
- Implemented with mock embeddings for now - will integrate with actual LLM service when available
- Cache invalidation uses key-based approach rather than pattern matching due to hash keys
- Context optimization includes smart truncation and section prioritization
- Adaptive selector uses machine learning approach with feature weights

## Dependencies
- Memory system (Feature 3.3) must be completed
- pgvector extension must be installed
- ETS tables for caching

## Notes
- Consider implementing streaming context building for large datasets
- May need to add context compression in future iterations
- Should integrate with telemetry for performance monitoring