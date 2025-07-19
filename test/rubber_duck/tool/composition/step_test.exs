defmodule RubberDuck.Tool.Composition.StepTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Composition.Step

  # Mock tool for testing
  defmodule MockTool do
    def execute(params, _context) do
      case params do
        %{action: "success"} -> {:ok, %{result: "success", data: params}}
        %{action: "error"} -> {:error, "tool_error"}
        %{action: "exception"} -> raise "tool_exception"
        _ -> {:ok, %{result: "default", data: params}}
      end
    end

    def compensate(_arguments, _result, _context) do
      :ok
    end
  end

  defmodule MockToolWithValidation do
    def execute(params, _context) do
      {:ok, %{result: "validated", data: params}}
    end

    def validate_parameters(params) do
      case params do
        %{valid: true} -> {:ok, params}
        %{valid: false} -> {:error, "validation_failed"}
        _ -> {:ok, params}
      end
    end
  end

  defmodule MockToolWithoutCompensation do
    def execute(params, _context) do
      {:ok, %{result: "no_compensation", data: params}}
    end
  end

  setup do
    # Clear any existing telemetry handlers
    events = [
      [:rubber_duck, :tool, :composition, :step_start],
      [:rubber_duck, :tool, :composition, :step_success],
      [:rubber_duck, :tool, :composition, :step_error],
      [:rubber_duck, :tool, :composition, :step_exception]
    ]

    # Attach test telemetry handler
    handler_id = "step_test_#{inspect(self())}"

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  describe "run/2" do
    test "executes a tool successfully" do
      arguments = %{action: "success", input: "test_input"}

      context = %{
        options: [MockTool, %{base_param: "base_value"}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:ok, result} = Step.run(arguments, context)
      assert result.result == "success"
      assert result.data.action == "success"
      assert result.data.input == "test_input"
      assert result.data.base_param == "base_value"
      assert result.data.context == context

      # Verify telemetry events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_start], %{count: 1}, _}
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_success], %{count: 1, duration: _}, _}
    end

    test "handles tool errors" do
      arguments = %{action: "error"}

      context = %{
        options: [MockTool, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:error, "tool_error"} = Step.run(arguments, context)

      # Verify telemetry events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_start], %{count: 1}, _}
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_error], %{count: 1, duration: _}, _}
    end

    test "handles tool exceptions" do
      arguments = %{action: "exception"}

      context = %{
        options: [MockTool, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:error, {:tool_exception, %RuntimeError{}}} = Step.run(arguments, context)

      # Verify telemetry events
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_start], %{count: 1}, _}
      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_exception], %{count: 1, duration: _}, _}
    end

    test "validates parameters when tool supports validation" do
      arguments = %{valid: true}

      context = %{
        options: [MockToolWithValidation, %{base_param: "base_value"}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:ok, result} = Step.run(arguments, context)
      assert result.result == "validated"
      assert result.data.valid == true
      assert result.data.base_param == "base_value"
    end

    test "handles validation failures" do
      arguments = %{valid: false}

      context = %{
        options: [MockToolWithValidation, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:error, {:validation_failed, "validation_failed"}} = Step.run(arguments, context)
    end

    test "handles missing tool configuration" do
      arguments = %{action: "success"}

      context = %{
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:error, {:tool_exception, %MatchError{}}} = Step.run(arguments, context)
    end

    test "merges input parameters correctly" do
      arguments = %{
        input: %{input_param: "input_value"},
        condition_result: {:ok, "condition_passed"},
        custom_arg: "custom_value"
      }

      context = %{
        options: [MockTool, %{base_param: "base_value"}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:ok, result} = Step.run(arguments, context)
      assert result.data.input.input_param == "input_value"
      assert result.data.condition_result == {:ok, "condition_passed"}
      assert result.data.custom_arg == "custom_value"
      assert result.data.base_param == "base_value"
      assert result.data.context == context
    end
  end

  describe "compensate/3" do
    test "calls tool compensation when available" do
      arguments = %{action: "compensate"}
      result = {:error, "failed"}

      context = %{
        options: [MockTool, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert :ok = Step.compensate(arguments, result, context)
    end

    test "handles missing compensation gracefully" do
      arguments = %{action: "compensate"}
      result = {:error, "failed"}

      context = %{
        options: [MockToolWithoutCompensation, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert :ok = Step.compensate(arguments, result, context)
    end

    test "handles compensation errors" do
      defmodule FailingCompensationTool do
        def execute(_params, _context), do: {:ok, "success"}
        def compensate(_arguments, _result, _context), do: raise("compensation_error")
      end

      arguments = %{action: "compensate"}
      result = {:error, "failed"}

      context = %{
        options: [FailingCompensationTool, %{}],
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert {:error, {:compensation_failed, %RuntimeError{}}} = Step.compensate(arguments, result, context)
    end

    test "handles missing tool configuration in compensation" do
      arguments = %{action: "compensate"}
      result = {:error, "failed"}

      context = %{
        workflow_id: "test_workflow",
        step_name: "test_step"
      }

      assert :ok = Step.compensate(arguments, result, context)
    end
  end

  describe "telemetry integration" do
    test "emits correct telemetry metadata" do
      arguments = %{action: "success"}

      context = %{
        options: [MockTool, %{}],
        workflow_id: "test_workflow_123",
        step_name: "test_step_456"
      }

      Step.run(arguments, context)

      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_start], %{count: 1}, metadata}
      assert metadata.workflow_id == "test_workflow_123"
      assert metadata.step_name == "test_step_456"
      assert metadata.tool_module == MockTool

      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_success], %{count: 1, duration: duration},
                      metadata}

      assert is_integer(duration)
      assert duration > 0
      assert metadata.workflow_id == "test_workflow_123"
      assert metadata.step_name == "test_step_456"
      assert metadata.tool_module == MockTool
    end

    test "handles missing context gracefully in telemetry" do
      arguments = %{action: "success"}

      context = %{
        options: [MockTool, %{}]
      }

      Step.run(arguments, context)

      assert_receive {:telemetry, [:rubber_duck, :tool, :composition, :step_start], %{count: 1}, metadata}
      assert metadata.workflow_id == "unknown"
      assert metadata.step_name == "unknown"
      assert metadata.tool_module == MockTool
    end
  end
end
