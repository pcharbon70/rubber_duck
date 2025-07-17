defmodule RubberDuck.Tool.IntegrationBridgeTest do
  use ExUnit.Case
  
  alias RubberDuck.Tool.{
    ExternalAdapter,
    ExternalRegistry, 
    ExternalRouter,
    CapabilityAPI,
    Streaming,
    StatePersistence,
    DiscoveryEnhanced
  }
  
  # Complex tool for integration testing
  defmodule IntegrationTestTool do
    use RubberDuck.Tool
    
    tool do
      metadata do
        name :integration_test
        description "Complex tool for integration testing"
        category :testing
        version "1.5.0"
      end
      
      parameter :operation do
        type :string
        required true
        description "Operation to perform"
        constraints %{
          enum: ["process", "analyze", "transform"]
        }
      end
      
      parameter :data do
        type {:array, :map}
        required true
        description "Data to process"
      end
      
      parameter :options do
        type :map
        required false
        default %{}
        description "Processing options"
      end
      
      security do
        level :balanced
        capabilities [:data_processing]
        rate_limits %{
          per_minute: 10,
          per_hour: 100
        }
      end
      
      execution do
        async true
        streaming true
        timeout 30_000
        retries 2
        
        handler fn params, context ->
          # Simulate processing with progress
          if context[:progress_callback] do
            context.progress_callback.(%{stage: "initializing", progress: 0})
          end
          
          Process.sleep(100)
          
          if context[:progress_callback] do
            context.progress_callback.(%{stage: "processing", progress: 50})
          end
          
          result = case params.operation do
            "process" -> 
              %{processed: length(params.data), items: params.data}
            
            "analyze" ->
              %{
                count: length(params.data),
                summary: "Analysis complete",
                metrics: %{avg: 42.0}
              }
            
            "transform" ->
              transformed = Enum.map(params.data, fn item ->
                Map.put(item, :transformed, true)
              end)
              %{transformed: transformed}
          end
          
          if context[:progress_callback] do
            context.progress_callback.(%{stage: "complete", progress: 100})
          end
          
          {:ok, result}
        end
      end
      
      examples do
        example do
          code ~s|integration_test("process", [%{id: 1}])|
          description "Process a list of items"
        end
      end
    end
  end
  
  setup do
    # Start all required services
    {:ok, _} = ExternalRegistry.start_link(auto_register: false)
    {:ok, _} = ExternalRouter.start_link()
    {:ok, _} = StatePersistence.start_link()
    
    # Register test tool
    RubberDuck.Tool.Registry.register(IntegrationTestTool)
    
    on_exit(fn ->
      RubberDuck.Tool.Registry.unregister(:integration_test)
    end)
    
    :ok
  end
  
  describe "end-to-end tool execution" do
    test "complete flow from discovery to execution with streaming" do
      # 1. Discover the tool
      assert {:ok, results} = DiscoveryEnhanced.semantic_search("integration")
      assert Enum.any?(results, & &1.tool_name == :integration_test)
      
      # 2. Get capabilities
      assert {:ok, capability} = CapabilityAPI.get_capability(:integration_test)
      assert capability.capabilities.streaming_supported == true
      
      # 3. Register with external services
      assert :ok = ExternalRegistry.register_tool(IntegrationTestTool)
      
      # 4. Execute through external router
      external_params = %{
        "operation" => "analyze",
        "data" => [%{"id" => 1}, %{"id" => 2}]
      }
      
      context = %{
        user: %{id: "test_user", capabilities: [:tool_access, :data_processing]},
        session_id: "test_session"
      }
      
      {:ok, request_id} = ExternalRouter.route_call(:integration_test, external_params, context)
      
      # 5. Subscribe to streaming updates
      ExternalRouter.subscribe_to_progress(request_id)
      
      # Collect progress events
      progress_events = collect_progress_events(request_id, 3000)
      
      # Verify progress stages
      assert Enum.any?(progress_events, & &1.stage == "initializing")
      assert Enum.any?(progress_events, & &1.stage == "processing")
      assert Enum.any?(progress_events, & &1.stage == "complete")
      
      # 6. Check final status
      Process.sleep(500)  # Ensure execution completes
      assert {:ok, status} = ExternalRouter.get_status(request_id)
      assert status.status == :completed
      
      # 7. Verify state persistence
      assert {:ok, history} = StatePersistence.get_history(%{request_id: request_id})
      assert length(history) == 1
    end
  end
  
  describe "tool composition compatibility" do
    test "checks compatibility between tools" do
      # Register another tool for compatibility testing
      defmodule VisualizationTool do
        use RubberDuck.Tool
        
        tool do
          metadata do
            name :viz_tool
            description "Visualization tool"
            category :visualization
          end
          
          parameter :data do
            type {:array, :map}
            required true
          end
          
          execution do
            handler fn _params, _context -> {:ok, "chart"} end
          end
        end
      end
      
      RubberDuck.Tool.Registry.register(VisualizationTool)
      
      # Check compatibility
      assert {:ok, compatibility} = DiscoveryEnhanced.check_compatibility(
        :integration_test,
        :viz_tool
      )
      
      # Data -> Analysis -> Visualization is a valid flow
      assert compatibility.compatible == true
      assert compatibility.semantic_compatible == true
      assert compatibility.suggested_order == [:integration_test, :viz_tool]
      
      RubberDuck.Tool.Registry.unregister(:viz_tool)
    end
  end
  
  describe "performance profiling" do
    test "profiles tool performance and provides suggestions" do
      # Execute tool multiple times to generate metrics
      context = %{
        user: %{id: "test_user", capabilities: [:tool_access, :data_processing]}
      }
      
      for _ <- 1..5 do
        params = %{"operation" => "process", "data" => [%{"id" => 1}]}
        ExternalRouter.route_call_sync(:integration_test, params, context)
      end
      
      # Profile the tool
      assert {:ok, profile} = DiscoveryEnhanced.profile_tool(:integration_test)
      
      assert profile.tool_name == :integration_test
      assert is_map(profile.metrics)
      assert is_map(profile.analysis)
      assert is_list(profile.suggestions)
    end
  end
  
  describe "state persistence and session management" do
    test "persists tool state across executions" do
      session_id = "persistent_session"
      
      # Save state
      state = %{last_operation: "analyze", results: [1, 2, 3]}
      assert :ok = StatePersistence.save_state(session_id, :integration_test, state)
      
      # Retrieve state
      assert {:ok, retrieved_state} = StatePersistence.get_state(session_id, :integration_test)
      assert retrieved_state == state
      
      # Execute tool and save execution record
      execution_record = %{
        request_id: "exec_123",
        tool_name: :integration_test,
        session_id: session_id,
        started_at: DateTime.utc_now(),
        status: :success,
        duration_ms: 150
      }
      
      StatePersistence.save_execution(execution_record)
      
      # Get statistics
      assert {:ok, stats} = StatePersistence.get_statistics(:integration_test)
      assert stats.total_executions > 0
      
      # Clear session
      assert :ok = StatePersistence.clear_session(session_id)
      assert {:error, :not_found} = StatePersistence.get_state(session_id, :integration_test)
    end
  end
  
  describe "advanced discovery features" do
    test "finds similar tools" do
      assert {:ok, similar} = DiscoveryEnhanced.find_similar_tools(:integration_test)
      
      assert is_list(similar)
      assert Enum.all?(similar, & &1.similarity_score >= 0)
    end
    
    test "analyzes usage trends" do
      # Generate some execution history
      for i <- 1..10 do
        execution = %{
          request_id: "trend_#{i}",
          tool_name: :integration_test,
          started_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second),
          status: if(rem(i, 5) == 0, do: :failed, else: :success),
          duration_ms: 100 + i * 10
        }
        
        StatePersistence.save_execution(execution)
      end
      
      assert {:ok, trends} = DiscoveryEnhanced.analyze_trends()
      
      assert Map.has_key?(trends, :usage_trend)
      assert Map.has_key?(trends, :popular_tools)
      assert Map.has_key?(trends, :error_trends)
      assert Map.has_key?(trends, :performance_trends)
    end
    
    test "provides contextual recommendations" do
      context = %{
        session_id: "rec_session",
        recent_tools: [:integration_test],
        preferred_category: :analysis
      }
      
      assert {:ok, recommendations} = DiscoveryEnhanced.recommend_tools(context)
      
      assert is_list(recommendations)
      assert Enum.all?(recommendations, fn rec ->
        Map.has_key?(rec, :tool_name) and
        Map.has_key?(rec, :confidence) and
        Map.has_key?(rec, :reasons)
      end)
    end
  end
  
  describe "streaming capabilities" do
    test "streams large results efficiently" do
      # Create streaming adapter
      adapter = Streaming.create_streaming_adapter("stream_test")
      
      # Add data in chunks
      large_data = String.duplicate("x", 10_000)
      
      {:ok, adapter} = Streaming.stream_data(adapter, large_data)
      
      # Verify chunking occurred
      assert adapter.chunks_sent > 0
      assert adapter.bytes_sent > 0
      
      # Flush remaining data
      {:ok, final_adapter} = Streaming.flush_stream(adapter)
      assert final_adapter.bytes_sent == byte_size(large_data)
    end
  end
  
  # Helper functions
  
  defp collect_progress_events(request_id, timeout) do
    collect_progress_events(request_id, timeout, [])
  end
  
  defp collect_progress_events(_request_id, timeout, events) when timeout <= 0 do
    Enum.reverse(events)
  end
  
  defp collect_progress_events(request_id, timeout, events) do
    receive do
      {:tool_execution_event, %{event: :progress, data: data}} ->
        collect_progress_events(request_id, timeout - 100, [data | events])
      
      {:tool_execution_event, %{event: :completed}} ->
        Enum.reverse(events)
    after
      100 ->
        collect_progress_events(request_id, timeout - 100, events)
    end
  end
end