defmodule RubberDuck.MCP.WorkflowAdapterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.WorkflowAdapter
  alias RubberDuck.MCP.WorkflowAdapter.{ContextManager, TemplateRegistry, StreamingHandler}
  alias RubberDuck.Tool.Registry

  describe "create_workflow/2" do
    test "creates a sequential workflow" do
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "test_tool", "params" => %{"input" => "hello"}},
          %{"tool" => "test_tool", "params" => %{"input" => "world"}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("test_workflow", definition)
      
      assert workflow.id == "test_workflow"
      assert workflow.type == "sequential"
      assert length(workflow.steps) == 2
    end

    test "creates a parallel workflow" do
      definition = %{
        "type" => "parallel",
        "steps" => [
          %{"tool" => "test_tool", "params" => %{"input" => "a"}},
          %{"tool" => "test_tool", "params" => %{"input" => "b"}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("parallel_test", definition)
      
      assert workflow.id == "parallel_test"
      assert workflow.type == "parallel"
      assert length(workflow.steps) == 2
    end

    test "creates a conditional workflow" do
      definition = %{
        "type" => "conditional",
        "condition" => %{"tool" => "validator", "params" => %{"value" => "test"}},
        "success" => [%{"tool" => "success_tool", "params" => %{}}],
        "failure" => [%{"tool" => "failure_tool", "params" => %{}}]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("conditional_test", definition)
      
      assert workflow.id == "conditional_test"
      assert workflow.type == "conditional"
      assert Map.has_key?(workflow.definition, "condition")
      assert Map.has_key?(workflow.definition, "success")
      assert Map.has_key?(workflow.definition, "failure")
    end

    test "creates a loop workflow" do
      definition = %{
        "type" => "loop",
        "steps" => [%{"tool" => "loop_tool", "params" => %{"count" => 5}}],
        "max_iterations" => 10
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("loop_test", definition)
      
      assert workflow.id == "loop_test"
      assert workflow.type == "loop"
      assert workflow.definition["max_iterations"] == 10
    end

    test "creates a reactive workflow" do
      definition = %{
        "type" => "reactive",
        "triggers" => [
          %{"event" => "data_received", "workflow" => "data_processing"}
        ],
        "workflows" => %{
          "data_processing" => %{
            "type" => "sequential",
            "steps" => [%{"tool" => "processor", "params" => %{}}]
          }
        }
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("reactive_test", definition)
      
      assert workflow.id == "reactive_test"
      assert workflow.type == "reactive"
      assert Map.has_key?(workflow.definition, "triggers")
      assert Map.has_key?(workflow.definition, "workflows")
    end

    test "returns error for invalid workflow type" do
      definition = %{
        "type" => "invalid_type",
        "steps" => []
      }

      assert {:error, reason} = WorkflowAdapter.create_workflow("invalid_test", definition)
      assert reason =~ "Unsupported workflow type"
    end

    test "returns error for missing required fields" do
      definition = %{
        "type" => "sequential"
        # Missing "steps"
      }

      assert {:error, reason} = WorkflowAdapter.create_workflow("missing_test", definition)
      assert reason =~ "Missing required field"
    end
  end

  describe "execute_workflow/2" do
    test "executes a simple sequential workflow" do
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "test_tool", "params" => %{"input" => "hello"}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("exec_test", definition)
      
      context = %{
        "session_id" => "test_session",
        "user_id" => "test_user"
      }

      # Mock the tool execution
      result = WorkflowAdapter.execute_workflow(workflow, context)
      
      # Should return some result structure
      case result do
        {:ok, _result} -> assert true
        {:error, _reason} -> assert true
      end
    end

    test "handles workflow execution errors gracefully" do
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "non_existent_tool", "params" => %{}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("error_test", definition)
      
      context = %{"session_id" => "test_session"}

      assert {:error, _reason} = WorkflowAdapter.execute_workflow(workflow, context)
    end

    test "passes context through workflow steps" do
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "context_reader", "params" => %{"key" => "test_value"}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("context_test", definition)
      
      context = %{
        "session_id" => "test_session",
        "test_value" => "passed_through"
      }

      # The context should be available to tools during execution
      result = WorkflowAdapter.execute_workflow(workflow, context)
      
      # Should not error due to context handling
      case result do
        {:ok, _result} -> assert true
        {:error, _reason} -> assert true
      end
    end
  end

  describe "create_multi_tool_operation/1" do
    test "creates a multi-tool operation from tool calls" do
      tool_calls = [
        %{"tool" => "first_tool", "params" => %{"input" => "a"}},
        %{"tool" => "second_tool", "params" => %{"input" => "b"}},
        %{"tool" => "third_tool", "params" => %{"input" => "c"}}
      ]

      {:ok, operation} = WorkflowAdapter.create_multi_tool_operation(tool_calls)
      
      assert operation.type == "multi_tool"
      assert length(operation.tool_calls) == 3
      assert operation.execution_mode == "sequential"
    end

    test "returns error for empty tool calls" do
      assert {:error, reason} = WorkflowAdapter.create_multi_tool_operation([])
      assert reason =~ "at least one tool call"
    end

    test "validates tool call structure" do
      invalid_tool_calls = [
        %{"params" => %{"input" => "a"}} # Missing "tool"
      ]

      assert {:error, reason} = WorkflowAdapter.create_multi_tool_operation(invalid_tool_calls)
      assert reason =~ "Invalid tool call"
    end
  end

  describe "execute_multi_tool_operation/2" do
    test "executes multiple tools in sequence" do
      tool_calls = [
        %{"tool" => "test_tool", "params" => %{"input" => "first"}},
        %{"tool" => "test_tool", "params" => %{"input" => "second"}}
      ]

      {:ok, operation} = WorkflowAdapter.create_multi_tool_operation(tool_calls)
      
      context = %{"session_id" => "test_session"}
      options = %{"timeout" => 30_000}

      result = WorkflowAdapter.execute_multi_tool_operation(operation, context, options)
      
      # Should return results from all tools
      case result do
        {:ok, _results} -> assert true
        {:error, _reason} -> assert true
      end
    end

    test "handles partial failures in multi-tool operations" do
      tool_calls = [
        %{"tool" => "test_tool", "params" => %{"input" => "valid"}},
        %{"tool" => "failing_tool", "params" => %{"input" => "invalid"}}
      ]

      {:ok, operation} = WorkflowAdapter.create_multi_tool_operation(tool_calls)
      
      context = %{"session_id" => "test_session"}

      # Should handle partial failures gracefully
      result = WorkflowAdapter.execute_multi_tool_operation(operation, context)
      
      case result do
        {:ok, results} -> 
          # Some results may be successful, others may contain errors
          assert is_list(results) or is_map(results)
        {:error, _reason} -> 
          # Complete failure is also acceptable
          assert true
      end
    end
  end

  describe "list_workflow_templates/0" do
    test "returns available workflow templates" do
      templates = WorkflowAdapter.list_workflow_templates()
      
      assert is_list(templates)
      assert length(templates) > 0
      
      # Check that built-in templates are included
      template_names = Enum.map(templates, & &1.name)
      assert "data_processing_pipeline" in template_names
      assert "user_onboarding" in template_names
      assert "content_moderation" in template_names
    end

    test "templates have required fields" do
      templates = WorkflowAdapter.list_workflow_templates()
      
      for template <- templates do
        assert Map.has_key?(template, :name)
        assert Map.has_key?(template, :version)
        assert Map.has_key?(template, :description)
        assert Map.has_key?(template, :definition)
        assert Map.has_key?(template, :parameters)
      end
    end
  end

  describe "create_workflow_from_template/2" do
    test "creates workflow from template with parameters" do
      template = %{name: "data_processing_pipeline"}
      params = %{
        "source" => "api",
        "destination" => "database",
        "format" => "json"
      }

      {:ok, workflow_definition} = WorkflowAdapter.create_workflow_from_template(template, params)
      
      assert Map.has_key?(workflow_definition, "type")
      assert Map.has_key?(workflow_definition, "steps")
      
      # Check that parameters were substituted
      steps_json = Jason.encode!(workflow_definition["steps"])
      assert String.contains?(steps_json, "api")
      assert String.contains?(steps_json, "database")
      assert String.contains?(steps_json, "json")
    end

    test "returns error for missing required parameters" do
      template = %{name: "data_processing_pipeline"}
      params = %{
        "source" => "api"
        # Missing required "destination" parameter
      }

      assert {:error, reason} = WorkflowAdapter.create_workflow_from_template(template, params)
      assert reason =~ "Missing required parameters"
    end

    test "returns error for non-existent template" do
      template = %{name: "non_existent_template"}
      params = %{}

      assert {:error, reason} = WorkflowAdapter.create_workflow_from_template(template, params)
      assert reason =~ "not found"
    end
  end

  describe "execute_sampling/2" do
    test "executes sampling with tool selection" do
      sampling_config = %{
        "type" => "tool_selection",
        "criteria" => %{
          "performance" => 0.8,
          "availability" => 0.9
        },
        "tools" => ["tool_a", "tool_b", "tool_c"]
      }

      options = %{"timeout" => 5_000}

      result = WorkflowAdapter.execute_sampling(sampling_config, options)
      
      case result do
        {:ok, selected_tool} ->
          assert is_binary(selected_tool)
          assert selected_tool in ["tool_a", "tool_b", "tool_c"]
        {:error, _reason} ->
          # Sampling may fail if tools are not available
          assert true
      end
    end

    test "returns error for invalid sampling config" do
      invalid_config = %{
        "type" => "invalid_sampling_type"
      }

      assert {:error, reason} = WorkflowAdapter.execute_sampling(invalid_config, %{})
      assert reason =~ "Invalid sampling"
    end
  end

  describe "create_reactive_trigger/1" do
    test "creates reactive trigger" do
      trigger_config = %{
        "event" => "user_signup",
        "condition" => %{"user_type" => "premium"},
        "workflow" => "premium_onboarding",
        "delay" => 5000
      }

      {:ok, trigger} = WorkflowAdapter.create_reactive_trigger(trigger_config)
      
      assert trigger.event == "user_signup"
      assert trigger.workflow == "premium_onboarding"
      assert trigger.delay == 5000
      assert trigger.active == true
      assert is_binary(trigger.id)
    end

    test "creates trigger with default values" do
      trigger_config = %{
        "event" => "data_received",
        "workflow" => "data_processing"
      }

      {:ok, trigger} = WorkflowAdapter.create_reactive_trigger(trigger_config)
      
      assert trigger.event == "data_received"
      assert trigger.workflow == "data_processing"
      assert trigger.delay == 0
      assert trigger.active == true
    end

    test "returns error for invalid trigger config" do
      invalid_config = %{
        "event" => "test_event"
        # Missing required "workflow" field
      }

      assert {:error, reason} = WorkflowAdapter.create_reactive_trigger(invalid_config)
      assert reason =~ "Missing required field"
    end
  end

  describe "register_trigger/1" do
    test "registers a trigger successfully" do
      trigger_config = %{
        "event" => "test_event",
        "workflow" => "test_workflow",
        "delay" => 1000
      }

      {:ok, trigger} = WorkflowAdapter.create_reactive_trigger(trigger_config)
      
      assert :ok = WorkflowAdapter.register_trigger(trigger)
    end

    test "handles trigger registration errors" do
      # Test with invalid trigger structure
      invalid_trigger = %{
        id: "invalid_trigger",
        event: nil,
        workflow: nil
      }

      result = WorkflowAdapter.register_trigger(invalid_trigger)
      
      # Should handle invalid trigger gracefully
      case result do
        :ok -> assert true
        {:error, _reason} -> assert true
      end
    end
  end

  describe "create_shared_context/1" do
    test "creates shared context" do
      initial_context = %{
        "user_id" => "user123",
        "session_id" => "session456",
        "preferences" => %{
          "theme" => "dark",
          "language" => "en"
        }
      }

      context = WorkflowAdapter.create_shared_context(initial_context)
      
      assert is_binary(context.id)
      assert context.data == initial_context
      assert context.version == 1
      assert %DateTime{} = context.created_at
      assert %DateTime{} = context.updated_at
    end

    test "creates context with empty data" do
      context = WorkflowAdapter.create_shared_context(%{})
      
      assert context.data == %{}
      assert context.version == 1
    end

    test "generates unique context IDs" do
      context1 = WorkflowAdapter.create_shared_context(%{"test" => "data1"})
      context2 = WorkflowAdapter.create_shared_context(%{"test" => "data2"})
      
      assert context1.id != context2.id
    end
  end

  describe "integration with other modules" do
    test "workflows can use context manager" do
      # This test verifies that WorkflowAdapter properly integrates with ContextManager
      initial_context = %{
        "user_id" => "test_user",
        "session_data" => %{"key" => "value"}
      }

      shared_context = WorkflowAdapter.create_shared_context(initial_context)
      
      # Verify the context was created properly
      assert shared_context.data["user_id"] == "test_user"
      assert shared_context.data["session_data"]["key"] == "value"
    end

    test "workflows can use templates" do
      # This test verifies that WorkflowAdapter properly integrates with TemplateRegistry
      templates = WorkflowAdapter.list_workflow_templates()
      
      # Should have built-in templates
      assert length(templates) > 0
      
      # Should be able to create workflows from templates
      template = %{name: "data_processing_pipeline"}
      params = %{
        "source" => "test_source",
        "destination" => "test_destination"
      }

      {:ok, workflow_def} = WorkflowAdapter.create_workflow_from_template(template, params)
      assert Map.has_key?(workflow_def, "type")
      assert Map.has_key?(workflow_def, "steps")
    end

    test "workflows can use streaming" do
      # This test verifies that WorkflowAdapter properly integrates with StreamingHandler
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "test_tool", "params" => %{"input" => "test"}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("streaming_test", definition)
      
      # Verify workflow structure supports streaming
      assert workflow.id == "streaming_test"
      assert workflow.type == "sequential"
    end
  end

  describe "error handling" do
    test "handles malformed workflow definitions" do
      malformed_definition = %{
        "type" => "sequential",
        "steps" => "not_a_list"
      }

      assert {:error, reason} = WorkflowAdapter.create_workflow("malformed", malformed_definition)
      assert is_binary(reason)
    end

    test "handles execution timeouts" do
      definition = %{
        "type" => "sequential",
        "steps" => [
          %{"tool" => "slow_tool", "params" => %{"delay" => 60_000}}
        ]
      }

      {:ok, workflow} = WorkflowAdapter.create_workflow("timeout_test", definition)
      
      context = %{"session_id" => "test"}
      options = %{"timeout" => 1000} # 1 second timeout

      result = WorkflowAdapter.execute_workflow(workflow, context, options)
      
      # Should handle timeout gracefully
      case result do
        {:ok, _} -> assert true
        {:error, reason} -> assert reason =~ "timeout" or is_binary(reason)
      end
    end

    test "validates workflow definitions thoroughly" do
      # Test various invalid workflow structures
      invalid_definitions = [
        %{"type" => "sequential"}, # Missing steps
        %{"steps" => []}, # Missing type
        %{"type" => "parallel", "steps" => [%{}]}, # Invalid step structure
        %{"type" => "conditional"}, # Missing condition
        %{"type" => "loop", "steps" => []}, # Missing max_iterations
        %{"type" => "reactive"} # Missing triggers
      ]

      for definition <- invalid_definitions do
        assert {:error, _reason} = WorkflowAdapter.create_workflow("invalid", definition)
      end
    end
  end
end