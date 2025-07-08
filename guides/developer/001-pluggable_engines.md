# RubberDuck Pluggable Engine System: Comprehensive Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture-overview)
3. [Core Components](#core-components)
4. [Engine Definition with Spark DSL](#engine-definition-with-spark-dsl)
5. [Engine Behavior and Lifecycle](#engine-behavior-and-lifecycle)
6. [Plugin Architecture](#plugin-architecture)
7. [Protocol-Based Extensibility](#protocol-based-extensibility)
8. [Engine Management and Pooling](#engine-management-and-pooling)
9. [Creating Custom Engines](#creating-custom-engines)
10. [Built-in Engines](#built-in-engines)
11. [Best Practices and Patterns](#best-practices-and-patterns)
12. [Troubleshooting and Debugging](#troubleshooting-and-debugging)

## Introduction

The RubberDuck pluggable engine system is a sophisticated, extensible architecture that allows for modular addition of new AI-powered capabilities without modifying core code. Built on Elixir's OTP principles and leveraging the Spark DSL framework, it provides a declarative, type-safe way to define and manage engines that handle specific tasks like code completion, generation, and analysis.

### Key Features

- **Declarative Configuration**: Uses Spark DSL for clean, compile-time validated engine definitions
- **Hot-swappable Plugins**: Add new capabilities at runtime without system restart
- **Protocol-based Extensibility**: Leverage Elixir protocols for flexible data processing
- **Concurrent Processing**: Built-in pooling and supervision for fault-tolerant operation
- **LLM Enhancement Ready**: Designed to integrate with Chain-of-Thought, RAG, and self-correction techniques

## Architecture Overview

The engine system follows a layered architecture:

```
┌─────────────────────────────────────────────────┐
│            Application Layer                    │
│         (LiveView, CLI, API, etc.)             │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────┐
│           Engine Manager Layer                   │
│    (Orchestration, Pool Management, Registry)   │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────┐
│             Engine Layer                         │
│  (Individual Engines with Spark DSL Config)     │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────┐
│          Plugin & Protocol Layer                 │
│    (Extensibility Points, Data Processing)      │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────┐
│            LLM Service Layer                     │
│    (Providers, Memory, Context Building)         │
└─────────────────────────────────────────────────┘
```

## Core Components

### 1. RubberDuck.EngineSystem

The main module that provides the Spark DSL for engine configuration:

```elixir
defmodule MyApp.Engines do
  use RubberDuck.EngineSystem

  engine :completion do
    module RubberDuck.Engines.Completion
    priority 100
    timeout 30_000
    config max_suggestions: 5
  end
end
```

### 2. RubberDuck.Engine Behavior

Defines the contract all engines must implement:

```elixir
@callback init(config :: keyword()) :: {:ok, state} | {:error, term()}
@callback execute(input :: map(), state :: term()) :: {:ok, result} | {:error, term()}
@callback capabilities() :: [atom()]
```

### 3. RubberDuck.Engine.Manager

Orchestrates engine execution with intelligent routing:

```elixir
# Execute with automatic engine selection
{:ok, result} = RubberDuck.Engine.Manager.execute(:completion, %{
  prefix: "def hello",
  suffix: "end",
  language: "elixir"
})
```

### 4. RubberDuck.Engine.Supervisor

Manages engine lifecycle with fault tolerance:

- Automatic restart on failure
- Pool size management
- Health monitoring
- Graceful shutdown

## Engine Definition with Spark DSL

### Basic Engine Definition

```elixir
defmodule MyApp.Engines do
  use RubberDuck.EngineSystem

  engine :my_custom_engine do
    # Required: Module implementing Engine behavior
    module MyApp.Engines.CustomEngine
    
    # Optional: Higher priority engines are tried first
    priority 50
    
    # Optional: Execution timeout in milliseconds
    timeout 60_000
    
    # Optional: Engine-specific configuration
    config [
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 1000
    ]
    
    # Optional: Human-readable description
    description "Custom engine for specialized tasks"
  end
end
```

### Advanced Configuration

```elixir
engine :advanced_engine do
  module MyApp.Engines.AdvancedEngine
  
  # Pool configuration
  config [
    pool_size: 10,
    max_overflow: 5,
    strategy: :fifo
  ]
  
  # Capabilities declaration
  capabilities [:generate, :refactor, :explain]
  
  # LLM configuration (Phase 3)
  llm_config [
    provider: :openai,
    model: "gpt-4",
    fallback_provider: :anthropic,
    context_strategy: :rag
  ]
  
  # Telemetry configuration
  telemetry_enabled true
  telemetry_prefix [:rubber_duck, :engines, :advanced]
end
```

### Compile-time Validations

The Spark DSL provides compile-time validations:

```elixir
# This will fail at compile time
engine :invalid do
  # Missing required module
  priority -10  # Invalid priority (must be 0-100)
end
```

## Engine Behavior and Lifecycle

### Implementing the Engine Behavior

```elixir
defmodule MyApp.Engines.CustomEngine do
  @behaviour RubberDuck.Engine
  
  @impl true
  def init(config) do
    # Initialize engine state
    state = %{
      config: config,
      cache: :ets.new(:custom_cache, [:set, :private]),
      stats: %{requests: 0, successes: 0}
    }
    
    {:ok, state}
  end
  
  @impl true
  def execute(input, state) do
    # Validate input
    with {:ok, validated_input} <- validate_input(input),
         # Process request
         {:ok, result} <- process(validated_input, state),
         # Update statistics
         new_state = update_stats(state, :success) do
      {:ok, result, new_state}
    else
      {:error, reason} = error ->
        new_state = update_stats(state, :failure)
        {error, new_state}
    end
  end
  
  @impl true
  def capabilities do
    [:custom_task, :specialized_processing]
  end
  
  # Optional callbacks
  def handle_info(:cleanup, state) do
    # Periodic cleanup
    {:noreply, cleanup_cache(state)}
  end
  
  def terminate(_reason, state) do
    # Cleanup resources
    :ets.delete(state.cache)
    :ok
  end
end
```

### Engine Server Wrapper

For engines requiring GenServer functionality:

```elixir
defmodule MyApp.Engines.StatefulEngine do
  use RubberDuck.Engine.Server
  
  @impl true
  def init(config) do
    # Schedule periodic tasks
    Process.send_after(self(), :refresh, 60_000)
    
    {:ok, %{config: config, cache: %{}}}
  end
  
  @impl true
  def handle_execute(input, state) do
    # Implementation with state management
    result = process_with_state(input, state)
    {:ok, result, state}
  end
  
  @impl true
  def handle_info(:refresh, state) do
    # Refresh caches or update state
    Process.send_after(self(), :refresh, 60_000)
    {:noreply, refresh_state(state)}
  end
end
```

## Plugin Architecture

### Creating Plugins

```elixir
defmodule MyApp.Plugins.CodeFormatter do
  @behaviour RubberDuck.Plugin
  
  @impl true
  def name, do: :code_formatter
  
  @impl true
  def execute(input, opts) do
    case input do
      %{type: :code, language: lang, content: content} ->
        formatted = format_code(lang, content, opts)
        {:ok, %{formatted: formatted}}
        
      _ ->
        {:error, :unsupported_input}
    end
  end
  
  @impl true
  def supported_types do
    [:code, :snippet]
  end
end
```

### Plugin Registration and Discovery

```elixir
# Register plugin
RubberDuck.PluginManager.register(MyApp.Plugins.CodeFormatter)

# Discover and execute plugins
plugins = RubberDuck.PluginManager.find_by_type(:code)
results = RubberDuck.PluginManager.execute_all(plugins, input)
```

### Plugin Configuration DSL

```elixir
defmodule MyApp.PluginConfig do
  use RubberDuck.Plugin.DSL
  
  plugin :formatter do
    module MyApp.Plugins.CodeFormatter
    priority 10
    config [
      indent_size: 2,
      line_length: 100
    ]
  end
  
  plugin :linter do
    module MyApp.Plugins.Linter
    dependencies [:formatter]
    enabled_for [:elixir, :javascript]
  end
end
```

## Protocol-Based Extensibility

### Processor Protocol

The Processor protocol enables type-based processing:

```elixir
defimpl RubberDuck.Processor, for: Map do
  def process(data, opts) do
    data
    |> transform_keys(opts)
    |> validate_structure(opts)
    |> enhance_with_metadata(opts)
  end
  
  def validate(data, _opts) do
    required_keys = [:input, :context]
    has_keys = Enum.all?(required_keys, &Map.has_key?(data, &1))
    
    if has_keys, do: :ok, else: {:error, :missing_keys}
  end
end

# Custom struct implementation
defimpl RubberDuck.Processor, for: MyApp.CodeRequest do
  def process(%MyApp.CodeRequest{} = request, opts) do
    %{
      code: request.code,
      language: detect_language(request),
      context: build_context(request, opts)
    }
  end
end
```

### Enhancer Protocol

The Enhancer protocol provides enhancement strategies:

```elixir
defimpl RubberDuck.Enhancer, for: Map do
  def enhance(data, :context) do
    Map.update(data, :context, %{}, fn ctx ->
      ctx
      |> add_file_context()
      |> add_project_patterns()
      |> add_user_preferences()
    end)
  end
  
  def enhance(data, :validation) do
    Map.put(data, :validations, run_validations(data))
  end
  
  def enhancement_types(_), do: [:context, :validation, :optimization]
end
```

## Engine Management and Pooling

### Pool Configuration

```elixir
# In engine definition
engine :pooled_engine do
  module MyApp.Engines.PooledEngine
  
  pool_config [
    size: 10,              # Number of workers
    max_overflow: 5,       # Additional workers under load
    strategy: :lifo,       # :fifo or :lifo
    checkout_timeout: 5000 # Max wait time for worker
  ]
end
```

### Dynamic Pool Management

```elixir
# Adjust pool size at runtime
RubberDuck.Engine.Pool.resize(:pooled_engine, 20)

# Monitor pool metrics
stats = RubberDuck.Engine.Pool.stats(:pooled_engine)
# => %{size: 20, available: 15, overflow: 2, waiting: 0}
```

### Health Monitoring

```elixir
defmodule MyApp.EngineHealth do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    schedule_health_check()
    {:ok, %{}}
  end
  
  def handle_info(:health_check, state) do
    engines = RubberDuck.Engine.Registry.all()
    
    health_status = Enum.map(engines, fn engine ->
      {engine.name, check_engine_health(engine)}
    end)
    
    broadcast_health_status(health_status)
    schedule_health_check()
    
    {:noreply, Map.put(state, :last_check, health_status)}
  end
end
```

## Creating Custom Engines

### Step-by-Step Guide

1. **Define Engine Module**

```elixir
defmodule MyApp.Engines.DocumentAnalyzer do
  @behaviour RubberDuck.Engine
  
  defstruct [:nlp_model, :cache, :stats]
  
  @impl true
  def init(config) do
    {:ok, %__MODULE__{
      nlp_model: load_model(config[:model_path]),
      cache: init_cache(),
      stats: %{analyzed: 0}
    }}
  end
  
  @impl true
  def execute(%{document: doc} = input, state) do
    with {:ok, tokens} <- tokenize(doc, state.nlp_model),
         {:ok, analysis} <- analyze_document(tokens, state),
         {:ok, summary} <- generate_summary(analysis, state) do
      
      result = %{
        summary: summary,
        sentiment: analysis.sentiment,
        key_topics: analysis.topics,
        readability_score: analysis.readability
      }
      
      new_state = update_in(state.stats.analyzed, &(&1 + 1))
      {:ok, result, new_state}
    end
  end
  
  @impl true
  def capabilities do
    [:document_analysis, :summarization, :sentiment_analysis]
  end
end
```

2. **Register in Engine System**

```elixir
defmodule MyApp.Engines do
  use RubberDuck.EngineSystem
  
  engine :document_analyzer do
    module MyApp.Engines.DocumentAnalyzer
    priority 80
    timeout 120_000  # 2 minutes for large documents
    
    config [
      model_path: "/models/nlp/bert-base",
      cache_ttl: 3600,
      max_document_size: 1_000_000
    ]
  end
end
```

3. **Add Plugin Support**

```elixir
defmodule MyApp.Plugins.LanguageDetector do
  @behaviour RubberDuck.Plugin
  
  def name, do: :language_detector
  
  def execute(%{text: text}, _opts) do
    language = detect_language(text)
    {:ok, %{detected_language: language, confidence: 0.95}}
  end
  
  def supported_types, do: [:document, :text]
end
```

4. **Integrate with Engine**

```elixir
def execute(input, state) do
  # Use plugin for language detection
  {:ok, lang_result} = RubberDuck.PluginManager.execute(
    :language_detector, 
    %{text: input.document}
  )
  
  enhanced_input = Map.put(input, :language, lang_result.detected_language)
  
  # Continue with analysis...
  process_with_language(enhanced_input, state)
end
```

## Built-in Engines

### Code Completion Engine

The completion engine uses Fill-in-the-Middle (FIM) context strategy:

```elixir
# Usage
{:ok, completions} = RubberDuck.Engine.Manager.execute(:completion, %{
  prefix: "def calculate_total(items) do\n  items |> Enum.",
  suffix: "\nend",
  language: "elixir",
  max_suggestions: 3
})

# Returns
%{
  completions: [
    %{text: "sum(&(&1.price))", score: 0.95},
    %{text: "reduce(0, fn item, acc -> acc + item.price end)", score: 0.88},
    %{text: "map(&(&1.price)) |> Enum.sum()", score: 0.82}
  ],
  metadata: %{
    model: "gpt-4",
    context_tokens: 150,
    generation_time_ms: 234
  }
}
```

### Code Generation Engine

The generation engine uses RAG for context-aware generation:

```elixir
# Usage
{:ok, result} = RubberDuck.Engine.Manager.execute(:generation, %{
  prompt: "Create a GenServer that manages a shopping cart with add, remove, and checkout functions",
  language: "elixir",
  context_files: ["lib/shop/product.ex", "lib/shop/order.ex"],
  style_preferences: %{
    testing: true,
    documentation: true,
    type_specs: true
  }
})

# Returns
%{
  code: "defmodule Shop.CartServer do\n  @moduledoc \"\"\"...",
  imports_detected: ["Shop.Product", "Shop.Order"],
  explanation: "This GenServer implements...",
  test_code: "defmodule Shop.CartServerTest do...",
  similar_patterns: [
    %{file: "lib/shop/inventory_server.ex", similarity: 0.87}
  ]
}
```

## Best Practices and Patterns

### 1. Engine Design Principles

```elixir
# Good: Single Responsibility
defmodule Engines.CodeFormatter do
  def execute(%{code: code, language: lang}, state) do
    # Only handles formatting
    format_code(code, lang, state.config)
  end
end

# Bad: Multiple Responsibilities
defmodule Engines.DoEverything do
  def execute(input, state) do
    # Formats, analyzes, and generates - too much!
  end
end
```

### 2. Error Handling Patterns

```elixir
defmodule MyEngine do
  def execute(input, state) do
    input
    |> validate_input()
    |> process_safely(state)
    |> handle_result()
  rescue
    e in [ArgumentError, RuntimeError] ->
      Logger.error("Engine error: #{inspect(e)}")
      {:error, :processing_failed}
  end
  
  defp process_safely(input, state) do
    Task.async(fn -> do_process(input, state) end)
    |> Task.await(state.config[:timeout] || 5000)
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end
end
```

### 3. Caching Strategies

```elixir
defmodule Engines.CachedEngine do
  def execute(input, state) do
    cache_key = generate_cache_key(input)
    
    case get_from_cache(cache_key, state) do
      {:ok, cached_result} ->
        {:ok, cached_result, state}
        
      :miss ->
        case process(input, state) do
          {:ok, result} = success ->
            put_in_cache(cache_key, result, state)
            success
            
          error ->
            error
        end
    end
  end
  
  defp generate_cache_key(input) do
    input
    |> Map.take([:code, :language, :options])
    |> :erlang.phash2()
  end
end
```

### 4. Telemetry Integration

```elixir
defmodule Engines.InstrumentedEngine do
  def execute(input, state) do
    start_time = System.monotonic_time()
    metadata = %{engine: :instrumented, input_size: byte_size(input.code)}
    
    :telemetry.span(
      [:rubber_duck, :engine, :execute],
      metadata,
      fn ->
        result = do_execute(input, state)
        {result, Map.put(metadata, :success, match?({:ok, _}, result))}
      end
    )
  end
end
```

### 5. Testing Engines

```elixir
defmodule MyEngineTest do
  use ExUnit.Case
  
  setup do
    # Start engine in test mode
    {:ok, engine} = MyEngine.start_link(test_mode: true)
    
    on_exit(fn ->
      GenServer.stop(engine)
    end)
    
    {:ok, engine: engine}
  end
  
  describe "execute/2" do
    test "processes valid input", %{engine: engine} do
      input = %{code: "def hello, do: :world", language: "elixir"}
      
      assert {:ok, result} = GenServer.call(engine, {:execute, input})
      assert result.formatted_code == "def hello, do: :world"
    end
    
    test "handles timeout gracefully", %{engine: engine} do
      input = %{code: "sleep(10000)", language: "python"}
      
      assert {:error, :timeout} = GenServer.call(engine, {:execute, input}, 1000)
    end
  end
end
```

## Troubleshooting and Debugging

### Common Issues

1. **Engine Not Found**
```elixir
# Check registration
RubberDuck.EngineSystem.get_engine(:my_engine)
# => nil means not registered

# List all engines
RubberDuck.EngineSystem.list_engines()
```

2. **Pool Exhaustion**
```elixir
# Monitor pool usage
:observer.start()
# Navigate to Applications > rubber_duck > Processes

# Or programmatically
RubberDuck.Engine.Pool.stats(:busy_engine)
# => %{waiting: 10, available: 0, overflow: 5}
```

3. **Memory Leaks**
```elixir
# Add memory monitoring to engine
def handle_info(:check_memory, state) do
  memory = :erlang.process_info(self(), :memory)
  if memory > @max_memory do
    Logger.warn("Engine using too much memory: #{memory}")
    {:noreply, cleanup_state(state)}
  else
    {:noreply, state}
  end
end
```

### Debug Mode

```elixir
# Enable debug mode for verbose logging
config :rubber_duck, :engines,
  debug: true,
  log_level: :debug

# Or at runtime
RubberDuck.EngineSystem.enable_debug(:my_engine)
```

### Performance Profiling

```elixir
defmodule Engines.ProfiledEngine do
  def execute(input, state) do
    :fprof.trace([:start])
    
    result = do_execute(input, state)
    
    :fprof.trace([:stop])
    :fprof.profile()
    :fprof.analyse(dest: 'engine_profile.txt')
    
    result
  end
end
```

## Conclusion

The RubberDuck pluggable engine system provides a robust, extensible foundation for building AI-powered coding assistants. By leveraging Elixir's strengths in concurrency, fault tolerance, and metaprogramming, it enables:

- Easy addition of new capabilities through plugins
- Type-safe configuration with compile-time validation
- Scalable processing with automatic pooling
- Flexible data handling through protocols
- Production-ready monitoring and debugging

Whether you're building simple code formatters or complex AI-driven analysis engines, this system provides the tools and patterns needed for success. The architecture ensures that as LLM technologies evolve, new techniques can be seamlessly integrated without disrupting existing functionality.
