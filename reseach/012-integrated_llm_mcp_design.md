# RubberDuck Integrated LLM & MCP System Design

## Overview

This document presents a unified architecture that integrates RubberDuck's LLM capabilities with the Model Context Protocol (MCP) server implementation. The design leverages Elixir's OTP principles, the Ash Framework's declarative patterns, and Spark DSL for extensibility while providing a standards-compliant MCP interface for external tools and LLMs.

## Architecture Principles

### Core Design Philosophy
1. **Declarative Configuration**: Use Ash Framework and Spark DSL for declarative system definition
2. **Fault Tolerance**: Leverage OTP supervision trees for resilient operation
3. **Protocol Agnostic**: Support multiple transport mechanisms (STDIO, WebSocket, HTTP)
4. **Composability**: Enable tool composition and enhancement through modular design
5. **Real-time Capable**: Support streaming and real-time updates via Phoenix Channels
6. **Memory-Enhanced**: Integrate hierarchical memory system for context-aware operations

## System Architecture

### Layer 1: Core LLM Infrastructure

#### 1.1 LLM Service Layer
```elixir
defmodule RubberDuck.LLM.Service do
  use GenServer
  use Ash.Api
  
  # Manages multiple LLM providers with fallback
  defstruct [
    :providers,
    :active_provider,
    :fallback_chain,
    :rate_limiters,
    :circuit_breakers,
    :telemetry_ref
  ]
  
  # Provider adapters for different LLMs
  def providers do
    %{
      openai: RubberDuck.LLM.Providers.OpenAI,
      anthropic: RubberDuck.LLM.Providers.Anthropic,
      ollama: RubberDuck.LLM.Providers.Ollama,
      local: RubberDuck.LLM.Providers.Local
    }
  end
end
```

#### 1.2 Memory System Integration
```elixir
defmodule RubberDuck.Memory.HierarchicalSystem do
  @moduledoc """
  Three-tier memory system for maintaining context
  """
  
  # Short-term: ETS-based session memory
  defmodule ShortTerm do
    use GenServer
    
    def init(opts) do
      table = :ets.new(:short_term_memory, [:set, :public])
      {:ok, %{table: table, max_items: 100}}
    end
  end
  
  # Mid-term: Pattern extraction and caching
  defmodule MidTerm do
    use Ash.Resource,
      data_layer: Ash.DataLayer.Ets
    
    attributes do
      uuid_primary_key :id
      attribute :pattern, :string
      attribute :frequency, :integer
      attribute :context, :map
      timestamps()
    end
  end
  
  # Long-term: PostgreSQL with pgvector
  defmodule LongTerm do
    use Ash.Resource,
      data_layer: AshPostgres.DataLayer
    
    attributes do
      uuid_primary_key :id
      attribute :content, :text
      attribute :embedding, {:array, :float}
      attribute :metadata, :map
      timestamps()
    end
    
    postgres do
      table "long_term_memories"
      repo RubberDuck.Repo
    end
  end
end
```

#### 1.3 Enhancement Techniques
```elixir
defmodule RubberDuck.Enhancement do
  @moduledoc """
  LLM enhancement techniques implementation
  """
  
  defmodule ChainOfThought do
    use Spark.Dsl.Extension
    
    dsl do
      section :reasoning do
        schema [
          steps: [type: {:list, :atom}, required: true],
          max_iterations: [type: :integer, default: 3]
        ]
      end
    end
    
    def execute(prompt, context) do
      # Implement step-by-step reasoning
    end
  end
  
  defmodule RAG do
    def enhance(prompt, %{memory: memory} = context) do
      # Retrieve relevant context
      relevant_docs = retrieve_documents(prompt, memory)
      
      # Augment prompt with context
      augmented_prompt = build_augmented_prompt(prompt, relevant_docs)
      
      # Generate with context
      {:ok, augmented_prompt, relevant_docs}
    end
  end
  
  defmodule SelfCorrection do
    def validate_and_correct(response, context) do
      # Validate response
      errors = validate_response(response)
      
      # Apply corrections if needed
      if Enum.any?(errors) do
        correct_response(response, errors, context)
      else
        {:ok, response}
      end
    end
  end
end
```

### Layer 2: MCP Protocol Implementation

