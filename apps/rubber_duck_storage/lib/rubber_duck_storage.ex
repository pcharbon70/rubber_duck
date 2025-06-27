defmodule RubberDuckStorage do
  @moduledoc """
  RubberDuckStorage provides comprehensive project-based data persistence for the RubberDuck system.

  This module serves as the main API for interacting with the storage layer,
  providing convenient access to:

  - Project-based data organization and isolation
  - Conversation and message persistence within project scope
  - Engine session and analysis result storage with project context
  - Context management and versioning
  - Caching and performance optimization
  - Transaction helpers for complex operations

  ## Key Components

  - `RubberDuckStorage.Repo` - Main Ecto repository
  - `RubberDuckStorage.Repository` - Unified repository with project-scoped operations
  - `RubberDuckStorage.ContextManager` - Context persistence and versioning
  - `RubberDuckStorage.Cache` - Multi-layer caching system
  - `RubberDuckStorage.Transaction` - Transaction helpers

  ## Project-Based Architecture

  All data operations are scoped to projects, providing natural data isolation
  and organization. Each project contains its own set of conversations, messages,
  engine sessions, and analysis results.

  ## Usage

  The storage layer integrates with RubberDuckCore data structures and protocols:

      # Create a project first
      {:ok, project} = RubberDuckStorage.add_project(%{name: "My Project"})

      # Create a conversation with messages within the project
      conversation = RubberDuckCore.Conversation.new(title: "My Chat")
      messages = [RubberDuckCore.Message.user("Hello")]
      
      {:ok, result} = RubberDuckStorage.add_conversation_with_messages(project.id, conversation, messages)

      # Store and retrieve context
      context = %{user_preferences: %{theme: "dark"}}
      {:ok, version} = RubberDuckStorage.store_context(conversation.id, context)
      {:ok, retrieved_context, version} = RubberDuckStorage.get_context(conversation.id)

  """

  alias RubberDuckStorage.{Repo, Repository, Cache, ContextManager, Transaction}

  # Project Operations

  @doc """
  Gets a project by ID.
  """
  defdelegate get_project(id), to: Repository

  @doc """
  Lists projects with optional filtering.
  """
  defdelegate list_projects(opts \\ []), to: Repository

  @doc """
  Creates a project.
  """
  defdelegate add_project(attrs), to: Repository

  @doc """
  Updates a project.
  """
  defdelegate change_project(id, attrs), to: Repository

  @doc """
  Archives a project.
  """
  defdelegate archive_project(id), to: Repository

  # Conversation Operations (Project-scoped)

  @doc """
  Creates a conversation with messages in a single transaction.
  """
  defdelegate add_conversation_with_messages(project_id, conversation, messages),
    to: Transaction

  @doc """
  Gets a conversation by ID within project scope.
  """
  defdelegate get_conversation(project_id, conversation_id), to: Repository

  @doc """
  Gets a conversation with messages preloaded within project scope.
  """
  defdelegate get_conversation_with_messages(project_id, conversation_id),
    to: Repository

  @doc """
  Lists conversations for a project with optional filtering.
  """
  defdelegate list_conversations(project_id, opts \\ []), to: Repository

  @doc """
  Updates a conversation within project scope.
  """
  defdelegate change_conversation(project_id, conversation_id, attrs), to: Repository

  @doc """
  Archives a conversation and related data within project scope.
  """
  defdelegate archive_conversation(project_id, conversation_id), to: Transaction

  # Message Operations (Project-scoped)

  @doc """
  Gets messages for a conversation within project scope.
  """
  defdelegate list_messages(project_id, conversation_id, opts \\ []), to: Repository

  @doc """
  Creates a message within project scope.
  """
  defdelegate add_message(project_id, conversation_id, attrs), to: Repository

  @doc """
  Creates multiple messages in batch within project scope.
  """
  defdelegate add_messages_batch(project_id, conversation_id, messages_attrs), to: Repository

  # Engine Session Operations (Project-scoped)

  @doc """
  Creates an engine session within project scope.
  """
  defdelegate add_engine_session(project_id, attrs), to: Repository

  @doc """
  Gets engine sessions for a project.
  """
  defdelegate list_engine_sessions(project_id, opts \\ []), to: Repository

  @doc """
  Gets engine sessions for a conversation within project scope.
  """
  defdelegate list_engine_sessions_for_conversation(project_id, conversation_id, opts \\ []),
    to: Repository

  @doc """
  Starts an engine session within project scope.
  """
  defdelegate start_engine_session(project_id, session_id), to: Repository

  @doc """
  Completes an engine session within project scope.
  """
  defdelegate complete_engine_session(project_id, session_id), to: Repository

  @doc """
  Completes an engine session with final results within project scope.
  """
  defdelegate complete_engine_session_with_results(project_id, session_id, results_attrs),
    to: Transaction

  # Analysis Result Operations (Project-scoped)

  @doc """
  Gets analysis results for a project.
  """
  defdelegate list_analysis_results(project_id, opts \\ []), to: Repository

  @doc """
  Gets analysis results for an engine session within project scope.
  """
  defdelegate list_analysis_results_for_session(project_id, session_id, opts \\ []),
    to: Repository

  @doc """
  Creates an analysis result within project scope.
  """
  defdelegate add_analysis_result(project_id, session_id, attrs), to: Repository

  @doc """
  Creates multiple analysis results in batch within project scope.
  """
  defdelegate add_analysis_results_batch(project_id, session_id, results_attrs), to: Repository

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
