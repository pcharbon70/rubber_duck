defmodule RubberDuck.Tool.ExternalRouterTest do
  use ExUnit.Case
  
  alias RubberDuck.Tool.ExternalRouter
  alias Phoenix.PubSub
  
  # Mock tool for testing
  defmodule RouterTestTool do
    use RubberDuck.Tool
    
    tool do
      metadata do
        name :router_test
        description "Tool for router testing"
      end
      
      parameter :action do
        type :string
        required true
        description "Action to perform"
      end
      
      parameter :delay do
        type :integer
        required false
        default 0
        description "Delay in milliseconds"
      end
      
      execution do
        handler fn params, context ->
          if params.delay > 0 do
            Process.sleep(params.delay)
          end
          
          # Call progress callback if available
          if callback = context[:progress_callback] do
            callback.(%{status: "processing", progress: 50})
          end
          
          case params.action do
            "success" -> {:ok, %{result: "Success!"}}
            "error" -> {:error, "Intentional error"}
            _ -> {:ok, %{result: "Unknown action"}}
          end
        end
      end
    end
  end
  
  setup do
    # Start router if not already started
    case ExternalRouter.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
    
    # Register test tool
    RubberDuck.Tool.Registry.register(RouterTestTool)
    
    on_exit(fn ->
      RubberDuck.Tool.Registry.unregister(:router_test)
    end)
    
    :ok
  end
  
  describe "route_call/4" do
    test "routes async tool call and returns request ID" do
      params = %{"action" => "success"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      assert {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      assert is_binary(request_id)
      assert String.starts_with?(request_id, "req_")
    end
    
    test "broadcasts execution events" do
      params = %{"action" => "success"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      
      # Subscribe to events
      PubSub.subscribe(RubberDuck.PubSub, "tool_execution:#{request_id}")
      
      # Wait for events
      assert_receive {:tool_execution_event, %{event: :started}}, 1000
      assert_receive {:tool_execution_event, %{event: :authorized}}, 1000
      assert_receive {:tool_execution_event, %{event: :parameters_mapped}}, 1000
      assert_receive {:tool_execution_event, %{event: :progress}}, 1000
      assert_receive {:tool_execution_event, %{event: :completed}}, 1000
    end
  end
  
  describe "route_call_sync/4" do
    test "executes tool synchronously and returns result" do
      params = %{"action" => "success"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      assert {:ok, result} = ExternalRouter.route_call_sync(:router_test, params, context)
      
      decoded = Jason.decode!(result)
      assert decoded["success"] == true
      assert decoded["data"]["result"] == "Success!"
    end
    
    test "handles tool errors properly" do
      params = %{"action" => "error"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      assert {:error, _} = ExternalRouter.route_call_sync(:router_test, params, context)
    end
    
    test "respects timeout option" do
      params = %{"action" => "success", "delay" => "100"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      opts = [timeout: 50]
      
      # This should timeout
      assert_raise RuntimeError, fn ->
        ExternalRouter.route_call_sync(:router_test, params, context, opts)
      end
    end
  end
  
  describe "get_status/1" do
    test "returns status of ongoing execution" do
      params = %{"action" => "success", "delay" => "100"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      
      # Check status immediately
      assert {:ok, status} = ExternalRouter.get_status(request_id)
      assert status.request_id == request_id
      assert status.tool_name == :router_test
      assert status.status == :running
      
      # Wait for completion
      Process.sleep(200)
      
      assert {:ok, status} = ExternalRouter.get_status(request_id)
      assert status.status == :completed
    end
    
    test "returns error for non-existent request" do
      assert {:error, :not_found} = ExternalRouter.get_status("req_nonexistent")
    end
  end
  
  describe "cancel/1" do
    test "cancels ongoing execution" do
      params = %{"action" => "success", "delay" => "1000"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      
      # Subscribe to events
      PubSub.subscribe(RubberDuck.PubSub, "tool_execution:#{request_id}")
      
      # Cancel immediately
      assert :ok = ExternalRouter.cancel(request_id)
      
      # Should receive cancellation event
      assert_receive {:tool_execution_event, %{event: :cancelled}}, 1000
      
      # Status should be cancelled
      assert {:ok, status} = ExternalRouter.get_status(request_id)
      assert status.status == :cancelled
    end
    
    test "returns error for non-existent request" do
      assert {:error, :not_found} = ExternalRouter.cancel("req_nonexistent")
    end
  end
  
  describe "authorization" do
    test "rejects unauthorized users" do
      params = %{"action" => "success"}
      context = %{user: %{id: "unauthorized_user", capabilities: []}}
      
      {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      
      # Subscribe to events
      PubSub.subscribe(RubberDuck.PubSub, "tool_execution:#{request_id}")
      
      # Should receive error event
      assert_receive {:tool_execution_event, %{event: :error, data: %{error: error}}}, 1000
      assert error.type == :unauthorized
    end
  end
  
  describe "concurrent execution limits" do
    test "respects max concurrent executions" do
      # Create router with low limit
      {:ok, _pid} = ExternalRouter.start_link(max_concurrent: 2)
      
      params = %{"action" => "success", "delay" => "500"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      # Start two executions (should succeed)
      {:ok, req1} = ExternalRouter.route_call(:router_test, params, context)
      {:ok, req2} = ExternalRouter.route_call(:router_test, params, context)
      
      # Subscribe to third request
      {:ok, req3} = ExternalRouter.route_call(:router_test, params, context)
      PubSub.subscribe(RubberDuck.PubSub, "tool_execution:#{req3}")
      
      # Third should fail immediately
      assert_receive {:tool_execution_event, %{event: :error, data: %{error: :too_many_requests}}}, 100
    end
  end
  
  describe "progress streaming" do
    test "streams progress updates during execution" do
      params = %{"action" => "success"}
      context = %{user: %{id: "test_user", capabilities: [:tool_access]}}
      
      {:ok, request_id} = ExternalRouter.route_call(:router_test, params, context)
      
      # Subscribe to progress
      ExternalRouter.subscribe_to_progress(request_id)
      
      # Should receive progress update
      assert_receive {:tool_execution_event, %{event: :progress, data: data}}, 1000
      assert data.status == "processing"
      assert data.progress == 50
    end
  end
end