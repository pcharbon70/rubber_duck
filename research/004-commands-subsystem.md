# RubberDuck Commands Subsystem Design

## Executive Summary

This design proposes a distributed, interface-agnostic commands subsystem for RubberDuck that leverages Elixir/OTP best practices. The architecture combines **Optimus** for command parsing, **Owl** for rich TUI interactions, **Horde** for distributed process management, and a behavior-based abstraction layer enabling seamless command execution across CLI, TUI, web, and IDE interfaces.

## Architecture Overview

### Core Components

```elixir
RubberDuck.CommandSystem
├── CommandRegistry (Horde.Registry)
├── CommandSupervisor (Horde.DynamicSupervisor)  
├── CommandRouter (routing logic)
├── CommandMetadata (structured definitions)
├── InterfaceAdapters (CLI/TUI/Web/IDE)
└── CommandExecutor (distributed execution)
```

### Key Design Decisions

1. **Optimus + Owl**: Best-in-class command parsing with rich interactive capabilities
2. **Horde-based Distribution**: Fault-tolerant distributed command execution
3. **Behavior-based Abstraction**: Clean separation between command logic and interfaces
4. **Metadata-driven UI**: Dynamic interface generation from command definitions

## Command Definition Layer

### Command Metadata Structure

```elixir
defmodule RubberDuck.CommandMetadata do
  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    category: String.t(),
    parameters: [Parameter.t()],
    subcommands: [t()],
    when_conditions: [String.t()],
    examples: [map()],
    interface_hints: map()
  }
  
  defstruct [:name, :description, :category, :parameters, 
             :subcommands, :when_conditions, :examples, :interface_hints]
  
  defmodule Parameter do
    @type t :: %__MODULE__{
      name: atom(),
      type: :string | :integer | :boolean | :float | :enum,
      description: String.t(),
      required: boolean(),
      default: any(),
      options: [any()],
      validation: (any() -> :ok | {:error, String.t()}),
      completion: (String.t() -> [String.t()])
    }
    
    defstruct [:name, :type, :description, :required, :default, 
               :options, :validation, :completion]
  end
end
```

### Command Behavior

```elixir
defmodule RubberDuck.CommandBehaviour do
  @callback metadata() :: RubberDuck.CommandMetadata.t()
  @callback execute(args :: map(), context :: map()) :: 
    {:ok, result :: any()} | {:error, reason :: any()}
  @callback validate(args :: map()) :: 
    {:ok, validated_args :: map()} | {:error, reason :: any()}
end
```

### Example Command Implementation

```elixir
defmodule RubberDuck.Commands.CreateModel do
  @behaviour RubberDuck.CommandBehaviour
  
  def metadata do
    %CommandMetadata{
      name: "model.create",
      description: "Create a new AI model configuration",
      category: "model",
      parameters: [
        %Parameter{
          name: :name,
          type: :string,
          description: "Model identifier",
          required: true,
          validation: &validate_model_name/1
        },
        %Parameter{
          name: :provider,
          type: :enum,
          options: ["openai", "anthropic", "local"],
          description: "Model provider",
          required: true
        }
      ],
      examples: [
        %{args: %{name: "gpt-4", provider: "openai"}, 
          description: "Create OpenAI model config"}
      ]
    }
  end
  
  def execute(%{name: name, provider: provider}, context) do
    with {:ok, model} <- ModelCoordinator.create_model(name, provider, context) do
      {:ok, %{model: model, message: "Model #{name} created successfully"}}
    end
  end
  
  def validate(args) do
    # Validation logic using Ecto-style changesets or custom validation
    {:ok, args}
  end
end
```

## Interface Abstraction Layer

### Extended InterfaceBehaviour

```elixir
defmodule RubberDuck.InterfaceBehaviour do
  @callback render_command_prompt(metadata :: CommandMetadata.t()) :: any()
  @callback collect_parameters(parameters :: [Parameter.t()]) :: {:ok, map()} | {:error, any()}
  @callback render_result(result :: any(), context :: map()) :: any()
  @callback show_error(error :: any(), context :: map()) :: any()
  @callback show_progress(message :: String.t(), progress :: float()) :: any()
  @callback supports_feature?(feature :: atom()) :: boolean()
end
```

### Interface Adapters

```elixir
defmodule RubberDuck.Interfaces.CLI do
  @behaviour RubberDuck.InterfaceBehaviour
  
  def render_command_prompt(%CommandMetadata{} = metadata) do
    # Use Optimus to generate CLI interface
    Optimus.new!(
      name: metadata.name,
      description: metadata.description,
      args: build_optimus_args(metadata.parameters),
      flags: build_optimus_flags(metadata.parameters)
    )
  end
  
  def collect_parameters(parameters) do
    # Interactive parameter collection for CLI
    Enum.reduce_while(parameters, {:ok, %{}}, fn param, {:ok, acc} ->
      case collect_cli_parameter(param) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, param.name, value)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  def supports_feature?(:autocomplete), do: true
  def supports_feature?(:interactive_prompts), do: true
  def supports_feature?(_), do: false
end

defmodule RubberDuck.Interfaces.TUI do
  @behaviour RubberDuck.InterfaceBehaviour
  use Ratatouille.App
  
  def render_command_prompt(%CommandMetadata{} = metadata) do
    # Use Owl for rich TUI interface
    import Ratatouille.View
    
    view do
      panel title: metadata.name do
        label(content: metadata.description)
        
        for param <- metadata.parameters do
          render_parameter_input(param)
        end
      end
    end
  end
  
  def supports_feature?(:rich_formatting), do: true
  def supports_feature?(:mouse_input), do: true
  def supports_feature?(_), do: false
end
```

