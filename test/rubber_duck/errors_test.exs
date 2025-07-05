defmodule RubberDuck.ErrorsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Errors
  alias RubberDuck.Errors.{
    RubberDuckError,
    EngineError,
    LLMError,
    ConfigurationError,
    ServiceUnavailableError
  }

  describe "RubberDuckError" do
    test "creates error with message" do
      error = RubberDuckError.exception(message: "Test error")
      assert error.message == "Test error"
      assert error.code == :unknown_error
      assert error.details == %{}
    end

    test "creates error with all fields" do
      error = RubberDuckError.exception(
        message: "Custom error",
        code: :custom_code,
        details: %{foo: "bar"}
      )
      
      assert error.message == "Custom error"
      assert error.code == :custom_code
      assert error.details == %{foo: "bar"}
    end
  end

  describe "EngineError" do
    test "creates error with default message" do
      error = EngineError.exception(engine: "test_engine", reason: "failed")
      assert error.message == "Engine test_engine error: failed"
      assert error.engine == "test_engine"
      assert error.reason == "failed"
    end

    test "creates error with custom message" do
      error = EngineError.exception(
        message: "Custom engine error",
        engine: "llm",
        input: %{prompt: "test"},
        reason: "timeout"
      )
      
      assert error.message == "Custom engine error"
      assert error.engine == "llm"
      assert error.input == %{prompt: "test"}
      assert error.reason == "timeout"
    end
  end

  describe "LLMError" do
    test "creates error with provider" do
      error = LLMError.exception(provider: "openai")
      assert error.message == "LLM provider openai returned error"
    end

    test "creates error with status code" do
      error = LLMError.exception(provider: "anthropic", status_code: 429)
      assert error.message == "LLM provider anthropic returned error (429)"
      assert error.status_code == 429
    end

    test "creates error with all fields" do
      error = LLMError.exception(
        message: "Rate limited",
        provider: "openai",
        status_code: 429,
        response: %{"error" => "rate_limit_exceeded"}
      )
      
      assert error.message == "Rate limited"
      assert error.provider == "openai"
      assert error.status_code == 429
      assert error.response == %{"error" => "rate_limit_exceeded"}
    end
  end

  describe "ConfigurationError" do
    test "creates error with key" do
      error = ConfigurationError.exception(key: :api_key)
      assert error.message == "Invalid configuration for :api_key"
    end

    test "creates error with expected and actual" do
      error = ConfigurationError.exception(
        key: :timeout,
        expected: "integer",
        actual: "string"
      )
      
      assert error.message == "Invalid configuration for :timeout"
      assert error.expected == "integer"
      assert error.actual == "string"
    end
  end

  describe "ServiceUnavailableError" do
    test "creates error with service name" do
      error = ServiceUnavailableError.exception(service: "database")
      assert error.message == "Service database is unavailable"
    end

    test "creates error with retry_after" do
      error = ServiceUnavailableError.exception(
        service: "llm_api",
        retry_after: 60
      )
      
      assert error.message == "Service llm_api is unavailable, retry after 60s"
      assert error.retry_after == 60
    end
  end

  describe "normalize_error/1" do
    test "normalizes exception" do
      error = EngineError.exception(engine: "test", reason: "failed")
      normalized = Errors.normalize_error(error)
      
      assert normalized.type == EngineError
      assert normalized.message == "Engine test error: failed"
      assert normalized.details == %{
        engine: "test",
        input: nil,
        reason: "failed"
      }
    end

    test "normalizes string error" do
      normalized = Errors.normalize_error("Something went wrong")
      
      assert normalized.type == :string_error
      assert normalized.message == "Something went wrong"
      assert normalized.details == %{}
    end

    test "normalizes unknown error" do
      normalized = Errors.normalize_error({:error, :timeout})
      
      assert normalized.type == :unknown_error
      assert normalized.message == "{:error, :timeout}"
      assert normalized.details == %{raw: {:error, :timeout}}
    end
  end

  describe "report_exception/3" do
    test "reports exception with metadata" do
      # Since we have Tower configured with no reporters in test,
      # we can't easily test the actual reporting. 
      # In a real scenario, you might mock Tower or use a test reporter.
      
      error = LLMError.exception(provider: "test", status_code: 500)
      metadata = %{user_id: "123", action: "generate"}
      
      # This should not raise
      assert :ok == Errors.report_exception(error, [], metadata)
    end
  end

  describe "report_message/3" do
    test "reports message" do
      # Similar to above, we're just ensuring it doesn't crash
      assert :ok == Errors.report_message(:error, "Test error", %{context: "test"})
    end
  end
end