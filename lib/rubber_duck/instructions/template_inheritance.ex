defmodule RubberDuck.Instructions.TemplateInheritance do
  @moduledoc """
  Implements template inheritance for instruction templates.
  
  Supports:
  - Template extension with {% extends "base.liquid" %}
  - Block definition with {% block name %}...{% endblock %}
  - Block overriding in child templates
  - Include directives with {% include "partial.liquid" %}
  - Multiple inheritance levels
  """

  alias RubberDuck.Instructions.{TemplateError, Security}
  
  @type template_tree :: %{
    content: String.t(),
    blocks: %{String.t() => String.t()},
    extends: String.t() | nil,
    includes: [String.t()]
  }

  @doc """
  Processes a template with inheritance support.
  
  Resolves extends and includes directives, merges blocks,
  and returns the final compiled template.
  """
  @spec process_inheritance(String.t(), (String.t() -> {:ok, String.t()} | {:error, term()})) :: 
    {:ok, String.t()} | {:error, term()}
  def process_inheritance(template_content, loader_fn) do
    with {:ok, tree} <- parse_template_tree(template_content),
         {:ok, resolved} <- resolve_inheritance(tree, loader_fn, []),
         {:ok, final} <- compile_template(resolved) do
      {:ok, final}
    end
  end

  @doc """
  Extracts blocks from a template for inheritance.
  """
  @spec extract_blocks(String.t()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  def extract_blocks(template_content) do
    block_pattern = ~r/\{%\s*block\s+(\w+)\s*%\}(.*?)\{%\s*endblock\s*%\}/s
    
    blocks = 
      Regex.scan(block_pattern, template_content)
      |> Enum.map(fn [_full, name, content] -> {name, String.trim(content)} end)
      |> Enum.into(%{})
    
    {:ok, blocks}
  end

  @doc """
  Parses extends directive from template.
  """
  @spec parse_extends(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def parse_extends(template_content) do
    case Regex.run(~r/\{%\s*extends\s+"([^"]+)"\s*%\}/, template_content) do
      [_, parent_path] -> 
        case Security.validate_include_path(parent_path) do
          :ok -> {:ok, parent_path}
          error -> error
        end
      nil -> 
        {:ok, nil}
    end
  end

  @doc """
  Parses include directives from template.
  """
  @spec parse_includes(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def parse_includes(template_content) do
    include_pattern = ~r/\{%\s*include\s+"([^"]+)"\s*%\}/
    
    includes = 
      Regex.scan(include_pattern, template_content)
      |> Enum.map(fn [_, path] -> path end)
    
    # Validate all include paths
    case validate_all_paths(includes) do
      :ok -> {:ok, includes}
      error -> error
    end
  end

  # Private functions

  defp parse_template_tree(template_content) do
    with {:ok, extends} <- parse_extends(template_content),
         {:ok, blocks} <- extract_blocks(template_content),
         {:ok, includes} <- parse_includes(template_content) do
      {:ok, %{
        content: template_content,
        blocks: blocks,
        extends: extends,
        includes: includes
      }}
    end
  end

  defp resolve_inheritance(tree, loader_fn, visited_paths) do
    # Check for circular inheritance
    if tree.extends && tree.extends in visited_paths do
      {:error, TemplateError.exception(reason: :circular_inheritance)}
    else
      resolve_tree(tree, loader_fn, visited_paths)
    end
  end

  defp resolve_tree(%{extends: nil} = tree, loader_fn, _visited) do
    # Base case: no parent template
    resolve_includes(tree, loader_fn)
  end

  defp resolve_tree(%{extends: parent_path} = tree, loader_fn, visited) do
    # Load and resolve parent template
    with {:ok, parent_content} <- loader_fn.(parent_path),
         {:ok, parent_tree} <- parse_template_tree(parent_content),
         {:ok, resolved_parent} <- resolve_inheritance(
           parent_tree, 
           loader_fn, 
           [parent_path | visited]
         ) do
      # Merge blocks: child blocks override parent blocks
      merged_blocks = Map.merge(resolved_parent.blocks, tree.blocks)
      merged_tree = %{tree | blocks: merged_blocks, extends: nil}
      
      # Apply blocks to parent content
      apply_blocks_to_template(resolved_parent, merged_blocks, loader_fn)
    end
  end

  defp resolve_includes(%{includes: []} = tree, _loader_fn), do: {:ok, tree}
  
  defp resolve_includes(%{includes: includes, content: content} = tree, loader_fn) do
    # Process each include
    result = 
      Enum.reduce_while(includes, {:ok, content}, fn include_path, {:ok, acc_content} ->
        case process_include(include_path, acc_content, loader_fn) do
          {:ok, new_content} -> {:cont, {:ok, new_content}}
          error -> {:halt, error}
        end
      end)
    
    case result do
      {:ok, final_content} -> {:ok, %{tree | content: final_content}}
      error -> error
    end
  end

  defp process_include(include_path, content, loader_fn) do
    include_tag = ~s({%\s*include\s+"#{Regex.escape(include_path)}"\s*%})
    
    case loader_fn.(include_path) do
      {:ok, include_content} ->
        # Recursively process includes in the included file
        case parse_includes(include_content) do
          {:ok, []} -> 
            # No nested includes, simple replacement
            {:ok, String.replace(content, ~r/#{include_tag}/, include_content)}
          {:ok, _nested} ->
            # Process nested includes
            with {:ok, tree} <- parse_template_tree(include_content),
                 {:ok, resolved} <- resolve_includes(tree, loader_fn) do
              {:ok, String.replace(content, ~r/#{include_tag}/, resolved.content)}
            end
        end
      error -> 
        error
    end
  end

  defp apply_blocks_to_template(parent_tree, blocks, _loader_fn) do
    # Replace block placeholders in parent with child content
    final_content = 
      Enum.reduce(blocks, parent_tree.content, fn {block_name, block_content}, acc ->
        block_pattern = ~r/\{%\s*block\s+#{block_name}\s*%\}.*?\{%\s*endblock\s*%\}/s
        String.replace(acc, block_pattern, block_content)
      end)
    
    {:ok, %{parent_tree | content: final_content, blocks: blocks}}
  end

  defp compile_template(tree) do
    # Remove any remaining template inheritance directives
    compiled = 
      tree.content
      |> remove_extends_directive()
      |> remove_empty_blocks()
    
    {:ok, compiled}
  end

  defp remove_extends_directive(content) do
    String.replace(content, ~r/\{%\s*extends\s+"[^"]+"\s*%\}\s*\n?/, "")
  end

  defp remove_empty_blocks(content) do
    String.replace(content, ~r/\{%\s*block\s+\w+\s*%\}\s*\{%\s*endblock\s*%\}\s*\n?/, "")
  end

  defp validate_all_paths(paths) do
    Enum.reduce_while(paths, :ok, fn path, _acc ->
      case Security.validate_include_path(path) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end