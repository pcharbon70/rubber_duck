defmodule RubberDuck.LoadBalancing.ConsistentHashTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LoadBalancing.ConsistentHash
  
  describe "new/1" do
    test "creates a new consistent hash ring with default settings" do
      ring = ConsistentHash.new()
      
      assert ring.virtual_nodes == 150
      assert ring.hash_function == :sha256
      assert ring.ring == %{}
      assert ring.nodes == []
    end
    
    test "creates a new ring with custom settings" do
      ring = ConsistentHash.new(virtual_nodes: 100, hash_function: :md5)
      
      assert ring.virtual_nodes == 100
      assert ring.hash_function == :md5
    end
  end
  
  describe "add_node/2" do
    test "adds a single node to the ring" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      
      assert "provider1" in ring.nodes
      assert map_size(ring.ring) == 150  # virtual_nodes
    end
    
    test "does not add duplicate nodes" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      |> ConsistentHash.add_node("provider1")
      
      assert length(ring.nodes) == 1
      assert map_size(ring.ring) == 150
    end
    
    test "adds multiple different nodes" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      |> ConsistentHash.add_node("provider2")
      
      assert length(ring.nodes) == 2
      assert map_size(ring.ring) == 300  # 2 * virtual_nodes
    end
  end
  
  describe "add_nodes/2" do
    test "adds multiple nodes at once" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      assert length(ring.nodes) == 3
      assert map_size(ring.ring) == 450  # 3 * virtual_nodes
    end
  end
  
  describe "remove_node/2" do
    test "removes an existing node" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      |> ConsistentHash.remove_node("provider1")
      
      assert ring.nodes == []
      assert ring.ring == %{}
    end
    
    test "does nothing when removing non-existent node" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      
      unchanged_ring = ConsistentHash.remove_node(ring, "provider2")
      
      assert unchanged_ring == ring
    end
  end
  
  describe "get_node/2" do
    test "returns nil for empty ring" do
      ring = ConsistentHash.new()
      
      assert ConsistentHash.get_node(ring, "any_key") == nil
    end
    
    test "returns a node for a given key" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      node = ConsistentHash.get_node(ring, "api_key_123")
      
      assert node in ["provider1", "provider2", "provider3"]
    end
    
    test "returns consistent results for the same key" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      node1 = ConsistentHash.get_node(ring, "api_key_123")
      node2 = ConsistentHash.get_node(ring, "api_key_123")
      
      assert node1 == node2
    end
    
    test "distributes keys across multiple nodes" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      keys = for i <- 1..100, do: "key_#{i}"
      
      distributions = keys
      |> Enum.map(&ConsistentHash.get_node(ring, &1))
      |> Enum.frequencies()
      
      # Should distribute across all providers
      assert map_size(distributions) == 3
      
      # Each provider should get a reasonable share (not perfectly equal due to hashing)
      Enum.each(distributions, fn {_provider, count} ->
        assert count > 10  # At least 10% of keys
        assert count < 70  # No more than 70% of keys
      end)
    end
  end
  
  describe "get_nodes/3" do
    test "returns multiple nodes for replication" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      nodes = ConsistentHash.get_nodes(ring, "api_key_123", 2)
      
      assert length(nodes) == 2
      assert Enum.uniq(nodes) == nodes  # No duplicates
    end
    
    test "returns empty list for empty ring" do
      ring = ConsistentHash.new()
      
      nodes = ConsistentHash.get_nodes(ring, "api_key_123", 2)
      
      assert nodes == []
    end
    
    test "returns available nodes when count exceeds node count" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      
      nodes = ConsistentHash.get_nodes(ring, "api_key_123", 5)
      
      assert length(nodes) == 1
    end
  end
  
  describe "get_stats/1" do
    test "returns statistics for empty ring" do
      ring = ConsistentHash.new()
      
      stats = ConsistentHash.get_stats(ring)
      
      assert stats.node_count == 0
      assert stats.virtual_node_count == 0
      assert stats.distribution == %{}
      assert stats.load_factor == 0.0
    end
    
    test "returns statistics for populated ring" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2"])
      
      stats = ConsistentHash.get_stats(ring)
      
      assert stats.node_count == 2
      assert stats.virtual_node_count == 300
      assert stats.virtual_nodes_per_node == 150
      assert is_map(stats.distribution)
      assert is_float(stats.load_factor)
    end
  end
  
  describe "has_node?/2" do
    test "returns true for existing node" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_node("provider1")
      
      assert ConsistentHash.has_node?(ring, "provider1")
    end
    
    test "returns false for non-existing node" do
      ring = ConsistentHash.new()
      
      refute ConsistentHash.has_node?(ring, "provider1")
    end
  end
  
  describe "get_all_nodes/1" do
    test "returns all nodes in the ring" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2", "provider3"])
      
      nodes = ConsistentHash.get_all_nodes(ring)
      
      assert length(nodes) == 3
      assert "provider1" in nodes
      assert "provider2" in nodes
      assert "provider3" in nodes
    end
  end
  
  describe "clear/1" do
    test "removes all nodes from the ring" do
      ring = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2"])
      |> ConsistentHash.clear()
      
      assert ring.nodes == []
      assert ring.ring == %{}
    end
  end
  
  describe "stability" do
    test "minimal redistribution when adding nodes" do
      # Create ring with initial nodes
      ring1 = ConsistentHash.new()
      |> ConsistentHash.add_nodes(["provider1", "provider2"])
      
      # Map 100 keys to nodes
      keys = for i <- 1..100, do: "key_#{i}"
      initial_mapping = Map.new(keys, fn key ->
        {key, ConsistentHash.get_node(ring1, key)}
      end)
      
      # Add a new node
      ring2 = ConsistentHash.add_node(ring1, "provider3")
      
      # Check how many keys remapped
      final_mapping = Map.new(keys, fn key ->
        {key, ConsistentHash.get_node(ring2, key)}
      end)
      
      unchanged_keys = Enum.count(keys, fn key ->
        initial_mapping[key] == final_mapping[key]
      end)
      
      # Should have minimal redistribution (at least 60% unchanged)
      unchanged_percentage = unchanged_keys / length(keys)
      assert unchanged_percentage >= 0.6
    end
  end
end