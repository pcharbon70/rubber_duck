defmodule RubberDuck.MCP.BridgeIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Bridge
  alias RubberDuck.Tool.Registry

  # Define a test tool for integration testing
  defmodule IntegrationTestTool do
    def __tool__(:all) do
      %{
        name: :integration_test,
        description: "Tool for bridge integration testing",
        version: "1.0.0",
        category: :testing,
        parameters: [
          %{
            name: :message,
            type: :string,
            description: "Test message",
            required: true
          },
          %{
            name: :format,
            type: :string,
            description: "Output format",
            required: false,
            default: "text",
            constraints: [
              enum: ["text", "json", "markdown"]
            ]
          }
        ],
        execution: %{
          handler: :execute,
          async: false,
          timeout: 5_000
        },
        examples: [
          %{
            name: "Basic example",
            params: %{message: "Hello", format: "text"}
          },
          %{
            name: "JSON example",
            params: %{message: "Data", format: "json"}
          }
        ]
      }
    end

    def __tool__(:metadata), do: __tool__(:all)
    def __tool__(:name), do: :integration_test
    def __tool__(:parameters), do: __tool__(:all).parameters
    def __tool__(:execution), do: __tool__(:all).execution
    def __tool__(:security), do: __tool__(:all).security || %{}

    def execute(params, context) do
      case params[:format] || params.format || "text" do
        "json" ->
          {:ok,
           %{
             output: %{message: params.message, context: context.user.id},
             format: :json
           }}

        "markdown" ->
          {:ok,
           %{
             output: "# #{params.message}\n\nProcessed by: #{context.user.id}",
             format: :markdown
           }}

        _ ->
          {:ok, "Processed: #{params.message}"}
      end
    end
  end

  setup do
    # Start registry if not already started
    case Registry.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end

    # Register test tool
    Registry.register(IntegrationTestTool)
    :ok
  end

  describe "list_tools/0" do
    test "lists tools with enhanced metadata" do
      result = Bridge.list_tools()

      assert %{"tools" => tools} = result
      assert is_list(tools)

      # Find our test tool
      test_tool = Enum.find(tools, &(&1["name"] == "integration_test"))
      assert test_tool

      # Check enhanced metadata
      assert test_tool["description"] == "Tool for bridge integration testing"
      assert test_tool["inputSchema"]["type"] == "object"
      assert test_tool["inputSchema"]["required"] == ["message"]

      # Check capabilities
      assert test_tool["capabilities"]["supportsAsync"] == false
      assert test_tool["capabilities"]["maxExecutionTime"] == 5_000

      # Check metadata
      assert test_tool["metadata"]["version"] == "1.0.0"
      assert test_tool["metadata"]["category"] == :testing
    end
  end

  describe "execute_tool/3" do
    test "executes tool with MCP parameters" do
      context = %{
        user: %{id: "test_user"},
        session_id: "test_session"
      }

      result = Bridge.execute_tool("integration_test", %{"message" => "Hello MCP"}, context)

      assert %{"content" => content} = result
      assert [%{"type" => "text", "text" => text}] = content
      assert text == "Processed: Hello MCP"
    end

    test "handles JSON format output" do
      context = %{
        user: %{id: "test_user"},
        session_id: "test_session"
      }

      result =
        Bridge.execute_tool(
          "integration_test",
          %{"message" => "Test", "format" => "json"},
          context
        )

      assert %{"content" => content} = result
      assert [%{"type" => "text", "text" => json_text, "mimeType" => "application/json"}] = content

      # Verify it's valid JSON
      {:ok, parsed} = Jason.decode(json_text)
      assert parsed["message"] == "Test"
      assert parsed["context"] == "test_user"
    end

    test "handles tool not found" do
      result = Bridge.execute_tool("nonexistent_tool", %{}, %{})

      assert %{"content" => content, "isError" => true} = result
      assert [%{"type" => "text", "text" => error_text}] = content
      assert error_text =~ "Tool execution failed"
    end

    test "handles execution errors" do
      # Create a tool that will fail
      defmodule FailingTool do
        def __tool__(:all) do
          %{
            name: :failing_tool,
            description: "Always fails",
            parameters: [],
            execution: %{handler: :execute}
          }
        end

        def __tool__(:metadata), do: __tool__(:all)
        def __tool__(:name), do: :failing_tool
        def __tool__(:parameters), do: []
        def __tool__(:execution), do: __tool__(:all).execution
        def __tool__(:security), do: %{}

        def execute(_params, _context) do
          {:error, :deliberate_failure}
        end
      end

      Registry.register(FailingTool)

      result = Bridge.execute_tool("failing_tool", %{}, %{user: %{id: "test"}})

      assert %{"content" => content, "isError" => true} = result
      assert [%{"type" => "text", "text" => error_text}] = content
      assert error_text =~ "Tool execution failed"
    end
  end

  describe "list_resources/1" do
    test "includes tool resources" do
      result = Bridge.list_resources()

      assert %{"resources" => resources} = result

      # Find tool resources
      tool_resources = Enum.filter(resources, &(&1["uri"] =~ "tool://"))
      assert length(tool_resources) > 0

      # Check for our test tool's resources
      test_tool_resources = Enum.filter(tool_resources, &(&1["uri"] =~ "integration_test"))
      # doc, schema, examples
      assert length(test_tool_resources) >= 3

      # Verify resource types
      assert Enum.any?(test_tool_resources, &(&1["uri"] =~ "documentation"))
      assert Enum.any?(test_tool_resources, &(&1["uri"] =~ "schema"))
      assert Enum.any?(test_tool_resources, &(&1["uri"] =~ "examples"))
    end
  end

  describe "read_resource/2" do
    test "reads tool documentation" do
      result = Bridge.read_resource("tool://integration_test/documentation", %{})

      assert %{"contents" => contents} = result
      assert [content] = contents
      assert content["mimeType"] == "text/markdown"
      assert content["text"] =~ "bridge integration testing"
    end

    test "reads tool schema" do
      result = Bridge.read_resource("tool://integration_test/schema", %{})

      assert %{"contents" => contents} = result
      assert [content] = contents
      assert content["mimeType"] == "application/schema+json"

      # Verify schema is valid JSON
      {:ok, schema} = Jason.decode(content["text"])
      assert schema["type"] == "object"
      assert schema["required"] == ["message"]
      assert schema["properties"]["message"]["type"] == "string"
    end

    test "reads tool examples" do
      result = Bridge.read_resource("tool://integration_test/examples", %{})

      assert %{"contents" => contents} = result
      assert [content] = contents
      assert content["mimeType"] == "application/json"

      # Verify examples are valid JSON
      {:ok, examples} = Jason.decode(content["text"])
      assert is_list(examples)
      assert length(examples) == 2
    end

    test "handles invalid tool resource" do
      result = Bridge.read_resource("tool://nonexistent/schema", %{})

      assert %{"contents" => contents, "isError" => true} = result
      assert [content] = contents
      assert content["text"] =~ "Tool not found"
    end

    test "handles unknown resource type" do
      result = Bridge.read_resource("tool://integration_test/unknown", %{})

      assert %{"contents" => contents, "isError" => true} = result
      assert [content] = contents
      assert content["text"] =~ "Unknown resource type"
    end
  end

  describe "list_prompts/0" do
    test "includes tool-specific prompts" do
      result = Bridge.list_prompts()

      assert %{"prompts" => prompts} = result
      assert is_list(prompts)

      # Should have built-in prompts
      assert Enum.any?(prompts, &(&1["name"] == "analyze_code"))
      assert Enum.any?(prompts, &(&1["name"] == "generate_tests"))

      # Should have tool-specific prompts
      tool_prompts = Enum.filter(prompts, &(&1["name"] =~ "integration_test"))
      assert length(tool_prompts) >= 1
    end
  end

  describe "get_prompt/1" do
    test "gets built-in prompt" do
      result = Bridge.get_prompt("analyze_code")

      assert result["description"] =~ "Analyze code"
      assert result["arguments"]
      assert result["messages"]
    end

    test "handles prompt not found" do
      result = Bridge.get_prompt("nonexistent_prompt")

      assert result["isError"] == true
      assert result["description"] =~ "not found"
    end
  end
end
