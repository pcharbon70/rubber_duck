defmodule RubberDuck.Commands.CommandBehaviourTest do
  use ExUnit.Case, async: true

  describe "CommandBehaviour" do
    defmodule TestCommand do
      @behaviour RubberDuck.Commands.CommandBehaviour

      @impl true
      def metadata do
        %RubberDuck.Commands.CommandMetadata{
          name: "test",
          description: "A test command",
          category: :testing,
          parameters: [
            %RubberDuck.Commands.CommandMetadata.Parameter{
              name: :input,
              type: :string,
              required: true,
              description: "Test input parameter"
            },
            %RubberDuck.Commands.CommandMetadata.Parameter{
              name: :verbose,
              type: :boolean,
              required: false,
              default: false,
              description: "Enable verbose output"
            }
          ],
          examples: [
            %{
              description: "Basic usage",
              command: "test --input 'hello world'"
            }
          ]
        }
      end

      @impl true
      def validate(params) do
        cond do
          is_nil(params[:input]) ->
            {:error, [{:input, "is required"}]}

          not is_binary(params[:input]) ->
            {:error, [{:input, "must be a string"}]}

          params[:verbose] not in [nil, true, false] ->
            {:error, [{:verbose, "must be a boolean"}]}

          true ->
            :ok
        end
      end

      @impl true
      def execute(params, context) do
        result = if params[:verbose] do
          "Executing test command with input: #{params[:input]} in context: #{inspect(context)}"
        else
          "Test result: #{params[:input]}"
        end

        {:ok, result}
      end
    end

    test "defines required callbacks" do
      assert function_exported?(TestCommand, :metadata, 0)
      assert function_exported?(TestCommand, :validate, 1)
      assert function_exported?(TestCommand, :execute, 2)
    end

    test "metadata returns CommandMetadata struct" do
      metadata = TestCommand.metadata()
      assert %RubberDuck.Commands.CommandMetadata{} = metadata
      assert metadata.name == "test"
      assert metadata.category == :testing
      assert length(metadata.parameters) == 2
    end

    test "validate accepts valid parameters" do
      assert :ok == TestCommand.validate(%{input: "hello", verbose: true})
      assert :ok == TestCommand.validate(%{input: "hello"})
    end

    test "validate rejects invalid parameters" do
      assert {:error, [{:input, "is required"}]} == TestCommand.validate(%{})
      assert {:error, [{:input, "must be a string"}]} == TestCommand.validate(%{input: 123})
      assert {:error, [{:verbose, "must be a boolean"}]} == TestCommand.validate(%{input: "hi", verbose: "yes"})
    end

    test "execute returns success tuple" do
      assert {:ok, "Test result: hello"} == TestCommand.execute(%{input: "hello"}, %{})
      assert {:ok, result} = TestCommand.execute(%{input: "hello", verbose: true}, %{user: "test"})
      assert result =~ "Executing test command"
      assert result =~ "context: %{user: \"test\"}"
    end
  end

  describe "CommandBehaviour with async command" do
    defmodule AsyncCommand do
      @behaviour RubberDuck.Commands.CommandBehaviour

      @impl true
      def metadata do
        %RubberDuck.Commands.CommandMetadata{
          name: "async_test",
          description: "An async test command",
          category: :testing,
          async: true,
          parameters: []
        }
      end

      @impl true
      def validate(_params), do: :ok

      @impl true
      def execute(_params, _context) do
        # Simulate async work
        Process.sleep(10)
        {:ok, :async_result}
      end
    end

    test "async command can be executed" do
      assert AsyncCommand.metadata().async == true
      assert {:ok, :async_result} == AsyncCommand.execute(%{}, %{})
    end
  end

  describe "CommandBehaviour with streaming response" do
    defmodule StreamCommand do
      @behaviour RubberDuck.Commands.CommandBehaviour

      @impl true
      def metadata do
        %RubberDuck.Commands.CommandMetadata{
          name: "stream_test",
          description: "A streaming test command",
          category: :testing,
          stream: true,
          parameters: []
        }
      end

      @impl true
      def validate(_params), do: :ok

      @impl true
      def execute(_params, _context) do
        stream = Stream.iterate(1, &(&1 + 1))
                 |> Stream.take(3)
                 |> Stream.map(&"Item #{&1}")

        {:ok, {:stream, stream}}
      end
    end

    test "streaming command returns stream tuple" do
      assert StreamCommand.metadata().stream == true
      assert {:ok, {:stream, stream}} = StreamCommand.execute(%{}, %{})
      assert Enum.to_list(stream) == ["Item 1", "Item 2", "Item 3"]
    end
  end
end