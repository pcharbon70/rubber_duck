defmodule RubberDuck.Analysis.AST.Parser do
  @moduledoc """
  Behavior defining the interface for language-specific AST parsers.

  Each parser implementation must provide a `parse/1` function that
  takes source code and returns structured AST information.
  """

  @doc """
  Parses source code and extracts AST information.

  Should return structured information about:
  - Module/script type
  - Function definitions with signatures
  - Dependencies (aliases, imports, requires)
  - Other language-specific metadata

  ## Return Values

  - `{:ok, ast_info}` - Successfully parsed with extracted information
  - `{:error, reason}` - Failed to parse with error details
  """
  @callback parse(content :: String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Optional callback for parsing with additional options.

  Options might include:
  - `:include_comments` - Whether to parse and include comments
  - `:include_line_numbers` - Whether to include line number information
  - `:max_depth` - Maximum AST traversal depth
  """
  @callback parse(content :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks parse: 2
end

