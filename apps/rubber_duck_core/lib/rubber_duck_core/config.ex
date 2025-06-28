defmodule RubberDuckCore.Config do
  @moduledoc """
  Configuration validation and helper functions for RubberDuck applications.
  """

  @doc """
  Validates that all required configuration keys are present and valid.
  Raises an error if any configuration is missing or invalid.
  """
  def validate! do
    validate_core_config!()
    validate_storage_config!()
    validate_engines_config!()
    validate_web_config!()
  end

  @doc """
  Gets a configuration value with a default fallback.
  """
  def get(app, key, default \\ nil) do
    Application.get_env(app, key, default)
  end

  @doc """
  Gets a required configuration value, raising if not found.
  """
  def get!(app, key) do
    case Application.get_env(app, key) do
      nil -> raise "Required configuration #{inspect(app)}.#{inspect(key)} is missing"
      value -> value
    end
  end

  # Private validation functions

  defp validate_core_config! do
    # Required configs
    get!(:rubber_duck_core, :ecto_repos)
    get!(:rubber_duck_core, :pubsub)
    
    # Validate values
    max_messages = get!(:rubber_duck_core, :max_conversation_messages)
    unless is_integer(max_messages) and max_messages > 0 do
      raise "max_conversation_messages must be a positive integer"
    end

    retention_days = get!(:rubber_duck_core, :conversation_retention_days)
    unless is_integer(retention_days) and retention_days > 0 do
      raise "conversation_retention_days must be a positive integer"
    end
  end

  defp validate_storage_config! do
    # Required configs
    get!(:rubber_duck_storage, :ecto_repos)
    
    # Validate cache settings
    cache_ttl = get!(:rubber_duck_storage, :cache_ttl)
    unless is_integer(cache_ttl) and cache_ttl > 0 do
      raise "cache_ttl must be a positive integer (milliseconds)"
    end

    cache_max_size = get!(:rubber_duck_storage, :cache_max_size)
    unless is_integer(cache_max_size) and cache_max_size > 0 do
      raise "cache_max_size must be a positive integer"
    end
  end

  defp validate_engines_config! do
    # Validate pool settings
    pool_size = get!(:rubber_duck_engines, :engine_pool_size)
    unless is_integer(pool_size) and pool_size > 0 do
      raise "engine_pool_size must be a positive integer"
    end

    timeout = get!(:rubber_duck_engines, :engine_timeout)
    unless is_integer(timeout) and timeout > 0 do
      raise "engine_timeout must be a positive integer (milliseconds)"
    end

    max_concurrent = get!(:rubber_duck_engines, :max_concurrent_analyses)
    unless is_integer(max_concurrent) and max_concurrent > 0 do
      raise "max_concurrent_analyses must be a positive integer"
    end

    # Validate engine configurations
    engines = get!(:rubber_duck_engines, :engines)
    unless is_list(engines) do
      raise "engines must be a keyword list"
    end

    Enum.each(engines, fn {engine_name, config} ->
      unless is_map(config) do
        raise "Engine #{engine_name} configuration must be a map"
      end

      unless is_boolean(config[:enabled]) do
        raise "Engine #{engine_name} must have an 'enabled' boolean field"
      end
    end)
  end

  defp validate_web_config! do
    # Validate endpoint configuration exists
    endpoint_config = get!(:rubber_duck_web, RubberDuckWeb.Endpoint)
    
    unless Keyword.keyword?(endpoint_config) do
      raise "RubberDuckWeb.Endpoint configuration must be a keyword list"
    end

    # In production, ensure secret_key_base is set
    if Mix.env() == :prod do
      secret_key = Keyword.get(endpoint_config, :secret_key_base)
      if is_nil(secret_key) or byte_size(secret_key) < 64 do
        raise "secret_key_base must be at least 64 characters in production"
      end
    end
  end
end