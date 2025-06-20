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

  @valid_parameter_types [
    # Basic types
    :string, :integer, :float, :boolean, :atom, :list, :map,
    # Advanced types
    :file_path, :directory, :url, :regex, :enum, :json,
    # Composite types
    :string_list, :integer_list, :key_value_pairs
  ]

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
    interface_hints: %{},
    # Phase 8.2 enhancements
    parameter_groups: [],
    when_conditions: [],
    input_types: [],
    output_types: [],
    version: "1.0.0",
    tags: []
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
    interface_hints: map(),
    # Phase 8.2 enhancements
    parameter_groups: [parameter_group()],
    when_conditions: [when_condition()],
    input_types: [atom()],
    output_types: [atom()],
    version: String.t(),
    tags: [atom()]
  }

  @type example :: %{
    description: String.t(),
    command: String.t(),
    expected_output: String.t() | nil
  }

  @type parameter_group :: %{
    name: String.t(),
    description: String.t(),
    parameters: [atom()],
    collapsible: boolean(),
    advanced: boolean()
  }

  @type when_condition :: %{
    type: :file_type | :project_type | :interface | :permission | :custom,
    condition: any(),
    description: String.t()
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
      choices: nil,
      # Phase 8.2 enhancements
      group: nil,
      depends_on: [],
      conditional_visibility: nil,
      interface_hints: %{},
      placeholder: nil,
      help_text: nil,
      min_value: nil,
      max_value: nil,
      pattern: nil,
      multiple: false
    ]

    @type t :: %__MODULE__{
      name: atom(),
      type: atom(),
      required: boolean(),
      description: String.t(),
      default: any(),
      validator: (any() -> boolean()) | nil,
      choices: [any()] | nil,
      # Phase 8.2 enhancements
      group: String.t() | nil,
      depends_on: [dependency()],
      conditional_visibility: conditional_visibility() | nil,
      interface_hints: map(),
      placeholder: String.t() | nil,
      help_text: String.t() | nil,
      min_value: number() | nil,
      max_value: number() | nil,
      pattern: String.t() | nil,
      multiple: boolean()
    }

    @type dependency :: %{
      parameter: atom(),
      condition: :equals | :not_equals | :greater_than | :less_than | :contains,
      value: any()
    }

    @type conditional_visibility :: %{
      show_when: [dependency()],
      hide_when: [dependency()]
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

      # Validate new Phase 8.2 fields
      if param.group && not is_binary(param.group) do
        raise ArgumentError, "Parameter group must be a string"
      end

      unless is_list(param.depends_on) do
        raise ArgumentError, "Parameter depends_on must be a list"
      end

      unless is_map(param.interface_hints) do
        raise ArgumentError, "Parameter interface_hints must be a map"
      end

      unless is_boolean(param.multiple) do
        raise ArgumentError, "Parameter multiple field must be a boolean"
      end

      # Validate type-specific constraints
      validate_type_constraints!(param)

      param
    end

    @doc """
    Validates type-specific parameter constraints.
    """
    @spec validate_type_constraints!(t()) :: :ok
    def validate_type_constraints!(%__MODULE__{} = param) do
      case param.type do
        :enum ->
          unless param.choices && is_list(param.choices) && length(param.choices) > 0 do
            raise ArgumentError, "Parameter of type :enum must have non-empty choices list"
          end

        :regex ->
          if param.pattern do
            try do
              Regex.compile!(param.pattern)
            rescue
              _ -> raise ArgumentError, "Parameter pattern must be a valid regex string"
            end
          end

        type when type in [:integer, :float] ->
          if param.min_value && param.max_value && param.min_value > param.max_value do
            raise ArgumentError, "Parameter min_value cannot be greater than max_value"
          end

        :file_path ->
          # File path specific validation can be added here
          :ok

        :directory ->
          # Directory specific validation can be added here
          :ok

        :url ->
          # URL specific validation can be added here
          :ok

        _ ->
          :ok
      end

      :ok
    end

    @doc """
    Validates a parameter value against its definition.
    """
    @spec validate_value(t(), any()) :: :ok | {:error, String.t()}
    def validate_value(%__MODULE__{} = param, value) do
      with :ok <- validate_required(param, value),
           :ok <- validate_type(param, value),
           :ok <- validate_choices(param, value),
           :ok <- validate_range(param, value),
           :ok <- validate_pattern(param, value),
           :ok <- validate_custom(param, value) do
        :ok
      end
    end

    defp validate_required(%{required: true}, nil), do: {:error, "is required"}
    defp validate_required(_, _), do: :ok

    defp validate_type(_, nil), do: :ok
    defp validate_type(%{type: :string}, value) when is_binary(value), do: :ok
    defp validate_type(%{type: :integer}, value) when is_integer(value), do: :ok
    defp validate_type(%{type: :float}, value) when is_float(value), do: :ok
    defp validate_type(%{type: :boolean}, value) when is_boolean(value), do: :ok
    defp validate_type(%{type: :atom}, value) when is_atom(value), do: :ok
    defp validate_type(%{type: :list}, value) when is_list(value), do: :ok
    defp validate_type(%{type: :map}, value) when is_map(value), do: :ok
    defp validate_type(%{type: :file_path}, value) when is_binary(value), do: validate_file_path(value)
    defp validate_type(%{type: :directory}, value) when is_binary(value), do: validate_directory(value)
    defp validate_type(%{type: :url}, value) when is_binary(value), do: validate_url(value)
    defp validate_type(%{type: :regex}, value) when is_binary(value), do: validate_regex(value)
    defp validate_type(%{type: :enum}, value), do: :ok  # Will be validated by validate_choices
    defp validate_type(%{type: :json}, value) when is_binary(value), do: validate_json(value)
    defp validate_type(%{type: :string_list}, value) when is_list(value) do
      if Enum.all?(value, &is_binary/1), do: :ok, else: {:error, "must be a list of strings"}
    end
    defp validate_type(%{type: :integer_list}, value) when is_list(value) do
      if Enum.all?(value, &is_integer/1), do: :ok, else: {:error, "must be a list of integers"}
    end
    defp validate_type(%{type: :key_value_pairs}, value) when is_map(value), do: :ok
    defp validate_type(%{type: type}, _), do: {:error, "must be of type #{type}"}

    defp validate_choices(%{choices: nil}, _), do: :ok
    defp validate_choices(%{choices: choices}, value) do
      if value in choices, do: :ok, else: {:error, "must be one of: #{Enum.join(choices, ", ")}"}
    end

    defp validate_range(%{min_value: nil, max_value: nil}, _), do: :ok
    defp validate_range(%{min_value: min, max_value: max}, value) when is_number(value) do
      cond do
        min && value < min -> {:error, "must be at least #{min}"}
        max && value > max -> {:error, "must be at most #{max}"}
        true -> :ok
      end
    end
    defp validate_range(_, _), do: :ok

    defp validate_pattern(%{pattern: nil}, _), do: :ok
    defp validate_pattern(%{pattern: pattern}, value) when is_binary(value) do
      if Regex.match?(Regex.compile!(pattern), value) do
        :ok
      else
        {:error, "must match pattern #{pattern}"}
      end
    end
    defp validate_pattern(_, _), do: :ok

    defp validate_custom(%{validator: nil}, _), do: :ok
    defp validate_custom(%{validator: validator}, value) when is_function(validator, 1) do
      if validator.(value), do: :ok, else: {:error, "failed custom validation"}
    end
    defp validate_custom(_, _), do: :ok

    # Type-specific validation helpers
    defp validate_file_path(path) do
      if String.contains?(path, ["\0", "<", ">", ":", "\"", "|", "?", "*"]) do
        {:error, "contains invalid file path characters"}
      else
        :ok
      end
    end

    defp validate_directory(path), do: validate_file_path(path)

    defp validate_url(url) do
      uri = URI.parse(url)
      if uri.scheme && uri.host do
        :ok
      else
        {:error, "must be a valid URL"}
      end
    end

    defp validate_regex(pattern) do
      try do
        Regex.compile!(pattern)
        :ok
      rescue
        _ -> {:error, "must be a valid regular expression"}
      end
    end

    defp validate_json(json) do
      try do
        Jason.decode!(json)
        :ok
      rescue
        _ -> {:error, "must be valid JSON"}
      end
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

    # Validate Phase 8.2 fields
    unless is_list(metadata.parameter_groups) do
      raise ArgumentError, "Parameter groups must be a list"
    end

    unless is_list(metadata.when_conditions) do
      raise ArgumentError, "When conditions must be a list"
    end

    unless is_list(metadata.input_types) do
      raise ArgumentError, "Input types must be a list"
    end

    unless is_list(metadata.output_types) do
      raise ArgumentError, "Output types must be a list"
    end

    unless is_binary(metadata.version) and String.length(metadata.version) > 0 do
      raise ArgumentError, "Version must be a non-empty string"
    end

    unless is_list(metadata.tags) do
      raise ArgumentError, "Tags must be a list"
    end

    # Validate parameter groups reference existing parameters
    validate_parameter_groups!(metadata)

    # Validate parameter dependencies
    validate_parameter_dependencies!(metadata)

    metadata
  end

  @doc """
  Validates that parameter groups reference existing parameters.
  """
  @spec validate_parameter_groups!(t()) :: :ok
  def validate_parameter_groups!(%__MODULE__{} = metadata) do
    param_names = parameter_names(metadata)
    
    Enum.each(metadata.parameter_groups, fn group ->
      unless is_map(group) do
        raise ArgumentError, "Parameter group must be a map"
      end

      unless Map.has_key?(group, :name) and is_binary(group.name) do
        raise ArgumentError, "Parameter group must have a name"
      end

      unless Map.has_key?(group, :parameters) and is_list(group.parameters) do
        raise ArgumentError, "Parameter group must have a parameters list"
      end

      invalid_params = group.parameters -- param_names
      unless Enum.empty?(invalid_params) do
        raise ArgumentError, "Parameter group '#{group.name}' references non-existent parameters: #{inspect(invalid_params)}"
      end
    end)

    :ok
  end

  @doc """
  Validates parameter dependencies reference existing parameters.
  """
  @spec validate_parameter_dependencies!(t()) :: :ok
  def validate_parameter_dependencies!(%__MODULE__{} = metadata) do
    param_names = parameter_names(metadata)
    
    Enum.each(metadata.parameters, fn param ->
      Enum.each(param.depends_on, fn dep ->
        unless is_map(dep) and Map.has_key?(dep, :parameter) do
          raise ArgumentError, "Parameter dependency must have a :parameter field"
        end

        unless dep.parameter in param_names do
          raise ArgumentError, "Parameter '#{param.name}' depends on non-existent parameter '#{dep.parameter}'"
        end

        if dep.parameter == param.name do
          raise ArgumentError, "Parameter '#{param.name}' cannot depend on itself"
        end
      end)
    end)

    :ok
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
  Gets parameters grouped by their group name.
  """
  @spec parameters_by_group(t()) :: %{String.t() => [Parameter.t()]}
  def parameters_by_group(%__MODULE__{parameters: parameters}) do
    parameters
    |> Enum.group_by(fn param -> param.group || "default" end)
  end

  @doc """
  Gets parameters that should be visible given the current parameter values.
  """
  @spec visible_parameters(t(), map()) :: [Parameter.t()]
  def visible_parameters(%__MODULE__{parameters: parameters}, current_values \\ %{}) do
    Enum.filter(parameters, fn param ->
      is_parameter_visible?(param, current_values)
    end)
  end

  @doc """
  Checks if a parameter should be visible given the current parameter values.
  """
  @spec is_parameter_visible?(Parameter.t(), map()) :: boolean()
  def is_parameter_visible?(%Parameter{conditional_visibility: nil}, _), do: true
  def is_parameter_visible?(%Parameter{conditional_visibility: conditions}, current_values) do
    show_conditions = Map.get(conditions, :show_when, [])
    hide_conditions = Map.get(conditions, :hide_when, [])

    should_show = Enum.empty?(show_conditions) or Enum.any?(show_conditions, &check_dependency(&1, current_values))
    should_hide = not Enum.empty?(hide_conditions) and Enum.any?(hide_conditions, &check_dependency(&1, current_values))

    should_show and not should_hide
  end

  @doc """
  Validates all parameter values against their definitions.
  """
  @spec validate_parameters(t(), map()) :: :ok | {:error, [{atom(), String.t()}]}
  def validate_parameters(%__MODULE__{parameters: parameters}, values) do
    errors = 
      parameters
      |> Enum.filter(&is_parameter_visible?(&1, values))
      |> Enum.flat_map(fn param ->
        case Parameter.validate_value(param, Map.get(values, param.name)) do
          :ok -> []
          {:error, message} -> [{param.name, message}]
        end
      end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Checks if the command is available given the current context.
  """
  @spec is_available?(t(), map()) :: boolean()
  def is_available?(%__MODULE__{when_conditions: conditions}, context) do
    Enum.all?(conditions, &check_when_condition(&1, context))
  end

  @doc """
  Gets the category hierarchy as a list of atoms.
  """
  @spec category_hierarchy(t()) :: [atom()]
  def category_hierarchy(%__MODULE__{category: category}) when is_atom(category) do
    category
    |> Atom.to_string()
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Checks if the command supports pipeline composition.
  """
  @spec supports_pipeline?(t()) :: boolean()
  def supports_pipeline?(%__MODULE__{input_types: input_types, output_types: output_types}) do
    not Enum.empty?(input_types) or not Enum.empty?(output_types)
  end

  @doc """
  Checks if this command can be chained after another command.
  """
  @spec can_chain_after?(t(), t()) :: boolean()
  def can_chain_after?(%__MODULE__{input_types: input_types}, %__MODULE__{output_types: output_types}) do
    not Enum.empty?(input_types) and 
    not Enum.empty?(output_types) and
    not Enum.empty?(input_types -- (input_types -- output_types))
  end

  # Private helper functions
  defp check_dependency(%{parameter: param, condition: condition, value: expected}, current_values) do
    actual = Map.get(current_values, param)
    
    case condition do
      :equals -> actual == expected
      :not_equals -> actual != expected
      :greater_than -> is_number(actual) and actual > expected
      :less_than -> is_number(actual) and actual < expected
      :contains -> is_binary(actual) and String.contains?(actual, expected)
      _ -> false
    end
  end

  defp check_when_condition(%{type: :file_type, condition: extensions}, %{file_path: file_path}) when is_list(extensions) do
    case Path.extname(file_path) do
      "" -> false
      ext -> String.trim_leading(ext, ".") in extensions
    end
  end
  defp check_when_condition(%{type: :project_type, condition: type}, %{project_type: project_type}) do
    project_type == type
  end
  defp check_when_condition(%{type: :interface, condition: interface}, %{interface: current_interface}) do
    current_interface == interface
  end
  defp check_when_condition(%{type: :permission, condition: permission}, %{permissions: permissions}) when is_list(permissions) do
    permission in permissions
  end
  defp check_when_condition(%{type: :custom, condition: condition}, context) when is_function(condition, 1) do
    condition.(context)
  end
  defp check_when_condition(_, _), do: true

  @doc """
  Generates a help string for the command.
  """
  @spec help_text(t()) :: String.t()
  def help_text(%__MODULE__{} = metadata) do
    """
    #{metadata.name} - #{metadata.description}

    Category: #{format_category(metadata.category)}
    Version: #{metadata.version}
    #{if metadata.deprecated, do: "⚠️  DEPRECATED", else: ""}
    #{tags_help(metadata)}
    #{availability_help(metadata)}

    #{parameters_help(metadata)}

    #{pipeline_help(metadata)}

    #{examples_help(metadata)}

    #{aliases_help(metadata)}
    """
    |> String.trim()
  end

  @doc """
  Generates help text for a specific interface.
  """
  @spec help_text_for_interface(t(), atom()) :: String.t()
  def help_text_for_interface(%__MODULE__{} = metadata, interface) do
    interface_hints = Map.get(metadata.interface_hints, interface, %{})
    
    """
    #{metadata.name} - #{metadata.description}

    #{parameters_help_for_interface(metadata, interface)}

    #{examples_help_for_interface(metadata, interface)}
    """
    |> String.trim()
  end

  defp parameters_help(%__MODULE__{parameters: []}), do: ""
  defp parameters_help(%__MODULE__{} = metadata) do
    groups = parameters_by_group(metadata)
    
    """
    Parameters:
    #{Enum.map_join(groups, "\n\n", &group_help/1)}
    """
  end

  defp parameters_help_for_interface(%__MODULE__{parameters: []}, _), do: ""
  defp parameters_help_for_interface(%__MODULE__{} = metadata, interface) do
    groups = parameters_by_group(metadata)
    
    """
    Parameters:
    #{Enum.map_join(groups, "\n\n", fn group -> group_help_for_interface(group, interface) end)}
    """
  end

  defp group_help({"default", parameters}) do
    Enum.map_join(parameters, "\n", &parameter_help/1)
  end
  defp group_help({group_name, parameters}) do
    """
    #{group_name}:
    #{Enum.map_join(parameters, "\n", &("  " <> parameter_help(&1)))}
    """
  end

  defp group_help_for_interface({group_name, parameters}, interface) do
    interface_params = Enum.filter(parameters, fn param ->
      hints = Map.get(param.interface_hints, interface, %{})
      not Map.get(hints, :hidden, false)
    end)

    if Enum.empty?(interface_params) do
      ""
    else
      if group_name == "default" do
        Enum.map_join(interface_params, "\n", &parameter_help_for_interface(&1, interface))
      else
        """
        #{group_name}:
        #{Enum.map_join(interface_params, "\n", &("  " <> parameter_help_for_interface(&1, interface)))}
        """
      end
    end
  end

  defp parameter_help(%Parameter{} = param) do
    required_text = if param.required, do: "(required)", else: "(optional)"
    default_text = if param.default, do: " [default: #{inspect(param.default)}]", else: ""
    choices_text = if param.choices, do: " [choices: #{Enum.join(param.choices, ", ")}]", else: ""
    multiple_text = if param.multiple, do: " [multiple]", else: ""
    range_text = if param.min_value || param.max_value do
      min_str = param.min_value || "∞"
      max_str = param.max_value || "∞"
      " [range: #{min_str}..#{max_str}]"
    else
      ""
    end
    pattern_text = if param.pattern, do: " [pattern: #{param.pattern}]", else: ""
    
    help_text = param.help_text || param.description
    placeholder_text = if param.placeholder, do: "\n    Placeholder: #{param.placeholder}", else: ""
    dependencies_text = if not Enum.empty?(param.depends_on) do
      deps = Enum.map_join(param.depends_on, ", ", fn dep ->
        "#{dep.parameter} #{dep.condition} #{inspect(dep.value)}"
      end)
      "\n    Depends on: #{deps}"
    else
      ""
    end
    
    "  --#{param.name} (#{param.type}) #{required_text}#{default_text}#{choices_text}#{multiple_text}#{range_text}#{pattern_text}\n    #{help_text}#{placeholder_text}#{dependencies_text}"
  end

  defp parameter_help_for_interface(%Parameter{} = param, interface) do
    interface_hints = Map.get(param.interface_hints, interface, %{})
    input_type = Map.get(interface_hints, :input_type, :text)
    
    base_help = parameter_help(param)
    interface_specific = case input_type do
      :file_picker -> "\n    Interface: File picker"
      :dropdown -> "\n    Interface: Dropdown menu"
      :slider -> "\n    Interface: Slider"
      :checkbox -> "\n    Interface: Checkbox"
      _ -> ""
    end
    
    base_help <> interface_specific
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

  defp tags_help(%__MODULE__{tags: []}), do: ""
  defp tags_help(%__MODULE__{tags: tags}) do
    "Tags: #{Enum.join(tags, ", ")}"
  end

  defp availability_help(%__MODULE__{when_conditions: []}), do: ""
  defp availability_help(%__MODULE__{when_conditions: conditions}) do
    condition_texts = Enum.map(conditions, fn
      %{type: :file_type, condition: extensions} -> "File types: #{Enum.join(extensions, ", ")}"
      %{type: :project_type, condition: type} -> "Project type: #{type}"
      %{type: :interface, condition: interface} -> "Interface: #{interface}"
      %{type: :permission, condition: permission} -> "Requires permission: #{permission}"
      %{description: desc} -> desc
      _ -> "Custom condition"
    end)
    
    "Available when: #{Enum.join(condition_texts, ", ")}"
  end

  defp pipeline_help(%__MODULE__{input_types: [], output_types: []}), do: ""
  defp pipeline_help(%__MODULE__{input_types: input_types, output_types: output_types}) do
    input_text = if Enum.empty?(input_types), do: "none", else: Enum.join(input_types, ", ")
    output_text = if Enum.empty?(output_types), do: "none", else: Enum.join(output_types, ", ")
    
    """
    Pipeline:
      Input types: #{input_text}
      Output types: #{output_text}
    """
  end

  defp examples_help_for_interface(%__MODULE__{examples: []}, _), do: ""
  defp examples_help_for_interface(%__MODULE__{examples: examples}, interface) do
    interface_examples = Enum.filter(examples, fn example ->
      interface_hint = Map.get(example, :interface, :all)
      interface_hint == :all or interface_hint == interface
    end)
    
    if Enum.empty?(interface_examples) do
      ""
    else
      """
      Examples:
      #{Enum.map_join(interface_examples, "\n", &example_help/1)}
      """
    end
  end

  defp format_category(category) when is_atom(category) do
    category
    |> Atom.to_string()
    |> String.replace(".", " > ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end