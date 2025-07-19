defmodule RubberDuck.MCP.Server.Tools.WorkflowExecutorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Server.Tools.WorkflowExecutor
  alias RubberDuck.MCP.Server.State
  alias Hermes.Server.Frame

  @moduletag :mcp_server

  describe "schema validation" do
    test "validates required fields" do
      frame = Frame.new() |> Frame.assign(:server_state, %State{})

      # Missing workflow_name
      params = %{params: %{}}
      assert {:error, _} = WorkflowExecutor.execute(params, frame)

      # Valid params
      params = %{
        workflow_name: "test_workflow",
        params: %{},
        async: false,
        timeout: 5000,
        stream_progress: false
      }

      assert {:ok, _, _} = WorkflowExecutor.execute(params, frame)
    end

    test "uses default values" do
      frame = Frame.new() |> Frame.assign(:server_state, %State{})

      params = %{
        workflow_name: "test_workflow",
        params: %{}
      }

      # Should use defaults for async, timeout, and stream_progress
      assert {:ok, result, _} = WorkflowExecutor.execute(params, frame)
      assert result["status"] == "completed"
    end
  end

  describe "synchronous execution" do
    setup do
      frame = Frame.new() |> Frame.assign(:server_state, %State{})
      {:ok, frame: frame}
    end

    test "executes known workflow successfully", %{frame: frame} do
      params = %{
        workflow_name: "test_workflow",
        params: %{input: "test"},
        async: false,
        timeout: 5000,
        stream_progress: false
      }

      assert {:ok, result, updated_frame} = WorkflowExecutor.execute(params, frame)

      assert result["status"] == "completed"
      assert result["result"]["output"] == "Workflow completed successfully"
      assert result["result"]["metrics"]["steps_executed"] == 3

      # Verify state was updated
      state = updated_frame.assigns[:server_state]
      assert state.request_count == 1
    end

    test "returns error for unknown workflow", %{frame: frame} do
      params = %{
        workflow_name: "unknown_workflow",
        params: %{},
        async: false,
        timeout: 5000,
        stream_progress: false
      }

      assert {:error, error} = WorkflowExecutor.execute(params, frame)
      assert error["code"] == "workflow_not_found"
      assert error["message"] =~ "unknown_workflow"
    end
  end

  describe "asynchronous execution" do
    setup do
      frame = Frame.new() |> Frame.assign(:server_state, %State{})
      {:ok, frame: frame}
    end

    test "returns immediately with execution ID", %{frame: frame} do
      params = %{
        workflow_name: "test_workflow",
        params: %{},
        async: true,
        timeout: 5000,
        stream_progress: false
      }

      assert {:ok, result, _} = WorkflowExecutor.execute(params, frame)

      assert result["status"] == "running"
      assert String.starts_with?(result["execution_id"], "exec_")
      assert result["message"] == "Workflow started asynchronously"
    end
  end

  describe "streaming execution" do
    setup do
      frame = Frame.new() |> Frame.assign(:server_state, %State{})
      {:ok, frame: frame}
    end

    test "executes with progress streaming", %{frame: frame} do
      params = %{
        workflow_name: "test_workflow",
        params: %{},
        async: false,
        timeout: 5000,
        stream_progress: true
      }

      assert {:ok, result, _} = WorkflowExecutor.execute(params, frame)

      assert result["isPartial"] == true
      assert String.starts_with?(result["progressToken"], "prog_")
      assert result["content"]["result"]["streamed"] == true
    end

    test "does not stream for async workflows", %{frame: frame} do
      params = %{
        workflow_name: "test_workflow",
        params: %{},
        async: true,
        timeout: 5000,
        stream_progress: true
      }

      assert {:ok, result, _} = WorkflowExecutor.execute(params, frame)

      # Should execute async without streaming
      assert result["status"] == "running"
      refute Map.has_key?(result, "isPartial")
      refute Map.has_key?(result, "progressToken")
    end
  end

  describe "tool metadata" do
    test "has proper description" do
      assert WorkflowExecutor.__description__() =~ "workflows"
    end

    test "defines input schema" do
      schema = WorkflowExecutor.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "workflow_name")
      assert Map.has_key?(schema["properties"], "params")
      assert Map.has_key?(schema["properties"], "async")
      assert Map.has_key?(schema["properties"], "timeout")
      assert Map.has_key?(schema["properties"], "stream_progress")

      assert "workflow_name" in schema["required"]
    end
  end
end
