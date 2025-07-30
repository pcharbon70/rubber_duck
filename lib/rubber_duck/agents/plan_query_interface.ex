defmodule RubberDuck.Agents.PlanQueryInterface do
  @moduledoc """
  Advanced query interface for plans with filtering, aggregation, and caching.
  
  This module provides:
  - Flexible query building with multiple filter types
  - Aggregation and statistical analysis
  - Result pagination and sorting
  - Query result caching with TTL
  - Full-text search capabilities
  - Query optimization and indexing hints
  """
  
  require Logger
  # alias RubberDuck.Planning.{Plan, Phase} # Not used currently
  
  # Query operators - will be resolved at runtime
  @operators %{
    eq: :equals?,
    neq: :not_equals?,
    gt: :greater_than?,
    gte: :greater_than_or_equal?,
    lt: :less_than?,
    lte: :less_than_or_equal?,
    in: :in_list?,
    nin: :not_in_list?,
    contains: :contains?,
    regex: :matches_regex?,
    exists: :field_exists?,
    between: :between?
  }
  
  # Aggregation functions - will be resolved at runtime
  @aggregations %{
    count: :aggregate_count,
    sum: :aggregate_sum,
    avg: :aggregate_average,
    min: :aggregate_min,
    max: :aggregate_max,
    group_by: :aggregate_group_by,
    distinct: :aggregate_distinct
  }
  
  # Sort directions
  @sort_directions [:asc, :desc]
  
  @doc """
  Builds and executes a query with the given parameters.
  
  ## Options
  - `:filters` - Map of field filters
  - `:sort` - List of sort specifications
  - `:pagination` - Pagination options (page, limit)
  - `:include` - Fields to include in results
  - `:exclude` - Fields to exclude from results
  - `:aggregations` - Aggregation specifications
  - `:cache` - Cache options (ttl, key)
  """
  def query(opts \\ []) do
    query_spec = build_query_spec(opts)
    
    # Check cache first
    case check_cache(query_spec) do
      {:hit, cached_result} ->
        Logger.debug("Query cache hit for #{inspect(query_spec.cache_key)}")
        {:ok, cached_result}
        
      :miss ->
        # Execute query
        with {:ok, results} <- execute_query(query_spec),
             {:ok, processed} <- process_results(results, query_spec) do
          
          # Cache results if caching enabled
          maybe_cache_results(processed, query_spec)
          
          {:ok, processed}
        end
    end
  end
  
  @doc """
  Searches plans using full-text search.
  """
  def search(search_term, opts \\ []) do
    search_spec = %{
      term: search_term,
      fields: Keyword.get(opts, :fields, [:name, :description]),
      fuzzy: Keyword.get(opts, :fuzzy, true),
      boost: Keyword.get(opts, :boost, %{name: 2.0, description: 1.0})
    }
    
    with {:ok, plan_ids} <- perform_text_search(search_spec),
         {:ok, plans} <- fetch_plans_by_ids(plan_ids) do
      
      # Apply additional filters if provided
      filtered = apply_post_filters(plans, Keyword.get(opts, :filters, %{}))
      
      # Sort by relevance score
      sorted = sort_by_relevance(filtered, search_spec)
      
      {:ok, paginate_results(sorted, Keyword.get(opts, :pagination, %{}))}
    end
  end
  
  @doc """
  Aggregates plan data based on specifications.
  """
  def aggregate(aggregation_spec, opts \\ []) do
    with {:ok, data} <- fetch_aggregation_data(aggregation_spec, opts),
         {:ok, results} <- perform_aggregations(data, aggregation_spec) do
      
      {:ok, format_aggregation_results(results, aggregation_spec)}
    end
  end
  
  @doc """
  Gets query suggestions based on partial input.
  """
  def suggest(partial_query, opts \\ []) do
    max_suggestions = Keyword.get(opts, :limit, 10)
    
    suggestions = []
    |> add_field_suggestions(partial_query)
    |> add_value_suggestions(partial_query)
    |> add_saved_query_suggestions(partial_query)
    |> Enum.take(max_suggestions)
    
    {:ok, suggestions}
  end
  
  @doc """
  Saves a query for later reuse.
  """
  def save_query(name, query_spec, opts \\ []) do
    saved_query = %{
      id: generate_query_id(),
      name: name,
      description: Keyword.get(opts, :description),
      query_spec: query_spec,
      owner: Keyword.get(opts, :owner, "system"),
      created_at: DateTime.utc_now(),
      tags: Keyword.get(opts, :tags, []),
      is_public: Keyword.get(opts, :public, false)
    }
    
    store_saved_query(saved_query)
    
    {:ok, saved_query}
  end
  
  @doc """
  Loads and executes a saved query.
  """
  def execute_saved_query(query_name, override_opts \\ []) do
    with {:ok, saved_query} <- load_saved_query(query_name),
         merged_spec <- merge_query_specs(saved_query.query_spec, override_opts) do
      
      query(merged_spec)
    end
  end
  
  @doc """
  Analyzes query performance and provides optimization suggestions.
  """
  def analyze_query(query_spec) do
    analysis = %{
      estimated_cost: estimate_query_cost(query_spec),
      suggested_indexes: suggest_indexes(query_spec),
      optimization_hints: generate_optimization_hints(query_spec),
      warnings: detect_query_issues(query_spec)
    }
    
    {:ok, analysis}
  end
  
  ## Query Building
  
  defp build_query_spec(opts) do
    %{
      filters: build_filters(Keyword.get(opts, :filters, %{})),
      sort: build_sort_spec(Keyword.get(opts, :sort, [])),
      pagination: build_pagination_spec(Keyword.get(opts, :pagination, %{})),
      projection: build_projection_spec(opts),
      aggregations: Keyword.get(opts, :aggregations, []),
      cache_key: generate_cache_key(opts),
      cache_ttl: get_in(opts, [:cache, :ttl]) || :timer.minutes(5)
    }
  end
  
  defp build_filters(filter_map) do
    filter_map
    |> Enum.map(fn {field, spec} ->
      build_single_filter(field, spec)
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp build_single_filter(field, value) when not is_map(value) do
    %{field: field, operator: :eq, value: value}
  end
  
  defp build_single_filter(field, %{} = spec) do
    %{
      field: field,
      operator: Map.get(spec, :op, :eq),
      value: spec.value,
      options: Map.get(spec, :options, %{})
    }
  end
  
  defp build_sort_spec(sort_list) when is_list(sort_list) do
    Enum.map(sort_list, fn
      {field, direction} when direction in @sort_directions ->
        %{field: field, direction: direction}
      field when is_atom(field) ->
        %{field: field, direction: :asc}
    end)
  end
  
  defp build_pagination_spec(pagination) do
    %{
      page: Map.get(pagination, :page, 1),
      limit: Map.get(pagination, :limit, 20),
      offset: Map.get(pagination, :offset)
    }
  end
  
  defp build_projection_spec(opts) do
    %{
      include: Keyword.get(opts, :include, :all),
      exclude: Keyword.get(opts, :exclude, [])
    }
  end
  
  ## Query Execution
  
  defp execute_query(query_spec) do
    # In a real implementation, this would query the Plan Manager Agent
    # or directly query the database
    plans = [
      %{
        id: "plan_1",
        name: "Test Plan",
        description: "A test plan",
        state: :active,
        created_at: DateTime.utc_now(),
        owner_id: "user_123",
        metadata: %{tags: ["test", "demo"]}
      }
    ]
    
    filtered = apply_filters(plans, query_spec.filters)
    sorted = apply_sorting(filtered, query_spec.sort)
    
    {:ok, sorted}
  end
  
  defp apply_filters(items, filters) do
    Enum.filter(items, fn item ->
      Enum.all?(filters, fn filter ->
        apply_single_filter(item, filter)
      end)
    end)
  end
  
  defp apply_single_filter(item, %{field: field, operator: op, value: value}) do
    field_value = get_nested_field(item, field)
    operator_name = Map.get(@operators, op, :equals?)
    apply(__MODULE__, operator_name, [field_value, value])
  end
  
  defp apply_sorting(items, []), do: items
  defp apply_sorting(items, sort_specs) do
    Enum.sort_by(items, fn item ->
      Enum.map(sort_specs, fn %{field: field, direction: dir} ->
        value = get_nested_field(item, field)
        if dir == :desc, do: {:desc, value}, else: value
      end)
    end)
  end
  
  defp process_results(results, query_spec) do
    results
    |> apply_projection(query_spec.projection)
    |> apply_pagination(query_spec.pagination)
    |> wrap_with_metadata(query_spec)
  end
  
  defp apply_projection(results, %{include: :all, exclude: exclude}) do
    Enum.map(results, fn item ->
      Map.drop(item, exclude)
    end)
  end
  
  defp apply_projection(results, %{include: include, exclude: _}) when is_list(include) do
    Enum.map(results, fn item ->
      Map.take(item, include)
    end)
  end
  
  defp apply_pagination(results, %{offset: offset, limit: limit}) when not is_nil(offset) do
    results
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end
  
  defp apply_pagination(results, %{page: page, limit: limit}) do
    offset = (page - 1) * limit
    apply_pagination(results, %{offset: offset, limit: limit})
  end
  
  defp wrap_with_metadata(results, query_spec) do
    %{
      data: results,
      meta: %{
        total: length(results),
        page: query_spec.pagination.page,
        limit: query_spec.pagination.limit,
        query_time: 0, # Would measure actual query time
        cached: false
      }
    }
  end
  
  ## Text Search
  
  defp perform_text_search(_search_spec) do
    # Simplified text search - real implementation would use
    # full-text search capabilities
    {:ok, ["plan_1", "plan_2"]}
  end
  
  defp fetch_plans_by_ids(_plan_ids) do
    # Fetch plans by IDs
    {:ok, []}
  end
  
  defp apply_post_filters(plans, filters) do
    apply_filters(plans, build_filters(filters))
  end
  
  defp sort_by_relevance(plans, _search_spec) do
    # Sort by relevance score
    plans
  end
  
  ## Aggregations
  
  defp fetch_aggregation_data(_aggregation_spec, _opts) do
    # Fetch data needed for aggregation
    {:ok, []}
  end
  
  defp perform_aggregations(data, aggregation_spec) do
    results = Enum.map(aggregation_spec, fn {agg_name, agg_config} ->
      agg_fn_name = Map.get(@aggregations, agg_config.function, :aggregate_count)
      result = apply(__MODULE__, agg_fn_name, [data, agg_config])
      {agg_name, result}
    end)
    
    {:ok, Enum.into(results, %{})}
  end
  
  defp format_aggregation_results(results, _aggregation_spec) do
    results
  end
  
  ## Caching
  
  defp check_cache(query_spec) do
    case Process.get({:query_cache, query_spec.cache_key}) do
      nil -> :miss
      {cached_result, expires_at} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:hit, cached_result}
        else
          Process.delete({:query_cache, query_spec.cache_key})
          :miss
        end
    end
  end
  
  defp maybe_cache_results(results, query_spec) do
    if query_spec.cache_ttl > 0 do
      expires_at = DateTime.add(DateTime.utc_now(), query_spec.cache_ttl, :millisecond)
      Process.put({:query_cache, query_spec.cache_key}, {results, expires_at})
    end
  end
  
  defp generate_cache_key(opts) do
    :crypto.hash(:sha256, :erlang.term_to_binary(opts))
    |> Base.encode16()
  end
  
  ## Query Suggestions
  
  defp add_field_suggestions(suggestions, partial) do
    fields = [:name, :description, :state, :owner_id, :created_at]
    
    matching_fields = Enum.filter(fields, fn field ->
      String.starts_with?(to_string(field), partial)
    end)
    
    field_suggestions = Enum.map(matching_fields, fn field ->
      %{
        type: :field,
        value: field,
        display: "Filter by #{field}",
        score: 0.8
      }
    end)
    
    suggestions ++ field_suggestions
  end
  
  defp add_value_suggestions(suggestions, _partial) do
    # Add value suggestions based on field context
    suggestions
  end
  
  defp add_saved_query_suggestions(suggestions, _partial) do
    # Add saved query suggestions
    suggestions
  end
  
  ## Saved Queries
  
  defp generate_query_id do
    "query_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
  
  defp store_saved_query(saved_query) do
    # Store in persistence layer
    {:ok, saved_query}
  end
  
  defp load_saved_query(_query_name) do
    # Load from persistence layer
    {:error, :not_found}
  end
  
  defp merge_query_specs(base_spec, overrides) do
    Map.merge(base_spec, Enum.into(overrides, %{}))
  end
  
  ## Query Analysis
  
  defp estimate_query_cost(query_spec) do
    base_cost = 1.0
    filter_cost = length(query_spec.filters) * 0.2
    sort_cost = length(query_spec.sort) * 0.5
    
    base_cost + filter_cost + sort_cost
  end
  
  defp suggest_indexes(query_spec) do
    filter_fields = Enum.map(query_spec.filters, & &1.field)
    sort_fields = Enum.map(query_spec.sort, & &1.field)
    
    (filter_fields ++ sort_fields)
    |> Enum.uniq()
    |> Enum.map(&{:index, &1})
  end
  
  defp generate_optimization_hints(query_spec) do
    hints = []
    
    # Check for expensive operations
    if length(query_spec.filters) > 5 do
      hints ++ ["Consider creating a composite index for multiple filters"]
    else
      hints
    end
  end
  
  defp detect_query_issues(query_spec) do
    warnings = []
    
    # Check for missing pagination
    if query_spec.pagination.limit > 100 do
      warnings ++ ["Large result set without proper pagination"]
    else
      warnings
    end
  end
  
  ## Helper Functions
  
  defp get_nested_field(item, field) when is_atom(field) do
    Map.get(item, field)
  end
  
  defp get_nested_field(item, field) when is_list(field) do
    get_in(item, field)
  end
  
  defp paginate_results(results, pagination) do
    apply_pagination(results, build_pagination_spec(pagination))
  end
  
  ## Operator Functions
  
  def equals?(a, b), do: a == b
  def not_equals?(a, b), do: a != b
  def greater_than?(a, b), do: a > b
  def greater_than_or_equal?(a, b), do: a >= b
  def less_than?(a, b), do: a < b
  def less_than_or_equal?(a, b), do: a <= b
  def in_list?(a, b) when is_list(b), do: a in b
  def not_in_list?(a, b) when is_list(b), do: a not in b
  def contains?(a, b) when is_binary(a), do: String.contains?(a, b)
  def contains?(a, b) when is_list(a), do: b in a
  def matches_regex?(a, b) when is_binary(a) and is_binary(b) do
    case Regex.compile(b) do
      {:ok, regex} -> Regex.match?(regex, a)
      _ -> false
    end
  end
  def field_exists?(a, _), do: not is_nil(a)
  def between?(a, {min, max}), do: a >= min and a <= max
  
  ## Aggregation Functions
  
  def aggregate_count(data, _config), do: length(data)
  def aggregate_sum(data, config) do
    field = config.field
    Enum.reduce(data, 0, fn item, acc ->
      acc + (get_nested_field(item, field) || 0)
    end)
  end
  def aggregate_average(data, config) do
    sum = aggregate_sum(data, config)
    count = aggregate_count(data, config)
    if count > 0, do: sum / count, else: 0
  end
  def aggregate_min(data, config) do
    field = config.field
    data
    |> Enum.map(&get_nested_field(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end
  def aggregate_max(data, config) do
    field = config.field
    data
    |> Enum.map(&get_nested_field(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end
  def aggregate_group_by(data, config) do
    field = config.field
    Enum.group_by(data, &get_nested_field(&1, field))
  end
  def aggregate_distinct(data, config) do
    field = config.field
    data
    |> Enum.map(&get_nested_field(&1, field))
    |> Enum.uniq()
  end
end