defmodule RubberDuck.Tool.ResultProcessorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.ResultProcessor
  
  @test_user %{
    id: "test-user",
    roles: [:user],
    permissions: [:read, :execute]
  }
  
  @test_context %{
    user: @test_user,
    execution_id: "test-exec-123"
  }
  
  defmodule TestTool do
    use RubberDuck.Tool
    
    tool do
      name :test_tool
      description "Test tool for result processing"
      category :testing
      
      parameter :input do
        type :string
        required true
      end
      
      execution do
        handler &TestTool.execute/2
      end
    end
    
    def execute(params, _context) do
      {:ok, "Processed: #{params.input}"}
    end
  end
  
  describe "result processing pipeline" do
    test "processes basic result successfully" do
      raw_result = %{
        output: "test output",
        status: :success,
        execution_time: 100,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      assert {:ok, processed_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context)
      
      # Should maintain original structure
      assert processed_result.output == "test output"
      assert processed_result.status == :success
      assert processed_result.execution_time == 100
      assert processed_result.retry_count == 0
      
      # Should add processing metadata
      assert Map.has_key?(processed_result, :processing_metadata)
      assert is_number(processed_result.processing_metadata.processing_time)
      assert processed_result.processing_metadata.version == "1.0"
    end
    
    test "handles different output formats" do
      raw_result = %{
        output: %{message: "hello", user: "test"},
        status: :success,
        execution_time: 50,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Test JSON format
      assert {:ok, json_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, format: :json)
      assert is_binary(json_result.output)
      assert json_result.output =~ "hello"
      
      # Test XML format
      assert {:ok, xml_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, format: :xml)
      assert is_binary(xml_result.output)
      assert xml_result.output =~ "<message>hello</message>"
      
      # Test YAML format
      assert {:ok, yaml_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, format: :yaml)
      assert is_binary(yaml_result.output)
      assert yaml_result.output =~ "message: \"hello\""
    end
    
    test "handles transformation options" do
      raw_result = %{
        output: "  Hello World!  ",
        status: :success,
        execution_time: 25,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Test sanitization
      assert {:ok, sanitized_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, transform: :sanitize)
      assert sanitized_result.output == "  Hello World!  "
      
      # Test compression
      assert {:ok, compressed_result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, transform: :compress)
      assert is_binary(compressed_result.output)
      assert compressed_result.output != raw_result.output
    end
    
    test "handles processing options" do
      raw_result = %{
        output: "test",
        status: :success,
        execution_time: 10,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Test with caching disabled
      assert {:ok, result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, cache: false)
      assert result.processing_metadata.processing_options[:cache] == false
      
      # Test with events disabled
      assert {:ok, result} = ResultProcessor.process_result(raw_result, TestTool, @test_context, emit_events: false)
      assert result.processing_metadata.processing_options[:emit_events] == false
    end
    
    test "handles validation errors" do
      # Missing required fields
      invalid_result = %{
        output: "test",
        status: :invalid_status
      }
      
      assert {:error, :processing_failed, _reason} = ResultProcessor.process_result(invalid_result, TestTool, @test_context)
    end
    
    test "handles formatting errors" do
      raw_result = %{
        output: {:invalid, :tuple},
        status: :success,
        execution_time: 10,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # JSON formatting should fail for invalid data
      assert {:error, :formatting_failed, _reason} = ResultProcessor.process_result(raw_result, TestTool, @test_context, format: :json)
    end
  end
  
  describe "output formatting" do
    test "formats JSON output correctly" do
      data = %{message: "hello", count: 42}
      
      assert {:ok, json} = ResultProcessor.format_output(data, :json)
      assert is_binary(json)
      assert json =~ "hello"
      assert json =~ "42"
    end
    
    test "formats XML output correctly" do
      data = %{message: "hello", count: 42}
      
      assert {:ok, xml} = ResultProcessor.format_output(data, :xml)
      assert is_binary(xml)
      assert xml =~ "<message>hello</message>"
      assert xml =~ "<count>42</count>"
    end
    
    test "formats YAML output correctly" do
      data = %{message: "hello", count: 42}
      
      assert {:ok, yaml} = ResultProcessor.format_output(data, :yaml)
      assert is_binary(yaml)
      assert yaml =~ "message: \"hello\""
      assert yaml =~ "count: 42"
    end
    
    test "formats binary output correctly" do
      data = "binary data"
      
      assert {:ok, binary} = ResultProcessor.format_output(data, :binary)
      assert is_binary(binary)
      assert binary == "binary data"
      
      # Non-binary data should be converted
      assert {:ok, binary} = ResultProcessor.format_output(%{test: "data"}, :binary)
      assert is_binary(binary)
    end
    
    test "formats plain text output correctly" do
      assert {:ok, plain} = ResultProcessor.format_output("hello", :plain)
      assert plain == "hello"
      
      assert {:ok, plain} = ResultProcessor.format_output(42, :plain)
      assert plain == "42"
    end
    
    test "handles structured format" do
      data = %{message: "hello"}
      
      assert {:ok, result} = ResultProcessor.format_output(data, :structured)
      assert result == data
    end
    
    test "handles unsupported format" do
      data = %{message: "hello"}
      
      assert {:error, :unsupported_format, :invalid} = ResultProcessor.format_output(data, :invalid)
    end
  end
  
  describe "result validation" do
    test "validates correct result structure" do
      valid_result = %{
        output: "test",
        status: :success,
        execution_time: 100,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      assert {:ok, result} = ResultProcessor.validate_result_structure(valid_result, TestTool)
      assert result == valid_result
    end
    
    test "enriches minimal result structure" do
      minimal_result = %{
        output: "test",
        status: :success
      }
      
      assert {:ok, result} = ResultProcessor.validate_result_structure(minimal_result, TestTool)
      assert result.output == "test"
      assert result.status == :success
      assert result.execution_time == 0
      assert result.metadata == %{}
      assert result.retry_count == 0
    end
    
    test "rejects invalid result structure" do
      invalid_result = %{
        output: "test"
        # Missing status
      }
      
      assert {:error, :invalid_structure, _reason} = ResultProcessor.validate_result_structure(invalid_result, TestTool)
    end
    
    test "handles validation errors" do
      invalid_result = :not_a_map
      
      assert {:error, :validation_error, _reason} = ResultProcessor.validate_result_structure(invalid_result, TestTool)
    end
  end
  
  describe "output transformation" do
    test "applies default transformation" do
      output = "test output"
      
      assert {:ok, result} = ResultProcessor.transform_output(output, :default, TestTool, @test_context)
      assert result == output
    end
    
    test "applies sanitization transformation" do
      output = "Hello <script>alert('hack')</script> World"
      
      assert {:ok, result} = ResultProcessor.transform_output(output, :sanitize, TestTool, @test_context)
      assert result == "Hello  World"
      refute result =~ "<script>"
    end
    
    test "applies compression transformation" do
      output = "This is a test string that should be compressed"
      
      assert {:ok, result} = ResultProcessor.transform_output(output, :compress, TestTool, @test_context)
      assert is_binary(result)
      assert result != output
    end
    
    test "applies normalization transformation" do
      output = %{:atom_key => "value", "string_key" => "value2"}
      
      assert {:ok, result} = ResultProcessor.transform_output(output, :normalize, TestTool, @test_context)
      assert Map.has_key?(result, "atom_key")
      assert Map.has_key?(result, "string_key")
    end
    
    test "handles unsupported transformation" do
      output = "test"
      
      assert {:error, :unsupported_transformer, :invalid} = 
        ResultProcessor.transform_output(output, :invalid, TestTool, @test_context)
    end
  end
  
  describe "caching" do
    test "caches processed results" do
      raw_result = %{
        output: "cached test",
        status: :success,
        execution_time: 50,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Process and cache
      assert {:ok, processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, cache: true)
      
      # Should be able to retrieve from cache
      assert {:ok, cached} = ResultProcessor.get_cached_result(TestTool, @test_context, cache: true)
      assert cached.output == processed.output
    end
    
    test "handles cache miss" do
      context = %{@test_context | execution_id: "non-existent"}
      
      assert {:error, :not_found} = ResultProcessor.get_cached_result(TestTool, context)
    end
    
    test "skips caching when disabled" do
      raw_result = %{
        output: "uncached test",
        status: :success,
        execution_time: 50,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Process without caching
      assert {:ok, _processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, cache: false)
      
      # Should not be in cache
      assert {:error, :not_found} = ResultProcessor.get_cached_result(TestTool, @test_context)
    end
  end
  
  describe "persistence" do
    test "persists results when enabled" do
      raw_result = %{
        output: "persisted test",
        status: :success,
        execution_time: 75,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Process with persistence enabled
      assert {:ok, _processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, persist: true)
      
      # In a real implementation, you would verify the result was stored
      # For now, we just ensure no errors occurred
    end
    
    test "skips persistence when disabled" do
      raw_result = %{
        output: "non-persisted test",
        status: :success,
        execution_time: 25,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Process without persistence (default)
      assert {:ok, _processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, persist: false)
      
      # Should complete without errors
    end
  end
  
  describe "event emission" do
    test "emits processing events by default" do
      raw_result = %{
        output: "event test",
        status: :success,
        execution_time: 30,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Subscribe to events
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "tool_results")
      
      # Process result
      assert {:ok, _processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context)
      
      # Should receive event
      assert_receive {:result_processed, %{tool: :test_tool}}, 1000
    end
    
    test "skips events when disabled" do
      raw_result = %{
        output: "no event test",
        status: :success,
        execution_time: 20,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Subscribe to events
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "tool_results")
      
      # Process result without events
      assert {:ok, _processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, emit_events: false)
      
      # Should not receive event
      refute_receive {:result_processed, _}, 500
    end
  end
  
  describe "error handling" do
    test "handles processing pipeline failures gracefully" do
      # Invalid result that will fail validation
      invalid_result = %{
        output: "test",
        status: :invalid_status,
        execution_time: "not_a_number"
      }
      
      result = ResultProcessor.process_result(invalid_result, TestTool, @test_context)
      assert match?({:error, _, _}, result)
    end
    
    test "continues processing on non-critical failures" do
      raw_result = %{
        output: "test",
        status: :success,
        execution_time: 10,
        metadata: %{tool_name: :test_tool},
        retry_count: 0
      }
      
      # Even if caching fails, processing should continue
      assert {:ok, processed} = ResultProcessor.process_result(raw_result, TestTool, @test_context, cache: true)
      assert processed.output == "test"
    end
  end
  
  describe "integration with executor" do
    test "processes results through executor" do
      params = %{input: "integration test"}
      
      # Execute tool (this should use result processing)
      assert {:ok, result} = RubberDuck.Tool.Executor.execute(TestTool, params, @test_user)
      
      # Should have processing metadata
      assert Map.has_key?(result, :processing_metadata)
      assert is_number(result.processing_metadata.processing_time)
    end
    
    test "handles executor with processing options" do
      params = %{input: "options test"}
      options = %{processing: [format: :json, cache: true]}
      
      # Execute with processing options
      assert {:ok, result} = RubberDuck.Tool.Executor.execute(TestTool, params, @test_user, options)
      
      # Should have JSON formatted output
      assert is_binary(result.output)
      assert result.output =~ "options test"
      
      # Should have processing metadata
      assert Map.has_key?(result, :processing_metadata)
      assert result.processing_metadata.processing_options[:format] == :json
    end
  end
end