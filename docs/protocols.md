# RubberDuck Protocol System

This document describes the protocol-based extensibility system in RubberDuck, which provides a powerful mechanism for supporting different data types and extending functionality.

## Overview

RubberDuck uses Elixir protocols to provide polymorphic dispatch across different data types. This allows engines and plugins to work seamlessly with various data structures while maintaining type safety and performance.

## Core Protocols

### RubberDuck.Processor

The Processor protocol handles data transformation and normalization for different types.

```elixir
defprotocol RubberDuck.Processor do
  @spec process(t, opts()) :: {:ok, any()} | {:error, term()}
  def process(data, opts \\ [])
  
  @spec metadata(t) :: map()
  def metadata(data)
  
  @spec validate(t) :: :ok | {:error, term()}
  def validate(data)
  
  @spec normalize(t) :: t
  def normalize(data)
end
```

#### Available Implementations

1. **Map Processing**
   - Flatten nested maps
   - Transform keys (stringify, atomize)
   - Filter or exclude specific keys
   - Extract metadata about structure

2. **String Processing**
   - Text normalization
   - Case conversion
   - Splitting and formatting
   - Language detection

3. **List Processing**
   - Batch operations
   - Filtering and mapping
   - Chunking and sampling
   - Statistical analysis

### RubberDuck.Enhancer

The Enhancer protocol enriches data with additional context and derived information.

```elixir
defprotocol RubberDuck.Enhancer do
  @spec enhance(t, strategy()) :: {:ok, any()} | {:error, term()}
  def enhance(data, strategy)
  
  @spec with_context(t, context()) :: t
  def with_context(data, context)
  
  @spec with_metadata(t, metadata()) :: t
  def with_metadata(data, metadata)
  
  @spec derive(t, derivation() | [derivation()]) :: {:ok, map()} | {:error, term()}
  def derive(data, derivations)
end
```

#### Enhancement Strategies

- `:semantic` - Extract meaning and relationships
- `:structural` - Analyze structure and patterns
- `:temporal` - Identify time-based information
- `:relational` - Find connections and dependencies

## Usage Examples

### Processing Data

```elixir
# Process a map
{:ok, processed} = RubberDuck.Processor.process(
  %{user_name: "John", user_email: "john@example.com"},
  flatten: true,
  transform_keys: &String.replace(&1, "user_", "")
)
# Result: %{"name" => "John", "email" => "john@example.com"}

# Process a string
{:ok, lines} = RubberDuck.Processor.process(
  "Hello\nWorld",
  split: :lines,
  trim: true
)
# Result: ["Hello", "World"]

# Process a list
{:ok, processed} = RubberDuck.Processor.process(
  [1, 2, 3, 4, 5],
  filter: &(&1 > 2),
  map: &(&1 * 2)
)
# Result: [6, 8, 10]
```

### Enhancing Data

```elixir
# Enhance a map with semantic information
{:ok, enhanced} = RubberDuck.Enhancer.enhance(
  %{email: "user@example.com", created_at: "2024-01-01"},
  :semantic
)
# Result includes semantic type detection, field relationships

# Enhance a string with structural analysis
{:ok, enhanced} = RubberDuck.Enhancer.enhance(
  "The quick brown fox jumps over the lazy dog.",
  :structural
)
# Result includes sentence structure, word count, readability metrics

# Enhance a list with pattern detection
{:ok, enhanced} = RubberDuck.Enhancer.enhance(
  [1, 2, 3, 5, 8, 13, 21],
  :structural
)
# Result detects Fibonacci sequence pattern
```

### Deriving Information

```elixir
# Derive statistics from a list
{:ok, stats} = RubberDuck.Enhancer.derive(
  [1, 2, 3, 4, 5],
  :statistics
)
# Result: %{statistics: %{mean: 3.0, median: 3, std_dev: 1.58, ...}}

# Derive multiple insights
{:ok, insights} = RubberDuck.Enhancer.derive(
  "Machine learning is transforming software development.",
  [:summary, :patterns, :relationships]
)
# Result includes summary, linguistic patterns, and entity relationships
```