## Distributed Command Execution

### Command Router with Horde

```elixir
defmodule RubberDuck.CommandRouter do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple("router"))
  end
  
  def route_command(command_name, args, context) do
    GenServer.call(via_tuple("router"), {:route, command_name, args, context})
  end
  
  def handle_call({:route, command_name, args, context}, _from, state) do
    case lookup_handler(command_name) do
      {:ok, handler_pid} ->
        result = GenServer.call(handler_pid, {:execute, args, context})
        {:reply, result, state}
        
      :error ->
        # Start new handler via Horde.DynamicSupervisor
        case start_command_handler(command_name) do
          {:ok, handler_pid} ->
            result = GenServer.call(handler_pid, {:execute, args, context})
            {:reply, result, state}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  defp via_tuple(name) do
    {:via, Horde.Registry, {RubberDuck.CommandRegistry, name}}
  end
  
  defp lookup_handler(command_name) do
    case Horde.Registry.lookup(RubberDuck.CommandRegistry, {:handler, command_name}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
```

### Command Handler GenServer

```elixir
defmodule RubberDuck.CommandHandler do
  use GenServer
  
  defstruct [:command_module, :execution_count, :last_executed, :state]
  
  def start_link({command_name, command_module}) do
    GenServer.start_link(__MODULE__, command_module, 
      name: via_tuple(command_name))
  end
  
  def init(command_module) do
    Process.flag(:trap_exit, true)
    
    {:ok, %__MODULE__{
      command_module: command_module,
      execution_count: 0,
      last_executed: nil,
      state: %{}
    }}
  end
  
  def handle_call({:execute, args, context}, _from, state) do
    # Add distributed tracing
    trace_id = generate_trace_id()
    context = Map.put(context, :trace_id, trace_id)
    
    # Execute with circuit breaker
    result = with_circuit_breaker(state.command_module, fn ->
      state.command_module.execute(args, context)
    end)
    
    new_state = %{state | 
      execution_count: state.execution_count + 1,
      last_executed: DateTime.utc_now()
    }
    
    {:reply, result, new_state}
  end
  
  # Graceful shutdown with state handoff
  def terminate(_reason, state) do
    Horde.Registry.put_meta(
      RubberDuck.CommandRegistry,
      {:handoff, self()},
      state
    )
  end
end
```

## State Management

### Distributed State Strategies

```elixir
defmodule RubberDuck.CommandState do
  # Local caching with ETS
  def init_local_cache do
    :ets.new(:command_cache, [:named_table, :public, read_concurrency: true])
  end
  
  # Distributed state with Mnesia
  def init_distributed_state do
    :mnesia.create_schema([node()])
    :mnesia.start()
    
    :mnesia.create_table(:command_history, 
      attributes: [:id, :command, :args, :result, :timestamp, :node],
      disc_copies: [node()],
      type: :set
    )
  end
  
  # CRDT for eventually consistent state
  def init_crdt_state do
    {:ok, crdt} = DeltaCrdt.start_link(
      DeltaCrdt.AWLWWMap,
      sync_interval: 100,
      max_sync_size: 1000
    )
    
    Process.register(crdt, :command_state_crdt)
  end
end
```

## Command Discovery and Help

### Dynamic Command Discovery

```elixir
defmodule RubberDuck.CommandDiscovery do
  def discover_commands do
    # Scan for modules implementing CommandBehaviour
    :code.all_loaded()
    |> Enum.filter(fn {mod, _} -> 
      is_command_module?(mod)
    end)
    |> Enum.map(fn {mod, _} -> 
      {mod.metadata().name, mod}
    end)
    |> Enum.into(%{})
  end
  
  defp is_command_module?(module) do
    Code.ensure_loaded?(module) and
    function_exported?(module, :behaviour_info, 1) and
    RubberDuck.CommandBehaviour in module.behaviour_info(:callbacks)
  end
  
  def search_commands(query, context) do
    all_commands = CommandRegistry.list_available_commands()
    
    all_commands
    |> Enum.filter(fn cmd -> 
      matches_query?(cmd, query) and 
      meets_conditions?(cmd, context)
    end)
    |> Enum.sort_by(&relevance_score(&1, query), &>=/2)
  end
end
```

### Help Generation

