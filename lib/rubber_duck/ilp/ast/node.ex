defmodule RubberDuck.ILP.AST.Node do
  @moduledoc """
  Unified AST node structure that works across all supported languages.
  Provides a common interface while preserving language-specific information.
  """

  defstruct [
    :type,
    :value,
    :children,
    :metadata,
    :position,
    :language,
    :source_range,
    :semantic_info
  ]

  @type position :: %{
    line: non_neg_integer(),
    column: non_neg_integer()
  }

  @type source_range :: %{
    start: position(),
    end: position()
  }

  @type semantic_info :: %{
    scope: atom(),
    references: [map()],
    definitions: [map()],
    type_info: map(),
    documentation: String.t() | nil
  }

  @type t :: %__MODULE__{
    type: atom(),
    value: term(),
    children: [t()],
    metadata: map(),
    position: position() | nil,
    language: atom(),
    source_range: source_range() | nil,
    semantic_info: semantic_info() | nil
  }

  @doc """
  Creates a new AST node.
  """
  def new(type, opts \\ []) do
    %__MODULE__{
      type: type,
      value: Keyword.get(opts, :value),
      children: Keyword.get(opts, :children, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      position: Keyword.get(opts, :position),
      language: Keyword.get(opts, :language, :unknown),
      source_range: Keyword.get(opts, :source_range),
      semantic_info: Keyword.get(opts, :semantic_info)
    }
  end

  @doc """
  Adds a child node to the current node.
  """
  def add_child(%__MODULE__{children: children} = node, child) do
    %{node | children: children ++ [child]}
  end

  @doc """
  Adds multiple child nodes to the current node.
  """
  def add_children(%__MODULE__{children: children} = node, new_children) do
    %{node | children: children ++ new_children}
  end

  @doc """
  Sets metadata for the node.
  """
  def set_metadata(%__MODULE__{} = node, metadata) when is_map(metadata) do
    %{node | metadata: metadata}
  end

  @doc """
  Merges metadata into the existing metadata.
  """
  def merge_metadata(%__MODULE__{metadata: existing} = node, new_metadata) when is_map(new_metadata) do
    %{node | metadata: Map.merge(existing, new_metadata)}
  end

  @doc """
  Sets semantic information for the node.
  """
  def set_semantic_info(%__MODULE__{} = node, semantic_info) do
    %{node | semantic_info: semantic_info}
  end

  @doc """
  Walks the AST and applies a function to each node.
  """
  def walk(%__MODULE__{children: children} = node, fun) when is_function(fun, 1) do
    new_node = fun.(node)
    new_children = Enum.map(children, &walk(&1, fun))
    %{new_node | children: new_children}
  end

  @doc """
  Finds all nodes matching a predicate.
  """
  def find_all(%__MODULE__{} = node, predicate) when is_function(predicate, 1) do
    find_all_recursive(node, predicate, [])
  end

  defp find_all_recursive(%__MODULE__{children: children} = node, predicate, acc) do
    new_acc = if predicate.(node), do: [node | acc], else: acc
    
    Enum.reduce(children, new_acc, fn child, acc ->
      find_all_recursive(child, predicate, acc)
    end)
  end

  @doc """
  Finds the first node matching a predicate.
  """
  def find_first(%__MODULE__{} = node, predicate) when is_function(predicate, 1) do
    if predicate.(node) do
      {:ok, node}
    else
      find_first_in_children(node.children, predicate)
    end
  end

  defp find_first_in_children([], _predicate), do: {:error, :not_found}
  
  defp find_first_in_children([child | rest], predicate) do
    case find_first(child, predicate) do
      {:ok, node} -> {:ok, node}
      {:error, :not_found} -> find_first_in_children(rest, predicate)
    end
  end

  @doc """
  Gets all leaf nodes (nodes with no children).
  """
  def get_leaves(%__MODULE__{children: []} = node), do: [node]
  def get_leaves(%__MODULE__{children: children}) do
    Enum.flat_map(children, &get_leaves/1)
  end

  @doc """
  Gets the depth of the AST tree.
  """
  def depth(%__MODULE__{children: []}), do: 1
  def depth(%__MODULE__{children: children}) do
    1 + Enum.max(Enum.map(children, &depth/1))
  end

  @doc """
  Counts the total number of nodes in the AST.
  """
  def count_nodes(%__MODULE__{children: children}) do
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  @doc """
  Checks if a node is at a specific position.
  """
  def at_position?(%__MODULE__{source_range: nil}, _position), do: false
  def at_position?(%__MODULE__{source_range: range}, %{line: line, column: column}) do
    in_range?(range, line, column)
  end

  defp in_range?(%{start: start_pos, end: end_pos}, line, column) do
    (line > start_pos.line or (line == start_pos.line and column >= start_pos.column)) and
    (line < end_pos.line or (line == end_pos.line and column <= end_pos.column))
  end

  @doc """
  Converts the AST to a simplified map structure.
  """
  def to_map(%__MODULE__{} = node) do
    %{
      type: node.type,
      value: node.value,
      children: Enum.map(node.children, &to_map/1),
      metadata: node.metadata,
      position: node.position,
      language: node.language,
      source_range: node.source_range
    }
  end

  @doc """
  Pretty prints the AST structure.
  """
  def pretty_print(%__MODULE__{} = node, indent \\ 0) do
    indent_str = String.duplicate("  ", indent)
    
    IO.puts("#{indent_str}#{node.type}" <> 
      if(node.value, do: " (#{inspect(node.value)})", else: ""))
    
    Enum.each(node.children, &pretty_print(&1, indent + 1))
  end

  @doc """
  Gets the text content of a node and its children.
  """
  def get_text(%__MODULE__{value: value, children: []}) when is_binary(value), do: value
  def get_text(%__MODULE__{children: children}) do
    children
    |> Enum.map(&get_text/1)
    |> Enum.join("")
  end
  def get_text(%__MODULE__{value: value}) when is_binary(value), do: value
  def get_text(%__MODULE__{}), do: ""

  @doc """
  Validates the AST structure.
  """
  def validate(%__MODULE__{} = node) do
    with :ok <- validate_node(node),
         :ok <- validate_children(node.children) do
      :ok
    end
  end

  defp validate_node(%__MODULE__{type: type}) when is_atom(type), do: :ok
  defp validate_node(_), do: {:error, :invalid_node_type}

  defp validate_children([]), do: :ok
  defp validate_children([child | rest]) do
    with :ok <- validate(child),
         :ok <- validate_children(rest) do
      :ok
    end
  end
end