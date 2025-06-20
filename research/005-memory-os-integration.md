# MemoryOS Integration for Distributed AI Assistant

## Overview

This document outlines the integration of MemoryOS principles into the distributed AI coding assistant, focusing on improving LLM context retention and engine efficiency. The implementation leverages the existing distributed infrastructure (Mnesia, Horde, Syn) while maintaining single-node optimization.

## Architecture Design

### 1. Core Memory Domain Structure

```elixir
defmodule AiAssistant.Memory do
  @moduledoc """
  MemoryOS domain for managing hierarchical conversation memory
  """
  
  defmodule Config do
    @moduledoc "Memory system configuration"
    
    defstruct [
      enabled: true,
      stm_capacity: 7,
      mtm_max_segments: 200,
      lpm_kb_capacity: 100,
      lpm_traits_capacity: 100,
      fscore_threshold: 0.6,
      heat_threshold: 5.0,
      heat_coefficients: %{alpha: 1.0, beta: 1.0, gamma: 1.0},
      time_constant: 1.0e7,
      top_m_segments: 5,
      top_k_pages: 5,
      top_lpm_entries: 10
    ]
  end
end
```

### 2. Mnesia Schema Extensions

```elixir
# Short-Term Memory (STM)
defmodule AiAssistant.Memory.Schema.DialoguePage do
  defstruct [
    :id,
    :session_id,
    :query,
    :response,
    :timestamp,
    :embedding,        # Vector embedding for semantic search
    :dialogue_chain,   # Reference to chain metadata
    :keywords,         # Extracted keywords for Jaccard similarity
    :created_at
  ]
end

# Mid-Term Memory (MTM)
defmodule AiAssistant.Memory.Schema.DialogueSegment do
  defstruct [
    :id,
    :session_id,
    :topic_summary,    # LLM-generated summary
    :page_ids,         # List of DialoguePage IDs
    :embedding,        # Segment embedding vector
    :keywords,         # Segment keywords
    :heat_score,       # Calculated heat metric
    :n_visit,          # Retrieval count
    :l_interaction,    # Number of pages
    :last_accessed,    # For recency calculation
    :created_at,
    :updated_at
  ]
end

# Long-Term Memory (LPM)
defmodule AiAssistant.Memory.Schema.UserPersona do
  defstruct [
    :id,
    :user_id,
    :profile,          # Static attributes (name, birth_year, etc.)
    :knowledge_base,   # Queue of factual information
    :traits,           # 90-dimensional trait vector
    :updated_at
  ]
end

defmodule AiAssistant.Memory.Schema.AgentPersona do
  defstruct [
    :id,
    :session_id,
    :profile,          # Fixed agent settings
    :traits,           # Dynamic interaction traits
    :updated_at
  ]
end
```

### 3. Memory Storage Implementation

```elixir
defmodule AiAssistant.Memory.Storage.STM do
  use GenServer
  alias AiAssistant.Memory.Schema.DialoguePage
  alias AiAssistant.Memory.Storage.MTM
  
  @doc """
  Manages short-term memory with fixed-capacity queue
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:session_id]))
  end
  
  def init(opts) do
    config = opts[:config] || %AiAssistant.Memory.Config{}
    
    state = %{
      session_id: opts[:session_id],
      queue: :queue.new(),
      capacity: config.stm_capacity,
      config: config
    }
    
    {:ok, state}
  end
  
  def add_dialogue(session_id, query, response) do
    GenServer.call(via_tuple(session_id), {:add_dialogue, query, response})
  end
  
  def handle_call({:add_dialogue, query, response}, _from, state) do
    page = create_dialogue_page(query, response, state.session_id)
    
    # Generate embeddings and extract keywords using LLM
    page = enrich_page_with_llm(page, state.config)
    
    # Update queue with FIFO eviction
    {new_queue, evicted} = update_queue(state.queue, page, state.capacity)
    
    # Transfer evicted page to MTM if necessary
    if evicted do
      MTM.add_page(state.session_id, evicted)
    end
    
    # Store in Mnesia
    :mnesia.transaction(fn ->
      :mnesia.write({:dialogue_page, page})
    end)
    
    {:reply, :ok, %{state | queue: new_queue}}
  end
  
  defp enrich_page_with_llm(page, config) do
    if config.enabled do
      # Use existing LLM abstraction layer
      {:ok, embedding} = AiAssistant.LLMAbstraction.generate_embedding(
        "#{page.query} #{page.response}"
      )
      
      {:ok, keywords} = AiAssistant.LLMAbstraction.extract_keywords(
        "#{page.query} #{page.response}"
      )
      
      %{page | embedding: embedding, keywords: keywords}
    else
      page
    end
  end
  
  defp via_tuple(session_id) do
    {:via, Horde.Registry, {AiAssistant.DistributedRegistry, {:stm, session_id}}}
  end
end
```

### 4. Distributed Synchronization

