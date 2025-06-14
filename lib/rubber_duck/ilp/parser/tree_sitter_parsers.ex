defmodule RubberDuck.ILP.Parser.TreeSitterParsers do
  @moduledoc """
  Auto-generated Tree-sitter parser modules for supported languages.
  """

  require RubberDuck.ILP.Parser.TreeSitterWrapper
  alias RubberDuck.ILP.Parser.TreeSitterWrapper

  # Generate parser modules for all supported languages
  TreeSitterWrapper.defparser :javascript, extensions: [".js", ".mjs"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :typescript, extensions: [".ts", ".tsx"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :python, extensions: [".py"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :go, extensions: [".go"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :rust, extensions: [".rs"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :java, extensions: [".java"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :cpp, extensions: [".cpp", ".cc", ".cxx"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :c, extensions: [".c", ".h"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :csharp, extensions: [".cs"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :ruby, extensions: [".rb"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :php, extensions: [".php"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :swift, extensions: [".swift"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :kotlin, extensions: [".kt"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :scala, extensions: [".scala"], capabilities: %{supports_semantic_tokens: true}
  TreeSitterWrapper.defparser :html, extensions: [".html", ".htm"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :css, extensions: [".css"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :json, extensions: [".json"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :yaml, extensions: [".yaml", ".yml"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :markdown, extensions: [".md"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :dockerfile, extensions: ["Dockerfile"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :bash, extensions: [".sh"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :sql, extensions: [".sql"], capabilities: %{supports_semantic_tokens: false}
  TreeSitterWrapper.defparser :erlang, extensions: [".erl", ".hrl"], capabilities: %{supports_semantic_tokens: true}
end