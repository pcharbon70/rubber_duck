# Action-Based Architecture Guide

RubberDuck now uses a modern action-based architecture powered by the Jido framework. This document explains how to work with the new system.

## Overview

The new architecture replaces traditional GenServer calls with composable actions that provide better modularity, observability, and maintainability.

## Agent Structure

### Before (GenServer)
```elixir
defmodule MyAgent do
  use GenServer
  
  def handle_call({:my_operation, params}, _from, state) do
    # Implementation here
    {:reply, result, new_state}
  end
end
```

### After (Action-Based)
```elixir
defmodule MyAgent do
  use RubberDuck.Agents.BaseAgent,
    actions: [
      MyOperationAction,
      AnotherOperationAction
    ]
end

defmodule MyOperationAction do
  use Jido.Action,
    name: "my_operation",
    description: "Performs my operation",
    schema: [
      param1: [type: :string, required: true],
      param2: [type: :integer, default: 0]
    ]
  
  @impl true
  def run(params, %{agent: agent}) do
    # Implementation here
    {:ok, result, %{agent: updated_agent}}
  end
end
```

## Using Actions

### Running Actions
```elixir
# Start an agent
{:ok, agent} = MyAgent.start_link([])

# Run an action
{:ok, result} = MyAgent.cmd(agent, MyOperationAction, %{param1: "value"})

# Or use the action name
{:ok, result} = MyAgent.cmd(agent, "my_operation", %{param1: "value"})
```

### Action Results
Actions return structured results:
```elixir
{:ok, result, context} = MyAgent.cmd(agent, MyAction, params)
{:error, reason} = MyAgent.cmd(agent, MyAction, invalid_params)
```

## Available Agents and Actions

### Core Agents
- **PromptManagerAgent** - Template and prompt management
- **ConversationRouterAgent** - Conversation routing and classification
- **LLMRouterAgent** - LLM provider routing
- **ResponseProcessorAgent** - Response formatting and enhancement
- **ProviderAgent** (Anthropic, OpenAI, Local) - LLM provider interfaces

### New Jido Agents
- **AnalysisAgent** - Code analysis and review
- **CodeAnalysisAgent** - Comprehensive code analysis
- **MetricsAgent** - System metrics collection
- **RestartTrackerAgent** - Agent restart tracking

### Action Categories

#### Prompt Management (8 actions)
- `build_prompt` - Build prompts from templates
- `create_template` - Create new templates
- `list_templates` - List available templates
- `validate_template` - Validate template syntax
- And 4 more...

#### Provider Actions (20 actions)
- Anthropic: 6 actions (requests, streaming, etc.)
- OpenAI: 7 actions (completion, chat, etc.)
- Local: 7 actions (model loading, unloading, etc.)

#### Analysis Actions (12 actions)
- `analyze_code` - Comprehensive code analysis
- `complexity_analysis` - Code complexity metrics
- `security_review` - Security vulnerability scanning
- `style_check` - Code style validation
- And 8 more...

#### Conversation Actions (15 actions)
- Enhancement: 5 actions for conversation improvements
- General: 5 actions for basic conversation handling
- Planning: 5 actions for planning workflows

## Benefits

### 1. **Modularity**
- Actions are reusable across agents
- Clear separation of concerns
- Easy to test individual actions

### 2. **Observability**
- Built-in telemetry for all actions
- Structured logging and metrics
- Signal-based event system

### 3. **Type Safety**
- Schema validation for action parameters
- Structured return types
- Better error handling

### 4. **Performance**
- Reduced memory footprint
- Better resource utilization
- Optimized execution paths

## Testing Actions

```elixir
defmodule MyActionTest do
  use ExUnit.Case, async: true
  
  test "my action works correctly" do
    # Setup
    agent = create_test_agent()
    params = %{param1: "test_value"}
    
    # Execute
    {:ok, result} = MyAgent.cmd(agent, MyAction, params)
    
    # Assert
    assert result.success == true
    assert result.data == expected_data
  end
end
```

## Migration Notes

If you have existing code that calls agents directly:

### Old Way
```elixir
GenServer.call(agent_pid, {:build_prompt, template_id, context})
```

### New Way
```elixir
MyAgent.cmd(agent_pid, "build_prompt", %{
  template_id: template_id, 
  context: context
})
```

## Signal System

The new architecture includes a powerful signal system for inter-agent communication:

```elixir
# Emit a signal
signal = %RubberDuck.Signal{
  type: "analysis.complete",
  data: %{result: analysis_result},
  source: agent_id
}

RubberDuck.SignalBus.emit(signal)
```

Signals are automatically routed to appropriate actions based on configured mappings.

## Best Practices

1. **Keep actions focused** - Each action should have a single responsibility
2. **Use schemas** - Always define parameter schemas for validation
3. **Handle errors gracefully** - Return structured error responses
4. **Test thoroughly** - Test actions in isolation and integration
5. **Use signals for communication** - Prefer signals over direct agent calls

## Getting Help

- Check the migration summary in `docs/genserver_to_actions_migration_summary.md`
- Look at existing actions for examples
- Refer to the Jido documentation for advanced features

The new action-based architecture provides a solid foundation for building scalable, maintainable AI agent systems.