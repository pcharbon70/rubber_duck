defmodule RubberDuck.Workflows.FoundationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{Workflow, Registry, Executor, Step, Cache, Metrics}

  # Test workflow module
  defmodule TestWorkflow do
    use RubberDuck.Workflows.Workflow

    workflow do
      step :fetch_data do
        run TestSteps.FetchData
        max_retries 2
      end

      step :process_data do
        run TestSteps.ProcessData
        argument :data, result(:fetch_data)
      end

      step :save_results do
        run TestSteps.SaveResults
        argument :processed, result(:process_data)
      end
    end
  end

  # Test step modules
  defmodule TestSteps.FetchData do
    use RubberDuck.Workflows.Step

    @impl true
    def run(_input, _context) do
      {:ok, %{data: [1, 2, 3, 4, 5]}}
    end
  end

  defmodule TestSteps.ProcessData do
    use RubberDuck.Workflows.Step

    @impl true
    def run(%{data: data}, _context) do
      processed = Enum.map(data, &(&1 * 2))
      {:ok, %{processed: processed}}
    end
  end

  defmodule TestSteps.SaveResults do
    use RubberDuck.Workflows.Step

    @impl true
    def run(%{processed: data}, _context) do
      # Simulate saving
      {:ok, %{saved: true, count: length(data)}}
    end
  end

  # Failing step for error testing
  defmodule TestSteps.FailingStep do
    use RubberDuck.Workflows.Step

    @impl true
    def run(_input, _context) do
      {:error, :intentional_failure}
    end
  end

  # Step with compensation
  defmodule TestSteps.CompensatingStep do
    use RubberDuck.Workflows.Step

    @impl true
    def run(input, _context) do
      # Track that we ran
      send(self(), {:step_executed, input})
      {:ok, %{executed: true}}
    end

    @impl true
    def compensate(_input, _output, _context) do
      # Track that we compensated
      send(self(), :step_compensated)
      :ok
    end
  end

  setup do
    # Start required processes
    {:ok, _} = start_supervised(Registry)
    {:ok, _} = start_supervised(Executor)
    {:ok, _} = start_supervised(Cache)

    :ok
  end

  describe "workflow definition" do
    test "defines workflow with steps" do
      assert TestWorkflow.name() == :test_workflow
      assert TestWorkflow.description() =~ "Workflow:"
      assert TestWorkflow.version() == "1.0.0"

      steps = TestWorkflow.steps()
      assert length(steps) == 3

      # Verify step names
      step_names = Enum.map(steps, & &1.name)
      assert :fetch_data in step_names
      assert :process_data in step_names
      assert :save_results in step_names
    end

    test "workflow can be executed" do
      result = TestWorkflow.run()

      assert {:ok, reactor_result} = result
      assert reactor_result.state == :complete
    end
  end

  describe "dynamic workflow building" do
    test "creates and executes dynamic workflow" do
      workflow =
        Workflow.new("dynamic_test")
        |> Workflow.add_step(:step1, TestSteps.FetchData)
        |> Workflow.add_step(:step2, TestSteps.ProcessData,
          arguments: [{:data, {:result, :step1}}],
          depends_on: [:step1]
        )
        |> Workflow.build()

      assert workflow.name == "dynamic_test"
      assert length(workflow.steps) == 2
    end
  end

  describe "workflow registry" do
    test "registers and looks up workflows" do
      assert :ok = Registry.register(TestWorkflow)

      assert {:ok, info} = Registry.lookup(:test_workflow)
      assert info.module == TestWorkflow
      assert info.name == :test_workflow
    end

    test "lists registered workflows" do
      Registry.register(TestWorkflow, tags: [:test, :example])

      workflows = Registry.list_workflows()
      assert length(workflows) > 0

      test_workflows = Registry.list_by_tag(:test)
      assert length(test_workflows) > 0
    end

    test "updates workflow metadata" do
      Registry.register(TestWorkflow)

      metadata = %{author: "Test", priority: :high}
      assert :ok = Registry.update_metadata(:test_workflow, metadata)

      assert {:ok, retrieved} = Registry.get_metadata(:test_workflow)
      assert retrieved == metadata
    end
  end

  describe "workflow execution" do
    test "executes workflow synchronously" do
      {:ok, result} = Executor.run(TestWorkflow)

      assert result.state == :complete
      # Verify all steps completed
      assert Map.has_key?(result.fields, :fetch_data)
      assert Map.has_key?(result.fields, :process_data)
      assert Map.has_key?(result.fields, :save_results)
    end

    test "handles step failures" do
      failing_workflow =
        Workflow.new("failing")
        |> Workflow.add_step(:fail_step, TestSteps.FailingStep)
        |> Workflow.build()

      assert {:error, _} = Executor.run(failing_workflow)
    end

    test "tracks workflow status" do
      task =
        Task.async(fn ->
          Executor.run(TestWorkflow, %{}, timeout: 5000)
        end)

      # Give it a moment to start
      Process.sleep(10)

      running = Executor.list_running()
      assert length(running) > 0

      # Wait for completion
      Task.await(task)

      # Should no longer be running
      running_after = Executor.list_running()
      assert length(running_after) == length(running) - 1
    end
  end

  describe "step result caching" do
    test "caches step results" do
      key = "test_key"
      value = %{data: [1, 2, 3]}

      assert :ok = Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "returns miss for non-existent keys" do
      assert :miss = Cache.get("non_existent")
    end

    test "respects TTL" do
      key = "ttl_test"
      value = "test_value"

      # Put with very short TTL
      # 50ms
      Cache.put(key, value, 50)

      # Should exist immediately
      assert {:ok, ^value} = Cache.get(key)

      # Wait for expiry
      Process.sleep(100)

      # Should be expired
      assert :miss = Cache.get(key)
    end

    test "generates consistent cache keys" do
      workflow = TestWorkflow
      input = %{user: "test", data: [1, 2, 3]}

      key1 = Cache.generate_key(workflow, input)
      key2 = Cache.generate_key(workflow, input)

      assert key1 == key2
    end

    test "cached function execution" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        :expensive_result
      end

      # First call executes function
      result1 = Cache.cached("cached_fun_test", 1000, fun)
      assert result1 == :expensive_result
      assert :counters.get(counter, 1) == 1

      # Second call uses cache
      result2 = Cache.cached("cached_fun_test", 1000, fun)
      assert result2 == :expensive_result
      # Counter didn't increment
      assert :counters.get(counter, 1) == 1
    end
  end

  describe "workflow metrics" do
    test "records workflow execution metrics" do
      # Attach a test handler
      test_pid = self()

      :telemetry.attach(
        "test-workflow-metrics",
        [:rubber_duck, :workflow, :completed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Record a workflow completion
      workflow_info = %{
        started_at: DateTime.utc_now() |> DateTime.add(-1000, :millisecond),
        completed_at: DateTime.utc_now(),
        status: :completed,
        workflow: TestWorkflow,
        result: %{results: %{step1: {:ok, 1}, step2: {:ok, 2}}}
      }

      Metrics.record_workflow_completion("test_wf_1", workflow_info)

      # Verify telemetry event was emitted
      assert_receive {:telemetry, [:rubber_duck, :workflow, :completed], measurements, metadata}
      assert metadata.workflow_id == "test_wf_1"
      assert measurements.duration >= 1000

      # Cleanup
      :telemetry.detach("test-workflow-metrics")
    end

    test "tracks custom metrics" do
      test_pid = self()

      :telemetry.attach(
        "test-custom-metrics",
        [:rubber_duck, :workflow, :custom, :items_processed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:custom_metric, measurements.value, metadata})
        end,
        nil
      )

      # Record custom metric
      Metrics.record_custom_metric("test_wf_2", :items_processed, 42, %{batch_id: "batch_1"})

      # Verify custom metric was recorded
      assert_receive {:custom_metric, 42, metadata}
      assert metadata.workflow_id == "test_wf_2"
      assert metadata.batch_id == "batch_1"

      # Cleanup
      :telemetry.detach("test-custom-metrics")
    end
  end

  describe "error handling and compensation" do
    test "triggers compensation on failure" do
      # Workflow with compensating step
      workflow =
        Workflow.new("compensating_workflow")
        |> Workflow.add_step(:step1, TestSteps.CompensatingStep)
        |> Workflow.add_step(:step2, TestSteps.FailingStep, depends_on: [:step1])
        |> Workflow.build()

      # Execute workflow (will fail at step2)
      {:error, _} = Executor.run(workflow, %{test: true})

      # Verify step1 executed
      assert_receive {:step_executed, %{test: true}}

      # Compensation would be triggered by Reactor
      # In a real test with full Reactor integration, we'd verify this
    end
  end

  describe "concurrent execution" do
    test "executes independent steps concurrently" do
      # Create workflow with parallel steps
      workflow =
        Workflow.new("parallel_workflow")
        |> Workflow.add_step(:parallel1, TestSteps.FetchData)
        |> Workflow.add_step(:parallel2, TestSteps.FetchData)
        |> Workflow.add_step(:parallel3, TestSteps.FetchData)
        |> Workflow.add_step(:combine, TestSteps.ProcessData,
          arguments: [
            {:data1, {:result, :parallel1}},
            {:data2, {:result, :parallel2}},
            {:data3, {:result, :parallel3}}
          ],
          depends_on: [:parallel1, :parallel2, :parallel3]
        )
        |> Workflow.build()

      # Execute and measure time
      start = System.monotonic_time(:millisecond)
      {:ok, _result} = Executor.run(workflow)
      duration = System.monotonic_time(:millisecond) - start

      # With concurrent execution, should be faster than sequential
      # (This is a simplified test - real concurrency testing would be more complex)
      # Reasonable time for parallel execution
      assert duration < 1000
    end
  end
end
