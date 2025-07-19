defmodule RubberDuck.Tool.DslTest do
  use ExUnit.Case, async: true

  describe "tool definition" do
    test "defines a simple tool with metadata" do
      defmodule SimpleTool do
        use RubberDuck.Tool

        tool do
          name :simple_tool
          description "A simple test tool"
          category(:testing)
          version("1.0.0")
        end
      end

      assert SimpleTool.__tool__(:name) == :simple_tool
      assert SimpleTool.__tool__(:description) == "A simple test tool"
      assert SimpleTool.__tool__(:category) == :testing
      assert SimpleTool.__tool__(:version) == "1.0.0"
    end

    test "defines tool with parameters" do
      defmodule ParameterizedTool do
        use RubberDuck.Tool

        tool do
          name :parameterized_tool

          parameter :input do
            type :string
            required(true)
            description "The input string to process"
          end

          parameter :count do
            type :integer
            required(false)
            default 1
            description "Number of times to repeat"
          end
        end
      end

      parameters = ParameterizedTool.__tool__(:parameters)
      assert length(parameters) == 2

      input_param = Enum.find(parameters, &(&1.name == :input))
      assert input_param.type == :string
      assert input_param.required == true

      count_param = Enum.find(parameters, &(&1.name == :count))
      assert count_param.type == :integer
      assert count_param.required == false
      assert count_param.default == 1
    end

    test "defines tool with execution configuration" do
      defmodule ExecutableTool do
        use RubberDuck.Tool

        tool do
          name :executable_tool

          execution do
            handler(&ExecutableTool.execute/2)
            timeout 5000
            async(true)
            retries(3)
          end
        end

        def execute(params, context) do
          {:ok, "Executed with #{inspect(params)}"}
        end
      end

      execution = ExecutableTool.__tool__(:execution)
      assert execution.timeout == 5000
      assert execution.async == true
      assert execution.retries == 3
      assert is_function(execution.handler, 2)
    end

    test "defines tool with security configuration" do
      defmodule SecureTool do
        use RubberDuck.Tool

        tool do
          name :secure_tool

          security do
            sandbox(:restricted)
            capabilities([:file_read, :network])
            rate_limit(per_minute: 10)
          end
        end
      end

      security = SecureTool.__tool__(:security)
      assert security.sandbox == :restricted
      assert security.capabilities == [:file_read, :network]
      assert security.rate_limit == [per_minute: 10]
    end

    test "validates required fields at compile time" do
      assert_raise Spark.Error.DslError, ~r/required :name option not found/, fn ->
        defmodule InvalidTool do
          use RubberDuck.Tool

          tool do
            description "Missing name"
          end
        end
      end
    end
  end
end
