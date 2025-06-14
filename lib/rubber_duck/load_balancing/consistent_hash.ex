defmodule RubberDuck.LoadBalancing.ConsistentHash do
  @moduledoc """
  Consistent hashing implementation for stable API key and provider distribution.
  
  This module implements consistent hashing with virtual nodes to ensure
  stable distribution of requests across providers and API keys with minimal
  redistribution when providers are added or removed.
  """

  defstruct ring: %{}, nodes: [], virtual_nodes: 150, hash_function: :sha256

  @type t :: %__MODULE__{
    ring: %{non_neg_integer() => term()},
    nodes: [term()],
    virtual_nodes: pos_integer(),
    hash_function: :md5 | :sha | :sha256 | :sha384 | :sha512
  }

  @type hash_node :: term()
  @type hash_key :: term()

  @doc """
  Create a new consistent hash ring.
  
  ## Options
  
    * `:virtual_nodes` - Number of virtual nodes per physical node (default: 150)
    * `:hash_function` - Hash function to use (default: :sha256)
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring.virtual_nodes
      150
      
      iex> ring = ConsistentHash.new(virtual_nodes: 100, hash_function: :md5)
      iex> ring.virtual_nodes
      100
  """
  def new(opts \\ []) do
    %__MODULE__{
      virtual_nodes: Keyword.get(opts, :virtual_nodes, 150),
      hash_function: Keyword.get(opts, :hash_function, :sha256)
    }
  end

  @doc """
  Add a node to the consistent hash ring.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_node(ring, "provider1")
      iex> "provider1" in ring.nodes
      true
  """
  def add_node(%__MODULE__{} = ring, node) do
    if node in ring.nodes do
      ring
    else
      new_ring = add_virtual_nodes(ring.ring, node, ring.virtual_nodes, ring.hash_function)
      
      %{ring |
        ring: new_ring,
        nodes: [node | ring.nodes]
      }
    end
  end

  @doc """
  Remove a node from the consistent hash ring.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_node(ring, "provider1")
      iex> ring = ConsistentHash.remove_node(ring, "provider1")
      iex> "provider1" in ring.nodes
      false
  """
  def remove_node(%__MODULE__{} = ring, node) do
    if node not in ring.nodes do
      ring
    else
      new_ring = remove_virtual_nodes(ring.ring, node, ring.virtual_nodes, ring.hash_function)
      
      %{ring |
        ring: new_ring,
        nodes: List.delete(ring.nodes, node)
      }
    end
  end

  @doc """
  Add multiple nodes to the consistent hash ring.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_nodes(ring, ["provider1", "provider2", "provider3"])
      iex> length(ring.nodes)
      3
  """
  def add_nodes(%__MODULE__{} = ring, nodes) when is_list(nodes) do
    Enum.reduce(nodes, ring, &add_node(&2, &1))
  end

  @doc """
  Get the node responsible for a given key.
  
  Returns the node that should handle the given key according to the
  consistent hash ring. If no nodes are available, returns nil.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_nodes(ring, ["provider1", "provider2"])
      iex> node = ConsistentHash.get_node(ring, "api_key_123")
      iex> node in ["provider1", "provider2"]
      true
  """
  def get_node(%__MODULE__{ring: ring} = _ring, _key) when map_size(ring) == 0 do
    nil
  end

  def get_node(%__MODULE__{} = ring, key) do
    hash = hash_key(key, ring.hash_function)
    find_node(ring.ring, hash)
  end

  @doc """
  Get multiple nodes responsible for a given key.
  
  Returns a list of nodes that should handle replicas of the given key.
  Useful for replication scenarios.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_nodes(ring, ["provider1", "provider2", "provider3"])
      iex> nodes = ConsistentHash.get_nodes(ring, "api_key_123", 2)
      iex> length(nodes)
      2
  """
  def get_nodes(%__MODULE__{} = ring, key, count) when count > 0 do
    case get_node(ring, key) do
      nil -> []
      primary_node ->
        hash = hash_key(key, ring.hash_function)
        get_replica_nodes(ring, hash, primary_node, count - 1, [primary_node])
    end
  end

  @doc """
  Get statistics about the hash ring distribution.
  
  Returns information about how evenly distributed the virtual nodes are
  and other ring statistics.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_nodes(ring, ["provider1", "provider2"])
      iex> stats = ConsistentHash.get_stats(ring)
      iex> Map.has_key?(stats, :node_count)
      true
  """
  def get_stats(%__MODULE__{} = ring) do
    ring_size = map_size(ring.ring)
    node_count = length(ring.nodes)
    
    distribution = if node_count > 0 do
      calculate_distribution(ring)
    else
      %{}
    end
    
    %{
      node_count: node_count,
      virtual_node_count: ring_size,
      virtual_nodes_per_node: ring.virtual_nodes,
      distribution: distribution,
      load_factor: calculate_load_factor(distribution)
    }
  end

  @doc """
  Check if the ring contains a specific node.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ConsistentHash.has_node?(ring, "provider1")
      false
      iex> ring = ConsistentHash.add_node(ring, "provider1")
      iex> ConsistentHash.has_node?(ring, "provider1")
      true
  """
  def has_node?(%__MODULE__{} = ring, node) do
    node in ring.nodes
  end

  @doc """
  Get all nodes in the ring.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_nodes(ring, ["provider1", "provider2"])
      iex> nodes = ConsistentHash.get_all_nodes(ring)
      iex> length(nodes)
      2
  """
  def get_all_nodes(%__MODULE__{} = ring) do
    ring.nodes
  end

  @doc """
  Clear all nodes from the ring.
  
  ## Examples
  
      iex> ring = ConsistentHash.new()
      iex> ring = ConsistentHash.add_node(ring, "provider1")
      iex> ring = ConsistentHash.clear(ring)
      iex> length(ring.nodes)
      0
  """
  def clear(%__MODULE__{} = ring) do
    %{ring | ring: %{}, nodes: []}
  end

  # Private Functions

  defp add_virtual_nodes(ring, node, virtual_nodes, hash_function) do
    0..(virtual_nodes - 1)
    |> Enum.reduce(ring, fn i, acc ->
      virtual_key = "#{node}:#{i}"
      hash = hash_key(virtual_key, hash_function)
      Map.put(acc, hash, node)
    end)
  end

  defp remove_virtual_nodes(ring, node, virtual_nodes, hash_function) do
    0..(virtual_nodes - 1)
    |> Enum.reduce(ring, fn i, acc ->
      virtual_key = "#{node}:#{i}"
      hash = hash_key(virtual_key, hash_function)
      Map.delete(acc, hash)
    end)
  end

  defp hash_key(key, hash_function) do
    key
    |> to_string()
    |> then(&:crypto.hash(hash_function, &1))
    |> :binary.decode_unsigned()
  end

  defp find_node(ring, hash) do
    # Find the first node clockwise from the hash
    ring
    |> Map.keys()
    |> Enum.sort()
    |> find_clockwise_node(ring, hash)
  end

  defp find_clockwise_node([], _ring, _hash), do: nil
  
  defp find_clockwise_node(sorted_hashes, ring, hash) do
    case Enum.find(sorted_hashes, &(&1 >= hash)) do
      nil ->
        # Wrap around to the first node
        first_hash = hd(sorted_hashes)
        Map.get(ring, first_hash)
      
      found_hash ->
        Map.get(ring, found_hash)
    end
  end

  defp get_replica_nodes(_ring, _hash, _primary, 0, acc), do: Enum.reverse(acc)
  defp get_replica_nodes(%__MODULE__{ring: ring} = ring_struct, hash, primary, count, acc) do
    sorted_hashes = ring |> Map.keys() |> Enum.sort()
    
    case find_next_different_node(sorted_hashes, ring, hash, primary, acc) do
      nil -> Enum.reverse(acc)
      {next_node, next_hash} ->
        get_replica_nodes(ring_struct, next_hash, primary, count - 1, [next_node | acc])
    end
  end

  defp find_next_different_node(sorted_hashes, ring, start_hash, exclude_node, exclude_list) do
    # Find next node that's different from the ones we already have
    case Enum.drop_while(sorted_hashes, &(&1 <= start_hash)) do
      [] ->
        # Wrap around
        find_different_node_from_start(sorted_hashes, ring, exclude_node, exclude_list)
      
      remaining ->
        find_different_node_from_list(remaining, ring, exclude_node, exclude_list) ||
          find_different_node_from_start(sorted_hashes, ring, exclude_node, exclude_list)
    end
  end

  defp find_different_node_from_start(sorted_hashes, ring, exclude_node, exclude_list) do
    find_different_node_from_list(sorted_hashes, ring, exclude_node, exclude_list)
  end

  defp find_different_node_from_list(hashes, ring, exclude_node, exclude_list) do
    Enum.reduce_while(hashes, nil, fn hash, _acc ->
      node = Map.get(ring, hash)
      
      if node != exclude_node and node not in exclude_list do
        {:halt, {node, hash}}
      else
        {:cont, nil}
      end
    end)
  end

  defp calculate_distribution(%__MODULE__{} = ring) do
    ring.nodes
    |> Enum.map(fn node ->
      virtual_node_count = count_virtual_nodes(ring.ring, node)
      {node, virtual_node_count}
    end)
    |> Map.new()
  end

  defp count_virtual_nodes(ring_map, node) do
    ring_map
    |> Map.values()
    |> Enum.count(&(&1 == node))
  end

  defp calculate_load_factor(distribution) when map_size(distribution) == 0, do: 0.0
  defp calculate_load_factor(distribution) do
    values = Map.values(distribution)
    mean = Enum.sum(values) / length(values)
    
    variance = values
    |> Enum.map(&((&1 - mean) * (&1 - mean)))
    |> Enum.sum()
    |> Kernel./(length(values))
    
    :math.sqrt(variance) / mean
  end
end