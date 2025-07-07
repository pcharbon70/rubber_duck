defmodule RubberDuck.Memory.Storage do
  @moduledoc """
  Module for handling tier-specific storage operations.
  Provides unified interface for different memory tier operations.
  """

  alias RubberDuck.Memory
  require Ash.Query

  # Short-term memory operations

  @doc """
  Store an interaction in short-term memory.
  """
  def store_short_term(interaction_data) do
    Memory.store_interaction(interaction_data)
  end

  @doc """
  Retrieve interactions from short-term memory.
  """
  def get_short_term(user_id, session_id) do
    Memory.get_recent_interactions(user_id, session_id)
  end

  @doc """
  Clear short-term memory for a session.
  """
  def clear_short_term(user_id, session_id) do
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} ->
        Enum.each(interactions, &Ash.destroy!(&1, authorize?: false))
        :ok

      error ->
        error
    end
  end

  # Mid-term memory operations

  @doc """
  Store or update a summary in mid-term memory.
  """
  def store_mid_term(summary_data) do
    topic = summary_data.topic
    user_id = summary_data.user_id

    case Memory.get_summary_by_topic(user_id, topic) do
      {:ok, [existing | _]} ->
        # Update existing summary
        Memory.update_summary(existing, %{
          frequency: existing.frequency + 1,
          metadata: Map.merge(existing.metadata, summary_data[:metadata] || %{})
        })

        Memory.increment_pattern_frequency(existing)

      _ ->
        # Create new summary
        Memory.create_summary(summary_data)
    end
  end

  @doc """
  Get summaries from mid-term memory.
  """
  def get_mid_term(user_id, opts \\ []) do
    if topic = opts[:topic] do
      Memory.get_summary_by_topic(user_id, topic)
    else
      Memory.get_user_summaries(user_id)
    end
  end

  @doc """
  Search mid-term memory.
  """
  def search_mid_term(user_id, query, opts \\ []) do
    Memory.search_summaries(user_id, query, opts)
  end

  # Long-term memory operations

  @doc """
  Store user profile in long-term memory.
  """
  def store_user_profile(profile_data) do
    Memory.create_or_update_profile(profile_data)
  end

  @doc """
  Store code pattern in long-term memory.
  """
  def store_code_pattern(pattern_data) do
    Memory.store_pattern(pattern_data)
  end

  @doc """
  Store knowledge in long-term memory.
  """
  def store_knowledge(knowledge_data) do
    Memory.store_knowledge(knowledge_data)
  end

  @doc """
  Get user profile from long-term memory.
  """
  def get_user_profile(user_id) do
    Memory.get_user_profile(user_id)
  end

  @doc """
  Search long-term memory for patterns.
  """
  def search_patterns(user_id, query, opts \\ []) do
    if opts[:semantic] && opts[:query_embedding] do
      Memory.search_patterns_semantic(user_id, opts[:query_embedding], opts)
    else
      Memory.search_patterns_keyword(user_id, query, opts)
    end
  end

  @doc """
  Search long-term memory for knowledge.
  """
  def search_knowledge(user_id, project_id, query, opts \\ []) do
    if opts[:semantic] && opts[:query_embedding] do
      Memory.search_knowledge_semantic(user_id, project_id, opts[:query_embedding], opts)
    else
      Memory.search_knowledge_keyword(user_id, project_id, query, opts)
    end
  end

  # Cross-tier operations

  @doc """
  Count items in each memory tier for a user.
  """
  def get_memory_stats(user_id) do
    # Count interactions
    interaction_count =
      case Memory.Interaction
           |> Ash.Query.for_read(:by_user, %{user_id: user_id})
           |> Ash.count(authorize?: false) do
        {:ok, count} -> count
        _ -> 0
      end

    # Count summaries
    summary_count =
      case Memory.Summary
           |> Ash.Query.for_read(:by_user, %{user_id: user_id})
           |> Ash.count(authorize?: false) do
        {:ok, count} -> count
        _ -> 0
      end

    # Count patterns
    pattern_count =
      case Memory.CodePattern
           |> Ash.Query.new()
           |> Ash.Query.filter(user_id: user_id)
           |> Ash.count(authorize?: false) do
        {:ok, count} -> count
        _ -> 0
      end

    %{
      short_term: interaction_count,
      mid_term: summary_count,
      long_term: %{
        patterns: pattern_count,
        profile: if(get_user_profile(user_id) |> elem(0) == :ok, do: 1, else: 0)
      },
      total: interaction_count + summary_count + pattern_count
    }
  end

  @doc """
  Clear all memory tiers for a user.
  WARNING: This is destructive and should be used carefully.
  """
  def clear_all_memory(user_id) do
    # Clear interactions
    Memory.Interaction
    |> Ash.Query.for_read(:by_user, %{user_id: user_id})
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    # Clear summaries
    Memory.Summary
    |> Ash.Query.for_read(:by_user, %{user_id: user_id})
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    # Clear patterns
    Memory.CodePattern
    |> Ash.Query.new()
    |> Ash.Query.filter(user_id: user_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    # Clear knowledge
    Memory.Knowledge
    |> Ash.Query.new()
    |> Ash.Query.filter(user_id: user_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    # Clear profile
    case get_user_profile(user_id) do
      {:ok, profile} -> Ash.destroy!(profile, authorize?: false)
      _ -> :ok
    end

    :ok
  end
end
