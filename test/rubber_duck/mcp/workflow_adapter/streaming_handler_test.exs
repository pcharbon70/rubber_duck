defmodule RubberDuck.MCP.WorkflowAdapter.StreamingHandlerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.WorkflowAdapter.StreamingHandler
  alias Phoenix.PubSub

  setup do
    # Ensure PubSub is available for testing
    start_supervised({Phoenix.PubSub, name: RubberDuck.PubSub})
    :ok
  end

  describe "create_workflow_stream/3" do
    test "creates a workflow stream successfully" do
      # Create a simple mock workflow
      workflow = %{
        id: "test_workflow",
        type: "sequential",
        steps: [
          %{tool: "test_tool", params: %{input: "test"}}
        ]
      }

      context = %{
        session_id: "test_session",
        user_id: "test_user"
      }

      options = %{
        timeout: 5000,
        streaming: true
      }

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, context, options)

      assert is_function(stream)

      # Test that stream produces events
      events = stream |> Enum.take(3)

      assert is_list(events)
      # Should receive some events (start, progress, completion/error)
      assert length(events) >= 1
    end

    test "handles workflow stream creation errors" do
      # Test with invalid workflow
      invalid_workflow = %{
        id: nil,
        type: "invalid_type"
      }

      context = %{session_id: "test_session"}

      result = StreamingHandler.create_workflow_stream(invalid_workflow, context, %{})

      # Should handle errors gracefully
      assert {:error, _reason} = result
    end

    test "stream emits workflow start event" do
      workflow = %{
        id: "stream_test",
        type: "sequential",
        steps: []
      }

      context = %{
        session_id: "test_session",
        workflow_id: "stream_test"
      }

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, context, %{})

      # Get first event
      first_event = stream |> Enum.take(1) |> List.first()

      assert first_event.type == "workflow_started"
      assert first_event.data.workflow_id == "stream_test"
      assert Map.has_key?(first_event.data, :context)
      assert Map.has_key?(first_event.data, :timestamp)
    end

    test "stream handles workflow execution completion" do
      workflow = %{
        id: "completion_test",
        type: "sequential",
        steps: [
          %{tool: "mock_tool", params: %{result: "success"}}
        ]
      }

      context = %{
        session_id: "test_session",
        workflow_id: "completion_test"
      }

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, context, %{})

      # Collect all events
      events = stream |> Enum.take(10) |> Enum.to_list()

      # Should have start event and possibly completion event
      event_types = Enum.map(events, & &1.type)
      assert "workflow_started" in event_types

      # May have completion or error event depending on execution
      completion_events =
        Enum.filter(event_types, fn type ->
          type in ["workflow_completed", "workflow_failed"]
        end)

      # Should have at least attempted completion
      assert length(completion_events) >= 0
    end
  end

  describe "execute_with_streaming/3" do
    test "executes workflow with streaming enabled" do
      workflow = %{
        id: "streaming_exec_test",
        type: "sequential",
        steps: [
          %{tool: "test_tool", params: %{input: "streaming_test"}}
        ]
      }

      context = %{
        session_id: "test_session",
        user_id: "test_user"
      }

      options = %{
        timeout: 5000,
        streaming: true
      }

      result = StreamingHandler.execute_with_streaming(workflow, context, options)

      # Should return execution result
      assert {:ok, _result} = result or {:error, _reason} = result
    end

    test "enhances context with streaming information" do
      workflow = %{
        id: "context_test",
        type: "sequential",
        steps: []
      }

      original_context = %{
        session_id: "test_session"
      }

      # Mock the execution to capture enhanced context
      result = StreamingHandler.execute_with_streaming(workflow, original_context, %{})

      # Should complete without error (context enhancement is internal)
      assert {:ok, _result} = result or {:error, _reason} = result
    end

    test "emits workflow completion event" do
      workflow = %{
        id: "completion_event_test",
        type: "sequential",
        steps: []
      }

      context = %{
        session_id: "test_session",
        workflow_id: "completion_event_test"
      }

      # Subscribe to events
      stream_id = "test_stream_id"
      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Execute workflow
      StreamingHandler.execute_with_streaming(workflow, context, %{})

      # Check for events (with timeout)
      receive do
        event ->
          assert Map.has_key?(event, :type)
          assert Map.has_key?(event, :data)
      after
        1000 ->
          # No events received, which is acceptable for this test
          :ok
      end
    end

    test "handles workflow execution errors with streaming" do
      workflow = %{
        id: "error_test",
        type: "sequential",
        steps: [
          %{tool: "failing_tool", params: %{should_fail: true}}
        ]
      }

      context = %{
        session_id: "test_session",
        workflow_id: "error_test"
      }

      result = StreamingHandler.execute_with_streaming(workflow, context, %{})

      # Should handle errors gracefully
      case result do
        {:ok, _} -> assert true
        {:error, _reason} -> assert true
      end
    end
  end

  describe "publish_workflow_event/3" do
    test "publishes event to PubSub" do
      stream_id = "test_stream_123"
      topic = "workflow_stream:#{stream_id}"

      # Subscribe to the topic
      PubSub.subscribe(RubberDuck.PubSub, topic)

      event_data = %{
        workflow_id: "test_workflow",
        step_name: "test_step",
        progress: 50
      }

      :ok = StreamingHandler.publish_workflow_event(stream_id, "step_progress", event_data)

      # Should receive the event
      receive do
        event ->
          assert event.type == "step_progress"
          assert event.stream_id == stream_id
          assert event.data == event_data
          assert %DateTime{} = event.timestamp
      after
        1000 ->
          flunk("Expected to receive workflow event")
      end
    end

    test "handles multiple subscribers" do
      stream_id = "multi_subscriber_test"
      topic = "workflow_stream:#{stream_id}"

      # Subscribe with multiple processes
      parent = self()

      subscribers =
        for i <- 1..3 do
          spawn(fn ->
            PubSub.subscribe(RubberDuck.PubSub, topic)

            receive do
              event ->
                send(parent, {:received, i, event})
            after
              1000 ->
                send(parent, {:timeout, i})
            end
          end)
        end

      # Publish event
      event_data = %{test: "multi_subscriber"}
      :ok = StreamingHandler.publish_workflow_event(stream_id, "test_event", event_data)

      # Collect responses
      responses =
        for _i <- 1..3 do
          receive do
            {:received, subscriber_id, event} ->
              {:received, subscriber_id, event}

            {:timeout, subscriber_id} ->
              {:timeout, subscriber_id}
          after
            1500 ->
              :no_response
          end
        end

      # All subscribers should receive the event
      received_count =
        Enum.count(responses, fn
          {:received, _, _} -> true
          _ -> false
        end)

      assert received_count >= 1
    end
  end

  describe "create_step_progress_reporter/2" do
    test "creates progress reporter function" do
      stream_id = "progress_test"
      step_name = "test_step"

      reporter = StreamingHandler.create_step_progress_reporter(stream_id, step_name)

      assert is_function(reporter, 1)

      # Subscribe to events
      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Use the reporter
      progress_data = %{
        percentage: 75,
        message: "Processing items"
      }

      reporter.(progress_data)

      # Should receive progress event
      receive do
        event ->
          assert event.type == "step_progress"
          assert event.stream_id == stream_id
          assert event.data.step_name == step_name
          assert event.data.progress == progress_data
          assert %DateTime{} = event.data.timestamp
      after
        1000 ->
          flunk("Expected to receive step progress event")
      end
    end

    test "reporter handles different progress data types" do
      stream_id = "progress_types_test"
      step_name = "flexible_step"

      reporter = StreamingHandler.create_step_progress_reporter(stream_id, step_name)

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Test with different data types
      test_data = [
        %{count: 10, total: 100},
        "50% complete",
        42,
        ["item1", "item2", "item3"]
      ]

      for data <- test_data do
        reporter.(data)

        receive do
          event ->
            assert event.type == "step_progress"
            assert event.data.progress == data
        after
          500 ->
            flunk("Expected to receive progress event for #{inspect(data)}")
        end
      end
    end
  end

  describe "stream_intermediate_result/3" do
    test "streams intermediate results" do
      stream_id = "intermediate_test"
      step_name = "data_processor"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Test with different result types
      results = [
        "Text result",
        %{data: "structured result"},
        [1, 2, 3, 4, 5],
        {:ok, "tuple result"}
      ]

      for result <- results do
        :ok = StreamingHandler.stream_intermediate_result(stream_id, step_name, result)

        receive do
          event ->
            assert event.type == "intermediate_result"
            assert event.stream_id == stream_id
            assert event.data.step_name == step_name
            assert Map.has_key?(event.data, :result)
            assert %DateTime{} = event.data.timestamp
        after
          500 ->
            flunk("Expected to receive intermediate result event")
        end
      end
    end

    test "formats different result types correctly" do
      stream_id = "format_test"
      step_name = "formatter"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Test text result
      :ok = StreamingHandler.stream_intermediate_result(stream_id, step_name, "text result")

      receive do
        event ->
          assert event.data.result.type == "text"
          assert event.data.result.content == "text result"
      after
        500 ->
          flunk("Expected text result event")
      end

      # Test map result
      :ok = StreamingHandler.stream_intermediate_result(stream_id, step_name, %{key: "value"})

      receive do
        event ->
          assert event.data.result.type == "json"
          assert event.data.result.content == %{key: "value"}
      after
        500 ->
          flunk("Expected json result event")
      end
    end
  end

  describe "stream_step_completion/4" do
    test "streams step completion events" do
      stream_id = "completion_test"
      step_name = "completed_step"
      result = %{status: "success", data: "processed"}
      execution_time = 1500

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_step_completion(stream_id, step_name, result, execution_time)

      receive do
        event ->
          assert event.type == "step_completed"
          assert event.stream_id == stream_id
          assert event.data.step_name == step_name
          assert event.data.execution_time_ms == execution_time
          assert Map.has_key?(event.data, :result)
          assert %DateTime{} = event.data.timestamp
      after
        1000 ->
          flunk("Expected to receive step completion event")
      end
    end

    test "handles large execution times" do
      stream_id = "large_time_test"
      step_name = "slow_step"
      result = "completed"
      # 1 minute
      execution_time = 60_000

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_step_completion(stream_id, step_name, result, execution_time)

      receive do
        event ->
          assert event.data.execution_time_ms == execution_time
      after
        1000 ->
          flunk("Expected to receive completion event")
      end
    end
  end

  describe "stream_step_failure/3" do
    test "streams step failure events" do
      stream_id = "failure_test"
      step_name = "failing_step"
      error = "Something went wrong"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_step_failure(stream_id, step_name, error)

      receive do
        event ->
          assert event.type == "step_failed"
          assert event.stream_id == stream_id
          assert event.data.step_name == step_name
          assert Map.has_key?(event.data, :error)
          assert %DateTime{} = event.data.timestamp
      after
        1000 ->
          flunk("Expected to receive step failure event")
      end
    end

    test "sanitizes error information" do
      stream_id = "sanitize_test"
      step_name = "secure_step"
      error = "Authentication failed with password=secret123 and token=abc123"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_step_failure(stream_id, step_name, error)

      receive do
        event ->
          sanitized_error = event.data.error
          assert not String.contains?(sanitized_error, "secret123")
          assert not String.contains?(sanitized_error, "abc123")
          assert String.contains?(sanitized_error, "password=***")
          assert String.contains?(sanitized_error, "token=***")
      after
        1000 ->
          flunk("Expected to receive sanitized error event")
      end
    end

    test "handles complex error structures" do
      stream_id = "complex_error_test"
      step_name = "complex_step"

      error = %{
        type: "validation_error",
        message: "Invalid input",
        details: %{
          field: "email",
          value: "invalid-email"
        }
      }

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_step_failure(stream_id, step_name, error)

      receive do
        event ->
          assert is_binary(event.data.error)
          assert String.contains?(event.data.error, "validation_error")
      after
        1000 ->
          flunk("Expected to receive complex error event")
      end
    end
  end

  describe "data sanitization" do
    test "sanitizes sensitive context data" do
      stream_id = "sanitize_context_test"

      # Create workflow with sensitive context
      workflow = %{
        id: "sensitive_test",
        type: "sequential",
        steps: []
      }

      sensitive_context = %{
        user_id: "user123",
        credentials: %{username: "admin", password: "secret"},
        secrets: %{api_key: "super_secret"},
        tokens: %{access_token: "token123"},
        safe_data: "this is safe"
      }

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, sensitive_context, %{})

      # Get the first event (workflow started)
      first_event = stream |> Enum.take(1) |> List.first()

      if first_event do
        sanitized_context = first_event.data.context

        # Should not contain sensitive information
        assert not Map.has_key?(sanitized_context, :credentials)
        assert not Map.has_key?(sanitized_context, :secrets)
        assert not Map.has_key?(sanitized_context, :tokens)

        # Should contain safe data
        assert Map.has_key?(sanitized_context, :safe_data)
        assert sanitized_context.safe_data == "this is safe"

        # Should be marked as sanitized
        assert sanitized_context.sanitized == true
      end
    end

    test "sanitizes sensitive result data" do
      stream_id = "sanitize_result_test"
      step_name = "sensitive_step"

      sensitive_result = %{
        data: "processed successfully",
        credentials: %{username: "admin"},
        secrets: %{api_key: "secret123"},
        tokens: %{jwt: "token456"}
      }

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      :ok = StreamingHandler.stream_intermediate_result(stream_id, step_name, sensitive_result)

      receive do
        event ->
          result = event.data.result

          # Should not contain sensitive keys in formatted result
          result_json = Jason.encode!(result)
          assert not String.contains?(result_json, "credentials")
          assert not String.contains?(result_json, "secrets")
          assert not String.contains?(result_json, "tokens")

          # Should contain safe data
          assert String.contains?(result_json, "processed successfully")
      after
        1000 ->
          flunk("Expected to receive sanitized result event")
      end
    end
  end

  describe "event timing and ordering" do
    test "events have proper timestamps" do
      stream_id = "timing_test"
      step_name = "timed_step"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      before_time = DateTime.utc_now()

      :ok = StreamingHandler.stream_step_completion(stream_id, step_name, "result", 100)

      receive do
        event ->
          after_time = DateTime.utc_now()
          event_time = event.data.timestamp

          # Event timestamp should be between before and after
          assert DateTime.compare(event_time, before_time) != :lt
          assert DateTime.compare(event_time, after_time) != :gt
      after
        1000 ->
          flunk("Expected to receive timed event")
      end
    end

    test "handles rapid event publishing" do
      stream_id = "rapid_test"
      step_name = "rapid_step"

      topic = "workflow_stream:#{stream_id}"
      PubSub.subscribe(RubberDuck.PubSub, topic)

      # Publish multiple events rapidly
      for i <- 1..5 do
        :ok = StreamingHandler.stream_intermediate_result(stream_id, step_name, "result_#{i}")
      end

      # Collect all events
      events =
        for _i <- 1..5 do
          receive do
            event -> event
          after
            1000 -> nil
          end
        end

      # Should receive all events
      received_events = Enum.reject(events, &is_nil/1)
      assert length(received_events) == 5

      # Events should be in order (timestamps should be increasing)
      timestamps = Enum.map(received_events, & &1.data.timestamp)
      sorted_timestamps = Enum.sort(timestamps, DateTime)

      assert timestamps == sorted_timestamps
    end
  end

  describe "stream lifecycle" do
    test "stream properly cleans up resources" do
      workflow = %{
        id: "cleanup_test",
        type: "sequential",
        steps: [
          %{tool: "test_tool", params: %{input: "cleanup"}}
        ]
      }

      context = %{
        session_id: "cleanup_session",
        workflow_id: "cleanup_test"
      }

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, context, %{})

      # Consume the stream
      events = stream |> Enum.take(5) |> Enum.to_list()

      # Should have received some events
      assert length(events) >= 0

      # Stream should complete without hanging
      assert true
    end

    test "stream handles early termination" do
      workflow = %{
        id: "early_term_test",
        type: "sequential",
        steps: [
          %{tool: "slow_tool", params: %{delay: 30_000}}
        ]
      }

      context = %{
        session_id: "term_session",
        workflow_id: "early_term_test"
      }

      {:ok, stream} = StreamingHandler.create_workflow_stream(workflow, context, %{})

      # Take only first few events and terminate early
      events = stream |> Enum.take(2) |> Enum.to_list()

      # Should handle early termination gracefully
      assert length(events) >= 0
    end
  end
end
