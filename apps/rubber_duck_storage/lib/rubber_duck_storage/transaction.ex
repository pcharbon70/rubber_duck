defmodule RubberDuckStorage.Transaction do
  @moduledoc """
  Transaction helper utilities for complex database operations.

  This module provides convenience functions for managing database transactions
  and ensures data consistency across multiple repository operations.
  """

  alias RubberDuckStorage.{Repo, Repository}
  alias RubberDuckCore.Conversation

  require Logger

  @doc """
  Creates a complete conversation with messages in a single transaction.
  """
  def add_conversation_with_messages(project_id, %Conversation{} = conversation, messages)
      when is_list(messages) do
    Repo.transaction(fn ->
      # Create the conversation first
      case Repository.add_conversation(project_id, conversation) do
        {:ok, stored_conversation} ->
          # Create messages in batch
          case Repository.add_messages_batch(project_id, conversation.id, messages) do
            {:ok, stored_messages} ->
              Logger.info(
                "Created conversation #{conversation.id} with #{length(stored_messages)} messages in project #{project_id}"
              )

              %{conversation: stored_conversation, messages: stored_messages}

            {:error, reason} ->
              Logger.error(
                "Failed to add messages for conversation #{conversation.id} in project #{project_id}: #{inspect(reason)}"
              )

              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error(
            "Failed to add conversation #{conversation.id} in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates conversation and adds new messages atomically.
  """
  def change_conversation_and_add_messages(
        project_id,
        conversation_id,
        conversation_updates,
        new_messages
      ) do
    Repo.transaction(fn ->
      # Update conversation
      case Repository.change_conversation(project_id, conversation_id, conversation_updates) do
        {:ok, changed_conversation} ->
          # Add new messages
          case Repository.add_messages_batch(project_id, conversation_id, new_messages) do
            {:ok, stored_messages} ->
              Logger.info(
                "Updated conversation #{conversation_id} and added #{length(stored_messages)} messages in project #{project_id}"
              )

              %{conversation: changed_conversation, messages: stored_messages}

            {:error, reason} ->
              Logger.error(
                "Failed to add messages to conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
              )

              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error(
            "Failed to change conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates an engine session with initial analysis results in a single transaction.
  """
  def add_engine_session_with_results(project_id, session_attrs, analysis_results_attrs) do
    Repo.transaction(fn ->
      # Create engine session
      case Repository.add_engine_session(project_id, session_attrs) do
        {:ok, engine_session} ->
          # Create analysis results if provided
          if length(analysis_results_attrs) > 0 do
            case Repository.add_analysis_results_batch(
                   project_id,
                   engine_session.id,
                   analysis_results_attrs
                 ) do
              {:ok, analysis_results} ->
                Logger.info(
                  "Created engine session #{engine_session.id} with #{length(analysis_results)} results in project #{project_id}"
                )

                %{engine_session: engine_session, analysis_results: analysis_results}

              {:error, reason} ->
                Logger.error(
                  "Failed to add analysis results for session #{engine_session.id} in project #{project_id}: #{inspect(reason)}"
                )

                Repo.rollback(reason)
            end
          else
            Logger.info(
              "Created engine session #{engine_session.id} without initial results in project #{project_id}"
            )

            %{engine_session: engine_session, analysis_results: []}
          end

        {:error, reason} ->
          Logger.error(
            "Failed to add engine session in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Completes an engine session and adds final analysis results atomically.
  """
  def complete_engine_session_with_results(project_id, session_id, final_results_attrs) do
    Repo.transaction(fn ->
      # Complete the session
      case Repository.complete_engine_session(project_id, session_id) do
        {:ok, completed_session} ->
          # Create final results if provided
          if length(final_results_attrs) > 0 do
            case Repository.add_analysis_results_batch(
                   project_id,
                   session_id,
                   final_results_attrs
                 ) do
              {:ok, analysis_results} ->
                Logger.info(
                  "Completed engine session #{session_id} with #{length(analysis_results)} final results in project #{project_id}"
                )

                %{engine_session: completed_session, analysis_results: analysis_results}

              {:error, reason} ->
                Logger.error(
                  "Failed to add final results for session #{session_id} in project #{project_id}: #{inspect(reason)}"
                )

                Repo.rollback(reason)
            end
          else
            Logger.info(
              "Completed engine session #{session_id} without final results in project #{project_id}"
            )

            %{engine_session: completed_session, analysis_results: []}
          end

        {:error, reason} ->
          Logger.error(
            "Failed to complete engine session #{session_id} in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Archives a conversation and all related data.
  """
  def archive_conversation(project_id, conversation_id) do
    Repo.transaction(fn ->
      # Archive the conversation
      case Repository.archive_conversation(project_id, conversation_id) do
        {:ok, archived_conversation} ->
          # Get related engine sessions
          case Repository.list_engine_sessions_for_conversation(project_id, conversation_id) do
            {:ok, engine_sessions} ->
              # Complete any running sessions
              running_sessions =
                Enum.filter(engine_sessions, fn session ->
                  session.status == :running
                end)

              completed_sessions =
                Enum.map(running_sessions, fn session ->
                  case Repository.fail_engine_session(
                         project_id,
                         session.id,
                         "Conversation archived"
                       ) do
                    {:ok, failed_session} -> failed_session
                    {:error, reason} -> Repo.rollback(reason)
                  end
                end)

              Logger.info(
                "Archived conversation #{conversation_id} and terminated #{length(completed_sessions)} running sessions in project #{project_id}"
              )

              %{
                conversation: archived_conversation,
                terminated_sessions: completed_sessions
              }

            {:error, reason} ->
              Logger.error(
                "Failed to get engine sessions for conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
              )

              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error(
            "Failed to archive conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
          )

          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Safely removes a conversation and all related data.
  """
  def remove_conversation_cascade(project_id, conversation_id) do
    Repo.transaction(fn ->
      # Get related data for logging
      case Repository.list_messages(project_id, conversation_id) do
        {:ok, messages} ->
          messages_count = length(messages)

          case Repository.list_engine_sessions_for_conversation(project_id, conversation_id) do
            {:ok, engine_sessions} ->
              # Remove conversation (cascading will handle related data due to foreign key constraints)
              case Repository.remove_conversation(project_id, conversation_id) do
                {:ok, removed_conversation} ->
                  Logger.info(
                    "Removed conversation #{conversation_id} with #{messages_count} messages and #{length(engine_sessions)} engine sessions from project #{project_id}"
                  )

                  %{
                    conversation: removed_conversation,
                    removed_messages_count: messages_count,
                    removed_sessions_count: length(engine_sessions)
                  }

                {:error, reason} ->
                  Logger.error(
                    "Failed to remove conversation #{conversation_id} from project #{project_id}: #{inspect(reason)}"
                  )

                  Repo.rollback(reason)
              end

            {:error, reason} ->
              Logger.error(
                "Failed to get engine sessions for conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
              )

              Repo.rollback(reason)
          end

        {:error, reason} ->
          Logger.error(
            "Failed to get messages for conversation #{conversation_id} in project #{project_id}: #{inspect(reason)}"
          )

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

        Logger.warning(
          "Operation failed (attempt #{attempt}/#{max_attempts}), retrying in #{delay}ms: #{inspect(reason)}"
        )

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
