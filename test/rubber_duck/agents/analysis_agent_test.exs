defmodule RubberDuck.Agents.AnalysisAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.AnalysisAgent
  alias RubberDuck.Agents.Agent

  describe "init/1" do
    test "initializes with default configuration" do
      config = %{
        name: "test_analysis_agent",
        max_concurrent_analyses: 5
      }

      assert {:ok, state} = AnalysisAgent.init(config)
      assert state.config == config
      assert Map.has_key?(state, :analysis_cache)
      assert Map.has_key?(state, :metrics)
    end
  end

  describe "handle_task/3" do
    setup do
      {:ok, state} = AnalysisAgent.init(%{})
      %{state: state}
    end

    test "handles analyze_code task", %{state: state} do
      task = %{
        id: "analyze_1",
        type: :analyze_code,
        priority: :high,
        payload: %{
          file_path: "lib/example.ex",
          analysis_types: [:semantic, :style, :security]
        }
      }

      context = %{user_preferences: %{}, memory: %{}}

      assert {:ok, result, new_state} = AnalysisAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :analysis_results)
      assert Map.has_key?(result, :issues_found)
      assert Map.has_key?(result, :confidence)
      assert new_state.metrics.tasks_completed == 1
    end

    test "handles security_review task", %{state: state} do
      task = %{
        id: "security_1",
        type: :security_review,
        priority: :critical,
        payload: %{
          file_paths: ["lib/auth.ex", "lib/api.ex"],
          vulnerability_types: [:sql_injection, :xss, :hardcoded_secrets]
        }
      }

      context = %{}

      assert {:ok, result, new_state} = AnalysisAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :vulnerabilities)
      assert Map.has_key?(result, :severity_summary)
      assert is_list(result.vulnerabilities)
    end

    test "handles complexity_analysis task", %{state: state} do
      task = %{
        id: "complexity_1",
        type: :complexity_analysis,
        priority: :medium,
        payload: %{
          module_path: "lib/complex_module.ex",
          metrics: [:cyclomatic, :cognitive, :halstead]
        }
      }

      context = %{}

      assert {:ok, result, _new_state} = AnalysisAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :complexity_metrics)
      assert Map.has_key?(result.complexity_metrics, :cyclomatic)
    end

    test "returns error for unsupported task type", %{state: state} do
      task = %{
        id: "unknown_1",
        type: :unknown_analysis,
        payload: %{}
      }

      assert {:error, {:unsupported_task_type, :unknown_analysis}, ^state} =
               AnalysisAgent.handle_task(task, %{}, state)
    end
  end

  describe "get_capabilities/1" do
    test "returns analysis capabilities" do
      {:ok, state} = AnalysisAgent.init(%{})
      capabilities = AnalysisAgent.get_capabilities(state)

      assert :code_analysis in capabilities
      assert :security_analysis in capabilities
      assert :complexity_analysis in capabilities
      assert :pattern_detection in capabilities
      assert :style_checking in capabilities
    end
  end

  describe "handle_message/3" do
    setup do
      {:ok, state} = AnalysisAgent.init(%{})
      %{state: state}
    end

    test "handles analysis_request message", %{state: state} do
      message = {:analysis_request, "lib/test.ex", [:semantic]}
      from = self()

      assert {:ok, new_state} = AnalysisAgent.handle_message(message, from, state)

      # Should receive response
      assert_receive {:analysis_result, _result}, 1000
    end

    test "handles cache_query message", %{state: state} do
      # First add something to cache
      state = %{state | analysis_cache: %{"lib/test.ex" => %{result: "cached"}}}

      message = {:cache_query, "lib/test.ex"}
      from = self()

      assert {:ok, ^state} = AnalysisAgent.handle_message(message, from, state)
      assert_receive {:cache_result, %{result: "cached"}}, 1000
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status" do
      {:ok, state} = AnalysisAgent.init(%{})
      status = AnalysisAgent.get_status(state)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :metrics)
      assert Map.has_key?(status, :capabilities)
      assert Map.has_key?(status, :health)
      assert status.capabilities == AnalysisAgent.get_capabilities(state)
    end
  end

  describe "integration with Agent base" do
    @tag :integration
    test "can be started through Agent supervisor" do
      config = %{
        name: "test_analysis_integration",
        engines: [:semantic, :security]
      }

      # This will fail until AnalysisAgent is implemented
      assert {:ok, pid} =
               Agent.start_link(
                 agent_type: :analysis,
                 agent_id: "test_analysis_1",
                 config: config,
                 registry: RubberDuck.Agents.Registry
               )

      assert Process.alive?(pid)

      # Test task assignment
      task = %{
        id: "int_test_1",
        type: :analyze_code,
        payload: %{
          file_path: "lib/test.ex",
          analysis_types: [:semantic]
        }
      }

      assert {:ok, result} = Agent.assign_task(pid, task)
      assert result.task_id == task.id

      # Cleanup
      Agent.stop(pid)
    end
  end
end
