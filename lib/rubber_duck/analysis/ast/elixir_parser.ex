defmodule RubberDuck.Analysis.AST.ElixirParser do
  @moduledoc """
  Elixir-specific AST parser implementation.

  Uses Elixir's built-in `Code.string_to_quoted/2` to parse code
  and extracts module structure, function definitions, and dependencies.
  """

  @behaviour RubberDuck.Analysis.AST.Parser

  @impl true
  def parse(content) do
    parse(content, [])
  end

  @impl true
  def parse(content, opts) do
    with {:ok, ast} <- Code.string_to_quoted(content, columns: true, token_metadata: true),
         {:ok, info} <- extract_info(ast, opts) do
      {:ok, info}
    else
      {:error, {metadata, error_desc, token}} when is_list(metadata) ->
        {:error,
         {:syntax_error,
          %{
            line: Keyword.get(metadata, :line, 1),
            column: Keyword.get(metadata, :column, 1),
            description: error_desc,
            token: token
          }}}

      {:error, {line, error_desc, token}} when is_integer(line) ->
        {:error,
         {:syntax_error,
          %{
            line: line,
            description: error_desc,
            token: token
          }}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_info(ast, _opts) do
    info = %{
      type: :script,
      name: nil,
      functions: [],
      aliases: [],
      imports: [],
      requires: [],
      calls: [],
      metadata: %{}
    }

    {:ok, traverse_ast(ast, info)}
  end

  defp traverse_ast({:defmodule, _meta, [module_alias | rest]}, info) do
    module_name = extract_module_name(module_alias)
    module_info = %{info | type: :module, name: module_name}

    # Extract module body
    case rest do
      [_opts, [do: body]] -> traverse_ast(body, module_info)
      [[do: body]] -> traverse_ast(body, module_info)
      _ -> module_info
    end
  end

  # Function definitions
  defp traverse_ast({def_type, meta, [{name, _, args} | rest]}, info)
       when def_type in [:def, :defp] do
    function_info = %{
      name: name,
      arity: get_arity(args),
      line: Keyword.get(meta, :line, 0),
      private: def_type == :defp
    }

    # Process function body to find calls
    updated_info = %{
      info
      | functions: [function_info | info.functions],
        metadata: Map.put(info.metadata, :current_function, {info.name, name, get_arity(args)})
    }

    # Continue traversing the function body
    case rest do
      [[do: body]] -> traverse_ast(body, updated_info)
      [_guards, [do: body]] -> traverse_ast(body, updated_info)
      _ -> updated_info
    end
  end

  # Alias
  defp traverse_ast({:alias, _meta, [module_ref | _opts]}, info) do
    case extract_aliases(module_ref) do
      modules when is_list(modules) ->
        %{info | aliases: modules ++ info.aliases}

      module ->
        %{info | aliases: [module | info.aliases]}
    end
  end

  # Import
  defp traverse_ast({:import, _meta, [module_ref | _opts]}, info) do
    module = extract_module_name(module_ref)
    %{info | imports: [module | info.imports]}
  end

  # Require
  defp traverse_ast({:require, _meta, [module_ref | _opts]}, info) do
    module = extract_module_name(module_ref)
    %{info | requires: [module | info.requires]}
  end

  # Handle blocks
  defp traverse_ast({:__block__, _meta, statements}, info) do
    Enum.reduce(statements, info, &traverse_ast/2)
  end

  # Handle other forms with bodies
  defp traverse_ast({_form, _meta, args}, info) when is_list(args) do
    Enum.reduce(args, info, fn
      arg, acc when is_tuple(arg) -> traverse_ast(arg, acc)
      _, acc -> acc
    end)
  end

  # Function calls
  defp traverse_ast({{:., _meta1, [module_ref, function]}, meta2, args}, info) when is_atom(function) do
    # Remote function call (e.g., Module.function())
    updated_info =
      case Map.get(info.metadata, :current_function) do
        {module, func, arity} ->
          called_module = extract_module_name(module_ref)

          call_info = %{
            from: {module, func, arity},
            to: {called_module, function, get_arity(args)},
            line: Keyword.get(meta2, :line, 0)
          }

          %{info | calls: [call_info | info.calls]}

        _ ->
          info
      end

    # Continue traversing arguments
    Enum.reduce(args, updated_info, fn
      arg, acc when is_tuple(arg) -> traverse_ast(arg, acc)
      _, acc -> acc
    end)
  end

  defp traverse_ast({function, meta, args}, info) when is_atom(function) and is_list(args) do
    # Local function call
    case Map.get(info.metadata, :current_function) do
      {module, func, arity} ->
        call_info = %{
          from: {module, func, arity},
          to: {module, function, get_arity(args)},
          line: Keyword.get(meta, :line, 0)
        }

        # Continue traversing arguments
        updated_info = %{info | calls: [call_info | info.calls]}

        Enum.reduce(args, updated_info, fn
          arg, acc when is_tuple(arg) -> traverse_ast(arg, acc)
          _, acc -> acc
        end)

      _ ->
        # Not inside a function, continue traversing
        Enum.reduce(args, info, fn
          arg, acc when is_tuple(arg) -> traverse_ast(arg, acc)
          _, acc -> acc
        end)
    end
  end

  # Base case
  defp traverse_ast(_ast, info), do: info

  defp extract_module_name({:__aliases__, _meta, parts}) do
    Module.concat(parts)
  end

  defp extract_module_name(module) when is_atom(module), do: module
  defp extract_module_name(_), do: nil

  # Handle multi-alias: alias Foo.{Bar, Baz}
  defp extract_aliases({{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, aliases}) do
    base_module = Module.concat(base_parts)

    Enum.map(aliases, fn
      {:__aliases__, _, parts} -> Module.concat([base_module | parts])
      atom when is_atom(atom) -> Module.concat([base_module, atom])
    end)
  end

  defp extract_aliases(module_ref) do
    extract_module_name(module_ref)
  end

  defp get_arity(nil), do: 0
  defp get_arity(args) when is_list(args), do: length(args)
  defp get_arity(_), do: 0
end

