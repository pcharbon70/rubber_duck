defimpl RubberDuck.Enhancer, for: Map do
  @moduledoc """
  Enhancer implementation for Map data type.
  
  Provides enhancement capabilities for map structures including:
  - Semantic enrichment with type information
  - Structural analysis and annotations
  - Temporal context (timestamps, versioning)
  - Relational mapping between fields
  """
  
  @doc """
  Enhance the map using the specified strategy.
  
  ## Strategies
  
  - `:semantic` - Add semantic type information to fields
  - `:structural` - Add structural annotations (depth, complexity)
  - `:temporal` - Add time-based context
  - `:relational` - Identify relationships between fields
  - `{:custom, opts}` - Custom enhancement with options
  """
  def enhance(map, strategy) do
    enhanced = case strategy do
      :semantic -> enhance_semantic(map)
      :structural -> enhance_structural(map)
      :temporal -> enhance_temporal(map)
      :relational -> enhance_relational(map)
      {:custom, opts} -> enhance_custom(map, opts)
      _ -> {:error, :unknown_strategy}
    end
    
    case enhanced do
      {:error, _} = error -> error
      result -> {:ok, result}
    end
  end
  
  @doc """
  Add contextual information to the map.
  """
  def with_context(map, context) do
    Map.put(map, :__context__, Map.merge(get_context(map), context))
  end
  
  @doc """
  Enrich map with metadata.
  """
  def with_metadata(map, metadata) do
    Map.put(map, :__metadata__, Map.merge(get_metadata(map), metadata))
  end
  
  @doc """
  Derive new information from the map data.
  """
  def derive(map, derivations) when is_list(derivations) do
    results = Enum.reduce(derivations, %{}, fn derivation, acc ->
      case derive_single(map, derivation) do
        {:ok, key, value} -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
    
    {:ok, results}
  end
  
  def derive(map, derivation) do
    case derive_single(map, derivation) do
      {:ok, key, value} -> {:ok, %{key => value}}
      error -> error
    end
  end
  
  # Private functions
  
  defp enhance_semantic(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      semantic_info = %{
        type: detect_semantic_type(key, value),
        nullable: is_nil(value),
        format: detect_format(value)
      }
      
      Map.put(acc, key, %{
        value: value,
        semantic: semantic_info
      })
    end)
  end
  
  defp enhance_structural(map) do
    %{
      data: map,
      structure: %{
        depth: calculate_depth(map),
        field_count: map_size(map),
        nested_fields: count_nested_fields(map),
        complexity_score: calculate_complexity(map),
        field_types: analyze_field_types(map)
      }
    }
  end
  
  defp enhance_temporal(map) do
    Map.merge(map, %{
      __temporal__: %{
        enhanced_at: DateTime.utc_now(),
        ttl: 3600, # 1 hour default
        version: generate_version(),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }
    })
  end
  
  defp enhance_relational(map) do
    relationships = analyze_relationships(map)
    
    %{
      data: map,
      relationships: relationships
    }
  end
  
  defp enhance_custom(map, opts) do
    # Allow custom enhancement functions
    case Keyword.get(opts, :enhancer) do
      nil -> map
      func when is_function(func, 1) -> func.(map)
      _ -> map
    end
  end
  
  defp derive_single(map, :summary) do
    summary = %{
      total_fields: map_size(map),
      null_fields: count_nil_fields(map),
      nested_maps: count_nested_maps(map),
      unique_types: unique_value_types(map)
    }
    {:ok, :summary, summary}
  end
  
  defp derive_single(map, :statistics) do
    stats = calculate_statistics(map)
    {:ok, :statistics, stats}
  end
  
  defp derive_single(map, :relationships) do
    rels = analyze_relationships(map)
    {:ok, :relationships, rels}
  end
  
  defp derive_single(map, :patterns) do
    patterns = detect_patterns(map)
    {:ok, :patterns, patterns}
  end
  
  defp derive_single(map, {:custom, opts}) do
    case Keyword.get(opts, :derive_fn) do
      nil -> {:error, :no_derive_function}
      func when is_function(func, 1) ->
        result = func.(map)
        {:ok, Keyword.get(opts, :key, :custom), result}
    end
  end
  
  defp derive_single(_map, _unknown) do
    {:error, :unknown_derivation}
  end
  
  # Helper functions
  
  defp get_context(map) do
    Map.get(map, :__context__, %{})
  end
  
  defp get_metadata(map) do
    Map.get(map, :__metadata__, %{})
  end
  
  defp detect_semantic_type(key, value) do
    key_str = to_string(key)
    
    cond do
      # Detect by key name patterns
      String.match?(key_str, ~r/email/i) -> :email
      String.match?(key_str, ~r/phone/i) -> :phone
      String.match?(key_str, ~r/url|link/i) -> :url
      String.match?(key_str, ~r/date|time/i) -> :datetime
      String.match?(key_str, ~r/price|cost|amount/i) -> :currency
      String.match?(key_str, ~r/^(id|uuid)$/i) -> :identifier
      String.match?(key_str, ~r/name$/i) -> :name
      String.match?(key_str, ~r/description|text|content/i) -> :text
      
      # Detect by value type
      is_number(value) -> :number
      is_boolean(value) -> :boolean
      is_list(value) -> :array
      is_map(value) -> :object
      is_binary(value) -> detect_string_type(value)
      
      true -> :unknown
    end
  end
  
  defp detect_string_type(string) do
    cond do
      String.match?(string, ~r/^\d{4}-\d{2}-\d{2}/) -> :date
      String.match?(string, ~r/^[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}$/) -> :email
      String.match?(string, ~r/^https?:\/\//) -> :url
      String.match?(string, ~r/^\+?\d[\d\s()-]+$/) -> :phone
      true -> :string
    end
  end
  
  defp detect_format(value) when is_binary(value) do
    cond do
      String.match?(value, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) -> :iso8601
      String.match?(value, ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/) -> :uuid
      String.match?(value, ~r/^\$?\d+\.?\d*$/) -> :currency
      true -> :text
    end
  end
  
  defp detect_format(_), do: nil
  
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
  
  defp count_nested_fields(map) do
    Enum.reduce(map, 0, fn {_k, v}, acc ->
      if is_map(v) do
        acc + map_size(v) + count_nested_fields(v)
      else
        acc
      end
    end)
  end
  
  defp calculate_complexity(map) do
    base_score = map_size(map)
    depth_score = calculate_depth(map) * 10
    nested_score = count_nested_fields(map) * 2
    
    base_score + depth_score + nested_score
  end
  
  defp analyze_field_types(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      type = type_of(value)
      Map.update(acc, type, [key], &[key | &1])
    end)
  end
  
  defp type_of(value) do
    cond do
      is_nil(value) -> :nil
      is_atom(value) -> :atom
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_boolean(value) -> :boolean
      is_list(value) -> :list
      is_map(value) -> :map
      true -> :other
    end
  end
  
  defp count_nil_fields(map) do
    Enum.count(map, fn {_k, v} -> is_nil(v) end)
  end
  
  defp count_nested_maps(map) do
    Enum.count(map, fn {_k, v} -> is_map(v) end)
  end
  
  defp unique_value_types(map) do
    map
    |> Map.values()
    |> Enum.map(&type_of/1)
    |> Enum.uniq()
  end
  
  defp calculate_statistics(map) do
    numeric_values = map
    |> Map.values()
    |> Enum.filter(&is_number/1)
    
    if Enum.empty?(numeric_values) do
      %{numeric_fields: 0}
    else
      %{
        numeric_fields: length(numeric_values),
        sum: Enum.sum(numeric_values),
        average: Enum.sum(numeric_values) / length(numeric_values),
        min: Enum.min(numeric_values),
        max: Enum.max(numeric_values)
      }
    end
  end
  
  defp analyze_relationships(map) do
    keys = Map.keys(map)
    
    relationships = for k1 <- keys, k2 <- keys, k1 != k2 do
      similarity = calculate_key_similarity(k1, k2)
      if similarity > 0.5 do
        %{from: k1, to: k2, similarity: similarity, type: infer_relationship_type(k1, k2)}
      end
    end
    
    Enum.filter(relationships, & &1)
  end
  
  defp calculate_key_similarity(k1, k2) do
    s1 = to_string(k1)
    s2 = to_string(k2)
    
    # Simple similarity based on shared prefixes/suffixes
    cond do
      String.starts_with?(s1, s2) or String.starts_with?(s2, s1) -> 0.8
      String.ends_with?(s1, s2) or String.ends_with?(s2, s1) -> 0.7
      String.contains?(s1, s2) or String.contains?(s2, s1) -> 0.6
      true -> 0.0
    end
  end
  
  defp infer_relationship_type(k1, k2) do
    s1 = to_string(k1)
    s2 = to_string(k2)
    
    cond do
      String.match?(s1, ~r/^parent_/) and String.match?(s2, ~r/^child_/) -> :parent_child
      String.ends_with?(s1, "_id") and String.starts_with?(s2, String.replace_suffix(s1, "_id", "")) -> :reference
      true -> :related
    end
  end
  
  defp detect_patterns(map) do
    %{
      naming_conventions: detect_naming_patterns(Map.keys(map)),
      value_patterns: detect_value_patterns(Map.values(map)),
      structural_patterns: detect_structural_patterns(map)
    }
  end
  
  defp detect_naming_patterns(keys) do
    string_keys = Enum.map(keys, &to_string/1)
    
    %{
      snake_case: Enum.count(string_keys, &String.match?(&1, ~r/^[a-z]+(_[a-z]+)*$/)),
      camel_case: Enum.count(string_keys, &String.match?(&1, ~r/^[a-z]+([A-Z][a-z]+)*$/)),
      pascal_case: Enum.count(string_keys, &String.match?(&1, ~r/^[A-Z][a-z]+([A-Z][a-z]+)*$/)),
      has_prefixes: Enum.any?(string_keys, &String.contains?(&1, "_")),
      common_prefixes: find_common_prefixes(string_keys)
    }
  end
  
  defp detect_value_patterns(values) do
    %{
      all_same_type: length(Enum.uniq_by(values, &type_of/1)) == 1,
      has_nulls: Enum.any?(values, &is_nil/1),
      has_empty_strings: Enum.any?(values, &(&1 == "")),
      has_nested_structures: Enum.any?(values, &(is_map(&1) or is_list(&1)))
    }
  end
  
  defp detect_structural_patterns(map) do
    %{
      flat_structure: Enum.all?(Map.values(map), &(not is_map(&1))),
      consistent_depth: consistent_depth?(map),
      has_id_fields: Enum.any?(Map.keys(map), &String.match?(to_string(&1), ~r/^(id|.*_id)$/i))
    }
  end
  
  defp find_common_prefixes(strings) do
    strings
    |> Enum.flat_map(&String.split(&1, "_"))
    |> Enum.frequencies()
    |> Enum.filter(fn {_prefix, count} -> count > 1 end)
    |> Enum.map(fn {prefix, _count} -> prefix end)
  end
  
  defp consistent_depth?(map) do
    depths = map
    |> Map.values()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&calculate_depth/1)
    
    case depths do
      [] -> true
      [_] -> true
      depths -> Enum.uniq(depths) |> length() == 1
    end
  end
  
  defp generate_version do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end