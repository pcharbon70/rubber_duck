defmodule RubberDuckStorage.Repository do
  @moduledoc """
  Unified repository for all data operations with project-based data isolation.
  
  This module consolidates all separate repository modules into a single
  interface that enforces project-scoped operations for conversations,
  messages, engine sessions, and analysis results.
  """

  import Ecto.Query, warn: false
  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Schemas.{Project, Conversation, Message, EngineSession, AnalysisResult}
  alias RubberDuckCore.Conversation, as: CoreConversation

  require Logger

  # Project Operations

  @doc """
  Gets a single project by id.
  """
  def get_project(id) do
    Repo.get(Project, id)
  end

  @doc """
  Gets a single project by id, raising if not found.
  """
  def get_project!(id) do
    Repo.get!(Project, id)
  end

  @doc """
  Lists all projects with optional filtering.
  """
  def list_projects(opts \\ []) do
    query = from(p in Project)

    query
    |> maybe_filter_projects_by_archived(opts[:archived])
    |> maybe_limit(opts[:limit])
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
    |> then(&{:ok, &1})
  end

  @doc """
  Adds a new project.
  """
  def add_project(attrs) when is_map(attrs) do
    Project.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Changes a project by struct or id.
  """
  def change_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def change_project(id, attrs) when is_binary(id) do
    case get_project(id) do
      nil -> {:error, :not_found}
      project -> change_project(project, attrs)
    end
  end

  @doc """
  Removes a project by struct or id.
  Note: This will cascade delete all related data.
  """
  def remove_project(%Project{} = project) do
    Repo.delete(project)
  end

  def remove_project(id) when is_binary(id) do
    case get_project(id) do
      nil -> {:error, :not_found}
      project -> remove_project(project)
    end
  end

  @doc """
  Archives a project (sets archived to true).
  """
  def archive_project(id) when is_binary(id) do
    case get_project(id) do
      nil -> {:error, :not_found}
      project -> 
        project
        |> Project.archive_changeset()
        |> Repo.update()
    end
  end

  # Conversation Operations (Project-scoped)

  @doc """
  Gets a single conversation by id within a project scope.
  """
  def get_conversation(project_id, conversation_id) do
    from(c in Conversation,
      where: c.id == ^conversation_id and c.project_id == ^project_id
    )
    |> Repo.one()
  end

  @doc """
  Gets a conversation with its messages preloaded within project scope.
  """
  def get_conversation_with_messages(project_id, conversation_id) do
    from(c in Conversation,
      where: c.id == ^conversation_id and c.project_id == ^project_id,
      preload: [:messages]
    )
    |> Repo.one()
  end

  @doc """
  Lists all conversations for a project with optional filtering.
  """
  def list_conversations(project_id, opts \\ []) do
    query = from(c in Conversation, where: c.project_id == ^project_id)

    query
    |> maybe_filter_conversations_by_status(opts[:status])
    |> maybe_limit(opts[:limit])
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
    |> then(&{:ok, &1})
  end

  @doc """
  Adds a conversation to a project from a RubberDuckCore.Conversation struct or attributes.
  """
  def add_conversation(project_id, %CoreConversation{} = core_conversation) do
    attrs = %{
      id: core_conversation.id,
      title: core_conversation.title,
      status: core_conversation.status,
      context: core_conversation.context,
      project_id: project_id
    }

    Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  def add_conversation(project_id, attrs) when is_map(attrs) do
    attrs_with_project = Map.put(attrs, :project_id, project_id)
    
    Conversation.create_changeset(attrs_with_project)
    |> Repo.insert()
  end

  @doc """
  Changes a conversation within project scope.
  """
  def change_conversation(project_id, conversation_id, attrs) do
    case get_conversation(project_id, conversation_id) do
      nil -> {:error, :not_found}
      conversation -> 
        conversation
        |> Conversation.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Removes a conversation within project scope.
  """
  def remove_conversation(project_id, conversation_id) do
    case get_conversation(project_id, conversation_id) do
      nil -> {:error, :not_found}
      conversation -> Repo.delete(conversation)
    end
  end

  @doc """
  Archives a conversation within project scope.
  """
  def archive_conversation(project_id, conversation_id) do
    change_conversation(project_id, conversation_id, %{status: :archived})
  end

  # Message Operations (Project-scoped through conversation)

  @doc """
  Gets messages for a conversation within project scope.
  """
  def list_messages(project_id, conversation_id, opts \\ []) do
    # First verify the conversation belongs to the project
    conversation_query = from(c in Conversation,
      where: c.id == ^conversation_id and c.project_id == ^project_id,
      select: c.id
    )

    case Repo.one(conversation_query) do
      nil -> {:error, :conversation_not_found}
      _conversation_id ->
        query = from(m in Message, where: m.conversation_id == ^conversation_id)

        query
        |> maybe_filter_messages_by_role(opts[:role])
        |> maybe_limit(opts[:limit])
        |> order_by([m], asc: m.timestamp)
        |> Repo.all()
        |> then(&{:ok, &1})
    end
  end

  @doc """
  Adds a message to a conversation within project scope.
  """
  def add_message(project_id, conversation_id, attrs) when is_map(attrs) do
    # First verify the conversation belongs to the project
    case get_conversation(project_id, conversation_id) do
      nil -> {:error, :conversation_not_found}
      _conversation ->
        attrs_with_conversation = Map.put(attrs, :conversation_id, conversation_id)
        
        Message.create_changeset(attrs_with_conversation)
        |> Repo.insert()
    end
  end

  @doc """
  Adds multiple messages in batch to a conversation within project scope.
  """
  def add_messages_batch(project_id, conversation_id, messages_attrs) when is_list(messages_attrs) do
    # First verify the conversation belongs to the project
    case get_conversation(project_id, conversation_id) do
      nil -> {:error, :conversation_not_found}
      _conversation ->
        changesets = 
          Enum.map(messages_attrs, fn attrs ->
            attrs_with_conversation = Map.put(attrs, :conversation_id, conversation_id)
            Message.create_changeset(attrs_with_conversation)
          end)

        Repo.transaction(fn ->
          Enum.map(changesets, fn changeset ->
            case Repo.insert(changeset) do
              {:ok, message} -> message
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
        end)
    end
  end

  # Engine Session Operations (Project-scoped)

  @doc """
  Gets a single engine session by id within a project scope.
  """
  def get_engine_session(project_id, session_id) do
    from(es in EngineSession,
      where: es.id == ^session_id and es.project_id == ^project_id
    )
    |> Repo.one()
  end

  @doc """
  Gets an engine session with analysis results preloaded within project scope.
  """
  def get_engine_session_with_results(project_id, session_id) do
    from(es in EngineSession,
      where: es.id == ^session_id and es.project_id == ^project_id,
      preload: [:analysis_results]
    )
    |> Repo.one()
  end

  @doc """
  Lists all engine sessions for a project with optional filtering.
  """
  def list_engine_sessions(project_id, opts \\ []) do
    query = from(es in EngineSession, where: es.project_id == ^project_id)

    query
    |> maybe_filter_engine_sessions_by_status(opts[:status])
    |> maybe_filter_engine_sessions_by_type(opts[:engine_type])
    |> maybe_filter_engine_sessions_by_conversation(opts[:conversation_id])
    |> maybe_limit(opts[:limit])
    |> order_by([es], desc: es.updated_at)
    |> Repo.all()
    |> then(&{:ok, &1})
  end

  @doc """
  Lists engine sessions for a specific conversation within project scope.
  """
  def list_engine_sessions_for_conversation(project_id, conversation_id, opts \\ []) do
    # First verify the conversation belongs to the project
    case get_conversation(project_id, conversation_id) do
      nil -> {:error, :conversation_not_found}
      _conversation ->
        query = from(es in EngineSession, 
          where: es.project_id == ^project_id and es.conversation_id == ^conversation_id
        )

        query
        |> maybe_filter_engine_sessions_by_status(opts[:status])
        |> maybe_filter_engine_sessions_by_type(opts[:engine_type])
        |> maybe_limit(opts[:limit])
        |> order_by([es], desc: es.updated_at)
        |> Repo.all()
        |> then(&{:ok, &1})
    end
  end

  @doc """
  Adds an engine session to a project.
  """
  def add_engine_session(project_id, attrs) when is_map(attrs) do
    attrs_with_project = Map.put(attrs, :project_id, project_id)
    
    EngineSession.create_changeset(attrs_with_project)
    |> Repo.insert()
  end

  @doc """
  Starts an engine session within project scope.
  """
  def start_engine_session(project_id, session_id) do
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> EngineSession.start_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Completes an engine session within project scope.
  """
  def complete_engine_session(project_id, session_id) do
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> EngineSession.complete_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Fails an engine session with error message within project scope.
  """
  def fail_engine_session(project_id, session_id, error_message) do
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> EngineSession.fail_changeset(error_message)
        |> Repo.update()
    end
  end

  @doc """
  Changes an engine session within project scope.
  """
  def change_engine_session(project_id, session_id, attrs) do
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :not_found}
      session ->
        session
        |> EngineSession.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Removes an engine session within project scope.
  """
  def remove_engine_session(project_id, session_id) do
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :not_found}
      session -> Repo.delete(session)
    end
  end

  # Analysis Result Operations (Project-scoped)

  @doc """
  Gets a single analysis result by id within a project scope.
  """
  def get_analysis_result(project_id, result_id) do
    from(ar in AnalysisResult,
      where: ar.id == ^result_id and ar.project_id == ^project_id
    )
    |> Repo.one()
  end

  @doc """
  Lists all analysis results for a project with optional filtering.
  """
  def list_analysis_results(project_id, opts \\ []) do
    query = from(ar in AnalysisResult, where: ar.project_id == ^project_id)

    query
    |> maybe_filter_analysis_results_by_type(opts[:result_type])
    |> maybe_filter_analysis_results_by_session(opts[:engine_session_id])
    |> maybe_filter_analysis_results_by_confidence(opts[:min_confidence])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.inserted_at)
    |> Repo.all()
    |> then(&{:ok, &1})
  end

  @doc """
  Lists analysis results for a specific engine session within project scope.
  """
  def list_analysis_results_for_session(project_id, session_id, opts \\ []) do
    # First verify the session belongs to the project
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :session_not_found}
      _session ->
        query = from(ar in AnalysisResult,
          where: ar.project_id == ^project_id and ar.engine_session_id == ^session_id
        )

        query
        |> maybe_filter_analysis_results_by_type(opts[:result_type])
        |> maybe_filter_analysis_results_by_confidence(opts[:min_confidence])
        |> maybe_limit(opts[:limit])
        |> order_by([ar], desc: ar.inserted_at)
        |> Repo.all()
        |> then(&{:ok, &1})
    end
  end

  @doc """
  Adds an analysis result to a project and engine session.
  """
  def add_analysis_result(project_id, session_id, attrs) when is_map(attrs) do
    # First verify the session belongs to the project
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :session_not_found}
      _session ->
        attrs_with_ids = 
          attrs
          |> Map.put(:project_id, project_id)
          |> Map.put(:engine_session_id, session_id)
        
        AnalysisResult.create_changeset(attrs_with_ids)
        |> Repo.insert()
    end
  end

  @doc """
  Adds multiple analysis results in batch to a project and engine session.
  """
  def add_analysis_results_batch(project_id, session_id, results_attrs) when is_list(results_attrs) do
    # First verify the session belongs to the project
    case get_engine_session(project_id, session_id) do
      nil -> {:error, :session_not_found}
      _session ->
        changesets = 
          Enum.map(results_attrs, fn attrs ->
            attrs_with_ids = 
              attrs
              |> Map.put(:project_id, project_id)
              |> Map.put(:engine_session_id, session_id)
            
            AnalysisResult.create_changeset(attrs_with_ids)
          end)

        Repo.transaction(fn ->
          Enum.map(changesets, fn changeset ->
            case Repo.insert(changeset) do
              {:ok, result} -> result
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
        end)
    end
  end

  @doc """
  Changes an analysis result within project scope.
  """
  def change_analysis_result(project_id, result_id, attrs) do
    case get_analysis_result(project_id, result_id) do
      nil -> {:error, :not_found}
      result ->
        result
        |> AnalysisResult.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Removes an analysis result within project scope.
  """
  def remove_analysis_result(project_id, result_id) do
    case get_analysis_result(project_id, result_id) do
      nil -> {:error, :not_found}
      result -> Repo.delete(result)
    end
  end

  # Helper functions for query building

  defp maybe_filter_projects_by_archived(query, nil), do: query
  defp maybe_filter_projects_by_archived(query, archived) do
    from(p in query, where: p.archived == ^archived)
  end

  defp maybe_filter_conversations_by_status(query, nil), do: query
  defp maybe_filter_conversations_by_status(query, status) do
    from(c in query, where: c.status == ^status)
  end

  defp maybe_filter_messages_by_role(query, nil), do: query
  defp maybe_filter_messages_by_role(query, role) do
    from(m in query, where: m.role == ^role)
  end

  defp maybe_filter_engine_sessions_by_status(query, nil), do: query
  defp maybe_filter_engine_sessions_by_status(query, status) do
    from(es in query, where: es.status == ^status)
  end

  defp maybe_filter_engine_sessions_by_type(query, nil), do: query
  defp maybe_filter_engine_sessions_by_type(query, engine_type) do
    from(es in query, where: es.engine_type == ^engine_type)
  end

  defp maybe_filter_engine_sessions_by_conversation(query, nil), do: query
  defp maybe_filter_engine_sessions_by_conversation(query, conversation_id) do
    from(es in query, where: es.conversation_id == ^conversation_id)
  end

  defp maybe_filter_analysis_results_by_type(query, nil), do: query
  defp maybe_filter_analysis_results_by_type(query, result_type) do
    from(ar in query, where: ar.result_type == ^result_type)
  end

  defp maybe_filter_analysis_results_by_session(query, nil), do: query
  defp maybe_filter_analysis_results_by_session(query, session_id) do
    from(ar in query, where: ar.engine_session_id == ^session_id)
  end

  defp maybe_filter_analysis_results_by_confidence(query, nil), do: query
  defp maybe_filter_analysis_results_by_confidence(query, min_confidence) do
    from(ar in query, where: ar.confidence >= ^min_confidence)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) do
    from(q in query, limit: ^limit)
  end
end