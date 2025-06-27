defmodule RubberDuckStorage.Repos.AnalysisResultRepo do
  @moduledoc """
  Repository for managing analysis result persistence operations with caching support.
  """

  import Ecto.Query, warn: false
  alias RubberDuckStorage.Repo
  alias RubberDuckStorage.Schemas.AnalysisResult

  @doc """
  Gets a single analysis result by id.
  """
  def get(id) do
    Repo.get(AnalysisResult, id)
  end

  @doc """
  Gets a single analysis result by id, raising if not found.
  """
  def get!(id) do
    Repo.get!(AnalysisResult, id)
  end

  @doc """
  Lists analysis results for an engine session.
  """
  def list_for_engine_session(engine_session_id, opts \\ []) do
    query = from(ar in AnalysisResult, where: ar.engine_session_id == ^engine_session_id)

    query
    |> maybe_filter_by_result_type(opts[:result_type])
    |> maybe_filter_by_min_confidence(opts[:min_confidence])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.confidence, desc: ar.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists analysis results by result type across all engine sessions.
  """
  def list_by_result_type(result_type, opts \\ []) do
    query = from(ar in AnalysisResult, where: ar.result_type == ^result_type)

    query
    |> maybe_filter_by_min_confidence(opts[:min_confidence])
    |> maybe_filter_by_tags(opts[:tags])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.confidence, desc: ar.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets analysis results by tags.
  """
  def get_by_tags(tags, opts \\ []) when is_list(tags) do
    query = from(ar in AnalysisResult, where: fragment("? && ?", ar.tags, ^tags))

    query
    |> maybe_filter_by_result_type(opts[:result_type])
    |> maybe_filter_by_min_confidence(opts[:min_confidence])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.confidence, desc: ar.inserted_at)
    |> Repo.all()
  end

  @doc """
  Adds an analysis result.
  """
  def add(attrs) when is_map(attrs) do
    AnalysisResult.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Adds multiple analysis results in a single transaction.
  """
  def add_batch(results_attrs) when is_list(results_attrs) do
    Repo.transaction(fn ->
      Enum.map(results_attrs, fn attrs ->
        case add(attrs) do
          {:ok, result} -> result
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Changes an analysis result by struct or id.
  """
  def change(%AnalysisResult{} = analysis_result, attrs) do
    analysis_result
    |> AnalysisResult.changeset(attrs)
    |> Repo.update()
  end

  def change(id, attrs) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      analysis_result -> change(analysis_result, attrs)
    end
  end

  @doc """
  Removes an analysis result by struct or id.
  """
  def remove(%AnalysisResult{} = analysis_result) do
    Repo.delete(analysis_result)
  end

  def remove(id) when is_binary(id) do
    case get(id) do
      nil -> {:error, :not_found}
      analysis_result -> remove(analysis_result)
    end
  end

  @doc """
  Gets high-confidence analysis results (confidence >= threshold).
  """
  def get_high_confidence(threshold \\ 0.8, opts \\ []) do
    query = from(ar in AnalysisResult, where: ar.confidence >= ^threshold)

    query
    |> maybe_filter_by_result_type(opts[:result_type])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.confidence, desc: ar.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets analysis results for a conversation through engine sessions.
  """
  def list_for_conversation(conversation_id, opts \\ []) do
    query = 
      from(ar in AnalysisResult,
        join: es in assoc(ar, :engine_session),
        where: es.conversation_id == ^conversation_id
      )

    query
    |> maybe_filter_by_result_type(opts[:result_type])
    |> maybe_filter_by_min_confidence(opts[:min_confidence])
    |> maybe_limit(opts[:limit])
    |> order_by([ar], desc: ar.confidence, desc: ar.inserted_at)
    |> Repo.all()
  end

  @doc """
  Counts analysis results for an engine session.
  """
  def count_for_engine_session(engine_session_id) do
    from(ar in AnalysisResult, where: ar.engine_session_id == ^engine_session_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets analysis results grouped by result type with counts.
  """
  def get_summary_by_result_type do
    from(ar in AnalysisResult,
      group_by: ar.result_type,
      select: {ar.result_type, count(ar.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp maybe_filter_by_result_type(query, nil), do: query
  defp maybe_filter_by_result_type(query, result_type) do
    from(ar in query, where: ar.result_type == ^result_type)
  end

  defp maybe_filter_by_min_confidence(query, nil), do: query
  defp maybe_filter_by_min_confidence(query, min_confidence) do
    from(ar in query, where: ar.confidence >= ^min_confidence)
  end

  defp maybe_filter_by_tags(query, nil), do: query
  defp maybe_filter_by_tags(query, tags) when is_list(tags) do
    from(ar in query, where: fragment("? && ?", ar.tags, ^tags))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) do
    from(ar in query, limit: ^limit)
  end
end