defmodule RubberDuck.ILP.Parser.Behaviour do
  @moduledoc """
  Behavior for language parsers in the ILP system.
  Defines the interface that all language parsers must implement.
  """

  @doc """
  Parses source code and returns a unified AST.
  """
  @callback parse(source :: String.t(), opts :: keyword()) :: 
    {:ok, RubberDuck.ILP.AST.Node.t()} | {:error, term()}

  @doc """
  Gets the language identifier supported by this parser.
  """
  @callback language() :: atom()

  @doc """
  Gets the file extensions supported by this parser.
  """
  @callback file_extensions() :: [String.t()]

  @doc """
  Gets parser capabilities and features.
  """
  @callback capabilities() :: %{
    supports_incremental: boolean(),
    supports_syntax_highlighting: boolean(),
    supports_folding: boolean(),
    supports_symbols: boolean(),
    supports_semantic_tokens: boolean()
  }

  @doc """
  Validates if source code is syntactically correct.
  """
  @callback validate(source :: String.t()) :: 
    {:ok, []} | {:error, [%{line: integer(), column: integer(), message: String.t()}]}

  @doc """
  Extracts symbols from the AST for navigation and completion.
  """
  @callback extract_symbols(ast :: RubberDuck.ILP.AST.Node.t()) :: 
    [%{name: String.t(), kind: atom(), range: map(), detail: String.t()}]

  @doc """
  Gets syntax highlighting tokens for the source code.
  """
  @callback get_syntax_tokens(source :: String.t()) :: 
    [%{type: atom(), range: map(), modifiers: [atom()]}]

  @doc """
  Gets folding ranges for code structure.
  """
  @callback get_folding_ranges(ast :: RubberDuck.ILP.AST.Node.t()) :: 
    [%{start_line: integer(), end_line: integer(), kind: atom()}]
end