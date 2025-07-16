# MCP System Integration Documentation

## Overview

This document describes the comprehensive integration between the Model Context Protocol (MCP) and RubberDuck's existing systems. The integration enhances rather than replaces current functionality, creating a unified platform where MCP tools and resources work seamlessly with memory, workflows, engines, and agents.

## Architecture

### Integration Strategy

The MCP system integration follows a layered approach:

1. **Provider Layer**: MCP as an LLM provider alongside existing providers
2. **Resource Layer**: System components exposed as MCP resources
3. **Tool Layer**: System functions wrapped as MCP tools
4. **Context Layer**: MCP-aware context building and prompt enhancement
5. **Agent Layer**: Agents enhanced with MCP capabilities

### Key Components

```
┌─────────────────────────────────────────────────────┐
│                   MCP Integration                    │
├─────────────────────────────────────────────────────┤
│  LLM Provider │  Memory  │  Workflows │  Engines     │
│  Integration  │  System  │  System    │  System      │
├─────────────────────────────────────────────────────┤
│  Context      │  Agent   │  CLI       │  LiveView    │
│  Building     │  System  │  Commands  │  Browser     │
├─────────────────────────────────────────────────────┤
│           Core MCP Infrastructure                    │
│  Registry │ Client │ Server │ Composition Engine     │
└─────────────────────────────────────────────────────┘
```

## LLM Provider Integration

### MCP Provider Implementation

The `RubberDuck.LLM.Providers.MCP` module implements the standard LLM provider interface:

```elixir
# Configuration
config = %{
  name: :mcp_claude,
  adapter: RubberDuck.LLM.Providers.MCP,
  mcp_client: :claude_desktop,
  models: ["claude-3-5-sonnet", "claude-3-haiku"],
  mcp_config: %{
    transport: {:stdio, command: "claude-desktop", args: []},
    capabilities: [:tools, :resources, :prompts]
  }
}

# Usage
RubberDuck.LLM.Service.register_provider(config)
```

### Features

- **Automatic Tool Discovery**: Discovers available MCP tools and exposes them to LLM
- **Resource Integration**: Includes MCP resources in conversation context
- **Streaming Support**: Full streaming capability with progress updates
- **Error Handling**: Comprehensive error handling and fallback mechanisms
- **Metrics Integration**: Tool usage metrics tracked in the registry

## Memory System Integration

### Memory as MCP Resources

Memory stores are exposed as MCP resources with URI pattern `memory://store_id`:

```elixir
# List memory stores
GET memory://

# Access specific store
GET memory://conversations?operation=list&limit=10
GET memory://conversations?operation=get&key=user_123
GET memory://conversations?operation=search&query=elixir
```

### Memory Tools

Three core memory tools are available:

1. **MemoryPut**: Store data with TTL and tagging
2. **MemoryDelete**: Remove data from memory
3. **MemoryBatch**: Batch operations for efficiency

```elixir
# Store data
{:ok, result} = RubberDuck.MCP.Registry.execute_tool("memory_put", %{
  store_id: "conversations",
  key: "user_123",
  value: %{name: "John", role: "developer"},
  ttl: 3600,
  tags: ["user", "active"]
})

# Batch operations
{:ok, result} = RubberDuck.MCP.Registry.execute_tool("memory_batch", %{
  store_id: "conversations",
  operations: [
    %{operation: "get", key: "user_123"},
    %{operation: "put", key: "user_124", value: %{name: "Jane"}}
  ]
})
```

## Workflow System Integration

### MCP Workflow Steps

Four new Reactor step types enable MCP integration in workflows:

1. **MCPToolStep**: Execute MCP tools
2. **MCPResourceStep**: Read MCP resources
3. **MCPCompositionStep**: Execute tool compositions
4. **MCPStreamingStep**: Handle streaming operations

```elixir
# Workflow definition
defmodule MyWorkflow do
  use Reactor
  
  step :analyze_code, MCPToolStep do
    argument :tool_name, "code_analyzer"
    argument :params, %{file_path: input(:file_path)}
  end
  
  step :get_context, MCPResourceStep do
    argument :resource_uri, "memory://context"
    argument :params, %{key: "current_session"}
  end
  
  step :execute_composition, MCPCompositionStep do
    argument :composition_id, "analyze_and_fix"
    argument :input, result(:analyze_code)
  end
end
```

### Workflow Compensation

MCP steps support compensation for error recovery:

```elixir
step :risky_operation, MCPToolStep do
  argument :tool_name, "risky_tool"
  argument :params, %{data: input(:data)}
  
  # Cleanup on failure
  option :cleanup, %{action: "rollback", data: input(:data)}
end
```

## Engine System Integration

### Engines as MCP Resources

Engines are exposed as resources with URI pattern `engines://engine_id`:

```elixir
# List engines
GET engines://

# Get engine details
GET engines://nlp_processor?operation=get&include_stats=true

# Get engine status
GET engines://nlp_processor?operation=status
```

