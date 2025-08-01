defmodule RubberDuck.Memory.MemoryQuery do
  @moduledoc """
  Query builder and executor for long-term memory searches.
  
  This module provides a fluent API for building complex queries against
  the memory storage system. Supports filtering, sorting, pagination,
  aggregation, and relevance ranking.
  """

  defstruct [
    :id,
    :filters,
    :sort,
    :pagination,
    :projections,
    :aggregations,
    :options,
    :metadata
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    filters: list(filter()),
    sort: list(sort_spec()),
    pagination: pagination(),
    projections: projections(),
    aggregations: list(aggregation()),
    options: query_options(),
    metadata: map()
  }

  @type filter :: %{
    field: String.t(),
    operator: filter_operator(),
    value: any(),
    combinator: :and | :or
  }

  @type filter_operator :: 
    :eq | :neq | :gt | :gte | :lt | :lte | 
    :in | :nin | :contains | :not_contains |
    :starts_with | :ends_with | :regex |
    :exists | :not_exists | :between

  @type sort_spec :: %{
    field: String.t(),
    direction: :asc | :desc,
    null_handling: :first | :last
  }

  @type pagination :: %{
    page: integer(),
    page_size: integer(),
    offset: integer() | nil,
    cursor: String.t() | nil
  }

  @type projections :: %{
    include: list(String.t()) | nil,
    exclude: list(String.t()) | nil
  }

  @type aggregation :: %{
    name: String.t(),
    type: :count | :sum | :avg | :min | :max | :distinct | :group_by,
    field: String.t() | nil,
    options: map()
  }

  @type query_options :: %{
    timeout_ms: integer(),
    include_deleted: boolean(),
    include_versions: boolean(),
    cache: boolean(),
    explain: boolean()
  }

  @default_page_size 20
  @max_page_size 100

  @doc """
  Creates a new query builder.
  """
  def new do
    %__MODULE__{
      id: generate_id(),
      filters: [],
      sort: [],
      pagination: %{
        page: 1,
        page_size: @default_page_size,
        offset: nil,
        cursor: nil
      },
      projections: %{include: nil, exclude: nil},
      aggregations: [],
      options: %{
        timeout_ms: 5000,
        include_deleted: false,
        include_versions: false,
        cache: true,
        explain: false
      },
      metadata: %{}
    }
  end

  @doc """
  Builds a query from a map of parameters.
  """
  def build(params) when is_map(params) do
    query = new()
    
    query
    |> apply_filters(params["filters"] || params[:filters])
    |> apply_sorting(params["sort"] || params[:sort])
    |> apply_pagination(params["pagination"] || params[:pagination])
    |> apply_projections(params["projections"] || params[:projections])
    |> apply_options(params["options"] || params[:options])
  end

  @doc """
  Adds a filter condition to the query.
  """
  def where(query, field, operator, value, combinator \\ :and) do
    filter = %{
      field: to_string(field),
      operator: operator,
      value: value,
      combinator: combinator
    }
    
    %{query | filters: query.filters ++ [filter]}
  end

  @doc """
  Adds multiple filter conditions.
  """
  def where_all(query, conditions) do
    Enum.reduce(conditions, query, fn {field, op, value}, acc ->
      where(acc, field, op, value)
    end)
  end

  @doc """
  Filters by memory type.
  """
  def by_type(query, type) when is_atom(type) do
    where(query, :type, :eq, type)
  end

  def by_type(query, types) when is_list(types) do
    where(query, :type, :in, types)
  end

  @doc """
  Filters by tags.
  """
  def with_tags(query, tags) when is_list(tags) do
    Enum.reduce(tags, query, fn tag, acc ->
      where(acc, :tags, :contains, tag)
    end)
  end

  def with_any_tags(query, tags) when is_list(tags) do
    where(query, :tags, :in, tags)
  end

  @doc """
  Filters by date range.
  """
  def created_between(query, start_date, end_date) do
    where(query, :created_at, :between, {start_date, end_date})
  end

  def updated_since(query, date) do
    where(query, :updated_at, :gte, date)
  end

  def accessed_since(query, date) do
    where(query, :accessed_at, :gte, date)
  end

  @doc """
  Adds text search filter.
  """
  def search(query, text) do
    where(query, :content, :contains, text)
  end

  @doc """
  Adds metadata filter.
  """
  def with_metadata(query, key, value) do
    where(query, "metadata.#{key}", :eq, value)
  end

  @doc """
  Adds sorting to the query.
  """
  def order_by(query, field, direction \\ :asc) do
    sort_spec = %{
      field: to_string(field),
      direction: direction,
      null_handling: :last
    }
    
    %{query | sort: query.sort ++ [sort_spec]}
  end

  @doc """
  Sets pagination parameters.
  """
  def paginate(query, page, page_size \\ @default_page_size) do
    page_size = min(page_size, @max_page_size)
    
    put_in(query.pagination.page, page)
    |> put_in([Access.key(:pagination), :page_size], page_size)
    |> put_in([Access.key(:pagination), :offset], (page - 1) * page_size)
  end

  @doc """
  Sets cursor-based pagination.
  """
  def after_cursor(query, cursor) do
    put_in(query.pagination.cursor, cursor)
  end

  @doc """
  Sets result limit (alternative to pagination).
  """
  def limit(query, limit) do
    paginate(query, 1, limit)
  end

  @doc """
  Sets result offset.
  """
  def offset(query, offset) do
    put_in(query.pagination.offset, offset)
  end

  @doc """
  Specifies fields to include in results.
  """
  def select(query, fields) when is_list(fields) do
    put_in(query.projections.include, Enum.map(fields, &to_string/1))
  end

  @doc """
  Specifies fields to exclude from results.
  """
  def exclude(query, fields) when is_list(fields) do
    put_in(query.projections.exclude, Enum.map(fields, &to_string/1))
  end

  @doc """
  Adds an aggregation to the query.
  """
  def aggregate(query, name, type, field \\ nil, options \\ %{}) do
    aggregation = %{
      name: name,
      type: type,
      field: field && to_string(field),
      options: options
    }
    
    %{query | aggregations: query.aggregations ++ [aggregation]}
  end

  @doc """
  Groups results by a field.
  """
  def group_by(query, field) do
    aggregate(query, "group_#{field}", :group_by, field)
  end

  @doc """
  Counts results.
  """
  def count(query) do
    aggregate(query, "total_count", :count)
  end

  @doc """
  Includes deleted records in results.
  """
  def include_deleted(query, include \\ true) do
    put_in(query.options.include_deleted, include)
  end

  @doc """
  Includes version history in results.
  """
  def include_versions(query, include \\ true) do
    put_in(query.options.include_versions, include)
  end

  @doc """
  Sets query timeout.
  """
  def timeout(query, timeout_ms) do
    put_in(query.options.timeout_ms, timeout_ms)
  end

  @doc """
  Enables query explanation.
  """
  def explain(query, explain \\ true) do
    put_in(query.options.explain, explain)
  end

  @doc """
  Converts query to executable format.
  """
  def to_executable(query) do
    %{
      filters: compile_filters(query.filters),
      sort: query.sort,
      pagination: query.pagination,
      projections: query.projections,
      aggregations: query.aggregations,
      options: query.options
    }
  end

  @doc """
  Validates the query structure.
  """
  def valid?(query) do
    with :ok <- validate_filters(query.filters),
         :ok <- validate_sort(query.sort),
         :ok <- validate_pagination(query.pagination),
         :ok <- validate_aggregations(query.aggregations) do
      true
    else
      {:error, _reason} -> false
    end
  end

  @doc """
  Returns a human-readable representation of the query.
  """
  def query_to_string(query) do
    parts = []
    
    # Add filters
    if query.filters != [] do
      filter_str = query.filters
      |> Enum.map(&format_filter/1)
      |> Enum.join(" AND ")
      parts = ["WHERE #{filter_str}" | parts]
    end
    
    # Add sorting
    if query.sort != [] do
      sort_str = query.sort
      |> Enum.map(&"#{&1.field} #{&1.direction}")
      |> Enum.join(", ")
      parts = parts ++ ["ORDER BY #{sort_str}"]
    end
    
    # Add pagination
    if query.pagination.page_size do
      parts = parts ++ ["LIMIT #{query.pagination.page_size}"]
    end
    
    if query.pagination.offset do
      parts = parts ++ ["OFFSET #{query.pagination.offset}"]
    end
    
    Enum.join(parts, " ")
  end

  # Private functions

  defp generate_id do
    "qry_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp apply_filters(query, nil), do: query
  defp apply_filters(query, filters) when is_list(filters) do
    Enum.reduce(filters, query, fn filter, acc ->
      where(acc, filter["field"], String.to_atom(filter["operator"]), filter["value"])
    end)
  end

  defp apply_sorting(query, nil), do: query
  defp apply_sorting(query, sort_fields) when is_list(sort_fields) do
    Enum.reduce(sort_fields, query, fn sort, acc ->
      direction = String.to_atom(sort["direction"] || "asc")
      order_by(acc, sort["field"], direction)
    end)
  end

  defp apply_pagination(query, nil), do: query
  defp apply_pagination(query, %{"page" => page, "page_size" => size}) do
    paginate(query, page, size)
  end
  defp apply_pagination(query, %{"cursor" => cursor}) do
    after_cursor(query, cursor)
  end
  defp apply_pagination(query, _), do: query

  defp apply_projections(query, nil), do: query
  defp apply_projections(query, %{"include" => fields}) when is_list(fields) do
    select(query, fields)
  end
  defp apply_projections(query, %{"exclude" => fields}) when is_list(fields) do
    exclude(query, fields)
  end
  defp apply_projections(query, _), do: query

  defp apply_options(query, nil), do: query
  defp apply_options(query, options) when is_map(options) do
    Enum.reduce(options, query, fn {key, value}, acc ->
      case key do
        "include_deleted" -> include_deleted(acc, value)
        "include_versions" -> include_versions(acc, value)
        "timeout" -> timeout(acc, value)
        "explain" -> explain(acc, value)
        _ -> acc
      end
    end)
  end

  defp compile_filters(filters) do
    # Group filters by combinator for efficient execution
    filters
    |> Enum.group_by(& &1.combinator)
    |> Map.new(fn {combinator, group} ->
      {combinator, Enum.map(group, &compile_filter/1)}
    end)
  end

  defp compile_filter(filter) do
    %{
      field_path: parse_field_path(filter.field),
      operator: filter.operator,
      value: filter.value,
      compiled: compile_operator(filter.operator, filter.value)
    }
  end

  defp parse_field_path(field) do
    String.split(field, ".")
  end

  defp compile_operator(:between, {start, end_val}) do
    fn value -> value >= start and value <= end_val end
  end
  defp compile_operator(:in, list) do
    set = MapSet.new(list)
    fn value -> MapSet.member?(set, value) end
  end
  defp compile_operator(:contains, substring) do
    fn value -> String.contains?(to_string(value), substring) end
  end
  defp compile_operator(op, expected) do
    fn value -> apply_operator(op, value, expected) end
  end

  defp apply_operator(:eq, a, b), do: a == b
  defp apply_operator(:neq, a, b), do: a != b
  defp apply_operator(:gt, a, b), do: a > b
  defp apply_operator(:gte, a, b), do: a >= b
  defp apply_operator(:lt, a, b), do: a < b
  defp apply_operator(:lte, a, b), do: a <= b
  defp apply_operator(:exists, value, _), do: value != nil
  defp apply_operator(:not_exists, value, _), do: value == nil
  defp apply_operator(:starts_with, str, prefix), do: String.starts_with?(to_string(str), prefix)
  defp apply_operator(:ends_with, str, suffix), do: String.ends_with?(to_string(str), suffix)
  defp apply_operator(:regex, str, pattern), do: Regex.match?(~r/#{pattern}/, to_string(str))
  defp apply_operator(_, _, _), do: false

  defp validate_filters(filters) do
    Enum.reduce_while(filters, :ok, fn filter, _acc ->
      if filter.operator in [:eq, :neq, :gt, :gte, :lt, :lte, :in, :nin, 
                            :contains, :not_contains, :starts_with, :ends_with,
                            :regex, :exists, :not_exists, :between] do
        {:cont, :ok}
      else
        {:halt, {:error, "Invalid operator: #{filter.operator}"}}
      end
    end)
  end

  defp validate_sort(sort_specs) do
    Enum.reduce_while(sort_specs, :ok, fn sort, _acc ->
      if sort.direction in [:asc, :desc] do
        {:cont, :ok}
      else
        {:halt, {:error, "Invalid sort direction: #{sort.direction}"}}
      end
    end)
  end

  defp validate_pagination(pagination) do
    cond do
      pagination.page < 1 -> {:error, "Page must be >= 1"}
      pagination.page_size < 1 -> {:error, "Page size must be >= 1"}
      pagination.page_size > @max_page_size -> {:error, "Page size exceeds maximum"}
      true -> :ok
    end
  end

  defp validate_aggregations(aggregations) do
    valid_types = [:count, :sum, :avg, :min, :max, :distinct, :group_by]
    
    Enum.reduce_while(aggregations, :ok, fn agg, _acc ->
      if agg.type in valid_types do
        {:cont, :ok}
      else
        {:halt, {:error, "Invalid aggregation type: #{agg.type}"}}
      end
    end)
  end

  defp format_filter(%{field: field, operator: op, value: value}) do
    "#{field} #{op} #{inspect(value)}"
  end
end