```elixir
defmodule AiAssistant.Memory.Sync do
  use GenServer
  require Logger
  
  @doc """
  Handles memory synchronization across nodes using Mnesia's built-in replication
  """
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Setup Mnesia tables with disc_copies for persistence
    setup_mnesia_tables()
    
    # Subscribe to cluster events
    :ok = :pg.join(:memory_sync, self())
    
    {:ok, %{}}
  end
  
  defp setup_mnesia_tables do
    tables = [
      {:dialogue_page, [:id, :session_id, :query, :response, :timestamp, 
                       :embedding, :dialogue_chain, :keywords, :created_at],
       [disc_copies: [node()]]},
      {:dialogue_segment, [:id, :session_id, :topic_summary, :page_ids,
                          :embedding, :keywords, :heat_score, :n_visit,
                          :l_interaction, :last_accessed, :created_at, :updated_at],
       [disc_copies: [node()]]},
      {:user_persona, [:id, :user_id, :profile, :knowledge_base, :traits, :updated_at],
       [disc_copies: [node()]]},
      {:agent_persona, [:id, :session_id, :profile, :traits, :updated_at],
       [disc_copies: [node()]]}
    ]
    
    Enum.each(tables, fn {name, attrs, opts} ->
      case :mnesia.create_table(name, [attributes: attrs] ++ opts) do
        {:atomic, :ok} -> Logger.info("Created Mnesia table #{name}")
        {:aborted, {:already_exists, ^name}} -> :ok
        error -> Logger.error("Failed to create table #{name}: #{inspect(error)}")
      end
    end)
    
    # Ensure tables are replicated to new nodes
    :mnesia.subscribe(:table)
  end
  
  def handle_info({:mnesia_table_event, {:write, Table, Record, _}}, state) do
    # Broadcast significant memory updates via pg
    :pg.get_members(:memory_sync)
    |> Enum.reject(&(&1 == self()))
    |> Enum.each(&send(&1, {:memory_update, Table, Record}))
    
    {:noreply, state}
  end
end
```

### 5. Memory Retrieval with Caching

```elixir
defmodule AiAssistant.Memory.Retrieval do
  use GenServer
  alias AiAssistant.Memory.Schema.{DialoguePage, DialogueSegment}
  
  @moduledoc """
  Retrieves relevant memory across all tiers with caching
  """
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize with Nebulex cache reference
    {:ok, %{cache: AiAssistant.Cache.Memory}}
  end
  
  def retrieve_context(session_id, query, config \\ %AiAssistant.Memory.Config{}) do
    GenServer.call(__MODULE__, {:retrieve_context, session_id, query, config})
  end
  
  def handle_call({:retrieve_context, session_id, query, config}, _from, state) do
    # Check cache first
    cache_key = {:memory_context, session_id, :erlang.phash2(query)}
    
    result = case Cachex.get(state.cache, cache_key) do
      {:ok, nil} ->
        # Perform retrieval
        context = retrieve_all_tiers(session_id, query, config)
        
        # Cache for 5 minutes
        Cachex.put(state.cache, cache_key, context, ttl: :timer.minutes(5))
        context
        
      {:ok, cached} ->
        cached
    end
    
    {:reply, result, state}
  end
  
  defp retrieve_all_tiers(session_id, query, config) do
    # Generate query embedding
    {:ok, query_embedding} = AiAssistant.LLMAbstraction.generate_embedding(query)
    
    # Parallel retrieval from all tiers
    tasks = [
      Task.async(fn -> retrieve_stm(session_id) end),
      Task.async(fn -> retrieve_mtm(session_id, query_embedding, config) end),
      Task.async(fn -> retrieve_lpm(session_id, query_embedding, config) end)
    ]
    
    [stm, mtm, lpm] = Task.await_many(tasks, 5000)
    
    %{
      short_term: stm,
      mid_term: mtm,
      long_term: lpm,
      query: query,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp retrieve_mtm(session_id, query_embedding, config) do
    # Two-stage retrieval process
    segments = :mnesia.transaction(fn ->
      :mnesia.match_object({:dialogue_segment, :_, session_id, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    end)
    |> elem(1)
    
    # Calculate Fscore for each segment
    scored_segments = segments
    |> Enum.map(&score_segment(&1, query_embedding))
    |> Enum.sort_by(&elem(1, &1), :desc)
    |> Enum.take(config.top_m_segments)
    
    # Update heat metrics
    Enum.each(scored_segments, &update_segment_heat/1)
    
    # Retrieve top-k pages from selected segments
    retrieve_pages_from_segments(scored_segments, query_embedding, config.top_k_pages)
  end
  
  defp score_segment(segment, query_embedding) do
    # Calculate Fscore = cos(e_s, e_p) + FJaccard(K_s, K_p)
    cos_sim = cosine_similarity(segment.embedding, query_embedding)
    jaccard = jaccard_similarity(segment.keywords, extract_query_keywords(query_embedding))
    
    {segment, cos_sim + jaccard}
  end
end
```

### 6. Integration with Existing Engines

