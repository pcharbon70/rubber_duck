defmodule RubberDuck.Memory.Updater do
  @moduledoc """
  Module for handling memory updates, migrations, and heat score calculations.
  """
  
  alias RubberDuck.Memory
  alias RubberDuck.Memory.Storage
  require Logger
  
  # Heat score calculations
  
  @doc """
  Calculate heat score for a summary based on frequency and recency.
  """
  def calculate_heat_score(frequency, created_at) do
    days_old = DateTime.diff(DateTime.utc_now(), created_at, :day)
    recency_factor = :math.exp(-days_old / 30)  # Decay over 30 days
    frequency * recency_factor
  end
  
  @doc """
  Update heat scores for all summaries of a user.
  """
  def update_heat_scores(user_id) do
    case Memory.get_user_summaries(user_id) do
      {:ok, summaries} ->
        Enum.each(summaries, fn summary ->
          heat_score = calculate_heat_score(summary.frequency, summary.created_at)
          Memory.update_summary(summary, %{heat_score: heat_score})
        end)
        :ok
        
      error ->
        Logger.error("Failed to update heat scores: #{inspect(error)}")
        error
    end
  end
  
  # Migration operations
  
  @doc """
  Migrate high-value summaries to long-term memory.
  """
  def migrate_summaries_to_long_term(user_id, opts \\ []) do
    heat_threshold = opts[:heat_threshold] || 10.0
    
    case Memory.get_user_summaries(user_id) do
      {:ok, summaries} ->
        candidates = summaries
        |> Enum.filter(&(&1.heat_score >= heat_threshold))
        |> Enum.sort_by(& &1.heat_score, :desc)
        
        results = Enum.map(candidates, &migrate_summary(&1))
        
        successful = Enum.count(results, &match?({:ok, _}, &1))
        Logger.info("Migrated #{successful}/#{length(candidates)} summaries to long-term memory")
        
        {:ok, successful}
        
      error ->
        error
    end
  end
  
  @doc """
  Extract patterns from interactions and create summaries.
  """
  def extract_patterns_from_interactions(user_id, session_id) do
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} when length(interactions) >= 3 ->
        patterns = analyze_interaction_patterns(interactions)
        
        Enum.each(patterns, fn pattern ->
          Storage.store_mid_term(Map.merge(pattern, %{
            user_id: user_id,
            source_interactions: Enum.map(interactions, & &1.id)
          }))
        end)
        
        {:ok, length(patterns)}
        
      {:ok, _} ->
        {:ok, 0}
        
      error ->
        error
    end
  end
  
  @doc """
  Update user profile based on learned patterns.
  """
  def update_user_profile_patterns(user_id) do
    with {:ok, profile} <- Memory.get_user_profile(user_id),
         {:ok, summaries} <- Memory.get_user_summaries(user_id),
         {:ok, patterns} <- get_top_patterns(user_id) do
      
      # Extract learned patterns
      learned = summaries
      |> Enum.filter(&(&1.heat_score >= 5.0))
      |> Enum.take(10)
      |> Enum.map(fn summary ->
        {summary.topic, %{
          frequency: summary.frequency,
          last_seen: summary.last_accessed_at,
          pattern_type: summary.pattern_type
        }}
      end)
      |> Map.new()
      
      # Update profile preferences based on patterns
      preferences = analyze_preferences(patterns)
      
      Memory.update_profile(profile, %{
        preferences: Map.merge(profile.preferences || %{}, preferences)
      })
      
      # Add learned patterns
      Enum.each(learned, fn {key, data} ->
        Memory.add_learned_pattern(profile, key, data)
      end)
      
      {:ok, profile}
    else
      error -> error
    end
  end
  
  # Private functions
  
  defp migrate_summary(summary) do
    try do
      case determine_migration_target(summary) do
        {:code_pattern, data} ->
          Memory.store_pattern(data)
          
        {:knowledge, data} ->
          Memory.store_knowledge(data)
          
        :skip ->
          {:ok, :skipped}
      end
    rescue
      e ->
        Logger.error("Failed to migrate summary #{summary.id}: #{inspect(e)}")
        {:error, e}
    end
  end
  
  defp determine_migration_target(summary) do
    case summary.pattern_type do
      :code_pattern ->
        {:code_pattern, %{
          user_id: summary.user_id,
          language: summary.metadata[:language] || "elixir",
          pattern_name: summary.topic,
          pattern_code: extract_code_from_summary(summary),
          description: summary.summary,
          pattern_type: :function,
          metadata: Map.merge(summary.metadata, %{
            migrated_from: "summary",
            original_id: summary.id,
            heat_score: summary.heat_score
          })
        }}
        
      type when type in [:error_pattern, :usage_pattern] ->
        if project_id = summary.metadata[:project_id] do
          {:knowledge, %{
            user_id: summary.user_id,
            project_id: project_id,
            knowledge_type: map_pattern_to_knowledge_type(type),
            title: summary.topic,
            content: summary.summary,
            tags: extract_tags_from_summary(summary),
            metadata: Map.merge(summary.metadata, %{
              migrated_from: "summary",
              original_id: summary.id,
              heat_score: summary.heat_score
            })
          }}
        else
          :skip
        end
        
      _ ->
        :skip
    end
  end
  
  defp extract_code_from_summary(summary) do
    # Extract code blocks from summary content
    # In production, use more sophisticated extraction
    summary.summary
    |> String.split("```")
    |> Enum.at(1, summary.summary)
    |> String.trim()
  end
  
  defp map_pattern_to_knowledge_type(:error_pattern), do: :business_logic
  defp map_pattern_to_knowledge_type(:usage_pattern), do: :api
  defp map_pattern_to_knowledge_type(_), do: :documentation
  
  defp extract_tags_from_summary(summary) do
    base_tags = [Atom.to_string(summary.pattern_type)]
    metadata_tags = summary.metadata[:tags] || []
    
    # Extract additional tags from topic
    topic_tags = summary.topic
    |> String.split("_")
    |> Enum.filter(&(String.length(&1) > 3))
    
    Enum.uniq(base_tags ++ metadata_tags ++ topic_tags)
  end
  
  defp analyze_interaction_patterns(interactions) do
    # Group by type and analyze
    interactions
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, typed_interactions} ->
      %{
        topic: create_pattern_topic(type, typed_interactions),
        summary: create_pattern_summary(typed_interactions),
        pattern_type: map_interaction_to_pattern_type(type),
        frequency: length(typed_interactions),
        metadata: %{
          interaction_type: type,
          session_start: List.first(typed_interactions).inserted_at,
          session_end: List.last(typed_interactions).inserted_at
        }
      }
    end)
    |> Enum.filter(&(&1.frequency >= 2))  # Only patterns with 2+ occurrences
  end
  
  defp create_pattern_topic(type, interactions) do
    timestamp = DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
    "#{type}_pattern_#{timestamp}_#{length(interactions)}"
  end
  
  defp create_pattern_summary(interactions) do
    # In production, use LLM to generate meaningful summary
    contents = interactions
    |> Enum.map(& &1.content)
    |> Enum.take(3)
    |> Enum.join("; ")
    
    "Pattern detected from #{length(interactions)} interactions: #{String.slice(contents, 0, 200)}..."
  end
  
  defp map_interaction_to_pattern_type(:code_generation), do: :code_pattern
  defp map_interaction_to_pattern_type(:code_completion), do: :code_pattern
  defp map_interaction_to_pattern_type(:error), do: :error_pattern
  defp map_interaction_to_pattern_type(_), do: :conversation_pattern
  
  defp get_top_patterns(user_id) do
    Memory.get_patterns_by_language(user_id, "elixir", limit: 10)
  end
  
  defp analyze_preferences(patterns) do
    # Analyze patterns to determine preferences
    pattern_types = patterns
    |> Enum.map(& &1.pattern_type)
    |> Enum.frequencies()
    
    %{
      preferred_patterns: Map.keys(pattern_types),
      pattern_frequencies: pattern_types,
      last_updated: DateTime.utc_now()
    }
  end
end
