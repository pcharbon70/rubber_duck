defmodule RubberDuck.MCP.Registry.CompositionTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Registry
  alias RubberDuck.MCP.Registry.Composition

  @moduletag :mcp_registry

  # Mock tools for testing
  defmodule ToolA do
    use Hermes.Server.Component, type: :tool

    @capabilities [:text_processing, :async]

    schema do
      field :input, :string
    end

    def execute(_, frame), do: {:ok, %{"output" => "A"}, frame}
  end

  defmodule ToolB do
    use Hermes.Server.Component, type: :tool

    @capabilities [:text_analysis, :streaming]

    schema do
      field :data, :string
    end

    def execute(_, frame), do: {:ok, %{"result" => "B"}, frame}
  end

  defmodule ToolC do
    use Hermes.Server.Component, type: :tool

    @capabilities [:validation]

    schema do
      field :value, :any
    end

    def execute(_, frame), do: {:ok, %{"valid" => true}, frame}
  end

  setup do
    # Start registry and register tools
    start_supervised!(Registry)
    Registry.register_tool(ToolA)
    Registry.register_tool(ToolB)
    Registry.register_tool(ToolC)
    :ok
  end

  describe "composition creation" do
    test "creates sequential composition" do
      comp =
        Composition.sequential("test_seq", [
          %{tool: ToolA, params: %{input: "test"}},
          %{tool: ToolB, params: %{}}
        ])

      assert comp.type == :sequential
      assert comp.name == "test_seq"
      assert length(comp.tools) == 2
      assert comp.id =~ ~r/^comp_/
    end

    test "creates parallel composition" do
      comp =
        Composition.parallel("test_par", [
          ToolA,
          ToolB,
          ToolC
        ])

      assert comp.type == :parallel
      assert length(comp.tools) == 3
    end

    test "creates conditional composition" do
      comp =
        Composition.conditional("test_cond", [
          %{tool: ToolA, condition: fn %{type: type} -> type == "A" end},
          %{tool: ToolB, condition: fn %{type: type} -> type == "B" end},
          # Default case
          %{tool: ToolC}
        ])

      assert comp.type == :conditional
      assert comp.tools |> Enum.at(0) |> Map.get(:condition) |> is_function()
      assert comp.tools |> Enum.at(2) |> Map.get(:condition) == nil
    end

    test "normalizes tool specifications" do
      comp =
        Composition.sequential("test", [
          # Just module
          ToolA,
          # Tuple
          {ToolB, %{data: "test"}},
          # Full spec
          %{tool: ToolC, params: %{value: 123}}
        ])

      assert Enum.all?(comp.tools, fn spec ->
               Map.has_key?(spec, :tool) and
                 Map.has_key?(spec, :params) and
                 Map.has_key?(spec, :output_mapping) and
                 Map.has_key?(spec, :condition)
             end)
    end
  end

  describe "composition validation" do
    test "validates all tools exist" do
      comp =
        Composition.sequential("test", [
          %{tool: ToolA},
          %{tool: NonExistentTool}
        ])

      assert {:error, {:tool_not_found, NonExistentTool}} = Composition.validate(comp)
    end

    test "validates sequential data flow" do
      comp =
        Composition.sequential("test", [
          %{tool: ToolA, params: %{}},
          %{tool: ToolB, output_mapping: %{"input" => "previous.output"}}
        ])

      assert :ok = Composition.validate(comp)
    end

    test "validates conditional structure" do
      # Invalid - middle tool without condition
      comp =
        Composition.conditional("test", [
          %{tool: ToolA, condition: fn _ -> true end},
          # Missing condition
          %{tool: ToolB},
          %{tool: ToolC, condition: fn _ -> false end}
        ])

      assert {:error, :invalid_conditional_structure} = Composition.validate(comp)
    end

    test "validates capability compatibility" do
      # These tools have composable capabilities
      comp =
        Composition.sequential("test", [
          # text_processing
          %{tool: ToolA},
          # text_analysis  
          %{tool: ToolB}
        ])

      assert :ok = Composition.validate(comp)
    end
  end

  describe "composition execution" do
    @tag :skip
    test "executes sequential composition" do
      comp =
        Composition.sequential("test", [
          %{tool: ToolA, params: %{input: "hello"}},
          %{tool: ToolB, params: %{data: "world"}}
        ])

      result = Composition.execute(comp, %{})

      assert result.status == :success
      assert length(result.results) == 2
      assert result.final_output
    end

    @tag :skip
    test "executes parallel composition" do
      comp =
        Composition.parallel("test", [
          %{tool: ToolA, params: %{input: "a"}},
          %{tool: ToolB, params: %{data: "b"}},
          %{tool: ToolC, params: %{value: "c"}}
        ])

      result = Composition.execute(comp, %{}, timeout: 5000)

      assert result.status == :success
      assert length(result.results) == 3
    end

    @tag :skip
    test "executes conditional composition" do
      comp =
        Composition.conditional("test", [
          %{tool: ToolA, condition: fn %{use: use} -> use == "A" end},
          %{tool: ToolB, condition: fn %{use: use} -> use == "B" end},
          # Default
          %{tool: ToolC}
        ])

      result = Composition.execute(comp, %{use: "B"})

      assert result.status == :success
      assert length(result.results) == 1
      # Should have executed ToolB
    end

    @tag :skip
    test "handles execution errors" do
      # Create a failing tool
      defmodule FailingTool do
        use Hermes.Server.Component, type: :tool

        schema do
          field :x, :integer
        end

        def execute(_, _), do: {:error, :intentional_failure}
      end

      Registry.register_tool(FailingTool)

      comp =
        Composition.sequential("test", [
          %{tool: ToolA},
          %{tool: FailingTool},
          %{tool: ToolB}
        ])

      result = Composition.execute(comp, %{})

      assert result.status == :partial
      # Only ToolA succeeded
      assert length(result.results) == 1
      assert length(result.errors) > 0
    end
  end

  describe "composition analysis" do
    test "finds parallelizable steps" do
      comp =
        Composition.sequential("test", [
          %{tool: ToolA},
          # No output mapping, could be parallel
          %{tool: ToolB},
          %{tool: ToolC, output_mapping: %{"prev" => "result"}}
        ])

      analysis = Composition.analyze(comp)
      assert is_list(analysis.parallelizable_steps)
    end

    test "finds redundant tools" do
      comp =
        Composition.sequential("test", [
          %{tool: ToolA, params: %{input: "x"}},
          %{tool: ToolB, params: %{data: "y"}},
          # Duplicate
          %{tool: ToolA, params: %{input: "x"}}
        ])

      analysis = Composition.analyze(comp)
      redundant = analysis.redundant_tools

      assert length(redundant) == 1
      assert hd(redundant).tool == ToolA
    end

    test "estimates latency" do
      comp = Composition.sequential("test", [ToolA, ToolB, ToolC])

      analysis = Composition.analyze(comp)
      assert is_number(analysis.estimated_latency)
      assert analysis.estimated_latency > 0
    end
  end

  describe "visualization" do
    test "generates Mermaid diagram for sequential" do
      comp = Composition.sequential("test", [ToolA, ToolB])
      diagram = Composition.to_diagram(comp)

      assert diagram =~ "graph TD"
      assert diagram =~ "T0[#{inspect(ToolA)}]"
      assert diagram =~ "T1[#{inspect(ToolB)}]"
      assert diagram =~ "T0 --> T1"
    end

    test "generates Mermaid diagram for parallel" do
      comp = Composition.parallel("test", [ToolA, ToolB, ToolC])
      diagram = Composition.to_diagram(comp)

      assert diagram =~ "Start[Input]"
      assert diagram =~ "End[Output]"
      assert diagram =~ "Start --> T0"
      assert diagram =~ "Start --> T1"
      assert diagram =~ "Start --> T2"
    end

    test "generates Mermaid diagram for conditional" do
      comp =
        Composition.conditional("test", [
          %{tool: ToolA, condition: fn _ -> true end},
          %{tool: ToolB}
        ])

      diagram = Composition.to_diagram(comp)

      assert diagram =~ "Start --condition--> T0"
      assert diagram =~ "Start --default--> T1"
    end
  end
end
