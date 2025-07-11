defmodule RubberDuck.Analysis.AST do
  @moduledoc """
  Main AST parsing module that delegates to language-specific parsers.

  Provides a unified interface for parsing code into abstract syntax trees
  and extracting metadata for analysis workflows.
  """

  @type language :: :elixir | :javascript | :typescript
  @type ast_info :: %{
          type: :module | :script,
          name: atom() | nil,
          functions: list(function_info()),
          aliases: list(module()),
          imports: list(module()),
          requires: list(module()),
          calls: list(call_info()),
          variables: list(variable_info()),
          metadata: map()
        }
  @type function_info :: %{
          name: atom(),
          arity: non_neg_integer(),
          line: non_neg_integer(),
          private: boolean(),
          variables: list(variable_info()),
          body_calls: list(call_info())
        }
  @type variable_info :: %{
          name: atom(),
          line: non_neg_integer(),
          column: non_neg_integer() | nil,
          context: atom() | nil,
          type: :assignment | :match | :usage,
          scope: {module(), atom(), non_neg_integer()} | :module
        }
  @type call_info :: %{
          from: {module(), atom(), non_neg_integer()},
          to: {module(), atom(), non_neg_integer()},
          line: non_neg_integer()
        }
  @type parse_result :: {:ok, ast_info()} | {:error, term()}

  @doc """
  Parses code content based on the specified language.

  ## Examples

      iex> AST.parse("defmodule Example do\\n  def hello, do: :world\\nend", :elixir)
      {:ok, %{type: :module, name: Example, functions: [%{name: :hello, arity: 0, line: 2, private: false}], ...}}
      
      iex> AST.parse("const x = 1", :javascript)
      {:ok, %{type: :script, name: nil, ...}}
      
      iex> AST.parse("code", :ruby)
      {:error, :unsupported_language}
  """
  @spec parse(String.t(), language()) :: parse_result()
  def parse(content, language) do
    case get_parser(language) do
      {:ok, parser_module} ->
        parser_module.parse(content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the parser module for the given language.
  """
  @spec get_parser(language()) :: {:ok, module()} | {:error, :unsupported_language}
  def get_parser(:elixir), do: {:ok, RubberDuck.Analysis.AST.SourcerorParser}
  def get_parser(:javascript), do: {:error, :not_implemented_yet}
  def get_parser(:typescript), do: {:error, :not_implemented_yet}
  def get_parser(_), do: {:error, :unsupported_language}

  @doc """
  Extracts call graph information from parsed AST.

  Returns a map of function calls showing which functions call which others.
  """
  @spec extract_call_graph(ast_info()) :: %{
          {module(), atom(), non_neg_integer()} => list({module(), atom(), non_neg_integer()})
        }
  def extract_call_graph(ast_info) do
    ast_info.calls
    |> Enum.group_by(& &1.from)
    |> Enum.map(fn {from, calls} ->
      {from, Enum.map(calls, & &1.to) |> Enum.uniq()}
    end)
    |> Map.new()
  end

  @doc """
  Compares two AST structures and returns the differences.
  """
  @spec diff(ast_info(), ast_info()) :: %{
          added: list(function_info()),
          removed: list(function_info()),
          changed: list(function_info())
        }
  def diff(_ast1, _ast2) do
    # Placeholder for AST diffing functionality
    %{added: [], removed: [], changed: []}
  end
end
