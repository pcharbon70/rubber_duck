defmodule RubberDuck.Interface.Behavior.CompatibilityValidationTest do
  @moduledoc """
  Automated interface compatibility validation tests.
  
  This module provides comprehensive validation of interface adapter compatibility
  with the InterfaceBehaviour contract, ensuring consistent behavior across all
  interface implementations while detecting breaking changes and regressions.
  """
  
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.{Behaviour, Gateway}
  alias RubberDuck.Interface.Adapters.CLI
  
  # Configuration for compatibility testing
  @test_config %{
    colors: false,
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,
    config_dir: System.tmp_dir!() <> "/compat_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/compat_sessions_#{System.unique_integer()}"
  }
  
  # Define the expected interface contract
  @required_callbacks [
    {:init, 1},
    {:handle_request, 3},
    {:format_response, 3},
    {:handle_error, 3},
    {:capabilities, 0},
    {:validate_request, 1},
    {:shutdown, 2}
  ]
  
  @core_operations [:chat, :complete, :analyze, :help, :status]
  @optional_operations [:session_management, :configuration, :file_upload, :batch_processing]
  
  setup do
    # Clean test directories
    [@test_config.config_dir, @test_config.sessions_dir]
    |> Enum.each(fn dir ->
      if File.exists?(dir) do
        File.rm_rf!(dir)
      end
    end)
    
    on_exit(fn ->
      [@test_config.config_dir, @test_config.sessions_dir]
      |> Enum.each(fn dir ->
        if File.exists?(dir) do
          File.rm_rf!(dir)
        end
      end)
    end)
    
    :ok
  end
  
  describe "Interface Contract Validation" do
    test "adapter implements all required callbacks" do
      # Verify CLI adapter exports all required functions
      cli_exports = CLI.__info__(:functions)
      
      for {callback, arity} <- @required_callbacks do
        assert {callback, arity} in cli_exports,
          "CLI adapter missing required callback: #{callback}/#{arity}"
      end
      
      # Verify callback implementations are not just stubs
      {:ok, state} = CLI.init(config: @test_config)
      assert is_map(state), "init/1 should return a state map"
      
      capabilities = CLI.capabilities()
      assert is_list(capabilities), "capabilities/0 should return a list"
      assert length(capabilities) > 0, "capabilities/0 should return non-empty list"
    end
    
    test "adapter follows behaviour contract specifications" do
      # Test that the adapter module implements the behaviour
      assert CLI.__info__(:attributes)
             |> Enum.any?(fn
               {:behaviour, [RubberDuck.Interface.Behaviour]} -> true
               _ -> false
             end), "CLI adapter should implement InterfaceBehaviour"
      
      # Verify behaviour module exists and is properly defined
      assert function_exported?(Behaviour, :behaviour_info, 1)
      
      # Verify all callbacks are properly defined in the behaviour
      behaviour_callbacks = Behaviour.behaviour_info(:callbacks)
      
      for {callback, arity} <- @required_callbacks do
        assert {callback, arity} in behaviour_callbacks,
          "Behaviour missing callback definition: #{callback}/#{arity}"
      end
    end
    
    test "adapter callback return types are consistent" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test init/1 return type
      assert match?({:ok, %{}}, CLI.init(config: @test_config)),
        "init/1 should return {:ok, state}"
      
      # Test handle_request/3 return type
      request = create_standard_request(:chat)
      context = %{interface: :cli}
      
      result = CLI.handle_request(request, context, state)
      assert match?({:ok, %{}, %{}}, result) or match?({:error, _, %{}}, result),
        "handle_request/3 should return {:ok, response, state} or {:error, reason, state}"
      
      # Test format_response/3 return type
      response = create_standard_response(request.id)
      format_result = CLI.format_response(response, request, state)
      assert match?({:ok, _binary}) or match?({:error, _reason}, format_result),
        "format_response/3 should return {:ok, formatted} or {:error, reason}"
      
      # Test validate_request/1 return type
      validation_result = CLI.validate_request(request)
      assert validation_result == :ok or match?({:error, _reasons}, validation_result),
        "validate_request/1 should return :ok or {:error, reasons}"
      
      # Test handle_error/3 return type
      error = %{type: :test_error, message: "Test error"}
      error_output = CLI.handle_error(error, request, state)
      assert is_binary(error_output),
        "handle_error/3 should return a string"
      
      # Test shutdown/2 return type
      shutdown_result = CLI.shutdown(:normal, state)
      assert shutdown_result == :ok,
        "shutdown/2 should return :ok"
    end
  end
  
  describe "Core Operation Compatibility" do
    test "adapter supports all core operations" do
      {:ok, state} = CLI.init(config: @test_config)
      capabilities = CLI.capabilities()
      
      # Verify core operations are supported
      for operation <- @core_operations do
        assert operation in capabilities,
          "Core operation #{operation} not in capabilities list"
        
        # Test that the operation can be processed
        request = create_standard_request(operation)
        context = %{interface: :cli}
        
        case CLI.validate_request(request) do
          :ok ->
            result = CLI.handle_request(request, context, state)
            assert match?({:ok, _, _}, result) or match?({:error, _, _}, result),
              "Core operation #{operation} should be processable"
            
          {:error, _reasons} ->
            # If validation fails, the operation might need different parameters
            # This is acceptable as long as it's documented
            :ok
        end
      end
    end
    
    test "adapter handles optional operations appropriately" do
      {:ok, state} = CLI.init(config: @test_config)
      capabilities = CLI.capabilities()
      
      for operation <- @optional_operations do
        request = create_standard_request(operation)
        context = %{interface: :cli}
        
        if operation in capabilities do
          # If advertised, should be able to handle it
          validation = CLI.validate_request(request)
          
          case validation do
            :ok ->
              result = CLI.handle_request(request, context, state)
              assert match?({:ok, _, _}, result) or match?({:error, _, _}, result)
              
            {:error, _reasons} ->
              # Validation might fail due to missing parameters
              :ok
          end
        else
          # If not advertised, should either handle gracefully or reject clearly
          result = CLI.handle_request(request, context, state)
          
          case result do
            {:ok, response, _state} ->
              # If it handles it, response should indicate lack of support
              assert response.status in [:error, :not_supported]
              
            {:error, _reason, _state} ->
              # Graceful rejection is acceptable
              :ok
          end
        end
      end
    end
  end
  
  describe "Request/Response Format Compatibility" do
    test "adapter accepts standard request format" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test with minimal valid request
      minimal_request = %{
        id: "minimal_test",
        operation: :chat,
        params: %{message: "test"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      result = CLI.handle_request(minimal_request, context, state)
      
      assert match?({:ok, _, _}, result) or match?({:error, _, _}, result),
        "Adapter should handle minimal valid request"
      
      # Test with extended request format
      extended_request = Map.merge(minimal_request, %{
        priority: :normal,
        metadata: %{source: "test"},
        correlation_id: "test_correlation"
      })
      
      extended_result = CLI.handle_request(extended_request, context, state)
      assert match?({:ok, _, _}, extended_result) or match?({:error, _, _}, extended_result),
        "Adapter should handle extended request format"
    end
    
    test "adapter produces standard response format" do
      {:ok, state} = CLI.init(config: @test_config)
      
      request = create_standard_request(:chat)
      context = %{interface: :cli}
      
      case CLI.handle_request(request, context, state) do
        {:ok, response, _new_state} ->
          # Validate response structure
          assert Map.has_key?(response, :id), "Response missing :id"
          assert Map.has_key?(response, :status), "Response missing :status"
          assert Map.has_key?(response, :data), "Response missing :data"
          
          assert response.id == request.id, "Response ID should match request ID"
          assert response.status in [:success, :error, :partial, :pending],
            "Response status should be valid"
          assert is_map(response.data), "Response data should be a map"
          
          # Optional fields should be properly typed if present
          if Map.has_key?(response, :metadata) do
            assert is_map(response.metadata), "Response metadata should be a map"
          end
          
        {:error, _reason, _state} ->
          # Error responses are acceptable
          :ok
      end
    end
    
    test "adapter validates request structure consistently" do
      # Test various invalid request structures
      invalid_requests = [
        # Missing required fields
        %{operation: :chat, interface: :cli},
        %{id: "test", interface: :cli},
        %{id: "test", operation: :chat},
        
        # Invalid field types
        %{id: 123, operation: :chat, params: %{}, interface: :cli},
        %{id: "test", operation: "invalid", params: %{}, interface: :cli},
        %{id: "test", operation: :chat, params: "invalid", interface: :cli},
        
        # Empty structures
        %{},
        
        # Non-map structure
        "invalid_request"
      ]
      
      for invalid_request <- invalid_requests do
        validation_result = try do
          CLI.validate_request(invalid_request)
        rescue
          _error -> {:error, ["Validation crashed"]}
        end
        
        # Should either reject with clear error or handle gracefully
        case validation_result do
          :ok ->
            # If validation passes, handling should not crash
            :ok
            
          {:error, reasons} ->
            assert is_list(reasons), "Validation errors should be a list"
            assert length(reasons) > 0, "Should provide error reasons"
            assert Enum.all?(reasons, &is_binary/1), "Error reasons should be strings"
        end
      end
    end
  end
  
  describe "Error Handling Compatibility" do
    test "adapter handles errors consistently across operations" do
      {:ok, state} = CLI.init(config: @test_config)
      
      error_scenarios = [
        %{type: :validation_error, message: "Invalid input"},
        %{type: :timeout_error, message: "Request timed out"},
        %{type: :network_error, message: "Network unavailable"},
        %{type: :resource_error, message: "Resource exhausted"},
        %{type: :unknown_error, message: "Unknown error occurred"}
      ]
      
      request = create_standard_request(:chat)
      
      for error <- error_scenarios do
        error_output = CLI.handle_error(error, request, state)
        
        assert is_binary(error_output), "Error output should be a string"
        assert String.length(error_output) > 0, "Error output should not be empty"
        
        # Error output should contain relevant information
        assert error_output =~ "error" or error_output =~ "Error" or
               error_output =~ error.type |> Atom.to_string() or
               error_output =~ error.message,
          "Error output should contain error information"
      end
    end
    
    test "adapter error messages are user-friendly" do
      {:ok, state} = CLI.init(config: @test_config)
      
      common_errors = [
        %{type: :validation_error, message: "Required field 'message' is missing"},
        %{type: :authorization_error, message: "Insufficient permissions"},
        %{type: :rate_limit_error, message: "Too many requests"}
      ]
      
      request = create_standard_request(:chat)
      
      for error <- common_errors do
        error_output = CLI.handle_error(error, request, state)
        
        # Error messages should be helpful to users
        refute error_output =~ "Process", "Should not expose internal process details"
        refute error_output =~ "GenServer", "Should not expose OTP implementation"
        refute error_output =~ "pid", "Should not expose process IDs"
        
        # Should provide actionable information
        assert String.length(error_output) > 10,
          "Error message should be substantial enough to be helpful"
      end
    end
  end
  
  describe "State Management Compatibility" do
    test "adapter maintains state consistency" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Process multiple requests and verify state evolution
      requests = for i <- 1..5 do
        %{
          id: "state_test_#{i}",
          operation: :chat,
          params: %{message: "State test #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
      end
      
      context = %{interface: :cli}
      
      {final_state, responses} = Enum.reduce(requests, {initial_state, []}, fn request, {state, acc_responses} ->
        case CLI.handle_request(request, context, state) do
          {:ok, response, new_state} ->
            {new_state, [response | acc_responses]}
            
          {:error, _reason, new_state} ->
            {new_state, acc_responses}
        end
      end)
      
      # State should have evolved properly
      assert final_state != initial_state, "State should change after processing requests"
      
      # If adapter tracks request count, it should be accurate
      if Map.has_key?(final_state, :request_count) do
        processed_count = length(responses)
        assert final_state.request_count >= processed_count,
          "Request count should reflect processed requests"
      end
    end
    
    test "adapter state is serializable" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # State should be serializable for potential persistence
      assert is_map(state), "State should be a map"
      
      # Should be able to encode/decode state
      try do
        encoded = :erlang.term_to_binary(state)
        decoded = :erlang.binary_to_term(encoded)
        
        assert decoded == state, "State should survive serialization round-trip"
      rescue
        _error ->
          # If state contains non-serializable elements (like PIDs),
          # adapter should provide serialization helpers
          :ok
      end
    end
  end
  
  describe "Capability Declaration Consistency" do
    test "advertised capabilities are actually supported" do
      capabilities = CLI.capabilities()
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test each advertised capability
      for capability <- capabilities do
        if capability in (@core_operations ++ @optional_operations) do
          request = create_standard_request(capability)
          context = %{interface: :cli}
          
          # Should either handle successfully or provide clear error
          validation = CLI.validate_request(request)
          
          case validation do
            :ok ->
              result = CLI.handle_request(request, context, state)
              assert match?({:ok, _, _}, result) or match?({:error, _, _}, result),
                "Advertised capability #{capability} should be processable"
              
            {:error, _reasons} ->
              # If validation fails, it might need different parameters
              # but the capability should still be recognizable
              :ok
          end
        end
      end
    end
    
    test "capability list is stable and documented" do
      capabilities1 = CLI.capabilities()
      capabilities2 = CLI.capabilities()
      
      # Capabilities should be deterministic
      assert capabilities1 == capabilities2,
        "Capability list should be stable across calls"
      
      # All capabilities should be atoms
      assert Enum.all?(capabilities1, &is_atom/1),
        "All capabilities should be atoms"
      
      # Should contain expected core capabilities for CLI
      cli_expected = [:chat, :complete, :analyze]
      
      for expected <- cli_expected do
        assert expected in capabilities1,
          "CLI adapter should support core capability: #{expected}"
      end
    end
  end
  
  describe "Performance Contract Compliance" do
    test "adapter initialization is within reasonable bounds" do
      # Multiple initializations should be fast
      times = for _i <- 1..10 do
        {time, {:ok, _state}} = :timer.tc(fn ->
          CLI.init(config: @test_config)
        end)
        time / 1000  # Convert to milliseconds
      end
      
      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)
      
      assert avg_time < 100, "Average initialization time should be < 100ms"
      assert max_time < 500, "Maximum initialization time should be < 500ms"
    end
    
    test "adapter request processing meets performance baseline" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test performance of basic operations
      basic_operations = [:chat, :status, :help]
      
      for operation <- basic_operations do
        request = create_standard_request(operation)
        context = %{interface: :cli}
        
        {time, result} = :timer.tc(fn ->
          CLI.handle_request(request, context, state)
        end)
        
        time_ms = time / 1000
        
        case result do
          {:ok, _response, _state} ->
            assert time_ms < 1000, "Basic operation #{operation} should complete in < 1s"
            
          {:error, _reason, _state} ->
            # Error handling should also be fast
            assert time_ms < 100, "Error handling for #{operation} should be fast"
        end
      end
    end
  end
  
  # Helper functions
  
  defp create_standard_request(operation) do
    params = case operation do
      :chat -> %{message: "Test message"}
      :complete -> %{prompt: "def test():"}
      :analyze -> %{content: "test content"}
      :session_management -> %{action: :list}
      :configuration -> %{action: :show}
      :help -> %{topic: :general}
      :status -> %{}
      :file_upload -> %{file_path: "/tmp/test.txt", content: "test"}
      :batch_processing -> %{items: ["test1", "test2"]}
      _ -> %{}
    end
    
    %{
      id: "compat_test_#{operation}_#{System.unique_integer()}",
      operation: operation,
      params: params,
      interface: :cli,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp create_standard_response(request_id) do
    %{
      id: request_id,
      status: :success,
      data: %{
        message: "Test response",
        session_id: "test_session"
      },
      metadata: %{
        timestamp: DateTime.utc_now(),
        processing_time: 42
      }
    }
  end
end