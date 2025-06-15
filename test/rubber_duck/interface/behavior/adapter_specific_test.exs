defmodule RubberDuck.Interface.Behavior.AdapterSpecificTest do
  @moduledoc """
  Adapter-specific test cases that validate unique functionality and optimizations
  for each interface type while ensuring they maintain behavioral consistency.
  """
  
  use ExUnit.Case, async: false  # Some tests involve real file operations
  
  alias RubberDuck.Interface.Adapters.CLI
  
  # Test configuration for isolated testing
  @test_config %{
    colors: false,
    syntax_highlight: false,
    format: "text",
    auto_save_sessions: false,
    config_dir: System.tmp_dir!() <> "/adapter_test_#{System.unique_integer()}",
    sessions_dir: System.tmp_dir!() <> "/adapter_sessions_#{System.unique_integer()}"
  }
  
  setup do
    # Clean up test directories
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
  
  describe "CLI Adapter Specific Features" do
    test "CLI adapter initializes with session manager" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # CLI should have session management capabilities
      assert Map.has_key?(state, :session_manager)
      assert Map.has_key?(state, :config)
      assert state.config.format == "text"
    end
    
    test "CLI adapter handles command-line specific operations" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test CLI-specific chat request
      request = %{
        id: "cli_chat_test",
        operation: :chat,
        params: %{
          message: "Test CLI chat",
          interactive: false
        },
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli, mode: :direct}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_binary(response.data.message)
      
      # CLI-specific response should include session info
      assert is_binary(response.data.session_id)
    end
    
    test "CLI adapter formats responses for terminal output" do
      {:ok, state} = CLI.init(config: @test_config)
      
      response = %{
        id: "format_test",
        status: :success,
        data: %{message: "Test response with formatting"},
        metadata: %{timestamp: DateTime.utc_now()}
      }
      
      request = %{operation: :chat}
      
      {:ok, formatted} = CLI.format_response(response, request, state)
      
      assert is_binary(formatted)
      assert formatted =~ "Test response"
      # With colors disabled, should not contain ANSI codes
      refute formatted =~ "\e["
    end
    
    test "CLI adapter validates CLI-specific parameters" do
      # Valid CLI request
      valid_request = %{
        id: "cli_validation_test",
        operation: :chat,
        params: %{message: "Valid message", interactive: false},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(valid_request)
      
      # Invalid CLI request (empty message in non-interactive mode)
      invalid_request = %{
        id: "cli_validation_fail",
        operation: :chat,
        params: %{message: "", interactive: false},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      # Should reject empty messages for non-interactive mode
      assert {:error, _reasons} = CLI.validate_request(invalid_request)
    end
    
    test "CLI adapter supports completion with language hints" do
      {:ok, state} = CLI.init(config: @test_config)
      
      request = %{
        id: "cli_completion_test",
        operation: :complete,
        params: %{
          prompt: "def fibonacci(n):",
          language: "python"
        },
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert is_binary(response.data.completion)
      assert response.data.completion =~ "fibonacci"
    end
    
    test "CLI adapter handles session management operations" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test session creation
      create_request = %{
        id: "session_create_test",
        operation: :session_management,
        params: %{action: :new, name: "test_session"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, new_state} = CLI.handle_request(create_request, context, state)
      
      assert response.status == :success
      assert is_map(response.data.session)
      assert response.data.session.name == "test_session"
      
      # Test session listing
      list_request = %{
        id: "session_list_test",
        operation: :session_management,
        params: %{action: :list},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, list_response, _final_state} = CLI.handle_request(list_request, context, new_state)
      
      assert list_response.status == :success
      assert is_list(list_response.data.sessions)
    end
    
    test "CLI adapter handles configuration operations" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test configuration display
      show_request = %{
        id: "config_show_test",
        operation: :configuration,
        params: %{action: :show},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(show_request, context, state)
      
      assert response.status == :success
      assert is_map(response.data.config)
      
      # Test configuration update
      set_request = %{
        id: "config_set_test",
        operation: :configuration,
        params: %{action: :set, key: "colors", value: true},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, set_response, updated_state} = CLI.handle_request(set_request, context, state)
      
      assert set_response.status == :success
      # Configuration should be updated in state
      assert updated_state.config.colors == true
    end
    
    test "CLI adapter provides comprehensive status information" do
      {:ok, state} = CLI.init(config: @test_config)
      
      request = %{
        id: "status_test",
        operation: :status,
        params: %{},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      {:ok, response, _new_state} = CLI.handle_request(request, context, state)
      
      assert response.status == :success
      assert response.data.adapter == :cli
      assert is_atom(response.data.health)
      assert is_integer(response.data.uptime)
      assert is_integer(response.data.sessions)
      assert is_integer(response.data.requests_processed)
      assert is_map(response.data.config)
    end
    
    test "CLI adapter capabilities include CLI-specific features" do
      capabilities = CLI.capabilities()
      
      assert is_list(capabilities)
      
      # Core capabilities
      assert :chat in capabilities
      assert :complete in capabilities
      assert :analyze in capabilities
      
      # CLI-specific capabilities
      assert :session_management in capabilities
      assert :interactive_mode in capabilities
      assert :configuration_management in capabilities
      assert :batch_processing in capabilities
    end
    
    test "CLI adapter handles errors with helpful suggestions" do
      {:ok, state} = CLI.init(config: @test_config)
      
      error = %{
        type: :validation_error,
        message: "Invalid input provided"
      }
      
      request = %{operation: :chat}
      
      formatted_error = CLI.handle_error(error, request, state)
      
      assert is_binary(formatted_error)
      assert formatted_error =~ "Invalid input"
      # CLI errors should be user-friendly
      assert String.length(formatted_error) > 10
    end
    
    test "CLI adapter handles shutdown gracefully" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Add some session state
      state_with_session = %{state | current_session: %{id: "test_session"}}
      
      # Should cleanup without errors
      assert :ok = CLI.shutdown(:normal, state_with_session)
      assert :ok = CLI.shutdown(:shutdown, state)
      assert :ok = CLI.shutdown({:shutdown, :timeout}, state)
    end
  end
  
  describe "Interface-Specific Validation Rules" do
    test "CLI adapter enforces CLI-specific validation" do
      # Test completion request validation
      valid_completion = %{
        id: "completion_validation",
        operation: :complete,
        params: %{prompt: "def hello():"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(valid_completion)
      
      # Empty prompt should fail
      invalid_completion = %{
        id: "completion_validation_fail",
        operation: :complete,
        params: %{prompt: ""},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert {:error, _reasons} = CLI.validate_request(invalid_completion)
      
      # Test analysis request validation
      valid_analysis = %{
        id: "analysis_validation",
        operation: :analyze,
        params: %{content: "some code to analyze"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert :ok = CLI.validate_request(valid_analysis)
      
      # Empty content should fail
      invalid_analysis = %{
        id: "analysis_validation_fail",
        operation: :analyze,
        params: %{content: ""},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      assert {:error, _reasons} = CLI.validate_request(invalid_analysis)
    end
    
    test "different adapters may have different validation rules" do
      # CLI has strict validation for some operations
      cli_request = %{
        id: "validation_comparison",
        operation: :complete,
        params: %{prompt: ""},  # Empty prompt
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      # CLI should reject empty prompts
      assert {:error, _reasons} = CLI.validate_request(cli_request)
      
      # This demonstrates that different adapters can have different validation
      # while still implementing the same behavior contract
    end
  end
  
  describe "Performance Characteristics" do
    test "CLI adapter handles multiple sequential requests efficiently" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Measure time for multiple requests
      start_time = System.monotonic_time(:millisecond)
      
      final_state = Enum.reduce(1..50, initial_state, fn i, state ->
        request = %{
          id: "perf_test_#{i}",
          operation: :chat,
          params: %{message: "Performance test #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        {:ok, _response, new_state} = CLI.handle_request(request, context, state)
        new_state
      end)
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should handle 50 requests reasonably quickly (< 5 seconds)
      assert duration < 5000
      
      # State should be properly maintained
      assert final_state.request_count == 50
    end
    
    test "CLI adapter memory usage remains stable" do
      {:ok, initial_state} = CLI.init(config: @test_config)
      
      # Process many requests to check memory stability
      final_state = Enum.reduce(1..100, initial_state, fn i, state ->
        request = %{
          id: "memory_test_#{i}",
          operation: :chat,
          params: %{message: "Memory test #{i}"},
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        {:ok, _response, new_state} = CLI.handle_request(request, context, state)
        new_state
      end)
      
      # State should not grow excessively
      state_size = :erlang.external_size(final_state)
      initial_size = :erlang.external_size(initial_state)
      
      # Allow some growth but not excessive (factor of 10 is reasonable)
      assert state_size < initial_size * 10
      
      # Request count should be tracked correctly
      assert final_state.request_count == 100
    end
  end
  
  describe "Error Recovery and Resilience" do
    test "CLI adapter recovers from session manager errors" do
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test with potentially problematic session operation
      request = %{
        id: "error_recovery_test",
        operation: :session_management,
        params: %{action: :switch, session_id: "nonexistent_session"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      context = %{interface: :cli}
      
      # Should handle gracefully (either succeed with fallback or fail cleanly)
      result = CLI.handle_request(request, context, state)
      
      case result do
        {:ok, _response, _new_state} -> :ok  # Handled with fallback
        {:error, _error, _new_state} -> :ok  # Failed cleanly
      end
      
      # Adapter should still be functional after error
      chat_request = %{
        id: "post_error_test",
        operation: :chat,
        params: %{message: "Still working?"},
        interface: :cli,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, _response, _final_state} = CLI.handle_request(chat_request, context, state)
    end
    
    test "CLI adapter handles malformed configuration gracefully" do
      # Test with problematic configuration
      bad_config = Map.merge(@test_config, %{
        sessions_dir: "/nonexistent/path/that/will/fail",
        config_dir: "/another/bad/path"
      })
      
      # Should either initialize successfully with fallbacks or fail cleanly
      result = CLI.init(config: bad_config)
      
      case result do
        {:ok, _state} -> 
          # Initialized with fallbacks - this is acceptable
          :ok
        {:error, _reason} -> 
          # Failed cleanly - this is also acceptable
          :ok
      end
    end
  end
  
  describe "Interface Compatibility" do
    test "CLI adapter maintains compatibility with interface behavior" do
      # Verify CLI adapter follows the interface behavior contract exactly
      {:ok, state} = CLI.init(config: @test_config)
      
      # Test all required operations that should be supported
      operations = [:chat, :complete, :analyze, :session_management, :configuration, :help, :status]
      
      for operation <- operations do
        request = %{
          id: "compatibility_test_#{operation}",
          operation: operation,
          params: get_params_for_operation(operation),
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        
        # All operations should either succeed or fail gracefully
        result = CLI.handle_request(request, context, state)
        
        case result do
          {:ok, response, _new_state} ->
            # Success response must follow contract
            assert Map.has_key?(response, :id)
            assert Map.has_key?(response, :status)
            assert Map.has_key?(response, :data)
            assert response.id == request.id
            
          {:error, _error, _new_state} ->
            # Error response is acceptable for some operations
            :ok
        end
      end
    end
    
    test "CLI adapter response formats are consistent" do
      {:ok, state} = CLI.init(config: @test_config)
      
      operations = [:chat, :complete, :analyze]
      
      for operation <- operations do
        request = %{
          id: "format_consistency_#{operation}",
          operation: operation,
          params: get_params_for_operation(operation),
          interface: :cli,
          timestamp: DateTime.utc_now()
        }
        
        context = %{interface: :cli}
        
        case CLI.handle_request(request, context, state) do
          {:ok, response, _new_state} ->
            # Test formatting
            case CLI.format_response(response, request, state) do
              {:ok, formatted} ->
                assert is_binary(formatted)
                assert String.length(formatted) > 0
                
              {:error, _reason} ->
                # Formatting might fail for some responses, but should be consistent
                :ok
            end
            
          {:error, _error, _new_state} ->
            :ok
        end
      end
    end
  end
  
  # Helper function to generate appropriate parameters for each operation
  defp get_params_for_operation(:chat), do: %{message: "Test message"}
  defp get_params_for_operation(:complete), do: %{prompt: "def test():"}
  defp get_params_for_operation(:analyze), do: %{content: "test content"}
  defp get_params_for_operation(:session_management), do: %{action: :list}
  defp get_params_for_operation(:configuration), do: %{action: :show}
  defp get_params_for_operation(:help), do: %{topic: :general}
  defp get_params_for_operation(:status), do: %{}
  defp get_params_for_operation(_), do: %{}
end