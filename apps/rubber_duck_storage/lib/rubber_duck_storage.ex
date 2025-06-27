defmodule RubberDuckStorage do
  @moduledoc """
  RubberDuckStorage provides comprehensive data persistence for the RubberDuck system.

  This module serves as the main API for interacting with the storage layer,
  providing convenient access to:

  - Conversation and message persistence
  - Engine session and analysis result storage
  - Context management and versioning
  - Caching and performance optimization
  - Transaction helpers for complex operations

  ## Key Components

  - `RubberDuckStorage.Repo` - Main Ecto repository
  - `RubberDuckStorage.Repos.*` - Specialized repository modules
  - `RubberDuckStorage.ContextManager` - Context persistence and versioning
  - `RubberDuckStorage.Cache` - Multi-layer caching system
  - `RubberDuckStorage.Transaction` - Transaction helpers

  ## Usage

  The storage layer integrates with RubberDuckCore data structures and protocols:

      # Create a conversation with messages
      conversation = RubberDuckCore.Conversation.new(title: "My Chat")
      messages = [RubberDuckCore.Message.user("Hello")]
      
      {:ok, result} = RubberDuckStorage.create_conversation_with_messages(conversation, messages)

      # Store and retrieve context
      context = %{user_preferences: %{theme: "dark"}}
      {:ok, version} = RubberDuckStorage.store_context(conversation.id, context)
      {:ok, retrieved_context, version} = RubberDuckStorage.get_context(conversation.id)

  """

  alias RubberDuckStorage.{Repo, Cache, ContextManager, Transaction}
  alias RubberDuckStorage.Repos.{ConversationRepo, MessageRepo, EngineSessionRepo, AnalysisResultRepo}

  # Conversation Operations

  @doc """
  Creates a conversation with messages in a single transaction.
  """
  defdelegate add_conversation_with_messages(conversation, messages), 
    to: Transaction

  @doc """
  Gets a conversation by ID.
  """
  defdelegate get_conversation(id), to: ConversationRepo, as: :get

  @doc """
  Gets a conversation with messages preloaded.
  """
  defdelegate get_conversation_with_messages(id), 
    to: ConversationRepo, as: :get_with_messages

  @doc """
  Lists conversations with optional filtering.
  """
  defdelegate list_conversations(opts \\ []), to: ConversationRepo, as: :list

  @doc """
  Updates a conversation.
  """
  defdelegate change_conversation(id, attrs), to: ConversationRepo, as: :change

  @doc """
  Archives a conversation and related data.
  """
  defdelegate archive_conversation(id), to: Transaction

  # Message Operations

  @doc """
  Gets messages for a conversation.
  """
  defdelegate get_messages_for_conversation(conversation_id, opts \\ []), 
    to: MessageRepo, as: :list_for_conversation

  @doc """
  Creates a message.
  """
  defdelegate add_message(attrs), to: MessageRepo, as: :add

  @doc """
  Creates multiple messages in batch.
  """
  defdelegate add_message_batch(messages_attrs), to: MessageRepo, as: :add_batch

  # Engine Session Operations

  @doc """
  Creates an engine session.
  """
  defdelegate add_engine_session(attrs), to: EngineSessionRepo, as: :add

  @doc """
  Gets engine sessions for a conversation.
  """
  defdelegate get_engine_sessions_for_conversation(conversation_id, opts \\ []), 
    to: EngineSessionRepo, as: :list_for_conversation

  @doc """
  Starts an engine session.
  """
  defdelegate start_engine_session(id), to: EngineSessionRepo, as: :start

  @doc """
  Completes an engine session.
  """
  defdelegate complete_engine_session(id), to: EngineSessionRepo, as: :complete

  @doc """
  Completes an engine session with final results.
  """
  defdelegate complete_engine_session_with_results(session_id, results_attrs), 
    to: Transaction

  # Analysis Result Operations

  @doc """
  Gets analysis results for an engine session.
  """
  defdelegate get_analysis_results_for_session(session_id, opts \\ []), 
    to: AnalysisResultRepo, as: :list_for_engine_session

  @doc """
  Creates an analysis result.
  """
  defdelegate add_analysis_result(attrs), to: AnalysisResultRepo, as: :add

  @doc """
  Gets high-confidence analysis results.
  """
  defdelegate get_high_confidence_results(threshold \\ 0.8, opts \\ []), 
    to: AnalysisResultRepo, as: :get_high_confidence

  # Context Management

  @doc """
  Stores context for a conversation.
  """
  defdelegate store_context(conversation_id, context, version \\ nil), 
    to: ContextManager

  @doc """
  Gets context for a conversation.
  """
  defdelegate get_context(conversation_id), to: ContextManager

  @doc """
  Merges context with existing context.
  """
  defdelegate merge_context(conversation_id, new_context, strategy \\ :deep_merge), 
    to: ContextManager

  @doc """
  Searches for conversations with matching context.
  """
  defdelegate search_context(search_params), to: ContextManager

  # Cache Operations

  @doc """
  Gets a value from cache.
  """
  defdelegate get_cached(key), to: Cache, as: :get

  @doc """
  Puts a value in cache.
  """
  defdelegate put_cached(key, value, ttl \\ nil), to: Cache, as: :put

  @doc """
  Caches a struct using its Cacheable protocol implementation.
  """
  defdelegate cache_struct(data), to: Cache, as: :put_cacheable

  @doc """
  Gets cache statistics.
  """
  defdelegate cache_stats(), to: Cache, as: :stats

  # Transaction Helpers

  @doc """
  Executes operations with retry logic.
  """
  defdelegate with_retry(operation, max_attempts \\ 3, base_delay \\ 100), 
    to: Transaction

  @doc """
  Executes multiple operations in a single transaction.
  """
  defdelegate execute_batch(operations), to: Transaction

  # Health Check

  @doc """
  Checks if the storage system is healthy.
  """
  def health_check do
    try do
      # Check database connectivity
      Repo.query!("SELECT 1")
      
      # Check cache
      Cache.stats()
      
      # Check context manager
      ContextManager.search_context(%{})
      
      {:ok, :healthy}
    rescue
      error -> {:error, error}
    end
  end
end
