defmodule RubberDuck.Embeddings.Service do
  @moduledoc """
  Service for generating and managing embeddings for semantic search.

  Supports multiple embedding models and includes caching for efficiency.
  """

  use GenServer
  require Logger

  @default_model "text-embedding-ada-002"
  @cache_ttl_hours 24

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates an embedding for the given text.
  """
  def generate(text, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    GenServer.call(__MODULE__, {:generate, text, model}, 30_000)
  end

  @doc """
  Generates embeddings for multiple texts in batch.
  """
  def generate_batch(texts, opts \\ []) when is_list(texts) do
    model = Keyword.get(opts, :model, @default_model)
    GenServer.call(__MODULE__, {:generate_batch, texts, model}, 60_000)
  end

  @doc """
  Calculates cosine similarity between two embeddings.
  """
  def cosine_similarity(embedding1, embedding2) when is_list(embedding1) and is_list(embedding2) do
    if length(embedding1) != length(embedding2) do
      {:error, :dimension_mismatch}
    else
      dot_product =
        Enum.zip(embedding1, embedding2)
        |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)

      magnitude1 = :math.sqrt(Enum.reduce(embedding1, 0.0, fn x, acc -> acc + x * x end))
      magnitude2 = :math.sqrt(Enum.reduce(embedding2, 0.0, fn x, acc -> acc + x * x end))

      if magnitude1 == 0.0 or magnitude2 == 0.0 do
        0.0
      else
        dot_product / (magnitude1 * magnitude2)
      end
    end
  end

  @doc """
  Finds the k most similar embeddings from a list.
  """
  def find_similar(query_embedding, embeddings, k \\ 5) when is_list(embeddings) do
    embeddings
    |> Enum.map(fn {id, embedding} ->
      {id, cosine_similarity(query_embedding, embedding)}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(k)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Initialize ETS cache for embeddings
    :ets.new(:embeddings_cache, [:set, :public, :named_table])

    state = %{
      model_dimensions: %{
        "text-embedding-ada-002" => 1536,
        "text-embedding-3-small" => 1536,
        "text-embedding-3-large" => 3072
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:generate, text, model}, _from, state) do
    case get_cached_embedding(text, model) do
      {:ok, embedding} ->
        {:reply, {:ok, embedding}, state}

      :miss ->
        case generate_embedding(text, model, state) do
          {:ok, embedding} ->
            cache_embedding(text, model, embedding)
            {:reply, {:ok, embedding}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:generate_batch, texts, model}, _from, state) do
    # Check cache first
    {cached, uncached} = partition_by_cache(texts, model)

    # Generate embeddings for uncached texts
    new_embeddings =
      if length(uncached) > 0 do
        {:ok, embeddings} = generate_batch_embeddings(uncached, model, state)
        # Cache the new embeddings
        Enum.zip(uncached, embeddings)
        |> Enum.each(fn {text, embedding} ->
          cache_embedding(text, model, embedding)
        end)

        embeddings
      else
        []
      end

    # Combine cached and new embeddings in original order
    all_embeddings = merge_embeddings(texts, cached, uncached, new_embeddings)

    {:reply, {:ok, all_embeddings}, state}
  end

  # Private functions

  defp generate_embedding(text, model, state) do
    # TODO: Integrate with actual LLM service when embedding endpoint is available
    # For now, generate mock embeddings
    Logger.debug("Generating mock embedding for text: #{String.slice(text, 0, 50)}...")

    # Generate deterministic mock embedding based on text
    dimensions = Map.get(state.model_dimensions, model, 1536)
    embedding = generate_mock_embedding(text, dimensions)

    {:ok, embedding}
  end

  defp generate_mock_embedding(text, dimensions) do
    # Create a deterministic but varied embedding based on text
    hash = :crypto.hash(:sha256, text)
    hash_bytes = :binary.bin_to_list(hash)

    # Generate embedding values
    Enum.map(1..dimensions, fn i ->
      # Use hash bytes cyclically to generate values between -1 and 1
      byte = Enum.at(hash_bytes, rem(i, length(hash_bytes)))
      (byte - 128) / 128.0
    end)
  end

  defp generate_batch_embeddings(texts, model, state) do
    # For now, generate mock embeddings for each text
    dimensions = Map.get(state.model_dimensions, model, 1536)

    embeddings =
      Enum.map(texts, fn text ->
        generate_mock_embedding(text, dimensions)
      end)

    {:ok, embeddings}
  end

  defp get_cached_embedding(text, model) do
    key = cache_key(text, model)

    case :ets.lookup(:embeddings_cache, key) do
      [{^key, embedding, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, embedding}
        else
          # Expired
          :ets.delete(:embeddings_cache, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache_embedding(text, model, embedding) do
    key = cache_key(text, model)
    expiry = DateTime.add(DateTime.utc_now(), @cache_ttl_hours * 3600, :second)
    :ets.insert(:embeddings_cache, {key, embedding, expiry})
  end

  defp cache_key(text, model) do
    data = "#{model}:#{text}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp partition_by_cache(texts, model) do
    Enum.reduce(texts, {[], []}, fn text, {cached, uncached} ->
      case get_cached_embedding(text, model) do
        {:ok, embedding} ->
          {[{text, embedding} | cached], uncached}

        :miss ->
          {cached, [text | uncached]}
      end
    end)
    |> then(fn {cached, uncached} ->
      {Enum.reverse(cached), Enum.reverse(uncached)}
    end)
  end

  defp merge_embeddings(original_texts, cached, uncached_texts, new_embeddings) do
    # Create a map of text -> embedding
    cached_map = Map.new(cached)

    uncached_map =
      Enum.zip(uncached_texts, new_embeddings)
      |> Map.new()

    # Return embeddings in original order
    Enum.map(original_texts, fn text ->
      Map.get(cached_map, text) || Map.get(uncached_map, text)
    end)
  end
end
