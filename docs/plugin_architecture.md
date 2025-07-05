# Plugin Architecture Documentation

## Overview

The RubberDuck Plugin System provides a flexible, extensible architecture for adding new capabilities without modifying core code. Plugins run in isolation, communicate through a message bus, and can be configured declaratively using a Spark-based DSL.

## Architecture Components

### 1. Plugin Behavior (`RubberDuck.Plugin`)

All plugins must implement this behavior, which defines the standard interface:

- `name/0` - Returns the plugin's unique identifier
- `version/0` - Returns the plugin version
- `description/0` - Human-readable description
- `supported_types/0` - List of data types the plugin can handle
- `dependencies/0` - Other plugins this plugin depends on
- `init/1` - Initialize plugin with configuration
- `execute/2` - Main plugin logic
- `terminate/2` - Cleanup on shutdown

Optional callbacks:
- `validate_input/1` - Validate input before processing
- `handle_config_change/2` - Handle runtime configuration updates

### 2. Plugin Manager (`RubberDuck.PluginManager`)

Central management service for plugins:
- Registration and unregistration
- Lifecycle management (start/stop)
- Plugin discovery and queries
- Dependency tracking
- Execution coordination

### 3. Plugin System DSL (`RubberDuck.PluginSystem`)

Declarative configuration using Spark DSL:

```elixir
defmodule MyApp.Plugins do
  use RubberDuck.PluginSystem
  
  plugins do
    plugin :text_enhancer do
      module TextEnhancerPlugin
      config [
        prefix: ">>",
        suffix: "<<"
      ]
      enabled true
      priority 90
      dependencies []
      auto_start true
    end
  end
end
```

### 4. Plugin Runner (`RubberDuck.Plugin.Runner`)

Provides isolated execution environment:
- Each plugin runs in its own supervised process
- Crash isolation prevents affecting other plugins
- Task-based execution with monitoring
- Statistics tracking
- Runtime configuration updates

### 5. Plugin Supervisor (`RubberDuck.Plugin.Supervisor`)

DynamicSupervisor for plugin processes:
- Fault tolerance with restart strategies
- Process registry integration
- Runtime plugin addition/removal

### 6. Message Bus (`RubberDuck.Plugin.MessageBus`)

Inter-plugin communication system:
- Publish/subscribe messaging
- Request/response patterns
- Topic-based routing
- Automatic cleanup on process termination

## Creating a Plugin

### 1. Implement the Plugin Behavior

```elixir
defmodule MyPlugin do
  @behaviour RubberDuck.Plugin
  
  @impl true
  def name, do: :my_plugin
  
  @impl true
  def version, do: "1.0.0"
  
  @impl true
  def description, do: "Does something useful"
  
  @impl true
  def supported_types, do: [:text, :json]
  
  @impl true
  def dependencies, do: [:other_plugin]
  
  @impl true
  def init(config) do
    # Initialize state from config
    {:ok, %{config: config}}
  end
  
  @impl true
  def execute(input, state) do
    # Process input
    result = transform(input)
    {:ok, result, state}
  end
  
  @impl true
  def terminate(_reason, _state) do
    # Cleanup if needed
    :ok
  end
end
```

### 2. Configure the Plugin

Add to your plugin configuration module:

```elixir
plugin :my_plugin do
  module MyPlugin
  config [
    option1: "value1",
    option2: 42
  ]
  enabled true
  priority 75
  dependencies [:other_plugin]
end
```

### 3. Load and Use

```elixir
# Load all plugins from configuration
RubberDuck.PluginSystem.load_plugins(MyApp.Plugins)

# Or manually register
PluginManager.register_plugin(MyPlugin, config)
PluginManager.start_plugin(:my_plugin)

# Execute plugin
{:ok, result} = PluginManager.execute(:my_plugin, input)
```

## Plugin Communication

### Publish/Subscribe

```elixir
# Subscribe to topic
MessageBus.subscribe(:data_processed)

# Publish message
MessageBus.publish(:data_processed, %{id: 123, status: :complete})

# Receive in your process
receive do
  {:plugin_message, :data_processed, data, metadata} ->
    handle_data(data)
end
```

### Request/Response

```elixir
# Register request handler
MessageBus.handle_requests(:my_service, fn request, metadata ->
  process_request(request)
end)

# Send request from another plugin
{:ok, response} = MessageBus.request(:my_service, %{cmd: :process})
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `module` | atom | required | Plugin module |
| `config` | keyword | [] | Plugin-specific configuration |
| `enabled` | boolean | true | Whether plugin is enabled |
| `priority` | integer | 50 | Execution priority (0-100) |
| `dependencies` | [atom] | [] | Required plugins |
| `auto_start` | boolean | true | Start automatically when loaded |
| `tags` | [atom] | [] | Categorization tags |

## Error Handling

- Plugin initialization failures prevent registration
- Execution errors are isolated and don't crash the system
- Circular dependencies detected at compile time
- Missing dependencies validated before starting

## Best Practices

1. **Keep plugins focused** - Single responsibility principle
2. **Handle errors gracefully** - Return `{:error, reason}` instead of crashing
3. **Validate input** - Implement `validate_input/1` for safety
4. **Document dependencies** - Be explicit about requirements
5. **Use appropriate data types** - Declare supported types accurately
6. **Clean up resources** - Implement `terminate/2` when needed
7. **Test in isolation** - Plugins should be independently testable

## Telemetry and Monitoring

Plugin execution emits telemetry events:
- Execution duration
- Success/failure rates
- Plugin state changes

Subscribe to events for monitoring:
```elixir
:telemetry.attach("plugin-metrics", 
  [:rubber_duck, :plugin, :execute], 
  &handle_event/4, 
  nil
)
```

## Limitations

- Plugins run in the same VM (no remote plugins yet)
- No dynamic code loading (plugins must be compiled)
- Limited to Elixir/Erlang languages
- No versioning conflicts resolution

## Future Enhancements

- Remote plugin execution
- Plugin marketplace/registry
- Hot code reloading
- Plugin sandboxing with restricted capabilities
- Version compatibility management