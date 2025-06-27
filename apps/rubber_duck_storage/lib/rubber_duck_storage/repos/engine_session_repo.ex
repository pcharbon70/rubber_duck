defmodule RubberDuckStorage.Repos.EngineSessionRepo do
  @moduledoc """
  Repository for managing engine session persistence operations.
  """

  import Ecto.Query, warn: false
  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Schemas.EngineSession

  @doc """
  Gets a single engine session by id.
  """
  def get(id) do
    Repo.get(EngineSession, id)
  end

  @doc """
  Gets a single engine session by id, raising if not found.
  """
  def get!(id) do
    Repo.get!(EngineSession, id)
  end

  @doc """
  Gets an engine session with analysis results preloaded.
  """
  def get_with_results(id) do
    EngineSession
    |> where([es], es.id == ^id)
    |> preload(:analysis_results)
    |> Repo.one()
  end

  @doc """
  Lists engine sessions for a conversation.
  """
  def list_for_conversation(conversation_id, opts \\ []) do
    query = from(es in EngineSession, where: es.conversation_id == ^conversation_id)

    query
    |> maybe_filter_by_engine_type(opts[:engine_type])
    |> maybe_filter_by_status(opts[:status])
    |> maybe_limit(opts[:limit])
    |> order_by([es], desc: es.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists engine sessions by status across all conversations.
  """
  def list_by_status(status, opts \\ []) do
    query = from(es in EngineSession, where: es.status == ^status)

    query
    |> maybe_filter_by_engine_type(opts[:engine_type])
    |> maybe_limit(opts[:limit])
    |> order_by([es], asc: es.inserted_at)
    |> Repo.all()
  end

  @doc """
  Adds an engine session.
  """
  def add(attrs) when is_map(attrs) do
    EngineSession.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Changes an engine session by struct or id.
  """
  def change(%EngineSession{} = engine_session, attrs) do
    engine_session
    |> EngineSession.changeset(attrs)
    |> Repo.update()
  end

  def change(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      engine_session -> change(engine_session, attrs)
    end
  end

  @doc """
  Starts an engine session (sets status to :running and started_at timestamp).
  """
  def start(%EngineSession{} = engine_session) do
    engine_session
    |> EngineSession.start_changeset()
    |> Repo.update()
  end

  def start(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      engine_session -> start(engine_session)
    end
  end

  @doc """
  Completes an engine session (sets status to :completed and completed_at timestamp).
  """
  def complete(%EngineSession{} = engine_session) do
    engine_session
    |> EngineSession.complete_changeset()
    |> Repo.update()
  end

  def complete(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      engine_session -> complete(engine_session)
    end
  end

  @doc """
  Fails an engine session (sets status to :failed, completed_at timestamp, and error message).
  """
  def fail(%EngineSession{} = engine_session, error_message) do
    engine_session
    |> EngineSession.fail_changeset(error_message)
    |> Repo.update()
  end

  def fail(id, error_message) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      engine_session -> fail(engine_session, error_message)
    end
  end

  @doc """
  Removes an engine session by struct or id.
  """
  def remove(%EngineSession{} = engine_session) do
    Repo.delete(engine_session)
  end

  def remove(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      engine_session -> remove(engine_session)
    end
  end

  @doc """
  Gets currently running engine sessions.
  """
  def get_running(opts \\ []) do
    list_by_status(:running, opts)
  end

  @doc """
  Gets pending engine sessions.
  """
  def get_pending(opts \\ []) do
    list_by_status(:pending, opts)
  end

  @doc """
  Gets engine sessions that have been running longer than the specified timeout.
  """
  def get_timed_out(timeout_minutes \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-timeout_minutes, :minute)

    from(es in EngineSession,
      where: es.status == :running and es.started_at < ^cutoff,
      order_by: [asc: es.started_at]
    )
    |> Repo.all()
  end

  defp maybe_filter_by_engine_type(query, nil), do: query
  defp maybe_filter_by_engine_type(query, engine_type) do
    from(es in query, where: es.engine_type == ^engine_type)
  end

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status) do
    from(es in query, where: es.status == ^status)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) do
    from(es in query, limit: ^limit)
  end
end