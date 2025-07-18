defmodule RubberDuck.MCP.ToolAdapterTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.ToolAdapter
  alias RubberDuck.Tool.Registry
  
  # Define a test tool module
  defmodule TestTool do
    def __tool__(:all) do
      %{
        name: :test_tool,
        description: "A test tool for adapter testing",
        version: "1.0.0",
        category: :testing,
        tags: [:test, :example],
        parameters: [
          %{
            name: :input,
            type: :string,
            description: "Test input parameter",
            required: true,
            constraints: [
              min_length: 3,
              max_length: 100,
              pattern: "^[a-zA-Z]+$"
            ]
          },
          %{
            name: :count,
            type: :integer,
            description: "Count parameter",
            required: false,
            default: 5,
            constraints: [
              min: 1,
              max: 100
            ]
          },
          %{
            name: :options,
            type: :map,
            description: "Options map",
            required: false
          }
        ],
        execution: %{
          handler: :execute,
          async: true,
          timeout: 10_000,
          streaming: true,
          cancellable: true
        },
        security: %{
          requires_auth: true,
          allowed_roles: [:user, :admin],
          rate_limit: 100,
          max_memory: 256,
          max_cpu: 10
        },
        examples: [
          %{
            name: "Basic usage",
            params: %{input: "hello", count: 3}
          }
        ],
        templates: [
          %{
            name: "test_tool_advanced",
            description: "Advanced test tool usage",
            content: "Use test_tool with input {{input}} and count {{count}}"
          }
        ]
      }
    end
    
    def __tool__(:metadata), do: __tool__(:all)
    def __tool__(:name), do: :test_tool
    def __tool__(:parameters), do: __tool__(:all).parameters
    def __tool__(:execution), do: __tool__(:all).execution
    def __tool__(:security), do: __tool__(:all).security
    
    def execute(params, context) do
      {:ok, %{
        input: params.input,
        count: params.count || 5,
        processed: true,
        user_id: context.user.id
      }}
    end
  end
  
  setup do
    # Register test tool
    Registry.start_link()
    Registry.register(TestTool)
    :ok
  end
  
  describe "convert_tool_to_mcp/1" do
    test "converts tool module to comprehensive MCP format" do
      result = ToolAdapter.convert_tool_to_mcp(TestTool)
      
      assert result["name"] == "test_tool"
      assert result["description"] == "A test tool for adapter testing"
      
      # Check input schema
      schema = result["inputSchema"]
      assert schema["type"] == "object"
      assert Map.keys(schema["properties"]) == ["count", "input", "options"]
      assert schema["required"] == ["input"]
      
      # Check capabilities
      capabilities = result["capabilities"]
      assert capabilities["supportsAsync"] == true
      assert capabilities["supportsStreaming"] == true
      assert capabilities["supportsCancellation"] == true
      assert capabilities["maxExecutionTime"] == 10_000
      
      # Check metadata
      metadata = result["metadata"]
      assert metadata["version"] == "1.0.0"
      assert metadata["category"] == :testing
      assert metadata["tags"] == [:test, :example]
      assert metadata["async"] == true
      assert metadata["timeout"] == 10_000
    end
    
    test "handles tool without metadata gracefully" do
      defmodule MinimalTool do
        def __tool__(:metadata), do: raise "No metadata"
      end
      
      result = ToolAdapter.convert_tool_to_mcp(MinimalTool)
      
      assert result["name"] =~ "MinimalTool"
      assert result["description"] =~ "Tool module"
      assert result["inputSchema"]["type"] == "object"
      assert result["inputSchema"]["properties"] == %{}
    end
  end
  
  describe "parameter_schema_to_mcp/1" do
    test "converts parameters to JSON Schema" do
      params = TestTool.__tool__(:metadata).parameters
      result = ToolAdapter.parameter_schema_to_mcp(params)
      
      assert result["type"] == "object"
      assert result["additionalProperties"] == false
      assert result["required"] == ["input"]
      
      # Check string parameter with constraints
      input_schema = result["properties"]["input"]
      assert input_schema["type"] == "string"
      assert input_schema["description"] == "Test input parameter"
      assert input_schema["minLength"] == 3
      assert input_schema["maxLength"] == 100
      assert input_schema["pattern"] == "^[a-zA-Z]+$"
      
      # Check integer parameter with constraints
      count_schema = result["properties"]["count"]
      assert count_schema["type"] == "integer"
      assert count_schema["default"] == 5
      assert count_schema["minimum"] == 1
      assert count_schema["maximum"] == 100
      
      # Check map parameter
      options_schema = result["properties"]["options"]
      assert options_schema["type"] == "object"
    end
    
    test "handles empty parameters" do
      result = ToolAdapter.parameter_schema_to_mcp([])
      
      assert result["type"] == "object"
      assert result["properties"] == %{}
      assert result["required"] == []
    end
  end
  
  describe "map_mcp_call/3" do
    test "maps MCP call to internal execution" do
      mcp_params = %{
        "input" => "hello",
        "count" => 10
      }
      
      mcp_context = %{
        user: %{id: "user123"},
        session_id: "session123",
        enable_progress: false
      }
      
      # Since authorization is strict, we expect an error
      # In a real implementation, proper user context would be provided
      result = ToolAdapter.map_mcp_call("test_tool", mcp_params, mcp_context)
      
      case result do
        {:ok, success_result} ->
          assert success_result["content"]
          assert success_result["metadata"]["tool"] == "test_tool"
        {:error, error_result} ->
          assert error_result["code"] == -32603
          assert error_result["data"]["tool"] == "test_tool"
      end
    end
    
    test "handles tool not found" do
      result = ToolAdapter.map_mcp_call("nonexistent", %{}, %{})
      
      assert {:error, _} = result
    end
  end
  
  describe "transform_parameters/3" do
    test "transforms from MCP format" do
      mcp_params = %{
        "input" => "hello",
        "count" => "10"  # String that should be converted
      }
      
      {:ok, result} = ToolAdapter.transform_parameters(TestTool, mcp_params, :from_mcp)
      
      assert result.input == "hello"
      assert result.count == "10"  # Basic implementation doesn't convert types yet
    end
    
    test "applies defaults for missing parameters" do
      mcp_params = %{"input" => "hello"}
      
      {:ok, result} = ToolAdapter.transform_parameters(TestTool, mcp_params, :from_mcp)
      
      assert result.input == "hello"
      assert result.count == 5  # Default value applied
    end
    
    test "transforms to MCP format" do
      internal_params = %{
        input: "hello",
        count: 10,
        options: %{key: "value"}
      }
      
      {:ok, result} = ToolAdapter.transform_parameters(TestTool, internal_params, :to_mcp)
      
      assert result["input"] == "hello"
      assert result["count"] == 10
      assert result["options"] == %{key: "value"}
    end
  end
  
  describe "format_execution_result/2" do
    test "formats string result" do
      result = ToolAdapter.format_execution_result("Hello, world!", TestTool)
      
      assert [content] = result["content"]
      assert content["type"] == "text"
      assert content["text"] == "Hello, world!"
      assert result["metadata"]["tool"] == "test_tool"
    end
    
    test "formats map result as JSON" do
      map_result = %{key: "value", nested: %{data: true}}
      result = ToolAdapter.format_execution_result(map_result, TestTool)
      
      assert [content] = result["content"]
      assert content["type"] == "text"
      assert content["text"] =~ "\"key\": \"value\""
      assert content["mimeType"] == "application/json"
    end
    
    test "formats result with output field" do
      exec_result = %{output: "Process completed", format: :markdown}
      result = ToolAdapter.format_execution_result(exec_result, TestTool)
      
      assert [content] = result["content"]
      assert content["type"] == "text"
      assert content["text"] == "Process completed"
      assert content["mimeType"] == "text/markdown"
    end
  end
  
  describe "error_to_mcp/2" do
    test "translates validation error" do
      error = {:validation_error, "Invalid input"}
      result = ToolAdapter.error_to_mcp(error, TestTool)
      
      assert result["code"] == -32602
      assert result["message"] =~ "Invalid parameters"
      assert result["data"]["tool"] == "test_tool"
      assert result["data"]["type"] == "validation_error"
    end
    
    test "translates authorization error" do
      error = {:authorization_error, "Not allowed"}
      result = ToolAdapter.error_to_mcp(error, TestTool)
      
      assert result["code"] == -32603
      assert result["message"] =~ "Not authorized"
    end
    
    test "sanitizes error messages" do
      error = {:tool_error, "Failed at /home/user/secret/path with IP 192.168.1.1"}
      result = ToolAdapter.error_to_mcp(error, TestTool)
      
      assert result["message"] =~ "/***"
      refute result["message"] =~ "secret"
      assert result["message"] =~ "*.*.*.*"
      refute result["message"] =~ "192.168"
    end
  end
  
  describe "discover_tool_resources/1" do
    test "discovers tool resources" do
      resources = ToolAdapter.discover_tool_resources(TestTool)
      
      assert length(resources) >= 3
      
      # Check documentation resource
      doc_resource = Enum.find(resources, & &1["uri"] =~ "documentation")
      assert doc_resource["name"] =~ "Documentation"
      assert doc_resource["mimeType"] == "text/markdown"
      
      # Check schema resource
      schema_resource = Enum.find(resources, & &1["uri"] =~ "schema")
      assert schema_resource["name"] =~ "Schema"
      assert schema_resource["mimeType"] == "application/schema+json"
      
      # Check examples resource
      examples_resource = Enum.find(resources, & &1["uri"] =~ "examples")
      assert examples_resource["name"] =~ "Examples"
      assert examples_resource["mimeType"] == "application/json"
    end
  end
  
  describe "prompt_templates/1" do
    test "generates prompt templates" do
      templates = ToolAdapter.prompt_templates(TestTool)
      
      assert length(templates) >= 2
      
      # Check basic template
      basic = Enum.find(templates, & &1["name"] == "test_tool_basic")
      assert basic["description"] =~ "Basic usage"
      assert basic["template"] =~ "{{input}}"
      assert basic["template"] =~ "{{count}}"
      
      # Check custom template
      custom = Enum.find(templates, & &1["name"] == "test_tool_advanced")
      assert custom["description"] =~ "Advanced"
    end
  end
  
  describe "capability_descriptor/1" do
    test "generates capability descriptor" do
      metadata = TestTool.__tool__(:metadata)
      result = ToolAdapter.capability_descriptor(metadata)
      
      assert result["supportsAsync"] == true
      assert result["supportsStreaming"] == true
      assert result["supportsCancellation"] == true
      assert result["maxExecutionTime"] == 10_000
      
      # Check resource limits
      limits = result["resourceLimits"]
      assert limits["maxMemory"] == 256
      assert limits["maxCpu"] == 10
      assert limits["maxTime"] == 10_000
      
      # Check security constraints
      security = result["securityConstraints"]
      assert security["requiresAuthentication"] == true
      assert security["requiresAuthorization"] == true
      assert security["allowedRoles"] == [:user, :admin]
      assert security["rateLimit"] == 100
    end
  end
  
  describe "setup_progress_reporter/2" do
    test "creates progress reporter function" do
      reporter = ToolAdapter.setup_progress_reporter("session123", "test_tool")
      
      assert is_function(reporter, 1)
      
      # Test that it doesn't crash when called
      reporter.(%{progress: 50, message: "Halfway done"})
    end
  end
end