# MCP Tool Registry Documentation

## Overview

The MCP Tool Registry provides a comprehensive system for managing, discovering, and composing MCP tools within RubberDuck. It extends the basic MCP server functionality with advanced features like capability-based discovery, quality metrics, tool composition, and intelligent recommendations.

## Architecture

### Core Components

1. **Registry (`RubberDuck.MCP.Registry`)**
   - GenServer-based registry with ETS storage
   - Manages tool lifecycle and discovery
   - Handles metrics collection and aggregation
   - Provides composition and recommendation features

2. **Metadata (`RubberDuck.MCP.Registry.Metadata`)**
   - Extracts and manages tool metadata
   - Handles module introspection
   - Provides schema analysis

3. **Metrics (`RubberDuck.MCP.Registry.Metrics`)**
   - Tracks execution statistics
   - Calculates quality scores
   - Monitors performance trends

4. **Capabilities (`RubberDuck.MCP.Registry.Capabilities`)**
   - Defines capability taxonomy
   - Manages capability relationships
   - Enables capability-based discovery

5. **Composition (`RubberDuck.MCP.Registry.Composition`)**
   - Builds tool workflows
   - Supports sequential, parallel, and conditional execution
   - Analyzes and optimizes compositions

## Tool Metadata

Tools can declare metadata using module attributes:

```elixir
defmodule MyTool do
  use Hermes.Server.Component, type: :tool
  
  @moduledoc "Tool description"
  @category :analysis
  @tags [:code, :elixir, :ast]
  @capabilities [:code_analysis, :async]
  @version "1.0.0"
  @examples [
    %{
      description: "Analyze a module",
      params: %{module_name: "MyApp.Module"}
    }
  ]
  @performance %{
    avg_latency_ms: 100,
    max_concurrent: 10
  }
  @dependencies [SomeDependency]
  
  schema do
    field :module_name, {:required, :string}
    field :include_private, :boolean, default: false
  end
  
  @impl true
  def execute(params, frame) do
    # Tool implementation
  end
end
```

## API Reference

### Registration

```elixir
# Register a tool
Registry.register_tool(MyTool, 
  source: :internal,
  metadata: %{custom: "data"}
)

# Unregister a tool
Registry.unregister_tool(MyTool)
```

### Discovery

```elixir
# List all tools
{:ok, tools} = Registry.list_tools()

# Filter by category
{:ok, tools} = Registry.list_tools(category: :analysis)

# Filter by tags
{:ok, tools} = Registry.list_tools(tags: [:code, :elixir])

# Filter by capabilities
{:ok, tools} = Registry.list_tools(capabilities: [:async])

# Search tools
{:ok, results} = Registry.search_tools("code analysis")

# Discover by capability
{:ok, tools} = Registry.discover_by_capability(:code_analysis)
```

### Recommendations

```elixir
# Get tool recommendations based on context
context = %{
  tags: [:code, :testing],
  required_capabilities: [:async, :streaming],
  category: :analysis
}

{:ok, recommendations} = Registry.recommend_tools(context, limit: 5)
```

### Metrics

```elixir
# Record execution metrics
Registry.record_metric(MyTool, {:execution, :success, 150}, nil)
Registry.record_metric(MyTool, {:execution, :failure, :timeout}, nil)

# Get tool metrics
{:ok, metrics} = Registry.get_metrics(MyTool)

# Metrics include:
# - Total/successful/failed executions
# - Average/min/max latency
# - Success rate
# - Quality score
# - Error distribution
```

### Tool Composition