## Implementing Custom Types

To add protocol support for your custom types:

```elixir
defmodule MyApp.CustomData do
  defstruct [:id, :content, :metadata]
end

defimpl RubberDuck.Processor, for: MyApp.CustomData do
  def process(%MyApp.CustomData{} = data, opts) do
    # Custom processing logic
    {:ok, process_content(data.content, opts)}
  end
  
  def metadata(%MyApp.CustomData{} = data) do
    Map.merge(data.metadata, %{
      type: :custom_data,
      id: data.id,
      timestamp: DateTime.utc_now()
    })
  end
  
  def validate(%MyApp.CustomData{id: id}) when not is_nil(id) do
    :ok
  end
  def validate(_), do: {:error, :missing_id}
  
  def normalize(%MyApp.CustomData{} = data) do
    %{data | content: String.trim(data.content)}
  end
end
```

## Integration with Engines

Engines can leverage protocols to handle different input types:

```elixir
defmodule MyApp.SmartEngine do
  use RubberDuck.Engine
  
  def execute(input, state) do
    # Process input regardless of type
    with {:ok, processed} <- RubberDuck.Processor.process(input),
         {:ok, enhanced} <- RubberDuck.Enhancer.enhance(processed, :semantic) do
      
      # Engine logic works with normalized, enhanced data
      perform_analysis(enhanced, state)
    end
  end
end
```

## Performance Considerations

1. **Protocol Consolidation**: Enabled in production for better performance
2. **Lazy Processing**: Use Stream operations for large datasets
3. **Selective Enhancement**: Only apply needed enhancement strategies
4. **Caching**: Consider caching derived information for repeated operations

## Best Practices

1. **Type Safety**: Always validate input in protocol implementations
2. **Error Handling**: Return proper `{:ok, result}` or `{:error, reason}` tuples
3. **Documentation**: Document supported options for each implementation
4. **Testing**: Test protocol implementations with property-based tests
5. **Composability**: Design implementations to work well together

## Common Patterns

### Pipeline Processing

```elixir
data
|> RubberDuck.Processor.validate()
|> case do
  :ok -> data
  error -> raise "Invalid data: #{inspect(error)}"
end
|> RubberDuck.Processor.normalize()
|> RubberDuck.Processor.process(opts)
|> case do
  {:ok, processed} -> 
    RubberDuck.Enhancer.enhance(processed, :semantic)
  error -> 
    error
end
```

### Conditional Processing

```elixir
def smart_process(data) do
  metadata = RubberDuck.Processor.metadata(data)
  
  opts = case metadata.type do
    :string -> [trim: true, normalize: true]
    :list -> [unique: true, sort: true]
    :map -> [flatten: true, stringify_keys: true]
    _ -> []
  end
  
  RubberDuck.Processor.process(data, opts)
end
```

### Multi-stage Enhancement

```elixir
def deep_analysis(data) do
  with {:ok, semantic} <- RubberDuck.Enhancer.enhance(data, :semantic),
       {:ok, structural} <- RubberDuck.Enhancer.enhance(semantic, :structural),
       {:ok, insights} <- RubberDuck.Enhancer.derive(structural, [:summary, :patterns]) do
    
    {:ok, %{
      original: data,
      enhanced: structural,
      insights: insights
    }}
  end
end
```

## Troubleshooting

### Protocol Not Implemented

If you see `Protocol.UndefinedError`:
1. Ensure the protocol implementation is compiled
2. Check that protocol consolidation isn't preventing dynamic loading
3. Verify the data type matches the implementation

### Performance Issues

1. Profile with `:fprof` or `:eprof`
2. Consider implementing type-specific optimizations
3. Use streaming for large collections
4. Cache enhancement results when appropriate

### Type Conflicts

1. Use guards in implementations to handle edge cases
2. Provide fallback implementations for Any type if needed
3. Document type constraints clearly

## Future Extensions

The protocol system is designed to be extended with:
- Additional built-in type implementations
- Domain-specific protocols for specialized processing
- Protocol composition for complex transformations
- Automatic protocol derivation for structs