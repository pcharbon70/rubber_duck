defmodule RubberDuck.Jido.Actions.Base.ProcessingActionTest do
  use ExUnit.Case, async: true
  
  # Test implementation of ProcessingAction
  defmodule TestProcessingAction do
    use RubberDuck.Jido.Actions.Base.ProcessingAction,
      name: "test_processing",
      description: "Test processing action",
      schema: [
        input_data: [type: :any, required: true],
        processing_mode: [type: :atom, default: :simple, values: [:simple, :complex, :error, :timeout]]
      ]
    
    @impl true
    def process_data(params, context) do
      case params.processing_mode do
        :simple -> 
          {:ok, %{result: "processed_#{params.input_data}", steps: 1}}
        :complex -> 
          # Simulate complex processing with progress tracking
          if params.enable_progress_tracking do
            track_progress("step1", 33, params)
            track_progress("step2", 66, params)
            track_progress("step3", 100, params)
          end
          {:ok, %{result: "complex_processed_#{params.input_data}", steps: 3}}
        :error -> 
          {:error, :processing_failed}
        :timeout ->
          Process.sleep(200)  # Will timeout with short max_processing_time
          {:ok, %{result: "delayed_result"}}
      end
    end
    
    def before_processing(params, context) do
      if Map.get(params, :add_metadata) do
        enhanced_context = Map.put(context, :metadata, %{started_at: DateTime.utc_now()})
        {:ok, enhanced_context}
      else
        {:ok, context}
      end
    end
    
    def after_processing(result, _params, _context) do
      enhanced_result = Map.put(result, :completed_at, DateTime.utc_now())
      {:ok, enhanced_result}
    end
    
    def handle_processing_error(:processing_failed, _params, _context) do
      {:ok, %{result: "recovered_result", error_handled: true}}
    end
    
    def handle_processing_error(reason, _params, _context) do
      {:error, reason}
    end
    
    def track_progress(stage, progress, _params) do
      send(self(), {:progress_update, stage, progress})
      :ok
    end
  end
  
  describe "ProcessingAction base behavior" do
    test "simple processing with default parameters" do
      params = %{input_data: "test_data"}
      context = %{agent: %{}}
      
      assert {:ok, result} = TestProcessingAction.run(params, context)
      assert result.success == true
      assert result.data.result == "processed_test_data"
      assert result.data.steps == 1
      assert result.data.completed_at
      assert result.metadata.action == "test_processing"
      assert is_integer(result.metadata.processing_time)
    end
    
    test "complex processing with progress tracking" do
      params = %{
        input_data: "complex_data",
        processing_mode: :complex,
        enable_progress_tracking: true
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestProcessingAction.run(params, context)
      assert result.success == true
      assert result.data.result == "complex_processed_complex_data"
      assert result.data.steps == 3
      assert result.metadata.progress_tracking_enabled == true
      
      # Check that progress updates were sent
      assert_receive {:progress_update, "step1", 33}
      assert_receive {:progress_update, "step2", 66}
      assert_receive {:progress_update, "step3", 100}
    end
    
    test "processing with before_processing hook" do
      params = %{
        input_data: "hook_data",
        add_metadata: true
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestProcessingAction.run(params, context)
      assert result.success == true
    end
    
    test "error handling with recovery" do
      params = %{
        input_data: "error_data",
        processing_mode: :error
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestProcessingAction.run(params, context)
      assert result.success == true
      assert result.data.result == "recovered_result"
      assert result.data.error_handled == true
    end
    
    test "processing timeout" do
      params = %{
        input_data: "timeout_data",
        processing_mode: :timeout,
        max_processing_time: 50  # Very short timeout
      }
      context = %{agent: %{}}
      
      assert {:error, result} = TestProcessingAction.run(params, context)
      assert result.success == false
      assert result.error == :processing_timeout
    end
    
    test "disabling telemetry" do
      params = %{
        input_data: "test_data",
        enable_telemetry: false
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestProcessingAction.run(params, context)
      assert result.success == true
      # Test passes if no telemetry events are emitted (no crash)
    end
    
    test "validates processing timeout parameter" do
      params = %{
        input_data: "test_data",
        max_processing_time: 500  # Too short
      }
      context = %{agent: %{}}
      
      assert {:error, result} = TestProcessingAction.run(params, context)
      assert result.error == :invalid_processing_time
    end
  end
end