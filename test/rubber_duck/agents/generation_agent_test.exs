defmodule RubberDuck.Agents.GenerationAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.GenerationAgent
  alias RubberDuck.Agents.Agent

  describe "init/1" do
    test "initializes with default configuration" do
      config = %{
        name: "test_generation_agent",
        llm_provider: :openai,
        model: "gpt-4"
      }

      assert {:ok, state} = GenerationAgent.init(config)
      assert state.config == config
      assert Map.has_key?(state, :generation_cache)
      assert Map.has_key?(state, :metrics)
      assert Map.has_key?(state, :user_preferences)
    end
  end

  describe "handle_task/3" do
    setup do
      {:ok, state} = GenerationAgent.init(%{})
      %{state: state}
    end

    test "handles generate_code task", %{state: state} do
      task = %{
        id: "gen_1",
        type: :generate_code,
        priority: :high,
        payload: %{
          prompt: "Create a GenServer that manages a counter",
          language: :elixir,
          context_files: ["lib/example.ex"]
        }
      }

      context = %{user_preferences: %{style: :verbose}, memory: %{}}

      assert {:ok, result, new_state} = GenerationAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :generated_code)
      assert Map.has_key?(result, :explanation)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :imports_detected)
      assert new_state.metrics.tasks_completed == 1
    end

    test "handles refactor_code task", %{state: state} do
      task = %{
        id: "refactor_1",
        type: :refactor_code,
        priority: :medium,
        payload: %{
          code: "def add(a, b), do: a + b",
          refactoring_type: :improve_readability,
          preserve_behavior: true
        }
      }

      context = %{}

      assert {:ok, result, new_state} = GenerationAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :refactored_code)
      assert Map.has_key?(result, :changes_made)
      assert result.behavior_preserved == true
    end

    test "handles fix_code task", %{state: state} do
      task = %{
        id: "fix_1",
        type: :fix_code,
        priority: :critical,
        payload: %{
          code: "def broken_function(x) do\n  x + \nend",
          error_message: "syntax error before: end",
          file_path: "lib/broken.ex"
        }
      }

      context = %{}

      assert {:ok, result, _new_state} = GenerationAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :fixed_code)
      assert Map.has_key?(result, :fix_explanation)
      assert result.syntax_valid == true
    end

    test "handles complete_code task", %{state: state} do
      task = %{
        id: "complete_1",
        type: :complete_code,
        priority: :medium,
        payload: %{
          prefix: "defmodule Calculator do\n  def add(a, b) do\n    ",
          suffix: "\n  end\nend",
          cursor_position: {3, 5}
        }
      }

      context = %{}

      assert {:ok, result, _new_state} = GenerationAgent.handle_task(task, context, state)
      assert result.task_id == task.id
      assert Map.has_key?(result, :completions)
      assert is_list(result.completions)
      assert length(result.completions) > 0

      first_completion = hd(result.completions)
      assert Map.has_key?(first_completion, :text)
      assert Map.has_key?(first_completion, :score)
    end

    test "returns error for unsupported task type", %{state: state} do
      task = %{
        id: "unknown_1",
        type: :unknown_generation,
        payload: %{}
      }

      assert {:error, {:unsupported_task_type, :unknown_generation}, ^state} =
               GenerationAgent.handle_task(task, %{}, state)
    end
  end

  describe "get_capabilities/1" do
    test "returns generation capabilities" do
      {:ok, state} = GenerationAgent.init(%{})
      capabilities = GenerationAgent.get_capabilities(state)

      assert :code_generation in capabilities
      assert :code_refactoring in capabilities
      assert :code_fixing in capabilities
      assert :code_completion in capabilities
      assert :documentation_generation in capabilities
    end
  end

  describe "handle_message/3" do
    setup do
      {:ok, state} = GenerationAgent.init(%{})
      %{state: state}
    end

    test "handles generation_request message", %{state: state} do
      message = {:generation_request, "Create a hello world function", :elixir}
      from = self()

      assert {:ok, new_state} = GenerationAgent.handle_message(message, from, state)

      # Should receive response
      assert_receive {:generation_result, _result}, 2000
    end

    test "handles preference_update message", %{state: state} do
      message = {:preference_update, %{code_style: :concise, comments: :minimal}}
      from = self()

      assert {:ok, new_state} = GenerationAgent.handle_message(message, from, state)
      assert new_state.user_preferences.code_style == :concise
      assert new_state.user_preferences.comments == :minimal
    end
  end

  describe "get_status/1" do
    test "returns comprehensive status" do
      {:ok, state} = GenerationAgent.init(%{})
      status = GenerationAgent.get_status(state)

      assert Map.has_key?(status, :status)
      assert Map.has_key?(status, :metrics)
      assert Map.has_key?(status, :capabilities)
      assert Map.has_key?(status, :health)
      assert Map.has_key?(status, :llm_status)
      assert status.capabilities == GenerationAgent.get_capabilities(state)
    end
  end

  describe "code validation" do
    setup do
      {:ok, state} = GenerationAgent.init(%{})
      %{state: state}
    end

    test "validates generated Elixir code syntax", %{state: state} do
      task = %{
        id: "validate_1",
        type: :generate_code,
        payload: %{
          prompt: "Simple addition function",
          language: :elixir,
          validate_syntax: true
        }
      }

      assert {:ok, result, _} = GenerationAgent.handle_task(task, %{}, state)
      assert result.syntax_valid == true
    end
  end

  describe "integration with Agent base" do
    @tag :integration
    test "can be started through Agent supervisor" do
      config = %{
        name: "test_generation_integration",
        llm_provider: :mock,
        model: "mock-model"
      }

      # This will fail until GenerationAgent is implemented
      assert {:ok, pid} =
               Agent.start_link(
                 agent_type: :generation,
                 agent_id: "test_gen_1",
                 config: config,
                 registry: RubberDuck.Agents.Registry
               )

      assert Process.alive?(pid)

      # Test task assignment
      task = %{
        id: "int_test_1",
        type: :generate_code,
        payload: %{
          prompt: "Hello world function",
          language: :elixir
        }
      }

      assert {:ok, result} = Agent.assign_task(pid, task)
      assert result.task_id == task.id

      # Cleanup
      Agent.stop(pid)
    end
  end
end
