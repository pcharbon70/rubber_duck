defmodule RubberDuck.Tools.Agents.BaseToolAgentTest do
  use ExUnit.Case, async: true
  
  # Define a test agent using BaseToolAgent
  defmodule TestToolAgent do
    use RubberDuck.Tools.Agents.BaseToolAgent,
      tool: :test_tool,
      name: "test_tool_agent",
      description: "Test agent for BaseToolAgent",
      cache_ttl: 1000, # 1 second for testing
      schema: [
        custom_state: [type: :string, default: "test"]
      ]
    
    @impl true
    def validate_params(%{"valid" => false}) do
      {:error, "Invalid params"}
    end
    
    def validate_params(params) do
      {:ok, params}
    end
    
    @impl true
    def process_result(result, _request) do
      Map.put(result, :processed, true)
    end
    
    @impl true
    def handle_tool_signal(agent, %{"type" => "custom_signal"} = signal) do
      emit_signal("custom_response", %{"data" => "handled"})
      {:ok, agent}
    end
  end
  
  setup do
    # Mock the tool executor
    Mox.defmock(RubberDuck.ToolSystem.ExecutorMock, for: RubberDuck.ToolSystem.Executor.Behaviour)
    
    # Create agent instance
    {:ok, agent} = TestToolAgent.start()
    
    on_exit(fn ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
    
    {:ok, agent: agent}
  end
  
  describe "tool_request signal" do
    test "executes tool successfully", %{agent: agent} do
      # Setup executor mock
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_tool, %{"input" => "test"} ->
        {:ok, %{output: "success"}}
      end)
      
      # Send tool request
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"input" => "test"},
          "request_id" => "test_123"
        }
      }
      
      {:ok, _updated_agent} = TestToolAgent.handle_signal(agent, signal)
      
      # Wait for async execution
      Process.sleep(100)
      
      # Should receive tool_result signal
      assert_receive {:signal, "tool_result", result_data}
      assert result_data["request_id"] == "test_123"
      assert result_data["result"][:output] == "success"
      assert result_data["result"][:processed] == true # From process_result callback
    end
    
    test "returns cached result on second request", %{agent: agent} do
      # Setup executor mock - should only be called once
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 1, fn :test_tool, %{"input" => "test"} ->
        {:ok, %{output: "cached_test"}}
      end)
      
      params = %{"input" => "test"}
      
      # First request
      signal1 = %{
        "type" => "tool_request",
        "data" => %{
          "params" => params,
          "request_id" => "req_1"
        }
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal1)
      Process.sleep(100)
      
      assert_receive {:signal, "tool_result", result1}
      assert result1["from_cache"] == nil
      
      # Second request with same params
      signal2 = %{
        "type" => "tool_request",
        "data" => %{
          "params" => params,
          "request_id" => "req_2"
        }
      }
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal2)
      
      assert_receive {:signal, "tool_result", result2}
      assert result2["from_cache"] == true
      assert result2["result"] == result1["result"]
    end
    
    test "validates parameters before execution", %{agent: agent} do
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"valid" => false},
          "request_id" => "invalid_req"
        }
      }
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, "tool_error", error_data}
      assert error_data["request_id"] == "invalid_req"
      assert error_data["error"] =~ "Validation failed"
    end
    
    test "handles tool execution errors", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_tool, _ ->
        {:error, "Tool failed"}
      end)
      
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"will" => "fail"},
          "request_id" => "fail_req"
        }
      }
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      assert_receive {:signal, "tool_error", error_data}
      assert error_data["request_id"] == "fail_req"
      assert error_data["error"] == "Tool failed"
    end
  end
  
  describe "rate limiting" do
    test "enforces rate limits", %{agent: agent} do
      # Set a low rate limit for testing
      agent = put_in(agent.state.rate_limit_max, 2)
      agent = put_in(agent.state.rate_limit_window, 1000) # 1 second
      
      # First two requests should succeed
      for i <- 1..2 do
        signal = %{
          "type" => "tool_request",
          "data" => %{
            "params" => %{"request" => i},
            "request_id" => "rate_#{i}"
          }
        }
        
        {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      end
      
      # Third request should be rate limited
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"request" => 3},
          "request_id" => "rate_3"
        }
      }
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal)
      
      assert_receive {:signal, "tool_error", error_data}
      assert error_data["error"] == "Rate limit exceeded"
      assert error_data["retry_after"] > 0
    end
  end
  
  describe "request management" do
    test "queues requests when one is active", %{agent: agent} do
      # Mock slow execution
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_tool, params ->
        Process.sleep(200) # Simulate slow execution
        {:ok, %{input: params["input"], result: "done"}}
      end)
      
      # Send two requests quickly
      signal1 = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"input" => "first"},
          "request_id" => "queue_1"
        }
      }
      
      signal2 = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"input" => "second"},
          "request_id" => "queue_2"
        }
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal1)
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal2)
      
      # Check queue state
      assert length(agent.state.request_queue) == 1
      assert map_size(agent.state.active_requests) == 1
      
      # Wait for both to complete
      Process.sleep(500)
      
      # Should receive both results in order
      assert_receive {:signal, "tool_result", result1}
      assert_receive {:signal, "tool_result", result2}
      
      assert result1["request_id"] == "queue_1"
      assert result2["request_id"] == "queue_2"
    end
    
    test "cancels queued request", %{agent: agent} do
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{"input" => "to_cancel"},
          "request_id" => "cancel_me"
        }
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      
      # Cancel before execution
      cancel_signal = %{
        "type" => "cancel_request",
        "data" => %{"request_id" => "cancel_me"}
      }
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, cancel_signal)
      
      assert_receive {:signal, "request_cancelled", cancel_data}
      assert cancel_data["request_id"] == "cancel_me"
    end
  end
  
  describe "metrics and monitoring" do
    test "tracks execution metrics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_tool, _ ->
        {:ok, %{result: "success"}}
      end)
      
      # Execute successful request
      signal1 = %{
        "type" => "tool_request",
        "data" => %{"params" => %{"test" => 1}}
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal1)
      Process.sleep(100)
      
      # Execute failed request
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, fn :test_tool, _ ->
        {:error, "Failed"}
      end)
      
      signal2 = %{
        "type" => "tool_request",
        "data" => %{"params" => %{"test" => 2}}
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal2)
      Process.sleep(100)
      
      # Get metrics
      metrics_signal = %{"type" => "get_metrics"}
      {:ok, _agent} = TestToolAgent.handle_signal(agent, metrics_signal)
      
      assert_receive {:signal, "metrics_report", metrics_data}
      
      metrics = metrics_data["metrics"]
      assert metrics.total_requests >= 2
      assert metrics.successful_requests >= 1
      assert metrics.failed_requests >= 1
      assert metrics.average_execution_time > 0
    end
    
    test "reports cache hits in metrics", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 1, fn :test_tool, _ ->
        {:ok, %{cached: true}}
      end)
      
      params = %{"same" => "params"}
      
      # First request
      signal = %{
        "type" => "tool_request",
        "data" => %{"params" => params}
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Second request (should hit cache)
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      
      # Get metrics
      metrics_signal = %{"type" => "get_metrics"}
      {:ok, _agent} = TestToolAgent.handle_signal(agent, metrics_signal)
      
      assert_receive {:signal, "metrics_report", metrics_data}
      assert metrics_data["metrics"].cache_hits >= 1
    end
  end
  
  describe "cache management" do
    test "clears cache on request", %{agent: agent} do
      # Populate cache
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_tool, _ ->
        {:ok, %{data: "original"}}
      end)
      
      signal = %{
        "type" => "tool_request",
        "data" => %{"params" => %{"key" => "value"}}
      }
      
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Clear cache
      clear_signal = %{"type" => "clear_cache"}
      {:ok, agent} = TestToolAgent.handle_signal(agent, clear_signal)
      
      assert_receive {:signal, "cache_cleared", clear_data}
      assert clear_data["tool"] == :test_tool
      
      # Next request should not hit cache
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should have made two executor calls
      verify!()
    end
    
    test "expires cached results after TTL", %{agent: agent} do
      expect(RubberDuck.ToolSystem.ExecutorMock, :execute, 2, fn :test_tool, _ ->
        {:ok, %{timestamp: System.monotonic_time()}}
      end)
      
      params = %{"expire" => "test"}
      signal = %{
        "type" => "tool_request",
        "data" => %{"params" => params}
      }
      
      # First request
      {:ok, agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Wait for TTL to expire (1 second in test agent)
      Process.sleep(1100)
      
      # Second request should not hit cache
      {:ok, _agent} = TestToolAgent.handle_signal(agent, signal)
      Process.sleep(100)
      
      # Should have made two executor calls
      verify!()
    end
  end
  
  describe "custom signal handling" do
    test "delegates to tool-specific handler", %{agent: agent} do
      custom_signal = %{"type" => "custom_signal", "data" => %{}}
      
      {:ok, _agent} = TestToolAgent.handle_signal(agent, custom_signal)
      
      assert_receive {:signal, "custom_response", response_data}
      assert response_data["data"] == "handled"
    end
    
    test "warns on unknown signals", %{agent: agent} do
      unknown_signal = %{"type" => "unknown_signal"}
      
      # Capture log output
      assert capture_log(fn ->
        {:ok, _agent} = TestToolAgent.handle_signal(agent, unknown_signal)
      end) =~ "received unknown signal: \"unknown_signal\""
    end
  end
  
  # Helper to capture logs
  defp capture_log(fun) do
    Logger.configure(level: :debug)
    
    {:ok, string_io} = StringIO.open("")
    Logger.add_backend({LoggerBackend, string_io})
    
    try do
      fun.()
      Logger.flush()
      
      {:ok, {_in, out}} = StringIO.close(string_io)
      out
    after
      Logger.remove_backend({LoggerBackend, string_io})
    end
  end
end