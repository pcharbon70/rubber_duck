defmodule RubberDuck.Tool.ExternalAdapterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.ExternalAdapter

  # Mock tool module for testing
  defmodule TestTool do
    use RubberDuck.Tool

    tool do
      metadata do
        name :test_tool
        description "A test tool for external adapter"
        category(:testing)
        version("1.0.0")
      end

      parameter :input do
        type :string
        required(true)
        description "Input string to process"
      end

      parameter :count do
        type :integer
        required(false)
        default 1
        description "Number of times to repeat"
      end

      execution do
        handler(fn params, _context ->
          result = String.duplicate(params.input, params.count || 1)
          {:ok, result}
        end)
      end

      examples do
        example do
          code("test_tool(\"hello\", 3)")
          description "Repeats 'hello' 3 times"
        end
      end
    end
  end

  describe "convert_metadata/2" do
    test "converts to OpenAPI format" do
      assert {:ok, spec} = ExternalAdapter.convert_metadata(TestTool, :openapi)

      assert spec["operationId"] == "test_tool"
      assert spec["summary"] == "A test tool for external adapter"
      assert spec["tags"] == ["testing"]
      assert spec["requestBody"]["required"] == true
    end

    test "converts to Anthropic format" do
      assert {:ok, spec} = ExternalAdapter.convert_metadata(TestTool, :anthropic)

      assert spec["name"] == "test_tool"
      assert spec["description"] == "A test tool for external adapter"
      assert is_map(spec["input_schema"])
    end

    test "converts to OpenAI format" do
      assert {:ok, spec} = ExternalAdapter.convert_metadata(TestTool, :openai)

      assert spec["name"] == "test_tool"
      assert spec["description"] == "A test tool for external adapter"
      assert is_map(spec["parameters"])
    end

    test "converts to LangChain format" do
      assert {:ok, spec} = ExternalAdapter.convert_metadata(TestTool, :langchain)

      assert spec["name"] == "test_tool"
      assert spec["description"] == "A test tool for external adapter"
      assert is_map(spec["args_schema"])
      assert spec["tags"] == ["testing"]
      assert spec["metadata"]["version"] == "1.0.0"
    end

    test "returns error for unsupported format" do
      assert {:error, :unsupported_format} = ExternalAdapter.convert_metadata(TestTool, :unknown)
    end
  end

  describe "generate_description/1" do
    test "generates detailed tool description" do
      description = ExternalAdapter.generate_description(TestTool)

      assert description.name == :test_tool
      assert description.description =~ "A test tool for external adapter"
      assert length(description.parameters) == 2
      assert length(description.examples) > 0
    end
  end

  describe "map_parameters/3" do
    test "maps basic parameters correctly" do
      external_params = %{"input" => "hello", "count" => "3"}

      assert {:ok, mapped} = ExternalAdapter.map_parameters(TestTool, external_params)
      assert mapped.input == "hello"
      assert mapped.count == 3
    end

    test "handles missing optional parameters" do
      external_params = %{"input" => "hello"}

      assert {:ok, mapped} = ExternalAdapter.map_parameters(TestTool, external_params)
      assert mapped.input == "hello"
      assert Map.has_key?(mapped, :count) == false
    end

    test "returns error for missing required parameter" do
      external_params = %{"count" => "3"}

      assert {:error, "Missing required parameter: input"} =
               ExternalAdapter.map_parameters(TestTool, external_params)
    end

    test "handles type conversions" do
      external_params = %{
        # Should convert to string
        "input" => 123,
        # Should convert to integer
        "count" => "5"
      }

      assert {:ok, mapped} = ExternalAdapter.map_parameters(TestTool, external_params)
      assert mapped.input == "123"
      assert mapped.count == 5
    end
  end

  describe "convert_result/3" do
    test "converts result to JSON format" do
      result = %{output: "hello world", status: "success"}

      assert {:ok, json} = ExternalAdapter.convert_result(result, TestTool, :json)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["success"] == true
      assert decoded["data"]["output"] == "hello world"
    end

    test "converts result to XML format" do
      result = %{output: "hello world", status: "success"}

      assert {:ok, xml} = ExternalAdapter.convert_result(result, TestTool, :xml)
      assert is_binary(xml)
      assert xml =~ "<output>hello world</output>"
    end

    test "returns error for unsupported format" do
      result = %{output: "hello"}

      assert {:error, :unsupported_format} =
               ExternalAdapter.convert_result(result, TestTool, :yaml)
    end
  end

  describe "execute/4" do
    setup do
      # Register the test tool
      RubberDuck.Tool.Registry.register(TestTool)

      on_exit(fn ->
        RubberDuck.Tool.Registry.unregister(:test_tool)
      end)

      :ok
    end

    test "executes tool with external parameters" do
      external_params = %{"input" => "hello", "count" => "3"}
      context = %{user: %{id: "test_user"}}

      assert {:ok, result} = ExternalAdapter.execute(:test_tool, external_params, context)

      decoded = Jason.decode!(result)
      assert decoded["success"] == true
      assert decoded["data"] == "hellohellohello"
    end

    test "handles execution errors" do
      # Missing required parameter
      external_params = %{}
      context = %{user: %{id: "test_user"}}

      assert {:error, _} = ExternalAdapter.execute(:test_tool, external_params, context)
    end
  end

  describe "execute_async/4" do
    setup do
      RubberDuck.Tool.Registry.register(TestTool)

      on_exit(fn ->
        RubberDuck.Tool.Registry.unregister(:test_tool)
      end)

      :ok
    end

    test "executes tool asynchronously" do
      external_params = %{"input" => "async", "count" => "2"}
      context = %{user: %{id: "test_user"}}

      assert {:ok, task} = ExternalAdapter.execute_async(:test_tool, external_params, context)
      assert %Task{} = task

      # Wait for result
      result = Task.await(task)
      assert {:ok, json} = result

      decoded = Jason.decode!(json)
      assert decoded["data"] == "asyncasync"
    end
  end

  describe "list_tools/1" do
    setup do
      RubberDuck.Tool.Registry.register(TestTool)

      on_exit(fn ->
        RubberDuck.Tool.Registry.unregister(:test_tool)
      end)

      :ok
    end

    test "lists tools in summary format" do
      tools = ExternalAdapter.list_tools(:summary)

      assert Enum.any?(tools, fn tool ->
               tool.name == :test_tool and
                 tool.description == "A test tool for external adapter" and
                 tool.category == :testing
             end)
    end

    test "lists tools in detailed format" do
      tools = ExternalAdapter.list_tools(:detailed)

      assert Enum.any?(tools, fn tool ->
               tool["operationId"] == "test_tool"
             end)
    end

    test "lists tool names only" do
      names = ExternalAdapter.list_tools(:names)

      assert :test_tool in names
    end
  end
end