#### 2.1 MCP Server Core
```elixir
defmodule RubberDuck.MCP.Server do
  use GenServer
  require Logger
  
  alias RubberDuck.MCP.{
    Protocol,
    ToolRegistry,
    SessionManager,
    Transport
  }
  
  defstruct [
    :transport,
    :sessions,
    :tool_registry,
    :config,
    :llm_service
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Initialize MCP server with LLM integration
    state = %__MODULE__{
      transport: init_transport(opts[:transport] || :stdio),
      sessions: %{},
      tool_registry: init_tool_registry(),
      llm_service: init_llm_service(opts),
      config: build_config(opts)
    }
    
    {:ok, state, {:continue, :setup}}
  end
  
  defp init_llm_service(opts) do
    # Start LLM service as part of MCP server
    {:ok, llm_pid} = RubberDuck.LLM.Service.start_link(opts[:llm_config] || [])
    llm_pid
  end
end
```

#### 2.2 Unified Tool System
```elixir
defmodule RubberDuck.MCP.ToolSystem do
  @moduledoc """
  Unified tool system that bridges Ash actions and MCP tools
  """
  
  defmodule Tool do
    use Ash.Resource,
      data_layer: Ash.DataLayer.Ets
    
    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false
      attribute :description, :string
      attribute :parameters, :map
      attribute :handler_module, :atom
      attribute :capabilities, {:array, :atom}
      attribute :llm_enhanced, :boolean, default: false
    end
    
    actions do
      defaults [:create, :read, :update]
      
      action :execute, :map do
        argument :input, :map, allow_nil?: false
        argument :context, :map
        
        run fn input, context ->
          RubberDuck.MCP.ToolExecutor.execute(input.arguments.tool_id, input, context)
        end
      end
    end
  end
  
  defmodule ToolComposer do
    use Spark.Dsl.Extension
    
    @tool_composition_dsl [
      %Spark.Dsl.Section{
        name: :composition,
        schema: [
          name: [type: :atom, required: true],
          description: [type: :string]
        ],
        sections: [
          %Spark.Dsl.Section{
            name: :steps,
            entity: Spark.Dsl.Entity,
            schema: [
              tool: [type: :atom, required: true],
              input_mapping: [type: :map],
              output_mapping: [type: :map]
            ]
          }
        ]
      }
    ]
    
    use Spark.Dsl.Extension,
      sections: @tool_composition_dsl
  end
end
```

#### 2.3 Protocol Bridge
```elixir
defmodule RubberDuck.MCP.ProtocolBridge do
  @moduledoc """
  Bridges MCP protocol with internal LLM and tool systems
  """
  
  def handle_tools_list(state) do
    # Get tools from registry
    ash_tools = RubberDuck.Tools.list_tools()
    
    # Convert to MCP format
    mcp_tools = Enum.map(ash_tools, &convert_to_mcp_tool/1)
    
    %{
      tools: mcp_tools
    }
  end
  
  def handle_tool_execute(tool_name, arguments, state) do
    # Execute through unified system
    with {:ok, tool} <- RubberDuck.Tools.get_tool(tool_name),
         {:ok, context} <- build_execution_context(state),
         {:ok, enhanced_args} <- enhance_with_llm(arguments, tool, context),
         {:ok, result} <- execute_tool(tool, enhanced_args, context) do
      
      # Format result for MCP
      format_mcp_result(result)
    end
  end
  
  defp enhance_with_llm(arguments, tool, context) do
    if tool.llm_enhanced do
      # Use LLM to enhance/validate arguments
      RubberDuck.LLM.Service.enhance_tool_arguments(arguments, tool, context)
    else
      {:ok, arguments}
    end
  end
end
```

### Layer 3: Transport and Communication

#### 3.1 Multi-Transport Support
```elixir
defmodule RubberDuck.MCP.Transport do
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback send_message(pid :: pid(), message :: map()) :: :ok
  @callback receive_message(pid :: pid()) :: {:ok, map()} | {:error, term()}
  
  defmodule STDIO do
    @behaviour RubberDuck.MCP.Transport
    
    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    def handle_info({:io_request, from, ref, {:put_chars, _, data}}, state) do
      message = Jason.decode!(data)
      send(state.parent, {:mcp_message, message})
      send(from, {:io_reply, ref, :ok})
      {:noreply, state}
    end
  end
  
  defmodule WebSocket do
    @behaviour RubberDuck.MCP.Transport
    
    def start_link(opts) do
      Phoenix.Channel.start_link(__MODULE__, opts)
    end
    
    def handle_in("mcp_request", payload, socket) do
      # Process MCP request through unified system
      result = RubberDuck.MCP.Server.handle_request(payload)
      
      # Support streaming responses
      case result do
        {:stream, stream} ->
          Task.start(fn ->
            Enum.each(stream, fn chunk ->
              push(socket, "mcp_stream", chunk)
            end)
            push(socket, "mcp_stream_end", %{})
          end)
          {:noreply, socket}
          
        {:ok, response} ->
          {:reply, {:ok, response}, socket}
      end
    end
  end
end
```

