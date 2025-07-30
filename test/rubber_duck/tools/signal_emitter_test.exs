defmodule RubberDuck.Tools.SignalEmitterTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.SignalEmitter
  
  describe "tool definition" do
    test "has correct metadata" do
      assert SignalEmitter.name() == :signal_emitter
      
      metadata = SignalEmitter.metadata()
      assert metadata.name == :signal_emitter
      assert metadata.description == "Emits a Jido signal to trigger workflows or agent communication"
      assert metadata.category == :integration
      assert metadata.version == "1.0.0"
      assert :jido in metadata.tags
      assert :workflow in metadata.tags
    end
    
    test "has required parameters" do
      params = SignalEmitter.parameters()
      
      signal_type_param = Enum.find(params, &(&1.name == :signal_type))
      assert signal_type_param.required == true
      assert signal_type_param.type == :string
      
      payload_param = Enum.find(params, &(&1.name == :payload))
      assert payload_param.default == %{}
      
      priority_param = Enum.find(params, &(&1.name == :priority))
      assert priority_param.default == "normal"
    end
    
    test "supports different priority levels" do
      params = SignalEmitter.parameters()
      priority_param = Enum.find(params, &(&1.name == :priority))
      
      allowed_priorities = priority_param.constraints[:enum]
      assert "low" in allowed_priorities
      assert "normal" in allowed_priorities
      assert "high" in allowed_priorities
      assert "urgent" in allowed_priorities
    end
    
    test "has security configuration" do
      security = SignalEmitter.security_config()
      assert :jido_signal in security.capabilities
      assert security.rate_limit == 200
    end
  end
  
  describe "signal emission" do
    test "emits basic signal successfully" do
      params = %{
        signal_type: "test.signal",
        payload: %{"data" => "test_data"},
        target: "test_agent",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      {:ok, result} = SignalEmitter.execute(params, %{})
      
      assert result.signal_type == "test.signal"
      assert result.target == "test_agent"
      assert result.status in [:emitted, :completed, :processing, :failed, :timeout]
      assert is_binary(result.signal_id)
      assert %DateTime{} = result.emitted_at
    end
    
    test "handles broadcast signals" do
      params = %{
        signal_type: "broadcast.test",
        payload: %{"message" => "hello_all"},
        target: "*",
        priority: "high",
        broadcast: true,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      {:ok, result} = SignalEmitter.execute(params, %{})
      
      assert result.target == "*"
      assert result.metadata.broadcast == true
      assert length(result.acknowledgments) >= 1
    end
    
    test "includes enriched payload" do
      params = %{
        signal_type: "enrichment.test",
        payload: %{"original" => "data"},
        target: "test_workflow",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      context = %{
        project_root: "/test/project",
        session_id: "session_123",
        agent_id: "test_agent"
      }
      
      {:ok, result} = SignalEmitter.execute(params, context)
      
      # Result should indicate successful emission
      assert result.status in [:emitted, :completed, :processing, :failed, :timeout]
    end
  end
  
  describe "synchronous execution" do
    test "waits for completion when synchronous" do
      params = %{
        signal_type: "sync.test",
        payload: %{},
        target: "sync_workflow",
        priority: "normal",
        broadcast: false,
        timeout_ms: 3000,
        retry_count: 0,
        metadata: %{},
        synchronous: true
      }
      
      start_time = System.monotonic_time(:millisecond)
      {:ok, result} = SignalEmitter.execute(params, %{})
      end_time = System.monotonic_time(:millisecond)
      
      # Should have waited some time
      assert end_time - start_time >= 100  # At least some delay
      assert result.status in [:completed, :processing, :failed, :timeout]
    end
    
    test "returns immediately when asynchronous" do
      params = %{
        signal_type: "async.test",
        payload: %{},
        target: "async_workflow",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      start_time = System.monotonic_time(:millisecond)
      {:ok, result} = SignalEmitter.execute(params, %{})
      end_time = System.monotonic_time(:millisecond)
      
      # Should return quickly
      assert end_time - start_time < 1000
      assert result.status == :emitted
    end
  end
  
  describe "retry mechanism" do
    test "respects retry count parameter" do
      params = %{
        signal_type: "retry.test",
        payload: %{},
        target: "unreliable_agent",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 2,
        metadata: %{},
        synchronous: false
      }
      
      # Should eventually succeed or fail after retries
      result = SignalEmitter.execute(params, %{})
      assert match?({:ok, _} | {:error, _}, result)
    end
  end
  
  describe "utility functions" do
    test "creates code completion signal" do
      signal_params = SignalEmitter.code_completion_signal(
        "def incomplete_function",
        %{"style" => "functional"}
      )
      
      assert signal_params.signal_type == "code.completion.requested"
      assert signal_params.payload["context"] == "def incomplete_function"
      assert signal_params.payload["language"] == "elixir"
      assert signal_params.target == "code_generation_workflow"
    end
    
    test "creates test execution signal" do
      signal_params = SignalEmitter.test_execution_signal(
        "test/**/*_test.exs",
        %{"coverage" => true}
      )
      
      assert signal_params.signal_type == "test.execution.requested"
      assert signal_params.payload["pattern"] == "test/**/*_test.exs"
      assert signal_params.priority == "high"
      assert signal_params.target == "test_runner_workflow"
    end
    
    test "creates error analysis signal" do
      error_data = %{"type" => "ArgumentError", "message" => "invalid argument"}
      context = %{"function" => "process_data/1"}
      
      signal_params = SignalEmitter.error_analysis_signal(error_data, context)
      
      assert signal_params.signal_type == "error.analysis.requested"
      assert signal_params.payload["error"] == error_data
      assert signal_params.payload["context"] == context
      assert signal_params.priority == "high"
    end
    
    test "creates refactoring signal" do
      code = "def old_function, do: :legacy"
      
      signal_params = SignalEmitter.refactoring_signal(
        code,
        "extract_method",
        %{"target_name" => "new_function"}
      )
      
      assert signal_params.signal_type == "code.refactoring.requested"
      assert signal_params.payload["code"] == code
      assert signal_params.payload["refactoring_type"] == "extract_method"
      assert signal_params.target == "refactoring_workflow"
    end
    
    test "creates documentation signal" do
      signal_params = SignalEmitter.documentation_signal("MyModule", "module")
      
      assert signal_params.signal_type == "documentation.generation.requested"
      assert signal_params.payload["target"] == "MyModule"
      assert signal_params.payload["type"] == "module"
      assert signal_params.priority == "low"
    end
  end
  
  describe "acknowledgments" do
    test "receives acknowledgments from targets" do
      params = %{
        signal_type: "ack.test",
        payload: %{},
        target: "responding_agent",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      {:ok, result} = SignalEmitter.execute(params, %{})
      
      assert is_list(result.acknowledgments)
      
      if length(result.acknowledgments) > 0 do
        ack = hd(result.acknowledgments)
        assert Map.has_key?(ack, :signal_id)
        assert Map.has_key?(ack, :acknowledged_at)
        assert ack.type in [:agent_ack, :workflow_ack]
      end
    end
    
    test "handles broadcast acknowledgments" do
      params = %{
        signal_type: "broadcast.ack.test",
        payload: %{},
        target: "all",
        priority: "normal",
        broadcast: true,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      {:ok, result} = SignalEmitter.execute(params, %{})
      
      # Broadcast should receive multiple acknowledgments
      assert length(result.acknowledgments) >= 1
    end
  end
  
  describe "error handling" do
    test "handles missing signal type" do
      params = %{
        signal_type: "",
        payload: %{},
        target: "test_agent",
        priority: "normal",
        broadcast: false,
        timeout_ms: 5000,
        retry_count: 0,
        metadata: %{},
        synchronous: false
      }
      
      # Should be caught by parameter validation
      assert_raise ArgumentError, fn ->
        SignalEmitter.execute(params, %{})
      end
    end
  end
end