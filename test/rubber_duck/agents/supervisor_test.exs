defmodule RubberDuck.Agents.SupervisorTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{Supervisor, AgentRegistry}

  import ExUnit.CaptureLog

  # Test helper module that implements agent behavior
  defmodule TestAgent do
    use GenServer
    alias RubberDuck.Agents.Behavior

    @behaviour Behavior

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    def crash(pid) do
      GenServer.cast(pid, :crash)
    end

    def block(pid) do
      GenServer.call(pid, :block, :infinity)
    end

    @impl true
    def init(config) do
      {:ok, %{config: config, status: :ready, task_queue: []}}
    end

    @impl Behavior
    def handle_task(task, _from, state) do
      case task do
        :crash_task ->
          {:reply, {:error, :crash}, state}

        :success_task ->
          {:reply, {:ok, :completed}, state}

        _ ->
          {:reply, {:ok, task}, state}
      end
    end

    @impl Behavior
    def handle_message(_message, _from, state) do
      {:noreply, state}
    end

    @impl Behavior
    def get_capabilities(state) do
      Map.get(state.config, :capabilities, [:test_capability])
    end

    @impl Behavior
    def get_status(state) do
      %{
        status: state.status,
        config: state.config,
        queue_length: length(state.task_queue)
      }
    end

    @impl Behavior
    def terminate(_reason, _state) do
      :ok
    end

    @impl GenServer
    def handle_cast(:crash, _state) do
      raise "Test crash"
    end

    @impl GenServer
    def handle_call(:block, _from, state) do
      Process.sleep(:infinity)
      {:reply, :ok, state}
    end

    @impl GenServer
    def handle_call({:agent_request, task, from, ref}, _from, state) do
      result =
        case handle_task(task, from, state) do
          {:reply, reply, new_state} ->
            send(from, {:agent_response, reply, ref})
            new_state

          {:noreply, new_state} ->
            new_state
        end

      {:reply, :ok, result}
    end
  end

  setup do
    # Ensure clean state
    case Process.whereis(Supervisor) do
      nil ->
        {:ok, _pid} = Supervisor.start_link([])

      _pid ->
        # Clean up any existing agents
        for {_, pid, _} <- DynamicSupervisor.which_children(Supervisor) do
          DynamicSupervisor.terminate_child(Supervisor, pid)
        end
    end

    # Ensure AgentRegistry is running
    case Process.whereis(AgentRegistry) do
      nil ->
        {:ok, _pid} = AgentRegistry.start_link([])

      _pid ->
        :ok
    end

    on_exit(fn ->
      # Clean up all agents
      for {_, pid, _} <- DynamicSupervisor.which_children(Supervisor) do
        DynamicSupervisor.terminate_child(Supervisor, pid)
      end
    end)

    :ok
  end

  describe "start_agent/2" do
    test "successfully starts an agent with specified type" do
      assert {:ok, pid} = Supervisor.start_agent(:research, %{})
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts agents of all supported types" do
      types = [:research, :analysis, :generation, :review]

      for type <- types do
        assert {:ok, pid} = Supervisor.start_agent(type, %{})
        assert Process.alive?(pid)
      end
    end

    test "passes configuration to agent" do
      config = %{
        memory_tier: :mid_term,
        capabilities: [:custom_cap],
        max_retries: 5
      }

      assert {:ok, pid} = Supervisor.start_agent(:research, config)

      # Verify agent received config via registry metadata
      agent_id = "research_#{:erlang.phash2(pid)}"
      {:ok, _pid, metadata} = AgentRegistry.lookup_agent(agent_id)
      assert metadata.config == config
    end

    test "prevents duplicate agent IDs" do
      # Start first agent
      {:ok, pid1} = Supervisor.start_agent(:research, %{id: "duplicate_test"})

      # Try to start another with same ID
      assert {:error, {:already_started, ^pid1}} =
               Supervisor.start_agent(:research, %{id: "duplicate_test"})
    end

    test "registers agent in both registries" do
      {:ok, pid} = Supervisor.start_agent(:analysis, %{})
      agent_id = "analysis_#{:erlang.phash2(pid)}"

      # Check standard Registry
      assert [{^pid, _}] = Registry.lookup(RubberDuck.Agents.Registry, agent_id)

      # Check AgentRegistry
      assert {:ok, ^pid, metadata} = AgentRegistry.lookup_agent(agent_id)
      assert metadata.type == :analysis
    end

    test "returns error for invalid agent type" do
      capture_log(fn ->
        assert {:error, _} = Supervisor.start_agent(:invalid_type, %{})
      end)
    end

    test "starts test agent when configured" do
      config = %{module: TestAgent, capabilities: [:test]}
      assert {:ok, pid} = Supervisor.start_agent(:test, config)
      assert Process.alive?(pid)
    end
  end

  describe "stop_agent/1" do
    test "stops agent by PID" do
      {:ok, pid} = Supervisor.start_agent(:research, %{})

      assert :ok = Supervisor.stop_agent(pid)
      refute Process.alive?(pid)
    end

    test "stops agent by ID" do
      {:ok, pid} = Supervisor.start_agent(:research, %{})
      agent_id = "research_#{:erlang.phash2(pid)}"

      assert :ok = Supervisor.stop_agent(agent_id)
      refute Process.alive?(pid)
    end

    test "removes agent from registries" do
      {:ok, pid} = Supervisor.start_agent(:analysis, %{})
      agent_id = "analysis_#{:erlang.phash2(pid)}"

      assert :ok = Supervisor.stop_agent(pid)

      # Verify removal from standard Registry
      assert [] = Registry.lookup(RubberDuck.Agents.Registry, agent_id)

      # Verify removal from AgentRegistry
      assert {:error, :agent_not_found} = AgentRegistry.lookup_agent(agent_id)
    end

    test "returns error for non-existent agent" do
      assert {:error, :not_found} = Supervisor.stop_agent("non_existent")
    end
  end

  describe "list_agents/0" do
    test "returns empty list when no agents running" do
      assert [] = Supervisor.list_agents()
    end

    test "returns information about running agents" do
      {:ok, _} = Supervisor.start_agent(:research, %{tag: "test1"})
      {:ok, _} = Supervisor.start_agent(:analysis, %{tag: "test2"})

      agents = Supervisor.list_agents()
      assert length(agents) == 2

      assert Enum.any?(agents, fn {id, _pid, meta} ->
               String.starts_with?(id, "research_") and meta.config.tag == "test1"
             end)

      assert Enum.any?(agents, fn {id, _pid, meta} ->
               String.starts_with?(id, "analysis_") and meta.config.tag == "test2"
             end)
    end

    test "updates list when agents are stopped" do
      {:ok, pid} = Supervisor.start_agent(:research, %{})
      assert length(Supervisor.list_agents()) == 1

      Supervisor.stop_agent(pid)
      assert [] = Supervisor.list_agents()
    end
  end

  describe "agent_counts/0" do
    test "returns zero counts for all types when no agents" do
      counts = Supervisor.agent_counts()

      assert counts.research == 0
      assert counts.analysis == 0
      assert counts.generation == 0
      assert counts.review == 0
      assert counts.total == 0
    end

    test "accurately counts agents by type" do
      # Start various agents
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:analysis, %{})
      {:ok, _} = Supervisor.start_agent(:generation, %{})

      counts = Supervisor.agent_counts()

      assert counts.research == 2
      assert counts.analysis == 1
      assert counts.generation == 1
      assert counts.review == 0
      assert counts.total == 4
    end
  end

  describe "health_check/0" do
    test "returns healthy status with no agents" do
      health = Supervisor.health_check()

      assert health.status == :healthy
      assert health.agent_count == 0
      assert is_float(health.uptime_seconds)
      assert health.uptime_seconds >= 0
    end

    test "includes agent counts in health check" do
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:analysis, %{})

      health = Supervisor.health_check()

      assert health.status == :healthy
      assert health.agent_count == 2
      assert health.agent_breakdown.research == 1
      assert health.agent_breakdown.analysis == 1
    end
  end

  describe "fault tolerance" do
    @tag :capture_log
    test "supervisor continues running when agent crashes" do
      # Start test agent that can crash
      {:ok, pid} = Supervisor.start_agent(:test, %{module: TestAgent})

      # Crash the agent
      capture_log(fn ->
        TestAgent.crash(pid)
        Process.sleep(100)
      end)

      # Supervisor should still be running
      assert Process.alive?(Process.whereis(Supervisor))

      # Should be able to start new agents
      assert {:ok, _} = Supervisor.start_agent(:research, %{})
    end

    test "respects restart limits" do
      # This test would require modifying supervisor restart strategy
      # Currently using :temporary, so agents don't restart
      # Marking as pending for future implementation
      :ok
    end
  end

  describe "concurrent operations" do
    test "handles concurrent agent starts" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Supervisor.start_agent(:research, %{index: i})
          end)
        end

      results = Task.await_many(tasks)
      successful = Enum.filter(results, &match?({:ok, _}, &1))

      assert length(successful) == 10
    end

    test "handles concurrent starts and stops" do
      # Start some agents
      pids =
        for i <- 1..5 do
          {:ok, pid} = Supervisor.start_agent(:analysis, %{index: i})
          pid
        end

      # Concurrently stop some and start others
      tasks = [
        Task.async(fn -> Supervisor.stop_agent(Enum.at(pids, 0)) end),
        Task.async(fn -> Supervisor.stop_agent(Enum.at(pids, 1)) end),
        Task.async(fn -> Supervisor.start_agent(:generation, %{}) end),
        Task.async(fn -> Supervisor.start_agent(:review, %{}) end)
      ]

      Task.await_many(tasks)

      # Verify final state
      agents = Supervisor.list_agents()
      # 3 original + 2 new
      assert length(agents) == 5
    end
  end

  describe "capability registration" do
    test "registers agent capabilities correctly" do
      {:ok, _} = Supervisor.start_agent(:research, %{})
      {:ok, _} = Supervisor.start_agent(:analysis, %{})

      # Find agents by capability
      {:ok, research_agents} = AgentRegistry.find_by_capability(:semantic_search)
      assert length(research_agents) > 0

      {:ok, analysis_agents} = AgentRegistry.find_by_capability(:code_analysis)
      assert length(analysis_agents) > 0
    end

    test "custom capabilities are registered" do
      config = %{
        module: TestAgent,
        capabilities: [:custom_test_cap, :another_cap]
      }

      {:ok, pid} = Supervisor.start_agent(:test, config)
      agent_id = "test_#{:erlang.phash2(pid)}"

      {:ok, _pid, metadata} = AgentRegistry.lookup_agent(agent_id)
      assert :custom_test_cap in metadata.capabilities
      assert :another_cap in metadata.capabilities
    end
  end

  describe "agent type handling" do
    test "starts correct module for each agent type" do
      # Test research agent
      {:ok, pid} = Supervisor.start_agent(:research, %{})
      assert {:ok, _pid, meta} = AgentRegistry.lookup_agent("research_#{:erlang.phash2(pid)}")
      assert meta.type == :research

      # Would need to verify actual module via :sys.get_state or similar
      # For now, verify it's registered with correct type
    end

    test "applies default capabilities for agent types" do
      # Start each type and verify capabilities
      type_capabilities = %{
        research: [:semantic_search, :context_building, :reference_finding],
        analysis: [:code_analysis, :security_analysis, :complexity_analysis, :pattern_detection, :style_checking],
        generation: [:code_generation, :refactoring, :completion, :fixing],
        review: [
          :change_review,
          :quality_assessment,
          :improvement_suggestions,
          :correctness_verification,
          :documentation_review
        ]
      }

      for {type, expected_caps} <- type_capabilities do
        {:ok, pid} = Supervisor.start_agent(type, %{})
        agent_id = "#{type}_#{:erlang.phash2(pid)}"

        {:ok, _pid, metadata} = AgentRegistry.lookup_agent(agent_id)

        for cap <- expected_caps do
          assert cap in metadata.capabilities
        end
      end
    end
  end

  describe "error handling" do
    test "handles registry lookup failures gracefully" do
      # Stop agent by non-existent ID
      assert {:error, :not_found} = Supervisor.stop_agent("fake_id")
    end

    test "handles invalid configurations" do
      capture_log(fn ->
        # Invalid module
        assert {:error, _} = Supervisor.start_agent(:test, %{module: NonExistentModule})
      end)
    end

    test "handles supervisor not started" do
      # This would require stopping the supervisor, which affects other tests
      # Marking as a note for integration testing
      :ok
    end
  end

  describe "agent lifecycle" do
    test "agents receive proper initialization" do
      config = %{test_value: :initialized}
      {:ok, pid} = Supervisor.start_agent(:research, config)

      agent_id = "research_#{:erlang.phash2(pid)}"
      {:ok, _pid, metadata} = AgentRegistry.lookup_agent(agent_id)

      assert metadata.config.test_value == :initialized
      assert metadata.started_at
      assert metadata.status == :running
    end

    test "agents are properly terminated" do
      {:ok, pid} = Supervisor.start_agent(:test, %{module: TestAgent})

      # Monitor the agent
      ref = Process.monitor(pid)

      # Stop the agent
      Supervisor.stop_agent(pid)

      # Should receive DOWN message
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}
    end
  end
end