#### 3.2 Session Management
```elixir
defmodule RubberDuck.MCP.SessionManager do
  use DynamicSupervisor
  
  defmodule Session do
    use GenServer
    
    defstruct [
      :id,
      :client_info,
      :active_tools,
      :conversation_state,
      :memory_context,
      :llm_session,
      :created_at,
      :last_activity
    ]
    
    def init({session_id, client_info}) do
      # Initialize session with LLM context
      {:ok, memory} = RubberDuck.Memory.Manager.create_session(session_id)
      {:ok, llm_session} = RubberDuck.LLM.Service.create_session(session_id)
      
      state = %__MODULE__{
        id: session_id,
        client_info: client_info,
        active_tools: MapSet.new(),
        memory_context: memory,
        llm_session: llm_session,
        conversation_state: %{},
        created_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      {:ok, state}
    end
    
    def handle_call({:execute_tool, tool_name, args}, _from, state) do
      # Execute with full context
      context = build_context(state)
      
      result = RubberDuck.MCP.ToolExecutor.execute(
        tool_name,
        args,
        context
      )
      
      # Update memory with execution
      updated_state = update_memory(state, tool_name, args, result)
      
      {:reply, result, updated_state}
    end
  end
end
```

### Layer 4: Integrated Features

#### 4.1 Conversation-Aware Tools
```elixir
defmodule RubberDuck.Tools.ConversationAware do
  @moduledoc """
  Tools that leverage conversation context and memory
  """
  
  defmodule CodeAnalysis do
    use RubberDuck.MCP.Tool
    
    tool do
      name :analyze_with_context
      description "Analyzes code using conversation history and project context"
      
      parameters do
        required :code, :string
        optional :focus_areas, {:array, :string}
        optional :use_history, :boolean, default: true
      end
      
      llm_enhanced true
    end
    
    def execute(%{code: code} = params, context) do
      # Get relevant context from memory
      relevant_context = if params[:use_history] do
        RubberDuck.Memory.Retriever.get_relevant_context(
          code,
          context.session.memory_context
        )
      else
        %{}
      end
      
      # Use LLM with context
      analysis = RubberDuck.LLM.Service.analyze(
        code,
        Map.merge(context, relevant_context)
      )
      
      {:ok, analysis}
    end
  end
end
```

#### 4.2 Reactive Workflows
```elixir
defmodule RubberDuck.Workflows.Reactive do
  use Reactor, extensions: [Ash.Reactor]
  
  input :mcp_request
  
  step :parse_request do
    argument :request, input(:mcp_request)
    run RubberDuck.MCP.Protocol.parse_request()
  end
  
  step :enhance_with_llm do
    argument :parsed, result(:parse_request)
    run RubberDuck.Enhancement.ChainOfThought.execute()
  end
  
  step :execute_tool do
    argument :enhanced, result(:enhance_with_llm)
    run RubberDuck.MCP.ToolExecutor.execute()
  end
  
  step :validate_result do
    argument :result, result(:execute_tool)
    run RubberDuck.Enhancement.SelfCorrection.validate_and_correct()
  end
  
  step :update_memory do
    argument :validated, result(:validate_result)
    run RubberDuck.Memory.Manager.store_interaction()
  end
  
  return :validate_result
end
```

#### 4.3 Monitoring and Observability
```elixir
defmodule RubberDuck.MCP.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  
  def metrics do
    [
      # MCP metrics
      counter("mcp.request.count"),
      summary("mcp.request.duration"),
      counter("mcp.tool.executed.count"),
      
      # LLM metrics
      counter("llm.request.count", tags: [:provider, :model]),
      summary("llm.request.duration", tags: [:provider]),
      summary("llm.tokens.used", tags: [:provider, :type]),
      
      # Memory metrics
      last_value("memory.short_term.size"),
      last_value("memory.patterns.count"),
      
      # Enhancement metrics
      counter("enhancement.cot.executed"),
      counter("enhancement.rag.queries"),
      summary("enhancement.self_correction.iterations")
    ]
  end
end
```