```elixir
defmodule AiAssistant.Memory.Integration do
  @moduledoc """
  Integrates MemoryOS with existing coding assistance engines
  """
  
  defmacro __using__(opts) do
    quote do
      def retrieve_memory_context(query, opts \\ []) do
        config = Keyword.get(opts, :memory_config, %AiAssistant.Memory.Config{})
        
        if config.enabled do
          session_id = Keyword.get(opts, :session_id)
          AiAssistant.Memory.Retrieval.retrieve_context(session_id, query, config)
        else
          nil
        end
      end
      
      def enrich_prompt_with_memory(prompt, memory_context) do
        if memory_context do
          build_enriched_prompt(prompt, memory_context)
        else
          prompt
        end
      end
      
      defp build_enriched_prompt(prompt, context) do
        """
        ## Current Context
        #{prompt}
        
        ## Short-term Memory
        #{format_stm_context(context.short_term)}
        
        ## Related Topics
        #{format_mtm_context(context.mid_term)}
        
        ## User Profile & Preferences
        #{format_lpm_context(context.long_term)}
        """
      end
    end
  end
end

# Usage in existing engines
defmodule AiAssistant.Engines.ExplanationEngine do
  use AiAssistant.CodingAssistant.Engine
  use AiAssistant.Memory.Integration
  
  def process_request(request, session_id) do
    # Retrieve memory context
    memory_context = retrieve_memory_context(request.content, session_id: session_id)
    
    # Enrich prompt
    enriched_prompt = enrich_prompt_with_memory(request.content, memory_context)
    
    # Process with LLM
    {:ok, response} = AiAssistant.LLMAbstraction.generate_completion(enriched_prompt)
    
    # Store interaction in memory
    AiAssistant.Memory.Storage.STM.add_dialogue(session_id, request.content, response)
    
    response
  end
end
```

### 7. Configuration and Feature Flags

```elixir
# config/config.exs
config :ai_assistant, :memory,
  enabled: true,
  stm_capacity: 7,
  mtm_max_segments: 200,
  fscore_threshold: 0.6,
  heat_threshold: 5.0,
  # Performance optimization for single-node
  replication_factor: 1,
  cache_ttl: :timer.minutes(5)

# Runtime configuration
defmodule AiAssistant.Memory.Runtime do
  def configure(opts) do
    config = struct(AiAssistant.Memory.Config, opts)
    Application.put_env(:ai_assistant, :memory_config, config)
  end
  
  def disable_for_session(session_id) do
    Registry.register(AiAssistant.MemoryDisabled, session_id, true)
  end
end
```

## Implementation Roadmap

### Phase 1: Core Memory Infrastructure (1-2 weeks)
- [ ] Extend Mnesia schema with memory tables
- [ ] Implement STM GenServer with FIFO queue
- [ ] Create basic DialoguePage structure and storage
- [ ] Add LLM integration for embeddings

### Phase 2: MTM and Heat-based Management (2-3 weeks)
- [ ] Implement DialogueSegment creation and Fscore calculation
- [ ] Add heat score computation and segment eviction
- [ ] Create MTM-to-LPM transfer logic
- [ ] Implement two-stage retrieval process

### Phase 3: LPM and Personalization (2-3 weeks)
- [ ] Design UserPersona and AgentPersona schemas
- [ ] Implement trait extraction and evolution
- [ ] Add knowledge base management
- [ ] Create LPM retrieval with semantic search

### Phase 4: Integration and Optimization (1-2 weeks)
- [ ] Integrate with existing engines via macros
- [ ] Add Nebulex caching layer
- [ ] Optimize for single-node performance
- [ ] Create configuration management

### Phase 5: Testing and Monitoring (1 week)
- [ ] Add comprehensive test suite
- [ ] Implement telemetry for memory operations
- [ ] Create memory usage dashboards
- [ ] Performance benchmarking

## Performance Considerations

### Single-Node Optimization
- Use `:disc_copies` for Mnesia tables to persist memory
- Configure Nebulex with local-only caching for single-node deployments
- Minimize network overhead by co-locating memory processes

### LLM Call Optimization
- Batch embedding generation when possible
- Cache embeddings aggressively
- Use background tasks for non-critical enrichment
- Implement circuit breakers for LLM failures

### Memory Usage
- Monitor queue sizes and implement cleanup strategies
- Use binary references for large text content
- Compress old segments before archiving
- Implement gradual trait evolution to prevent memory bloat

## Future Extensions

### Code Analysis Memory
```elixir
defmodule AiAssistant.Memory.Schema.CodeAnalysisPattern do
  defstruct [
    :id,
    :pattern_type,    # :smell, :vulnerability, :optimization
    :language,
    :detection_rule,
    :occurrences,     # Count of times detected
    :last_seen,
    :effectiveness    # Success rate of suggested fixes
  ]
end
```

### Refactoring History
```elixir
defmodule AiAssistant.Memory.Schema.RefactoringHistory do
  defstruct [
    :id,
    :session_id,
    :original_code,
    :refactored_code,
    :refactoring_type,
    :user_accepted,
    :timestamp
  ]
end
```

These extensions would follow the same heat-based promotion patterns, allowing the system to learn from past code analysis and refactoring decisions.
