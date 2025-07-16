defmodule RubberDuck.LLM.Config do
  @moduledoc """
  Configuration management for LLM providers and models.
  
  Provides a unified interface for accessing LLM settings from
  application configuration.
  """

  @doc """
  Get the model for a specific provider.
  """
  def get_provider_model(provider, _cli_config \\ nil) do
    provider_atom = ensure_atom(provider)
    get_app_provider_model(provider_atom)
  end

  @doc """
  Get the current provider and model based on configuration.
  
  Returns {provider, model} tuple.
  """
  def get_current_provider_and_model(_cli_config \\ nil) do
    get_app_default_provider_and_model()
  end

  @doc """
  List all available models for all providers.
  
  Returns a map of %{provider => [models]}
  """
  def list_available_models(_cli_config \\ nil) do
    get_app_models()
  end

  @doc """
  Validate that a model is available for a provider.
  """
  def validate_model(provider, model) do
    provider_atom = ensure_atom(provider)
    available_models = list_available_models()
    
    case available_models[provider_atom] do
      nil ->
        # If provider not configured, allow it for flexibility
        :ok
      
      models when is_list(models) ->
        if Enum.empty?(models) || model in models do
          :ok
        else
          # If model not in list, still allow it for flexibility
          :ok
        end
    end
  end

  # Private functions

  defp ensure_atom(value) when is_atom(value), do: value
  defp ensure_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> String.to_atom(value)
  end

  defp get_app_provider_model(provider) do
    llm_config = Application.get_env(:rubber_duck, :llm, [])
    providers = Keyword.get(llm_config, :providers, [])
    
    provider_config = Enum.find(providers, fn config ->
      config[:name] == provider
    end)
    
    if provider_config do
      provider_config[:default_model] || List.first(provider_config[:models])
    else
      nil
    end
  end

  defp get_app_default_provider_and_model do
    llm_config = Application.get_env(:rubber_duck, :llm, [])
    default_provider = Keyword.get(llm_config, :default_provider)
    
    if default_provider do
      model = get_app_provider_model(default_provider)
      {default_provider, model}
    else
      # Get first configured provider
      providers = Keyword.get(llm_config, :providers, [])
      case providers do
        [first | _] ->
          {first[:name], first[:default_model]}
        [] ->
          {nil, nil}
      end
    end
  end

  defp get_app_models do
    llm_config = Application.get_env(:rubber_duck, :llm, [])
    providers = Keyword.get(llm_config, :providers, [])
    
    providers
    |> Enum.map(fn provider ->
      {provider[:name], provider[:models] || []}
    end)
    |> Enum.into(%{})
  end
end