### Engine Tools

Three engine tools provide execution capabilities:

1. **EngineExecute**: Execute engines sync/async
2. **EngineGetResult**: Retrieve async results
3. **EngineCancel**: Cancel running executions

```elixir
# Synchronous execution
{:ok, result} = RubberDuck.MCP.Registry.execute_tool("engine_execute", %{
  engine_id: "nlp_processor",
  input: %{text: "Analyze this text"},
  async: false,
  timeout: 30_000
})

# Asynchronous execution
{:ok, result} = RubberDuck.MCP.Registry.execute_tool("engine_execute", %{
  engine_id: "nlp_processor",
  input: %{text: "Long processing task"},
  async: true
})

# Get async result
{:ok, result} = RubberDuck.MCP.Registry.execute_tool("engine_get_result", %{
  execution_id: result.execution_id,
  wait: true,
  timeout: 5_000
})
```

## Context Building Integration

### Enhanced Context

The context building system now includes MCP information:

```elixir
# Basic context enhancement
base_context = %{user: "developer", task: "code_analysis"}
enhanced_context = RubberDuck.MCP.Integration.Context.enhance_context(base_context, [
  include_tools: true,
  include_resources: true,
  include_clients: true,
  include_executions: true
])

# Result includes MCP data
enhanced_context.mcp.tools        # Available tools
enhanced_context.mcp.resources    # Available resources
enhanced_context.mcp.clients      # Connected clients
enhanced_context.mcp.recent_executions  # Recent activity
```

### MCP-Aware Prompts

Prompts are automatically enhanced with MCP information:

```elixir
base_prompt = "Help me analyze this code"
context = %{mcp: %{tools: [...], resources: [...]}}

mcp_prompt = RubberDuck.MCP.Integration.Context.create_mcp_prompt(
  base_prompt, 
  context,
  include_tool_info: true,
  include_resource_info: true,
  include_composition_suggestions: true
)
```

The enhanced prompt includes:
- Available tools and their capabilities
- Accessible resources
- Recent execution context
- Tool composition suggestions

## Agent System Integration

### MCP-Enhanced Agents

Agents are enhanced with four MCP capabilities:

1. **Tool Discovery**: Automatic discovery of available tools
2. **Tool Learning**: Learn from usage patterns
3. **Composition**: Create and execute tool compositions
4. **Context Awareness**: MCP-aware context handling

```elixir
# Enhance agent with MCP capabilities
base_agent = %{
  id: "code_assistant",
  name: "Code Assistant",
  capabilities: %{},
  preferences: %{}
}

enhanced_agent = RubberDuck.MCP.Integration.Agents.enhance_agent(base_agent, [
  auto_discover: true,
  learn_from_usage: true,
  can_create_compositions: true,
  context_aware: true
])
```

### Agent Tool Discovery

Agents can discover tools based on their capabilities and preferences:

```elixir
# Discover tools for agent
discovery = RubberDuck.MCP.Integration.Agents.discover_tools_for_agent(
  agent,
  category: :code_analysis,
  min_quality_score: 80
)

# Results include
discovery.available_tools     # Filtered available tools
discovery.recommended_tools   # Personalized recommendations
```

### Personalized Recommendations

Agents receive personalized tool recommendations based on:
- Usage history and success rates
- Agent capabilities and preferences
- Current context and task
- Tool quality metrics

```elixir
{:ok, recommendations} = RubberDuck.MCP.Integration.Agents.get_personalized_recommendations(
  agent,
  %{current_task: "code_review", language: "elixir"},
  limit: 5
)

# Each recommendation includes
recommendation.agent_score           # Personalized score
recommendation.recommendation_reason # Why it's recommended
```

### Tool Usage Learning

Agents learn from tool usage patterns:

```elixir
learning_results = RubberDuck.MCP.Integration.Agents.learn_from_usage(agent)

# Results include
learning_results.usage_patterns          # Discovered patterns
learning_results.updated_preferences     # Updated preferences
learning_results.updated_recommendations # New recommendations
```

## CLI Integration

### MCP Commands

The CLI includes comprehensive MCP commands:

```bash
# List tools
rubber_duck mcp tools list
rubber_duck mcp tools list --format json

# Show tool details
rubber_duck mcp tools show code_analyzer
rubber_duck mcp tools show code_analyzer --format json

# Execute tool
rubber_duck mcp tools execute code_analyzer '{"file": "app.ex"}'

# Search tools
rubber_duck mcp tools search "elixir analysis"

# Show metrics
rubber_duck mcp metrics
rubber_duck mcp metrics code_analyzer

# List clients
rubber_duck mcp clients list

# Show system status
rubber_duck mcp status

# Composition commands
rubber_duck mcp compositions list
rubber_duck mcp compositions execute comp_123 '{"input": "data"}'

# Suggest compositions
rubber_duck mcp suggest "analyze and fix elixir code"
```

