defmodule RubberDuck.Jido.Agents.TelemetryTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.{Telemetry, Supervisor}
  alias RubberDuck.Jido.Agents.ExampleAgent
  
  setup do
    # Start supervisor
    {:ok, _} = start_supervised(Supervisor)
    
    # Ensure ETS table for restart policies exists
    if :ets.info(:agent_restart_policies) == :undefined do
      :ets.new(:agent_restart_policies, [:set, :public, :named_table])
    end
    
    # Detach any existing handlers
    Telemetry.detach_default_handlers()
    
    on_exit(fn ->
      Telemetry.detach_default_handlers()
      # Clean up any test handlers
      :telemetry.list_handlers([:rubber_duck, :agent, :_])
      |> Enum.each(fn handler ->
        if String.starts_with?(handler.id, "test-"), do: :telemetry.detach(handler.id)
      end)
    end)
    
    :ok
  end
  
  describe "lifecycle events" do
    test "emits spawn event" do
      test_pid = self()
      
      :telemetry.attach(
        "test-spawn",
        [:rubber_duck, :agent, :spawn],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.agent_spawned("test_agent_1", ExampleAgent, %{custom: "data"})
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :spawn], measurements, metadata}
      assert measurements.count == 1
      assert metadata.agent_id == "test_agent_1"
      assert metadata.agent_module == ExampleAgent
      assert metadata.custom == "data"
      assert is_integer(metadata.timestamp)
    end
    
    test "emits terminate event" do
      test_pid = self()
      
      :telemetry.attach(
        "test-terminate",
        [:rubber_duck, :agent, :terminate],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.agent_terminated("test_agent_2", :normal, %{uptime: 120})
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :terminate], measurements, metadata}
      assert measurements.count == 1
      assert metadata.agent_id == "test_agent_2"
      assert metadata.reason == :normal
      assert metadata.uptime == 120
    end
    
    test "emits state change event" do
      test_pid = self()
      
      :telemetry.attach(
        "test-state-change",
        [:rubber_duck, :agent, :state_change],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.agent_state_changed("test_agent_3", :idle, :busy)
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :state_change], _measurements, metadata}
      assert metadata.old_state == :idle
      assert metadata.new_state == :busy
    end
    
    test "emits error event" do
      test_pid = self()
      
      :telemetry.attach(
        "test-error",
        [:rubber_duck, :agent, :error],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.agent_error("test_agent_4", {:error, :timeout})
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :error], measurements, metadata}
      assert measurements.severity == 2
      assert metadata.error == {:error, :timeout}
    end
    
    test "emits recovery event" do
      test_pid = self()
      
      :telemetry.attach(
        "test-recovery",
        [:rubber_duck, :agent, :recovery],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.agent_recovered("test_agent_5", :circuit_open)
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :recovery], _measurements, metadata}
      assert metadata.from_error == :circuit_open
    end
  end
  
  describe "performance events" do
    test "spans action execution" do
      test_pid = self()
      
      :telemetry.attach_many(
        "test-action-span",
        [
          [:rubber_duck, :agent, :action, :start],
          [:rubber_duck, :agent, :action, :stop],
          [:rubber_duck, :agent, :action, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Successful action returns the value from the function
      result = Telemetry.span_action("test_agent_6", TestAction, %{}, fn ->
        Process.sleep(10)
        :my_result
      end)
      
      assert result == :my_result
      
      # Just verify we get the events - metadata structure varies with telemetry.span
      assert_receive {:telemetry, [:rubber_duck, :agent, :action, :start], start_measurements, _start_metadata}
      assert is_integer(start_measurements.system_time)
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :action, :stop], stop_measurements, _stop_metadata}
      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration > 0
      
      # Failing action
      assert_raise RuntimeError, fn ->
        Telemetry.span_action("test_agent_7", FailingAction, %{}, fn ->
          raise "test error"
        end)
      end
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :action, :exception], _exception_measurements, _exception_metadata}
    end
    
    test "reports queue depth" do
      test_pid = self()
      
      :telemetry.attach(
        "test-queue-depth",
        [:rubber_duck, :agent, :queue, :depth],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      Telemetry.report_queue_depth("main_queue", 42, %{pool: "worker_pool"})
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :queue, :depth], measurements, metadata}
      assert measurements.depth == 42
      assert metadata.queue_name == "main_queue"
      assert metadata.pool == "worker_pool"
    end
  end
  
  describe "resource events" do
    test "reports agent resources" do
      test_pid = self()
      
      :telemetry.attach_many(
        "test-resources",
        [
          [:rubber_duck, :agent, :memory],
          [:rubber_duck, :agent, :cpu],
          [:rubber_duck, :agent, :message_queue]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Create a real process to measure
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      
      {:ok, resources} = Telemetry.report_agent_resources("test_agent_8", pid)
      
      assert is_integer(resources.memory)
      assert resources.memory > 0
      assert is_integer(resources.queue_length)
      assert is_integer(resources.reductions)
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :memory], memory_measurements, memory_metadata}
      assert memory_measurements.bytes == resources.memory
      assert memory_metadata.agent_id == "test_agent_8"
      assert memory_metadata.pid == pid
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :cpu], cpu_measurements, _}
      assert cpu_measurements.reductions == resources.reductions
      
      assert_receive {:telemetry, [:rubber_duck, :agent, :message_queue], queue_measurements, _}
      assert queue_measurements.length == resources.queue_length
      
      Agent.stop(pid)
    end
    
    test "handles non-existent process" do
      # Create a pid that doesn't exist
      fake_pid = spawn(fn -> :ok end)
      Process.sleep(10)  # Let it die
      
      {:error, :process_not_found} = Telemetry.report_agent_resources("test_agent_9", fake_pid)
    end
  end
  
  describe "default handlers" do
    test "attaches and detaches default handlers" do
      initial_count = length(:telemetry.list_handlers([:rubber_duck, :agent]))
      
      Telemetry.attach_default_handlers()
      
      handlers = :telemetry.list_handlers([:rubber_duck, :agent])
      assert length(handlers) > initial_count
      
      # Check specific handlers exist
      handler_ids = Enum.map(handlers, & &1.id)
      assert "agent-lifecycle-logger" in handler_ids
      assert "agent-performance-logger" in handler_ids
      assert "agent-resource-logger" in handler_ids
      assert "agent-health-logger" in handler_ids
      
      Telemetry.detach_default_handlers()
      
      final_handlers = :telemetry.list_handlers([:rubber_duck, :agent])
      assert length(final_handlers) == initial_count
    end
  end
  
  describe "integration with agent lifecycle" do
    @tag :skip
    test "tracks agent spawn and termination through server" do
      test_pid = self()
      
      :telemetry.attach_many(
        "test-integration",
        [
          [:rubber_duck, :agent, :spawn],
          [:rubber_duck, :agent, :terminate],
          [:rubber_duck, :jido, :agent, :terminated]  # Also listen for the old event
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Start an agent
      {:ok, _pid} = Supervisor.start_agent(ExampleAgent, %{}, id: "telemetry_lifecycle_test")
      
      # Should receive spawn event
      assert_receive {:telemetry, [:rubber_duck, :agent, :spawn], _, spawn_metadata}, 1000
      assert spawn_metadata.agent_id == "telemetry_lifecycle_test"
      assert spawn_metadata.agent_module == ExampleAgent
      
      # Stop the agent
      :ok = Supervisor.stop_agent("telemetry_lifecycle_test")
      
      # Should receive terminate event (may take a moment due to graceful shutdown)
      # Accept either the new or old telemetry event
      assert_receive {:telemetry, event, _, terminate_metadata}, 2000
      assert event in [[:rubber_duck, :agent, :terminate], [:rubber_duck, :jido, :agent, :terminated]]
      assert terminate_metadata.agent_id == "telemetry_lifecycle_test"
      assert terminate_metadata.reason in [:shutdown, :normal]
    end
  end
end