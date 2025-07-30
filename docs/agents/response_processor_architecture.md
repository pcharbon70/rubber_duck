# Response Processor Agent Architecture

## Overview

The Response Processor Agent is a comprehensive post-processing pipeline for LLM responses that provides parsing, validation, enhancement, and intelligent caching capabilities. It serves as the final stage in the response pipeline, ensuring all outputs meet quality standards before delivery to clients.

## Core Components

### 1. Processing Pipeline

The main processing pipeline consists of four sequential stages:

1. **Parsing Stage**: Multi-format content parsing with automatic detection
2. **Validation Stage**: Quality scoring and safety validation
3. **Enhancement Stage**: Content improvement and enrichment
4. **Caching Stage**: Intelligent storage with TTL management

### 2. Parser System

#### Multi-Format Support
- **JSON Parser**: Handles structured data with error recovery
- **Markdown Parser**: Extracts document structure and metadata
- **Text Parser**: Comprehensive text analysis and classification
- **XML Parser**: Structured document parsing (future extension)

#### Automatic Format Detection
The parser system uses pattern matching and confidence scoring to automatically detect content formats:

```elixir
# Detection confidence scores
JSON: 0.9 for valid JSON structures
Markdown: 0.8 for documents with headers, links, or code blocks
Text: 0.6 as universal fallback
```

### 3. Validation Framework

#### Quality Scoring Components
- **Completeness Check**: Evaluates content completeness (0.0-1.0)
- **Safety Validation**: Detects sensitive information patterns
- **Readability Scoring**: Analyzes sentence structure and complexity
- **Format Validation**: Ensures consistency with expected formats

#### Scoring Algorithm
```elixir
quality_score = average([
  completeness_score,
  readability_score,
  safety_score,
  format_consistency_score
])
```

### 4. Enhancement Pipeline

#### Enhancement Types
- **Format Beautification**: Normalizes whitespace and formatting
- **Link Enrichment**: Validates and enriches URL references
- **Content Cleanup**: Removes artifacts and unwanted characters
- **Readability Improvement**: Optimizes sentence structure

#### Enhancement Flow
Enhancers are applied sequentially with logging:
1. Each enhancer receives the current content state
2. Applies specific improvements
3. Logs changes and quality impact
4. Passes enhanced content to next enhancer

### 5. Caching System

#### Cache Strategy
- **Key Generation**: MD5 hash of content + options
- **TTL Management**: Configurable expiration (default: 2 hours)
- **Size Limits**: LRU eviction when cache exceeds capacity
- **Quality Threshold**: Only caches responses above quality threshold

#### Cache Operations
```elixir
# Cache hit/miss flow
cache_key = generate_cache_key(content, options)
case get_from_cache(agent, cache_key) do
  {:hit, response} -> return_cached_response(response)
  :miss -> process_and_cache(content)
end
```

## Data Structures

### ProcessedResponse
Core data structure representing a processed response:

```elixir
%ProcessedResponse{
  id: UUID,
  original_response: String,
  parsed_content: Map | String,
  format: Atom,
  quality_score: Float,
  enhanced_content: String,
  validation_results: Map,
  enhancement_log: List,
  error_log: List,
  metadata: Map,
  processing_time: Integer,
  created_at: DateTime
}
```

### Parser Results
Structured parsing outputs vary by format:

**JSON Output:**
```elixir
%{
  parsed_data: Map,
  metadata: %{keys: List, depth: Integer, size: Integer}
}
```

**Markdown Output:**
```elixir
%{
  structure: %{headers: List, outline: List, toc: String},
  elements: %{links: List, code_blocks: List, tables: List},
  metadata: %{word_count: Integer, complexity_score: Float}
}
```

**Text Output:**
```elixir
%{
  structure: %{sentences: List, paragraphs: List},
  analysis: %{content_type: Atom, language: String, sentiment: String},
  metadata: %{reading_time: Integer, topics: List}
}
```

## Signal Interface

### Processing Signals
- `process_response`: Complete processing pipeline
- `parse_response`: Parse specific format
- `validate_response`: Quality validation only
- `enhance_response`: Content enhancement only

### Cache Management Signals
- `get_cached_response`: Retrieve cached content
- `invalidate_cache`: Remove specific cache entries
- `clear_cache`: Clear entire cache

### Status and Configuration Signals
- `get_metrics`: Processing and cache metrics
- `get_status`: Agent health status
- `configure_processor`: Update configuration

## Performance Characteristics

### Processing Metrics
- **Average Processing Time**: Tracked per response
- **Cache Hit Rate**: Percentage of cache hits vs. misses
- **Quality Distribution**: Histogram of quality scores
- **Format Distribution**: Frequency of different formats

### Scalability Features
- **Streaming Support**: All parsers support streaming input
- **Concurrent Processing**: Thread-safe operations
- **Memory Management**: Automatic cache cleanup and size limits
- **Error Recovery**: Graceful degradation on parser failures

## Configuration Options

```elixir
%{
  cache_ttl: 7200,              # Cache TTL in seconds
  max_cache_size: 10000,        # Maximum cache entries
  enable_streaming: true,       # Enable streaming support
  quality_threshold: 0.8,       # Minimum quality for caching
  compression_enabled: true,    # Enable cache compression
  auto_enhance: true,          # Automatic enhancement
  fallback_to_text: true      # Fallback to text parser
}
```

## Error Handling

### Graceful Degradation
- Parser failures fall back to text parsing
- Enhancement failures preserve original content  
- Validation errors don't block processing
- Cache failures trigger fresh processing

### Error Logging
All errors are logged to `error_log` with:
- Error type and timestamp
- Detailed error message
- Context information
- Recovery actions taken

## Integration Points

### With Provider Agents
Receives processed responses from LLM provider agents and applies post-processing pipeline.

### With Client Applications
Delivers enhanced, validated responses in consistent format regardless of original provider.

### With Prompt Manager
Coordinates with prompt templates to apply format-specific enhancements.

## Future Extensions

### Planned Enhancements
- **ML-based Quality Scoring**: Advanced content analysis
- **Custom Enhancement Plugins**: User-defined enhancement rules
- **Multi-language Support**: Enhanced language detection and processing
- **Response Versioning**: Track response evolution over time