defmodule RubberDuck.Memory.Manager do
  use GenServer
  require Logger
  
  alias RubberDuck.Memory
  
  @moduledoc """
  GenServer that coordinates the three-tier memory system.
  Handles memory operations across short-term, mid-term, and long-term storage.
  """
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Store an interaction in short-term memory.
  Automatically handles FIFO eviction.
  """
  def store_interaction(interaction_data) do
    GenServer.call(__MODULE__, {:store_interaction, interaction_data})
  end
  
  @doc """
  Retrieve recent interactions for a user/session.
  """
  def get_recent_interactions(user_id, session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_recent_interactions, user_id, session_id, opts})
  end
  
  @doc """
  Search across all memory tiers for relevant information.
  """
  def search(user_id, query, opts \\ []) do
    GenServer.call(__MODULE__, {:search, user_id, query, opts})
  end
  
  @doc """
  Create or update a summary in mid-term memory.
  """
  def create_summary(user_id, topic, summary_data) do
    GenServer.call(__MODULE__, {:create_summary, user_id, topic, summary_data})
  end
  
  @doc """
  Migrate important patterns from mid-term to long-term memory.
  """
  def migrate_to_long_term(user_id) do
    GenServer.cast(__MODULE__, {:migrate_to_long_term, user_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Schedule periodic migration checks
    schedule_migration_check()
    
    state = %{
      migration_interval: :timer.hours(1),
      heat_threshold: 10.0  # Minimum heat score for migration
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:store_interaction, interaction_data}, _from, state) do
    result = Memory.store_interaction(interaction_data)
    
    # Check if we should create summaries from recent interactions
    Task.start(fn ->
      check_for_pattern_extraction(interaction_data.user_id, interaction_data.session_id)
    end)
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:get_recent_interactions, user_id, session_id, _opts}, _from, state) do
    result = Memory.get_recent_interactions(user_id, session_id)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:search, user_id, query, opts}, _from, state) do
    # Search across all memory tiers
    results = search_all_tiers(user_id, query, opts)
    {:reply, {:ok, results}, state}
  end
  
  @impl true
  def handle_call({:create_summary, user_id, topic, summary_data}, _from, state) do
    # Check if summary exists
    case Memory.get_summary_by_topic(user_id, topic) do
      {:ok, [existing | _]} ->
        # Update existing summary
        Memory.increment_pattern_frequency(existing)
        
      _ ->
        # Create new summary
        Memory.create_summary(Map.merge(summary_data, %{
          user_id: user_id,
          topic: topic
        }))
    end
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_cast({:migrate_to_long_term, user_id}, state) do
    # Get high-value summaries
    case Memory.get_user_summaries(user_id) do
      {:ok, summaries} ->
        summaries
        |> Enum.filter(&(&1.heat_score >= state.heat_threshold))
        |> Enum.each(&migrate_summary_to_long_term(&1, user_id))
        
      error ->
        Logger.error("Failed to get summaries for migration: #{inspect(error)}")
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:migration_check, state) do
    # Check all users for migration opportunities
    # In a real system, this would iterate through active users
    Logger.info("Running periodic memory migration check")
    
    # Schedule next check
    schedule_migration_check()
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp schedule_migration_check do
    Process.send_after(self(), :migration_check, :timer.hours(1))
  end
  
  defp check_for_pattern_extraction(user_id, session_id) do
    # Get recent interactions
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} when length(interactions) >= 5 ->
        # Extract patterns from recent interactions
        extract_patterns(interactions, user_id)
        
      _ ->
        :ok
    end
  end
  
  defp extract_patterns(interactions, user_id) do
    # Group by interaction type
    patterns = interactions
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, type_interactions} ->
      %{
        topic: "#{type}_pattern_#{Date.utc_today()}",
        pattern_type: :conversation_pattern,
        summary: summarize_interactions(type_interactions),
        source_interactions: Enum.map(type_interactions, & &1.id)
      }
    end)
    
    # Create summaries for identified patterns
    Enum.each(patterns, fn pattern ->
      create_summary(user_id, pattern.topic, pattern)
    end)
  end
  
  defp summarize_interactions(interactions) do
    # Simple summarization - in production, use LLM
    contents = Enum.map(interactions, & &1.content) |> Enum.join("; ")
    "Pattern identified from #{length(interactions)} interactions: #{String.slice(contents, 0, 200)}..."
  end
  
  defp search_all_tiers(user_id, query, opts) do
    project_id = opts[:project_id]
    limit = opts[:limit] || 10
    
    # Search each tier in parallel
    tasks = [
      Task.async(fn ->
        {:interactions, Memory.get_user_interactions(user_id)}
      end),
      Task.async(fn ->
        {:summaries, Memory.search_summaries(user_id, query, limit: limit)}
      end)
    ]
    
    # Add long-term searches if project_id provided
    tasks = if project_id do
      tasks ++ [
        Task.async(fn ->
          {:knowledge, Memory.search_knowledge_keyword(user_id, project_id, query, limit: limit)}
        end),
        Task.async(fn ->
          {:patterns, Memory.search_patterns_keyword(user_id, query, limit: limit)}
        end)
      ]
    else
      tasks
    end
    
    # Collect results
    results = Task.await_many(tasks, 5000)
    |> Enum.reduce(%{}, fn {tier, {:ok, data}}, acc ->
      Map.put(acc, tier, data)
    end)
    
    results
  end
  
  defp migrate_summary_to_long_term(summary, user_id) do
    # Determine the type of long-term storage
    case summary.pattern_type do
      :code_pattern ->
        # Extract code pattern data
        pattern_data = %{
          user_id: user_id,
          language: summary.metadata[:language] || "unknown",
          pattern_name: summary.topic,
          pattern_code: summary.summary,
          description: "Extracted from recurring patterns",
          pattern_type: :function,
          metadata: summary.metadata
        }
        
        Memory.store_pattern(pattern_data)
        
      _ ->
        # Store as general knowledge
        if project_id = summary.metadata[:project_id] do
          knowledge_data = %{
            user_id: user_id,
            project_id: project_id,
            knowledge_type: :business_logic,
            title: summary.topic,
            content: summary.summary,
            tags: extract_tags(summary),
            metadata: summary.metadata
          }
          
          Memory.store_knowledge(knowledge_data)
        end
    end
    
    Logger.info("Migrated summary #{summary.id} to long-term memory")
  end
  
  defp extract_tags(summary) do
    # Extract tags from summary content and metadata
    base_tags = [Atom.to_string(summary.pattern_type)]
    metadata_tags = summary.metadata[:tags] || []
    
    base_tags ++ metadata_tags
  end
end
