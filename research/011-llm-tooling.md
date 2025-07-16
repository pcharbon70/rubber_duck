# Comprehensive Tool Definition System Design for RubberDuck

## Architecture analysis reveals opportunity for unified tool system

Based on extensive research of the RubberDuck codebase architecture and LLM tool patterns, the coding assistant's Ash Framework foundation provides an ideal platform for building a sophisticated tool definition system. The existing Spark DSL infrastructure, combined with Reactor's workflow orchestration and planned MCP integration, creates natural extension points for a comprehensive tool system that can serve both internal engines and external MCP clients.

The analysis identified that RubberDuck's architecture follows a resource-oriented design pattern using Ash Framework, with declarative configuration through Spark DSL, event-driven workflows via Reactor, and a pluggable engine system. This architectural foundation aligns perfectly with modern LLM tool patterns observed across LangChain, OpenAI, and Anthropic implementations, while Elixir/OTP's concurrency model provides unique advantages for safe, scalable tool execution.

## Spark DSL enables declarative tool definitions with type safety

The proposed tool definition system leverages Spark DSL to create a declarative, extensible configuration language that maintains consistency with RubberDuck's existing patterns. This approach provides compile-time validation, code generation capabilities, and seamless integration with the current architecture.

```elixir
defmodule RubberDuck.Tool do
  use Spark.Dsl.Extension,
    sections: [@tool_definition, @execution, @security]

  @tool_definition %Spark.Dsl.Section{
    name: :tool,
    describe: "Define tool metadata and parameters",
    schema: [
      name: [type: :atom, required: true],
      description: [type: :string, required: true],
      category: [type: {:one_of, [:filesystem, :web, :command, :api, :composite]}],
      version: [type: :string, default: "1.0.0"]
    ],
    sections: [
      %Spark.Dsl.Section{
        name: :parameters,
        entities: [
          %Spark.Dsl.Entity{
            name: :param,
            target: RubberDuck.Tool.Parameter,
            args: [:name],
            schema: [
              name: [type: :atom, required: true],
              type: [type: :atom, required: true],
              description: [type: :string, required: true],
              required: [type: :boolean, default: false],
              default: [type: :any],
              constraints: [type: :keyword_list]
            ]
          }
        ]
      }
    ]
  }

  @execution %Spark.Dsl.Section{
    name: :execution,
    schema: [
      handler: [type: {:or, [:atom, {:tuple, [:atom, :atom]}]}, required: true],
      timeout: [type: :pos_integer, default: 30_000],
      async: [type: :boolean, default: true],
      retries: [type: :non_neg_integer, default: 3]
    ]
  }

  @security %Spark.Dsl.Section{
    name: :security,
    schema: [
      sandbox: [type: {:one_of, [:none, :process, :container]}, default: :process],
      capabilities: [type: {:list, :atom}, default: []],
      rate_limit: [type: :pos_integer],
      user_consent_required: [type: :boolean, default: false]
    ]
  }
end
```

This DSL approach enables tools to be defined declaratively while maintaining full type safety and validation. The system generates both runtime execution code and MCP-compatible tool descriptions from these definitions, ensuring consistency across all integration points.

## Multi-layer execution architecture ensures isolation and safety

The tool execution system implements a sophisticated multi-layer architecture that balances performance with security. Each layer serves a specific purpose in the execution pipeline, from request validation through result formatting.

**Validation Layer** performs comprehensive input validation using JSON Schema generated from Spark DSL definitions. This layer prevents malformed requests from reaching execution handlers and provides detailed error messages for debugging.

**Authorization Layer** integrates with Ash's policy system to enforce fine-grained access control. Tools can define custom authorization rules based on user roles, resource ownership, or contextual factors.

**Execution Layer** leverages Elixir's process isolation to run each tool in a supervised GenServer. This approach provides natural fault isolation - if a tool crashes, it doesn't affect the system. The layer supports configurable resource limits, timeouts, and cancellation.

**Result Processing Layer** handles output formatting, sensitive data filtering, and result caching. Results are validated against expected schemas before being returned to ensure type safety throughout the system.

```elixir
defmodule RubberDuck.Tool.Executor do
  use GenServer

  def execute(tool_name, params, opts \\ []) do
    with {:ok, tool} <- RubberDuck.Tool.Registry.get(tool_name),
         {:ok, validated} <- validate_params(tool, params),
         {:ok, authorized} <- authorize_execution(tool, opts[:actor]),
         {:ok, result} <- execute_sandboxed(tool, validated, opts) do
      process_result(result, tool)
    end
  end

  defp execute_sandboxed(tool, params, opts) do
    task = Task.Supervisor.async_nolink(
      RubberDuck.Tool.TaskSupervisor,
      fn -> 
        apply(tool.handler, :execute, [params])
      end,
      max_heap_size: opts[:max_heap_size] || 100_000_000
    )

    case Task.await(task, tool.timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> handle_execution_error(reason, tool)
    end
  end
end
```

## MCP integration enables universal tool access

The MCP server implementation exposes RubberDuck's tools to any MCP-compatible client, including IDEs, chat interfaces, and other AI systems. The server maintains stateful connections and handles tool discovery, execution, and result streaming.

