# RubberDuck Conversation AI System - Comprehensive Guide

## Table of Contents

1. [Introduction](#introduction)
2. [Architecture Overview](#architecture)
3. [Conversation Engines](#conversation-engines)
4. [ConversationChannel](#conversation-channel)
5. [Question Classification and Routing](#routing)
6. [Integration with CoT](#cot-integration)
7. [Session and Context Management](#session-management)
8. [Client Integration](#client-integration)
9. [Examples and Use Cases](#examples)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

## 1. Introduction {#introduction}

The RubberDuck Conversation AI system provides intelligent, context-aware conversational interactions through a sophisticated engine-based architecture. It seamlessly handles everything from simple queries to complex multi-step reasoning tasks.

### Key Features

- **Intelligent Routing**: Automatically routes queries to specialized engines
- **Context Preservation**: Maintains conversation history across exchanges
- **WebSocket-based**: Real-time bidirectional communication
- **Scalable Architecture**: Each conversation runs in isolated processes
- **Extensible Design**: Easy to add new conversation patterns

### Design Philosophy

The system separates concerns into three layers:
1. **Interface Layer**: WebSocket channels for client communication
2. **Routing Layer**: Intelligent classification and engine selection
3. **Processing Layer**: Specialized engines for different conversation types

## 2. Architecture Overview {#architecture}

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Applications                       │
│              (Web UI, VS Code, Mobile Apps)                 │
└─────────────────────┬───────────────────────────────────────┘
                      │ WebSocket
┌─────────────────────┴───────────────────────────────────────┐
│                  ConversationChannel                         │
│         (Phoenix Channel, Session Management)                │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│                    Engine Manager                            │
│              (Routing, Pool Management)                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────┴───────────────────────────────────────┐
│                ConversationRouter                            │
│          (Query Classification & Routing)                    │
└────┬────────┬────────┬────────┬────────┬────────┬──────────┘
     │        │        │        │        │        │
┌────┴───┐┌───┴───┐┌───┴───┐┌───┴───┐┌───┴───┐┌───┴───┐
│Simple  ││Complex││Analysis││Gener- ││Problem││Multi- │
│Conv.   ││Conv.  ││Conv.   ││ation  ││Solver ││Step   │
└────────┘└───┬───┘└────────┘└───────┘└───────┘└───────┘
              │ Uses CoT
         ┌────┴────────────┐
         │ Chain-of-Thought│
         │    System       │
         └─────────────────┘
```

## 3. Conversation Engines {#conversation-engines}

### 3.1 ConversationRouter

The router is the entry point for all conversational queries:

```elixir
defmodule RubberDuck.Engines.Conversation.ConversationRouter do
  @behaviour RubberDuck.Engine
  
  def execute(input, state) do
    # Classify query
    query_type = classify_query(input.query, input.context)
    
    # Route to appropriate engine
    target_engine = select_engine(query_type)
    
    # Execute through EngineManager
    case EngineManager.execute(target_engine, input, state.timeout) do
      {:ok, result} -> 
        {:ok, Map.put(result, :routed_to, target_engine)}
      {:error, reason} -> 
        {:error, {:engine_error, target_engine, reason}}
    end
  end
end
```

### 3.2 SimpleConversation

Handles straightforward queries without complex reasoning:

```elixir
# Characteristics:
- Direct factual questions
- Simple code explanations
- Quick lookups
- Basic conversions

# Example queries:
- "What is pattern matching?"
- "Convert this timestamp to ISO format"
- "What's the syntax for a GenServer?"
```

### 3.3 ComplexConversation

Uses Chain-of-Thought for multi-step reasoning:

```elixir
# Characteristics:
- Complex problem solving
- Architectural decisions
- Multi-faceted analysis
- Deep reasoning required

# Example queries:
- "Design a distributed cache with eventual consistency"
- "How should I structure a multi-tenant Phoenix application?"
- "Explain the trade-offs between different state management approaches"
```

### 3.4 AnalysisConversation

Specialized for code review and analysis:

```elixir
# Characteristics:
- Code quality assessment
- Performance analysis
- Security review
- Best practices evaluation

# Example queries:
- "Review this GenServer for potential issues"
- "Analyze the performance bottlenecks in this code"
- "Check for security vulnerabilities"
```

### 3.5 GenerationConversation

Handles code generation with planning:

```elixir
# Characteristics:
- Code scaffolding
- Implementation planning
- API design
- Feature development

# Example queries:
- "Generate a REST API for user management"
- "Create a GenServer for rate limiting"
- "Implement a binary search tree"
```

### 3.6 ProblemSolver

Debugging and troubleshooting specialist:

```elixir
# Characteristics:
- Error diagnosis
- Root cause analysis
- Solution proposals
- Fix verification

# Example queries:
- "My GenServer keeps timing out"
- "Why is this pattern match failing?"
- "Debug this memory leak issue"
```

### 3.7 MultiStepConversation

Maintains context across multiple exchanges:

```elixir
# Characteristics:
- Follow-up questions
- Iterative refinement
- Context-aware responses
- Conversation continuity

# Example interaction:
User: "Create a user authentication system"
AI: [provides implementation]
User: "Now add password reset functionality"
AI: [builds on previous context]
```

## 4. ConversationChannel {#conversation-channel}

The ConversationChannel provides the WebSocket interface:

### 4.1 Channel Setup

```elixir
defmodule RubberDuckWeb.ConversationChannel do
  use RubberDuckWeb, :channel
  
  def join("conversation:" <> conversation_id, params, socket) do
    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:messages, [])
      |> assign(:context, %{})
      |> assign(:session_id, generate_session_id())
    
    {:ok, %{session_id: socket.assigns.session_id}, socket}
  end
end
```

### 4.2 Message Handling

```elixir
def handle_in("message", %{"content" => content} = params, socket) do
  # Send thinking indicator
  push(socket, "thinking", %{})
  
  # Build input for router
  input = %{
    query: content,
    context: build_context(socket, params),
    options: Map.get(params, "options", %{}),
    llm_config: build_llm_config(socket, params)
  }
  
  # Process through conversation router
  case EngineManager.execute(:conversation_router, input, @timeout) do
    {:ok, result} ->
      push(socket, "response", format_response(result))
      {:noreply, update_conversation_state(socket, result)}
      
    {:error, reason} ->
      push(socket, "error", format_error(reason))
      {:noreply, socket}
  end
end
```

### 4.3 Session Management

```elixir
# Start new conversation
handle_in("new_conversation", _params, socket)

# Update context
handle_in("set_context", %{"context" => context}, socket)

# Typing indicators
handle_in("typing", %{"typing" => typing}, socket)
```

## 5. Question Classification and Routing {#routing}

### 5.1 Classification Logic

```elixir
defp classify_query(query, context) do
  query_lower = String.downcase(query)
  
  cond do
    # Analysis patterns
    contains_any?(query_lower, ["analyze", "review", "check", "audit"]) ->
      :analysis
      
    # Generation patterns
    contains_any?(query_lower, ["generate", "create", "implement", "build"]) ->
      :generation
      
    # Problem solving patterns
    contains_any?(query_lower, ["debug", "fix", "error", "issue", "problem"]) ->
      :problem_solving
      
    # Multi-step detection
    has_conversation_history?(context) ->
      :multi_step
      
    # Complexity assessment
    is_complex_query?(query, context) ->
      :complex
      
    # Default to simple
    true ->
      :simple
  end
end
```

### 5.2 Engine Selection

```elixir
defp select_engine(query_type) do
  case query_type do
    :simple -> :simple_conversation
    :complex -> :complex_conversation
    :analysis -> :analysis_conversation
    :generation -> :generation_conversation
    :problem_solving -> :problem_solver
    :multi_step -> :multi_step_conversation
  end
end
```

## 6. Integration with CoT {#cot-integration}

Complex conversation engines leverage Chain-of-Thought reasoning:

### 6.1 ComplexConversation with CoT

```elixir
defmodule RubberDuck.Engines.Conversation.ComplexConversation do
  def execute(input, state) do
    # Build CoT context
    cot_context = %{
      context: input.context,
      llm_config: build_llm_config(input, state),
      user_id: input.context[:user_id],
      session_id: input.context[:session_id]
    }
    
    # Execute ConversationChain with multi-step reasoning
    case ConversationManager.execute_chain(
      ConversationChain, 
      input.query, 
      cot_context
    ) do
      {:ok, result} -> format_complex_response(result)
      {:error, reason} -> handle_cot_error(reason)
    end
  end
end
```

### 6.2 Available CoT Chains

```elixir
# ConversationChain - General multi-step reasoning
# AnalysisChain - Code analysis with systematic review
# GenerationChain - Code generation with planning
# ProblemSolverChain - Debugging with root cause analysis
# LightweightConversationChain - Optimized for simple multi-turn
```

## 7. Session and Context Management {#session-management}

### 7.1 Context Building

```elixir
defp build_context(socket, params) do
  %{
    # User and session info
    user_id: socket.assigns.user_id,
    session_id: socket.assigns.session_id,
    conversation_id: socket.assigns.conversation_id,
    
    # Conversation history
    messages: format_messages_for_context(socket.assigns.messages),
    message_count: length(socket.assigns.messages),
    
    # Custom context
    custom_context: socket.assigns.context,
    preferences: socket.assigns.preferences,
    
    # Request-specific context
    timestamp: DateTime.utc_now()
  }
  |> Map.merge(Map.get(params, "context", %{}))
end
```

### 7.2 Message History

```elixir
defp add_message(messages, new_message) do
  # Keep conversation history manageable
  (messages ++ [new_message])
  |> Enum.take(-@max_context_messages)
end

defp format_messages_for_context(messages) do
  messages
  |> Enum.map(fn msg ->
    %{
      role: msg.role,
      content: msg.content,
      timestamp: msg.timestamp
    }
  end)
end
```

## 8. Client Integration {#client-integration}

### 8.1 JavaScript Client

```javascript
import { Socket } from "phoenix"

class ConversationClient {
  constructor(endpoint, apiKey) {
    this.socket = new Socket(endpoint, {
      params: { api_key: apiKey }
    })
    this.channel = null
  }
  
  connect() {
    this.socket.connect()
    this.channel = this.socket.channel("conversation:unique_id")
    
    // Set up event handlers
    this.channel.on("response", this.handleResponse)
    this.channel.on("thinking", this.handleThinking)
    this.channel.on("error", this.handleError)
    
    return this.channel.join()
  }
  
  sendMessage(content, options = {}) {
    return this.channel.push("message", {
      content: content,
      context: options.context || {},
      options: options.options || {},
      llm_config: options.llm_config || {}
    })
  }
}
```

### 8.2 Elixir Client

```elixir
defmodule MyApp.ConversationClient do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def send_message(content, opts \\ []) do
    GenServer.call(__MODULE__, {:send_message, content, opts})
  end
  
  # Direct engine usage
  def ask_question(query, context \\ %{}) do
    input = %{
      query: query,
      context: context,
      options: %{},
      llm_config: %{}
    }
    
    RubberDuck.Engine.Manager.execute(
      :conversation_router, 
      input, 
      30_000
    )
  end
end
```

## 9. Examples and Use Cases {#examples}

### 9.1 Simple Query Flow

```elixir
# User asks a simple question
User: "What is GenServer?"

# Flow:
1. ConversationChannel receives message
2. Routes to ConversationRouter
3. Classified as :simple
4. Routed to SimpleConversation
5. Direct LLM call for quick response
6. Response sent back via channel

# Response includes:
- Quick explanation
- Basic example
- No complex reasoning needed
```

### 9.2 Complex Problem Solving

```elixir
# User asks complex question
User: "Design a fault-tolerant distributed task queue"

# Flow:
1. ConversationChannel receives message
2. Routes to ConversationRouter
3. Classified as :complex
4. Routed to ComplexConversation
5. Uses ConversationChain with CoT:
   - understand_requirements
   - analyze_constraints
   - design_architecture
   - implementation_details
   - scalability_considerations
6. Comprehensive response with reasoning

# Response includes:
- Step-by-step design process
- Architecture decisions
- Implementation considerations
- Trade-offs explained
```

### 9.3 Multi-turn Conversation

```elixir
# Turn 1
User: "Create a rate limiter"
AI: [provides basic implementation]

# Turn 2
User: "Add Redis support"
AI: [extends previous implementation with Redis]

# Turn 3
User: "How can I make it distributed?"
AI: [builds on context, suggests distributed strategies]

# Flow:
- Each turn maintains context
- MultiStepConversation engine handles continuity
- Previous code and decisions preserved
- Coherent progression through the conversation
```

### 9.4 Code Analysis Session

```elixir
# User requests analysis
User: "Review this code for issues"
Code: [paste GenServer implementation]

# Flow:
1. Routes to AnalysisConversation
2. Uses AnalysisChain with steps:
   - syntax_check
   - pattern_analysis
   - performance_review
   - security_audit
   - best_practices
3. Structured analysis report

# Response includes:
- Identified issues with severity
- Specific recommendations
- Code improvement suggestions
- Performance optimization tips
```

## 10. Best Practices {#best-practices}

### 10.1 Engine Design

```elixir
# Good: Single responsibility
defmodule SimpleConversation do
  # Handles only simple, direct queries
  # Fast response times
  # No complex reasoning
end

# Good: Clear capability definition
def capabilities do
  [:simple_questions, :factual_queries, :basic_code, :quick_reference]
end
```

### 10.2 Context Management

```elixir
# Limit context size
@max_context_messages 20

# Include only relevant context
defp build_relevant_context(messages, current_query) do
  messages
  |> filter_relevant_messages(current_query)
  |> summarize_old_messages()
  |> take_recent_messages()
end
```

### 10.3 Error Handling

```elixir
# Graceful degradation
case EngineManager.execute(preferred_engine, input, timeout) do
  {:ok, result} -> 
    {:ok, result}
  {:error, :timeout} -> 
    # Try simpler engine
    EngineManager.execute(:simple_conversation, input, timeout)
  {:error, reason} -> 
    # Provide helpful error message
    {:error, format_user_friendly_error(reason)}
end
```

### 10.4 Performance Optimization

```elixir
# Cache common queries
defmodule ConversationCache do
  use GenServer
  
  def get_or_compute(query, context, fun) do
    cache_key = generate_key(query, context)
    
    case :ets.lookup(@table, cache_key) do
      [{^cache_key, result, expiry}] when expiry > now() ->
        {:ok, result}
      _ ->
        result = fun.()
        cache_result(cache_key, result)
        result
    end
  end
end
```

## 11. Troubleshooting {#troubleshooting}

### 11.1 Common Issues

**Routing Errors**
```elixir
# Issue: Wrong engine selected
# Solution: Check classification logic
Logger.debug("Query classified as: #{query_type}")
Logger.debug("Routed to: #{target_engine}")
```

**Context Overflow**
```elixir
# Issue: Too much context causing errors
# Solution: Implement context summarization
defp summarize_if_needed(messages) when length(messages) > 50 do
  recent = Enum.take(messages, -10)
  summary = summarize_older_messages(messages)
  [summary | recent]
end
```

**Timeout Issues**
```elixir
# Issue: Complex queries timing out
# Solution: Adjust timeouts per engine
config :simple_conversation, timeout: 15_000
config :complex_conversation, timeout: 60_000
```

### 11.2 Debugging Tools

```elixir
# Enable conversation tracing
ConversationChannel.enable_tracing(conversation_id)

# Inspect routing decisions
{:ok, trace} = ConversationRouter.explain_routing(query, context)

# Monitor engine performance
:telemetry.attach("conversation-metrics", 
  [:conversation, :engine, :execute], 
  &handle_metrics/4,
  nil
)
```

### 11.3 Testing Conversations

```elixir
defmodule ConversationTest do
  use ExUnit.Case
  
  test "complex query routes correctly" do
    input = %{
      query: "Design a distributed system",
      context: %{}
    }
    
    assert {:ok, result} = 
      EngineManager.execute(:conversation_router, input, 30_000)
    assert result.routed_to == :complex_conversation
  end
  
  test "maintains context across messages" do
    # Test multi-turn conversation
    # Verify context preservation
    # Check response coherence
  end
end
```

## Conclusion

The RubberDuck Conversation AI system provides a robust, scalable foundation for intelligent conversational interactions. By separating concerns into specialized engines and using intelligent routing, the system can handle diverse conversation patterns while maintaining high performance and reliability.

Key takeaways:
- Use ConversationRouter as the entry point
- Let the system classify and route queries automatically
- Leverage specialized engines for optimal results
- Maintain context for coherent multi-turn conversations
- Monitor and optimize based on usage patterns

The architecture's extensibility ensures new conversation patterns can be easily added as requirements evolve.