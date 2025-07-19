defmodule RubberDuck.MCP.RegistryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Registry
  alias RubberDuck.MCP.Registry.{Metadata, Metrics}

  @moduletag :mcp_registry

  # Define a test tool module
  defmodule TestTool do
    use Hermes.Server.Component, type: :tool

    @category :test
    @tags [:test, :example]
    @capabilities [:text_processing, :async]

    schema do
      field :input, {:required, :string}
      field :async, :boolean, default: false
    end

    @impl true
    def execute(params, frame) do
      {:ok, %{"result" => "processed: #{params.input}"}, frame}
    end
  end

  defmodule TestTool2 do
    use Hermes.Server.Component, type: :tool

    @category :test
    @tags [:test, :another]
    @capabilities [:text_analysis, :streaming]

    schema do
      field :text, {:required, :string}
    end

    @impl true
    def execute(params, frame) do
      {:ok, %{"analysis" => "length: #{String.length(params.text)}"}, frame}
    end
  end

  setup do
    # Start registry
    start_supervised!(Registry)

    # Register test tools
    :ok = Registry.register_tool(TestTool, source: :test)
    :ok = Registry.register_tool(TestTool2, source: :test)

    :ok
  end

  describe "tool registration" do
    test "registers a tool successfully" do
      defmodule NewTool do
        use Hermes.Server.Component, type: :tool

        schema do
          field :data, :string
        end

        def execute(_, frame), do: {:ok, %{}, frame}
      end

      assert :ok = Registry.register_tool(NewTool)
      assert {:ok, metadata} = Registry.get_tool(NewTool)
      assert metadata.module == NewTool
    end

    test "fails to register invalid tool" do
      defmodule NotATool do
        def some_function, do: :ok
      end

      assert {:error, _} = Registry.register_tool(NotATool)
    end

    test "unregisters a tool" do
      assert :ok = Registry.unregister_tool(TestTool)
      assert {:error, :not_found} = Registry.get_tool(TestTool)
    end
  end

  describe "tool listing and filtering" do
    test "lists all tools" do
      assert {:ok, tools} = Registry.list_tools()
      assert length(tools) >= 2
      assert Enum.any?(tools, fn t -> t.module == TestTool end)
    end

    test "filters by category" do
      assert {:ok, tools} = Registry.list_tools(category: :test)
      assert Enum.all?(tools, fn t -> t.category == :test end)
    end

    test "filters by tags" do
      assert {:ok, tools} = Registry.list_tools(tags: [:example])
      assert Enum.any?(tools, fn t -> :example in t.tags end)
    end

    test "filters by capabilities" do
      assert {:ok, tools} = Registry.list_tools(capabilities: [:text_processing])
      assert Enum.any?(tools, fn t -> :text_processing in t.capabilities end)
    end
  end

  describe "tool discovery" do
    test "searches tools by query" do
      assert {:ok, results} = Registry.search_tools("test")
      assert length(results) >= 1
      assert Enum.any?(results, fn t -> String.contains?(String.downcase(t.name), "test") end)
    end

    test "discovers by capability" do
      assert {:ok, tools} = Registry.discover_by_capability(:text_processing)
      assert Enum.any?(tools, fn t -> :text_processing in t.capabilities end)
    end

    test "recommends tools based on context" do
      context = %{
        tags: [:test],
        required_capabilities: [:text_processing]
      }

      assert {:ok, recommendations} = Registry.recommend_tools(context, limit: 3)
      assert length(recommendations) <= 3
      # Should recommend TestTool highly
      assert Enum.any?(recommendations, fn t -> t.module == TestTool end)
    end
  end

  describe "metrics tracking" do
    test "records execution metrics" do
      Registry.record_metric(TestTool, {:execution, :success, 150}, nil)
      Registry.record_metric(TestTool, {:execution, :success, 200}, nil)
      Registry.record_metric(TestTool, {:execution, :failure, :timeout}, nil)

      assert {:ok, metrics} = Registry.get_metrics(TestTool)
      assert metrics.total_executions == 3
      assert metrics.successful_executions == 2
      assert metrics.failed_executions == 1
      assert Metrics.success_rate(metrics) < 100.0
    end

    test "calculates quality scores" do
      Registry.record_metric(TestTool2, {:execution, :success, 50}, nil)
      Registry.record_metric(TestTool2, {:execution, :success, 60}, nil)

      assert {:ok, metrics} = Registry.get_metrics(TestTool2)
      score = Metrics.quality_score(metrics)
      assert score > 0 and score <= 100
    end
  end

  describe "tool composition" do
    test "composes tools sequentially" do
      tool_specs = [
        %{tool: TestTool, params: %{input: "hello"}},
        %{tool: TestTool2, params: %{}}
      ]

      assert {:ok, composition} = Registry.compose_tools(tool_specs, type: :sequential)
      assert composition.tools == tool_specs
    end

    test "validates tool existence in composition" do
      tool_specs = [
        %{tool: NonExistentTool, params: %{}}
      ]

      assert {:error, {:tool_not_found, NonExistentTool}} =
               Registry.compose_tools(tool_specs)
    end
  end
end