```elixir
defmodule RubberDuck.MCP.ToolServer do
  use GenServer
  
  def handle_call({:json_rpc, %{"method" => "tools/list"}}, _from, state) do
    tools = RubberDuck.Tool.Registry.list_tools()
    |> Enum.map(&to_mcp_format/1)
    
    {:reply, {:ok, %{"tools" => tools}}, state}
  end

  def handle_call({:json_rpc, %{"method" => "tools/call", "params" => params}}, from, state) do
    %{"name" => tool_name, "arguments" => args} = params
    
    Task.start(fn ->
      result = RubberDuck.Tool.Executor.execute(tool_name, args, actor: state.actor)
      GenServer.reply(from, format_tool_result(result))
    end)
    
    {:noreply, state}
  end

  defp to_mcp_format(tool) do
    %{
      "name" => to_string(tool.name),
      "description" => tool.description,
      "inputSchema" => generate_json_schema(tool.parameters)
    }
  end
end
```

The MCP integration supports OAuth 2.1 authentication for remote access, tool annotations for UI hints, and proper error handling that distinguishes between protocol errors and tool execution failures.

## Security model leverages BEAM's process isolation

The security architecture takes advantage of BEAM's lightweight processes to provide multiple levels of isolation. Each tool execution runs in an isolated process with configurable resource limits, preventing runaway tools from affecting system stability.

**Process-level sandboxing** uses Erlang's built-in process flags to enforce memory limits and prevent excessive message queue growth. Tools that exceed limits are automatically terminated with proper cleanup.

**Capability-based security** restricts tool access to specific system resources. Tools must explicitly declare required capabilities (filesystem access, network access, etc.) which are enforced at runtime.

**Input sanitization** prevents common attack vectors like path traversal and command injection. The system provides built-in sanitizers for common patterns while allowing custom validation logic.

**Audit logging** tracks all tool executions with full context, enabling security analysis and compliance reporting. The audit system integrates with Ash's change tracking for complete traceability.

## Tool composition enables complex workflows

The system supports sophisticated tool composition patterns through integration with Reactor workflows. Composite tools can orchestrate multiple atomic tools, handle conditional logic, and manage distributed execution.

```elixir
defmodule RubberDuck.Tools.CodeRefactoring do
  use RubberDuck.Tool

  tool do
    name :refactor_module
    description "Analyzes and refactors an Elixir module"
    category :composite
  end

  workflow do
    step :parse_code, tool: :elixir_parser
    step :analyze_complexity, tool: :complexity_analyzer, 
         input: result(:parse_code)
    
    branch :needs_refactoring?, result(:analyze_complexity) do
      true ->
        step :identify_patterns, tool: :pattern_detector
        step :generate_refactoring, tool: :refactoring_generator
        step :validate_refactoring, tool: :code_validator
      
      false ->
        return {:ok, "No refactoring needed"}
    end
  end
end
```

This composition model enables building sophisticated tools from simpler components while maintaining clear execution boundaries and error handling.

## Implementation roadmap aligns with existing phases

The tool system implementation should be phased to align with RubberDuck's development roadmap:

**Phase 1 - Core Infrastructure** (Integrate with Phase 2): Implement basic tool registry, Spark DSL definitions, and execution engine. This provides the foundation for all subsequent features.

**Phase 2 - Engine Integration** (Align with Phase 3): Connect tools to the existing engine system, allowing engines to discover and execute tools. Add structured input/output handling for LLM integration.

**Phase 3 - Workflow Integration** (Align with Phase 4): Integrate tools with Reactor workflows, enabling complex tool compositions and conditional execution patterns.

**Phase 4 - MCP Server** (Implement Phase 8): Deploy full MCP server with authentication, tool discovery, and streaming support. This enables external tool access.

**Phase 5 - Advanced Features**: Add distributed execution, advanced sandboxing options, and performance optimizations based on usage patterns.

## Testing and validation ensure reliability

The tool system includes comprehensive testing infrastructure:

**Property-based testing** uses StreamData to generate random inputs and verify tool behavior across edge cases. This catches subtle bugs that example-based tests might miss.

**Integration testing** verifies tool interaction with engines, workflows, and MCP clients. Tests run in isolated environments to prevent interference.

**Performance benchmarking** tracks tool execution times, memory usage, and system impact. Automated alerts detect performance regressions.

**Security testing** includes fuzzing, penetration testing, and automated vulnerability scanning. The system undergoes regular security audits.

## Conclusion

This comprehensive tool definition system design leverages RubberDuck's existing architectural strengths while incorporating best practices from the broader LLM ecosystem. The Spark DSL approach provides elegant declarative configuration, while Elixir/OTP's process model enables robust isolation and concurrent execution. The phased implementation plan ensures smooth integration with existing systems while building toward full MCP compatibility.

The design prioritizes developer experience through declarative configuration, operational excellence through comprehensive monitoring and testing, and security through multiple isolation layers. By building on Ash Framework's resource-oriented patterns and Reactor's workflow capabilities, the tool system becomes a natural extension of RubberDuck's architecture rather than a bolted-on component.
