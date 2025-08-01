defmodule RubberDuck.Memory.AccessPatternTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Memory.AccessPattern
  alias RubberDuck.Agents.ShortTermMemoryAgent

  setup do
    {:ok, agent} = ShortTermMemoryAgent.init(%{})
    
    # Create test memories with different access patterns
    memories = create_test_memories(agent)
    
    {:ok, agent: agent, memories: memories}
  end

  describe "access pattern detection" do
    test "detects sequential access pattern" do
      accesses = [
        {"mem_1", ~U[2024-01-01 10:00:00Z]},
        {"mem_2", ~U[2024-01-01 10:00:01Z]},
        {"mem_3", ~U[2024-01-01 10:00:02Z]},
        {"mem_4", ~U[2024-01-01 10:00:03Z]}
      ]
      
      pattern = AccessPattern.analyze_pattern(accesses)
      
      assert pattern.type == :sequential
      assert pattern.confidence >= 0.9
      assert pattern.metrics.avg_interval_ms <= 1000
    end

    test "detects random access pattern" do
      accesses = [
        {"mem_7", ~U[2024-01-01 10:00:00Z]},
        {"mem_2", ~U[2024-01-01 10:00:01Z]},
        {"mem_9", ~U[2024-01-01 10:00:02Z]},
        {"mem_1", ~U[2024-01-01 10:00:03Z]},
        {"mem_5", ~U[2024-01-01 10:00:04Z]}
      ]
      
      pattern = AccessPattern.analyze_pattern(accesses)
      
      assert pattern.type == :random
      assert pattern.confidence >= 0.7
    end

    test "detects burst access pattern" do
      accesses = [
        {"mem_1", ~U[2024-01-01 10:00:00.000Z]},
        {"mem_2", ~U[2024-01-01 10:00:00.100Z]},
        {"mem_3", ~U[2024-01-01 10:00:00.200Z]},
        # Long gap
        {"mem_4", ~U[2024-01-01 10:05:00.000Z]},
        {"mem_5", ~U[2024-01-01 10:05:00.100Z]},
        {"mem_6", ~U[2024-01-01 10:05:00.200Z]}
      ]
      
      pattern = AccessPattern.analyze_pattern(accesses)
      
      assert pattern.type == :burst
      assert pattern.metrics.burst_count >= 2
      assert pattern.metrics.avg_burst_size >= 3
    end

    test "detects periodic access pattern" do
      # Access every 5 seconds
      accesses = Enum.map(0..9, fn i ->
        {"mem_#{i}", DateTime.add(~U[2024-01-01 10:00:00Z], i * 5, :second)}
      end)
      
      pattern = AccessPattern.analyze_pattern(accesses)
      
      assert pattern.type == :periodic
      assert pattern.metrics.period_ms == 5000
      assert pattern.confidence >= 0.8
    end

    test "handles mixed patterns with lower confidence" do
      accesses = [
        {"mem_1", ~U[2024-01-01 10:00:00Z]},
        {"mem_2", ~U[2024-01-01 10:00:01Z]},  # Sequential
        {"mem_7", ~U[2024-01-01 10:00:02Z]},  # Random jump
        {"mem_3", ~U[2024-01-01 10:00:07Z]},  # Time gap
        {"mem_4", ~U[2024-01-01 10:00:08Z]}   # Back to sequential
      ]
      
      pattern = AccessPattern.analyze_pattern(accesses)
      
      assert pattern.type in [:mixed, :random]
      assert pattern.confidence < 0.7
    end
  end

  describe "access frequency analysis" do
    test "calculates access frequency correctly", %{agent: agent} do
      memory_id = "freq_test_1"
      
      # Record multiple accesses
      Enum.each(1..10, fn i ->
        {:ok, agent} = ShortTermMemoryAgent.record_access(agent, memory_id, %{
          timestamp: DateTime.add(DateTime.utc_now(), -i * 60, :second)
        })
      end)
      
      frequency = AccessPattern.calculate_frequency(agent.access_logs[memory_id])
      
      assert frequency.accesses_per_minute > 0
      assert frequency.accesses_per_hour == 10
      assert frequency.peak_access_time != nil
    end

    test "identifies hot and cold memories", %{agent: agent} do
      # Create hot memory (many recent accesses)
      hot_memory = "hot_mem_1"
      Enum.each(1..20, fn i ->
        ShortTermMemoryAgent.record_access(agent, hot_memory, %{
          timestamp: DateTime.add(DateTime.utc_now(), -i, :second)
        })
      end)
      
      # Create cold memory (few old accesses)
      cold_memory = "cold_mem_1"
      Enum.each(1..2, fn i ->
        ShortTermMemoryAgent.record_access(agent, cold_memory, %{
          timestamp: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
        })
      end)
      
      hot_freq = AccessPattern.calculate_frequency(agent.access_logs[hot_memory])
      cold_freq = AccessPattern.calculate_frequency(agent.access_logs[cold_memory])
      
      assert AccessPattern.is_hot?(hot_freq) == true
      assert AccessPattern.is_cold?(cold_freq) == true
    end

    test "tracks access recency properly" do
      now = DateTime.utc_now()
      
      accesses = [
        %{timestamp: DateTime.add(now, -1, :second)},      # 1 second ago
        %{timestamp: DateTime.add(now, -60, :second)},     # 1 minute ago
        %{timestamp: DateTime.add(now, -3600, :second)},   # 1 hour ago
        %{timestamp: DateTime.add(now, -86400, :second)}   # 1 day ago
      ]
      
      recency = AccessPattern.calculate_recency(accesses)
      
      assert recency.last_access_seconds_ago <= 2
      assert recency.avg_recency_minutes > 0
      assert recency.recency_score >= 0 and recency.recency_score <= 1
    end
  end

  describe "pattern-based optimization" do
    test "suggests prefetching for sequential patterns" do
      sequential_pattern = %AccessPattern{
        type: :sequential,
        confidence: 0.95,
        metrics: %{predicted_next: ["mem_5", "mem_6"]}
      }
      
      suggestions = AccessPattern.optimization_suggestions(sequential_pattern)
      
      assert :prefetch in suggestions.actions
      assert "mem_5" in suggestions.prefetch_candidates
      assert suggestions.cache_strategy == :sequential_cache
    end

    test "suggests caching for burst patterns" do
      burst_pattern = %AccessPattern{
        type: :burst,
        confidence: 0.85,
        metrics: %{
          avg_burst_size: 10,
          burst_memories: ["mem_1", "mem_2", "mem_3"]
        }
      }
      
      suggestions = AccessPattern.optimization_suggestions(burst_pattern)
      
      assert :cache_burst_group in suggestions.actions
      assert suggestions.cache_strategy == :group_cache
      assert length(suggestions.cache_group) > 0
    end

    test "suggests eviction for random patterns with cold memories" do
      random_pattern = %AccessPattern{
        type: :random,
        confidence: 0.8,
        metrics: %{
          cold_memories: ["mem_old_1", "mem_old_2"],
          cache_pressure: 0.9
        }
      }
      
      suggestions = AccessPattern.optimization_suggestions(random_pattern)
      
      assert :evict_cold in suggestions.actions
      assert "mem_old_1" in suggestions.eviction_candidates
      assert suggestions.cache_strategy == :lru
    end
  end

  describe "access anomaly detection" do
    test "detects unusual access spike" do
      normal_accesses = Enum.map(1..20, fn i ->
        {"mem_#{i}", DateTime.add(~U[2024-01-01 10:00:00Z], i * 60, :second)}
      end)
      
      # Add spike
      spike_accesses = Enum.map(1..10, fn i ->
        {"mem_spike", DateTime.add(~U[2024-01-01 11:00:00Z], i, :second)}
      end)
      
      all_accesses = normal_accesses ++ spike_accesses
      
      anomalies = AccessPattern.detect_anomalies(all_accesses)
      
      assert length(anomalies) > 0
      assert Enum.any?(anomalies, &(&1.type == :access_spike))
    end

    test "detects unusual access gap" do
      accesses = [
        {"mem_1", ~U[2024-01-01 10:00:00Z]},
        {"mem_2", ~U[2024-01-01 10:01:00Z]},
        {"mem_3", ~U[2024-01-01 10:02:00Z]},
        # Large gap
        {"mem_4", ~U[2024-01-01 15:00:00Z]},
        {"mem_5", ~U[2024-01-01 15:01:00Z]}
      ]
      
      anomalies = AccessPattern.detect_anomalies(accesses)
      
      assert Enum.any?(anomalies, &(&1.type == :access_gap))
      assert Enum.any?(anomalies, &(&1.duration_minutes >= 180))
    end

    test "detects pattern changes" do
      # Sequential pattern that changes to random
      accesses = [
        {"mem_1", ~U[2024-01-01 10:00:00Z]},
        {"mem_2", ~U[2024-01-01 10:00:01Z]},
        {"mem_3", ~U[2024-01-01 10:00:02Z]},
        {"mem_4", ~U[2024-01-01 10:00:03Z]},
        # Pattern change
        {"mem_9", ~U[2024-01-01 10:00:04Z]},
        {"mem_2", ~U[2024-01-01 10:00:05Z]},
        {"mem_7", ~U[2024-01-01 10:00:06Z]}
      ]
      
      changes = AccessPattern.detect_pattern_changes(accesses)
      
      assert length(changes) > 0
      assert Enum.any?(changes, &(&1.from_pattern == :sequential))
      assert Enum.any?(changes, &(&1.to_pattern == :random))
    end
  end

  describe "access prediction" do
    test "predicts next access for sequential pattern" do
      recent_accesses = [
        {"mem_1", DateTime.utc_now()},
        {"mem_2", DateTime.add(DateTime.utc_now(), -1, :second)},
        {"mem_3", DateTime.add(DateTime.utc_now(), -2, :second)},
        {"mem_4", DateTime.add(DateTime.utc_now(), -3, :second)}
      ]
      
      prediction = AccessPattern.predict_next_access(recent_accesses)
      
      assert prediction.next_memory_id == "mem_5"
      assert prediction.confidence >= 0.8
      assert prediction.expected_time_ms <= 1000
    end

    test "predicts access timing for periodic pattern" do
      # Every 5 seconds pattern
      periodic_accesses = Enum.map(0..4, fn i ->
        {"mem_x", DateTime.add(DateTime.utc_now(), -i * 5, :second)}
      end)
      
      prediction = AccessPattern.predict_next_access(periodic_accesses)
      
      assert prediction.expected_time_ms >= 4000 and prediction.expected_time_ms <= 6000
      assert prediction.pattern_type == :periodic
    end

    test "provides low confidence for random patterns" do
      random_accesses = [
        {"mem_7", DateTime.utc_now()},
        {"mem_2", DateTime.add(DateTime.utc_now(), -1, :second)},
        {"mem_9", DateTime.add(DateTime.utc_now(), -2, :second)},
        {"mem_1", DateTime.add(DateTime.utc_now(), -3, :second)}
      ]
      
      prediction = AccessPattern.predict_next_access(random_accesses)
      
      assert prediction.confidence < 0.3
      assert prediction.pattern_type == :random
    end
  end

  # Helper functions

  defp create_test_memories(agent) do
    memories = Enum.map(1..10, fn i ->
      memory_data = %{
        id: "mem_#{i}",
        content: "Test memory #{i}",
        type: :test,
        created_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
      }
      
      {:ok, agent} = ShortTermMemoryAgent.store_memory(agent, memory_data)
      {memory_data.id, memory_data}
    end)
    
    Map.new(memories)
  end
end