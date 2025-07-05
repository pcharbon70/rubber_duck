defmodule RubberDuck.LLM.ProviderConfig do
  @moduledoc """
  Configuration for an LLM provider.
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
    options: keyword()
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
    options: []
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
      behaviours = config.adapter.module_info(:attributes)
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
end