defmodule RubberDuck.LLM.ConfigLoader do
  @moduledoc """
  Loads LLM provider configuration from multiple sources.
  
  Configuration sources in priority order:
  1. Runtime overrides (highest priority)
  2. User config file (~/.rubber_duck/config.json)
  3. Environment variables
  
  The config.json file supports specifying custom environment variable names
  per provider, allowing flexible configuration across different deployments.
  """
  
  require Logger
  
  @config_file_path Path.expand("~/.rubber_duck/config.json")
  
  @doc """
  Loads configuration for all providers from available sources.
  
  Returns a list of provider configurations with resolved values.
  """
  def load_all_providers(runtime_overrides \\ %{}) do
    # Load base configuration from file
    file_config = load_config_file()
    
    # Get all configured providers
    providers = get_all_provider_names(file_config, runtime_overrides)
    
    # Load configuration for each provider
    Enum.map(providers, fn provider_name ->
      load_provider_config(provider_name, file_config, runtime_overrides)
    end)
    |> Enum.filter(&(&1 != nil))
  end
  
  @doc """
  Loads configuration for a specific provider.
  
  Merges configuration from all sources with proper priority.
  """
  def load_provider_config(provider_name, file_config \\ nil, runtime_overrides \\ %{}) do
    file_config = file_config || load_config_file()
    
    # Get provider-specific configs
    provider_str = to_string(provider_name)
    file_provider_config = get_in(file_config, ["providers", provider_str]) || %{}
    runtime_provider_config = Map.get(runtime_overrides, provider_name, %{})
    
    # Determine environment variable names
    api_key_env = file_provider_config["env_var_name"] || default_api_key_env(provider_name)
    base_url_env = file_provider_config["base_url_env_var"] || default_base_url_env(provider_name)
    
    # Load values with priority
    api_key = runtime_provider_config[:api_key] || 
              runtime_provider_config["api_key"] ||
              file_provider_config["api_key"] || 
              (api_key_env && System.get_env(api_key_env))
              
    base_url = runtime_provider_config[:base_url] || 
               runtime_provider_config["base_url"] ||
               file_provider_config["base_url"] || 
               (base_url_env && System.get_env(base_url_env))
    
    # Get other configuration
    models = runtime_provider_config[:models] || 
             runtime_provider_config["models"] ||
             file_provider_config["models"] || 
             default_models(provider_name)
             
    adapter = get_adapter_module(provider_name)
    
    if adapter do
      %{
        name: provider_name,
        adapter: adapter,
        api_key: api_key,
        base_url: base_url,
        models: ensure_list(models),
        priority: get_priority(provider_name, file_provider_config, runtime_provider_config),
        rate_limit: get_rate_limit(provider_name, file_provider_config, runtime_provider_config),
        max_retries: get_max_retries(file_provider_config, runtime_provider_config),
        timeout: get_timeout(file_provider_config, runtime_provider_config),
        headers: get_headers(file_provider_config, runtime_provider_config),
        options: get_options(file_provider_config, runtime_provider_config)
      }
    else
      Logger.warning("Unknown provider: #{provider_name}")
      nil
    end
  end
  
  @doc """
  Loads the config.json file if it exists.
  """
  def load_config_file do
    case File.read(@config_file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            config
          {:error, error} ->
            Logger.error("Failed to parse config.json: #{inspect(error)}")
            %{}
        end
      {:error, :enoent} ->
        Logger.debug("Config file not found at #{@config_file_path}")
        %{}
      {:error, error} ->
        Logger.error("Failed to read config.json: #{inspect(error)}")
        %{}
    end
  end
  
  @doc """
  Saves configuration to the config.json file.
  """
  def save_config_file(config) do
    # Ensure directory exists
    dir = Path.dirname(@config_file_path)
    File.mkdir_p!(dir)
    
    # Write config
    content = Jason.encode!(config, pretty: true)
    File.write!(@config_file_path, content)
  end
  
  @doc """
  Gets the path to the config file.
  """
  def config_file_path, do: @config_file_path
  
  # Private functions
  
  defp get_all_provider_names(file_config, runtime_overrides) do
    file_providers = Map.get(file_config, "providers", %{}) |> Map.keys() |> Enum.map(&String.to_atom/1)
    runtime_providers = Map.keys(runtime_overrides)
    
    # Known providers that might not be in config
    known_providers = [:openai, :anthropic, :ollama, :tgi, :mock]
    
    (file_providers ++ runtime_providers ++ known_providers)
    |> Enum.uniq()
  end
  
  defp get_adapter_module(provider_name) do
    case RubberDuck.LLM.AdapterRegistry.get_adapter(provider_name) do
      {:ok, adapter} -> adapter
      {:error, _} -> nil
    end
  end
  
  defp default_api_key_env(:openai), do: "OPENAI_API_KEY"
  defp default_api_key_env(:anthropic), do: "ANTHROPIC_API_KEY"
  defp default_api_key_env(_), do: nil
  
  defp default_base_url_env(:ollama), do: "OLLAMA_BASE_URL"
  defp default_base_url_env(:tgi), do: "TGI_BASE_URL"
  defp default_base_url_env(_), do: nil
  
  defp default_models(:openai), do: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"]
  defp default_models(:anthropic), do: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]
  defp default_models(:ollama), do: ["llama2", "codellama", "mistral"]
  defp default_models(:tgi), do: ["llama-3.1-8b", "mistral-7b"]
  defp default_models(:mock), do: ["mock-fast", "mock-smart"]
  defp default_models(_), do: []
  
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list(value), do: [value]
  
  defp get_priority(:openai, _, _), do: 1
  defp get_priority(:anthropic, _, _), do: 2
  defp get_priority(:ollama, _, _), do: 3
  defp get_priority(:tgi, _, _), do: 4
  defp get_priority(:mock, _, _), do: 5
  defp get_priority(_, file_config, runtime_config) do
    runtime_config[:priority] || file_config["priority"] || 99
  end
  
  defp get_rate_limit(provider_name, file_config, runtime_config) do
    # Check runtime config first
    runtime_limit = runtime_config[:rate_limit]
    
    # Then check file config
    file_limit = parse_rate_limit(file_config["rate_limit"])
    
    # Finally use defaults
    default_limit = case provider_name do
      :openai -> {100, :minute}
      :anthropic -> {50, :minute}
      _ -> nil
    end
    
    runtime_limit || file_limit || default_limit
  end
  
  defp parse_rate_limit(nil), do: nil
  defp parse_rate_limit({_, _} = rate_limit), do: rate_limit
  defp parse_rate_limit(%{"limit" => limit, "unit" => unit}) do
    {limit, String.to_atom(unit)}
  end
  defp parse_rate_limit(_), do: nil
  
  defp get_max_retries(file_config, runtime_config) do
    runtime_config[:max_retries] || file_config["max_retries"] || 3
  end
  
  defp get_timeout(file_config, runtime_config) do
    runtime_config[:timeout] || file_config["timeout"] || 30_000
  end
  
  defp get_headers(file_config, runtime_config) do
    file_headers = file_config["headers"] || %{}
    runtime_headers = runtime_config[:headers] || %{}
    Map.merge(file_headers, runtime_headers)
  end
  
  defp get_options(file_config, runtime_config) do
    file_options = file_config["options"] || []
    runtime_options = runtime_config[:options] || []
    Keyword.merge(
      normalize_options(file_options),
      normalize_options(runtime_options)
    )
  end
  
  defp normalize_options(opts) when is_list(opts), do: opts
  defp normalize_options(opts) when is_map(opts) do
    Enum.map(opts, fn {k, v} -> {String.to_atom(k), v} end)
  end
  defp normalize_options(_), do: []
end