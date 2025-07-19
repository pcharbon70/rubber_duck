defmodule RubberDuck.StatusTest do
  @moduledoc """
  Tests for the Status module and its API.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Status
  
  @test_conversation_id "test_conv_789"
  
  setup do
    # Ensure broadcaster is started
    start_supervised!(Status.Broadcaster)
    
    # Subscribe to PubSub for this conversation
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
    
    :ok
  end
  
  describe "update/4" do
    test "sends status update with all categories" do
      categories = [:info, :warning, :error, :progress, :engine, :tool, :workflow]
      
      Enum.each(categories, fn category ->
        Status.update(@test_conversation_id, category, "Test #{category}", %{test: true})
        
        assert_receive {:status_update, update}, 1000
        assert update.category == category
        assert update.text == "Test #{category}"
        assert update.metadata.test == true
        assert update.timestamp
      end)
    end
    
    test "handles nil conversation_id gracefully" do
      # Should not crash when conversation_id is nil
      assert Status.update(nil, :info, "No conversation", %{}) == :ok
      
      # Should still broadcast to general status channel
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:all")
      Status.update(nil, :info, "Broadcast to all", %{})
      
      assert_receive {:status_update, update}, 1000
      assert update.text == "Broadcast to all"
    end
  end
  
  describe "convenience functions" do
    test "info/3 sends info status" do
      Status.info(@test_conversation_id, "Info message", %{source: "test"})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :info
      assert update.text == "Info message"
    end
    
    test "warning/3 sends warning status" do
      Status.warning(@test_conversation_id, "Warning message", %{level: "medium"})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :warning
      assert update.text == "Warning message"
    end
    
    test "error/3 sends error status" do
      Status.error(@test_conversation_id, "Error message", %{code: 500})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :error
      assert update.text == "Error message"
    end
    
    test "progress/3 sends progress status" do
      Status.progress(@test_conversation_id, "In progress", %{step: 1})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :progress
      assert update.text == "In progress"
    end
    
    test "engine/3 sends engine status" do
      Status.engine(@test_conversation_id, "Engine processing", %{engine: "test"})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :engine
      assert update.text == "Engine processing"
    end
    
    test "tool/3 sends tool status" do
      Status.tool(@test_conversation_id, "Tool executing", %{tool: "calculator"})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :tool
      assert update.text == "Tool executing"
    end
    
    test "workflow/3 sends workflow status" do
      Status.workflow(@test_conversation_id, "Workflow running", %{step: "validation"})
      
      assert_receive {:status_update, update}, 1000
      assert update.category == :workflow
      assert update.text == "Workflow running"
    end
  end
  
  describe "metadata builders" do
    test "build_llm_metadata/3 creates proper structure" do
      metadata = Status.build_llm_metadata("gpt-4", "openai", %{temperature: 0.7})
      
      assert metadata.model == "gpt-4"
      assert metadata.provider == "openai"
      assert metadata.temperature == 0.7
      assert metadata.timestamp
    end
    
    test "build_tool_metadata/3 creates proper structure" do
      params = %{input: "test"}
      metadata = Status.build_tool_metadata("test_tool", params, %{version: "1.0"})
      
      assert metadata.tool == "test_tool"
      assert metadata.params == params
      assert metadata.version == "1.0"
      assert metadata.timestamp
    end
    
    test "build_workflow_metadata/4 creates proper structure" do
      metadata = Status.build_workflow_metadata("process_flow", 2, 5, %{stage: "validation"})
      
      assert metadata.workflow == "process_flow"
      assert metadata.completed_steps == 2
      assert metadata.total_steps == 5
      assert metadata.progress_percentage == 40.0
      assert metadata.stage == "validation"
      assert metadata.timestamp
    end
    
    test "build_error_metadata/3 creates proper structure" do
      metadata = Status.build_error_metadata(:validation_error, "Invalid input", %{field: "email"})
      
      assert metadata.error_type == :validation_error
      assert metadata.message == "Invalid input"
      assert metadata.field == "email"
      assert metadata.timestamp
    end
  end
  
  describe "helper functions" do
    test "with_timing/5 includes duration information" do
      start_time = System.monotonic_time(:millisecond)
      Process.sleep(50)
      
      Status.with_timing(@test_conversation_id, :info, "Timed op", start_time, %{op: "test"})
      
      assert_receive {:status_update, update}, 1000
      assert update.metadata.duration_ms >= 50
      assert update.metadata.duration_human
      assert update.metadata.op == "test"
    end
    
    test "progress_percentage/5 calculates percentage" do
      Status.progress_percentage(@test_conversation_id, "Processing items", 30, 100, %{batch: 1})
      
      assert_receive {:status_update, update}, 1000
      assert update.metadata.progress == 30
      assert update.metadata.total == 100
      assert update.metadata.percentage == 30.0
      assert update.metadata.batch == 1
    end
    
    test "bulk_update/2 sends multiple updates" do
      updates = [
        {:info, "First update", %{index: 1}},
        {:progress, "Second update", %{index: 2}},
        {:info, "Third update", %{index: 3}}
      ]
      
      Status.bulk_update(@test_conversation_id, updates)
      
      # Should receive all three updates
      assert_receive {:status_update, %{text: "First update", metadata: %{index: 1}}}, 1000
      assert_receive {:status_update, %{text: "Second update", metadata: %{index: 2}}}, 1000
      assert_receive {:status_update, %{text: "Third update", metadata: %{index: 3}}}, 1000
    end
    
    test "maybe_update/4 conditionally sends updates" do
      # Should send when condition is true
      Status.maybe_update(@test_conversation_id, true, :info, "Conditional true", %{})
      assert_receive {:status_update, %{text: "Conditional true"}}, 1000
      
      # Should not send when condition is false
      Status.maybe_update(@test_conversation_id, false, :info, "Conditional false", %{})
      refute_receive {:status_update, %{text: "Conditional false"}}, 100
      
      # Should not send when condition is nil
      Status.maybe_update(@test_conversation_id, nil, :info, "Conditional nil", %{})
      refute_receive {:status_update, %{text: "Conditional nil"}}, 100
    end
  end
  
  describe "format_duration/1" do
    test "formats durations correctly" do
      assert Status.format_duration(50) == "50ms"
      assert Status.format_duration(1_500) == "1.50s"
      assert Status.format_duration(65_000) == "1m 5s"
      assert Status.format_duration(3_665_000) == "1h 1m 5s"
    end
  end
end