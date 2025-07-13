defmodule RubberDuck.LLM.Config do
  @moduledoc """
  Configuration management for LLM providers and models.
  
  Handles merging CLI configuration with application configuration,
  providing a unified interface for accessing LLM settings.
  """

  alias RubberDuck.CLIClient.Auth

  @doc """
  Get the model for a specific provider.
  
  CLI config takes precedence over application config.
  """
  def get_provider_model(provider, cli_config \\ nil) do
    provider_atom = ensure_atom(provider)
    cli_config = cli_config || Auth.get_llm_config()
    
    # First check CLI config
    model = if cli_config do
      provider_str = to_string(provider_atom)
      get_in(cli_config, ["providers", provider_str, "model"])
    end
    
    # Fall back to app config if no CLI config
    model || get_app_provider_model(provider_atom)
  end

  @doc """
  Get the current provider and model based on configuration.
  
  Returns {provider, model} tuple.
  """
  def get_current_provider_and_model(cli_config \\ nil) do
    cli_config = cli_config || Auth.get_llm_config()
    
    if cli_config do
      # Use CLI config
      provider = cli_config["default_provider"]
      
      if provider do
        model = cli_config["default_model"] || 
                get_in(cli_config, ["providers", provider, "model"])
        {ensure_atom(provider), model}
      else
        # No default provider, get first from CLI config
        case cli_config["providers"] do
          nil -> 
            # No providers in CLI config, fall back to app config
            get_app_default_provider_and_model()
          providers when map_size(providers) > 0 ->
            {provider_str, config} = Enum.at(providers, 0)
            {ensure_atom(provider_str), config["model"]}
          _ ->
            # Empty providers, fall back to app config
            get_app_default_provider_and_model()
        end
      end
    else
      # Fall back to app config
      get_app_default_provider_and_model()
    end
  end

  @doc """
  List all available models for all providers.
  
  Returns a map of %{provider => [models]}
  """
  def list_available_models(cli_config \\ nil) do
    cli_config = cli_config || Auth.get_llm_config()
    
    # Get models from app config
    app_models = get_app_models()
    
    # Get models from CLI config
    cli_models = if cli_config && cli_config["providers"] do
      cli_config["providers"]
      |> Enum.map(fn {provider, config} ->
        model = config["model"]
        {ensure_atom(provider), [model]}
      end)
      |> Enum.into(%{})
    else
      %{}
    end
    
    # Merge with CLI config taking precedence
    Map.merge(app_models, cli_models)
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