defmodule RubberDuck.LLM.ProviderConfig do
  @moduledoc """
  Configuration for an LLM provider.
  
  Supports runtime configuration through multiple sources:
  - Runtime overrides (highest priority)
  - Config file (~/.rubber_duck/config.json)
  - Environment variables
  """

  @type t :: %__MODULE__{
          name: atom(),
          adapter: module(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          models: list(String.t()),
          priority: non_neg_integer(),
          rate_limit: {non_neg_integer(), :second | :minute | :hour} | nil,
          max_retries: non_neg_integer(),
          timeout: non_neg_integer(),
          headers: map(),
          options: keyword(),
          runtime_overrides: map()
        }

  defstruct [
    :name,
    :adapter,
    :api_key,
    :base_url,
    models: [],
    priority: 1,
    rate_limit: nil,
    max_retries: 3,
    timeout: 30_000,
    headers: %{},
    options: [],
    runtime_overrides: %{}
  ]

  @doc """
  Validates a provider configuration.
  """
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_required_fields(config),
         :ok <- validate_adapter(config),
         :ok <- validate_models(config),
         :ok <- validate_rate_limit(config) do
      {:ok, config}
    end
  end

  defp validate_required_fields(config) do
    cond do
      is_nil(config.name) -> {:error, :name_required}
      is_nil(config.adapter) -> {:error, :adapter_required}
      true -> :ok
    end
  end

  defp validate_adapter(config) do
    if Code.ensure_loaded?(config.adapter) do
      behaviours =
        config.adapter.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      if RubberDuck.LLM.Provider in behaviours do
        :ok
      else
        {:error, {:adapter_missing_behaviour, config.adapter}}
      end
    else
      {:error, {:adapter_not_found, config.adapter}}
    end
  end

  defp validate_models(config) do
    if Enum.all?(config.models, &is_binary/1) do
      :ok
    else
      {:error, :invalid_models}
    end
  end

  defp validate_rate_limit(%{rate_limit: nil}), do: :ok

  defp validate_rate_limit(%{rate_limit: {limit, unit}})
       when is_integer(limit) and limit > 0 and unit in [:second, :minute, :hour] do
    :ok
  end

  defp validate_rate_limit(_), do: {:error, :invalid_rate_limit}
  
  @doc """
  Applies runtime overrides to a provider configuration.
  
  The overrides map can contain:
  - `:api_key` - Override API key
  - `:base_url` - Override base URL
  - `:models` - Override available models
  - `:headers` - Additional headers (merged with existing)
  - `:options` - Additional options (merged with existing)
  """
  def apply_overrides(%__MODULE__{} = config, overrides) when is_map(overrides) do
    config
    |> maybe_override(:api_key, overrides)
    |> maybe_override(:base_url, overrides)
    |> maybe_override(:models, overrides)
    |> maybe_override(:priority, overrides)
    |> maybe_override(:rate_limit, overrides)
    |> maybe_override(:max_retries, overrides)
    |> maybe_override(:timeout, overrides)
    |> merge_override(:headers, overrides)
    |> merge_override(:options, overrides)
    |> Map.put(:runtime_overrides, overrides)
  end
  
  defp maybe_override(config, field, overrides) do
    case Map.get(overrides, field) do
      nil -> config
      value -> Map.put(config, field, value)
    end
  end
  
  defp merge_override(config, :headers, overrides) do
    case Map.get(overrides, :headers) do
      nil -> config
      new_headers -> Map.update!(config, :headers, &Map.merge(&1, new_headers))
    end
  end
  
  defp merge_override(config, :options, overrides) do
    case Map.get(overrides, :options) do
      nil -> config
      new_options -> Map.update!(config, :options, &Keyword.merge(&1, new_options))
    end
  end
end
