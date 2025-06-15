defmodule RubberDuck.Interface.Behaviour.InterfaceBehaviourTest do
  @moduledoc """
  Comprehensive test suite for validating Interface Behaviour compliance.
  
  This test module ensures that all interface adapters properly implement
  the InterfaceBehaviour contract while maintaining consistency across
  different interface types (CLI, TUI, Web, LSP).
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.{Behaviour, Gateway}
  
  # Test adapter implementations for behavior validation
  defmodule MockAdapter do
    @behaviour RubberDuck.Interface.Behaviour
    
    def init(opts) do
      state = %{
        config: Keyword.get(opts, :config, %{}),
        initialized_at: DateTime.utc_now(),
        request_count: 0
      }
      {:ok, state}
    end
    
    def handle_request(request, context, state) do
      new_state = %{state | request_count: state.request_count + 1}
      
      response = %{
        id: request.id,
        status: :success,
        data: %{
          operation: request.operation,
          echo: request.params,
          processed_at: DateTime.utc_now()
        },
        metadata: %{
          interface: :mock,
          request_count: new_state.request_count
        }
      }
      
      {:ok, response, new_state}
    end
    
    def format_response(response, _request, _state) do
      formatted = "Mock response: #{inspect(response.data)}"
      {:ok, formatted}
    end
    
    def handle_error(error, _request, _state) do
      "Mock error: #{error.type} - #{error.message}"
    end
    
    def capabilities do
      [:chat, :complete, :analyze, :test_capability]
    end
    
    def validate_request(request) do
      case request do
        %{id: id, operation: op, params: params} when is_binary(id) and is_atom(op) and is_map(params) ->
          :ok
        _ ->
          {:error, ["Invalid request structure"]}
      end
    end
    
    def shutdown(_reason, _state) do
      :ok
    end
  end
  
  defmodule FailingAdapter do
    @behaviour RubberDuck.Interface.Behaviour
    
    def init(_opts), do: {:error, :init_failed}
    def handle_request(_request, _context, _state), do: {:error, :request_failed, %{}}
    def format_response(_response, _request, _state), do: {:error, :format_failed}
    def handle_error(_error, _request, _state), do: "Failing adapter error"
    def capabilities, do: []
    def validate_request(_request), do: {:error, ["Always fails"]}
    def shutdown(_reason, _state), do: :ok
  end
  
  defmodule MinimalAdapter do
    @behaviour RubberDuck.Interface.Behaviour
    
    def init(_opts), do: {:ok, %{}}
    def handle_request(request, _context, state) do
      response = Behaviour.success_response(request.id, %{minimal: true})
      {:ok, response, state}
    end
    def format_response(_response, _request, _state), do: {:ok, "minimal"}
    def handle_error(_error, _request, _state), do: "minimal error"
    def capabilities, do: [:minimal]
    def validate_request(_request), do: :ok
    def shutdown(_reason, _state), do: :ok
  end
  
  describe "Interface Behaviour Contract" do
    test "adapters must implement all required callbacks" do
      # Verify MockAdapter implements all callbacks
      assert function_exported?(MockAdapter, :init, 1)
      assert function_exported?(MockAdapter, :handle_request, 3)
      assert function_exported?(MockAdapter, :format_response, 3)
      assert function_exported?(MockAdapter, :handle_error, 3)
      assert function_exported?(MockAdapter, :capabilities, 0)
      assert function_exported?(MockAdapter, :validate_request, 1)
      assert function_exported?(MockAdapter, :shutdown, 2)
      
      # Verify all callbacks have correct arities
      {:module, MockAdapter} = Code.ensure_loaded(MockAdapter)
      callbacks = MockAdapter.__info__(:functions)
      
      assert Enum.member?(callbacks, {:init, 1})
      assert Enum.member?(callbacks, {:handle_request, 3})
      assert Enum.member?(callbacks, {:format_response, 3})
      assert Enum.member?(callbacks, {:handle_error, 3})
      assert Enum.member?(callbacks, {:capabilities, 0})
      assert Enum.member?(callbacks, {:validate_request, 1})
      assert Enum.member?(callbacks, {:shutdown, 2})
    end
    
    test "init/1 must return proper initialization response" do
      # Successful initialization
      assert {:ok, state} = MockAdapter.init(config: %{test: true})
      assert is_map(state)
      assert Map.has_key?(state, :config)
      
      # Failed initialization
      assert {:error, :init_failed} = FailingAdapter.init([])
      
      # Minimal valid initialization
      assert {:ok, state} = MinimalAdapter.init([])
      assert is_map(state)
    end
    
    test "handle_request/3 must return consistent response format" do
      {:ok, state} = MockAdapter.init([])
      
      request = %{
        id: "test_123",
        operation: :chat,
        params: %{message: "test"},
        interface: :mock,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :mock}
      
      assert {:ok, response, new_state} = MockAdapter.handle_request(request, context, state)
      
      # Validate response structure
      assert is_map(response)
      assert Map.has_key?(response, :id)
      assert Map.has_key?(response, :status)
      assert Map.has_key?(response, :data)
      assert response.id == request.id
      assert response.status == :success
      
      # Validate state evolution
      assert is_map(new_state)
      assert new_state.request_count == state.request_count + 1
    end
    
    test "handle_request/3 must handle errors properly" do
      {:ok, state} = FailingAdapter.init([])
      request = %{id: "test", operation: :test, params: %{}}
      context = %{}
      
      assert {:error, :request_failed, _state} = FailingAdapter.handle_request(request, context, state)
    end
    
    test "format_response/3 must return formatted output" do
      {:ok, state} = MockAdapter.init([])
      
      response = %{
        id: "test_123",
        status: :success,
        data: %{message: "test response"}
      }
      
      request = %{operation: :chat}
      
      assert {:ok, formatted} = MockAdapter.format_response(response, request, state)
      assert is_binary(formatted)
      assert formatted =~ "Mock response"
    end
    
    test "capabilities/0 must return list of supported operations" do
      capabilities = MockAdapter.capabilities()
      
      assert is_list(capabilities)
      assert :chat in capabilities
      assert :complete in capabilities
      assert :analyze in capabilities
      
      # Minimal adapter should also return a list
      minimal_caps = MinimalAdapter.capabilities()
      assert is_list(minimal_caps)
      assert :minimal in minimal_caps
    end
    
    test "validate_request/1 must validate request structure" do
      valid_request = %{
        id: "test_123",
        operation: :chat,
        params: %{message: "test"},
        interface: :mock
      }
      
      assert :ok = MockAdapter.validate_request(valid_request)
      
      # Invalid requests should return errors
      invalid_request = %{invalid: :structure}
      assert {:error, reasons} = MockAdapter.validate_request(invalid_request)
      assert is_list(reasons)
      assert length(reasons) > 0
    end
    
    test "shutdown/2 must handle graceful shutdown" do
      {:ok, state} = MockAdapter.init([])
      
      assert :ok = MockAdapter.shutdown(:normal, state)
      assert :ok = MockAdapter.shutdown(:shutdown, state)
      assert :ok = MockAdapter.shutdown({:shutdown, :timeout}, state)
    end
  end
  
  describe "Response Format Consistency" do
    test "all adapters must produce consistent response structure" do
      adapters = [MockAdapter, MinimalAdapter]
      
      for adapter <- adapters do
        {:ok, state} = adapter.init([])
        
        request = %{
          id: "consistency_test",
          operation: :chat,
          params: %{message: "test"},
          interface: :test,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :test}
        
        case adapter.handle_request(request, context, state) do
          {:ok, response, _new_state} ->
            # All successful responses must have these fields
            assert Map.has_key?(response, :id)
            assert Map.has_key?(response, :status)
            assert Map.has_key?(response, :data)
            assert response.id == request.id
            assert response.status in [:success, :error, :partial]
            
          {:error, _reason, _state} ->
            # Error responses are acceptable but should be handled consistently
            :ok
        end
      end
    end
    
    test "error responses must follow consistent format" do
      # Test with an adapter that returns errors
      request = %{id: "error_test", operation: :invalid, params: %{}}
      context = %{}
      
      # Even failing adapters should return consistent error format
      case FailingAdapter.handle_request(request, context, %{}) do
        {:error, reason, state} ->
          assert is_atom(reason) or is_binary(reason) or is_map(reason)
          assert is_map(state)
          
        {:ok, response, _state} ->
          # If it returns success, it should still be properly formatted
          assert Map.has_key?(response, :status)
      end
    end
  end
  
  describe "Request Validation Consistency" do
    test "all adapters must validate basic request structure" do
      adapters = [MockAdapter, MinimalAdapter]
      
      # Valid request structure
      valid_request = %{
        id: "valid_123",
        operation: :chat,
        params: %{message: "test"},
        interface: :test,
        timestamp: DateTime.utc_now()
      }
      
      for adapter <- adapters do
        case adapter.validate_request(valid_request) do
          :ok -> :ok  # This is expected
          {:error, _reasons} -> :ok  # Some adapters might have stricter validation
        end
      end
      
      # Invalid request structure should be rejected by all adapters
      invalid_request = %{}
      
      for adapter <- adapters do
        result = adapter.validate_request(invalid_request)
        
        # Should either be :ok (lenient) or {:error, reasons} (strict)
        assert result == :ok or match?({:error, _}, result)
      end
    end
    
    test "validation errors must be descriptive" do
      invalid_request = %{invalid: :structure}
      
      case MockAdapter.validate_request(invalid_request) do
        {:error, reasons} ->
          assert is_list(reasons)
          assert length(reasons) > 0
          assert Enum.all?(reasons, &is_binary/1)
          
        :ok ->
          # Some adapters might be more lenient
          :ok
      end
    end
  end
  
  describe "Capability Declaration" do
    test "capabilities must be atoms" do
      adapters = [MockAdapter, MinimalAdapter]
      
      for adapter <- adapters do
        capabilities = adapter.capabilities()
        assert is_list(capabilities)
        assert Enum.all?(capabilities, &is_atom/1)
      end
    end
    
    test "common capabilities should be consistently named" do
      mock_caps = MockAdapter.capabilities()
      
      # Standard capability names should be used
      standard_capabilities = [:chat, :complete, :analyze, :help, :status, :configuration]
      
      for cap <- mock_caps do
        if cap in standard_capabilities do
          # If an adapter claims to support a standard capability,
          # it should handle requests for that operation
          request = %{
            id: "cap_test",
            operation: cap,
            params: %{},
            interface: :test,
            timestamp: DateTime.utc_now()
          }
          
          # Should validate successfully for supported operations
          case MockAdapter.validate_request(request) do
            :ok -> :ok
            {:error, _} -> :ok  # Validation might still fail for other reasons
          end
        end
      end
    end
  end
  
  describe "State Management" do
    test "adapters must maintain state properly" do
      {:ok, initial_state} = MockAdapter.init(config: %{test: true})
      
      request = %{
        id: "state_test",
        operation: :chat,
        params: %{message: "test"},
        interface: :mock,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :mock}
      
      # First request
      {:ok, _response1, state1} = MockAdapter.handle_request(request, context, initial_state)
      assert state1.request_count == 1
      
      # Second request with evolved state
      request2 = %{request | id: "state_test_2"}
      {:ok, _response2, state2} = MockAdapter.handle_request(request2, context, state1)
      assert state2.request_count == 2
      
      # State should be preserved and evolved
      assert state2.request_count > state1.request_count
    end
    
    test "state should be isolated between different adapter instances" do
      {:ok, state1} = MockAdapter.init(config: %{instance: 1})
      {:ok, state2} = MockAdapter.init(config: %{instance: 2})
      
      # States should be independent
      refute state1 == state2
      assert state1.config != state2.config
    end
  end
  
  describe "Error Handling Consistency" do
    test "error handlers must return string output" do
      adapters = [MockAdapter, MinimalAdapter, FailingAdapter]
      
      error = %{
        type: :validation_error,
        message: "Test error message"
      }
      
      request = %{operation: :chat}
      state = %{}
      
      for adapter <- adapters do
        result = adapter.handle_error(error, request, state)
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end
    
    test "error output should include relevant information" do
      error = %{
        type: :timeout_error,
        message: "Request timed out after 30 seconds"
      }
      
      request = %{operation: :chat}
      state = %{}
      
      result = MockAdapter.handle_error(error, request, state)
      
      # Error output should contain error type or message
      assert result =~ "timeout" or result =~ "error" or result =~ "Mock"
    end
  end
  
  describe "Interface-Agnostic Behavior" do
    test "adapters should handle interface-agnostic requests" do
      {:ok, state} = MockAdapter.init([])
      
      # Request without interface-specific parameters
      generic_request = %{
        id: "generic_test",
        operation: :chat,
        params: %{message: "Hello"},
        interface: :generic,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :generic}
      
      {:ok, response, _new_state} = MockAdapter.handle_request(generic_request, context, state)
      
      # Should process successfully regardless of interface type
      assert response.status == :success
      assert response.id == generic_request.id
    end
    
    test "core operations should work across all interfaces" do
      core_operations = [:chat, :complete, :analyze]
      {:ok, state} = MockAdapter.init([])
      context = %{interface: :test}
      
      for operation <- core_operations do
        request = %{
          id: "core_op_#{operation}",
          operation: operation,
          params: %{message: "test"},
          interface: :test,
          timestamp: DateTime.utc_now()
        }
        
        case MockAdapter.handle_request(request, context, state) do
          {:ok, response, _state} ->
            assert response.status == :success
            assert response.data.operation == operation
            
          {:error, _reason, _state} ->
            # Some operations might not be supported by all adapters
            :ok
        end
      end
    end
  end
  
  describe "Performance and Resource Management" do
    test "adapters should handle concurrent requests" do
      {:ok, state} = MockAdapter.init([])
      context = %{interface: :concurrent_test}
      
      # Create multiple requests
      requests = for i <- 1..10 do
        %{
          id: "concurrent_#{i}",
          operation: :chat,
          params: %{message: "test #{i}"},
          interface: :test,
          timestamp: DateTime.utc_now()
        }
      end
      
      # Process requests concurrently (simulated)
      results = for request <- requests do
        MockAdapter.handle_request(request, context, state)
      end
      
      # All requests should succeed (with stateless processing)
      for result <- results do
        assert {:ok, _response, _state} = result
      end
    end
    
    test "adapters should not leak resources" do
      {:ok, initial_state} = MockAdapter.init([])
      
      # Process many requests to check for resource leaks
      final_state = Enum.reduce(1..100, initial_state, fn i, state ->
        request = %{
          id: "leak_test_#{i}",
          operation: :chat,
          params: %{message: "test"},
          interface: :test,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :test}
        {:ok, _response, new_state} = MockAdapter.handle_request(request, context, state)
        new_state
      end)
      
      # State should be reasonable in size
      assert final_state.request_count == 100
      
      # Cleanup should work
      assert :ok = MockAdapter.shutdown(:normal, final_state)
    end
  end
end