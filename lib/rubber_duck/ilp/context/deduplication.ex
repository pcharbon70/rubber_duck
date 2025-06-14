defmodule RubberDuck.ILP.Context.Deduplication do
  @moduledoc """
  Hash-based deduplication for distributed context storage.
  Implements content-based deduplication, similarity detection, and storage optimization.
  """
  use GenServer
  require Logger

  defstruct [
    :hash_index,
    :similarity_index,
    :content_signatures,
    :deduplication_stats,
    :similarity_threshold,
    :hash_algorithm
  ]

  @default_similarity_threshold 0.85
  @hash_algorithms [:sha256, :blake2b, :md5]
  @signature_algorithms [:minhash, :simhash, :fuzzy_hash]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if content already exists and returns existing context ID if found.
  """
  def check_duplicate(content, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:check_duplicate, content, metadata})
  end

  @doc """
  Registers new content in the deduplication index.
  """
  def register_content(context_id, content, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_content, context_id, content, metadata})
  end

  @doc """
  Finds similar content based on configurable similarity threshold.
  """
  def find_similar_content(content, opts \\ []) do
    GenServer.call(__MODULE__, {:find_similar, content, opts})
  end

  @doc """
  Updates content and maintains deduplication index consistency.
  """
  def update_content(context_id, new_content, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:update_content, context_id, new_content, metadata})
  end

  @doc """
  Removes content from deduplication index.
  """
  def remove_content(context_id) do
    GenServer.call(__MODULE__, {:remove_content, context_id})
  end

  @doc """
  Gets deduplication statistics and storage savings.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Performs maintenance on the deduplication index.
  """
  def perform_maintenance do
    GenServer.call(__MODULE__, :perform_maintenance)
  end

  @doc """
  Rebuilds the deduplication index from stored content.
  """
  def rebuild_index(content_list) do
    GenServer.call(__MODULE__, {:rebuild_index, content_list})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting ILP Context Deduplication system")
    
    state = %__MODULE__{
      hash_index: %{},
      similarity_index: %{},
      content_signatures: %{},
      deduplication_stats: initialize_stats(),
      similarity_threshold: Keyword.get(opts, :similarity_threshold, @default_similarity_threshold),
      hash_algorithm: Keyword.get(opts, :hash_algorithm, :sha256)
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:check_duplicate, content, metadata}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    # Calculate content hash
    content_hash = calculate_hash(content, state.hash_algorithm)
    
    # Check exact match first
    case Map.get(state.hash_index, content_hash) do
      nil ->
        # No exact match - check for similar content
        similar_result = find_similar_content_internal(content, state)
        
        end_time = System.monotonic_time(:microsecond)
        new_stats = update_lookup_stats(state.deduplication_stats, end_time - start_time, :miss)
        new_state = %{state | deduplication_stats: new_stats}
        
        case similar_result do
          {:found, context_id, similarity} ->
            {:reply, {:similar, context_id, similarity}, new_state}
          
          :not_found ->
            {:reply, :not_found, new_state}
        end
      
      existing_context_id ->
        # Exact match found
        end_time = System.monotonic_time(:microsecond)
        new_stats = update_lookup_stats(state.deduplication_stats, end_time - start_time, :hit)
        new_state = %{state | deduplication_stats: new_stats}
        
        {:reply, {:exact_match, existing_context_id}, new_state}
    end
  end

  @impl true
  def handle_call({:register_content, context_id, content, metadata}, _from, state) do
    content_hash = calculate_hash(content, state.hash_algorithm)
    content_signature = calculate_signature(content, :minhash)
    
    # Check if hash already exists
    case Map.get(state.hash_index, content_hash) do
      nil ->
        # New content - register it
        new_hash_index = Map.put(state.hash_index, content_hash, context_id)
        new_similarity_index = Map.put(state.similarity_index, context_id, content_signature)
        new_content_signatures = Map.put(state.content_signatures, context_id, %{
          hash: content_hash,
          signature: content_signature,
          size: byte_size(content),
          created_at: System.monotonic_time(:millisecond),
          metadata: metadata
        })
        
        new_stats = update_registration_stats(state.deduplication_stats, byte_size(content), :new)
        
        new_state = %{state |
          hash_index: new_hash_index,
          similarity_index: new_similarity_index,
          content_signatures: new_content_signatures,
          deduplication_stats: new_stats
        }
        
        {:reply, {:ok, :new_content}, new_state}
      
      existing_context_id ->
        # Content already exists - update reference count
        new_stats = update_registration_stats(state.deduplication_stats, byte_size(content), :duplicate)
        new_state = %{state | deduplication_stats: new_stats}
        
        {:reply, {:ok, :duplicate_content, existing_context_id}, new_state}
    end
  end

  @impl true
  def handle_call({:find_similar, content, opts}, _from, state) do
    threshold = Keyword.get(opts, :threshold, state.similarity_threshold)
    max_results = Keyword.get(opts, :max_results, 10)
    
    content_signature = calculate_signature(content, :minhash)
    
    similar_content = state.similarity_index
    |> Enum.map(fn {context_id, signature} ->
      similarity = calculate_similarity(content_signature, signature)
      {context_id, similarity}
    end)
    |> Enum.filter(fn {_context_id, similarity} -> similarity >= threshold end)
    |> Enum.sort_by(fn {_context_id, similarity} -> similarity end, :desc)
    |> Enum.take(max_results)
    |> Enum.map(fn {context_id, similarity} ->
      signatures = Map.get(state.content_signatures, context_id, %{})
      %{
        context_id: context_id,
        similarity: similarity,
        size: signatures[:size] || 0,
        created_at: signatures[:created_at] || 0
      }
    end)
    
    {:reply, {:ok, similar_content}, state}
  end

  @impl true
  def handle_call({:update_content, context_id, new_content, metadata}, _from, state) do
    # Remove old content references
    case Map.get(state.content_signatures, context_id) do
      nil ->
        # Context doesn't exist - treat as new registration
        handle_call({:register_content, context_id, new_content, metadata}, nil, state)
      
      old_signatures ->
        old_hash = old_signatures.hash
        
        # Remove old hash reference if this was the only context using it
        contexts_with_hash = state.hash_index
        |> Enum.filter(fn {_hash, cid} -> cid == context_id end)
        |> Enum.map(fn {hash, _cid} -> hash end)
        
        new_hash_index = if length(contexts_with_hash) == 1 do
          Map.delete(state.hash_index, old_hash)
        else
          state.hash_index
        end
        
        # Register new content
        new_content_hash = calculate_hash(new_content, state.hash_algorithm)
        new_content_signature = calculate_signature(new_content, :minhash)
        
        updated_hash_index = Map.put(new_hash_index, new_content_hash, context_id)
        updated_similarity_index = Map.put(state.similarity_index, context_id, new_content_signature)
        updated_content_signatures = Map.put(state.content_signatures, context_id, %{
          hash: new_content_hash,
          signature: new_content_signature,
          size: byte_size(new_content),
          created_at: System.monotonic_time(:millisecond),
          metadata: metadata
        })
        
        new_stats = update_update_stats(state.deduplication_stats, 
          old_signatures.size, byte_size(new_content))
        
        new_state = %{state |
          hash_index: updated_hash_index,
          similarity_index: updated_similarity_index,
          content_signatures: updated_content_signatures,
          deduplication_stats: new_stats
        }
        
        {:reply, {:ok, :updated}, new_state}
    end
  end

  @impl true
  def handle_call({:remove_content, context_id}, _from, state) do
    case Map.get(state.content_signatures, context_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      signatures ->
        content_hash = signatures.hash
        
        # Remove from all indexes
        new_hash_index = remove_hash_reference(state.hash_index, content_hash, context_id)
        new_similarity_index = Map.delete(state.similarity_index, context_id)
        new_content_signatures = Map.delete(state.content_signatures, context_id)
        
        new_stats = update_removal_stats(state.deduplication_stats, signatures.size)
        
        new_state = %{state |
          hash_index: new_hash_index,
          similarity_index: new_similarity_index,
          content_signatures: new_content_signatures,
          deduplication_stats: new_stats
        }
        
        {:reply, {:ok, :removed}, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    enhanced_stats = enhance_stats_with_calculations(state.deduplication_stats, state)
    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_call(:perform_maintenance, _from, state) do
    Logger.info("Performing deduplication index maintenance")
    
    # Clean up orphaned references
    new_state = cleanup_orphaned_references(state)
    
    # Optimize similarity index
    optimized_state = optimize_similarity_index(new_state)
    
    # Update maintenance stats
    maintenance_stats = Map.put(optimized_state.deduplication_stats, :last_maintenance, 
      System.monotonic_time(:millisecond))
    
    final_state = %{optimized_state | deduplication_stats: maintenance_stats}
    
    {:reply, {:ok, :maintenance_completed}, final_state}
  end

  @impl true
  def handle_call({:rebuild_index, content_list}, _from, state) do
    Logger.info("Rebuilding deduplication index from #{length(content_list)} items")
    
    # Clear existing indexes
    clean_state = %{state |
      hash_index: %{},
      similarity_index: %{},
      content_signatures: %{}
    }
    
    # Rebuild from content list
    final_state = Enum.reduce(content_list, clean_state, fn {context_id, content, metadata}, acc_state ->
      {:reply, _result, new_state} = handle_call({:register_content, context_id, content, metadata}, nil, acc_state)
      new_state
    end)
    
    rebuild_stats = Map.merge(final_state.deduplication_stats, %{
      last_rebuild: System.monotonic_time(:millisecond),
      rebuild_count: (final_state.deduplication_stats[:rebuild_count] || 0) + 1
    })
    
    final_state_with_stats = %{final_state | deduplication_stats: rebuild_stats}
    
    {:reply, {:ok, :index_rebuilt}, final_state_with_stats}
  end

  # Private functions

  defp find_similar_content_internal(content, state) do
    content_signature = calculate_signature(content, :minhash)
    
    similar_matches = state.similarity_index
    |> Enum.map(fn {context_id, signature} ->
      similarity = calculate_similarity(content_signature, signature)
      {context_id, similarity}
    end)
    |> Enum.filter(fn {_context_id, similarity} -> 
      similarity >= state.similarity_threshold
    end)
    |> Enum.sort_by(fn {_context_id, similarity} -> similarity end, :desc)
    
    case similar_matches do
      [] -> :not_found
      [{context_id, similarity} | _] -> {:found, context_id, similarity}
    end
  end

  defp calculate_hash(content, algorithm) do
    case algorithm do
      :sha256 -> :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      :blake2b -> :crypto.hash(:blake2b, content) |> Base.encode16(case: :lower)
      :md5 -> :crypto.hash(:md5, content) |> Base.encode16(case: :lower)
      _ -> :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    end
  end

  defp calculate_signature(content, algorithm) do
    case algorithm do
      :minhash -> calculate_minhash(content)
      :simhash -> calculate_simhash(content)
      :fuzzy_hash -> calculate_fuzzy_hash(content)
      _ -> calculate_minhash(content)
    end
  end

  defp calculate_minhash(content) do
    # Simplified MinHash implementation
    # In production, would use proper MinHash with multiple hash functions
    shingles = create_shingles(content, 3)
    
    hashes = Enum.map(shingles, fn shingle ->
      :crypto.hash(:sha256, shingle) |> :binary.decode_unsigned()
    end)
    
    case hashes do
      [] -> 0
      _ -> Enum.min(hashes)
    end
  end

  defp calculate_simhash(content) do
    # Simplified SimHash implementation
    words = String.split(content, ~r/\W+/)
    
    word_hashes = Enum.map(words, fn word ->
      :crypto.hash(:sha256, word) |> :binary.decode_unsigned()
    end)
    
    case word_hashes do
      [] -> 0
      _ -> Enum.reduce(word_hashes, 0, &Bitwise.bxor/2)
    end
  end

  defp calculate_fuzzy_hash(content) do
    # Simplified fuzzy hash - in production would use ssdeep or similar
    content
    |> String.length()
    |> rem(1000000)
  end

  defp create_shingles(content, size) do
    words = String.split(content, ~r/\W+/)
    
    if length(words) < size do
      [content]
    else
      words
      |> Enum.chunk_every(size, 1, :discard)
      |> Enum.map(&Enum.join(&1, " "))
    end
  end

  defp calculate_similarity(signature1, signature2) do
    # Simplified Jaccard similarity
    case {signature1, signature2} do
      {0, 0} -> 1.0
      {0, _} -> 0.0
      {_, 0} -> 0.0
      {s1, s2} ->
        # Use XOR distance as approximation
        xor_distance = Bitwise.bxor(s1, s2)
        max_distance = max(s1, s2)
        
        if max_distance == 0 do
          1.0
        else
          1.0 - (xor_distance / max_distance)
        end
    end
  end

  defp initialize_stats do
    %{
      total_content_registered: 0,
      unique_content_count: 0,
      duplicate_content_count: 0,
      total_bytes_saved: 0,
      total_lookups: 0,
      cache_hits: 0,
      cache_misses: 0,
      avg_lookup_time: 0,
      created_at: System.monotonic_time(:millisecond)
    }
  end

  defp update_lookup_stats(stats, lookup_time, result) do
    new_total_lookups = stats.total_lookups + 1
    
    updated_stats = %{stats |
      total_lookups: new_total_lookups,
      avg_lookup_time: (stats.avg_lookup_time * stats.total_lookups + lookup_time) / new_total_lookups
    }
    
    case result do
      :hit -> %{updated_stats | cache_hits: stats.cache_hits + 1}
      :miss -> %{updated_stats | cache_misses: stats.cache_misses + 1}
    end
  end

  defp update_registration_stats(stats, content_size, type) do
    case type do
      :new ->
        %{stats |
          total_content_registered: stats.total_content_registered + 1,
          unique_content_count: stats.unique_content_count + 1
        }
      
      :duplicate ->
        %{stats |
          total_content_registered: stats.total_content_registered + 1,
          duplicate_content_count: stats.duplicate_content_count + 1,
          total_bytes_saved: stats.total_bytes_saved + content_size
        }
    end
  end

  defp update_update_stats(stats, old_size, new_size) do
    size_diff = new_size - old_size
    
    %{stats |
      total_bytes_saved: max(0, stats.total_bytes_saved - size_diff)
    }
  end

  defp update_removal_stats(stats, content_size) do
    %{stats |
      unique_content_count: max(0, stats.unique_content_count - 1)
    }
  end

  defp remove_hash_reference(hash_index, content_hash, context_id) do
    case Map.get(hash_index, content_hash) do
      ^context_id -> Map.delete(hash_index, content_hash)
      _ -> hash_index  # Hash is used by other contexts
    end
  end

  defp cleanup_orphaned_references(state) do
    # Remove hash index entries that point to non-existent contexts
    valid_context_ids = Map.keys(state.content_signatures) |> MapSet.new()
    
    cleaned_hash_index = state.hash_index
    |> Enum.filter(fn {_hash, context_id} ->
      MapSet.member?(valid_context_ids, context_id)
    end)
    |> Enum.into(%{})
    
    cleaned_similarity_index = Map.take(state.similarity_index, MapSet.to_list(valid_context_ids))
    
    %{state |
      hash_index: cleaned_hash_index,
      similarity_index: cleaned_similarity_index
    }
  end

  defp optimize_similarity_index(state) do
    # In a real implementation, this would optimize the similarity index structure
    # For now, just return the state unchanged
    state
  end

  defp enhance_stats_with_calculations(stats, state) do
    unique_count = map_size(state.content_signatures)
    total_contexts = map_size(state.similarity_index)
    
    deduplication_ratio = if total_contexts > 0 do
      1.0 - (unique_count / total_contexts)
    else
      0.0
    end
    
    Map.merge(stats, %{
      current_unique_count: unique_count,
      current_total_contexts: total_contexts,
      deduplication_ratio: deduplication_ratio,
      index_sizes: %{
        hash_index: map_size(state.hash_index),
        similarity_index: map_size(state.similarity_index),
        content_signatures: map_size(state.content_signatures)
      }
    })
  end
end