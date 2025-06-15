defmodule RubberDuck.Interface.Adapters.BaseTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.{Behaviour, Adapters.Base}
  
  defmodule TestAdapter do
    use Base
    
    @impl true
    def handle_request(request, context, state) do
      case request[:operation] do
        :success ->
          response = Behaviour.success_response(request[:id], %{result: "success"})
          {:ok, response, state}
          
        :error ->
          error = Behaviour.error(:internal_error, "Test error")
          {:error, error, state}
          
        :async ->
          ref = make_ref()
          {:async, ref, state}
      end
    end
    
    @impl true
    def format_response(response, _request, _state) do
      {:ok, Map.put(response, :formatted, true)}
    end
    
    @impl true
    def handle_error(error, _request, _state) do
      Map.put(error, :handled, true)
    end
    
    @impl true
    def capabilities, do: [:chat, :complete, :test]
  end
  
  describe "adapter initialization" do
    test "initializes with default state" do
      {:ok, state} = TestAdapter.init([])
      
      assert %{
        config: %{},
        start_time: start_time,
        request_count: 0,
        error_count: 0,
        metrics: %{},
        circuit_breaker: %{
          failure_count: 0,
          last_failure: nil,
          state: :closed
        }
      } = state
      
      assert is_integer(start_time)
    end
    
    test "initializes with custom config" do
      {:ok, state} = TestAdapter.init(config: %{custom: "value"})
      
      assert state.config == %{custom: "value"}
    end
  end
  
  describe "request validation" do
    test "validates basic request structure" do
      valid_request = %{
        operation: :test,
        params: %{}
      }
      
      assert :ok = TestAdapter.validate_request(valid_request)
    end
    
    test "rejects non-map requests" do
      assert {:error, ["Request must be a map"]} = TestAdapter.validate_request("invalid")
    end
    
    test "rejects requests without operation" do
      invalid_request = %{params: %{}}
      
      assert {:error, ["Request must have an operation field"]} = 
        TestAdapter.validate_request(invalid_request)
    end
    
    test "rejects requests without params" do
      invalid_request = %{operation: :test}
      
      assert {:error, ["Request must have a params field"]} = 
        TestAdapter.validate_request(invalid_request)
    end
  end
  
  describe "request middleware" do
    test "handles successful requests" do
      {:ok, state} = TestAdapter.init([])
      
      request = %{
        id: "test_123",
        operation: :success,
        params: %{}
      }
      
      handler = fn req, _ctx, st ->
        response = Behaviour.success_response(req[:id], %{result: "success"})
        {:ok, response, st}
      end
      
      {:ok, response, new_state} = 
        TestAdapter.handle_request_with_middleware(request, %{}, state, handler)
      
      assert response.id == "test_123"
      assert response.status == :ok
      assert new_state.request_count == 1
      assert new_state.error_count == 0
    end
    
    test "handles error requests" do
      {:ok, state} = TestAdapter.init([])
      
      request = %{
        id: "test_123",
        operation: :error,
        params: %{}
      }
      
      handler = fn _req, _ctx, st ->
        error = Behaviour.error(:internal_error, "Test error")
        {:error, error, st}
      end
      
      {:error, error, new_state} = 
        TestAdapter.handle_request_with_middleware(request, %{}, state, handler)
      
      assert {:error, :internal_error, "Test error", %{}} = error
      assert new_state.request_count == 1
      assert new_state.error_count == 1
    end
    
    test "generates request ID if missing" do
      request = %{operation: :test, params: %{}}
      
      id = TestAdapter.ensure_request_id(request)
      
      assert is_binary(id)
      assert String.starts_with?(id, "req_")
    end
    
    test "preserves existing request ID" do
      request = %{id: "existing_123", operation: :test, params: %{}}
      
      id = TestAdapter.ensure_request_id(request)
      
      assert id == "existing_123"
    end
  end
  
  describe "metrics and monitoring" do
    test "updates success metrics" do
      {:ok, state} = TestAdapter.init([])
      
      new_state = TestAdapter.update_metrics(state, :success, 100)
      
      assert new_state.metrics[:success] == 1
      assert new_state.metrics[:total_duration] == 100
    end
    
    test "calculates error rate" do
      state = %{request_count: 10, error_count: 2}
      
      rate = TestAdapter.calculate_error_rate(state)
      
      assert rate == 20.0
    end
    
    test "returns zero error rate for no requests" do
      state = %{request_count: 0, error_count: 0}
      
      rate = TestAdapter.calculate_error_rate(state)
      
      assert rate == 0.0
    end
  end
  
  describe "circuit breaker" do
    test "allows requests when circuit is closed" do
      state = %{circuit_breaker: %{state: :closed}}
      
      assert :ok = TestAdapter.check_circuit_breaker(state)
    end
    
    test "blocks requests when circuit is open and recent" do
      now = System.monotonic_time(:millisecond)
      state = %{
        circuit_breaker: %{
          state: :open,
          last_failure: now - 30_000  # 30 seconds ago
        }
      }
      
      assert {:error, "Circuit breaker is open"} = 
        TestAdapter.check_circuit_breaker(state)
    end
    
    test "allows requests when circuit is open but timeout passed" do
      now = System.monotonic_time(:millisecond)
      state = %{
        circuit_breaker: %{
          state: :open,
          last_failure: now - 70_000  # 70 seconds ago
        }
      }
      
      assert :ok = TestAdapter.check_circuit_breaker(state)
    end
    
    test "resets circuit breaker after success" do
      state = %{
        circuit_breaker: %{
          failure_count: 3,
          last_failure: 12345,
          state: :half_open
        }
      }
      
      new_state = TestAdapter.reset_circuit_breaker(state)
      
      assert new_state.circuit_breaker == %{
        failure_count: 0,
        last_failure: nil,
        state: :closed
      }
    end
    
    test "trips circuit breaker after threshold failures" do
      state = %{
        circuit_breaker: %{
          failure_count: 4,
          last_failure: nil,
          state: :closed
        }
      }
      
      new_state = TestAdapter.trip_circuit_breaker(state)
      
      assert new_state.circuit_breaker.failure_count == 5
      assert new_state.circuit_breaker.state == :open
      assert is_integer(new_state.circuit_breaker.last_failure)
    end
  end
  
  describe "parameter validation" do
    test "validates required parameters" do
      params = %{name: "test", age: 25}
      schema = %{
        name: %{required: true, type: :string},
        age: %{required: true, type: :integer}
      }
      
      assert :ok = TestAdapter.validate_params(params, schema)
    end
    
    test "rejects missing required parameters" do
      params = %{name: "test"}
      schema = %{
        name: %{required: true, type: :string},
        age: %{required: true, type: :integer}
      }
      
      assert {:error, [{:age, "is required"}]} = 
        TestAdapter.validate_params(params, schema)
    end
    
    test "validates parameter types" do
      params = %{name: 123}
      schema = %{name: %{required: true, type: :string}}
      
      assert {:error, [{:name, "must be of type string"}]} = 
        TestAdapter.validate_params(params, schema)
    end
    
    test "allows optional parameters" do
      params = %{name: "test"}
      schema = %{
        name: %{required: true, type: :string},
        optional: %{type: :string}
      }
      
      assert :ok = TestAdapter.validate_params(params, schema)
    end
  end
  
  describe "health check" do
    test "reports healthy when circuit is closed" do
      {:ok, state} = TestAdapter.init([])
      
      {status, metadata} = TestAdapter.health_check(state)
      
      assert status == :healthy
      assert metadata.circuit_breaker == :closed
      assert metadata.request_count == 0
      assert metadata.error_count == 0
    end
    
    test "reports unhealthy when circuit is open" do
      {:ok, state} = TestAdapter.init([])
      state = put_in(state, [:circuit_breaker, :state], :open)
      
      {status, _metadata} = TestAdapter.health_check(state)
      
      assert status == :unhealthy
    end
  end
  
  describe "context enrichment" do
    test "enriches context with adapter metadata" do
      context = %{user_id: "123"}
      metadata = %{source: "test"}
      
      enriched = TestAdapter.enrich_context(context, metadata)
      
      assert enriched.user_id == "123"
      assert enriched.adapter == TestAdapter
      assert enriched.adapter_metadata == metadata
      assert %DateTime{} = enriched.timestamp
    end
  end
  
  describe "rate limiting" do
    test "allows requests under limit" do
      assert :ok = TestAdapter.check_rate_limit("test_key", 5, 60_000)
      assert :ok = TestAdapter.check_rate_limit("test_key", 5, 60_000)
    end
    
    test "blocks requests over limit" do
      key = "limit_test_#{:rand.uniform(1000)}"
      
      # Use up the limit
      for _i <- 1..5 do
        assert :ok = TestAdapter.check_rate_limit(key, 5, 60_000)
      end
      
      # Next request should be blocked
      assert {:error, :rate_limit_exceeded} = 
        TestAdapter.check_rate_limit(key, 5, 60_000)
    end
  end
end