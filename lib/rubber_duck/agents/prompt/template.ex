defmodule RubberDuck.Agents.Prompt.Template do
  @moduledoc """
  Data structure representing a prompt template.
  
  Prompt templates are reusable text patterns with variables that can be
  substituted with actual values during prompt construction. They support
  versioning, categorization, and metadata for better organization.
  """

  @derive {Jason.Encoder, only: [:id, :name, :description, :content, :variables, :metadata, :version, :tags, :category, :access_level]}
  defstruct [
    :id,              # UUID for the template
    :name,            # Human-readable name
    :description,     # Description of what this template does
    :content,         # Template content with {{variable}} placeholders
    :variables,       # List of required variables with validation rules
    :metadata,        # Additional metadata (author, usage stats, etc.)
    :version,         # Version number (semantic versioning)
    :created_at,      # Creation timestamp
    :updated_at,      # Last update timestamp
    :tags,            # List of tags for categorization
    :category,        # Category (e.g., "coding", "analysis", "creative")
    :access_level     # Access control level (:public, :private, :team)
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    description: String.t(),
    content: String.t(),
    variables: [variable()],
    metadata: map(),
    version: String.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    tags: [String.t()],
    category: String.t(),
    access_level: :public | :private | :team
  }

  @type variable :: %{
    name: String.t(),
    type: :string | :integer | :float | :boolean | :list | :map,
    required: boolean(),
    default: term(),
    description: String.t(),
    validation: term()
  }

  @doc """
  Creates a new prompt template with validation.
  
  ## Examples
  
      iex> RubberDuck.Agents.Prompt.Template.new(%{
      ...>   name: "Code Review",
      ...>   description: "Template for code review prompts",
      ...>   content: "Review this {{language}} code: {{code}}",
      ...>   variables: [
      ...>     %{name: "language", type: :string, required: true, description: "Programming language"},
      ...>     %{name: "code", type: :string, required: true, description: "Code to review"}
      ...>   ],
      ...>   category: "coding",
      ...>   tags: ["review", "analysis"]
      ...> })
      {:ok, %RubberDuck.Agents.Prompt.Template{...}}
  """
  def new(attrs) do
    with {:ok, validated_attrs} <- validate_attributes(attrs),
         {:ok, template} <- build_template(validated_attrs) do
      {:ok, template}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates an existing template with new attributes.
  """
  def update(%__MODULE__{} = template, attrs) do
    with {:ok, validated_attrs} <- validate_attributes(attrs),
         updated_template <- apply_updates(template, validated_attrs) do
      {:ok, updated_template}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that a template has all required fields and valid data.
  """
  def validate(%__MODULE__{} = template) do
    with :ok <- validate_required_fields(template),
         :ok <- validate_content_variables(template),
         :ok <- validate_variable_definitions(template) do
      {:ok, template}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts variable names from template content.
  
  Finds all {{variable}} patterns in the content.
  """
  def extract_variables(content) when is_binary(content) do
    Regex.scan(~r/\{\{([^}]+)\}\}/, content, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
  end

  @doc """
  Checks if all variables in the content are defined in the variables list.
  """
  def variables_complete?(%__MODULE__{content: content, variables: variables}) do
    content_vars = extract_variables(content) |> MapSet.new()
    defined_vars = Enum.map(variables, & &1.name) |> MapSet.new()
    
    MapSet.subset?(content_vars, defined_vars)
  end

  @doc """
  Gets template statistics including usage metrics.
  """
  def get_stats(%__MODULE__{metadata: metadata}) do
    %{
      usage_count: Map.get(metadata, :usage_count, 0),
      success_rate: Map.get(metadata, :success_rate, 0.0),
      avg_tokens: Map.get(metadata, :avg_tokens, 0),
      last_used: Map.get(metadata, :last_used),
      error_count: Map.get(metadata, :error_count, 0)
    }
  end

  # Private functions

  defp validate_attributes(attrs) do
    required_fields = [:name, :content]
    
    with :ok <- validate_required_attrs(attrs, required_fields),
         :ok <- validate_attr_types(attrs) do
      {:ok, attrs}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_required_attrs(attrs, required_fields) do
    missing_fields = required_fields -- Map.keys(attrs)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_attr_types(attrs) do
    validations = [
      {:name, :string},
      {:description, :string},
      {:content, :string},
      {:category, :string},
      {:access_level, :atom},
      {:tags, :list},
      {:variables, :list}
    ]
    
    Enum.reduce_while(validations, :ok, fn {key, expected_type}, acc ->
      case Map.get(attrs, key) do
        nil -> {:cont, acc}
        value -> 
          if valid_type?(value, expected_type) do
            {:cont, acc}
          else
            {:halt, {:error, "Invalid type for #{key}: expected #{expected_type}"}}
          end
      end
    end)
  end

  defp valid_type?(value, :string), do: is_binary(value)
  defp valid_type?(value, :atom), do: is_atom(value)
  defp valid_type?(value, :list), do: is_list(value)
  defp valid_type?(_value, _type), do: true

  defp build_template(attrs) do
    now = DateTime.utc_now()
    
    template = %__MODULE__{
      id: Map.get(attrs, :id, Uniq.UUID.uuid4()),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description, ""),
      content: Map.fetch!(attrs, :content),
      variables: Map.get(attrs, :variables, []),
      metadata: Map.get(attrs, :metadata, %{}),
      version: Map.get(attrs, :version, "1.0.0"),
      created_at: Map.get(attrs, :created_at, now),
      updated_at: now,
      tags: Map.get(attrs, :tags, []),
      category: Map.get(attrs, :category, "general"),
      access_level: Map.get(attrs, :access_level, :private)
    }
    
    validate(template)
  end

  defp apply_updates(template, attrs) do
    %{template |
      name: Map.get(attrs, :name, template.name),
      description: Map.get(attrs, :description, template.description),
      content: Map.get(attrs, :content, template.content),
      variables: Map.get(attrs, :variables, template.variables),
      metadata: Map.merge(template.metadata, Map.get(attrs, :metadata, %{})),
      version: Map.get(attrs, :version, increment_version(template.version)),
      updated_at: DateTime.utc_now(),
      tags: Map.get(attrs, :tags, template.tags),
      category: Map.get(attrs, :category, template.category),
      access_level: Map.get(attrs, :access_level, template.access_level)
    }
  end

  defp validate_required_fields(%__MODULE__{name: name, content: content}) do
    cond do
      is_nil(name) or name == "" ->
        {:error, "Template name is required"}
      is_nil(content) or content == "" ->
        {:error, "Template content is required"}
      true ->
        :ok
    end
  end

  defp validate_content_variables(%__MODULE__{content: content, variables: variables}) do
    content_vars = extract_variables(content)
    defined_vars = Enum.map(variables, & &1.name)
    undefined_vars = content_vars -- defined_vars
    
    if Enum.empty?(undefined_vars) do
      :ok
    else
      {:error, "Undefined variables in content: #{Enum.join(undefined_vars, ", ")}"}
    end
  end

  defp validate_variable_definitions(variables) when is_list(variables) do
    Enum.reduce_while(variables, :ok, fn var, acc ->
      case validate_variable(var) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_variable_definitions(_), do: :ok

  defp validate_variable(%{name: name, type: type, required: required}) 
       when is_binary(name) and is_atom(type) and is_boolean(required) do
    valid_types = [:string, :integer, :float, :boolean, :list, :map]
    
    if type in valid_types do
      :ok
    else
      {:error, "Invalid variable type: #{type}"}
    end
  end

  defp validate_variable(var) do
    {:error, "Invalid variable definition: #{inspect(var)}"}
  end

  defp increment_version(version) when is_binary(version) do
    case String.split(version, ".") do
      [major, minor, patch] ->
        case Integer.parse(patch) do
          {patch_int, ""} -> "#{major}.#{minor}.#{patch_int + 1}"
          _ -> "#{version}.1"
        end
      _ ->
        "#{version}.1"
    end
  end

  defp increment_version(_), do: "1.0.1"
end