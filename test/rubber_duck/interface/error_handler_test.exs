defmodule RubberDuck.Interface.ErrorHandlerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.ErrorHandler
  
  describe "create_error/4" do
    test "creates standardized error with metadata" do
      error = ErrorHandler.create_error(
        :validation_error,
        "Missing required field",
        %{field: :operation},
        %{request_id: "req_123"}
      )
      
      assert {:error, :validation_error, "Missing required field", metadata} = error
      assert metadata.field == :operation
      assert metadata.category == :validation_error
      assert metadata.severity == :low
      assert metadata.request_id == "req_123"
      assert %DateTime{} = metadata.timestamp
    end
    
    test "determines correct severity for different categories" do
      {:error, _, _, metadata1} = ErrorHandler.create_error(:validation_error, "test")
      assert metadata1.severity == :low
      
      {:error, _, _, metadata2} = ErrorHandler.create_error(:authentication_error, "test")
      assert metadata2.severity == :high
      
      {:error, _, _, metadata3} = ErrorHandler.create_error(:internal_error, "test")
      assert metadata3.severity == :critical
    end
  end
  
  describe "transform_error/3" do
    test "transforms error for CLI interface" do
      error = {:error, :validation_error, "Missing parameter", %{}}
      
      transformed = ErrorHandler.transform_error(error, :cli)
      
      assert transformed.category == :validation_error
      assert transformed.exit_code == 64
      assert String.contains?(transformed.message, "Validation error - Missing parameter")
    end
    
    test "transforms error for web interface" do
      error = {:error, :not_found, "Resource not found", %{resource_id: "123"}}
      
      transformed = ErrorHandler.transform_error(error, :web, include_details: true)
      
      assert transformed.error.type == :not_found
      assert transformed.error.message == "Resource not found"
      assert transformed.error.status == 404
      assert transformed.error.details.resource_id == "123"
    end
    
    test "transforms error for LSP interface" do
      error = {:error, :unsupported_operation, "Method not supported", %{}}
      
      transformed = ErrorHandler.transform_error(error, :lsp)
      
      assert transformed.code == -32601
      assert transformed.message == "Method not supported"
      assert is_map(transformed.data)
    end
    
    test "transforms generic error format" do
      error = {:error, :timeout, "Request timed out", %{duration: 30000}}
      
      transformed = ErrorHandler.transform_error(error, :generic)
      
      assert transformed.type == :timeout
      assert transformed.message == "Request timed out"
      assert transformed.metadata.duration == 30000
    end
    
    test "normalizes non-standard error formats" do
      error = {:error, "Simple error message"}
      
      transformed = ErrorHandler.transform_error(error, :cli)
      
      assert transformed.category == :internal_error
      assert String.contains?(transformed.message, "Simple error message")
    end
  end
  
  describe "error_to_response/3" do
    test "generates error response" do
      error = {:error, :validation_error, "Invalid input", %{severity: :low}}
      
      response = ErrorHandler.error_to_response(error, "req_123", %{custom: "metadata"})
      
      assert response.id == "req_123"
      assert response.status == :error
      assert {category, message, _} = response.data
      assert category == :validation_error
      assert message == "Invalid input"
      assert response.metadata.error_category == :validation_error
      assert response.metadata.error_severity == :low
      assert response.metadata.custom == "metadata"
    end
  end
  
  describe "wrap_exception/2" do
    test "wraps ArgumentError" do
      exception = %ArgumentError{message: "invalid argument"}
      
      error = ErrorHandler.wrap_exception(exception, %{request_id: "req_123"})
      
      assert {:error, :validation_error, message, metadata} = error
      assert String.contains?(message, "invalid argument")
      assert metadata.exception_type == "ArgumentError"
      assert metadata.request_id == "req_123"
    end
    
    test "wraps RuntimeError" do
      exception = %RuntimeError{message: "something went wrong"}
      
      error = ErrorHandler.wrap_exception(exception)
      
      assert {:error, :internal_error, "something went wrong", metadata} = error
      assert metadata.exception_type == "RuntimeError"
    end
    
    test "wraps unknown exception" do
      exception = %Jason.DecodeError{data: "invalid json"}
      
      error = ErrorHandler.wrap_exception(exception)
      
      assert {:error, :validation_error, message, metadata} = error
      assert String.contains?(message, "JSON decode error")
      assert metadata.exception_type == "JSON DecodeError"
    end
  end
  
  describe "retryable?/1" do
    test "identifies retryable errors" do
      assert ErrorHandler.retryable?({:error, :timeout, "", %{}})
      assert ErrorHandler.retryable?({:error, :network_error, "", %{}})
      assert ErrorHandler.retryable?({:error, :dependency_error, "", %{}})
      assert ErrorHandler.retryable?({:error, :rate_limit, "", %{}})
      assert ErrorHandler.retryable?({:error, :internal_error, "", %{}})
    end
    
    test "identifies non-retryable errors" do
      refute ErrorHandler.retryable?({:error, :validation_error, "", %{}})
      refute ErrorHandler.retryable?({:error, :authentication_error, "", %{}})
      refute ErrorHandler.retryable?({:error, :authorization_error, "", %{}})
      refute ErrorHandler.retryable?({:error, :not_found, "", %{}})
      refute ErrorHandler.retryable?({:error, :unsupported_operation, "", %{}})
    end
  end
  
  describe "retry_delay/2" do
    test "calculates delay for different error types" do
      timeout_error = {:error, :timeout, "", %{}}
      rate_limit_error = {:error, :rate_limit, "", %{}}
      network_error = {:error, :network_error, "", %{}}
      
      # First attempt
      assert ErrorHandler.retry_delay(timeout_error, 1) >= 5000
      assert ErrorHandler.retry_delay(rate_limit_error, 1) >= 60000
      assert ErrorHandler.retry_delay(network_error, 1) >= 2000
      
      # Second attempt should be longer (exponential backoff)
      delay_1 = ErrorHandler.retry_delay(timeout_error, 1)
      delay_2 = ErrorHandler.retry_delay(timeout_error, 2)
      assert delay_2 > delay_1
    end
  end
  
  describe "CLI error formatting" do
    test "formats CLI error with color" do
      error = {:error, :validation_error, "Missing parameter", %{}}
      
      formatted = ErrorHandler.transform_error(error, :cli, colorize: true)
      
      assert String.contains?(formatted.message, "\e[31mError:\e[0m")
      assert String.contains?(formatted.message, "Validation error - Missing parameter")
    end
    
    test "formats CLI error without color" do
      error = {:error, :timeout, "Request timed out", %{}}
      
      formatted = ErrorHandler.transform_error(error, :cli, colorize: false)
      
      assert String.starts_with?(formatted.message, "Error:")
      refute String.contains?(formatted.message, "\e[")
      assert formatted.exit_code == 75
    end
    
    test "includes stack trace when requested" do
      error = {:error, :internal_error, "Something broke", %{
        stacktrace: [{:module, :function, 1, [file: 'test.ex', line: 10]}]
      }}
      
      formatted = ErrorHandler.transform_error(error, :cli, include_stack_trace: true)
      
      assert Map.has_key?(formatted, :stacktrace)
      assert is_binary(formatted.stacktrace)
    end
  end
  
  describe "Web error formatting" do
    test "formats web error with details" do
      error = {:error, :not_found, "User not found", %{user_id: "123", severity: :low}}
      
      formatted = ErrorHandler.transform_error(error, :web, include_details: true)
      
      assert formatted.error.type == :not_found
      assert formatted.error.status == 404
      assert formatted.error.details.user_id == "123"
      refute Map.has_key?(formatted.error.details, :severity)  # Internal metadata filtered
    end
    
    test "formats web error without details" do
      error = {:error, :authentication_error, "Invalid token", %{token_type: "Bearer"}}
      
      formatted = ErrorHandler.transform_error(error, :web, include_details: false)
      
      assert formatted.error.type == :authentication_error
      assert formatted.error.status == 401
      refute Map.has_key?(formatted.error, :details)
    end
  end
  
  describe "LSP error formatting" do
    test "formats LSP error with custom data" do
      error = {:error, :validation_error, "Invalid position", %{
        lsp_data: %{line: 10, character: 5}
      }}
      
      formatted = ErrorHandler.transform_error(error, :lsp)
      
      assert formatted.code == -32602
      assert formatted.message == "Invalid position"
      assert formatted.data.line == 10
      assert formatted.data.character == 5
    end
  end
  
  describe "error categorization" do
    test "maps HTTP status codes correctly" do
      assert ErrorHandler.transform_error({:error, :validation_error, "", %{}}, :web).error.status == 400
      assert ErrorHandler.transform_error({:error, :authentication_error, "", %{}}, :web).error.status == 401
      assert ErrorHandler.transform_error({:error, :authorization_error, "", %{}}, :web).error.status == 403
      assert ErrorHandler.transform_error({:error, :not_found, "", %{}}, :web).error.status == 404
      assert ErrorHandler.transform_error({:error, :timeout, "", %{}}, :web).error.status == 408
      assert ErrorHandler.transform_error({:error, :rate_limit, "", %{}}, :web).error.status == 429
      assert ErrorHandler.transform_error({:error, :internal_error, "", %{}}, :web).error.status == 500
    end
    
    test "maps CLI exit codes correctly" do
      assert ErrorHandler.transform_error({:error, :validation_error, "", %{}}, :cli).exit_code == 64
      assert ErrorHandler.transform_error({:error, :authentication_error, "", %{}}, :cli).exit_code == 77
      assert ErrorHandler.transform_error({:error, :not_found, "", %{}}, :cli).exit_code == 66
      assert ErrorHandler.transform_error({:error, :internal_error, "", %{}}, :cli).exit_code == 70
    end
    
    test "maps LSP error codes correctly" do
      assert ErrorHandler.transform_error({:error, :validation_error, "", %{}}, :lsp).code == -32602
      assert ErrorHandler.transform_error({:error, :not_found, "", %{}}, :lsp).code == -32601
      assert ErrorHandler.transform_error({:error, :internal_error, "", %{}}, :lsp).code == -32603
    end
  end
end