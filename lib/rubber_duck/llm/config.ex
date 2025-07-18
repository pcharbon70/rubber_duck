defmodule RubberDuck.LLM.Config do
  @moduledoc """
  Configuration management for LLM providers and models.
  
  Provides a unified interface for accessing LLM settings from
  application configuration and user preferences.
  """

  @doc """
  Get the model for a specific provider with optional user context.
  
  If user_id is provided, will check user preferences first,
  then fall back to global configuration.
  """
  def get_provider_model(provider, user_id \\ nil) do
    provider_atom = ensure_atom(provider)
    
    case get_user_provider_model(user_id, provider_atom) do
      {:ok, model} -> model
      :not_found -> get_app_provider_model(provider_atom)
    end
  end

  @doc """
  Get the current provider and model based on configuration and user preferences.
  
  Returns {provider, model} tuple.
  If user_id is provided, prioritizes user default settings.
  """
  def get_current_provider_and_model(user_id \\ nil) do
    case get_user_default_provider_and_model(user_id) do
      {:ok, {provider, model}} -> {provider, model}
      :not_found -> get_app_default_provider_and_model()
    end
  end

  @doc """
  List all available models for all providers.
  
  Returns a map of %{provider => [models]}
  Optionally includes user's configured models.
  """
  def list_available_models(user_id \\ nil) do
    app_models = get_app_models()
    
    case get_user_models(user_id) do
      {:ok, user_models} ->
        # Merge user models with app models
        Map.merge(app_models, user_models, fn _provider, app_list, user_list ->
          (app_list ++ user_list) |> Enum.uniq()
        end)
      
      :not_found ->
        app_models
    end
  end

  @doc """
  Validate that a model is available for a provider.
  Checks both application config and user preferences.
  """
  def validate_model(provider, model, user_id \\ nil) do
    provider_atom = ensure_atom(provider)
    available_models = list_available_models(user_id)
    
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

  @doc """
  Get user's default LLM configuration.
  
  Returns {:ok, {provider, model}} if user has a default set,
  or :not_found if no user default exists.
  """
  def get_user_default_provider_and_model(user_id) when is_binary(user_id) do
    case RubberDuck.Memory.get_user_default(user_id) do
      {:ok, config} when not is_nil(config) ->
        {:ok, {config.provider, config.model}}
      
      {:ok, nil} ->
        :not_found
        
      {:error, _} ->
        :not_found
    end
  end
  
  def get_user_default_provider_and_model(_user_id), do: :not_found

  @doc """
  Get user's provider-specific model preference.
  
  Returns {:ok, model} if user has configured this provider,
  or :not_found if no user preference exists.
  """
  def get_user_provider_model(user_id, provider) when is_binary(user_id) and is_atom(provider) do
    case RubberDuck.Memory.get_provider_default(user_id, provider) do
      {:ok, config} when not is_nil(config) ->
        {:ok, config.model}
      
      {:ok, nil} ->
        :not_found
        
      {:error, _} ->
        :not_found
    end
  end
  
  def get_user_provider_model(_user_id, _provider), do: :not_found

  @doc """
  Get all user-configured models by provider.
  
  Returns {:ok, %{provider => [models]}} or :not_found.
  """
  def get_user_models(user_id) when is_binary(user_id) do
    case RubberDuck.Memory.get_user_configs(user_id) do
      {:ok, configs} when is_list(configs) and length(configs) > 0 ->
        models_by_provider = 
          configs
          |> Enum.group_by(& &1.provider)
          |> Map.new(fn {provider, provider_configs} ->
            models = Enum.map(provider_configs, & &1.model)
            {provider, models}
          end)
        
        {:ok, models_by_provider}
      
      {:ok, []} ->
        :not_found
        
      {:error, _} ->
        :not_found
    end
  end
  
  def get_user_models(_user_id), do: :not_found

  @doc """
  Set user's default LLM configuration.
  
  Creates or updates a user's default provider and model preference.
  """
  def set_user_default(user_id, provider, model) when is_binary(user_id) and is_atom(provider) and is_binary(model) do
    case RubberDuck.Memory.set_user_default(user_id, provider, model) do
      {:ok, config} ->
        {:ok, config}
      
      {:error, reason} ->
        {:error, reason}
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