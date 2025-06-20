defmodule RubberDuck.Commands.CommandMetadataTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Commands.CommandMetadata
  alias RubberDuck.Commands.CommandMetadata.Parameter

  describe "CommandMetadata" do
    test "creates metadata with required fields" do
      metadata = %CommandMetadata{
        name: "test",
        description: "A test command",
        category: :general
      }

      assert metadata.name == "test"
      assert metadata.description == "A test command"
      assert metadata.category == :general
      assert metadata.parameters == []
      assert metadata.examples == []
      assert metadata.async == false
      assert metadata.stream == false
    end

    test "creates metadata with all fields" do
      metadata = %CommandMetadata{
        name: "complex",
        description: "A complex command",
        category: :analysis,
        parameters: [
          %Parameter{
            name: :file,
            type: :string,
            required: true,
            description: "File to analyze"
          }
        ],
        examples: [
          %{
            description: "Analyze a file",
            command: "complex --file test.ex"
          }
        ],
        async: true,
        stream: true,
        aliases: ["comp", "cx"],
        deprecated: false,
        interface_hints: %{
          cli: %{show_progress: true},
          tui: %{interactive: true}
        }
      }

      assert metadata.name == "complex"
      assert length(metadata.parameters) == 1
      assert length(metadata.examples) == 1
      assert metadata.async == true
      assert metadata.stream == true
      assert metadata.aliases == ["comp", "cx"]
      assert metadata.interface_hints[:cli][:show_progress] == true
    end

    test "validates command name" do
      assert_raise ArgumentError, ~r/Command name must be a non-empty string/, fn ->
        %CommandMetadata{
          name: "",
          description: "Test",
          category: :general
        } |> CommandMetadata.validate!()
      end

      assert_raise ArgumentError, ~r/Command name must be a non-empty string/, fn ->
        %CommandMetadata{
          name: nil,
          description: "Test",
          category: :general
        } |> CommandMetadata.validate!()
      end
    end

    test "validates category" do
      assert_raise ArgumentError, ~r/Category must be an atom/, fn ->
        %CommandMetadata{
          name: "test",
          description: "Test",
          category: "general"
        } |> CommandMetadata.validate!()
      end
    end
  end

  describe "CommandMetadata.Parameter" do
    test "creates parameter with required fields" do
      param = %Parameter{
        name: :input,
        type: :string,
        required: true,
        description: "Input value"
      }

      assert param.name == :input
      assert param.type == :string
      assert param.required == true
      assert param.description == "Input value"
      assert param.default == nil
    end

    test "creates parameter with all fields" do
      param = %Parameter{
        name: :count,
        type: :integer,
        required: false,
        default: 10,
        description: "Number of items",
        validator: fn v -> v > 0 end,
        choices: nil
      }

      assert param.name == :count
      assert param.type == :integer
      assert param.required == false
      assert param.default == 10
      assert is_function(param.validator, 1)
    end

    test "supports parameter with choices" do
      param = %Parameter{
        name: :format,
        type: :string,
        required: true,
        description: "Output format",
        choices: ["json", "xml", "yaml"]
      }

      assert param.choices == ["json", "xml", "yaml"]
    end

    test "validates parameter type" do
      assert_raise ArgumentError, ~r/Invalid parameter type/, fn ->
        %Parameter{
          name: :test,
          type: :invalid_type,
          required: true,
          description: "Test"
        } |> Parameter.validate!()
      end
    end

    test "validates parameter name" do
      assert_raise ArgumentError, ~r/Parameter name must be an atom/, fn ->
        %Parameter{
          name: "test",
          type: :string,
          required: true,
          description: "Test"
        } |> Parameter.validate!()
      end
    end
  end

  describe "CommandMetadata validation" do
    test "validate!/1 returns metadata for valid struct" do
      metadata = %CommandMetadata{
        name: "valid",
        description: "A valid command",
        category: :general,
        parameters: [
          %Parameter{
            name: :test,
            type: :string,
            required: true,
            description: "Test param"
          }
        ]
      }

      assert CommandMetadata.validate!(metadata) == metadata
    end

    test "validate!/1 validates all parameters" do
      assert_raise ArgumentError, ~r/Invalid parameter type/, fn ->
        %CommandMetadata{
          name: "invalid",
          description: "Invalid command",
          category: :general,
          parameters: [
            %Parameter{
              name: :bad,
              type: :bad_type,
              required: true,
              description: "Bad param"
            }
          ]
        } |> CommandMetadata.validate!()
      end
    end
  end

  describe "CommandMetadata helpers" do
    test "has_required_params?/1 checks for required parameters" do
      metadata_with_required = %CommandMetadata{
        name: "test",
        description: "Test",
        category: :general,
        parameters: [
          %Parameter{name: :req, type: :string, required: true, description: "Required"},
          %Parameter{name: :opt, type: :string, required: false, description: "Optional"}
        ]
      }

      metadata_without_required = %CommandMetadata{
        name: "test2",
        description: "Test2",
        category: :general,
        parameters: [
          %Parameter{name: :opt, type: :string, required: false, description: "Optional"}
        ]
      }

      assert CommandMetadata.has_required_params?(metadata_with_required) == true
      assert CommandMetadata.has_required_params?(metadata_without_required) == false
    end

    test "parameter_names/1 returns list of parameter names" do
      metadata = %CommandMetadata{
        name: "test",
        description: "Test",
        category: :general,
        parameters: [
          %Parameter{name: :first, type: :string, required: true, description: "First"},
          %Parameter{name: :second, type: :integer, required: false, description: "Second"}
        ]
      }

      assert CommandMetadata.parameter_names(metadata) == [:first, :second]
    end
  end
end