# Conversational AI System Design for Elixir Coding Assistant

## System Architecture for Memory-Enhanced Conversational AI

Based on extensive research into production Elixir systems and architectural patterns, here's a comprehensive design for your conversational/chat system that integrates with your existing Elixir infrastructure and 3-tier memory system.

### 1. Memory-Enhanced Conversational Engine

The research reveals several proven patterns for integrating conversational AI with your 3-tier memory system. [Discord's architecture handling 5M+ concurrent users](https://discord.com/blog/how-discord-scaled-elixir-to-5-000-000-concurrent-users) demonstrates that [ETS provides microsecond-level access times when properly configured](https://blog.appsignal.com/2019/11/12/caching-with-elixir-and-ets.html).

**Core Architecture Pattern:**
```elixir
defmodule RubberDuck.Conversation.Engine do
  use GenServer
  
  def start_link(conversation_id) do
    GenServer.start_link(__MODULE__, conversation_id, 
      name: {:via, Registry, {RubberDuck.ConversationRegistry, conversation_id}})
  end
  
  def init(conversation_id) do
    {:ok, %{
      conversation_id: conversation_id,
      short_term: init_ets_cache(conversation_id),
      context_window: [],
      last_activity: System.monotonic_time(:second),
      memory_manager: RubberDuck.Memory.Manager
    }}
  end
  
  defp init_ets_cache(conversation_id) do
    :ets.new(:"conv_#{conversation_id}", [
      :set, :public, :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end
  
  def handle_call({:add_message, message}, _from, state) do
    # Store in short-term memory (ETS)
    :ets.insert(state.short_term, {System.system_time(:millisecond), message})
    
    # Update context window with relevance scoring
    updated_context = update_context_window(state.context_window, message, state.memory_manager)
    
    # Trigger pattern extraction if needed
    maybe_extract_patterns(state)
    
    {:reply, :ok, %{state | context_window: updated_context, last_activity: System.monotonic_time(:second)}}
  end
  
  def handle_call({:get_context, query_type}, _from, state) do
    context = build_conversation_context(state, query_type)
    {:reply, context, state}
  end
  
  defp build_conversation_context(state, query_type) do
    %{
      recent_messages: get_recent_messages(state.short_term),
      relevant_patterns: get_relevant_patterns(state.memory_manager, query_type),
      context_window: state.context_window,
      conversation_id: state.conversation_id
    }
  end
end
```

**[Context Window Optimization Strategy](https://www.techtarget.com/whatis/definition/context-window):**
- Implement token-aware context management with dynamic prioritization
- Use [sliding window with relevance scoring](https://stackoverflow.com/questions/51446662/sliding-window-over-a-list-in-elixir) for memory retrieval
- [Leverage pgvector for semantic similarity search](https://revelry.co/insights/open-source-semantic-vector-search-with-instructor-pgvector-and-flask/) in PostgreSQL
- Apply [ETS management patterns](https://blog.jola.dev/patterns-for-managing-ets-tables) for performance-critical operations

**Pattern Extraction Pipeline:**
```elixir
defmodule RubberDuck.Conversation.PatternExtractor do
  use GenServer
  
  @window_size 50
  @extraction_interval 300_000  # 5 minutes
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    schedule_extraction()
    {:ok, %{window_buffer: [], patterns: %{}}}
  end
  
  def handle_info(:extract_patterns, state) do
    patterns = state.window_buffer
    |> extract_patterns_from_buffer()
    |> merge_with_existing_patterns(state.patterns)
    
    # Persist significant patterns to mid-term storage
    persist_to_mid_term_storage(patterns)
    
    schedule_extraction()
    {:noreply, %{state | patterns: patterns, window_buffer: []}}
  end
  
  def handle_cast({:add_to_buffer, message}, state) do
    updated_buffer = [message | state.window_buffer]
    |> Enum.take(@window_size)
    
    {:noreply, %{state | window_buffer: updated_buffer}}
  end
  
  defp extract_patterns_from_buffer(buffer) do
    buffer
    |> Enum.group_by(&extract_intent/1)
    |> Enum.map(fn {intent, messages} ->
      {intent, %{
        frequency: length(messages),
        last_seen: System.system_time(:second),
        examples: Enum.take(messages, 3)
      }}
    end)
    |> Map.new()
  end
  
  defp schedule_extraction do
    Process.send_after(self(), :extract_patterns, @extraction_interval)
  end
end
```

### 2. Multi-Client Phoenix Channel Architecture

Research shows Phoenix Channels efficiently handle heterogeneous clients through [**topic-based routing**](https://hexdocs.pm/phoenix/channels.html) and **client capability detection**.

**Channel Design Pattern:**
```elixir
defmodule RubberDuckWeb.ConversationChannel do
  use Phoenix.Channel
  
  def join("conversation:" <> conv_id, %{"client_type" => type, "capabilities" => caps}, socket) do
    socket = socket
    |> assign(:client_type, type)
    |> assign(:capabilities, caps)
    |> assign(:conversation_id, conv_id)
    
    # Start or connect to conversation engine
    case RubberDuck.Conversation.Engine.start_conversation(conv_id) do
      {:ok, _pid} -> configure_client(socket, type)
      {:error, {:already_started, _pid}} -> configure_client(socket, type)
      error -> error
    end
  end
  
  def handle_in("message", %{"content" => content, "type" => msg_type}, socket) do
    conv_id = socket.assigns.conversation_id
    
    message = %{
      content: content,
      type: msg_type,
      client_type: socket.assigns.client_type,
      timestamp: System.system_time(:millisecond)
    }
    
    # Add to conversation engine
    RubberDuck.Conversation.Engine.add_message(conv_id, message)
    
    # Process based on message type
    response = case msg_type do
      "command" -> process_command(content, socket)
      "chat" -> process_chat(content, conv_id, socket)
      "mixed" -> process_mixed_input(content, conv_id, socket)
    end
    
    broadcast_response(socket, response)
    {:noreply, socket}
  end
  
  def handle_out("response", msg, socket) do
    formatted_msg = format_for_client(msg, socket.assigns.client_type)
    push(socket, "response", formatted_msg)
    {:noreply, socket}
  end
  
  defp configure_client(socket, type) do
    case type do
      "cli" -> {:ok, assign(socket, :format, "text")}
      "liveview" -> {:ok, assign(socket, :format, "html")}
      "tui" -> {:ok, assign(socket, :format, "ansi")}
      "websocket" -> {:ok, assign(socket, :format, "json")}
      _ -> {:error, %{reason: "unsupported_client_type"}}
    end
  end
  
  defp process_chat(content, conv_id, socket) do
    # Get conversation context
    context = RubberDuck.Conversation.Engine.get_context(conv_id, :chat)
    
    # Process with LLM using enhanced context
    case RubberDuck.LLM.Service.chat_completion(%{
      messages: [%{role: "user", content: content}],
      context: context,
      enhancement_techniques: [:cot, :rag]
    }) do
      {:ok, response} -> 
        %{type: "chat_response", content: response.content, streaming: false}
      {:error, reason} -> 
        %{type: "error", content: "Chat processing failed: #{reason}"}
    end
  end
end
```

**[Shared Communication Protocol](https://strongwing.studio/2018/07/07/setting-up-phoenix-channels-to-use-messagepack-for-serialization/):**
- [Use MessagePack for binary serialization](https://github.com/phoenixframework/phoenix/issues/810) (50-90% size reduction)
- [Implement version negotiation](https://hexdocs.pm/phoenix/writing_a_channels_client.html) via `vsn` parameter
- Support graceful degradation for limited clients

### 3. Conversational Context Management

**[State Management with GenServer](https://dev.to/_areichert/learning-elixir-s-genserver-with-a-real-world-example-5fef) Supervision:**
```elixir
defmodule RubberDuck.Conversation.Supervisor do
  use DynamicSupervisor
  
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  def start_conversation(conversation_id, initial_state \\ %{}) do
    child_spec = %{
      id: {RubberDuck.Conversation.Engine, conversation_id},
      start: {RubberDuck.Conversation.Engine, :start_link, [conversation_id, initial_state]},
      restart: :temporary,
      shutdown: 5_000
    }
    
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def stop_conversation(conversation_id) do
    case Registry.lookup(RubberDuck.ConversationRegistry, conversation_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
end
```

**[Memory Integration with ETS](https://elixirschool.com/en/lessons/storage/ets) Patterns:**
```elixir
defmodule RubberDuck.Conversation.MemoryBridge do
  @moduledoc """
  Bridge between conversation engine and the 3-tier memory system
  """
  
  def store_interaction(conversation_id, interaction) do
    # Short-term: Store in conversation ETS table
    :ets.insert(:"conv_#{conversation_id}", {
      interaction.timestamp,
      interaction
    })
    
    # Mid-term: Add to pattern extraction buffer
    GenServer.cast(RubberDuck.Conversation.PatternExtractor, {:add_to_buffer, interaction})
    
    # Long-term: Store significant interactions in PostgreSQL via Memory Manager
    if significant_interaction?(interaction) do
      RubberDuck.Memory.Manager.store_interaction(interaction)
    end
  end
  
  def retrieve_context(conversation_id, query_type, limit \\ 20) do
    # Get recent from ETS
    recent = get_recent_from_ets(conversation_id, limit)
    
    # Get relevant patterns from mid-term
    patterns = RubberDuck.Memory.Manager.get_relevant_patterns(query_type)
    
    # Get long-term context if needed
    long_term = if complex_query?(query_type) do
      RubberDuck.Memory.Manager.retrieve_similar_contexts(query_type)
    else
      []
    end
    
    %{
      recent: recent,
      patterns: patterns,
      long_term: long_term,
      conversation_id: conversation_id
    }
  end
  
  defp get_recent_from_ets(conversation_id, limit) do
    :"conv_#{conversation_id}"
    |> :ets.tab2list()
    |> Enum.sort_by(fn {timestamp, _} -> timestamp end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_, interaction} -> interaction end)
  end
end
```

**[Reconnection Handling with Phoenix Presence](https://hexdocs.pm/phoenix/Phoenix.Presence.html):**
```elixir
defmodule RubberDuck.ConversationPresence do
  use Phoenix.Presence,
    otp_app: :rubber_duck,
    pubsub_server: RubberDuck.PubSub
    
  def track_user_conversation(socket, user_id, conversation_id) do
    Presence.track(socket, user_id, %{
      conversation_id: conversation_id,
      connected_at: System.system_time(:second),
      client_type: socket.assigns.client_type,
      capabilities: socket.assigns.capabilities
    })
  end
  
  def get_conversation_participants(conversation_id) do
    "conversation:#{conversation_id}"
    |> Presence.list()
    |> Enum.map(fn {user_id, %{metas: [meta | _]}} ->
      %{user_id: user_id, client_type: meta.client_type, connected_at: meta.connected_at}
    end)
  end
end
```

**State Recovery Pattern:**
```elixir
defmodule RubberDuck.Conversation.Recovery do
  def recover_on_reconnect(conversation_id, user_id) do
    with {:ok, last_snapshot} <- load_conversation_snapshot(conversation_id),
         {:ok, missed_events} <- load_events_since(last_snapshot.timestamp),
         {:ok, recovered_state} <- rebuild_conversation_state(last_snapshot, missed_events) do
      
      # Restore conversation engine state
      RubberDuck.Conversation.Engine.restore_state(conversation_id, recovered_state)
    else
      {:error, :not_found} -> 
        # Start fresh conversation
        RubberDuck.Conversation.Supervisor.start_conversation(conversation_id)
      error -> error
    end
  end
  
  defp load_conversation_snapshot(conversation_id) do
    # Load from PostgreSQL via Ash
    RubberDuck.Workspace.ConversationSnapshot
    |> Ash.Query.filter(conversation_id == ^conversation_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one()
  end
end
```

### 4. Command-Chat Hybrid Interface

**Intent Classification with Context:**
```elixir
defmodule RubberDuck.Conversation.HybridInterface do
  @command_patterns [
    {~r/^\/analyze\s+(.+)/, :analyze},
    {~r/^\/generate\s+(.+)/, :generate},
    {~r/^\/complete\s+(.+)/, :complete},
    {~r/^\/refactor\s+(.+)/, :refactor}
  ]
  
  def process_input(input, conversation_context) do
    case classify_intent(input, conversation_context) do
      {:command, command_type, args} ->
        execute_command(command_type, args, conversation_context)
        
      {:natural_language, text} ->
        process_with_llm(text, conversation_context)
        
      {:mixed, command_parts, chat_parts} ->
        handle_mixed_input(command_parts, chat_parts, conversation_context)
    end
  end
  
  defp classify_intent(input, context) do
    cond do
      command_match = find_command_pattern(input) ->
        {:command, command_match.type, command_match.args}
        
      contains_command_keywords?(input) ->
        extract_mixed_intent(input, context)
        
      true ->
        {:natural_language, input}
    end
  end
  
  defp find_command_pattern(input) do
    Enum.find_value(@command_patterns, fn {pattern, type} ->
      case Regex.run(pattern, input) do
        [_, args] -> %{type: type, args: args}
        nil -> nil
      end
    end)
  end
  
  defp extract_mixed_intent(input, context) do
    # Use LLM to parse mixed command/chat input
    case RubberDuck.LLM.Service.analyze_intent(%{
      text: input,
      context: context,
      available_commands: get_available_commands(context)
    }) do
      {:ok, %{type: "mixed", command_parts: cmd, chat_parts: chat}} ->
        {:mixed, cmd, chat}
      {:ok, %{type: "command", extracted: cmd}} ->
        {:command, cmd.type, cmd.args}
      _ ->
        {:natural_language, input}
    end
  end
  
  defp execute_command(command_type, args, context) do
    # Delegate to the unified command processor
    RubberDuck.Commands.Processor.execute(%{
      type: command_type,
      args: parse_command_args(args),
      context: context
    })
  end
end
```

**Command Suggestion Engine:**
```elixir
defmodule RubberDuck.Conversation.CommandSuggester do
  def generate_suggestions(partial_input, conversation_context) do
    available_commands = get_available_commands(conversation_context)
    
    suggestions = available_commands
    |> filter_by_prefix(partial_input)
    |> score_by_context_relevance(conversation_context)
    |> sort_by_score()
    |> limit(5)
    
    %{
      suggestions: suggestions,
      partial_input: partial_input,
      context_relevant: length(suggestions) > 0
    }
  end
  
  defp filter_by_prefix(commands, prefix) do
    prefix_clean = String.trim_leading(prefix, "/")
    
    Enum.filter(commands, fn cmd ->
      String.starts_with?(cmd.name, prefix_clean)
    end)
  end
  
  defp score_by_context_relevance(commands, context) do
    Enum.map(commands, fn cmd ->
      relevance_score = calculate_relevance(cmd, context)
      Map.put(cmd, :score, relevance_score)
    end)
  end
  
  defp calculate_relevance(command, context) do
    base_score = 1.0
    
    # Boost score based on recent usage
    recent_usage_boost = if recently_used?(command, context), do: 0.5, else: 0.0
    
    # Boost score based on current project context
    project_relevance_boost = if relevant_to_project?(command, context.project_id), do: 0.3, else: 0.0
    
    base_score + recent_usage_boost + project_relevance_boost
  end
end
```

## Implementation Recommendations

### Architecture Overview

1. **Process Architecture**
   - Use Registry for conversation process tracking
   - Implement process-per-conversation pattern for isolation
   - Use DynamicSupervisor for conversation lifecycle management

2. **Memory Optimization**
   - [Configure ETS with read/write concurrency flags](https://dockyard.com/blog/2017/05/19/optimizing-elixir-and-phoenix-with-ets)
   - Implement tiered memory compaction every 10 minutes
   - [Use pgvector indexes for semantic search](https://github.com/pgvector/pgvector-elixir) (HNSW algorithm)

3. **Performance Targets**
   - Sub-100ms conversation response latency
   - Support 1K+ concurrent conversations per node
   - Efficient memory usage with automatic cleanup

4. **Security Measures**
   - [Token-based authentication](https://dev.to/hexshift/locking-the-gate-secure-and-scalable-api-authentication-in-phoenix-2m9c) for all client types
   - [Rate limiting with Hammer](https://paraxial.io/blog/auth-rate-limit) (100 requests/hour per user)
   - Conversation data encryption at rest using AES-256-GCM

### Integration Points

**With Existing Components:**
- **[Ash Framework](https://hexdocs.pm/ash/what-is-ash.html)**: Store conversation snapshots and long-term memory
- **[Reactor](https://hexdocs.pm/reactor/getting-started-with-reactor.html)**: Trigger workflows from conversational context
- **LLM Service**: Enhanced context building with memory integration
- **Memory Manager**: [Seamless integration via GenServer messaging](https://hexdocs.pm/elixir/1.12/GenServer.html)

**Monitoring Strategy:**
- Track conversation metrics via Telemetry
- Monitor ETS memory usage and hit rates
- Implement circuit breakers for external services
- Use :observer for runtime introspection

### Testing Approach

1. **[Channel Testing](https://hexdocs.pm/phoenix/Phoenix.ChannelTest.html)**: Use Phoenix.ChannelTest for integration tests
2. **[Load Testing](https://github.com/phoenixframework/phoenix/issues/1285)**: Test concurrent WebSocket connections
3. **Property Testing**: Use StreamData for conversation flow properties
4. **Memory Profiling**: Regular profiling with :observer and custom metrics

This architecture leverages Elixir's strengths while learning from production systems and proven patterns from the community. The design ensures scalability, fault tolerance, and maintainability while supporting your multi-client requirements and integrating seamlessly with your existing 3-tier memory system.
