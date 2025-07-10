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
      variables: [],
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
    arity = get_arity(args)
    current_function = {info.name, name, arity}

    # Create a new context for this function
    function_context = %{
      info
      | metadata:
          info.metadata
          |> Map.put(:current_function, current_function)
          |> Map.put(:function_variables, [])
          |> Map.put(:function_calls, [])
    }

    # Extract parameter variables
    param_vars = extract_parameter_variables(args, current_function, meta)

    function_context = %{
      function_context
      | metadata: Map.update!(function_context.metadata, :function_variables, &(Enum.concat(&1, param_vars)))
    }

    # Process function body
    function_context =
      case rest do
        [[do: body]] -> traverse_ast(body, function_context)
        [_guards, [do: body]] -> traverse_ast(body, function_context)
        _ -> function_context
      end

    # Extract function-specific data
    function_vars = Map.get(function_context.metadata, :function_variables, [])
    function_calls = Map.get(function_context.metadata, :function_calls, [])

    function_info = %{
      name: name,
      arity: arity,
      line: Keyword.get(meta, :line, 0),
      private: def_type == :defp,
      variables: function_vars,
      body_calls: function_calls
    }

    # Merge back to main info
    %{
      info
      | functions: [function_info | info.functions],
        calls: function_context.calls,
        variables: Enum.concat(info.variables, function_vars)
    }
  end

  # Alias
  defp traverse_ast({:alias, _meta, [module_ref | _opts]}, info) do
    case extract_aliases(module_ref) do
      modules when is_list(modules) ->
        %{info | aliases: Enum.concat(modules, info.aliases)}

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

          info = %{info | calls: [call_info | info.calls]}

          # Also track in function-specific calls if we're inside a function
          if Map.has_key?(info.metadata, :function_calls) do
            %{info | metadata: Map.update!(info.metadata, :function_calls, &[call_info | &1])}
          else
            info
          end

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

        # Also track in function-specific calls if we're inside a function
        updated_info =
          if Map.has_key?(updated_info.metadata, :function_calls) do
            %{updated_info | metadata: Map.update!(updated_info.metadata, :function_calls, &[call_info | &1])}
          else
            updated_info
          end

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

  # Variable assignment with =
  defp traverse_ast({:=, meta, [left, right]}, info) do
    # First traverse the right side to find any variable usage
    info = traverse_ast(right, info)

    # Then extract variables from the left side (pattern match)
    extract_variables_from_pattern(left, info, :assignment, meta)
  end

  # Variable usage
  defp traverse_ast({var_name, meta, context}, info)
       when is_atom(var_name) and is_atom(context) and var_name != :_ do
    # This is a variable reference
    if variable_name?(var_name) do
      var_info = %{
        name: var_name,
        line: Keyword.get(meta, :line, 0),
        column: Keyword.get(meta, :column, nil),
        context: context,
        type: :usage,
        scope: Map.get(info.metadata, :current_function, :module)
      }

      updated_info =
        if Map.has_key?(info.metadata, :function_variables) do
          %{info | metadata: Map.update!(info.metadata, :function_variables, &[var_info | &1])}
        else
          %{info | variables: [var_info | info.variables]}
        end

      updated_info
    else
      info
    end
  end

  # Case expressions
  defp traverse_ast({:case, _meta, [expr, [do: clauses]]}, info) do
    # First traverse the expression
    info = traverse_ast(expr, info)

    # Then traverse each clause
    Enum.reduce(clauses, info, fn
      {:->, _meta, [[pattern], body]}, acc ->
        # Extract variables from pattern
        acc = extract_variables_from_pattern(pattern, acc, :match, [])
        # Then traverse the body
        traverse_ast(body, acc)

      _, acc ->
        acc
    end)
  end

  # With expressions
  defp traverse_ast({:with, _meta, args}, info) do
    Enum.reduce(args, info, fn
      {:<-, _meta, [pattern, expr]}, acc ->
        # First traverse the expression
        acc = traverse_ast(expr, acc)
        # Then extract variables from pattern
        extract_variables_from_pattern(pattern, acc, :match, [])

      [do: body], acc ->
        traverse_ast(body, acc)

      [else: clauses], acc ->
        Enum.reduce(clauses, acc, fn
          {:->, _meta, [[pattern], body]}, acc2 ->
            acc2 = extract_variables_from_pattern(pattern, acc2, :match, [])
            traverse_ast(body, acc2)

          _, acc2 ->
            acc2
        end)

      expr, acc when is_tuple(expr) ->
        traverse_ast(expr, acc)

      _, acc ->
        acc
    end)
  end

  # Comprehensions
  defp traverse_ast({:for, _meta, args}, info) do
    Enum.reduce(args, info, fn
      {:<-, _meta, [pattern, expr]}, acc ->
        # Traverse expression first
        acc = traverse_ast(expr, acc)
        # Extract variables from pattern
        extract_variables_from_pattern(pattern, acc, :match, [])

      [do: body], acc ->
        traverse_ast(body, acc)

      expr, acc when is_tuple(expr) ->
        traverse_ast(expr, acc)

      _, acc ->
        acc
    end)
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

  # Helper functions for variable extraction
  defp extract_parameter_variables(nil, _scope, _meta), do: []

  defp extract_parameter_variables(args, scope, meta) when is_list(args) do
    Enum.flat_map(args, fn arg ->
      extract_variables_from_pattern(arg, %{variables: [], metadata: %{current_function: scope}}, :assignment, meta).variables
    end)
  end

  defp extract_parameter_variables(_, _scope, _meta), do: []

  defp extract_variables_from_pattern({var_name, meta, context}, info, var_type, _parent_meta)
       when is_atom(var_name) and is_atom(context) and var_name != :_ do
    if variable_name?(var_name) do
      var_info = %{
        name: var_name,
        line: Keyword.get(meta, :line, 0),
        column: Keyword.get(meta, :column, nil),
        context: context,
        type: var_type,
        scope: Map.get(info.metadata, :current_function, :module)
      }

      if Map.has_key?(info.metadata, :function_variables) do
        %{info | metadata: Map.update!(info.metadata, :function_variables, &[var_info | &1])}
      else
        %{info | variables: [var_info | info.variables]}
      end
    else
      info
    end
  end

  # Pattern matching in tuples
  defp extract_variables_from_pattern({:{}, _meta, elements}, info, var_type, parent_meta) do
    Enum.reduce(elements, info, fn elem, acc ->
      extract_variables_from_pattern(elem, acc, var_type, parent_meta)
    end)
  end

  # Pattern matching in lists
  defp extract_variables_from_pattern(list, info, var_type, parent_meta) when is_list(list) do
    Enum.reduce(list, info, fn elem, acc ->
      extract_variables_from_pattern(elem, acc, var_type, parent_meta)
    end)
  end

  # Pattern matching with cons operator [head | tail]
  defp extract_variables_from_pattern({:|, _meta, [head, tail]}, info, var_type, parent_meta) do
    info
    |> extract_variables_from_pattern(head, var_type, parent_meta)
    |> extract_variables_from_pattern(tail, var_type, parent_meta)
  end

  # Map pattern matching
  defp extract_variables_from_pattern({:%{}, _meta, pairs}, info, var_type, parent_meta) do
    Enum.reduce(pairs, info, fn
      {_key, value}, acc ->
        extract_variables_from_pattern(value, acc, var_type, parent_meta)
    end)
  end

  # Struct pattern matching
  defp extract_variables_from_pattern({:%, _meta, [_struct, {:%{}, _meta2, pairs}]}, info, var_type, parent_meta) do
    Enum.reduce(pairs, info, fn
      {_key, value}, acc ->
        extract_variables_from_pattern(value, acc, var_type, parent_meta)
    end)
  end

  # Binary pattern matching
  defp extract_variables_from_pattern({:<<>>, _meta, segments}, info, var_type, parent_meta) do
    Enum.reduce(segments, info, fn
      {:"::", _meta, [value, _size]}, acc ->
        extract_variables_from_pattern(value, acc, var_type, parent_meta)

      value, acc ->
        extract_variables_from_pattern(value, acc, var_type, parent_meta)
    end)
  end

  # Skip other patterns
  defp extract_variables_from_pattern(_pattern, info, _var_type, _parent_meta), do: info

  defp variable_name?(name) when is_atom(name) do
    name_str = Atom.to_string(name)

    String.match?(name_str, ~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/) and
      name_str != "_" and
      not String.starts_with?(name_str, "_")
  end

  defp variable_name?(_), do: false
end