## Configuration

### Application Configuration

```elixir
# Enable MCP integration
config :rubber_duck,
  mcp_integration_enabled: true,
  mcp_server_enabled: true,
  mcp_tool_registry_enabled: true

# MCP provider configuration
config :rubber_duck, :llm_providers, [
  %{
    name: :mcp_claude,
    adapter: RubberDuck.LLM.Providers.MCP,
    priority: 1,
    mcp_client: :claude_desktop,
    models: ["claude-3-5-sonnet"],
    mcp_config: %{
      transport: {:stdio, command: "claude-desktop", args: []},
      capabilities: [:tools, :resources, :prompts]
    }
  }
]

# Registry configuration
config :rubber_duck, RubberDuck.MCP.Registry,
  discovery_interval: :timer.minutes(5),
  metrics_interval: :timer.minutes(1),
  external_sources: []
```

### Memory Integration Configuration

```elixir
config :rubber_duck, :mcp_memory_integration,
  expose_all_stores: true,
  default_permissions: :read_write,
  max_batch_size: 100
```

### Agent Integration Configuration

```elixir
config :rubber_duck, :mcp_agent_integration,
  auto_enhance_agents: true,
  learning_enabled: true,
  max_tool_recommendations: 10
```

## Best Practices

### LLM Provider Integration

1. **Fallback Strategy**: Always configure MCP providers with fallback to direct providers
2. **Model Mapping**: Map models to appropriate MCP clients
3. **Timeout Configuration**: Set appropriate timeouts for MCP operations
4. **Error Handling**: Implement comprehensive error handling and retry logic

### Memory Integration

1. **Access Control**: Implement proper access controls for memory stores
2. **Data Validation**: Validate data before storing in memory
3. **TTL Management**: Use appropriate TTL values for temporary data
4. **Batch Operations**: Use batch operations for multiple memory operations

### Workflow Integration

1. **Compensation**: Always implement compensation for MCP steps
2. **Timeout Handling**: Set appropriate timeouts for tool executions
3. **Error Recovery**: Implement proper error recovery strategies
4. **Resource Management**: Clean up resources after workflow completion

### Agent Integration

1. **Permission Management**: Implement proper tool permissions for agents
2. **Learning Limits**: Set limits on learning data to prevent memory issues
3. **Tool Filtering**: Filter tools based on agent capabilities
4. **Context Management**: Manage context size to prevent memory issues

## Monitoring and Debugging

### Metrics Collection

The integration collects comprehensive metrics:

```elixir
# Tool execution metrics
Registry.get_metrics(tool_name)

# Provider performance metrics
RubberDuck.LLM.Service.get_provider_metrics(:mcp_claude)

# Agent learning metrics
Agents.get_learning_metrics(agent)
```

### Debug Logging

Enable debug logging for troubleshooting:

```elixir
config :logger, :console,
  level: :debug,
  metadata: [:mcp_integration, :mcp_provider, :mcp_agent]
```

### Health Checks

System health checks include MCP integration:

```elixir
# Overall system health
{:ok, status} = RubberDuck.Health.check_system()

# MCP-specific health
{:ok, mcp_status} = RubberDuck.MCP.Integration.health_check()
```

## Migration Guide

### From Direct Provider Usage

1. **Add MCP Configuration**: Add MCP provider configuration
2. **Update Model Mappings**: Map models to MCP clients
3. **Test Fallback**: Ensure fallback to direct providers works
4. **Monitor Performance**: Monitor performance impact

### From Manual Tool Management

1. **Register Tools**: Register existing tools with MCP registry
2. **Add Metadata**: Add metadata attributes to tools
3. **Update Workflows**: Update workflows to use MCP steps
4. **Test Integration**: Test end-to-end integration

## Troubleshooting

### Common Issues

1. **Client Connection Failures**
   - Check transport configuration
   - Verify client executable is available
   - Check network connectivity

2. **Tool Execution Failures**
   - Verify tool registration
   - Check parameter validation
   - Review error logs

3. **Memory Integration Issues**
   - Verify memory store availability
   - Check access permissions
   - Review memory configuration

4. **Agent Learning Problems**
   - Check learning data size
   - Verify tool permissions
   - Review learning configuration

### Performance Optimization

1. **Connection Pooling**: Use connection pooling for MCP clients
2. **Caching**: Implement caching for frequently accessed resources
3. **Batch Operations**: Use batch operations where possible
4. **Async Processing**: Use async processing for long-running operations

## Future Enhancements

1. **Advanced Composition**: More sophisticated composition patterns
2. **ML-Based Recommendations**: Machine learning for tool recommendations
3. **Distributed Registry**: Multi-node tool registry
4. **Visual Composition**: GUI for building tool compositions
5. **Real-time Collaboration**: Real-time collaborative tool usage
6. **External Tool Markets**: Integration with external tool marketplaces