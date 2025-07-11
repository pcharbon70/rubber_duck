defmodule RubberDuck.Analysis.AST.SourcerorParser do
  @moduledoc """
  Comprehensive AST parser for Elixir code using Sourceror.
  
  This module provides advanced code analysis capabilities including:
  - Module structure extraction
  - Function detection and analysis
  - Variable tracking with scope awareness
  - Function call tracking and call graph construction
  - Pattern matching support
  - Control structure analysis
  - Metadata preservation
  """
  
  @behaviour RubberDuck.Analysis.AST.Parser
  
  alias Sourceror.Zipper, as: Z
  
  defstruct modules: [],
            functions: [],
            variables: [],
            calls: [],
            imports: [],
            aliases: [],
            requires: [],
            errors: []
  
  @type t :: %__MODULE__{
    modules: [module_info()],
    functions: [function_info()],
    variables: [variable_info()],
    calls: [call_info()],
    imports: [import_info()],
    aliases: [alias_info()],
    requires: [require_info()],
    errors: [error_info()]
  }
  
  @type module_info :: %{
    name: module(),
    line: pos_integer(),
    doc: String.t() | nil,
    attributes: [attribute_info()]
  }
  
  @type function_info :: %{
    name: atom(),
    arity: non_neg_integer(),
    type: :def | :defp | :defmacro | :defmacrop,
    module: module(),
    line: pos_integer(),
    doc: String.t() | nil,
    guards: term(),
    specs: [spec_info()],
    variables: [variable_info()],
    calls: [call_info()]
  }
  
  @type variable_info :: %{
    name: atom(),
    type: :assignment | :usage | :pattern,
    scope: {:module, module()} | {:function, atom(), non_neg_integer()},
    line: pos_integer(),
    context: atom() | nil
  }
  
  @type call_info :: %{
    type: :local | :remote | :capture | :anonymous,
    from: {module(), atom(), non_neg_integer()},
    to: {module(), atom(), non_neg_integer()} | {:anonymous, pos_integer()},
    line: pos_integer()
  }
  
  @type import_info :: %{
    module: module(),
    only: keyword() | nil,
    except: keyword() | nil,
    line: pos_integer()
  }
  
  @type alias_info :: %{
    module: module(),
    as: module(),
    line: pos_integer()
  }
  
  @type require_info :: %{
    module: module(),
    as: module() | nil,
    line: pos_integer()
  }
  
  @type attribute_info :: %{
    name: atom(),
    value: term(),
    line: pos_integer()
  }
  
  @type spec_info :: %{
    name: atom(),
    arity: non_neg_integer(),
    spec: term(),
    line: pos_integer()
  }
  
  @type error_info :: %{
    type: atom(),
    message: String.t(),
    line: pos_integer() | nil,
    column: pos_integer() | nil
  }
  
  @doc """
  Parses Elixir source code and extracts comprehensive AST information.
  
  ## Examples
  
      iex> source = \"""
      ...> defmodule Example do
      ...>   def hello(name) do
      ...>     "Hello, \#{name}!"
      ...>   end
      ...> end
      ...> \"""
      iex> {:ok, analysis} = RubberDuck.Analysis.SourcerorParser.parse(source)
      iex> length(analysis.modules)
      1
      iex> length(analysis.functions)
      1
  """
  @impl true
  def parse(source) when is_binary(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        case analyze_ast(ast) do
          {:ok, result} -> convert_to_map(result)
          error -> error
        end
      {:error, error} ->
        {:error, format_parse_error(error)}
    end
  end
  
  @impl true
  def parse(source, _opts) when is_binary(source) do
    # For now, ignore opts and delegate to parse/1
    parse(source)
  end
  
  @doc """
  Parses an AST directly and returns struct format (for internal use).
  """
  @spec parse_ast(Macro.t()) :: {:ok, t()} | {:error, term()}
  def parse_ast(ast) when is_tuple(ast) or is_atom(ast) or is_list(ast) do
    analyze_ast(ast)
  end
  
  @doc """
  Parses a file and extracts AST information.
  """
  @spec parse_file(Path.t()) :: {:ok, map()} | {:error, term()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse(content)
      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end
  
  # Converts the struct format to the expected map format for compatibility
  defp convert_to_map(%__MODULE__{} = result) do
    # Get the first module or default to script
    {type, name} = case result.modules do
      [%{name: module_name} | _] -> {:module, module_name}
      [] -> {:script, nil}
    end
    
    # Convert functions to expected format, enriching with variables and calls
    functions = Enum.map(result.functions, fn func ->
      # Find variables and calls for this function
      func_scope = {:function, func.name, func.arity}
      func_variables = Enum.filter(result.variables, fn var ->
        var.scope == func_scope
      end)
      
      func_name = func.name
      func_arity = func.arity
      func_calls = Enum.filter(result.calls, fn call ->
        case call.from do
          {_, ^func_name, ^func_arity} -> true
          _ -> false
        end
      end)
      
      %{
        name: func.name,
        arity: func.arity,
        line: func.line,
        private: func.type in [:defp, :defmacrop],
        variables: func_variables,
        body_calls: func_calls
      }
    end)
    
    # Convert aliases to just module names
    aliases = Enum.map(result.aliases, & &1.module)
    imports = Enum.map(result.imports, & &1.module)
    requires = Enum.map(result.requires, & &1.module)
    
    {:ok, %{
      type: type,
      name: name,
      functions: functions,
      aliases: aliases,
      imports: imports,
      requires: requires,
      calls: result.calls,
      variables: result.variables,
      metadata: %{}
    }}
  end
  
  # Private functions
  
  defp analyze_ast(ast) do
    state = %__MODULE__{}
    
    try do
      zipper = Z.zip(ast)
      final_state = traverse_ast(zipper, state)
      {:ok, final_state}
    rescue
      e ->
        {:error, {:analysis_error, Exception.message(e)}}
    end
  end
  
  defp traverse_ast(zipper, state) do
    case Z.node(zipper) do
      # Module definition
      {:defmodule, meta, [alias_ast, body_ast]} ->
        state = extract_module(zipper, state, alias_ast, body_ast, meta)
        continue_traversal(zipper, state)
      
      # Function definitions
      {def_type, meta, [signature | _body]} when def_type in [:def, :defp, :defmacro, :defmacrop] ->
        state = extract_function(zipper, state, def_type, signature, meta)
        continue_traversal(zipper, state)
      
      # Variable assignments
      {:=, meta, [pattern, _value]} ->
        state = extract_pattern_variables(pattern, state, :assignment, meta)
        continue_traversal(zipper, state)
      
      # Function calls
      {{:., _, [module, function]}, meta, args} when is_atom(module) and is_atom(function) ->
        state = add_remote_call(state, module, function, length(args || []), meta)
        continue_traversal(zipper, state)
      
      {function, meta, args} when is_atom(function) and is_list(args) ->
        state = add_local_call(state, function, length(args), meta)
        continue_traversal(zipper, state)
      
      # Import, alias, require
      {:import, meta, [module | opts]} ->
        state = add_import(state, module, opts, meta)
        continue_traversal(zipper, state)
      
      {:alias, meta, [module | opts]} ->
        state = add_alias(state, module, opts, meta)
        continue_traversal(zipper, state)
      
      {:require, meta, [module | opts]} ->
        state = add_require(state, module, opts, meta)
        continue_traversal(zipper, state)
      
      # Control structures
      {:case, meta, [expr, [do: clauses]]} ->
        state = analyze_case(state, expr, clauses, meta)
        continue_traversal(zipper, state)
      
      {:with, meta, args} ->
        state = analyze_with(state, args, meta)
        continue_traversal(zipper, state)
      
      # Function captures
      {:&, meta, [{:/, _, [{function, _, _}, arity]}]} when is_atom(function) and is_integer(arity) ->
        state = add_capture(state, function, arity, meta)
        continue_traversal(zipper, state)
      
      # Anonymous functions
      {:fn, meta, clauses} ->
        state = analyze_anonymous_function(state, clauses, meta)
        continue_traversal(zipper, state)
      
      # Continue traversal for other nodes
      _ ->
        continue_traversal(zipper, state)
    end
  end
  
  defp continue_traversal(zipper, state) do
    if down = Z.down(zipper) do
      traverse_ast(down, state)
    else
      case Z.right(zipper) do
        nil ->
          # Try to go up and right
          case Z.up(zipper) do
            nil -> state
            up -> 
              case Z.right(up) do
                nil -> state
                right -> traverse_ast(right, state)
              end
          end
        right ->
          traverse_ast(right, state)
      end
    end
  end
  
  defp extract_module(zipper, state, alias_ast, body_ast, meta) do
    module_name = extract_module_name(alias_ast)
    line = meta[:line] || 0
    
    module_info = %{
      name: module_name,
      line: line,
      doc: extract_module_doc(zipper),
      attributes: []
    }
    
    # Set current context for nested analysis
    state = %{state | modules: [module_info | state.modules]}
    
    # Extract the actual body from the keyword list
    body = case body_ast do
      [{{:__block__, _, [:do]}, body}] -> body
      [{:do, body}] -> body
      _ -> nil
    end
    
    if body do
      # Analyze module body
      body_zipper = Z.zip(body)
      with_module_context(state, module_name, fn state ->
        traverse_ast(body_zipper, state)
      end)
    else
      state
    end
  end
  
  defp extract_module_name({:__aliases__, _, parts}) do
    Module.concat(parts)
  end
  defp extract_module_name(name) when is_atom(name), do: name
  
  defp extract_module_doc(_zipper) do
    # TODO: Extract @moduledoc
    nil
  end
  
  defp extract_function(zipper, state, def_type, signature, meta) do
    {name, args} = extract_function_signature(signature)
    arity = length(args)
    line = meta[:line] || 0
    current_module = get_current_module(state)
    
    function_info = %{
      name: name,
      arity: arity,
      type: def_type,
      module: current_module,
      line: line,
      doc: extract_function_doc(zipper),
      guards: extract_guards(signature),
      specs: [],
      variables: [],
      calls: []
    }
    
    # Extract parameter variables
    state = Enum.reduce(args, state, fn arg, acc ->
      extract_pattern_variables(arg, acc, :pattern, meta)
    end)
    
    %{state | functions: [function_info | state.functions]}
  end
  
  defp extract_function_signature({:when, _, [sig | _guards]}) do
    extract_function_signature(sig)
  end
  defp extract_function_signature({name, _, args}) when is_atom(name) do
    {name, args || []}
  end
  
  defp extract_guards({:when, _, [_sig | guards]}), do: guards
  defp extract_guards(_), do: nil
  
  defp extract_function_doc(_zipper) do
    # TODO: Extract @doc
    nil
  end
  
  defp extract_pattern_variables(pattern, state, type, meta) do
    line = meta[:line] || 0
    scope = get_current_scope(state)
    variables = do_extract_variables(pattern, type, line, scope)
    
    Enum.reduce(variables, state, fn var, acc ->
      %{acc | variables: [var | acc.variables]}
    end)
  end
  
  defp do_extract_variables(pattern, type, line, scope) do
    case pattern do
      # Simple variable
      {name, _, context} when is_atom(name) and is_atom(context) ->
        [%{name: name, type: type, line: line, context: context, scope: scope}]
      
      # Tuple pattern
      {:{}, _, elements} ->
        Enum.flat_map(elements, &do_extract_variables(&1, type, line, scope))
      
      # Two-element tuple
      {a, b} ->
        do_extract_variables(a, type, line, scope) ++ do_extract_variables(b, type, line, scope)
      
      # List pattern
      list when is_list(list) ->
        Enum.flat_map(list, &do_extract_variables(&1, type, line, scope))
      
      # Cons pattern [head | tail]
      [{:|, _, [head, tail]}] ->
        do_extract_variables(head, type, line, scope) ++ do_extract_variables(tail, type, line, scope)
      
      # Map pattern
      {:%{}, _, pairs} ->
        Enum.flat_map(pairs, fn {_key, value} ->
          do_extract_variables(value, type, line, scope)
        end)
      
      # Struct pattern
      {:%, _, [_struct, {:%{}, _, pairs}]} ->
        Enum.flat_map(pairs, fn {_key, value} ->
          do_extract_variables(value, type, line, scope)
        end)
      
      # Binary pattern
      {:<<>>, _, segments} ->
        Enum.flat_map(segments, &extract_binary_segment_variables(&1, type, line, scope))
      
      # Pinned variable (^var)
      {:^, _, [var]} ->
        do_extract_variables(var, :usage, line, scope)
      
      # Literals and other patterns
      _ ->
        []
    end
  end
  
  defp extract_binary_segment_variables({:"::", _, [var, _spec]}, type, line, scope) do
    do_extract_variables(var, type, line, scope)
  end
  defp extract_binary_segment_variables(var, type, line, scope) do
    do_extract_variables(var, type, line, scope)
  end
  
  defp add_remote_call(state, module, function, arity, meta) do
    line = meta[:line] || 0
    from = get_current_location(state)
    
    call_info = %{
      type: :remote,
      from: from,
      to: {module, function, arity},
      line: line
    }
    
    %{state | calls: [call_info | state.calls]}
  end
  
  defp add_local_call(state, function, arity, meta) do
    line = meta[:line] || 0
    from = get_current_location(state)
    current_module = get_current_module(state)
    
    call_info = %{
      type: :local,
      from: from,
      to: {current_module, function, arity},
      line: line
    }
    
    %{state | calls: [call_info | state.calls]}
  end
  
  defp add_capture(state, function, arity, meta) do
    line = meta[:line] || 0
    from = get_current_location(state)
    current_module = get_current_module(state)
    
    call_info = %{
      type: :capture,
      from: from,
      to: {current_module, function, arity},
      line: line
    }
    
    %{state | calls: [call_info | state.calls]}
  end
  
  defp analyze_case(state, _expr, clauses, _meta) do
    Enum.reduce(clauses, state, fn {:->, clause_meta, [pattern, _body]}, acc ->
      extract_pattern_variables(hd(pattern), acc, :pattern, clause_meta)
    end)
  end
  
  defp analyze_with(state, args, _meta) do
    Enum.reduce(args, state, fn
      {:<-, meta, [pattern, _expr]}, acc ->
        extract_pattern_variables(pattern, acc, :pattern, meta)
      _, acc ->
        acc
    end)
  end
  
  defp analyze_anonymous_function(state, clauses, meta) do
    line = meta[:line] || 0
    from = get_current_location(state)
    
    # Add anonymous function call tracking
    call_info = %{
      type: :anonymous,
      from: from,
      to: {:anonymous, line},
      line: line
    }
    
    state = %{state | calls: [call_info | state.calls]}
    
    # Analyze clauses for variables
    Enum.reduce(clauses, state, fn {:->, clause_meta, [args, _body]}, acc ->
      Enum.reduce(args, acc, fn arg, acc2 ->
        extract_pattern_variables(arg, acc2, :pattern, clause_meta)
      end)
    end)
  end
  
  defp add_import(state, module, opts, meta) do
    line = meta[:line] || 0
    module_name = extract_module_name(module)
    
    import_info = %{
      module: module_name,
      only: opts[:only],
      except: opts[:except],
      line: line
    }
    
    %{state | imports: [import_info | state.imports]}
  end
  
  defp add_alias(state, module, opts, meta) do
    line = meta[:line] || 0
    module_name = extract_module_name(module)
    as = if opts[:as], do: extract_module_name(opts[:as]), else: get_alias_default(module_name)
    
    alias_info = %{
      module: module_name,
      as: as,
      line: line
    }
    
    %{state | aliases: [alias_info | state.aliases]}
  end
  
  defp add_require(state, module, opts, meta) do
    line = meta[:line] || 0
    module_name = extract_module_name(module)
    as = if opts[:as], do: extract_module_name(opts[:as])
    
    require_info = %{
      module: module_name,
      as: as,
      line: line
    }
    
    %{state | requires: [require_info | state.requires]}
  end
  
  defp get_alias_default(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> String.to_atom()
  end
  
  defp get_current_module(state) do
    case state.modules do
      [%{name: module} | _] -> module
      [] -> nil
    end
  end
  
  defp get_current_location(state) do
    module = get_current_module(state)
    
    case state.functions do
      [%{name: function, arity: arity} | _] -> {module, function, arity}
      [] -> {module, nil, nil}
    end
  end
  
  defp get_current_scope(state) do
    case get_current_location(state) do
      {module, nil, nil} -> {:module, module}
      {_module, function, arity} -> {:function, function, arity}
    end
  end
  
  defp with_module_context(state, _module, fun) do
    # Just return the result of the function
    fun.(state)
  end
  
  defp format_parse_error({:error, {line, error, token}}) do
    %{
      type: :syntax_error,
      message: "#{error}#{token}",
      line: line,
      column: nil
    }
  end
  defp format_parse_error(error), do: error
  
  @doc """
  Builds a call graph from the analysis results.
  
  Returns a map where keys are {module, function, arity} tuples
  and values are lists of called functions.
  """
  @spec build_call_graph(t()) :: %{{module(), atom(), non_neg_integer()} => [{module(), atom(), non_neg_integer()}]}
  def build_call_graph(%__MODULE__{calls: calls}) do
    Enum.reduce(calls, %{}, fn call, graph ->
      from = call.from
      to = call.to
      
      Map.update(graph, from, [to], fn existing ->
        [to | existing] |> Enum.uniq()
      end)
    end)
  end
  
  @doc """
  Finds all variables in a specific scope.
  """
  @spec variables_in_scope(t(), {:module, module()} | {:function, atom(), non_neg_integer()}) :: [variable_info()]
  def variables_in_scope(%__MODULE__{variables: variables}, scope) do
    Enum.filter(variables, fn var ->
      var.scope == scope
    end)
  end
  
  @doc """
  Finds all calls from a specific function.
  """
  @spec calls_from_function(t(), module(), atom(), non_neg_integer()) :: [call_info()]
  def calls_from_function(%__MODULE__{calls: calls}, module, function, arity) do
    from = {module, function, arity}
    Enum.filter(calls, fn call ->
      call.from == from
    end)
  end
  
  @doc """
  Gets all functions in a module.
  """
  @spec functions_in_module(t(), module()) :: [function_info()]
  def functions_in_module(%__MODULE__{functions: functions}, module) do
    Enum.filter(functions, fn fun ->
      fun.module == module
    end)
  end
end
