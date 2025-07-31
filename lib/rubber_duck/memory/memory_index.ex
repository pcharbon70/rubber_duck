defmodule RubberDuck.Memory.MemoryIndex do
  @moduledoc """
  Data structure and utilities for memory indexing in the long-term storage system.
  
  This module provides indexing capabilities for efficient memory retrieval,
  including full-text search, metadata filtering, and vector similarity search.
  Supports multiple index types and provides index maintenance operations.
  """

  defstruct [
    :id,
    :name,
    :type,
    :field,
    :index_data,
    :config,
    :stats,
    :last_updated,
    :created_at,
    :status
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    type: index_type(),
    field: atom() | String.t(),
    index_data: map(),
    config: map(),
    stats: index_stats(),
    last_updated: DateTime.t(),
    created_at: DateTime.t(),
    status: index_status()
  }

  @type index_type :: :fulltext | :metadata | :vector | :composite
  @type index_status :: :active | :building | :rebuilding | :disabled | :error

  @type index_stats :: %{
    entry_count: integer(),
    size_bytes: integer(),
    last_query: DateTime.t() | nil,
    query_count: integer(),
    avg_query_time_ms: float(),
    hit_rate: float()
  }

  @valid_types [:fulltext, :metadata, :vector, :composite]

  @doc """
  Creates a new index with the given configuration.
  """
  def new(attrs) do
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      name: validate_name(attrs[:name]),
      type: validate_type(attrs[:type]),
      field: attrs[:field],
      index_data: %{},
      config: build_config(attrs[:type], attrs[:config] || %{}),
      stats: initial_stats(),
      last_updated: now,
      created_at: now,
      status: :building
    }
  end

  @doc """
  Adds an entry to the index.
  """
  def add_entry(index, memory_id, value) do
    case index.type do
      :fulltext -> add_fulltext_entry(index, memory_id, value)
      :metadata -> add_metadata_entry(index, memory_id, value)
      :vector -> add_vector_entry(index, memory_id, value)
      :composite -> add_composite_entry(index, memory_id, value)
    end
  end

  @doc """
  Removes an entry from the index.
  """
  def remove_entry(index, memory_id) do
    updated_data = case index.type do
      :fulltext -> remove_fulltext_entry(index.index_data, memory_id)
      :metadata -> remove_metadata_entry(index.index_data, memory_id)
      :vector -> remove_vector_entry(index.index_data, memory_id)
      :composite -> remove_composite_entry(index.index_data, memory_id)
    end
    
    %{index | 
      index_data: updated_data,
      last_updated: DateTime.utc_now()
    }
    |> update_stats(:remove)
  end

  @doc """
  Searches the index for matching entries.
  """
  def search(index, query, options \\ %{}) do
    start_time = System.monotonic_time(:millisecond)
    
    results = case index.type do
      :fulltext -> search_fulltext(index, query, options)
      :metadata -> search_metadata(index, query, options)
      :vector -> search_vector(index, query, options)
      :composite -> search_composite(index, query, options)
    end
    
    query_time = System.monotonic_time(:millisecond) - start_time
    
    # Update query stats
    updated_index = update_query_stats(index, query_time, length(results))
    
    {results, updated_index}
  end

  @doc """
  Optimizes the index for better performance.
  """
  def optimize(index) do
    optimized_data = case index.type do
      :fulltext -> optimize_fulltext(index.index_data)
      :metadata -> optimize_metadata(index.index_data)
      :vector -> optimize_vector(index.index_data)
      :composite -> optimize_composite(index.index_data)
    end
    
    %{index |
      index_data: optimized_data,
      last_updated: DateTime.utc_now(),
      status: :active
    }
  end

  @doc """
  Rebuilds the entire index from scratch.
  """
  def rebuild(index, memory_entries) do
    %{index | 
      index_data: %{},
      status: :rebuilding,
      stats: initial_stats()
    }
    |> build_from_entries(memory_entries)
  end

  @doc """
  Returns statistics about the index.
  """
  def get_stats(index) do
    Map.merge(index.stats, %{
      type: index.type,
      name: index.name,
      status: index.status,
      last_updated: index.last_updated,
      created_at: index.created_at,
      config: index.config
    })
  end

  @doc """
  Validates index health and returns any issues.
  """
  def validate_health(index) do
    issues = []
    
    issues = if index.status == :error, do: ["Index in error state" | issues], else: issues
    issues = if stale?(index), do: ["Index is stale" | issues], else: issues
    issues = if fragmented?(index), do: ["Index is fragmented" | issues], else: issues
    
    {length(issues) == 0, issues}
  end

  # Full-text index operations

  defp add_fulltext_entry(index, memory_id, text) do
    tokens = tokenize_text(text)
    posting_list = build_posting_list(memory_id, tokens)
    
    updated_data = Enum.reduce(posting_list, index.index_data, fn {token, positions}, acc ->
      Map.update(acc, token, %{memory_id => positions}, fn existing ->
        Map.put(existing, memory_id, positions)
      end)
    end)
    
    %{index | 
      index_data: updated_data,
      last_updated: DateTime.utc_now()
    }
    |> update_stats(:add)
  end

  defp remove_fulltext_entry(index_data, memory_id) do
    Map.new(index_data, fn {token, postings} ->
      {token, Map.delete(postings, memory_id)}
    end)
    |> Enum.reject(fn {_token, postings} -> map_size(postings) == 0 end)
    |> Map.new()
  end

  defp search_fulltext(index, query, options) do
    tokens = tokenize_text(query)
    
    # Find documents containing all tokens (AND search)
    results = tokens
    |> Enum.map(fn token -> 
      Map.get(index.index_data, token, %{}) |> Map.keys()
    end)
    |> intersect_lists()
    
    # Apply limit and offset
    results
    |> Enum.drop(Map.get(options, :offset, 0))
    |> Enum.take(Map.get(options, :limit, 20))
  end

  defp optimize_fulltext(index_data) do
    # Remove rare tokens and compress posting lists
    index_data
    |> Enum.filter(fn {_token, postings} -> map_size(postings) >= 2 end)
    |> Map.new()
  end

  # Metadata index operations

  defp add_metadata_entry(index, memory_id, metadata_value) do
    field_values = extract_field_values(metadata_value, index.field)
    
    updated_data = Enum.reduce(field_values, index.index_data, fn value, acc ->
      Map.update(acc, value, [memory_id], fn existing ->
        [memory_id | existing] |> Enum.uniq()
      end)
    end)
    
    %{index | 
      index_data: updated_data,
      last_updated: DateTime.utc_now()
    }
    |> update_stats(:add)
  end

  defp remove_metadata_entry(index_data, memory_id) do
    Map.new(index_data, fn {value, memory_ids} ->
      {value, Enum.reject(memory_ids, &(&1 == memory_id))}
    end)
    |> Enum.reject(fn {_value, memory_ids} -> Enum.empty?(memory_ids) end)
    |> Map.new()
  end

  defp search_metadata(index, value, _options) do
    Map.get(index.index_data, value, [])
  end

  defp optimize_metadata(index_data) do
    # Sort memory IDs for faster lookups
    Map.new(index_data, fn {value, memory_ids} ->
      {value, Enum.sort(memory_ids)}
    end)
  end

  # Vector index operations

  defp add_vector_entry(index, memory_id, vector) do
    normalized = normalize_vector(vector)
    
    updated_data = Map.put(index.index_data, memory_id, %{
      vector: normalized,
      magnitude: vector_magnitude(normalized)
    })
    
    %{index | 
      index_data: updated_data,
      last_updated: DateTime.utc_now()
    }
    |> update_stats(:add)
  end

  defp remove_vector_entry(index_data, memory_id) do
    Map.delete(index_data, memory_id)
  end

  defp search_vector(index, query_vector, options) do
    normalized_query = normalize_vector(query_vector)
    k = Map.get(options, :k, 10)
    
    # Calculate similarities
    similarities = index.index_data
    |> Enum.map(fn {memory_id, %{vector: vector}} ->
      similarity = cosine_similarity(normalized_query, vector)
      {memory_id, similarity}
    end)
    |> Enum.sort_by(fn {_id, sim} -> sim end, :desc)
    |> Enum.take(k)
    
    # Return memory IDs with scores above threshold
    threshold = Map.get(options, :threshold, 0.5)
    
    similarities
    |> Enum.filter(fn {_id, sim} -> sim >= threshold end)
    |> Enum.map(fn {id, _sim} -> id end)
  end

  defp optimize_vector(index_data) do
    # Could implement clustering or other optimizations
    index_data
  end

  # Composite index operations

  defp add_composite_entry(index, memory_id, data) do
    # Composite indexes combine multiple index types
    # Implementation depends on specific requirements
    index
  end

  defp remove_composite_entry(index_data, memory_id) do
    # Remove from all sub-indexes
    index_data
  end

  defp search_composite(index, query, options) do
    # Search across multiple index types and combine results
    []
  end

  defp optimize_composite(index_data) do
    # Optimize each sub-index
    index_data
  end

  # Helper functions

  defp generate_id do
    "idx_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp validate_name(nil), do: raise ArgumentError, "Index name is required"
  defp validate_name(name) when is_binary(name), do: name
  defp validate_name(_), do: raise ArgumentError, "Index name must be a string"

  defp validate_type(type) when type in @valid_types, do: type
  defp validate_type(type), do: raise ArgumentError, "Invalid index type: #{inspect(type)}"

  defp build_config(:fulltext, config) do
    Map.merge(%{
      analyzer: :standard,
      case_sensitive: false,
      stemming: true,
      stop_words: default_stop_words()
    }, config)
  end

  defp build_config(:metadata, config) do
    Map.merge(%{
      data_type: :string,
      case_sensitive: false
    }, config)
  end

  defp build_config(:vector, config) do
    Map.merge(%{
      dimensions: 512,
      metric: :cosine,
      normalize: true
    }, config)
  end

  defp build_config(:composite, config) do
    config
  end

  defp initial_stats do
    %{
      entry_count: 0,
      size_bytes: 0,
      last_query: nil,
      query_count: 0,
      avg_query_time_ms: 0.0,
      hit_rate: 0.0
    }
  end

  defp update_stats(index, :add) do
    update_in(index.stats.entry_count, &(&1 + 1))
  end

  defp update_stats(index, :remove) do
    update_in(index.stats.entry_count, &max(0, &1 - 1))
  end

  defp update_query_stats(index, query_time, result_count) do
    stats = index.stats
    new_query_count = stats.query_count + 1
    
    # Update moving average of query time
    new_avg_time = (stats.avg_query_time_ms * stats.query_count + query_time) / new_query_count
    
    # Update hit rate
    hit = if result_count > 0, do: 1, else: 0
    new_hit_rate = (stats.hit_rate * stats.query_count + hit) / new_query_count
    
    %{index |
      stats: %{stats |
        last_query: DateTime.utc_now(),
        query_count: new_query_count,
        avg_query_time_ms: new_avg_time,
        hit_rate: new_hit_rate
      }
    }
  end

  defp tokenize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(&1 in default_stop_words()))
    |> Enum.with_index()
  end

  defp build_posting_list(memory_id, tokens) do
    Enum.reduce(tokens, %{}, fn {token, position}, acc ->
      Map.update(acc, token, [position], &[position | &1])
    end)
  end

  defp extract_field_values(data, field) when is_atom(field) do
    case Map.get(data, field) do
      nil -> []
      value when is_list(value) -> value
      value -> [value]
    end
  end

  defp extract_field_values(data, field_path) when is_binary(field_path) do
    # Support nested field paths like "metadata.category"
    field_path
    |> String.split(".")
    |> Enum.reduce(data, fn field, acc ->
      case acc do
        %{} = map -> Map.get(map, field)
        _ -> nil
      end
    end)
    |> case do
      nil -> []
      value when is_list(value) -> value
      value -> [value]
    end
  end

  defp normalize_vector(vector) do
    magnitude = vector_magnitude(vector)
    if magnitude > 0 do
      Enum.map(vector, &(&1 / magnitude))
    else
      vector
    end
  end

  defp vector_magnitude(vector) do
    vector
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    |> :math.sqrt()
  end

  defp cosine_similarity(vec1, vec2) do
    Enum.zip(vec1, vec2)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()
  end

  defp intersect_lists([]), do: []
  defp intersect_lists([list]), do: list
  defp intersect_lists([list1, list2 | rest]) do
    intersection = MapSet.intersection(MapSet.new(list1), MapSet.new(list2))
    intersect_lists([MapSet.to_list(intersection) | rest])
  end

  defp stale?(index) do
    # Index is stale if not updated in last hour
    DateTime.diff(DateTime.utc_now(), index.last_updated, :second) > 3600
  end

  defp fragmented?(index) do
    # Simple heuristic: fragmented if average posting list is small
    case index.type do
      :fulltext ->
        avg_posting_size = if map_size(index.index_data) > 0 do
          total_postings = Enum.reduce(index.index_data, 0, fn {_k, v}, acc -> 
            acc + map_size(v)
          end)
          total_postings / map_size(index.index_data)
        else
          0
        end
        avg_posting_size < 2
      _ -> false
    end
  end

  defp build_from_entries(index, entries) do
    Enum.reduce(entries, index, fn entry, acc ->
      value = extract_value_for_index(entry, acc)
      add_entry(acc, entry.id, value)
    end)
    |> Map.put(:status, :active)
  end

  defp extract_value_for_index(entry, index) do
    case index.type do
      :fulltext -> Map.get(entry, :content, "")
      :metadata -> Map.get(entry, :metadata, %{})
      :vector -> Map.get(entry, :embedding)
      :composite -> entry
    end
  end

  defp default_stop_words do
    ~w(a an and are as at be by for from has he in is it its of on that the to was will with)
  end
end