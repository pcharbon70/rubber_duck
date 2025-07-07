defimpl RubberDuck.Processor, for: List do
  @moduledoc """
  Processor implementation for List data type.

  Handles processing of list/array data structures, including:
  - Batch operations
  - Element transformation
  - Filtering and mapping
  - Chunking and grouping
  """

  @doc """
  Process a list with various transformation options.

  ## Options

  - `:map` - Function to map over each element
  - `:filter` - Function to filter elements
  - `:chunk_size` - Split into chunks of given size
  - `:flatten` - Flatten nested lists (default: false)
  - `:unique` - Remove duplicates (default: false)
  - `:sort` - Sort the list (true, :asc, :desc, or comparator function)
  - `:limit` - Limit the number of elements
  - `:sample` - Random sample of N elements
  - `:batch_process` - Process elements in batches with given function
  """
  def process(list, opts) do
    result =
      list
      |> maybe_flatten(opts)
      |> maybe_filter(opts)
      |> maybe_map(opts)
      |> maybe_unique(opts)
      |> maybe_sort(opts)
      |> maybe_chunk(opts)
      |> maybe_batch_process(opts)
      |> maybe_limit(opts)
      |> maybe_sample(opts)

    {:ok, result}
  rescue
    e -> {:error, e}
  end

  @doc """
  Extract metadata from the list.
  """
  def metadata(list) do
    %{
      type: :list,
      length: length(list),
      empty: Enum.empty?(list),
      element_types: detect_element_types(list),
      has_nested_lists: has_nested_lists?(list),
      max_depth: calculate_max_depth(list),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Validate the list structure.
  """
  def validate(list) when is_list(list) do
    :ok
  end

  @doc """
  Normalize the list by flattening single-element nested lists.
  """
  def normalize(list) do
    Enum.map(list, fn
      [single_element] -> single_element
      element -> element
    end)
  end

  # Private functions

  defp maybe_flatten(list, opts) do
    case Keyword.get(opts, :flatten) do
      true -> List.flatten(list)
      depth when is_integer(depth) -> flatten_to_depth(list, depth)
      _ -> list
    end
  end

  defp flatten_to_depth(list, 0), do: list

  defp flatten_to_depth(list, depth) do
    Enum.flat_map(list, fn
      sublist when is_list(sublist) -> flatten_to_depth(sublist, depth - 1)
      element -> [element]
    end)
  end

  defp maybe_filter(list, opts) do
    case Keyword.get(opts, :filter) do
      nil -> list
      func when is_function(func, 1) -> Enum.filter(list, func)
    end
  end

  defp maybe_map(list, opts) do
    case Keyword.get(opts, :map) do
      nil -> list
      func when is_function(func, 1) -> Enum.map(list, func)
    end
  end

  defp maybe_unique(list, opts) do
    if Keyword.get(opts, :unique, false) do
      Enum.uniq(list)
    else
      list
    end
  end

  defp maybe_sort(list, opts) do
    case Keyword.get(opts, :sort) do
      nil -> list
      true -> Enum.sort(list)
      :asc -> Enum.sort(list)
      :desc -> Enum.sort(list, :desc)
      func when is_function(func, 2) -> Enum.sort(list, func)
    end
  end

  defp maybe_chunk(list, opts) do
    case Keyword.get(opts, :chunk_size) do
      nil ->
        list

      size when is_integer(size) and size > 0 ->
        Enum.chunk_every(list, size)
    end
  end

  defp maybe_batch_process(list, opts) do
    case Keyword.get(opts, :batch_process) do
      nil ->
        list

      {func, batch_size} when is_function(func, 1) and is_integer(batch_size) ->
        list
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(func)

      _ ->
        list
    end
  end

  defp maybe_limit(list, opts) do
    case Keyword.get(opts, :limit) do
      nil -> list
      n when is_integer(n) and n > 0 -> Enum.take(list, n)
    end
  end

  defp maybe_sample(list, opts) do
    case Keyword.get(opts, :sample) do
      nil -> list
      n when is_integer(n) and n > 0 -> Enum.take_random(list, n)
    end
  end

  defp detect_element_types(list) do
    list
    # Sample first 100 elements for performance
    |> Enum.take(100)
    |> Enum.map(&type_of/1)
    |> Enum.frequencies()
  end

  defp type_of(value) do
    cond do
      is_nil(value) -> nil
      is_atom(value) -> :atom
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_list(value) -> :list
      is_map(value) -> :map
      is_tuple(value) -> :tuple
      true -> :other
    end
  end

  defp has_nested_lists?(list) do
    Enum.any?(list, &is_list/1)
  end

  defp calculate_max_depth(list, current_depth \\ 1) do
    nested_depths =
      list
      |> Enum.filter(&is_list/1)
      |> Enum.map(&calculate_max_depth(&1, current_depth + 1))

    case nested_depths do
      [] -> current_depth
      depths -> Enum.max(depths)
    end
  end
end
