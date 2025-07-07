defimpl RubberDuck.Enhancer, for: List do
  @moduledoc """
  Enhancer implementation for List data type.

  Provides enhancement capabilities for list structures including:
  - Pattern detection in sequences
  - Statistical analysis
  - Grouping and categorization
  - Trend identification
  """

  @doc """
  Enhance the list using the specified strategy.

  ## Strategies

  - `:semantic` - Group and categorize list elements
  - `:structural` - Analyze list structure and patterns
  - `:temporal` - Detect time-based patterns if applicable
  - `:relational` - Find relationships between elements
  - `{:custom, opts}` - Custom enhancement with options
  """
  def enhance(list, strategy) do
    enhanced =
      case strategy do
        :semantic -> enhance_semantic(list)
        :structural -> enhance_structural(list)
        :temporal -> enhance_temporal(list)
        :relational -> enhance_relational(list)
        {:custom, opts} -> enhance_custom(list, opts)
        _ -> {:error, :unknown_strategy}
      end

    case enhanced do
      {:error, _} = error -> error
      result -> {:ok, result}
    end
  end

  @doc """
  Add contextual information to the list.
  """
  def with_context(list, context) do
    %{
      data: list,
      context: context,
      enhanced_at: DateTime.utc_now()
    }
  end

  @doc """
  Enrich list with metadata.
  """
  def with_metadata(list, metadata) do
    %{
      data: list,
      metadata: Map.merge(extract_base_metadata(list), metadata)
    }
  end

  @doc """
  Derive new information from the list data.
  """
  def derive(list, derivations) when is_list(derivations) do
    results =
      Enum.reduce(derivations, %{}, fn derivation, acc ->
        case derive_single(list, derivation) do
          {:ok, key, value} -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    {:ok, results}
  end

  def derive(list, derivation) do
    case derive_single(list, derivation) do
      {:ok, key, value} -> {:ok, %{key => value}}
      error -> error
    end
  end

  # Private functions

  defp enhance_semantic(list) do
    %{
      data: list,
      semantic: %{
        categories: categorize_elements(list),
        groups: group_similar_elements(list),
        classifications: classify_elements(list),
        dominant_types: find_dominant_types(list),
        outliers: detect_outliers(list)
      }
    }
  end

  defp enhance_structural(list) do
    %{
      data: list,
      structure: %{
        length: length(list),
        depth: calculate_depth(list),
        patterns: detect_patterns(list),
        sequences: find_sequences(list),
        distribution: analyze_distribution(list),
        balance: calculate_balance(list)
      }
    }
  end

  defp enhance_temporal(list) do
    # Attempt to extract temporal information if elements contain time data
    temporal_elements = extract_temporal_elements(list)

    %{
      data: list,
      temporal: %{
        time_series: build_time_series(temporal_elements),
        trends: detect_trends(temporal_elements),
        periodicity: detect_periodicity(temporal_elements),
        enhanced_at: DateTime.utc_now()
      }
    }
  end

  defp enhance_relational(list) do
    %{
      data: list,
      relational: %{
        correlations: find_correlations(list),
        dependencies: detect_dependencies(list),
        clusters: find_clusters(list),
        similarity_matrix: build_similarity_matrix(list)
      }
    }
  end

  defp enhance_custom(list, opts) do
    case Keyword.get(opts, :enhancer) do
      nil -> list
      func when is_function(func, 1) -> func.(list)
      _ -> list
    end
  end

  defp derive_single(list, :summary) do
    summary = %{
      total_elements: length(list),
      unique_elements: length(Enum.uniq(list)),
      type_distribution: get_type_distribution(list),
      empty_elements: count_empty_elements(list),
      nested_lists: count_nested_lists(list)
    }

    {:ok, :summary, summary}
  end

  defp derive_single(list, :statistics) do
    stats = calculate_statistics(list)
    {:ok, :statistics, stats}
  end

  defp derive_single(list, :relationships) do
    rels = %{
      sequences: find_sequences(list),
      patterns: detect_patterns(list),
      groupings: natural_groupings(list)
    }

    {:ok, :relationships, rels}
  end

  defp derive_single(list, :patterns) do
    patterns = %{
      repetitions: find_repetitions(list),
      cycles: detect_cycles(list),
      progressions: find_progressions(list),
      symmetries: detect_symmetries(list)
    }

    {:ok, :patterns, patterns}
  end

  defp derive_single(list, {:custom, opts}) do
    case Keyword.get(opts, :derive_fn) do
      nil ->
        {:error, :no_derive_function}

      func when is_function(func, 1) ->
        result = func.(list)
        {:ok, Keyword.get(opts, :key, :custom), result}
    end
  end

  defp derive_single(_list, _unknown) do
    {:error, :unknown_derivation}
  end

  # Helper functions

  defp extract_base_metadata(list) do
    %{
      type: :list,
      length: length(list),
      empty: Enum.empty?(list),
      homogeneous: is_homogeneous?(list),
      timestamp: DateTime.utc_now()
    }
  end

  defp categorize_elements(list) do
    Enum.reduce(list, %{}, fn element, acc ->
      category = categorize_single(element)
      Map.update(acc, category, [element], &[element | &1])
    end)
  end

  defp categorize_single(element) do
    cond do
      is_nil(element) -> nil
      is_number(element) -> categorize_number(element)
      is_binary(element) -> categorize_string(element)
      is_map(element) -> :map
      is_list(element) -> :list
      is_atom(element) -> :atom
      is_boolean(element) -> :boolean
      true -> :other
    end
  end

  defp categorize_number(n) do
    cond do
      is_integer(n) and n > 0 -> :positive_integer
      is_integer(n) and n < 0 -> :negative_integer
      is_integer(n) -> :zero
      is_float(n) and n > 0 -> :positive_float
      is_float(n) and n < 0 -> :negative_float
      true -> :number
    end
  end

  defp categorize_string(s) do
    cond do
      String.match?(s, ~r/^\d+$/) -> :numeric_string
      String.match?(s, ~r/^[A-Z]+$/) -> :uppercase_string
      String.match?(s, ~r/^[a-z]+$/) -> :lowercase_string
      String.match?(s, ~r/^[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}$/) -> :email
      String.match?(s, ~r/^https?:\/\//) -> :url
      String.length(s) == 0 -> :empty_string
      true -> :string
    end
  end

  defp group_similar_elements(list) do
    # Group elements by similarity
    indexed_list = Enum.with_index(list)

    groups =
      Enum.reduce(indexed_list, [], fn {element, index}, groups ->
        case find_similar_group(element, groups) do
          nil ->
            [[{element, index}] | groups]

          group_index ->
            List.update_at(groups, group_index, &[{element, index} | &1])
        end
      end)

    # Convert back to just elements and indices
    Enum.map(groups, fn group ->
      %{
        elements: Enum.map(group, fn {elem, _} -> elem end),
        indices: Enum.map(group, fn {_, idx} -> idx end)
      }
    end)
  end

  defp find_similar_group(element, groups) do
    Enum.find_index(groups, fn group ->
      {sample, _} = List.first(group)
      similar?(element, sample)
    end)
  end

  defp similar?(a, b) when is_number(a) and is_number(b) do
    # Numbers within 10% are similar
    abs(a - b) / max(abs(a), abs(b)) < 0.1
  end

  defp similar?(a, b) when is_binary(a) and is_binary(b) do
    # Strings with same length or same prefix are similar
    String.length(a) == String.length(b) or
      String.starts_with?(a, b) or
      String.starts_with?(b, a)
  end

  defp similar?(a, b) do
    # For other types, check type equality
    type_of(a) == type_of(b)
  end

  defp classify_elements(list) do
    numeric_elements = Enum.filter(list, &is_number/1)

    %{
      numeric_classification: classify_numeric_distribution(numeric_elements),
      size_classification: classify_by_size(list),
      complexity_classification: classify_by_complexity(list)
    }
  end

  defp classify_numeric_distribution([]), do: :no_numbers

  defp classify_numeric_distribution(numbers) do
    sorted = Enum.sort(numbers)
    min = List.first(sorted)
    max = List.last(sorted)
    range = max - min

    cond do
      range == 0 -> :constant
      is_arithmetic_sequence?(sorted) -> :arithmetic_sequence
      is_geometric_sequence?(sorted) -> :geometric_sequence
      is_fibonacci_like?(sorted) -> :fibonacci_like
      true -> :irregular
    end
  end

  defp is_arithmetic_sequence?([_]), do: true

  defp is_arithmetic_sequence?([a, b | rest]) do
    diff = b - a
    is_arithmetic_with_diff?([b | rest], diff)
  end

  defp is_arithmetic_with_diff?([_], _diff), do: true

  defp is_arithmetic_with_diff?([a, b | rest], diff) do
    b - a == diff and is_arithmetic_with_diff?([b | rest], diff)
  end

  defp is_geometric_sequence?([_]), do: true

  defp is_geometric_sequence?([a, b | rest]) when a != 0 do
    ratio = b / a
    is_geometric_with_ratio?([b | rest], ratio)
  end

  defp is_geometric_sequence?(_), do: false

  defp is_geometric_with_ratio?([_], _ratio), do: true

  defp is_geometric_with_ratio?([a, b | rest], ratio) when a != 0 do
    abs(b / a - ratio) < 0.0001 and is_geometric_with_ratio?([b | rest], ratio)
  end

  defp is_geometric_with_ratio?(_, _), do: false

  defp is_fibonacci_like?([_]), do: false
  defp is_fibonacci_like?([_, _]), do: false

  defp is_fibonacci_like?([a, b, c | rest]) do
    a + b == c and is_fibonacci_like?([b, c | rest])
  end

  defp classify_by_size(list) do
    size = length(list)

    cond do
      size == 0 -> :empty
      size == 1 -> :singleton
      size < 10 -> :small
      size < 100 -> :medium
      size < 1000 -> :large
      true -> :very_large
    end
  end

  defp classify_by_complexity(list) do
    nested_count = Enum.count(list, &(is_list(&1) or is_map(&1)))
    total = length(list)

    cond do
      total == 0 -> :empty
      nested_count == 0 -> :flat
      nested_count < total / 2 -> :partially_nested
      true -> :highly_nested
    end
  end

  defp find_dominant_types(list) do
    list
    |> Enum.map(&type_of/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_type, count} -> -count end)
    |> Enum.take(3)
  end

  defp detect_outliers(list) do
    numeric_elements = Enum.filter(list, &is_number/1)

    if length(numeric_elements) > 3 do
      mean = Enum.sum(numeric_elements) / length(numeric_elements)
      std_dev = calculate_std_dev(numeric_elements, mean)

      # Elements more than 2 standard deviations from mean
      outliers =
        Enum.filter(numeric_elements, fn x ->
          abs(x - mean) > 2 * std_dev
        end)

      %{
        outliers: outliers,
        outlier_indices: find_indices(list, outliers)
      }
    else
      %{outliers: [], outlier_indices: []}
    end
  end

  defp calculate_std_dev(numbers, mean) do
    variance = Enum.sum(Enum.map(numbers, fn x -> :math.pow(x - mean, 2) end)) / length(numbers)
    :math.sqrt(variance)
  end

  defp find_indices(list, elements) do
    indexed = Enum.with_index(list)

    Enum.flat_map(elements, fn elem ->
      indexed
      |> Enum.filter(fn {x, _} -> x == elem end)
      |> Enum.map(fn {_, idx} -> idx end)
    end)
  end

  defp calculate_depth(list, current_depth \\ 1) do
    nested_depths =
      list
      |> Enum.filter(&is_list/1)
      |> Enum.map(&calculate_depth(&1, current_depth + 1))

    case nested_depths do
      [] -> current_depth
      depths -> Enum.max(depths)
    end
  end

  defp detect_patterns(list) do
    %{
      repeating_patterns: find_repeating_patterns(list),
      alternating_patterns: find_alternating_patterns(list),
      increasing_patterns: find_increasing_patterns(list),
      symmetric_patterns: find_symmetric_patterns(list)
    }
  end

  defp find_repeating_patterns(list) do
    # Look for patterns of length 2-5 that repeat
    pattern_lengths = 2..min(5, div(length(list), 2))

    patterns =
      Enum.flat_map(pattern_lengths, fn len ->
        find_patterns_of_length(list, len)
      end)

    Enum.uniq(patterns)
  end

  defp find_patterns_of_length(list, pattern_length) do
    chunks = Enum.chunk_every(list, pattern_length, 1, :discard)

    chunks
    |> Enum.frequencies()
    |> Enum.filter(fn {_pattern, count} -> count > 1 end)
    |> Enum.map(fn {pattern, count} -> %{pattern: pattern, count: count, length: pattern_length} end)
  end

  defp find_alternating_patterns(list) do
    case list do
      [] ->
        []

      [_] ->
        []

      [a, b | rest] ->
        if check_alternating([a, b | rest], a, b) do
          [%{type: :alternating, elements: [a, b]}]
        else
          []
        end
    end
  end

  defp check_alternating([], _a, _b), do: true
  defp check_alternating([x], a, _b), do: x == a

  defp check_alternating([x, y | rest], a, b) do
    x == a and y == b and check_alternating(rest, a, b)
  end

  defp find_increasing_patterns(list) do
    numeric_only = Enum.filter(list, &is_number/1)

    if length(numeric_only) > 1 do
      consecutive_increases =
        numeric_only
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b > a end)
        |> Enum.chunk_by(& &1)
        |> Enum.filter(fn chunk -> List.first(chunk) == true end)
        |> Enum.map(&length/1)

      %{
        has_increasing_subsequences: not Enum.empty?(consecutive_increases),
        longest_increase: if(Enum.empty?(consecutive_increases), do: 0, else: Enum.max(consecutive_increases))
      }
    else
      %{has_increasing_subsequences: false, longest_increase: 0}
    end
  end

  defp find_symmetric_patterns(list) do
    len = length(list)

    symmetries =
      for i <- 0..div(len, 2) do
        left = Enum.slice(list, 0, i)
        right = Enum.slice(list, len - i, i)

        if left == Enum.reverse(right) and i > 0 do
          %{type: :symmetric, position: i, elements: left}
        end
      end

    Enum.filter(symmetries, & &1)
  end

  defp find_sequences(list) do
    indexed = Enum.with_index(list)

    # Group consecutive elements of the same type
    sequences = Enum.chunk_by(indexed, fn {elem, _} -> type_of(elem) end)

    Enum.map(sequences, fn seq ->
      elements = Enum.map(seq, fn {elem, _} -> elem end)
      indices = Enum.map(seq, fn {_, idx} -> idx end)

      %{
        type: type_of(List.first(elements)),
        elements: elements,
        start_index: List.first(indices),
        length: length(elements)
      }
    end)
  end

  defp analyze_distribution(list) do
    frequencies = Enum.frequencies(list)
    total = length(list)

    distribution =
      Enum.map(frequencies, fn {elem, count} ->
        %{
          element: elem,
          count: count,
          percentage: count / total * 100
        }
      end)

    %{
      unique_elements: map_size(frequencies),
      most_common: Enum.max_by(distribution, & &1.count, fn -> nil end),
      distribution: Enum.sort_by(distribution, &(-&1.count))
    }
  end

  defp calculate_balance(list) do
    # Calculate how evenly distributed the elements are
    frequencies = Enum.frequencies(list)

    if map_size(frequencies) > 0 do
      counts = Map.values(frequencies)
      mean = Enum.sum(counts) / length(counts)
      variance = Enum.sum(Enum.map(counts, fn c -> :math.pow(c - mean, 2) end)) / length(counts)

      %{
        balance_score: 1 / (1 + variance),
        perfectly_balanced: variance == 0
      }
    else
      %{balance_score: 0, perfectly_balanced: true}
    end
  end

  defp extract_temporal_elements(list) do
    # Try to extract DateTime or date-like elements
    list
    |> Enum.filter(fn elem ->
      case elem do
        %DateTime{} -> true
        s when is_binary(s) -> String.match?(s, ~r/\d{4}-\d{2}-\d{2}/)
        _ -> false
      end
    end)
    |> Enum.map(fn elem ->
      case elem do
        %DateTime{} = dt -> dt
        s when is_binary(s) -> parse_date_string(s)
      end
    end)
  end

  defp parse_date_string(s) do
    # Simple date parsing - in real system use proper date parsing
    case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, s) do
      [_, y, m, d] ->
        {:ok, dt} =
          DateTime.new(Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d)), ~T[00:00:00])

        dt

      _ ->
        nil
    end
  end

  defp build_time_series(temporal_elements) do
    if length(temporal_elements) > 0 do
      sorted = Enum.sort(temporal_elements, DateTime)

      %{
        start: List.first(sorted),
        end: List.last(sorted),
        duration: DateTime.diff(List.last(sorted), List.first(sorted)),
        points: length(sorted)
      }
    else
      nil
    end
  end

  defp detect_trends(temporal_elements) do
    # Simple trend detection based on intervals
    if length(temporal_elements) > 2 do
      intervals =
        temporal_elements
        |> Enum.sort(DateTime)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> DateTime.diff(b, a) end)

      %{
        regular_intervals: regular_intervals?(intervals),
        average_interval: Enum.sum(intervals) / length(intervals),
        trend: classify_trend(intervals)
      }
    else
      nil
    end
  end

  defp regular_intervals?([]), do: true

  defp regular_intervals?(intervals) do
    mean = Enum.sum(intervals) / length(intervals)
    variance = Enum.sum(Enum.map(intervals, fn i -> :math.pow(i - mean, 2) end)) / length(intervals)

    # Consider regular if variance is less than 10% of mean
    variance < mean * 0.1
  end

  defp classify_trend(intervals) do
    cond do
      Enum.all?(intervals, fn i -> i > 0 end) and increasing_trend?(intervals) -> :accelerating
      Enum.all?(intervals, fn i -> i > 0 end) and decreasing_trend?(intervals) -> :decelerating
      regular_intervals?(intervals) -> :steady
      true -> :irregular
    end
  end

  defp increasing_trend?(intervals) do
    intervals
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> b >= a end)
  end

  defp decreasing_trend?(intervals) do
    intervals
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> b <= a end)
  end

  defp detect_periodicity(_temporal_elements) do
    # Simplified periodicity detection
    # In a real system, would use FFT or autocorrelation
    %{periodic: false, period: nil}
  end

  defp find_correlations(list) do
    # Find correlations between numeric elements at different positions
    numeric_indices =
      list
      |> Enum.with_index()
      |> Enum.filter(fn {elem, _} -> is_number(elem) end)

    if length(numeric_indices) > 3 do
      # Simple correlation: check if elements at distance d are related
      distances = [1, 2, 3]

      correlations =
        Enum.map(distances, fn d ->
          pairs =
            Enum.chunk_every(numeric_indices, 2, d, :discard)
            |> Enum.filter(fn chunk -> length(chunk) == 2 end)

          if length(pairs) > 0 do
            correlation = calculate_correlation(pairs)
            %{distance: d, correlation: correlation}
          end
        end)

      Enum.filter(correlations, & &1)
    else
      []
    end
  end

  defp calculate_correlation(pairs) do
    # Simple correlation coefficient
    {xs, ys} = Enum.unzip(Enum.map(pairs, fn [{x, _}, {y, _}] -> {x, y} end))

    mean_x = Enum.sum(xs) / length(xs)
    mean_y = Enum.sum(ys) / length(ys)

    covariance =
      Enum.zip(xs, ys)
      |> Enum.map(fn {x, y} -> (x - mean_x) * (y - mean_y) end)
      |> Enum.sum()
      |> Kernel./(length(xs))

    std_x = calculate_std_dev(xs, mean_x)
    std_y = calculate_std_dev(ys, mean_y)

    if std_x > 0 and std_y > 0 do
      covariance / (std_x * std_y)
    else
      0
    end
  end

  defp detect_dependencies(list) do
    # Detect if later elements depend on earlier ones
    indexed = Enum.with_index(list)

    dependencies =
      for {elem1, i1} <- indexed,
          {elem2, i2} <- indexed,
          i2 > i1,
          depends_on?(elem2, elem1) do
        %{from: i1, to: i2, type: dependency_type(elem1, elem2)}
      end

    dependencies
  end

  defp depends_on?(elem2, elem1) do
    cond do
      is_number(elem1) and is_number(elem2) ->
        # Check if elem2 is a function of elem1
        elem2 == elem1 * 2 or elem2 == elem1 + 1 or elem2 == elem1 * elem1

      is_binary(elem1) and is_binary(elem2) ->
        # Check if elem2 contains elem1
        String.contains?(elem2, elem1)

      true ->
        false
    end
  end

  defp dependency_type(elem1, elem2) do
    cond do
      is_number(elem1) and is_number(elem2) and elem2 == elem1 * 2 -> :double
      is_number(elem1) and is_number(elem2) and elem2 == elem1 + 1 -> :increment
      is_number(elem1) and is_number(elem2) and elem2 == elem1 * elem1 -> :square
      is_binary(elem1) and is_binary(elem2) -> :contains
      true -> :unknown
    end
  end

  defp find_clusters(list) do
    # Simple clustering based on similarity
    if length(list) > 0 do
      # Start with each element in its own cluster
      clusters = Enum.map(list, fn elem -> [elem] end)

      # Merge similar clusters
      merged_clusters = merge_similar_clusters(clusters, [])

      Enum.map(merged_clusters, fn cluster ->
        %{
          elements: cluster,
          size: length(cluster),
          representative: find_representative(cluster)
        }
      end)
    else
      []
    end
  end

  defp merge_similar_clusters([], acc), do: acc

  defp merge_similar_clusters([cluster | rest], acc) do
    {merged, remaining} =
      Enum.split_with(rest, fn other ->
        clusters_similar?(cluster, other)
      end)

    new_cluster = [cluster | merged] |> List.flatten()
    merge_similar_clusters(remaining, [new_cluster | acc])
  end

  defp clusters_similar?(cluster1, cluster2) do
    # Check if any elements are similar across clusters
    Enum.any?(cluster1, fn elem1 ->
      Enum.any?(cluster2, fn elem2 ->
        similar?(elem1, elem2)
      end)
    end)
  end

  defp find_representative(cluster) do
    # Find the most "central" element
    frequencies = Enum.frequencies(cluster)

    case Enum.max_by(frequencies, fn {_elem, count} -> count end, fn -> nil end) do
      {elem, _} -> elem
      nil -> List.first(cluster)
    end
  end

  defp build_similarity_matrix(list) do
    # Build a matrix showing similarity between all pairs
    indexed = Enum.with_index(list)

    matrix =
      for {elem1, i1} <- indexed do
        row =
          for {elem2, i2} <- indexed do
            if i1 == i2 do
              1.0
            else
              calculate_similarity(elem1, elem2)
            end
          end

        row
      end

    %{
      matrix: matrix,
      size: length(list),
      symmetric: true
    }
  end

  defp calculate_similarity(a, b) do
    cond do
      a == b -> 1.0
      similar?(a, b) -> 0.7
      type_of(a) == type_of(b) -> 0.3
      true -> 0.0
    end
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

  defp get_type_distribution(list) do
    list
    |> Enum.map(&type_of/1)
    |> Enum.frequencies()
  end

  defp count_empty_elements(list) do
    Enum.count(list, fn elem ->
      case elem do
        nil -> true
        "" -> true
        [] -> true
        %{} = map when map_size(map) == 0 -> true
        _ -> false
      end
    end)
  end

  defp count_nested_lists(list) do
    Enum.count(list, &is_list/1)
  end

  defp calculate_statistics(list) do
    numeric_values = Enum.filter(list, &is_number/1)

    if Enum.empty?(numeric_values) do
      %{numeric_elements: 0}
    else
      sorted = Enum.sort(numeric_values)
      len = length(sorted)
      sum = Enum.sum(sorted)
      mean = sum / len

      %{
        numeric_elements: len,
        sum: sum,
        mean: mean,
        median: calculate_median(sorted),
        mode: calculate_mode(numeric_values),
        min: List.first(sorted),
        max: List.last(sorted),
        range: List.last(sorted) - List.first(sorted),
        std_dev: calculate_std_dev(numeric_values, mean),
        percentiles: calculate_percentiles(sorted)
      }
    end
  end

  defp calculate_median(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
    else
      Enum.at(sorted_list, mid)
    end
  end

  defp calculate_mode(values) do
    frequencies = Enum.frequencies(values)

    if map_size(frequencies) > 0 do
      {mode, _count} = Enum.max_by(frequencies, fn {_val, count} -> count end)
      mode
    else
      nil
    end
  end

  defp calculate_percentiles(sorted_list) do
    len = length(sorted_list)

    %{
      p25: percentile_at(sorted_list, 0.25, len),
      p50: percentile_at(sorted_list, 0.50, len),
      p75: percentile_at(sorted_list, 0.75, len),
      p90: percentile_at(sorted_list, 0.90, len),
      p95: percentile_at(sorted_list, 0.95, len),
      p99: percentile_at(sorted_list, 0.99, len)
    }
  end

  defp percentile_at(sorted_list, percentile, len) do
    index = round(percentile * (len - 1))
    Enum.at(sorted_list, index)
  end

  defp natural_groupings(list) do
    # Find natural groupings based on gaps or changes
    indexed = Enum.with_index(list)

    groups =
      Enum.chunk_by(indexed, fn {elem, _idx} ->
        # Group by type and approximate value
        {type_of(elem), group_key(elem)}
      end)

    Enum.map(groups, fn group ->
      elements = Enum.map(group, fn {elem, _} -> elem end)
      indices = Enum.map(group, fn {_, idx} -> idx end)

      %{
        elements: elements,
        indices: indices,
        start: List.first(indices),
        end: List.last(indices),
        size: length(elements)
      }
    end)
  end

  defp group_key(elem) do
    cond do
      # Group numbers by tens
      is_number(elem) -> round(elem / 10) * 10
      # Group strings by first letter
      is_binary(elem) -> String.first(elem)
      true -> :other
    end
  end

  defp find_repetitions(list) do
    # Find elements that repeat
    frequencies = Enum.frequencies(list)

    repetitions =
      frequencies
      |> Enum.filter(fn {_elem, count} -> count > 1 end)
      |> Enum.map(fn {elem, count} ->
        %{
          element: elem,
          count: count,
          positions: find_all_positions(list, elem)
        }
      end)
      |> Enum.sort_by(&(-&1.count))

    repetitions
  end

  defp find_all_positions(list, target) do
    list
    |> Enum.with_index()
    |> Enum.filter(fn {elem, _} -> elem == target end)
    |> Enum.map(fn {_, idx} -> idx end)
  end

  defp detect_cycles(list) do
    # Detect if the list contains repeating cycles
    max_cycle_len = min(div(length(list), 2), 10)

    cycles =
      for len <- 2..max_cycle_len do
        if is_cyclic_with_period?(list, len) do
          %{period: len, cycle: Enum.take(list, len)}
        end
      end

    Enum.filter(cycles, & &1)
  end

  defp is_cyclic_with_period?(list, period) do
    chunks = Enum.chunk_every(list, period)

    case chunks do
      [] ->
        false

      [_] ->
        false

      [first | rest] ->
        Enum.all?(rest, fn chunk ->
          length(chunk) == period and chunk == first
        end)
    end
  end

  defp find_progressions(list) do
    numeric_values =
      list
      |> Enum.with_index()
      |> Enum.filter(fn {elem, _} -> is_number(elem) end)

    if length(numeric_values) >= 3 do
      # Check for arithmetic progressions
      arithmetic = find_arithmetic_progressions(numeric_values)

      # Check for geometric progressions
      geometric = find_geometric_progressions(numeric_values)

      %{
        arithmetic: arithmetic,
        geometric: geometric
      }
    else
      %{arithmetic: [], geometric: []}
    end
  end

  defp find_arithmetic_progressions(indexed_values) do
    # Find subsequences that form arithmetic progressions
    progressions =
      for start <- 0..(length(indexed_values) - 3) do
        find_longest_arithmetic_from(indexed_values, start)
      end

    progressions
    |> Enum.filter(& &1)
    |> Enum.uniq_by(& &1.indices)
  end

  defp find_longest_arithmetic_from(indexed_values, start) do
    {first_val, first_idx} = Enum.at(indexed_values, start)
    {second_val, second_idx} = Enum.at(indexed_values, start + 1)

    diff = second_val - first_val
    current = [{first_val, first_idx}, {second_val, second_idx}]

    rest = Enum.drop(indexed_values, start + 2)

    final =
      Enum.reduce_while(rest, current, fn {val, idx}, acc ->
        {last_val, _} = List.last(acc)

        if val - last_val == diff do
          {:cont, acc ++ [{val, idx}]}
        else
          {:halt, acc}
        end
      end)

    if length(final) >= 3 do
      %{
        type: :arithmetic,
        difference: diff,
        length: length(final),
        values: Enum.map(final, fn {v, _} -> v end),
        indices: Enum.map(final, fn {_, i} -> i end)
      }
    else
      nil
    end
  end

  defp find_geometric_progressions(indexed_values) do
    # Similar to arithmetic but with ratios
    progressions =
      for start <- 0..(length(indexed_values) - 3) do
        find_longest_geometric_from(indexed_values, start)
      end

    progressions
    |> Enum.filter(& &1)
    |> Enum.uniq_by(& &1.indices)
  end

  defp find_longest_geometric_from(indexed_values, start) do
    {first_val, first_idx} = Enum.at(indexed_values, start)
    {second_val, second_idx} = Enum.at(indexed_values, start + 1)

    if first_val != 0 do
      ratio = second_val / first_val
      current = [{first_val, first_idx}, {second_val, second_idx}]

      rest = Enum.drop(indexed_values, start + 2)

      final =
        Enum.reduce_while(rest, current, fn {val, idx}, acc ->
          {last_val, _} = List.last(acc)

          if last_val != 0 and abs(val / last_val - ratio) < 0.0001 do
            {:cont, acc ++ [{val, idx}]}
          else
            {:halt, acc}
          end
        end)

      if length(final) >= 3 do
        %{
          type: :geometric,
          ratio: ratio,
          length: length(final),
          values: Enum.map(final, fn {v, _} -> v end),
          indices: Enum.map(final, fn {_, i} -> i end)
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp detect_symmetries(list) do
    len = length(list)

    symmetries = []

    # Check for palindrome
    symmetries =
      if list == Enum.reverse(list) do
        [%{type: :palindrome, full: true} | symmetries]
      else
        symmetries
      end

    # Check for partial symmetries
    partial_symmetries =
      for i <- 1..div(len, 2) do
        left = Enum.slice(list, 0, i)
        right = Enum.slice(list, -i, i)

        if left == Enum.reverse(right) do
          %{type: :partial_palindrome, length: i, elements: left}
        end
      end

    symmetries ++ Enum.filter(partial_symmetries, & &1)
  end

  defp is_homogeneous?(list) do
    types = list |> Enum.map(&type_of/1) |> Enum.uniq()
    length(types) == 1
  end
end
