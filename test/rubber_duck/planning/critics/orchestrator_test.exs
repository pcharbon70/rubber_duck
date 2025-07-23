defmodule RubberDuck.Planning.Critics.OrchestratorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Critics.Orchestrator
  alias RubberDuck.Planning.Critics.CriticBehaviour

  # Test critics
  defmodule FastPassingCritic do
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Fast Passing Critic"

    @impl true
    def type, do: :hard

    @impl true
    def priority, do: 10

    @impl true
    def validate(_target, _opts) do
      {:ok, %{status: :passed, message: "All good"}}
    end
  end

  defmodule SlowWarningCritic do
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Slow Warning Critic"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 20

    @impl true
    def validate(_target, _opts) do
      # Simulate slow validation
      Process.sleep(10)

      {:ok,
       %{
         status: :warning,
         message: "Some concerns",
         suggestions: ["Consider improvement A", "Try approach B"]
       }}
    end
  end

  defmodule FailingCritic do
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Failing Critic"

    @impl true
    def type, do: :hard

    @impl true
    def priority, do: 30

    @impl true
    def validate(_target, _opts) do
      {:ok,
       %{
         status: :failed,
         message: "Critical issue found",
         details: %{error: "Bad thing happened"},
         suggestions: ["Fix the bad thing"]
       }}
    end
  end

  defmodule ConfigurableCritic do
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Configurable Critic"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 40

    @impl true
    def validate(_target, opts) do
      if Keyword.get(opts, :strict_mode, false) do
        {:ok, %{status: :failed, message: "Strict mode failure"}}
      else
        {:ok, %{status: :passed, message: "Lenient mode pass"}}
      end
    end

    @impl true
    def configure(opts) do
      Keyword.put(opts, :configured, true)
    end
  end

  defmodule ConditionalCritic do
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Conditional Critic"

    @impl true
    def type, do: :hard

    @impl true
    def priority, do: 50

    @impl true
    def validate(target, _opts) do
      {:ok, %{status: :passed, message: "Validated #{target.type}"}}
    end

    @impl true
    def can_validate?(target) do
      Map.get(target, :type) == :special
    end
  end

  describe "new/1" do
    test "creates orchestrator with default options" do
      orchestrator = Orchestrator.new()

      assert orchestrator.cache_enabled == true
      assert orchestrator.parallel_execution == true
      assert orchestrator.timeout == 30_000
      assert length(orchestrator.hard_critics) > 0
      assert length(orchestrator.soft_critics) > 0
    end

    test "creates orchestrator with custom options" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic],
          soft_critics: [SlowWarningCritic],
          cache_enabled: false,
          parallel_execution: false,
          timeout: 5_000
        )

      assert orchestrator.hard_critics == [FastPassingCritic]
      assert orchestrator.soft_critics == [SlowWarningCritic]
      assert orchestrator.cache_enabled == false
      assert orchestrator.parallel_execution == false
      assert orchestrator.timeout == 5_000
    end
  end

  describe "validate/3" do
    test "validates with all critics" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic, FailingCritic],
          soft_critics: [SlowWarningCritic],
          cache_enabled: false
        )

      target = %{id: "test-1", description: "Test target"}

      {:ok, results} = Orchestrator.validate(orchestrator, target)

      assert length(results) == 3
      assert Enum.any?(results, fn {critic, _} -> critic == FastPassingCritic end)
      assert Enum.any?(results, fn {critic, _} -> critic == FailingCritic end)
      assert Enum.any?(results, fn {critic, _} -> critic == SlowWarningCritic end)
    end

    test "respects critic priority order" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FailingCritic, FastPassingCritic],
          soft_critics: [],
          cache_enabled: false,
          parallel_execution: false
        )

      target = %{id: "test-2"}

      {:ok, results} = Orchestrator.validate(orchestrator, target)

      critics = Enum.map(results, fn {critic, _} -> critic end)
      assert critics == [FastPassingCritic, FailingCritic]
    end

    test "uses cache when enabled" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic],
          soft_critics: [],
          cache_enabled: true
        )

      target = %{id: "test-3"}

      # First call should execute critics
      {:ok, results1} = Orchestrator.validate(orchestrator, target)

      # Second call should use cache
      {:ok, results2} = Orchestrator.validate(orchestrator, target)

      assert results1 == results2
    end

    test "filters critics based on can_validate?" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic, ConditionalCritic],
          soft_critics: [],
          cache_enabled: false
        )

      # Target that ConditionalCritic won't validate
      target1 = %{id: "test-4", type: :normal}
      {:ok, results1} = Orchestrator.validate(orchestrator, target1)
      assert length(results1) == 1

      # Target that ConditionalCritic will validate
      target2 = %{id: "test-5", type: :special}
      {:ok, results2} = Orchestrator.validate(orchestrator, target2)
      assert length(results2) == 2
    end
  end

  describe "validate_hard/3 and validate_soft/3" do
    test "validate_hard runs only hard critics" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic, FailingCritic],
          soft_critics: [SlowWarningCritic],
          custom_critics: [ConfigurableCritic],
          cache_enabled: false
        )

      target = %{id: "test-hard"}

      results = Orchestrator.validate_hard(orchestrator, target)

      assert length(results) == 2
      critics = Enum.map(results, fn {critic, _} -> critic end)
      assert FastPassingCritic in critics
      assert FailingCritic in critics
      assert SlowWarningCritic not in critics
    end

    test "validate_soft runs only soft critics" do
      orchestrator =
        Orchestrator.new(
          hard_critics: [FastPassingCritic],
          soft_critics: [SlowWarningCritic],
          custom_critics: [ConfigurableCritic],
          cache_enabled: false
        )

      target = %{id: "test-soft"}

      results = Orchestrator.validate_soft(orchestrator, target)

      assert length(results) == 2
      critics = Enum.map(results, fn {critic, _} -> critic end)
      assert SlowWarningCritic in critics
      assert ConfigurableCritic in critics
      assert FastPassingCritic not in critics
    end
  end

  describe "add_critic/2" do
    test "adds custom critic" do
      orchestrator = Orchestrator.new(custom_critics: [])

      updated = Orchestrator.add_critic(orchestrator, ConfigurableCritic)

      assert ConfigurableCritic in updated.custom_critics
    end

    test "raises error for invalid critic" do
      orchestrator = Orchestrator.new()

      assert_raise ArgumentError, fn ->
        Orchestrator.add_critic(orchestrator, String)
      end
    end
  end

  describe "configure_critic/3" do
    test "configures specific critic" do
      orchestrator = Orchestrator.new()

      updated =
        Orchestrator.configure_critic(
          orchestrator,
          ConfigurableCritic,
          %{strict_mode: true}
        )

      assert updated.config[ConfigurableCritic] == %{strict_mode: true}
    end
  end

  describe "aggregate_results/1" do
    test "aggregates validation results correctly" do
      results = [
        {FastPassingCritic, {:ok, %{status: :passed, message: "OK"}}},
        {SlowWarningCritic,
         {:ok,
          %{
            status: :warning,
            message: "Warning",
            suggestions: ["Fix A", "Fix B"]
          }}},
        {FailingCritic,
         {:ok,
          %{
            status: :failed,
            message: "Failed",
            details: %{error: "Bad"}
          }}}
      ]

      aggregated = Orchestrator.aggregate_results(results)

      assert aggregated.summary == :failed
      assert length(aggregated.hard_critics) == 2
      assert length(aggregated.soft_critics) == 1
      assert length(aggregated.blocking_issues) == 1
      assert "Fix A" in aggregated.suggestions
      assert "Fix B" in aggregated.suggestions
      assert aggregated.metadata.total_critics_run == 3
    end

    test "handles critic execution errors" do
      results = [
        {FastPassingCritic, {:ok, %{status: :passed, message: "OK"}}},
        {FailingCritic, {:error, "Critic crashed"}}
      ]

      aggregated = Orchestrator.aggregate_results(results)

      assert aggregated.summary == :passed
      assert length(aggregated.all_validations) == 2

      error_result = Enum.find(aggregated.all_validations, &(&1.status == :error))
      assert error_result.critic_name == "Failing Critic"
    end
  end

  describe "parallel execution" do
    test "executes critics in parallel when enabled" do
      orchestrator =
        Orchestrator.new(
          hard_critics: List.duplicate(SlowWarningCritic, 5),
          soft_critics: [],
          cache_enabled: false,
          parallel_execution: true
        )

      target = %{id: "test-parallel"}

      start_time = System.monotonic_time(:millisecond)
      {:ok, _results} = Orchestrator.validate(orchestrator, target)
      duration = System.monotonic_time(:millisecond) - start_time

      # With parallel execution, 5 critics sleeping 10ms each should take ~10ms total
      # In sequential, it would take ~50ms
      assert duration < 30
    end

    test "executes critics sequentially when disabled" do
      orchestrator =
        Orchestrator.new(
          hard_critics: List.duplicate(SlowWarningCritic, 3),
          soft_critics: [],
          cache_enabled: false,
          parallel_execution: false
        )

      target = %{id: "test-sequential"}

      start_time = System.monotonic_time(:millisecond)
      {:ok, _results} = Orchestrator.validate(orchestrator, target)
      duration = System.monotonic_time(:millisecond) - start_time

      # Sequential execution of 3 critics sleeping 10ms each should take ~30ms
      assert duration >= 30
    end
  end
end
