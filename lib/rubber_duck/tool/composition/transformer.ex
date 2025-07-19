defmodule RubberDuck.Tool.Composition.Transformer do
  @moduledoc """
  Data transformation utilities for workflow steps.

  Provides automatic data conversion, extraction, and mapping between
  workflow steps to ensure compatibility between different tools.
  """

  require Logger

  @doc """
  Transforms data from one format to another.

  Supports various transformation types:
  - Type conversion (string to integer, etc.)
  - JSONPath extraction
  - Template-based mapping
  - Custom transformation functions

  ## Examples

      # Type conversion
      {:ok, 123} = Transformer.transform("123", {:type, :integer})
      
      # Path extraction
      {:ok, "John"} = Transformer.transform(%{user: %{name: "John"}}, {:extract, "user.name"})
      
      # Template mapping
      {:ok, "Hello John"} = Transformer.transform(%{name: "John"}, {:template, "Hello {{name}}"})
      
      # Custom function
      {:ok, "HELLO"} = Transformer.transform("hello", {:custom, &String.upcase/1})
  """
  @spec transform(term(), term()) :: {:ok, term()} | {:error, term()}
  def transform(data, transformation_spec) do
    case transformation_spec do
      {:type, target_type} ->
        convert_type(data, target_type)

      {:extract, path} ->
        extract_path(data, path)

      {:template, template} ->
        apply_template(data, template)

      {:custom, fun} when is_function(fun, 1) ->
        apply_custom_function(data, fun)

      {:compose, transformations} ->
        compose_transformations(data, transformations)

      {:map, transformation} ->
        map_transformation(data, transformation)

      {:filter, condition} ->
        filter_data(data, condition)

      _ ->
        {:error, "Unknown transformation type: #{inspect(transformation_spec)}"}
    end
  end

  @doc """
  Converts data to a different type.

  Supported conversions:
  - :string, :integer, :float, :boolean, :atom
  - :list, :map, :tuple
  - :json (encode/decode)
  """
  @spec convert_type(term(), atom()) :: {:ok, term()} | {:error, term()}
  def convert_type(data, target_type) do
    try do
      converted = do_convert_type(data, target_type)
      {:ok, converted}
    rescue
      error -> {:error, "Type conversion failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Extracts data using JSONPath-like syntax.

  Supports:
  - Simple paths: "user.name"
  - Array indices: "users[0].name"
  - Wildcards: "users[*].name"
  """
  @spec extract_path(term(), String.t()) :: {:ok, term()} | {:error, term()}
  def extract_path(data, path) when is_binary(path) do
    if is_map(data) or is_list(data) do
      try do
        result = do_extract_path(data, parse_path(path))
        {:ok, result}
      rescue
        error -> {:error, "Path extraction failed: #{Exception.message(error)}"}
      end
    else
      {:error, "Path extraction requires a map or list, got: #{inspect(data)}"}
    end
  end

  @doc """
  Applies a template to transform data.

  Templates support:
  - Variable substitution: "Hello {{name}}"
  - Nested paths: "User {{user.name}} has {{user.orders.length}} orders"
  """
  @spec apply_template(term(), String.t()) :: {:ok, term()} | {:error, term()}
  def apply_template(data, template) when is_binary(template) do
    if is_map(data) or is_list(data) do
      try do
        result = do_apply_template(data, template)
        {:ok, result}
      rescue
        error -> {:error, "Template application failed: #{Exception.message(error)}"}
      end
    else
      {:error, "Template application requires a map or list, got: #{inspect(data)}"}
    end
  end

  @doc """
  Applies a custom transformation function.
  """
  @spec apply_custom_function(term(), function()) :: {:ok, term()} | {:error, term()}
  def apply_custom_function(data, fun) when is_function(fun, 1) do
    try do
      result = fun.(data)
      {:ok, result}
    rescue
      error -> {:error, "Custom function failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Composes multiple transformations in sequence.
  """
  @spec compose_transformations(term(), [term()]) :: {:ok, term()} | {:error, term()}
  def compose_transformations(data, transformations) when is_list(transformations) do
    Enum.reduce_while(transformations, {:ok, data}, fn transformation, {:ok, acc_data} ->
      case transform(acc_data, transformation) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Maps a transformation over a list of data.
  """
  @spec map_transformation(term(), term()) :: {:ok, term()} | {:error, term()}
  def map_transformation(data, transformation) when is_list(data) do
    results =
      Enum.map(data, fn item ->
        case transform(item, transformation) do
          {:ok, result} -> result
          {:error, error} -> {:error, error}
        end
      end)

    # Check if any transformations failed
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, results}
      error -> error
    end
  end

  def map_transformation(data, _transformation) do
    {:error, "Map transformation requires a list, got: #{inspect(data)}"}
  end

  @doc """
  Filters data based on a condition.
  """
  @spec filter_data(term(), term()) :: {:ok, term()} | {:error, term()}
  def filter_data(data, condition) when is_list(data) do
    try do
      filtered =
        Enum.filter(data, fn item ->
          evaluate_condition(item, condition)
        end)

      {:ok, filtered}
    rescue
      error -> {:error, "Filter failed: #{Exception.message(error)}"}
    end
  end

  def filter_data(data, _condition) do
    {:error, "Filter requires a list, got: #{inspect(data)}"}
  end

  # Private implementation functions

  defp do_convert_type(data, :string) do
    to_string(data)
  end

  defp do_convert_type(data, :integer) when is_binary(data) do
    String.to_integer(data)
  end

  defp do_convert_type(data, :integer) when is_float(data) do
    trunc(data)
  end

  defp do_convert_type(data, :integer) when is_integer(data) do
    data
  end

  defp do_convert_type(data, :float) when is_binary(data) do
    String.to_float(data)
  end

  defp do_convert_type(data, :float) when is_integer(data) do
    data * 1.0
  end

  defp do_convert_type(data, :float) when is_float(data) do
    data
  end

  defp do_convert_type(data, :boolean) when data in [true, false] do
    data
  end

  defp do_convert_type("true", :boolean), do: true
  defp do_convert_type("false", :boolean), do: false
  defp do_convert_type(1, :boolean), do: true
  defp do_convert_type(0, :boolean), do: false

  defp do_convert_type(data, :atom) when is_binary(data) do
    String.to_atom(data)
  end

  defp do_convert_type(data, :atom) when is_atom(data) do
    data
  end

  defp do_convert_type(data, :list) when is_list(data) do
    data
  end

  defp do_convert_type(data, :list) when is_map(data) do
    Map.to_list(data)
  end

  defp do_convert_type(data, :map) when is_map(data) do
    data
  end

  defp do_convert_type(data, :map) when is_list(data) do
    Enum.into(data, %{})
  end

  defp do_convert_type(data, :json) do
    Jason.encode!(data)
  end

  defp do_convert_type(data, :from_json) when is_binary(data) do
    Jason.decode!(data)
  end

  defp do_convert_type(data, target_type) do
    raise "Cannot convert #{inspect(data)} to #{target_type}"
  end

  defp parse_path(path) do
    path
    |> String.split(".")
    |> Enum.map(&parse_path_segment/1)
  end

  defp parse_path_segment(segment) do
    cond do
      String.contains?(segment, "[") ->
        # Handle array indices like "users[0]" or "users[*]"
        [key, index_part] = String.split(segment, "[", parts: 2)
        index = String.trim_trailing(index_part, "]")

        case index do
          "*" -> {:key_wildcard, key}
          _ -> {:key_index, key, String.to_integer(index)}
        end

      true ->
        {:key, segment}
    end
  end

  defp do_extract_path(data, path_segments) do
    Enum.reduce(path_segments, data, fn segment, acc ->
      extract_segment(acc, segment)
    end)
  end

  defp extract_segment(data, {:key, key}) when is_map(data) do
    Map.get(data, key) || Map.get(data, String.to_atom(key))
  end

  defp extract_segment(data, {:key_index, key, index}) when is_map(data) do
    list_data = Map.get(data, key) || Map.get(data, String.to_atom(key))

    if is_list(list_data) do
      Enum.at(list_data, index)
    else
      nil
    end
  end

  defp extract_segment(data, {:key_wildcard, key}) when is_map(data) do
    list_data = Map.get(data, key) || Map.get(data, String.to_atom(key))

    if is_list(list_data) do
      list_data
    else
      []
    end
  end

  defp extract_segment(_data, _segment) do
    nil
  end

  defp do_apply_template(data, template) do
    # Simple template engine - replace {{path}} with values
    Regex.replace(~r/\{\{([^}]+)\}\}/, template, fn _, path ->
      case extract_path(data, String.trim(path)) do
        {:ok, value} -> to_string(value)
        {:error, _} -> ""
      end
    end)
  end

  defp evaluate_condition(item, condition) do
    case condition do
      {:equals, value} -> item == value
      {:not_equals, value} -> item != value
      {:greater_than, value} -> is_number(item) and is_number(value) and item > value
      {:less_than, value} -> is_number(item) and is_number(value) and item < value
      {:contains, value} -> contains_value?(item, value)
      {:matches, pattern} -> is_binary(item) and Regex.match?(pattern, item)
      fun when is_function(fun, 1) -> fun.(item)
      _ -> false
    end
  end

  defp contains_value?(result, value) when is_list(result) do
    value in result
  end

  defp contains_value?(result, value) when is_binary(result) and is_binary(value) do
    String.contains?(result, value)
  end

  defp contains_value?(result, value) when is_map(result) do
    Map.has_key?(result, value)
  end

  defp contains_value?(_, _), do: false
end
