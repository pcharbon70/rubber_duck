# Conversation Channel Documentation

The conversation channel provides a WebSocket-based interface for real-time AI conversations with context management and intelligent routing.

## Overview

The conversation channel (`conversation:*`) enables:
- Real-time conversational AI interactions
- Context preservation across messages
- Automatic routing to specialized engines
- Session and conversation management
- Typing indicators and status updates

## Connection

### JavaScript Client

```javascript
import { Socket } from "phoenix"

const socket = new Socket("/socket", {
  params: { api_key: "your_api_key" }
})

socket.connect()

const channel = socket.channel("conversation:unique_id", {
  user_id: "optional_user_id",
  preferences: {
    temperature: 0.7,
    max_tokens: 2000
  }
})

channel.join()
  .receive("ok", resp => console.log("Joined", resp))
  .receive("error", resp => console.log("Failed to join", resp))
```

## Message Types

### Outgoing (Client → Server)

#### `message`
Send a message in the conversation.

```javascript
channel.push("message", {
  content: "How do I implement a GenServer?",
  context: {
    skill_level: "beginner",
    language: "elixir"
  },
  options: {
    include_examples: true
  },
  llm_config: {
    temperature: 0.8,
    max_tokens: 3000
  }
})
```

#### `new_conversation`
Start a fresh conversation, clearing all context.

```javascript
channel.push("new_conversation", {})
```

#### `set_context`
Update the conversation context.

```javascript
channel.push("set_context", {
  context: {
    project_type: "phoenix",
    database: "postgresql",
    deployment: "kubernetes"
  }
})
```

#### `typing`
Send typing indicator.

```javascript
channel.push("typing", { typing: true })
```

### Incoming (Server → Client)

#### `response`
AI response to a message.

```javascript
channel.on("response", response => {
  console.log("Query:", response.query)
  console.log("Response:", response.response)
  console.log("Type:", response.conversation_type)
  console.log("Routed to:", response.routed_to)
  console.log("Metadata:", response.metadata)
})
```

Response structure:
```javascript
{
  query: "Original user query",
  response: "AI response text",
  conversation_type: "simple|complex|analysis|generation|problem_solving|multi_step",
  routed_to: "engine_name",
  timestamp: "2024-01-15T10:30:00Z",
  metadata: {
    processing_time: 1234,
    model_used: "gpt-4",
    steps: [...],
    analysis_points: [...],
    recommendations: [...],
    generated_code: "...",
    implementation_plan: [...],
    root_cause: "..."
  }
}
```

#### `thinking`
Indicates AI is processing the request.

```javascript
channel.on("thinking", () => {
  showLoadingIndicator()
})
```

#### `error`
Error occurred during processing.

```javascript
channel.on("error", error => {
  console.error("Error:", error.message)
  console.error("Details:", error.details)
})
```

#### `conversation_reset`
Confirmation that conversation was reset.

```javascript
channel.on("conversation_reset", data => {
  console.log("New session ID:", data.session_id)
})
```

#### `context_updated`
Confirmation that context was updated.

```javascript
channel.on("context_updated", data => {
  console.log("Updated context:", data.context)
})
```

## Conversation Flow

1. **User sends message** → ConversationChannel receives it
2. **Channel sends to ConversationRouter** → Classifies query type
3. **Router selects appropriate engine**:
   - SimpleConversation: Basic queries
   - ComplexConversation: Complex reasoning with CoT
   - AnalysisConversation: Code analysis
   - GenerationConversation: Code generation
   - ProblemSolver: Debugging help
   - MultiStepConversation: Context-aware follow-ups
4. **Engine processes query** → May use CoT chains
5. **Response sent back** → With metadata about processing

## Example Conversations

### Simple Query
```javascript
// User
channel.push("message", {
  content: "What is pattern matching in Elixir?"
})

// Response
{
  response: "Pattern matching in Elixir is a powerful feature that allows you to match against data structures...",
  conversation_type: "simple",
  routed_to: "simple_conversation"
}
```

### Code Generation
```javascript
// User
channel.push("message", {
  content: "Generate a GenServer that manages a shopping cart"
})

// Response
{
  response: "Here's a GenServer implementation for a shopping cart...",
  conversation_type: "generation",
  routed_to: "generation_conversation",
  metadata: {
    generated_code: "defmodule ShoppingCart do\n  use GenServer\n  ...",
    implementation_plan: [
      "Define the GenServer module",
      "Implement init/1 callback",
      "Add API functions",
      "Implement callbacks"
    ]
  }
}
```

### Multi-turn Conversation
```javascript
// Turn 1
channel.push("message", {
  content: "What's the difference between Task and GenServer?"
})

// Turn 2 (with context)
channel.push("message", {
  content: "When should I use each one?"
})

// Response includes context from previous messages
{
  response: "Based on our previous discussion about Task and GenServer, here's when to use each...",
  conversation_type: "multi_step",
  routed_to: "multi_step_conversation"
}
```

### Problem Solving
```javascript
// User
channel.push("message", {
  content: "My GenServer keeps crashing with a timeout error",
  context: {
    error_message: "** (exit) exited in: GenServer.call(..., 5000)"
  }
})

// Response
{
  response: "Let's debug this timeout issue step by step...",
  conversation_type: "problem_solving",
  routed_to: "problem_solver",
  metadata: {
    root_cause: "The GenServer is likely blocked by a long-running operation",
    solution_steps: [
      "Check if handle_call is doing heavy computation",
      "Consider using handle_cast for fire-and-forget operations",
      "Implement timeouts in external API calls"
    ]
  }
}
```

## Best Practices

1. **Maintain Context**: Use `set_context` to provide project-specific information
2. **Clear Conversations**: Use `new_conversation` when switching topics
3. **Handle Errors**: Always implement error handlers
4. **Show Loading States**: Use the `thinking` event to show progress
5. **Limit Message Size**: Keep messages under 4000 characters
6. **Rate Limiting**: Implement client-side throttling to avoid overload

## Advanced Usage

### Custom LLM Configuration
```javascript
channel.push("message", {
  content: "Explain this code",
  llm_config: {
    model: "gpt-4",
    temperature: 0.2,  // Lower for more focused responses
    max_tokens: 4000,
    top_p: 0.9
  }
})
```

### Conversation Preferences
```javascript
const channel = socket.channel("conversation:123", {
  preferences: {
    response_style: "concise",
    include_sources: true,
    language: "en",
    timezone: "America/New_York"
  }
})
```

### Session Management
The channel automatically manages sessions and maintains conversation history. Each conversation has:
- `conversation_id`: Unique identifier for the conversation
- `session_id`: Unique session within the conversation
- `user_id`: Authenticated user identifier

## Security Considerations

1. **Authentication**: Always provide valid API key or token
2. **Input Validation**: The server validates all inputs
3. **Rate Limiting**: Implemented server-side
4. **Context Isolation**: Each conversation is isolated
5. **No Code Execution**: The AI only generates code, never executes it