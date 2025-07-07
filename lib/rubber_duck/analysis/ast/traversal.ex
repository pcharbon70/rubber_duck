defmodule RubberDuck.Analysis.AST.Traversal do
  @moduledoc """
  Common AST traversal utilities for working with parsed AST structures.

  Provides helpers for navigating, searching, and transforming AST data.
  """

  alias RubberDuck.Analysis.AST

  @doc """
  Finds all functions in the AST that match the given criteria.

  ## Options

  - `:name` - Function name to match (atom or regex)
  - `:arity` - Specific arity to match
  - `:private` - Whether to include private functions (default: true)
  - `:public` - Whether to include public functions (default: true)

  ## Examples

      iex> find_functions(ast_info, name: :process)
      [%{name: :process, arity: 1, line: 10, private: false}]
      
      iex> find_functions(ast_info, arity: 0, private: false)
      [%{name: :init, arity: 0, line: 5, private: false}]
  """
  @spec find_functions(AST.ast_info(), keyword()) :: list(AST.function_info())
  def find_functions(ast_info, opts \\ []) do
    include_private = Keyword.get(opts, :private, true)
    include_public = Keyword.get(opts, :public, true)

    ast_info.functions
    |> Enum.filter(fn func ->
      visibility_match?(func, include_private, include_public) &&
        name_match?(func, opts[:name]) &&
        arity_match?(func, opts[:arity])
    end)
  end

  @doc """
  Finds all function calls from or to specific functions.

  ## Options

  - `:from` - Find calls from this function {module, name, arity}
  - `:to` - Find calls to this function {module, name, arity}
  - `:module` - Filter by module name

  ## Examples

      iex> find_calls(ast_info, from: {MyModule, :init, 0})
      [%{from: {MyModule, :init, 0}, to: {Logger, :info, 1}, line: 10}]
  """
  @spec find_calls(AST.ast_info(), keyword()) :: list(AST.call_info())
  def find_calls(ast_info, opts \\ []) do
    ast_info.calls
    |> Enum.filter(fn call ->
      from_match?(call, opts[:from]) &&
        to_match?(call, opts[:to]) &&
        module_match?(call, opts[:module])
    end)
  end

  @doc """
  Builds a dependency graph showing which modules depend on which others.

  Returns a map where keys are module names and values are sets of 
  modules they depend on (through aliases, imports, or requires).
  """
  @spec dependency_graph(AST.ast_info()) :: %{module() => MapSet.t(module())}
  def dependency_graph(ast_info) do
    deps = MapSet.new(ast_info.aliases ++ ast_info.imports ++ ast_info.requires)

    if ast_info.name do
      %{ast_info.name => deps}
    else
      %{}
    end
  end

  @doc """
  Finds all modules referenced in the AST (including through function calls).
  """
  @spec referenced_modules(AST.ast_info()) :: MapSet.t(module())
  def referenced_modules(ast_info) do
    direct_deps = MapSet.new(ast_info.aliases ++ ast_info.imports ++ ast_info.requires)

    called_modules =
      ast_info.calls
      |> Enum.map(fn %{to: {module, _, _}} -> module end)
      |> Enum.reject(&(&1 == ast_info.name))
      |> MapSet.new()

    MapSet.union(direct_deps, called_modules)
  end

  @doc """
  Checks if a function is recursive (calls itself).
  """
  @spec recursive_function?(AST.ast_info(), atom(), non_neg_integer()) :: boolean()
  def recursive_function?(ast_info, function_name, arity) do
    from = {ast_info.name, function_name, arity}

    Enum.any?(ast_info.calls, fn call ->
      call.from == from && call.to == from
    end)
  end

  @doc """
  Finds all unused functions (functions that are never called within the module).

  Note: This only checks internal calls. Functions may still be used externally.
  """
  @spec find_unused_functions(AST.ast_info()) :: list(AST.function_info())
  def find_unused_functions(ast_info) do
    called_functions =
      ast_info.calls
      |> Enum.filter(fn %{to: {module, _, _}} -> module == ast_info.name end)
      |> Enum.map(fn %{to: {_, name, arity}} -> {name, arity} end)
      |> MapSet.new()

    ast_info.functions
    |> Enum.reject(fn func ->
      MapSet.member?(called_functions, {func.name, func.arity})
    end)
  end

  @doc """
  Calculates complexity metrics for the AST.
  """
  @spec complexity_metrics(AST.ast_info()) :: map()
  def complexity_metrics(ast_info) do
    %{
      module_name: ast_info.name,
      function_count: length(ast_info.functions),
      public_function_count: Enum.count(ast_info.functions, &(!&1.private)),
      private_function_count: Enum.count(ast_info.functions, & &1.private),
      dependency_count: length(ast_info.aliases) + length(ast_info.imports) + length(ast_info.requires),
      call_count: length(ast_info.calls),
      unique_called_modules: referenced_modules(ast_info) |> MapSet.size()
    }
  end

  # Private helpers

  defp visibility_match?(func, include_private, include_public) do
    (func.private && include_private) || (!func.private && include_public)
  end

  defp name_match?(_func, nil), do: true
  defp name_match?(func, name) when is_atom(name), do: func.name == name
  defp name_match?(func, %Regex{} = regex), do: Regex.match?(regex, Atom.to_string(func.name))

  defp arity_match?(_func, nil), do: true
  defp arity_match?(func, arity), do: func.arity == arity

  defp from_match?(_call, nil), do: true
  defp from_match?(call, from), do: call.from == from

  defp to_match?(_call, nil), do: true
  defp to_match?(call, to), do: call.to == to

  defp module_match?(_call, nil), do: true
  defp module_match?(%{from: {module, _, _}}, module), do: true
  defp module_match?(%{to: {module, _, _}}, module), do: true
  defp module_match?(_, _), do: false
end
