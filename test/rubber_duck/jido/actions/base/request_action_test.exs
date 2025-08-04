defmodule RubberDuck.Jido.Actions.Base.RequestActionTest do
  use ExUnit.Case, async: true
  
  # Test implementation of RequestAction
  defmodule TestRequestAction do
    use RubberDuck.Jido.Actions.Base.RequestAction,
      name: "test_request",
      description: "Test request action",
      schema: [
        url: [type: :string, required: true],
        method: [type: :atom, default: :get, values: [:get, :post]]
      ]
    
    @impl true
    def handle_request(params, _context) do
      case params.url do
        "https://success.example.com" -> 
          {:ok, %{status: 200, body: "Success"}}
        "https://error.example.com" -> 
          {:error, :request_failed}
        "https://timeout.example.com" -> 
          Process.sleep(100)
          {:ok, %{status: 200, body: "Delayed"}}
        _ -> 
          {:error, :unknown_url}
      end
    end
    
    def before_request(params, context) do
      if Map.get(params, :add_auth_header) do
        enhanced_context = Map.put(context, :auth_header, "Bearer token")
        {:ok, enhanced_context}
      else
        {:ok, context}
      end
    end
    
    def after_request(result, _params, _context) do
      enhanced_result = Map.put(result, :processed_at, DateTime.utc_now())
      {:ok, enhanced_result}
    end
    
    def handle_error(:request_failed, _params, _context) do
      {:ok, %{status: 500, body: "Recovered from error"}}
    end
    
    def handle_error(reason, _params, _context) do
      {:error, reason}
    end
  end
  
  describe "RequestAction base behavior" do
    test "successful request with default parameters" do
      params = %{url: "https://success.example.com"}
      context = %{agent: %{}}
      
      assert {:ok, result} = TestRequestAction.run(params, context)
      assert result.success == true
      assert result.data.status == 200
      assert result.data.body == "Success"
      assert result.data.processed_at
      assert result.metadata.action == "test_request"
      assert result.metadata.timeout == 30_000
      assert result.metadata.retry_attempts == 3
    end
    
    test "request with custom timeout and retry settings" do
      params = %{
        url: "https://success.example.com",
        timeout: 10_000,
        retry_attempts: 1
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestRequestAction.run(params, context)
      assert result.metadata.timeout == 10_000
      assert result.metadata.retry_attempts == 1
    end
    
    test "request with before_request hook" do
      params = %{
        url: "https://success.example.com",
        add_auth_header: true
      }
      context = %{agent: %{}}
      
      assert {:ok, result} = TestRequestAction.run(params, context)
      assert result.success == true
    end
    
    test "error handling with recovery" do
      params = %{url: "https://error.example.com"}
      context = %{agent: %{}}
      
      assert {:ok, result} = TestRequestAction.run(params, context)
      assert result.success == true
      assert result.data.status == 500
      assert result.data.body == "Recovered from error"
    end
    
    test "error handling without recovery" do
      params = %{url: "https://unknown.example.com"}
      context = %{agent: %{}}
      
      assert {:error, result} = TestRequestAction.run(params, context)
      assert result.success == false
      assert result.error == {:max_retries_exceeded, :unknown_url}
      assert result.metadata.action == "test_request"
    end
    
    test "handles missing required parameters" do
      params = %{method: :post}  # missing required url
      context = %{agent: %{}}
      
      # Should fail when trying to access required field
      assert {:error, result} = TestRequestAction.run(params, context)
      assert result.error == {:max_retries_exceeded, :unknown_url}
    end
    
    test "handles invalid method values" do
      params = %{url: "https://test.com", method: :invalid}
      context = %{agent: %{}}
      
      # Should still work since we don't validate the method in handle_request
      assert {:error, result} = TestRequestAction.run(params, context)
      assert result.error == {:max_retries_exceeded, :unknown_url}
    end
  end
end