```elixir
defmodule RubberDuck.CommandHelp do
  def generate_help(command_name, format \\ :text) do
    case CommandRegistry.get_command(command_name) do
      {:ok, command_module} ->
        metadata = command_module.metadata()
        
        case format do
          :text -> format_text_help(metadata)
          :markdown -> format_markdown_help(metadata)
          :json -> format_json_help(metadata)
        end
        
      :error ->
        {:error, :command_not_found}
    end
  end
  
  defp format_text_help(metadata) do
    """
    #{metadata.name} - #{metadata.description}
    
    USAGE:
      #{usage_string(metadata)}
    
    PARAMETERS:
    #{format_parameters_text(metadata.parameters)}
    
    EXAMPLES:
    #{format_examples_text(metadata.examples)}
    """
  end
end
```

## Testing Strategy

### Multi-Level Testing Approach

```elixir
# Unit tests for command modules
defmodule RubberDuck.Commands.CreateModelTest do
  use ExUnit.Case, async: true
  
  describe "metadata/0" do
    test "returns valid command metadata" do
      metadata = CreateModel.metadata()
      assert metadata.name == "model.create"
      assert length(metadata.parameters) == 2
    end
  end
  
  describe "execute/2" do
    test "creates model successfully" do
      args = %{name: "test-model", provider: "openai"}
      context = %{user_id: "user123"}
      
      assert {:ok, result} = CreateModel.execute(args, context)
      assert result.model.name == "test-model"
    end
  end
end

# Property-based testing
defmodule RubberDuck.CommandPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "all commands handle invalid input gracefully" do
    check all command_name <- StreamData.member_of(list_all_commands()),
              invalid_args <- map_of(atom(), term()) do
      
      command_module = CommandRegistry.get_command!(command_name)
      result = command_module.execute(invalid_args, %{})
      
      assert match?({:error, _}, result)
    end
  end
end

# Integration testing
defmodule RubberDuck.CommandIntegrationTest do
  use ExUnit.Case
  
  setup do
    {:ok, _} = start_supervised(RubberDuck.CommandSystem)
    :ok
  end
  
  test "command execution across interfaces" do
    # Test same command via different interfaces
    for interface <- [:cli, :tui, :web] do
      result = RubberDuck.InterfaceGateway.execute_command(
        interface,
        "model.create",
        %{name: "test-#{interface}", provider: "openai"}
      )
      
      assert {:ok, _} = result
    end
  end
end
```

## Integration with Existing RubberDuck Components

### ContextManager Integration

```elixir
defmodule RubberDuck.Commands.ContextAware do
  def build_command_context(user_session) do
    %{
      user_id: user_session.user_id,
      conversation_id: ContextManager.current_conversation(user_session),
      available_models: ModelCoordinator.list_available_models(),
      interface_capabilities: InterfaceGateway.current_capabilities(),
      node: node(),
      timestamp: DateTime.utc_now()
    }
  end
end
```

### ModelCoordinator Integration

```elixir
defmodule RubberDuck.Commands.ModelCommands do
  def route_to_model(command, context) do
    model = ModelCoordinator.select_best_model(command, context)
    ModelCoordinator.execute_with_model(model, command)
  end
end
```

## Implementation Roadmap

### Phase 1: Core Infrastructure (Week 1-2)
- Set up Optimus for command parsing
- Implement CommandBehaviour and metadata structures
- Create basic CommandRegistry with Horde.Registry
- Build initial CLI interface adapter

### Phase 2: Distributed Execution (Week 3-4)
- Implement Horde.DynamicSupervisor for command handlers
- Add distributed state management with Mnesia
- Implement circuit breakers and fault tolerance
- Create command routing layer

### Phase 3: Multi-Interface Support (Week 5-6)
- Build TUI adapter with Owl/Ratatouille
- Implement web interface adapter for Phoenix
- Create IDE protocol adapter
- Add command discovery and help generation

### Phase 4: Advanced Features (Week 7-8)
- Property-based testing suite
- Performance optimization and benchmarking
- Command composition and pipelines
- Advanced context propagation

## Performance Considerations

### Optimization Strategies

1. **Command Caching**: Use ETS for frequently executed commands
2. **Lazy Loading**: Load command modules on-demand
3. **Batch Processing**: Support batch command execution
4. **Connection Pooling**: Reuse interface connections
5. **Parallel Execution**: Use Task.async_stream for independent commands

### Benchmarking Approach

```elixir
Benchee.run(%{
  "single_command" => fn -> execute_command("model.create", args) end,
  "batch_commands" => fn -> execute_batch(commands) end,
  "parallel_commands" => fn -> execute_parallel(commands) end
}, time: 10, memory_time: 2)
```

## Security Considerations

1. **Command Authorization**: Integrate with existing auth system
2. **Input Validation**: Strict parameter validation at interface boundary
3. **Rate Limiting**: Per-user command execution limits
4. **Audit Logging**: Comprehensive command history in Mnesia
5. **Sandboxing**: Isolated execution environments for untrusted commands

## Conclusion

This design provides a robust, scalable foundation for RubberDuck's command subsystem that:

- **Supports multiple interfaces** through behavior-based abstraction
- **Scales horizontally** using Horde's distributed process management
- **Maintains fault tolerance** with OTP supervision trees
- **Enables rich interactions** via Optimus and Owl
- **Integrates seamlessly** with existing RubberDuck components

The architecture follows Elixir/OTP best practices while providing the flexibility needed for a distributed AI assistant platform.
