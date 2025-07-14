defmodule RubberDuck.Instructions.TemplateProcessor do
  @moduledoc """
  Core template processing engine for instruction templates.
  
  Provides secure template processing using Solid for user templates and EEx for system templates,
  with comprehensive safety measures and performance optimization.
  
  ## Features
  
  - Solid (Liquid) template processing for user-provided templates
  - EEx template processing for trusted system templates
  - Markdown to HTML conversion via Earmark
  - Multi-layered security validation
  - Template inheritance and composition
  - Variable sanitization and type checking
  - Conditional logic support
  - Metadata extraction from YAML frontmatter
  """

  require Logger
  alias RubberDuck.Instructions.{Security, TemplateInheritance}

  @type template_type :: :user | :system
  @type template_result :: {:ok, String.t()} | {:error, term()}
  @type metadata :: map()

  @doc """
  Processes a template string with the given variables and options.
  
  ## Options
  
  - `:type` - Template type (:user or :system). Defaults to :user
  - `:markdown` - Whether to convert result to HTML. Defaults to true
  - `:validate` - Whether to validate template before processing. Defaults to true
  - `:loader` - Function for loading included/extended templates. Required for inheritance.
  
  ## Examples
  
      iex> process_template("Hello {{ name }}", %{name: "World"})
      {:ok, "<p>Hello World</p>"}
      
      iex> process_template("{% if admin %}Secret{% endif %}", %{admin: false})
      {:ok, ""}
  """
  @spec process_template(String.t(), map(), keyword()) :: template_result()
  def process_template(template_content, variables \\ %{}, opts \\ []) do
    type = Keyword.get(opts, :type, :user)
    markdown = Keyword.get(opts, :markdown, true)
    validate = Keyword.get(opts, :validate, true)
    loader = Keyword.get(opts, :loader)

    with {:ok, processed_template} <- maybe_process_inheritance(template_content, loader),
         {:ok, validated_template} <- maybe_validate_template(processed_template, validate),
         {:ok, sanitized_vars} <- sanitize_variables(variables),
         {:ok, rendered} <- render_template(validated_template, sanitized_vars, type),
         {:ok, final_output} <- maybe_convert_markdown(rendered, markdown) do
      {:ok, final_output}
    end
  end

  @doc """
  Processes a template with inheritance support.
  
  Requires a loader function to resolve template includes and extends.
  """
  @spec process_template_with_inheritance(String.t(), map(), (String.t() -> {:ok, String.t()} | {:error, term()}), keyword()) :: template_result()
  def process_template_with_inheritance(template_content, variables, loader_fn, opts \\ []) do
    opts_with_loader = Keyword.put(opts, :loader, loader_fn)
    process_template(template_content, variables, opts_with_loader)
  end

  @doc """
  Parses and validates a template without rendering it.
  
  Useful for pre-validation of templates before storage.
  """
  @spec validate_template(String.t(), template_type()) :: {:ok, Solid.template()} | {:error, term()}
  def validate_template(template_content, type \\ :user) do
    case type do
      :user -> validate_solid_template(template_content)
      :system -> validate_eex_template(template_content)
      _ -> {:error, {:invalid_template_type, type}}
    end
  end

  @doc """
  Extracts metadata from template frontmatter.
  
  Supports YAML frontmatter delimited by --- lines.
  """
  @spec extract_metadata(String.t()) :: {:ok, metadata(), String.t()} | {:error, term()}
  def extract_metadata(template_content) do
    # First check if there are multiple --- delimiters (invalid format)
    delimiter_count = template_content |> String.split(~r/^---$/m) |> length()
    
    if delimiter_count > 3 do
      {:error, :invalid_frontmatter_format}
    else
      case String.split(template_content, ~r/^---$/m, parts: 3) do
        ["", frontmatter, content] ->
          parse_frontmatter(frontmatter, content)
          
        [content] ->
          {:ok, %{}, content}
          
        _ ->
          {:error, :invalid_frontmatter_format}
      end
    end
  end

  @doc """
  Builds a context map with standard variables available to all templates.
  """
  @spec build_standard_context(map()) :: map()
  def build_standard_context(custom_vars \\ %{}) do
    %{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "date" => Date.utc_today() |> Date.to_iso8601(),
      "env" => Mix.env() |> to_string()
    }
    |> Map.merge(stringify_keys(custom_vars))
  end

  # Private functions

  defp maybe_process_inheritance(template, nil), do: {:ok, template}
  defp maybe_process_inheritance(template, loader_fn) do
    TemplateInheritance.process_inheritance(template, loader_fn)
  end

  defp maybe_validate_template(template, true) do
    case Security.validate_template(template) do
      :ok -> {:ok, template}
      error -> error
    end
  end
  defp maybe_validate_template(template, false), do: {:ok, template}

  defp sanitize_variables(variables) when is_map(variables) do
    case Security.validate_variables(variables) do
      :ok ->
        # Use the security module's sandbox context
        {:ok, Security.sandbox_context(variables)}
      error ->
        error
    end
  end
  defp sanitize_variables(_), do: {:error, :invalid_variables}

  defp render_template(template, variables, :user) do
    render_solid_template(template, variables)
  end

  defp render_template(template, variables, :system) do
    render_eex_template(template, variables)
  end

  defp render_solid_template(template_content, variables) do
    try do
      with {:ok, template} <- Solid.parse(template_content),
           {:ok, rendered, _warnings} <- Solid.render(template, stringify_keys(variables)) do
        {:ok, to_string(rendered)}
      else
        {:error, error} -> {:error, {:template_error, error}}
      end
    rescue
      e -> {:error, {:render_error, Exception.message(e)}}
    end
  end

  defp render_eex_template(template_content, variables) do
    try do
      # Only allow system templates - additional security check
      if System.get_env("ALLOW_SYSTEM_TEMPLATES") != "true" do
        {:error, :system_templates_disabled}
      else
        rendered = EEx.eval_string(template_content, Keyword.new(variables))
        {:ok, rendered}
      end
    rescue
      e -> {:error, {:render_error, Exception.message(e)}}
    end
  end

  defp validate_solid_template(template_content) do
    case Solid.parse(template_content) do
      {:ok, template} -> {:ok, template}
      {:error, error} -> {:error, {:parse_error, error}}
    end
  end

  defp validate_eex_template(template_content) do
    try do
      # Try to compile the template to check for syntax errors
      EEx.compile_string(template_content)
      {:ok, template_content}
    rescue
      e -> {:error, {:parse_error, Exception.message(e)}}
    end
  end

  defp maybe_convert_markdown(content, true) do
    case Earmark.as_html(content) do
      {:ok, html, _warnings} -> {:ok, html}
      {:error, _html, errors} -> {:error, {:markdown_error, errors}}
    end
  end
  defp maybe_convert_markdown(content, false), do: {:ok, content}

  defp parse_frontmatter(frontmatter, content) do
    case YamlElixir.read_from_string(frontmatter) do
      {:ok, metadata} when is_map(metadata) ->
        validated_metadata = validate_metadata(metadata)
        {:ok, validated_metadata, content}
        
      {:ok, _} ->
        {:error, :invalid_metadata_format}
        
      {:error, reason} ->
        {:error, {:yaml_parse_error, reason}}
    end
  end

  defp validate_metadata(metadata) do
    # Include all keys, but provide defaults for standard ones
    base_metadata = %{
      "priority" => "normal",
      "type" => "auto", 
      "tags" => []
    }
    
    metadata
    |> Map.merge(base_metadata, fn _key, new_val, _default -> new_val end)
    |> Map.update("priority", "normal", &validate_priority/1)
    |> Map.update("type", "auto", &validate_rule_type/1)
    |> Map.update("tags", [], &validate_tags/1)
  end

  defp validate_priority(priority) when priority in ["low", "normal", "high", "critical"], do: priority
  defp validate_priority(_), do: "normal"

  defp validate_rule_type(type) when type in ["always", "auto", "agent", "manual"], do: type
  defp validate_rule_type(_), do: "auto"

  defp validate_tags(tags) when is_list(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.take(10)
  end
  defp validate_tags(_), do: []

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end
  defp stringify_keys(_), do: %{}
end