defmodule RubberDuck.Agents.ReviewAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.ReviewAgent
  alias RubberDuck.Agents.Agent

  describe "init/1" do
    test "initializes with default configuration" do
      config = %{
        name: "test_review_agent",
        enable_self_correction: true,
        llm_provider: :openai
      }

      assert {:ok, state} = ReviewAgent.init(config)
      assert state.config == config
      assert Map.has_key?(state, :review_cache)
      assert Map.has_key?(state, :metrics)
      assert Map.has_key?(state, :review_standards)
    end
  end

  describe "handle_task/3" do
    setup do
      {:ok, state} = ReviewAgent.init(%{})
      %{state: state}
    end

    test "handles review_changes task", %{state: state} do
      task = %{
        id: "review_1",
        type: :review_changes,
        priority: :high,
        payload: %{
          original_code: "def add(a, b), do: a + b",
          modified_code: "def add(a, b) when is_number(a) and is_number(b), do: a + b",
          change_type: :enhancement,
          file_path: "lib/math.ex"
        }
      }

      context = %{user_preferences: %{}, memory: %{}}

      assert {:ok, result, new_state} = ReviewAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :review_status)
      assert Map.has_key?(result, :feedback)
      assert Map.has_key?(result, :suggestions)
      assert Map.has_key?(result, :approval_score)
      assert new_state.metrics.tasks_completed == 1
    end

    test "handles quality_review task", %{state: state} do
      task = %{
        id: "quality_1",
        type: :quality_review,
        priority: :medium,
        payload: %{
          code: """
          defmodule Example do
            def process(data) do
              Enum.map(data, fn x -> x * 2 end)
            end
          end
          """,
          quality_aspects: [:readability, :maintainability, :performance]
        }
      }

      context = %{}

      assert {:ok, result, new_state} = ReviewAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :quality_scores)
      assert Map.has_key?(result, :improvements)
      assert result.quality_scores.readability >= 0 and result.quality_scores.readability <= 1.0
    end

    test "handles suggest_improvements task", %{state: state} do
      task = %{
        id: "improve_1",
        type: :suggest_improvements,
        priority: :low,
        payload: %{
          code: "def calc(x), do: x + 1",
          improvement_focus: [:naming, :documentation, :error_handling]
        }
      }

      context = %{}

      assert {:ok, result, _new_state} = ReviewAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :suggestions)
      assert is_list(result.suggestions)
      assert length(result.suggestions) > 0
    end

    test "handles verify_correctness task", %{state: state} do
      task = %{
        id: "verify_1",
        type: :verify_correctness,
        priority: :critical,
        payload: %{
          code: """
          def factorial(0), do: 1
          def factorial(n) when n > 0, do: n * factorial(n - 1)
          """,
          expected_behavior: "Calculate factorial of a number",
          test_cases: [
            %{input: 0, expected: 1},
            %{input: 5, expected: 120}
          ]
        }
      }

      context = %{}

      assert {:ok, result, _new_state} = ReviewAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :correctness_verified)
      assert Map.has_key?(result, :test_results)
      assert Map.has_key?(result, :edge_cases_covered)
    end

    test "returns error for unsupported task type", %{state: state} do
      task = %{
        id: "unknown_1",
        type: :unknown_review,
        payload: %{}
      }

      assert {:error, {:unsupported_task_type, :unknown_review}, ^state} =
               ReviewAgent.handle_task(task, %{}, state)
    end
  end

  describe "get_capabilities/1" do
    test "returns review capabilities" do
      {:ok, state} = ReviewAgent.init(%{})
      capabilities = ReviewAgent.get_capabilities(state)

      assert :change_review in capabilities
      assert :quality_assessment in capabilities
      assert :improvement_suggestions in capabilities
      assert :correctness_verification in capabilities
      assert :documentation_review in capabilities
    end
  end

  describe "handle_message/3" do
    setup do
      {:ok, state} = ReviewAgent.init(%{})
      %{state: state}
    end

    test "handles quick_review message", %{state: state} do
      message = {:quick_review, "def add(a, b), do: a + b", :basic}
      from = self()

      assert {:ok, new_state} = ReviewAgent.handle_message(message, from, state)

      # Should receive response
      assert_receive {:review_result, _result}, 2000
    end

    test "handles review_standards_update message", %{state: state} do
      message = {:review_standards_update, %{readability_weight: 0.4, security_weight: 0.6}}
      from = self()

      assert {:ok, new_state} = ReviewAgent.handle_message(message, from, state)
      assert new_state.review_standards.readability_weight == 0.4
      assert new_state.review_standards.security_weight == 0.6
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status" do
      {:ok, state} = ReviewAgent.init(%{})
      status = ReviewAgent.get_status(state)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :metrics)
      assert Map.has_key?(status, :capabilities)
      assert Map.has_key?(status, :health)
      assert Map.has_key?(status, :review_standards)
      assert status.capabilities == ReviewAgent.get_capabilities(state)
    end
  end

  describe "change detection" do
    setup do
      {:ok, state} = ReviewAgent.init(%{})
      %{state: state}
    end

    test "correctly identifies breaking changes", %{state: state} do
      task = %{
        id: "breaking_1",
        type: :review_changes,
        payload: %{
          original_code: "def process(data), do: data",
          modified_code: "def process(data, options), do: data",
          change_type: :refactoring
        }
      }

      assert {:ok, result, _} = ReviewAgent.handle_task(task, %{}, state)
      assert result.breaking_changes_detected == true
    end
  end

  describe "integration with Agent base" do
    @tag :integration
    test "can be started through Agent supervisor" do
      config = %{
        name: "test_review_integration",
        llm_provider: :mock,
        model: "mock-model"
      }

      # This will fail until ReviewAgent is implemented
      assert {:ok, pid} =
               Agent.start_link(
                 agent_type: :review,
                 agent_id: "test_review_1",
                 config: config,
                 registry: RubberDuck.Agents.Registry
               )

      assert Process.alive?(pid)

      # Test task assignment
      task = %{
        id: "int_test_1",
        type: :quality_review,
        payload: %{
          code: "def example, do: :ok",
          quality_aspects: [:all]
        }
      }

      assert {:ok, result} = Agent.assign_task(pid, task)
      assert result.task_id == task.id

      # Cleanup
      Agent.stop(pid)
    end
  end
end
