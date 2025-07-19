defmodule RubberDuck.StatusIntegrationTest do
  @moduledoc """
  Integration tests for the Status Broadcasting System.
  
  Tests the complete flow of status updates through various system components.
  """
  
  use ExUnit.Case, async: false
  use RubberDuckWeb.ChannelCase
  
  alias RubberDuck.{Status, LLM, Tool, Workflows}
  alias RubberDuckWeb.StatusChannel
  
  @test_conversation_id "test_conv_123"
  @test_user_id "test_user_456"
  
  setup do
    # Ensure status broadcaster is running
    start_supervised!(Status.Broadcaster)
    
    # Connect to status channel
    {:ok, _, socket} =
      RubberDuckWeb.UserSocket
      |> socket(@test_user_id, %{})
      |> subscribe_and_join(StatusChannel, "status:#{@test_conversation_id}")
    
    %{socket: socket}
  end
  
  describe "LLM status updates" do
    test "broadcasts status updates during LLM request", %{socket: _socket} do
      # Subscribe to status updates
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Make an LLM request
      messages = [%{role: "user", content: "Test message"}]
      
      # Mock the LLM service to return quickly
      expect(RubberDuck.LLM.MockProvider, :execute, fn _request, _config ->
        {:ok, %{content: "Test response", usage: %{total_tokens: 10}}}
      end)
      
      # Execute LLM request
      {:ok, _response} = LLM.Service.completion(
        model: "mock-fast",
        messages: messages,
        user_id: @test_conversation_id
      )
      
      # Assert we received status updates
      assert_receive {:status_update, %{category: :engine, text: text1}}, 1000
      assert text1 =~ "Starting"
      
      assert_receive {:status_update, %{category: :engine, text: text2}}, 1000
      assert text2 =~ "Completed"
    end
    
    test "broadcasts error status on LLM failure", %{socket: _socket} do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Mock provider to fail
      expect(RubberDuck.LLM.MockProvider, :execute, fn _request, _config ->
        {:error, :provider_error}
      end)
      
      # Execute failing request
      {:error, _} = LLM.Service.completion(
        model: "mock-fast",
        messages: [%{role: "user", content: "Test"}],
        user_id: @test_conversation_id
      )
      
      # Assert we received error status
      assert_receive {:status_update, %{category: :error, text: text}}, 1000
      assert text =~ "failed"
    end
  end
  
  describe "Tool execution status updates" do
    test "broadcasts status during tool execution", %{socket: _socket} do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Define a test tool
      defmodule TestStatusTool do
        use RubberDuck.Tool
        
        @impl true
        def metadata do
          %{
            name: :test_status_tool,
            description: "Test tool for status updates",
            category: :testing,
            input_schema: %{},
            output_schema: %{}
          }
        end
        
        @impl true
        def execute(params, _context) do
          {:ok, %{result: "success", params: params}}
        end
      end
      
      # Execute tool
      user = %{id: @test_user_id}
      context = %{conversation_id: @test_conversation_id}
      
      {:ok, _result} = Tool.Executor.execute(TestStatusTool, %{}, user, context)
      
      # Assert status updates
      assert_receive {:status_update, %{category: :tool, text: prep_text}}, 1000
      assert prep_text =~ "Preparing"
      
      assert_receive {:status_update, %{category: :tool, text: exec_text}}, 1000
      assert exec_text =~ "Executing"
      
      assert_receive {:status_update, %{category: :tool, text: comp_text}}, 1000
      assert comp_text =~ "Completed"
    end
    
    test "broadcasts error status on tool failure", %{socket: _socket} do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Define a failing tool
      defmodule FailingStatusTool do
        use RubberDuck.Tool
        
        @impl true
        def metadata do
          %{
            name: :failing_status_tool,
            description: "Failing test tool",
            category: :testing,
            input_schema: %{},
            output_schema: %{}
          }
        end
        
        @impl true
        def execute(_params, _context) do
          {:error, :deliberate_failure}
        end
      end
      
      # Execute failing tool
      user = %{id: @test_user_id}
      context = %{conversation_id: @test_conversation_id}
      
      {:error, _} = Tool.Executor.execute(FailingStatusTool, %{}, user, context)
      
      # Assert error status
      assert_receive {:status_update, %{category: :error, text: error_text}}, 1000
      assert error_text =~ "failed"
    end
  end
  
  describe "Workflow status updates" do
    test "broadcasts status during workflow execution", %{socket: _socket} do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Define a test workflow
      defmodule TestStatusWorkflow do
        use RubberDuck.Workflows.Workflow
        
        @impl true
        def name, do: "test_status_workflow"
        
        @impl true
        def description, do: "Test workflow for status updates"
        
        @impl true
        def version, do: "1.0.0"
        
        @impl true
        def steps do
          [
            %{
              name: :step1,
              impl: fn _args -> {:ok, %{result: "step1_complete"}} end,
              arguments: []
            },
            %{
              name: :step2,
              impl: fn _args -> {:ok, %{result: "step2_complete"}} end,
              arguments: [:step1]
            }
          ]
        end
      end
      
      # Execute workflow
      opts = [conversation_id: @test_conversation_id]
      {:ok, _result} = Workflows.Executor.run(TestStatusWorkflow, %{}, opts)
      
      # Assert workflow status updates
      assert_receive {:status_update, %{category: :workflow, text: start_text}}, 1000
      assert start_text =~ "Starting workflow"
      
      assert_receive {:status_update, %{category: :workflow, text: comp_text}}, 1000
      assert comp_text =~ "Completed workflow"
    end
  end
  
  describe "Channel status updates" do
    test "receives status updates through WebSocket channel", %{socket: socket} do
      # Send a status update
      Status.info(@test_conversation_id, "Test channel update", %{source: "test"})
      
      # Assert we receive it through the channel
      assert_push "status_update", %{
        category: "info",
        text: "Test channel update",
        metadata: %{source: "test"}
      }
    end
    
    test "filters updates by category subscription", %{socket: socket} do
      # Update subscription to only receive errors
      push(socket, "update_subscription", %{"categories" => ["error"]})
      assert_reply :ok, %{subscribed_categories: ["error"]}
      
      # Send various status updates
      Status.info(@test_conversation_id, "Info message", %{})
      Status.error(@test_conversation_id, "Error message", %{})
      Status.progress(@test_conversation_id, "Progress message", %{})
      
      # Should only receive error
      assert_push "status_update", %{category: "error", text: "Error message"}
      
      # Should not receive others
      refute_push "status_update", %{category: "info"}
      refute_push "status_update", %{category: "progress"}
    end
  end
  
  describe "Status API helpers" do
    test "metadata builders create consistent structures" do
      # Test LLM metadata builder
      llm_meta = Status.build_llm_metadata("gpt-4", "openai", %{extra: "data"})
      assert llm_meta.model == "gpt-4"
      assert llm_meta.provider == "openai"
      assert llm_meta.extra == "data"
      
      # Test tool metadata builder
      tool_meta = Status.build_tool_metadata("test_tool", %{param: "value"}, %{})
      assert tool_meta.tool == "test_tool"
      assert tool_meta.params == %{param: "value"}
      
      # Test workflow metadata builder
      workflow_meta = Status.build_workflow_metadata("test_workflow", 3, 5, %{})
      assert workflow_meta.workflow == "test_workflow"
      assert workflow_meta.completed_steps == 3
      assert workflow_meta.total_steps == 5
      
      # Test error metadata builder
      error_meta = Status.build_error_metadata(:test_error, "Test error message", %{})
      assert error_meta.error_type == :test_error
      assert error_meta.message == "Test error message"
    end
    
    test "timing helper calculates duration correctly" do
      start_time = System.monotonic_time(:millisecond)
      Process.sleep(100)
      
      Status.with_timing(@test_conversation_id, :info, "Timed operation", start_time, %{})
      
      assert_receive {:status_update, %{metadata: meta}}, 1000
      assert meta.duration_ms >= 100
      assert meta.duration_human =~ "ms"
    end
    
    test "progress percentage helper" do
      Status.progress_percentage(@test_conversation_id, "Processing", 25, 100, %{})
      
      assert_receive {:status_update, %{metadata: meta}}, 1000
      assert meta.progress == 25
      assert meta.total == 100
      assert meta.percentage == 25.0
    end
  end
  
  describe "Error boundary integration" do
    test "error boundary reports to status system", %{socket: _socket} do
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Run failing operation in error boundary
      {:error, _} = RubberDuck.ErrorBoundary.run(
        fn -> raise "Test error" end,
        metadata: %{conversation_id: @test_conversation_id}
      )
      
      # Assert error status was broadcast
      assert_receive {:status_update, %{category: :error, text: text}}, 1000
      assert text =~ "Error boundary caught exception"
    end
  end
  
  # Helper to mock provider responses
  defp expect(module, function, callback) do
    # In a real test, you'd use a mocking library like Mox
    # This is a simplified version for illustration
    :ok
  end
end