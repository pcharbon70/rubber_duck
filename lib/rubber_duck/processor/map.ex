defimpl RubberDuck.Processor, for: Map do
  @moduledoc """
  Processor implementation for Map data type.
  
  Handles processing of map/dictionary data structures, including:
  - Nested map flattening
  - Key transformation
  - Value extraction
  - Schema validation
  """
  
  @doc """
  Process a map with various transformation options.
  
  ## Options
  
  - `:flatten` - Flatten nested maps (default: false)
  - `:transform_keys` - Function to transform keys
  - `:filter_keys` - List of keys to include
  - `:exclude_keys` - List of keys to exclude
  - `:stringify_keys` - Convert keys to strings (default: false)
  - `:atomize_keys` - Convert keys to atoms (default: false, use with caution)
  """
  def process(map, opts) do
    result = map
    |> maybe_flatten(opts)
    |> maybe_transform_keys(opts)
    |> maybe_filter_keys(opts)
    |> maybe_stringify_keys(opts)
    |> maybe_atomize_keys(opts)
    
    {:ok, result}
  rescue
    e -> {:error, e}
  end
  
  @doc """
  Extract metadata from the map.
  """
  def metadata(map) do
    %{
      type: :map,
      size: map_size(map),
      keys: Map.keys(map),
      depth: calculate_depth(map),
      has_nested_maps: has_nested_maps?(map),
      timestamp: DateTime.utc_now()
    }
  end
  
  @doc """
  Validate the map structure.
  """
  def validate(map) when is_map(map) do
    :ok
  end
  
  @doc """
  Normalize the map by sorting keys and converting to consistent format.
  """
  def normalize(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Map.new()
  end
  
  # Private functions
  
  defp maybe_flatten(map, opts) do
    if Keyword.get(opts, :flatten, false) do
      flatten_map(map)
    else
      map
    end
  end
  
  defp flatten_map(map, prefix \\ "") do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      new_key = if prefix == "", do: to_string(key), else: "#{prefix}.#{key}"
      
      case value do
        %{} = nested_map when map_size(nested_map) > 0 ->
          Map.merge(acc, flatten_map(nested_map, new_key))
          
        _ ->
          Map.put(acc, new_key, value)
      end
    end)
  end
  
  defp maybe_transform_keys(map, opts) do
    case Keyword.get(opts, :transform_keys) do
      nil -> map
      func when is_function(func, 1) ->
        Map.new(map, fn {k, v} -> {func.(k), v} end)
    end
  end
  
  defp maybe_filter_keys(map, opts) do
    cond do
      filter = Keyword.get(opts, :filter_keys) ->
        Map.take(map, filter)
        
      exclude = Keyword.get(opts, :exclude_keys) ->
        Map.drop(map, exclude)
        
      true ->
        map
    end
  end
  
  defp maybe_stringify_keys(map, opts) do
    if Keyword.get(opts, :stringify_keys, false) do
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    else
      map
    end
  end
  
  defp maybe_atomize_keys(map, opts) do
    if Keyword.get(opts, :atomize_keys, false) do
      # Only atomize existing atoms for safety
      Map.new(map, fn 
        {k, v} when is_binary(k) ->
          try do
            {String.to_existing_atom(k), v}
          rescue
            ArgumentError -> {k, v}
          end
          
        {k, v} ->
          {k, v}
      end)
    else
      map
    end
  end
  
  defp calculate_depth(map, current_depth \\ 1) do
    nested_depths = map
    |> Map.values()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&calculate_depth(&1, current_depth + 1))
    
    case nested_depths do
      [] -> current_depth
      depths -> Enum.max(depths)
    end
  end
  
  defp has_nested_maps?(map) do
    Enum.any?(Map.values(map), &is_map/1)
  end
end