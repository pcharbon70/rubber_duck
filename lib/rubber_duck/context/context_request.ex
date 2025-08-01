defmodule RubberDuck.Context.ContextRequest do
  @moduledoc """
  Data structure representing a request for context building.
  
  Context requests define what context is needed, including purpose,
  constraints, source requirements, and preferences for optimization.
  """

  defstruct [
    :id,
    :purpose,
    :max_tokens,
    :required_sources,
    :excluded_sources,
    :filters,
    :preferences,
    :priority,
    :deadline,
    :streaming,
    :cache_key,
    :metadata
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    purpose: String.t(),
    max_tokens: integer(),
    required_sources: list(String.t()),
    excluded_sources: list(String.t()),
    filters: map(),
    preferences: map(),
    priority: priority_level(),
    deadline: DateTime.t() | nil,
    streaming: boolean(),
    cache_key: String.t() | nil,
    metadata: map()
  }

  @type priority_level :: :low | :normal | :high | :critical

  @valid_purposes ~w(general code_generation code_analysis planning conversation documentation debugging)

  @doc """
  Creates a new context request with validation.
  """
  def new(attrs) do
    request = %__MODULE__{
      id: attrs[:id] || generate_id(),
      purpose: validate_purpose(attrs[:purpose] || "general"),
      max_tokens: validate_max_tokens(attrs[:max_tokens] || 4000),
      required_sources: attrs[:required_sources] || [],
      excluded_sources: attrs[:excluded_sources] || [],
      filters: attrs[:filters] || %{},
      preferences: attrs[:preferences] || %{},
      priority: validate_priority(attrs[:priority] || :normal),
      deadline: attrs[:deadline],
      streaming: attrs[:streaming] || false,
      cache_key: attrs[:cache_key] || generate_cache_key(attrs),
      metadata: attrs[:metadata] || %{}
    }
    
    validate_request!(request)
    request
  end

  @doc """
  Checks if the request has expired based on its deadline.
  """
  def expired?(request) do
    case request.deadline do
      nil -> false
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :gt
    end
  end

  @doc """
  Checks if a source should be used for this request.
  """
  def should_use_source?(request, source_id) do
    not_excluded = source_id not in request.excluded_sources
    
    required_or_not_specified = request.required_sources == [] or 
                               source_id in request.required_sources
    
    not_excluded and required_or_not_specified
  end

  @doc """
  Applies filters to determine if an entry matches the request.
  """
  def matches_filters?(request, entry) do
    Enum.all?(request.filters, fn {key, value} ->
      entry_value = get_nested_value(entry, key)
      matches_filter_value?(entry_value, value)
    end)
  end

  @doc """
  Calculates the urgency of the request based on priority and deadline.
  """
  def urgency_score(request) do
    priority_score = case request.priority do
      :critical -> 1.0
      :high -> 0.75
      :normal -> 0.5
      :low -> 0.25
    end
    
    deadline_score = case request.deadline do
      nil -> 0.5
      deadline ->
        minutes_until = DateTime.diff(deadline, DateTime.utc_now(), :minute)
        cond do
          minutes_until <= 0 -> 1.0
          minutes_until < 5 -> 0.9
          minutes_until < 30 -> 0.7
          minutes_until < 60 -> 0.5
          true -> 0.3
        end
    end
    
    (priority_score + deadline_score) / 2
  end

  @doc """
  Merges two requests, combining their requirements.
  """
  def merge(request1, request2) do
    %__MODULE__{
      id: generate_id(),
      purpose: "#{request1.purpose},#{request2.purpose}",
      max_tokens: max(request1.max_tokens, request2.max_tokens),
      required_sources: Enum.uniq(request1.required_sources ++ request2.required_sources),
      excluded_sources: Enum.uniq(request1.excluded_sources ++ request2.excluded_sources),
      filters: Map.merge(request1.filters, request2.filters),
      preferences: Map.merge(request1.preferences, request2.preferences),
      priority: max_priority(request1.priority, request2.priority),
      deadline: earliest_deadline(request1.deadline, request2.deadline),
      streaming: request1.streaming or request2.streaming,
      cache_key: nil,  # Merged requests get new cache key
      metadata: Map.merge(request1.metadata, request2.metadata)
    }
  end

  @doc """
  Creates a sub-request for a specific source.
  """
  def for_source(request, source_id) do
    %{request |
      required_sources: [source_id],
      cache_key: "#{request.cache_key}_#{source_id}"
    }
  end

  @doc """
  Converts request to a map for serialization.
  """
  def to_map(request) do
    %{
      id: request.id,
      purpose: request.purpose,
      max_tokens: request.max_tokens,
      required_sources: request.required_sources,
      excluded_sources: request.excluded_sources,
      filters: request.filters,
      preferences: request.preferences,
      priority: request.priority,
      deadline: request.deadline,
      streaming: request.streaming,
      metadata: request.metadata
    }
  end

  # Private functions

  defp generate_id do
    "req_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp generate_cache_key(attrs) do
    # Create cache key from significant attributes
    key_parts = [
      attrs[:purpose] || "general",
      attrs[:max_tokens] || 4000,
      inspect(attrs[:required_sources] || []),
      inspect(attrs[:filters] || %{})
    ]
    
    key_string = Enum.join(key_parts, "_")
    :crypto.hash(:md5, key_string) |> Base.encode16(case: :lower)
  end

  defp validate_purpose(purpose) when purpose in @valid_purposes, do: purpose
  defp validate_purpose(purpose) when is_binary(purpose) do
    if String.contains?(purpose, "_") do
      purpose  # Allow custom purposes with underscores
    else
      "general"
    end
  end
  defp validate_purpose(_), do: "general"

  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0 and tokens <= 100_000 do
    tokens
  end
  defp validate_max_tokens(_), do: 4000

  defp validate_priority(priority) when priority in [:low, :normal, :high, :critical], do: priority
  defp validate_priority(priority) when is_binary(priority) do
    String.to_atom(priority)
  end
  defp validate_priority(_), do: :normal

  defp validate_request!(request) do
    # Check for conflicting source requirements
    conflict = MapSet.intersection(
      MapSet.new(request.required_sources),
      MapSet.new(request.excluded_sources)
    )
    
    unless MapSet.size(conflict) == 0 do
      raise ArgumentError, "Sources cannot be both required and excluded: #{inspect(MapSet.to_list(conflict))}"
    end
    
    # Validate deadline is in the future
    if request.deadline && DateTime.compare(request.deadline, DateTime.utc_now()) == :lt do
      raise ArgumentError, "Deadline must be in the future"
    end
    
    request
  end

  defp get_nested_value(entry, key) when is_binary(key) do
    keys = String.split(key, ".")
    get_in(entry, Enum.map(keys, &String.to_atom/1))
  end
  defp get_nested_value(entry, key), do: Map.get(entry, key)

  defp matches_filter_value?(nil, _filter), do: false
  defp matches_filter_value?(value, filter) when is_map(filter) do
    # Handle complex filters like {gte: 5, lte: 10}
    Enum.all?(filter, fn {op, filter_val} ->
      case op do
        "eq" -> value == filter_val
        "neq" -> value != filter_val
        "gt" -> value > filter_val
        "gte" -> value >= filter_val
        "lt" -> value < filter_val
        "lte" -> value <= filter_val
        "in" -> value in filter_val
        "contains" -> String.contains?(to_string(value), filter_val)
        _ -> true
      end
    end)
  end
  defp matches_filter_value?(value, filter), do: value == filter

  defp max_priority(p1, p2) do
    priority_order = %{critical: 4, high: 3, normal: 2, low: 1}
    
    if priority_order[p1] >= priority_order[p2], do: p1, else: p2
  end

  defp earliest_deadline(nil, d2), do: d2
  defp earliest_deadline(d1, nil), do: d1
  defp earliest_deadline(d1, d2) do
    if DateTime.compare(d1, d2) == :lt, do: d1, else: d2
  end
end