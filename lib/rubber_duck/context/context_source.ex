defmodule RubberDuck.Context.ContextSource do
  @moduledoc """
  Data structure representing a context source.
  
  Context sources are registered providers of context information, such as
  memory systems, code analyzers, documentation, etc. Each source has its
  own configuration, weighting, and transformation logic.
  """

  defstruct [
    :id,
    :name,
    :type,
    :weight,
    :config,
    :status,
    :last_fetch,
    :failure_count,
    :transformer,
    :validator,
    :cache_config,
    :metrics
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    type: atom(),
    weight: float(),
    config: map(),
    status: source_status(),
    last_fetch: DateTime.t() | nil,
    failure_count: integer(),
    transformer: (any() -> any()) | nil,
    validator: (any() -> boolean()) | nil,
    cache_config: cache_config(),
    metrics: source_metrics()
  }

  @type source_status :: :active | :inactive | :failing | :disabled
  
  @type cache_config :: %{
    enabled: boolean(),
    ttl: integer(),
    max_entries: integer()
  }

  @type source_metrics :: %{
    total_fetches: integer(),
    successful_fetches: integer(),
    avg_fetch_time_ms: float(),
    total_entries_provided: integer(),
    last_error: String.t() | nil
  }

  @valid_types [:memory, :code_analysis, :documentation, :conversation, :planning, :custom]

  @doc """
  Creates a new context source with the given configuration.
  """
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      name: attrs[:name] || "Unnamed Source",
      type: validate_type(attrs[:type]),
      weight: validate_weight(attrs[:weight] || 1.0),
      config: attrs[:config] || %{},
      status: :active,
      last_fetch: nil,
      failure_count: 0,
      transformer: attrs[:transformer],
      validator: attrs[:validator],
      cache_config: build_cache_config(attrs[:cache_config]),
      metrics: initial_metrics()
    }
  end

  @doc """
  Updates source configuration and attributes.
  """
  def update(source, updates) do
    source
    |> maybe_update_field(:name, updates["name"])
    |> maybe_update_field(:weight, updates["weight"], &validate_weight/1)
    |> maybe_update_field(:config, updates["config"])
    |> maybe_update_field(:status, updates["status"], &validate_status/1)
    |> maybe_update_field(:transformer, updates["transformer"])
    |> maybe_update_field(:validator, updates["validator"])
    |> maybe_update_field(:cache_config, updates["cache_config"], &build_cache_config/1)
  end

  @doc """
  Records a successful fetch from the source.
  """
  def record_success(source, fetch_time_ms, entries_count) do
    metrics = source.metrics
    total = metrics.total_fetches + 1
    successful = metrics.successful_fetches + 1
    
    avg_time = (metrics.avg_fetch_time_ms * metrics.total_fetches + fetch_time_ms) / total
    
    %{source |
      last_fetch: DateTime.utc_now(),
      failure_count: 0,
      status: :active,
      metrics: %{metrics |
        total_fetches: total,
        successful_fetches: successful,
        avg_fetch_time_ms: avg_time,
        total_entries_provided: metrics.total_entries_provided + entries_count,
        last_error: nil
      }
    }
  end

  @doc """
  Records a failed fetch from the source.
  """
  def record_failure(source, error_message) do
    failure_count = source.failure_count + 1
    
    status = if failure_count >= 3, do: :failing, else: source.status
    
    %{source |
      failure_count: failure_count,
      status: status,
      metrics: %{source.metrics |
        total_fetches: source.metrics.total_fetches + 1,
        last_error: error_message
      }
    }
  end

  @doc """
  Checks if the source is available for fetching.
  """
  def available?(source) do
    source.status in [:active, :failing]
  end

  @doc """
  Checks if the source should be included based on requirements.
  """
  def matches_requirements?(source, required_types, required_ids) do
    type_match = required_types == [] or source.type in required_types
    id_match = required_ids == [] or source.id in required_ids
    
    type_match and id_match
  end

  @doc """
  Applies the source's transformer to raw data.
  """
  def transform_data(source, data) do
    if source.transformer do
      try do
        {:ok, source.transformer.(data)}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:ok, data}
    end
  end

  @doc """
  Validates data using the source's validator.
  """
  def validate_data(source, data) do
    if source.validator do
      try do
        if source.validator.(data) do
          :ok
        else
          {:error, "Validation failed"}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      :ok
    end
  end

  @doc """
  Calculates the effective weight of the source based on its status.
  """
  def effective_weight(source) do
    case source.status do
      :active -> source.weight
      :failing -> source.weight * 0.5  # Reduce weight for failing sources
      :inactive -> 0.0
      :disabled -> 0.0
    end
  end

  @doc """
  Returns source health status information.
  """
  def health_status(source) do
    success_rate = if source.metrics.total_fetches > 0 do
      source.metrics.successful_fetches / source.metrics.total_fetches * 100
    else
      100.0
    end
    
    %{
      status: source.status,
      available: available?(source),
      failure_count: source.failure_count,
      success_rate: success_rate,
      last_fetch: source.last_fetch,
      last_error: source.metrics.last_error
    }
  end

  @doc """
  Resets the source to active status.
  """
  def reset(source) do
    %{source |
      status: :active,
      failure_count: 0,
      metrics: %{source.metrics | last_error: nil}
    }
  end

  @doc """
  Disables the source temporarily.
  """
  def disable(source) do
    %{source | status: :disabled}
  end

  @doc """
  Enables a disabled source.
  """
  def enable(source) do
    %{source | status: :active, failure_count: 0}
  end

  # Private functions

  defp generate_id do
    "src_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp validate_type(type) when type in @valid_types, do: type
  defp validate_type(type) when is_binary(type) do
    atom_type = String.to_atom(type)
    if atom_type in @valid_types do
      atom_type
    else
      raise ArgumentError, "Invalid source type: #{type}"
    end
  end
  defp validate_type(_), do: raise(ArgumentError, "Source type must be one of: #{inspect(@valid_types)}")

  defp validate_weight(weight) when is_number(weight) and weight >= 0 and weight <= 10 do
    weight / 1  # Convert to float
  end
  defp validate_weight(_), do: raise(ArgumentError, "Weight must be a number between 0 and 10")

  defp validate_status(status) when status in [:active, :inactive, :failing, :disabled], do: status
  defp validate_status(status) when is_binary(status) do
    String.to_atom(status)
  end
  defp validate_status(_), do: :active

  defp build_cache_config(nil), do: default_cache_config()
  defp build_cache_config(config) when is_map(config) do
    Map.merge(default_cache_config(), config)
  end

  defp default_cache_config do
    %{
      enabled: true,
      ttl: 300_000,  # 5 minutes
      max_entries: 1000
    }
  end

  defp initial_metrics do
    %{
      total_fetches: 0,
      successful_fetches: 0,
      avg_fetch_time_ms: 0.0,
      total_entries_provided: 0,
      last_error: nil
    }
  end

  defp maybe_update_field(source, _field, nil, _validator), do: source
  defp maybe_update_field(source, field, value, validator) do
    validated_value = validator.(value)
    Map.put(source, field, validated_value)
  end

  defp maybe_update_field(source, _field, nil), do: source
  defp maybe_update_field(source, field, value) do
    Map.put(source, field, value)
  end
end