defmodule RubberDuck.Instructions.TemplateError do
  @moduledoc """
  Error raised when template processing fails.
  """
  defexception [:message, :reason]

  @impl true
  def exception(opts) do
    reason = Keyword.get(opts, :reason)
    message = Keyword.get(opts, :message, format_message(reason))

    %__MODULE__{
      message: message,
      reason: reason
    }
  end

  defp format_message({:parse_error, details}), do: "Template parsing failed: #{inspect(details)}"
  defp format_message({:render_error, details}), do: "Template rendering failed: #{inspect(details)}"
  defp format_message({:markdown_error, details}), do: "Markdown conversion failed: #{inspect(details)}"
  defp format_message({:yaml_parse_error, details}), do: "YAML frontmatter parsing failed: #{inspect(details)}"
  defp format_message({:inheritance_error, details}), do: "Template inheritance failed: #{inspect(details)}"
  defp format_message(:template_too_large), do: "Template exceeds maximum size limit"
  defp format_message(:dangerous_template_content), do: "Template contains potentially dangerous patterns"
  defp format_message(:circular_inheritance), do: "Circular inheritance detected in template hierarchy"
  defp format_message(:invalid_frontmatter_format), do: "Invalid frontmatter format - must be YAML delimited by ---"
  defp format_message(:invalid_metadata_format), do: "Metadata must be a valid YAML object"
  defp format_message(:template_not_found), do: "Template file not found"
  defp format_message(:include_depth_exceeded), do: "Maximum include depth exceeded"
  defp format_message(reason), do: "Template error: #{inspect(reason)}"
end

defmodule RubberDuck.Instructions.SecurityError do
  @moduledoc """
  Error raised when template security validation fails.
  """
  defexception [:message, :reason]

  @impl true
  def exception(opts) do
    reason = Keyword.get(opts, :reason)
    message = Keyword.get(opts, :message, format_message(reason))

    %__MODULE__{
      message: message,
      reason: reason
    }
  end

  defp format_message(:injection_attempt), do: "Potential injection attempt detected"
  defp format_message(:unauthorized_access), do: "Unauthorized template access attempt"
  defp format_message(:path_traversal), do: "Path traversal attempt detected"
  defp format_message(:excessive_nesting), do: "Template nesting depth exceeded"
  defp format_message(:template_too_large), do: "Template exceeds security size limits"
  defp format_message(:too_many_variables), do: "Too many variables provided to template"
  defp format_message(:value_too_large), do: "Variable value exceeds maximum size"
  defp format_message(:list_too_large), do: "List variable exceeds maximum length"
  defp format_message(:map_too_large), do: "Map variable exceeds maximum size"
  defp format_message(:invalid_value_type), do: "Invalid variable value type"
  defp format_message(:system_templates_disabled), do: "System templates are disabled in this environment"
  defp format_message(:suspicious_content), do: "Template contains suspicious encoded or obfuscated content"
  defp format_message(:sandbox_violation), do: "Template attempted to access restricted functionality"
  defp format_message(:resource_limit_exceeded), do: "Template exceeded resource limits"
  defp format_message(:timeout), do: "Template execution timed out"
  defp format_message(:memory_limit_exceeded), do: "Template exceeded memory limits"
  defp format_message(:user_blocked), do: "User has been blocked due to repeated security violations"
  defp format_message(reason), do: "Security error: #{inspect(reason)}"
end