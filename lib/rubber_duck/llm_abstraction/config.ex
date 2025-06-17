defmodule RubberDuck.LLMAbstraction.Config do
  @moduledoc """
  Configuration schema and validation for LLM providers.
  
  This module defines the configuration structure for LLM providers including
  URLs, authentication, models, and provider-specific settings.
  """

  defstruct [
    :provider_type,
    :base_url,
    :api_key,
    :organization_id,
    :project_id,
    :model,
    :default_model,
    :supported_models,
    :timeout,
    :max_retries,
    :rate_limit,
    :headers,
    :custom_endpoints,
    :api_version,
    :region,
    :environment,
    :metadata
  ]

  @type provider_type :: :openai | :anthropic | :local | :azure_openai | :google | :cohere | :custom

  @type rate_limit :: %{
    requests_per_minute: pos_integer(),
    tokens_per_minute: pos_integer(),
    tokens_per_day: pos_integer()
  }

  @type custom_endpoints :: %{
    chat: String.t(),
    completions: String.t(),
    embeddings: String.t(),
    models: String.t()
  }

  @type t :: %__MODULE__{
    provider_type: provider_type(),
    base_url: String.t(),
    api_key: String.t() | nil,
    organization_id: String.t() | nil,
    project_id: String.t() | nil,
    model: String.t() | nil,
    default_model: String.t(),
    supported_models: [String.t()],
    timeout: pos_integer(),
    max_retries: non_neg_integer(),
    rate_limit: rate_limit() | nil,
    headers: [{String.t(), String.t()}],
    custom_endpoints: custom_endpoints() | nil,
    api_version: String.t() | nil,
    region: String.t() | nil,
    environment: String.t(),
    metadata: map()
  }

  @default_timeout 30_000
  @default_max_retries 3

  @doc """
  Create OpenAI provider configuration.
  """
  def openai(opts \\ []) do
    %__MODULE__{
      provider_type: :openai,
      base_url: Keyword.get(opts, :base_url, "https://api.openai.com/v1"),
      api_key: Keyword.get(opts, :api_key),
      organization_id: Keyword.get(opts, :organization_id),
      project_id: Keyword.get(opts, :project_id),
      model: Keyword.get(opts, :model),
      default_model: Keyword.get(opts, :default_model, "gpt-3.5-turbo"),
      supported_models: Keyword.get(opts, :supported_models, default_openai_models()),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      rate_limit: Keyword.get(opts, :rate_limit),
      headers: Keyword.get(opts, :headers, []),
      custom_endpoints: Keyword.get(opts, :custom_endpoints),
      api_version: Keyword.get(opts, :api_version, "v1"),
      environment: Keyword.get(opts, :environment, "production"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create Anthropic provider configuration.
  """
  def anthropic(opts \\ []) do
    %__MODULE__{
      provider_type: :anthropic,
      base_url: Keyword.get(opts, :base_url, "https://api.anthropic.com"),
      api_key: Keyword.get(opts, :api_key),
      model: Keyword.get(opts, :model),
      default_model: Keyword.get(opts, :default_model, "claude-3-sonnet-20240229"),
      supported_models: Keyword.get(opts, :supported_models, default_anthropic_models()),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      rate_limit: Keyword.get(opts, :rate_limit),
      headers: Keyword.get(opts, :headers, []),
      custom_endpoints: Keyword.get(opts, :custom_endpoints),
      api_version: Keyword.get(opts, :api_version, "2023-06-01"),
      environment: Keyword.get(opts, :environment, "production"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create Azure OpenAI provider configuration.
  """
  def azure_openai(opts \\ []) do
    resource_name = Keyword.get(opts, :resource_name) || 
      raise ArgumentError, "resource_name is required for Azure OpenAI"
    
    deployment_id = Keyword.get(opts, :deployment_id) || 
      raise ArgumentError, "deployment_id is required for Azure OpenAI"

    base_url = "https://#{resource_name}.openai.azure.com/openai/deployments/#{deployment_id}"

    %__MODULE__{
      provider_type: :azure_openai,
      base_url: base_url,
      api_key: Keyword.get(opts, :api_key),
      model: deployment_id,
      default_model: deployment_id,
      supported_models: [deployment_id],
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      rate_limit: Keyword.get(opts, :rate_limit),
      headers: Keyword.get(opts, :headers, []),
      api_version: Keyword.get(opts, :api_version, "2023-12-01-preview"),
      environment: Keyword.get(opts, :environment, "production"),
      metadata: Map.merge(
        Keyword.get(opts, :metadata, %{}),
        %{resource_name: resource_name, deployment_id: deployment_id}
      )
    }
  end

  @doc """
  Create local/custom provider configuration.
  """
  def local(opts \\ []) do
    base_url = Keyword.get(opts, :base_url) || 
      raise ArgumentError, "base_url is required for local provider"

    %__MODULE__{
      provider_type: :local,
      base_url: base_url,
      api_key: Keyword.get(opts, :api_key),
      model: Keyword.get(opts, :model),
      default_model: Keyword.get(opts, :default_model, "local-model"),
      supported_models: Keyword.get(opts, :supported_models, ["local-model"]),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      rate_limit: Keyword.get(opts, :rate_limit),
      headers: Keyword.get(opts, :headers, []),
      custom_endpoints: Keyword.get(opts, :custom_endpoints),
      api_version: Keyword.get(opts, :api_version),
      environment: Keyword.get(opts, :environment, "local"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create custom provider configuration.
  """
  def custom(provider_type, opts \\ []) do
    base_url = Keyword.get(opts, :base_url) || 
      raise ArgumentError, "base_url is required for custom provider"

    %__MODULE__{
      provider_type: provider_type,
      base_url: base_url,
      api_key: Keyword.get(opts, :api_key),
      model: Keyword.get(opts, :model),
      default_model: Keyword.get(opts, :default_model, "custom-model"),
      supported_models: Keyword.get(opts, :supported_models, ["custom-model"]),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      rate_limit: Keyword.get(opts, :rate_limit),
      headers: Keyword.get(opts, :headers, []),
      custom_endpoints: Keyword.get(opts, :custom_endpoints),
      api_version: Keyword.get(opts, :api_version),
      environment: Keyword.get(opts, :environment, "custom"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Validate provider configuration.
  """
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_provider_type(config.provider_type),
         :ok <- validate_base_url(config.base_url),
         :ok <- validate_auth(config),
         :ok <- validate_models(config),
         :ok <- validate_rate_limit(config.rate_limit),
         :ok <- validate_timeouts(config) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_) do
    {:error, :invalid_config_structure}
  end

  @doc """
  Get the endpoint URL for a specific operation.
  """
  def get_endpoint_url(%__MODULE__{} = config, operation) do
    case get_custom_endpoint(config, operation) do
      nil -> build_default_endpoint(config, operation)
      custom_url -> custom_url
    end
  end

  @doc """
  Get authentication headers for the provider.
  """
  def get_auth_headers(%__MODULE__{provider_type: :openai, api_key: api_key}) when not is_nil(api_key) do
    [{"Authorization", "Bearer #{api_key}"}]
  end

  def get_auth_headers(%__MODULE__{provider_type: :anthropic, api_key: api_key}) when not is_nil(api_key) do
    [{"x-api-key", api_key}]
  end

  def get_auth_headers(%__MODULE__{provider_type: :azure_openai, api_key: api_key}) when not is_nil(api_key) do
    [{"api-key", api_key}]
  end

  def get_auth_headers(%__MODULE__{api_key: api_key}) when not is_nil(api_key) do
    [{"Authorization", "Bearer #{api_key}"}]
  end

  def get_auth_headers(_) do
    []
  end

  @doc """
  Get all HTTP headers for the provider.
  """
  def get_headers(%__MODULE__{} = config) do
    auth_headers = get_auth_headers(config)
    provider_headers = get_provider_specific_headers(config)
    custom_headers = config.headers || []
    
    auth_headers ++ provider_headers ++ custom_headers
  end

  @doc """
  Check if the provider supports a specific model.
  """
  def supports_model?(%__MODULE__{supported_models: models}, model) when is_list(models) do
    model in models
  end

  def supports_model?(_, _) do
    true  # If no supported models list, assume all models are supported
  end

  @doc """
  Get the model to use for requests.
  """
  def get_model(%__MODULE__{model: model}) when not is_nil(model) do
    model
  end

  def get_model(%__MODULE__{default_model: default_model}) do
    default_model
  end

  @doc """
  Load configuration from environment variables.
  """
  def from_env(provider_type) do
    case provider_type do
      :openai -> openai_from_env()
      :anthropic -> anthropic_from_env()
      :azure_openai -> azure_openai_from_env()
      :local -> local_from_env()
      _ -> {:error, :unsupported_provider_type}
    end
  end

  @doc """
  Load configuration from a file.
  """
  def from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Path.extname(file_path) do
          ".json" -> parse_json_config(content)
          ".yaml" -> parse_yaml_config(content)
          ".yml" -> parse_yaml_config(content)
          _ -> {:error, :unsupported_file_format}
        end
      
      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  # Private Functions

  defp validate_provider_type(provider_type) when provider_type in [:openai, :anthropic, :local, :azure_openai, :google, :cohere, :custom] do
    :ok
  end

  defp validate_provider_type(_) do
    {:error, :invalid_provider_type}
  end

  defp validate_base_url(nil) do
    {:error, :missing_base_url}
  end

  defp validate_base_url(url) when is_binary(url) do
    uri = URI.parse(url)
    if uri.scheme in ["http", "https"] and not is_nil(uri.host) do
      :ok
    else
      {:error, :invalid_base_url}
    end
  end

  defp validate_base_url(_) do
    {:error, :invalid_base_url}
  end

  defp validate_auth(%__MODULE__{provider_type: provider_type, api_key: api_key}) do
    case {provider_type, api_key} do
      {:local, _} -> :ok  # Local providers may not need API keys
      {_, nil} -> {:error, :missing_api_key}
      {_, key} when is_binary(key) -> :ok
      _ -> {:error, :invalid_api_key}
    end
  end

  defp validate_models(%__MODULE__{supported_models: models}) when is_list(models) do
    if Enum.all?(models, &is_binary/1) do
      :ok
    else
      {:error, :invalid_model_list}
    end
  end

  defp validate_models(_) do
    :ok
  end

  defp validate_rate_limit(nil) do
    :ok
  end

  defp validate_rate_limit(%{} = rate_limit) do
    required_keys = [:requests_per_minute]
    if Enum.all?(required_keys, &Map.has_key?(rate_limit, &1)) do
      :ok
    else
      {:error, :invalid_rate_limit}
    end
  end

  defp validate_rate_limit(_) do
    {:error, :invalid_rate_limit}
  end

  defp validate_timeouts(%__MODULE__{timeout: timeout, max_retries: max_retries}) do
    cond do
      not is_integer(timeout) or timeout <= 0 ->
        {:error, :invalid_timeout}
      
      not is_integer(max_retries) or max_retries < 0 ->
        {:error, :invalid_max_retries}
      
      true ->
        :ok
    end
  end

  defp get_custom_endpoint(%__MODULE__{custom_endpoints: nil}, _operation) do
    nil
  end

  defp get_custom_endpoint(%__MODULE__{custom_endpoints: endpoints}, operation) do
    Map.get(endpoints, operation)
  end

  defp build_default_endpoint(%__MODULE__{provider_type: :openai, base_url: base_url}, :chat) do
    "#{base_url}/chat/completions"
  end

  defp build_default_endpoint(%__MODULE__{provider_type: :openai, base_url: base_url}, :completions) do
    "#{base_url}/completions"
  end

  defp build_default_endpoint(%__MODULE__{provider_type: :openai, base_url: base_url}, :embeddings) do
    "#{base_url}/embeddings"
  end

  defp build_default_endpoint(%__MODULE__{provider_type: :anthropic, base_url: base_url}, :chat) do
    "#{base_url}/v1/messages"
  end

  defp build_default_endpoint(%__MODULE__{provider_type: :azure_openai, base_url: base_url, api_version: api_version}, operation) do
    operation_path = case operation do
      :chat -> "chat/completions"
      :completions -> "completions"
      :embeddings -> "embeddings"
    end
    
    "#{base_url}/#{operation_path}?api-version=#{api_version}"
  end

  defp build_default_endpoint(%__MODULE__{base_url: base_url}, operation) do
    "#{base_url}/#{operation}"
  end

  defp get_provider_specific_headers(%__MODULE__{provider_type: :anthropic, api_version: api_version}) when not is_nil(api_version) do
    [{"anthropic-version", api_version}]
  end

  defp get_provider_specific_headers(%__MODULE__{provider_type: :openai, organization_id: org_id}) when not is_nil(org_id) do
    [{"OpenAI-Organization", org_id}]
  end

  defp get_provider_specific_headers(_) do
    []
  end

  defp openai_from_env do
    with {:ok, api_key} <- get_env_var("OPENAI_API_KEY") do
      {:ok, openai([
        api_key: api_key,
        base_url: System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1"),
        organization_id: System.get_env("OPENAI_ORG_ID"),
        project_id: System.get_env("OPENAI_PROJECT_ID")
      ])}
    end
  end

  defp anthropic_from_env do
    with {:ok, api_key} <- get_env_var("ANTHROPIC_API_KEY") do
      {:ok, anthropic([
        api_key: api_key,
        base_url: System.get_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
      ])}
    end
  end

  defp azure_openai_from_env do
    with {:ok, api_key} <- get_env_var("AZURE_OPENAI_API_KEY"),
         {:ok, resource_name} <- get_env_var("AZURE_OPENAI_RESOURCE_NAME"),
         {:ok, deployment_id} <- get_env_var("AZURE_OPENAI_DEPLOYMENT_ID") do
      {:ok, azure_openai([
        api_key: api_key,
        resource_name: resource_name,
        deployment_id: deployment_id,
        api_version: System.get_env("AZURE_OPENAI_API_VERSION", "2023-12-01-preview")
      ])}
    end
  end

  defp local_from_env do
    with {:ok, base_url} <- get_env_var("LOCAL_LLM_BASE_URL") do
      {:ok, local([
        base_url: base_url,
        api_key: System.get_env("LOCAL_LLM_API_KEY"),
        model: System.get_env("LOCAL_LLM_MODEL", "local-model")
      ])}
    end
  end

  defp get_env_var(name) do
    case System.get_env(name) do
      nil -> {:error, {:missing_env_var, name}}
      value -> {:ok, value}
    end
  end

  defp parse_json_config(content) do
    case Jason.decode(content) do
      {:ok, data} -> config_from_map(data)
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp parse_yaml_config(content) do
    try do
      case YamlElixir.read_from_string(content) do
        {:ok, data} -> config_from_map(data)
        {:error, reason} -> {:error, {:yaml_parse_error, reason}}
      end
    rescue
      _ -> {:error, :yaml_parser_not_available}
    end
  end

  defp config_from_map(%{"provider_type" => "openai"} = data) do
    {:ok, openai(map_to_keywords(data))}
  end

  defp config_from_map(%{"provider_type" => "anthropic"} = data) do
    {:ok, anthropic(map_to_keywords(data))}
  end

  defp config_from_map(%{"provider_type" => "azure_openai"} = data) do
    {:ok, azure_openai(map_to_keywords(data))}
  end

  defp config_from_map(%{"provider_type" => "local"} = data) do
    {:ok, local(map_to_keywords(data))}
  end

  defp config_from_map(_) do
    {:error, :invalid_config_format}
  end

  defp map_to_keywords(map) do
    Enum.map(map, fn {k, v} ->
      {String.to_atom(k), v}
    end)
  end

  defp default_openai_models do
    [
      "gpt-4",
      "gpt-4-32k",
      "gpt-4-1106-preview",
      "gpt-4-0125-preview",
      "gpt-3.5-turbo",
      "gpt-3.5-turbo-16k",
      "gpt-3.5-turbo-1106",
      "text-davinci-003",
      "text-davinci-002"
    ]
  end

  defp default_anthropic_models do
    [
      "claude-3-opus-20240229",
      "claude-3-sonnet-20240229",
      "claude-3-haiku-20240307",
      "claude-2.1",
      "claude-2.0",
      "claude-instant-1.2"
    ]
  end
end