## Deployment Architecture

### Supervision Tree
```elixir
defmodule RubberDuck.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Core services
      RubberDuck.Repo,
      RubberDuck.PubSub,
      
      # LLM system
      {RubberDuck.LLM.Service, name: :llm_service},
      {RubberDuck.Memory.Manager, name: :memory_manager},
      
      # MCP server
      {RubberDuck.MCP.Server, transport: :websocket},
      {RubberDuck.MCP.SessionSupervisor, name: :mcp_sessions},
      
      # Tool system
      {RubberDuck.MCP.ToolRegistry, name: :tool_registry},
      
      # Web interface (if using Phoenix)
      RubberDuckWeb.Endpoint,
      
      # Telemetry
      RubberDuck.MCP.Telemetry
    ]
    
    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Configuration
```elixir
# config/config.exs
config :rubber_duck, 
  # MCP configuration
  mcp: [
    transport: :websocket,
    port: 4000,
    protocol_version: "2024-11-05"
  ],
  
  # LLM configuration
  llm: [
    providers: [
      openai: [api_key: System.get_env("OPENAI_API_KEY")],
      anthropic: [api_key: System.get_env("ANTHROPIC_API_KEY")],
      ollama: [base_url: "http://localhost:11434"]
    ],
    default_provider: :ollama,
    fallback_chain: [:ollama, :openai, :anthropic]
  ],
  
  # Memory configuration
  memory: [
    short_term_limit: 100,
    mid_term_ttl: :timer.hours(24),
    long_term_enabled: true
  ]
```

## Integration Examples

### Example 1: Code Generation with Context
```elixir
# MCP client request
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "generate_code",
    "arguments": {
      "description": "Create a GenServer for handling user sessions",
      "language": "elixir",
      "use_context": true
    }
  },
  "id": "1"
}

# System flow:
# 1. MCP Server receives request
# 2. Retrieves relevant context from memory (similar code patterns)
# 3. Enhances prompt with RAG
# 4. Generates code using LLM
# 5. Validates with self-correction
# 6. Stores in memory for future reference
# 7. Returns MCP response
```

### Example 2: Multi-Tool Composition
```elixir
defmodule MyApp.Tools.Composed do
  use RubberDuck.MCP.ToolComposer
  
  composition do
    name :refactor_and_test
    description "Refactor code and generate tests"
    
    steps do
      step :analyze do
        tool :code_analysis
        input_mapping %{code: :input_code}
      end
      
      step :refactor do
        tool :code_refactor
        input_mapping %{
          code: :input_code,
          issues: :analyze.issues
        }
      end
      
      step :generate_tests do
        tool :test_generation
        input_mapping %{
          code: :refactor.code
        }
      end
    end
  end
end
```

## Key Design Benefits

1. **Unified Architecture**: Single system handles both LLM operations and MCP protocol
2. **Memory-Enhanced**: All operations benefit from hierarchical memory system
3. **Fault Tolerant**: OTP supervision ensures system resilience
4. **Extensible**: Spark DSL enables easy addition of new tools and capabilities
5. **Real-time Capable**: Phoenix Channels enable streaming and real-time updates
6. **Observable**: Comprehensive telemetry for monitoring and optimization

## Implementation Roadmap

### Phase 1: Core Infrastructure
- Set up Ash domain and resources
- Implement basic MCP protocol handler
- Create WebSocket transport

### Phase 2: LLM Integration
- Integrate LLM providers
- Implement memory system
- Add enhancement techniques

### Phase 3: Tool System
- Build tool registry
- Implement tool composition
- Add LLM-enhanced tools

### Phase 4: Production Features
- Add monitoring and telemetry
- Implement authentication
- Create admin interface

### Phase 5: Advanced Features
- Multi-agent support
- Advanced workflow orchestration
- Distributed deployment

This integrated design provides a comprehensive system that leverages Elixir's strengths while providing a standards-compliant MCP interface for tool integration with LLMs.
