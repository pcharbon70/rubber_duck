defmodule RubberDuckStorage.Transaction do
  @moduledoc """
  Transaction helper utilities for complex database operations.

  This module provides convenience functions for managing database transactions
  and ensures data consistency across multiple repository operations.
  """

  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Repos.{ConversationRepo, MessageRepo, EngineSessionRepo, AnalysisResultRepo}
  alias RubberDuckCore.{Conversation, Message}

  require Logger

  @doc """
  Creates a complete conversation with messages in a single transaction.
  """
  def create_conversation_with_messages(%Conversation{} = conversation, messages) when is_list(messages) do
    Repo.transaction(fn ->
      # Create the conversation first
      case ConversationRepo.create(conversation) do
        {:ok, stored_conversation} ->
          # Create messages in batch
          case MessageRepo.create_batch_from_core(messages, conversation.id) do
            {:ok, stored_messages} ->
              Logger.info("Created conversation #{conversation.id} with #{length(stored_messages)} messages")
              %{conversation: stored_conversation, messages: stored_messages}

            {:error, reason} ->
              Logger.error("Failed to create messages for conversation #{conversation.id}: #{inspect(reason)}")
              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error("Failed to create conversation #{conversation.id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates conversation and adds new messages atomically.
  """
  def update_conversation_and_add_messages(conversation_id, conversation_updates, new_messages) do
    Repo.transaction(fn ->
      # Update conversation
      case ConversationRepo.update(conversation_id, conversation_updates) do
        {:ok, updated_conversation} ->
          # Add new messages
          case MessageRepo.create_batch_from_core(new_messages, conversation_id) do
            {:ok, stored_messages} ->
              Logger.info("Updated conversation #{conversation_id} and added #{length(stored_messages)} messages")
              %{conversation: updated_conversation, messages: stored_messages}

            {:error, reason} ->
              Logger.error("Failed to add messages to conversation #{conversation_id}: #{inspect(reason)}")
              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error("Failed to update conversation #{conversation_id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates an engine session with initial analysis results in a single transaction.
  """
  def create_engine_session_with_results(session_attrs, analysis_results_attrs) do
    Repo.transaction(fn ->
      # Create engine session
      case EngineSessionRepo.create(session_attrs) do
        {:ok, engine_session} ->
          # Create analysis results if provided
          if length(analysis_results_attrs) > 0 do
            # Add engine_session_id to each result
            results_with_session_id = 
              Enum.map(analysis_results_attrs, fn attrs ->
                Map.put(attrs, :engine_session_id, engine_session.id)
              end)

            case AnalysisResultRepo.create_batch(results_with_session_id) do
              {:ok, analysis_results} ->
                Logger.info("Created engine session #{engine_session.id} with #{length(analysis_results)} results")
                %{engine_session: engine_session, analysis_results: analysis_results}

              {:error, reason} ->
                Logger.error("Failed to create analysis results for session #{engine_session.id}: #{inspect(reason)}")
                Repo.rollback(reason)
            end
          else
            Logger.info("Created engine session #{engine_session.id} without initial results")
            %{engine_session: engine_session, analysis_results: []}
          end

        {:error, reason} ->
          Logger.error("Failed to create engine session: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Completes an engine session and creates final analysis results atomically.
  """
  def complete_engine_session_with_results(session_id, final_results_attrs) do
    Repo.transaction(fn ->
      # Complete the session
      case EngineSessionRepo.complete(session_id) do
        {:ok, completed_session} ->
          # Create final results if provided
          if length(final_results_attrs) > 0 do
            # Add engine_session_id to each result
            results_with_session_id = 
              Enum.map(final_results_attrs, fn attrs ->
                Map.put(attrs, :engine_session_id, session_id)
              end)

            case AnalysisResultRepo.create_batch(results_with_session_id) do
              {:ok, analysis_results} ->
                Logger.info("Completed engine session #{session_id} with #{length(analysis_results)} final results")
                %{engine_session: completed_session, analysis_results: analysis_results}

              {:error, reason} ->
                Logger.error("Failed to create final results for session #{session_id}: #{inspect(reason)}")
                Repo.rollback(reason)
            end
          else
            Logger.info("Completed engine session #{session_id} without final results")
            %{engine_session: completed_session, analysis_results: []}
          end

        {:error, reason} ->
          Logger.error("Failed to complete engine session #{session_id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Archives a conversation and all related data.
  """
  def archive_conversation(conversation_id) do
    Repo.transaction(fn ->
      # Archive the conversation
      case ConversationRepo.archive(conversation_id) do
        {:ok, archived_conversation} ->
          # Get related engine sessions
          engine_sessions = EngineSessionRepo.list_for_conversation(conversation_id)
          
          # Complete any running sessions
          running_sessions = Enum.filter(engine_sessions, fn session -> 
            session.status == :running 
          end)
          
          completed_sessions = 
            Enum.map(running_sessions, fn session ->
              case EngineSessionRepo.fail(session.id, "Conversation archived") do
                {:ok, failed_session} -> failed_session
                {:error, reason} -> Repo.rollback(reason)
              end
            end)

          Logger.info("Archived conversation #{conversation_id} and terminated #{length(completed_sessions)} running sessions")
          %{
            conversation: archived_conversation, 
            terminated_sessions: completed_sessions
          }

        {:error, reason} ->
          Logger.error("Failed to archive conversation #{conversation_id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Safely deletes a conversation and all related data.
  """
  def delete_conversation_cascade(conversation_id) do
    Repo.transaction(fn ->
      # Get related data for logging
      messages_count = MessageRepo.count_for_conversation(conversation_id)
      engine_sessions = EngineSessionRepo.list_for_conversation(conversation_id)
      
      # Delete conversation (cascading will handle related data due to foreign key constraints)
      case ConversationRepo.delete(conversation_id) do
        {:ok, deleted_conversation} ->
          Logger.info("Deleted conversation #{conversation_id} with #{messages_count} messages and #{length(engine_sessions)} engine sessions")
          %{
            conversation: deleted_conversation,
            deleted_messages_count: messages_count,
            deleted_sessions_count: length(engine_sessions)
          }

        {:error, reason} ->
          Logger.error("Failed to delete conversation #{conversation_id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Retries a failed operation with exponential backoff.
  """
  def with_retry(operation, max_attempts \\ 3, base_delay \\ 100) do
    do_with_retry(operation, max_attempts, base_delay, 1)
  end

  defp do_with_retry(operation, max_attempts, base_delay, attempt) do
    case operation.() do
      {:ok, result} -> 
        {:ok, result}
      
      {:error, reason} when attempt < max_attempts ->
        delay = base_delay * :math.pow(2, attempt - 1)
        Logger.warn("Operation failed (attempt #{attempt}/#{max_attempts}), retrying in #{delay}ms: #{inspect(reason)}")
        Process.sleep(round(delay))
        do_with_retry(operation, max_attempts, base_delay, attempt + 1)
      
      {:error, reason} ->
        Logger.error("Operation failed after #{max_attempts} attempts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Executes multiple operations in a single transaction with rollback on any failure.
  """
  def execute_batch(operations) when is_list(operations) do
    Repo.transaction(fn ->
      Enum.reduce_while(operations, [], fn operation, acc ->
        case operation.() do
          {:ok, result} -> 
            {:cont, [result | acc]}
          
          {:error, reason} -> 
            Logger.error("Batch operation failed, rolling back: #{inspect(reason)}")
            Repo.rollback(reason)
            {:halt, acc}
        end
      end)
      |> Enum.reverse()
    end)
  end

  @doc """
  Creates a transaction savepoint for nested transaction-like behavior.
  """
  def with_savepoint(name, operation) do
    Repo.transaction(fn ->
      Repo.query!("SAVEPOINT #{name}")
      
      try do
        case operation.() do
          {:ok, result} -> 
            Repo.query!("RELEASE SAVEPOINT #{name}")
            result
          
          {:error, reason} -> 
            Repo.query!("ROLLBACK TO SAVEPOINT #{name}")
            Repo.rollback(reason)
        end
      rescue
        error ->
          Repo.query!("ROLLBACK TO SAVEPOINT #{name}")
          Repo.rollback(error)
      end
    end)
  end
end