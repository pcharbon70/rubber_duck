defmodule RubberDuck.RAG.VectorStore do
  @moduledoc """
  Vector store abstraction for the RAG pipeline.

  Provides a unified interface for vector storage and retrieval operations,
  wrapping the existing pgvector integration with advanced features like
  partitioned search, query optimization, and hybrid retrieval.
  """

  require Logger
  alias RubberDuck.{Workspace, Embeddings}
  require Ash.Query

  @type search_strategy :: :semantic | :keyword | :hybrid
  @type vector :: [float()]

  @doc """
  Indexes a processed document in the vector store.

  Stores document chunks with their embeddings and metadata.
  """
  @spec index_document(String.t(), map(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def index_document(document_id, processed_document, project_id \\ nil) do
    # For now, we'll store in the existing CodeFile resource
    # In a full implementation, we might create a dedicated DocumentChunk resource

    chunks = processed_document.chunks
    metadata = processed_document.metadata

    # Create or update a code file record for each chunk
    results =
      Enum.map(chunks, fn chunk ->
        file_path = build_chunk_path(document_id, chunk.metadata.index)

        attrs = %{
          file_path: file_path,
          content: chunk.content,
          language: metadata[:language] || "text",
          embeddings: chunk.embedding,
          ast_cache: %{
            chunk_metadata: chunk.metadata,
            document_metadata: metadata
          }
        }

        # Add project association if provided
        attrs =
          if project_id do
            Map.put(attrs, :project_id, project_id)
          else
            attrs
          end

        case create_or_update_code_file(attrs) do
          {:ok, _file} -> :ok
          error -> error
        end
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      {:ok, %{document_id: document_id, chunks_indexed: length(chunks)}}
    else
      {:error, :indexing_failed}
    end
  end

  @doc """
  Retrieves a document by ID from the vector store.
  """
  @spec get_document(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_document(document_id) do
    # Reconstruct document from chunks
    pattern = "rag_doc:#{document_id}:"

    # For now, use basic filtering - would need custom filter for LIKE queries
    case Workspace.list_code_files() do
      {:ok, all_files} ->
        # Filter files matching the pattern
        files =
          Enum.filter(all_files, fn file ->
            String.starts_with?(file.file_path, pattern)
          end)

        if files == [] do
          {:error, :not_found}
        else
          chunks =
            Enum.map(files, fn file ->
              %{
                content: file.content,
                embedding: file.embeddings,
                metadata: get_in(file.ast_cache, ["chunk_metadata"]) || %{}
              }
            end)

          document = %{
            content: Enum.map_join(chunks, "\n", & &1.content),
            chunks: chunks,
            metadata: get_in(List.first(files).ast_cache, ["document_metadata"]) || %{}
          }

          {:ok, document}
        end

      error ->
        error
    end
  end

  @doc """
  Updates an existing document in the vector store.
  """
  @spec update_document(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_document(document_id, processed_document) do
    # Delete existing chunks
    pattern = "rag_doc:#{document_id}:"

    case delete_document_chunks(pattern) do
      :ok -> index_document(document_id, processed_document)
      error -> error
    end
  end

  @doc """
  Searches the vector store using various strategies.

  Supports semantic search, keyword search, and hybrid approaches.
  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :hybrid)
    limit = Keyword.get(opts, :limit, 10)
    project_id = Keyword.get(opts, :project_id)

    case strategy do
      :semantic -> semantic_search(query, limit, project_id)
      :keyword -> keyword_search(query, limit, project_id)
      :hybrid -> hybrid_search(query, limit, project_id)
      _ -> {:error, :invalid_strategy}
    end
  end

  @doc """
  Performs similarity search using vector embeddings.

  Uses cosine similarity to find the most relevant chunks.
  """
  @spec similarity_search(vector(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def similarity_search(query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, 0.7)
    project_id = Keyword.get(opts, :project_id)

    # Get all relevant code files
    files =
      case project_id do
        nil ->
          Workspace.list_code_files()

        id ->
          # Build query with filter
          query =
            RubberDuck.Workspace.CodeFile
            |> Ash.Query.filter(project_id == ^id)

          Workspace.list_code_files(query: query)
      end

    case files do
      {:ok, files} ->
        # Calculate similarities and filter
        results =
          files
          |> Enum.filter(& &1.embeddings)
          |> Enum.map(fn file ->
            similarity = Embeddings.Service.cosine_similarity(query_embedding, file.embeddings)

            %{
              content: file.content,
              metadata: %{
                file_path: file.file_path,
                language: file.language,
                chunk_metadata: get_in(file.ast_cache, ["chunk_metadata"]) || %{}
              },
              score: similarity
            }
          end)
          |> Enum.filter(&(&1.score >= threshold))
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(limit)

        {:ok, results}

      error ->
        error
    end
  end

  # Private functions

  defp build_chunk_path(document_id, chunk_index) do
    "rag_doc:#{document_id}:#{String.pad_leading(to_string(chunk_index), 4, "0")}"
  end

  defp create_or_update_code_file(attrs) do
    # Check if file exists by querying with file_path filter
    query =
      RubberDuck.Workspace.CodeFile
      |> Ash.Query.filter(file_path == ^attrs.file_path)

    case Workspace.list_code_files(query: query) do
      {:ok, [existing | _]} ->
        Workspace.update_code_file(existing, attrs)

      {:ok, []} ->
        Workspace.create_code_file(attrs)

      error ->
        error
    end
  end

  defp delete_document_chunks(pattern) do
    case Workspace.list_code_files() do
      {:ok, all_files} ->
        # Filter files matching the pattern
        files_to_delete =
          Enum.filter(all_files, fn file ->
            String.starts_with?(file.file_path, pattern)
          end)

        Enum.each(files_to_delete, &Workspace.delete_code_file/1)
        :ok

      error ->
        error
    end
  end

  defp semantic_search(query, limit, project_id) do
    with {:ok, query_embedding} <- Embeddings.Service.generate(query) do
      similarity_search(query_embedding, limit: limit, project_id: project_id)
    end
  end

  defp keyword_search(query, limit, project_id) do
    # Simple keyword search implementation
    keywords = String.split(String.downcase(query), ~r/\s+/)

    files =
      case project_id do
        nil -> Workspace.list_code_files()
        id -> Workspace.list_code_files(filter: [project_id: id])
      end

    case files do
      {:ok, files} ->
        results =
          files
          |> Enum.map(fn file ->
            content_lower = String.downcase(file.content)
            score = Enum.count(keywords, &String.contains?(content_lower, &1)) / length(keywords)

            %{
              content: file.content,
              metadata: %{
                file_path: file.file_path,
                language: file.language
              },
              score: score
            }
          end)
          |> Enum.filter(&(&1.score > 0))
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(limit)

        {:ok, results}

      error ->
        error
    end
  end

  defp hybrid_search(query, limit, project_id) do
    # Combine semantic and keyword search results
    tasks = [
      Task.async(fn -> semantic_search(query, limit * 2, project_id) end),
      Task.async(fn -> keyword_search(query, limit * 2, project_id) end)
    ]

    results = Task.await_many(tasks, 5000)

    case results do
      [{:ok, semantic_results}, {:ok, keyword_results}] ->
        # Merge and rerank results
        merged =
          merge_search_results(semantic_results, keyword_results)
          |> Enum.take(limit)

        {:ok, merged}

      _ ->
        {:error, :search_failed}
    end
  end

  defp merge_search_results(semantic_results, keyword_results) do
    # Simple merging strategy - can be enhanced with more sophisticated reranking
    all_results = semantic_results ++ keyword_results

    all_results
    |> Enum.group_by(& &1.content)
    |> Enum.map(fn {_content, duplicates} ->
      # Take the highest scoring version
      Enum.max_by(duplicates, & &1.score)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end
end