```elixir
# Sequential composition
comp = Composition.sequential("analyze_and_fix", [
  %{tool: CodeAnalyzer, params: %{file: "app.ex"}},
  %{tool: CodeFormatter, params: %{style: :default}},
  %{tool: CodeValidator, params: %{}}
])

# Parallel composition
comp = Composition.parallel("multi_analysis", [
  %{tool: SecurityScanner, params: %{}},
  %{tool: PerformanceAnalyzer, params: %{}},
  %{tool: DependencyChecker, params: %{}}
])

# Conditional composition
comp = Composition.conditional("smart_processor", [
  %{
    tool: ElixirAnalyzer,
    condition: fn %{lang: lang} -> lang == "elixir" end
  },
  %{
    tool: JavaScriptAnalyzer,
    condition: fn %{lang: lang} -> lang == "javascript" end
  },
  %{tool: GenericAnalyzer}  # Default fallback
])

# Execute composition
result = Composition.execute(comp, %{file: "app.ex", lang: "elixir"})
```

## Capabilities

The registry defines a comprehensive capability taxonomy:

- **Core Capabilities**
  - `text_processing` - Text transformation
  - `text_analysis` - Pattern analysis, sentiment
  - `code_analysis` - Source code analysis
  - `code_generation` - Code creation
  - `file_operations` - File I/O
  - `workflow_execution` - Workflow orchestration

- **Execution Capabilities**
  - `streaming` - Stream processing support
  - `async` - Asynchronous execution
  - `monitoring` - Operation monitoring
  - `validation` - Data validation

- **Integration Capabilities**
  - `conversation_management` - Context management
  - `memory_storage` - Persistent storage
  - `search` - Data search
  - `llm_integration` - LLM interaction

## Quality Scoring

Tools are scored based on:

1. **Success Rate (60%)** - Percentage of successful executions
2. **Latency Score (30%)** - Based on average response time
3. **Usage Score (10%)** - Based on execution frequency

Scores range from 0-100, with higher scores indicating better performance.

## Composition Analysis

The registry can analyze compositions for:

- **Parallelizable Steps** - Identifies independent operations
- **Redundant Tools** - Finds duplicate tool usage
- **Capability Gaps** - Missing required capabilities
- **Latency Estimation** - Predicts execution time

## Visualization

Generate Mermaid diagrams for compositions:

```elixir
diagram = Composition.to_diagram(comp)
# Outputs Mermaid graph syntax
```

## Configuration

Configure the registry in your application:

```elixir
config :rubber_duck, RubberDuck.MCP.Registry,
  discovery_interval: :timer.minutes(5),
  metrics_interval: :timer.minutes(1),
  external_sources: ["https://tools.example.com/registry"]
```

## Best Practices

1. **Tool Design**
   - Always include `@moduledoc` documentation
   - Define appropriate `@category` and `@tags`
   - List all `@capabilities` explicitly
   - Provide usage `@examples`

2. **Performance**
   - Set realistic `@performance` expectations
   - Monitor metrics regularly
   - Optimize tools with low quality scores

3. **Composition**
   - Validate compositions before execution
   - Use parallel execution when possible
   - Handle errors gracefully
   - Monitor composition performance

4. **Discovery**
   - Use specific filters for better results
   - Leverage capability-based discovery
   - Trust recommendation scores

## Integration with MCP Server

The registry automatically discovers and registers tools from the MCP server:

```elixir
# Tools in RubberDuck.MCP.Server.Tools.* are auto-discovered
# Additional tools can be registered manually
```

## Extending the Registry

### Custom Capabilities

Add new capabilities to `Capabilities` module:

```elixir
@capabilities Map.put(@capabilities, :my_capability, %{
  description: "My custom capability",
  input_types: [:custom],
  output_types: [:custom],
  composable_with: [:other_capability],
  requirements: []
})
```

### Custom Metrics

Extend metrics tracking:

```elixir
Registry.record_metric(MyTool, {:custom_metric, value}, nil)
```

### External Tool Sources

Implement external tool discovery by adding sources that return tool metadata in the expected format.

## Troubleshooting

### Common Issues

1. **Tool not found** - Ensure tool is registered and implements required callbacks
2. **Capability mismatch** - Verify tool capabilities are correctly declared
3. **Composition fails** - Check tool compatibility and data flow
4. **Low quality scores** - Review error logs and optimize tool implementation

### Debug Mode

Enable debug logging for the registry:

```elixir
config :logger, :console,
  level: :debug,
  metadata: [:mcp_registry]
```