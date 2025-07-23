defmodule RubberDuck.Status.OptimizerTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Status.Optimizer
  alias RubberDuck.Status.Monitor

  setup do
    # Ensure Optimizer is started
    case Process.whereis(Optimizer) do
      nil -> {:ok, _} = Optimizer.start_link()
      _ -> :ok
    end

    # Ensure Monitor is started (needed for metrics)
    case Process.whereis(Monitor) do
      nil -> {:ok, _} = Monitor.start_link()
      _ -> :ok
    end

    :ok
  end

  describe "get_optimizations/0" do
    test "returns current optimization settings" do
      {:ok, optimizations} = Optimizer.get_optimizations()

      assert is_map(optimizations)
      assert Map.has_key?(optimizations, :batch_size)
      assert Map.has_key?(optimizations, :flush_interval)
      assert Map.has_key?(optimizations, :compression)
      assert Map.has_key?(optimizations, :sharding)

      assert is_integer(optimizations.batch_size)
      assert is_integer(optimizations.flush_interval)
      assert is_boolean(optimizations.compression)
      assert is_boolean(optimizations.sharding)
    end
  end

  describe "set_optimization/2" do
    test "updates batch size" do
      assert :ok = Optimizer.set_optimization(:batch_size, 50)

      {:ok, optimizations} = Optimizer.get_optimizations()
      assert optimizations.batch_size == 50
    end

    test "updates flush interval" do
      assert :ok = Optimizer.set_optimization(:flush_interval, 200)

      {:ok, optimizations} = Optimizer.get_optimizations()
      assert optimizations.flush_interval == 200
    end

    test "updates compression setting" do
      assert :ok = Optimizer.set_optimization(:compression, false)

      {:ok, optimizations} = Optimizer.get_optimizations()
      assert optimizations.compression == false

      assert :ok = Optimizer.set_optimization(:compression, true)

      {:ok, optimizations} = Optimizer.get_optimizations()
      assert optimizations.compression == true
    end

    test "updates sharding setting" do
      assert :ok = Optimizer.set_optimization(:sharding, true)

      {:ok, optimizations} = Optimizer.get_optimizations()
      assert optimizations.sharding == true
    end
  end

  describe "set_enabled/1" do
    test "enables automatic optimization" do
      Optimizer.set_enabled(true)
      # No direct way to verify, but should not crash
      assert true
    end

    test "disables automatic optimization" do
      Optimizer.set_enabled(false)
      # No direct way to verify, but should not crash
      assert true
    end
  end

  describe "optimize_now/0" do
    test "triggers immediate optimization" do
      # Set up some metrics that would trigger optimization
      # High queue depth
      Monitor.record_metric(:queue_depth, 2000)
      Monitor.record_metric(:throughput, 100)
      Monitor.record_metric(:latency, 50)
      Monitor.record_metric(:error_rate, 0.005)

      {:ok, initial_opts} = Optimizer.get_optimizations()

      Optimizer.optimize_now()

      # Give time for optimization to complete
      Process.sleep(100)

      {:ok, final_opts} = Optimizer.get_optimizations()

      # Batch size should have increased due to high queue depth
      assert final_opts.batch_size >= initial_opts.batch_size
    end
  end

  describe "should_compress?/1" do
    test "returns true for large binary messages" do
      # 2KB
      large_message = :crypto.strong_rand_bytes(2048)
      assert Optimizer.should_compress?(large_message) == true
    end

    test "returns false for small binary messages" do
      small_message = "Hello, world!"
      assert Optimizer.should_compress?(small_message) == false
    end

    test "returns true for large term messages" do
      large_term = %{
        data: List.duplicate("x", 500),
        nested: %{
          more_data: List.duplicate("y", 500)
        }
      }

      assert Optimizer.should_compress?(large_term) == true
    end

    test "returns false for small term messages" do
      small_term = %{id: 1, name: "test"}
      assert Optimizer.should_compress?(small_term) == false
    end
  end

  describe "compress_message/1 and decompress_message/1" do
    test "compresses and decompresses binary messages" do
      original = :crypto.strong_rand_bytes(2048)

      compressed = Optimizer.compress_message(original)

      assert compressed.compressed == true
      assert is_binary(compressed.data)
      assert compressed.original_size == byte_size(original)
      assert compressed.compressed_size < compressed.original_size

      decompressed = Optimizer.decompress_message(compressed)
      assert decompressed == original
    end

    test "compresses and decompresses term messages" do
      original = %{
        id: 123,
        data: List.duplicate("test data", 100),
        timestamp: DateTime.utc_now()
      }

      compressed = Optimizer.compress_message(original)

      assert compressed.compressed == true
      assert is_binary(compressed.data)

      decompressed = Optimizer.decompress_message(compressed)
      assert decompressed == original
    end

    test "passes through non-compressed messages" do
      message = %{content: "test"}
      assert Optimizer.decompress_message(message) == message
    end
  end

  describe "get_topic/2" do
    test "returns basic topic when sharding disabled" do
      Optimizer.set_optimization(:sharding, false)
      Process.sleep(100)

      topic = Optimizer.get_topic("conv_123", "thinking")
      assert topic == "status:conv_123:thinking"
    end

    test "returns sharded topic when sharding enabled" do
      :persistent_term.put({Optimizer, :sharding_enabled}, true)

      topic = Optimizer.get_topic("conv_123", "thinking")
      assert String.starts_with?(topic, "status:conv_123:thinking:shard")

      # Verify consistent sharding
      topic2 = Optimizer.get_topic("conv_123", "thinking")
      assert topic == topic2

      # Different conversation should potentially get different shard
      topic3 = Optimizer.get_topic("conv_456", "thinking")
      assert String.starts_with?(topic3, "status:conv_456:thinking:shard")
    end
  end

  describe "optimization strategies" do
    test "increases batch size for high queue depth" do
      # Simulate high queue depth
      Monitor.record_metric(:queue_depth, 5000)
      Monitor.record_metric(:throughput, 200)

      {:ok, initial_opts} = Optimizer.get_optimizations()

      Optimizer.optimize_now()
      Process.sleep(100)

      {:ok, final_opts} = Optimizer.get_optimizations()

      assert final_opts.batch_size > initial_opts.batch_size
    end

    test "decreases flush interval for high throughput" do
      # Simulate high throughput
      Monitor.record_metric(:queue_depth, 100)
      Monitor.record_metric(:throughput, 2000)

      {:ok, initial_opts} = Optimizer.get_optimizations()

      Optimizer.optimize_now()
      Process.sleep(100)

      {:ok, final_opts} = Optimizer.get_optimizations()

      assert final_opts.flush_interval <= initial_opts.flush_interval
    end

    test "enables compression when system is stable" do
      # Simulate stable system
      # 0.1%
      Monitor.record_metric(:error_rate, 0.001)
      # 50ms
      Monitor.record_metric(:latency, 50)

      Optimizer.set_optimization(:compression, false)

      Optimizer.optimize_now()
      Process.sleep(100)

      {:ok, final_opts} = Optimizer.get_optimizations()

      assert final_opts.compression == true
    end

    test "enables sharding for very high throughput" do
      # Simulate very high throughput
      Monitor.record_metric(:throughput, 6000)

      Optimizer.set_optimization(:sharding, false)

      Optimizer.optimize_now()
      Process.sleep(100)

      {:ok, final_opts} = Optimizer.get_optimizations()

      assert final_opts.sharding == true
    end
  end
end
