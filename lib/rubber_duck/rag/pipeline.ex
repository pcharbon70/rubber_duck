defmodule RubberDuck.RAG.Pipeline do
  @moduledoc """
  Central coordinator for the enhanced RAG (Retrieval Augmented Generation) pipeline.
  
  Orchestrates document processing, chunking, embedding generation, and indexing
  using existing services while providing advanced features like parallel processing
  and incremental updates.
  """
  
  require Logger
  
  alias RubberDuck.Embeddings
  alias RubberDuck.RAG.{Chunking, VectorStore}
  
  @type document :: %{
    required(:content) => String.t(),
    required(:metadata) => map()
  }
  
  @type processed_document :: %{
    required(:chunks) => [chunk()],
    required(:metadata) => map(),
    required(:processing_time_ms) => integer()
  }
  
  @type chunk :: %{
    required(:content) => String.t(),
    required(:embedding) => [float()],
    required(:metadata) => map(),
    required(:position) => integer()
  }
  
  @type index_result :: %{
    required(:document_id) => String.t(),
    required(:status) => :indexed | :failed,
    optional(:error) => term()
  }
  
  @doc """
  Processes a single document through the full RAG pipeline.
  
  Steps:
  1. Chunk the document based on content and metadata
  2. Generate embeddings for each chunk
  3. Add position and metadata to chunks
  4. Return processed document with chunks
  """
  @spec process_document(document(), keyword()) :: {:ok, processed_document()} | {:error, term()}
  def process_document(document, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, chunks} <- Chunking.chunk_document(document.content, document.metadata),
         {:ok, chunks_with_embeddings} <- generate_embeddings_for_chunks(chunks, opts) do
      
      processed = %{
        chunks: chunks_with_embeddings,
        metadata: document.metadata,
        processing_time_ms: System.monotonic_time(:millisecond) - start_time
      }
      
      {:ok, processed}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process document: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Processes and indexes multiple documents in parallel.
  
  Uses Task.async_stream for concurrent processing with back-pressure control.
  """
  @spec index_documents([document()], keyword()) :: {:ok, [index_result()]} | {:error, term()}
  def index_documents(documents, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online() * 2)
    timeout = Keyword.get(opts, :timeout, 30_000)
    project_id = Keyword.get(opts, :project_id)
    
    Logger.info("Indexing #{length(documents)} documents with max concurrency: #{max_concurrency}")
    
    results = 
      documents
      |> Task.async_stream(
        fn doc -> process_and_index_document(doc, project_id) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> %{document_id: "unknown", status: :failed, error: :timeout}
        {:exit, reason} -> %{document_id: "unknown", status: :failed, error: reason}
      end)
    
    {:ok, results}
  end
  
  @doc """
  Updates the index incrementally with new or modified documents.
  
  Detects changes and only processes modified content to optimize performance.
  """
  @spec update_index(document(), keyword()) :: {:ok, index_result()} | {:error, term()}
  def update_index(document, opts \\ []) do
    document_id = get_document_id(document)
    
    with {:ok, existing} <- VectorStore.get_document(document_id),
         true <- document_changed?(document, existing),
         {:ok, processed} <- process_document(document, opts),
         {:ok, _} <- VectorStore.update_document(document_id, processed) do
      
      {:ok, %{document_id: document_id, status: :indexed}}
    else
      false ->
        # Document hasn't changed, skip processing
        {:ok, %{document_id: document_id, status: :indexed}}
      
      {:error, :not_found} ->
        # New document, process and index
        process_and_index_document(document, opts[:project_id])
      
      {:error, reason} = error ->
        Logger.error("Failed to update index for document #{document_id}: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Retrieves documents similar to a query using the enhanced pipeline.
  
  Supports multiple retrieval strategies and reranking.
  """
  @spec retrieve(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def retrieve(query, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :hybrid)
    limit = Keyword.get(opts, :limit, 10)
    
    with {:ok, results} <- VectorStore.search(query, strategy: strategy, limit: limit * 2),
         {:ok, reranked} <- rerank_results(results, query, opts) do
      
      {:ok, Enum.take(reranked, limit)}
    end
  end
  
  # Private functions
  
  defp generate_embeddings_for_chunks(chunks, opts) do
    # Process chunks in batches for efficiency
    batch_size = Keyword.get(opts, :batch_size, 10)
    
    chunks
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      texts = Enum.map(batch, & &1.content)
      
      case Embeddings.Service.generate_batch(texts, []) do
        {:ok, embeddings} ->
          chunks_with_embeddings = 
            batch
            |> Enum.zip(embeddings)
            |> Enum.with_index(length(acc))
            |> Enum.map(fn {{chunk, embedding}, position} ->
              Map.merge(chunk, %{
                embedding: embedding,
                position: position
              })
            end)
          
          {:cont, {:ok, acc ++ chunks_with_embeddings}}
        
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
  
  defp process_and_index_document(document, project_id) do
    document_id = get_document_id(document)
    
    try do
      with {:ok, processed} <- process_document(document),
           {:ok, _} <- VectorStore.index_document(document_id, processed, project_id) do
        
        %{document_id: document_id, status: :indexed}
      else
        {:error, reason} ->
          %{document_id: document_id, status: :failed, error: reason}
      end
    catch
      kind, reason ->
        Logger.error("Unexpected error processing document #{document_id}: #{inspect({kind, reason})}")
        %{document_id: document_id, status: :failed, error: {kind, reason}}
    end
  end
  
  defp get_document_id(document) do
    # Generate consistent ID from document metadata or content
    source = get_in(document, [:metadata, :source]) || "unknown"
    :crypto.hash(:sha256, "#{source}:#{document.content}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
  
  defp document_changed?(new_doc, existing_doc) do
    # Simple change detection based on content hash
    # Could be enhanced with more sophisticated comparison
    hash_content(new_doc.content) != hash_content(existing_doc.content)
  end
  
  defp hash_content(content) do
    :crypto.hash(:sha256, content)
  end
  
  defp rerank_results(results, _query, _opts) do
    # TODO: Implement sophisticated reranking with cross-encoder
    # For now, return results as-is
    {:ok, results}
  end
end