defmodule RubberDuck.Commands.CommandMetadata do
  @moduledoc """
  Metadata structure for command definitions in the distributed commands subsystem.
  
  This module defines the structure for command metadata that enables:
  - Rich command description and documentation
  - Parameter validation and type checking
  - Interface-agnostic command definitions
  - Dynamic help generation
  - Command discovery and registration
  """

  @valid_parameter_types [:string, :integer, :float, :boolean, :atom, :list, :map]

  defstruct [
    :name,
    :description,
    :category,
    parameters: [],
    examples: [],
    async: false,
    stream: false,
    aliases: [],
    deprecated: false,
    interface_hints: %{}
  ]

  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    category: atom(),
    parameters: [Parameter.t()],
    examples: [example()],
    async: boolean(),
    stream: boolean(),
    aliases: [String.t()],
    deprecated: boolean(),
    interface_hints: map()
  }

  @type example :: %{
    description: String.t(),
    command: String.t()
  }

  defmodule Parameter do
    @moduledoc """
    Parameter definition for command metadata.
    """

    defstruct [
      :name,
      :type,
      :required,
      :description,
      default: nil,
      validator: nil,
      choices: nil
    ]

    @type t :: %__MODULE__{
      name: atom(),
      type: atom(),
      required: boolean(),
      description: String.t(),
      default: any(),
      validator: (any() -> boolean()) | nil,
      choices: [any()] | nil
    }

    @doc """
    Validates a parameter definition.
    """
    @spec validate!(t()) :: t()
    def validate!(%__MODULE__{} = param) do
      unless is_atom(param.name) do
        raise ArgumentError, "Parameter name must be an atom, got: #{inspect(param.name)}"
      end

      unless param.type in RubberDuck.Commands.CommandMetadata.valid_parameter_types() do
        raise ArgumentError, "Invalid parameter type: #{inspect(param.type)}. Valid types: #{inspect(RubberDuck.Commands.CommandMetadata.valid_parameter_types())}"
      end

      unless is_binary(param.description) and String.length(param.description) > 0 do
        raise ArgumentError, "Parameter description must be a non-empty string"
      end

      unless is_boolean(param.required) do
        raise ArgumentError, "Parameter required field must be a boolean"
      end

      param
    end
  end

  @doc """
  Returns the list of valid parameter types.
  """
  @spec valid_parameter_types() :: [atom()]
  def valid_parameter_types, do: @valid_parameter_types

  @doc """
  Validates command metadata.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = metadata) do
    unless is_binary(metadata.name) and String.length(metadata.name) > 0 do
      raise ArgumentError, "Command name must be a non-empty string, got: #{inspect(metadata.name)}"
    end

    unless is_binary(metadata.description) and String.length(metadata.description) > 0 do
      raise ArgumentError, "Command description must be a non-empty string"
    end

    unless is_atom(metadata.category) do
      raise ArgumentError, "Category must be an atom, got: #{inspect(metadata.category)}"
    end

    unless is_list(metadata.parameters) do
      raise ArgumentError, "Parameters must be a list"
    end

    # Validate all parameters
    Enum.each(metadata.parameters, &Parameter.validate!/1)

    unless is_list(metadata.examples) do
      raise ArgumentError, "Examples must be a list"
    end

    unless is_boolean(metadata.async) do
      raise ArgumentError, "Async field must be a boolean"
    end

    unless is_boolean(metadata.stream) do
      raise ArgumentError, "Stream field must be a boolean"
    end

    unless is_list(metadata.aliases) do
      raise ArgumentError, "Aliases must be a list"
    end

    unless is_boolean(metadata.deprecated) do
      raise ArgumentError, "Deprecated field must be a boolean"
    end

    unless is_map(metadata.interface_hints) do
      raise ArgumentError, "Interface hints must be a map"
    end

    metadata
  end

  @doc """
  Checks if the command has any required parameters.
  """
  @spec has_required_params?(t()) :: boolean()
  def has_required_params?(%__MODULE__{parameters: parameters}) do
    Enum.any?(parameters, & &1.required)
  end

  @doc """
  Returns a list of parameter names for the command.
  """
  @spec parameter_names(t()) :: [atom()]
  def parameter_names(%__MODULE__{parameters: parameters}) do
    Enum.map(parameters, & &1.name)
  end

  @doc """
  Returns the required parameters for the command.
  """
  @spec required_parameters(t()) :: [Parameter.t()]
  def required_parameters(%__MODULE__{parameters: parameters}) do
    Enum.filter(parameters, & &1.required)
  end

  @doc """
  Returns the optional parameters for the command.
  """
  @spec optional_parameters(t()) :: [Parameter.t()]
  def optional_parameters(%__MODULE__{parameters: parameters}) do
    Enum.reject(parameters, & &1.required)
  end

  @doc """
  Finds a parameter by name.
  """
  @spec find_parameter(t(), atom()) :: Parameter.t() | nil
  def find_parameter(%__MODULE__{parameters: parameters}, name) do
    Enum.find(parameters, &(&1.name == name))
  end

  @doc """
  Generates a help string for the command.
  """
  @spec help_text(t()) :: String.t()
  def help_text(%__MODULE__{} = metadata) do
    """
    #{metadata.name} - #{metadata.description}

    Category: #{metadata.category}
    #{if metadata.deprecated, do: "⚠️  DEPRECATED", else: ""}

    #{parameters_help(metadata)}

    #{examples_help(metadata)}

    #{aliases_help(metadata)}
    """
    |> String.trim()
  end

  defp parameters_help(%__MODULE__{parameters: []}), do: ""
  defp parameters_help(%__MODULE__{parameters: parameters}) do
    """
    Parameters:
    #{Enum.map_join(parameters, "\n", &parameter_help/1)}
    """
  end

  defp parameter_help(%Parameter{} = param) do
    required_text = if param.required, do: "(required)", else: "(optional)"
    default_text = if param.default, do: " [default: #{inspect(param.default)}]", else: ""
    choices_text = if param.choices, do: " [choices: #{Enum.join(param.choices, ", ")}]", else: ""
    
    "  --#{param.name} (#{param.type}) #{required_text}#{default_text}#{choices_text}\n    #{param.description}"
  end

  defp examples_help(%__MODULE__{examples: []}), do: ""
  defp examples_help(%__MODULE__{examples: examples}) do
    """
    Examples:
    #{Enum.map_join(examples, "\n", &example_help/1)}
    """
  end

  defp example_help(%{description: desc, command: cmd}) do
    "  #{desc}:\n    #{cmd}"
  end

  defp aliases_help(%__MODULE__{aliases: []}), do: ""
  defp aliases_help(%__MODULE__{aliases: aliases}) do
    "Aliases: #{Enum.join(aliases, ", ")}"
  end
end