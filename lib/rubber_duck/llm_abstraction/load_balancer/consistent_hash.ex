defmodule RubberDuck.LLMAbstraction.LoadBalancer.ConsistentHash do
  @moduledoc """
  Consistent hashing implementation for API key distribution.
  
  This module provides consistent hashing for distributing requests across
  multiple API keys for each provider, ensuring even distribution while
  maintaining session affinity when needed.
  
  Features:
  - Virtual nodes for better distribution
  - Dynamic addition/removal of keys
  - Session affinity support
  - Configurable hash function
  """

  defstruct [
    :ring,
    :virtual_nodes,
    :hash_function,
    :keys
  ]

  @type t :: %__MODULE__{
    ring: :gb_trees.tree(),
    virtual_nodes: non_neg_integer(),
    hash_function: atom(),
    keys: MapSet.t()
  }

  @default_virtual_nodes 150
  @default_hash_function :sha256

  @doc """
  Create a new consistent hash ring.
  
  ## Options
    - virtual_nodes: Number of virtual nodes per physical key (default: 150)
    - hash_function: Hash function to use (:md5, :sha, :sha256, etc.)
  """
  def new(opts \\ []) do
    %__MODULE__{
      ring: :gb_trees.empty(),
      virtual_nodes: Keyword.get(opts, :virtual_nodes, @default_virtual_nodes),
      hash_function: Keyword.get(opts, :hash_function, @default_hash_function),
      keys: MapSet.new()
    }
  end

  @doc """
  Add a key to the hash ring.
  """
  def add_key(%__MODULE__{} = hash_ring, key) do
    if MapSet.member?(hash_ring.keys, key) do
      hash_ring  # Key already exists
    else
      new_ring = add_virtual_nodes(hash_ring.ring, key, hash_ring.virtual_nodes, hash_ring.hash_function)
      new_keys = MapSet.put(hash_ring.keys, key)
      
      %{hash_ring | ring: new_ring, keys: new_keys}
    end
  end

  @doc """
  Remove a key from the hash ring.
  """
  def remove_key(%__MODULE__{} = hash_ring, key) do
    if MapSet.member?(hash_ring.keys, key) do
      new_ring = remove_virtual_nodes(hash_ring.ring, key, hash_ring.virtual_nodes, hash_ring.hash_function)
      new_keys = MapSet.delete(hash_ring.keys, key)
      
      %{hash_ring | ring: new_ring, keys: new_keys}
    else
      hash_ring  # Key doesn't exist
    end
  end

  @doc """
  Get the key responsible for the given input.
  
  Returns the key that should handle the request for the given input.
  Uses consistent hashing to ensure the same input always maps to the
  same key (unless the ring topology changes).
  """
  def get_key(%__MODULE__{} = hash_ring, input) do
    if :gb_trees.is_empty(hash_ring.ring) do
      nil
    else
      input_hash = hash_input(input, hash_ring.hash_function)
      find_key_for_hash(hash_ring.ring, input_hash)
    end
  end

  @doc """
  Get multiple keys for the given input (for replication).
  
  Returns a list of keys that should handle replicas of the request.
  Useful for implementing replication or backup strategies.
  """
  def get_keys(%__MODULE__{} = hash_ring, input, count) when count > 0 do
    if :gb_trees.is_empty(hash_ring.ring) do
      []
    else
      input_hash = hash_input(input, hash_ring.hash_function)
      find_keys_for_hash(hash_ring.ring, input_hash, count, [])
    end
  end

  @doc """
  List all keys in the hash ring.
  """
  def list_keys(%__MODULE__{} = hash_ring) do
    MapSet.to_list(hash_ring.keys)
  end

  @doc """
  Get statistics about the hash ring.
  """
  def stats(%__MODULE__{} = hash_ring) do
    key_count = MapSet.size(hash_ring.keys)
    virtual_node_count = if key_count > 0, do: key_count * hash_ring.virtual_nodes, else: 0
    
    %{
      key_count: key_count,
      virtual_nodes_per_key: hash_ring.virtual_nodes,
      total_virtual_nodes: virtual_node_count,
      hash_function: hash_ring.hash_function,
      ring_size: :gb_trees.size(hash_ring.ring)
    }
  end

  @doc """
  Calculate the distribution of hash space for each key.
  
  Returns a map showing what percentage of the hash space each key is responsible for.
  Useful for analyzing the evenness of distribution.
  """
  def distribution(%__MODULE__{} = hash_ring) do
    if :gb_trees.is_empty(hash_ring.ring) do
      %{}
    else
      calculate_distribution(hash_ring)
    end
  end

  # Private Functions

  defp add_virtual_nodes(ring, key, virtual_nodes, hash_function) do
    0..(virtual_nodes - 1)
    |> Enum.reduce(ring, fn i, acc_ring ->
      virtual_key = "#{key}:#{i}"
      virtual_hash = hash_input(virtual_key, hash_function)
      :gb_trees.insert(virtual_hash, key, acc_ring)
    end)
  end

  defp remove_virtual_nodes(ring, key, virtual_nodes, hash_function) do
    0..(virtual_nodes - 1)
    |> Enum.reduce(ring, fn i, acc_ring ->
      virtual_key = "#{key}:#{i}"
      virtual_hash = hash_input(virtual_key, hash_function)
      :gb_trees.delete(virtual_hash, acc_ring)
    end)
  end

  defp hash_input(input, hash_function) do
    input_binary = to_string(input)
    
    hash_binary = case hash_function do
      :md5 -> :crypto.hash(:md5, input_binary)
      :sha -> :crypto.hash(:sha, input_binary)
      :sha256 -> :crypto.hash(:sha256, input_binary)
      :sha512 -> :crypto.hash(:sha512, input_binary)
      _ -> :crypto.hash(:sha256, input_binary)  # Default fallback
    end
    
    # Convert binary hash to integer for consistent ordering
    :binary.decode_unsigned(hash_binary, :big)
  end

  defp find_key_for_hash(ring, input_hash) do
    case find_next_key(ring, input_hash) do
      nil ->
        # Wrap around to the smallest key
        case :gb_trees.smallest(ring) do
          {_hash, key} -> key
          _ -> nil
        end
      
      key ->
        key
    end
  end

  defp find_next_key(ring, input_hash) do
    iterator = :gb_trees.iterator_from(input_hash, ring)
    
    case :gb_trees.next(iterator) do
      {_hash, key, _new_iterator} -> key
      :none -> nil
    end
  end

  defp find_keys_for_hash(ring, input_hash, count, acc) when length(acc) >= count do
    acc |> Enum.reverse() |> Enum.take(count) |> Enum.uniq()
  end

  defp find_keys_for_hash(ring, input_hash, count, acc) do
    case find_next_unique_key(ring, input_hash, acc) do
      nil ->
        # Wrap around and continue from beginning
        case :gb_trees.smallest(ring) do
          {smallest_hash, _key} when smallest_hash != input_hash ->
            find_keys_for_hash(ring, smallest_hash, count, acc)
          _ ->
            acc |> Enum.reverse() |> Enum.uniq()
        end
      
      {next_hash, key} ->
        if key in acc do
          # Skip duplicate and continue
          find_keys_for_hash(ring, next_hash + 1, count, acc)
        else
          find_keys_for_hash(ring, next_hash + 1, count, [key | acc])
        end
    end
  end

  defp find_next_unique_key(ring, start_hash, existing_keys) do
    iterator = :gb_trees.iterator_from(start_hash, ring)
    find_next_unique_key_iter(iterator, existing_keys)
  end

  defp find_next_unique_key_iter(iterator, existing_keys) do
    case :gb_trees.next(iterator) do
      {hash, key, new_iterator} ->
        if key in existing_keys do
          find_next_unique_key_iter(new_iterator, existing_keys)
        else
          {hash, key}
        end
      
      :none ->
        nil
    end
  end

  defp calculate_distribution(hash_ring) do
    ring_points = :gb_trees.to_list(hash_ring.ring)
    total_space = :math.pow(2, 256)  # Assuming 256-bit hash space
    
    ring_points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(%{}, fn [{start_hash, key}, {end_hash, _}], acc ->
      space = end_hash - start_hash
      percentage = (space / total_space) * 100
      
      Map.update(acc, key, percentage, &(&1 + percentage))
    end)
    |> handle_wrap_around(ring_points, total_space)
  end

  defp handle_wrap_around(distribution, ring_points, total_space) do
    case {List.first(ring_points), List.last(ring_points)} do
      {{first_hash, first_key}, {last_hash, last_key}} when first_key != last_key ->
        # Handle wrap-around from last to first
        wrap_space = (total_space - last_hash) + first_hash
        wrap_percentage = (wrap_space / total_space) * 100
        
        Map.update(distribution, last_key, wrap_percentage, &(&1 + wrap_percentage))
      
      _ ->
        distribution
    end
  end
end