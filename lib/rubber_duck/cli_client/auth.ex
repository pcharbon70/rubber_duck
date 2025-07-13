defmodule RubberDuck.CLIClient.Auth do
  @moduledoc """
  Authentication management for RubberDuck CLI client.

  Handles API key storage, retrieval, and validation.
  """

  @config_dir Path.expand("~/.rubber_duck")
  @config_file Path.join(@config_dir, "config.json")
  @key_length 32

  @doc """
  Get the stored API key.
  """
  def get_api_key do
    case load_config() do
      {:ok, config} ->
        config["api_key"]

      {:error, _} ->
        nil
    end
  end

  @doc """
  Get the stored server URL.
  """
  def get_server_url do
    case load_config() do
      {:ok, config} ->
        config["server_url"] || "ws://localhost:5555/socket/websocket"

      {:error, _} ->
        "ws://localhost:5555/socket/websocket"
    end
  end

  @doc """
  Store API key and server URL.
  """
  def save_credentials(api_key, server_url) do
    ensure_config_dir()

    # Load existing config to preserve other settings
    existing_config = case load_config() do
      {:ok, config} -> config
      {:error, _} -> %{}
    end

    config = existing_config
    |> Map.put("api_key", api_key)
    |> Map.put("server_url", server_url)
    |> Map.put("created_at", DateTime.utc_now() |> DateTime.to_iso8601())

    case Jason.encode(config, pretty: true) do
      {:ok, json} ->
        config_file = Process.get(:rubber_duck_config_file) || @config_file
        File.write(config_file, json)

      error ->
        error
    end
  end

  @doc """
  Generate a new API key.
  """
  def generate_api_key do
    :crypto.strong_rand_bytes(@key_length)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Clear stored credentials.
  """
  def clear_credentials do
    config_file = Process.get(:rubber_duck_config_file) || @config_file
    case File.rm(config_file) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc """
  Get the user ID derived from the API key.
  """
  def get_user_id do
    case get_api_key() do
      nil -> "cli_user_anonymous"
      api_key -> "cli_user_#{String.slice(api_key, 0, 8)}"
    end
  end

  @doc """
  Check if credentials are configured.
  """
  def configured? do
    get_api_key() != nil
  end

  @doc """
  Get the LLM configuration from the config file.
  """
  def get_llm_config do
    case load_config() do
      {:ok, config} ->
        config["llm"]

      {:error, _} ->
        nil
    end
  end

  @doc """
  Save LLM settings to the config file.
  """
  def save_llm_settings(llm_settings) do
    ensure_config_dir()

    # Load existing config to preserve other settings
    existing_config = case load_config() do
      {:ok, config} -> config
      {:error, _} -> %{}
    end

    config = existing_config
    |> Map.put("llm", llm_settings)
    |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

    case Jason.encode(config, pretty: true) do
      {:ok, json} ->
        config_file = Process.get(:rubber_duck_config_file) || @config_file
        File.write(config_file, json)

      error ->
        error
    end
  end

  @doc """
  Update the model for a specific provider.
  """
  def update_provider_model(provider, model) do
    ensure_config_dir()

    # Load existing config
    existing_config = case load_config() do
      {:ok, config} -> config
      {:error, _} -> %{}
    end

    # Get existing LLM config or create new one
    llm_config = existing_config["llm"] || %{
      "providers" => %{}
    }

    # Update the provider model
    updated_providers = llm_config["providers"]
    |> Map.put(provider, %{"model" => model})

    updated_llm = llm_config
    |> Map.put("providers", updated_providers)

    # If this provider becomes the default, update default_model too
    final_llm = if llm_config["default_provider"] == provider do
      Map.put(updated_llm, "default_model", model)
    else
      updated_llm
    end

    # Save back to config
    save_llm_settings(final_llm)
  end

  @doc """
  Set the default provider.
  """
  def set_default_provider(provider) do
    ensure_config_dir()

    # Load existing config
    existing_config = case load_config() do
      {:ok, config} -> config
      {:error, _} -> %{}
    end

    # Get existing LLM config or create new one
    llm_config = existing_config["llm"] || %{
      "providers" => %{}
    }

    # Get the model for this provider if configured
    provider_model = try do
      llm_config["providers"][provider]["model"]
    rescue
      _ -> nil
    end

    updated_llm = llm_config
    |> Map.put("default_provider", provider)
    |> Map.put("default_model", provider_model || "")

    # Save back to config
    save_llm_settings(updated_llm)
  end

  @doc """
  Get the current model for the default provider or a specific provider.
  """
  def get_current_model(provider \\ nil) do
    llm_config = get_llm_config()

    if llm_config do
      if provider do
        # Get model for specific provider
        model = try do
          llm_config["providers"][provider]["model"]
        rescue
          _ -> nil
        end
        {provider, model}
      else
        # Get default provider and model
        default_provider = llm_config["default_provider"]
        default_model = llm_config["default_model"]
        {default_provider, default_model}
      end
    else
      {provider, nil}
    end
  end

  # Private functions

  defp load_config do
    # Check for test config override
    config_file = Process.get(:rubber_duck_config_file) || @config_file
    
    case File.read(config_file) do
      {:ok, content} ->
        Jason.decode(content)

      {:error, :enoent} ->
        {:error, :not_configured}

      error ->
        error
    end
  end

  defp ensure_config_dir do
    # Check for test config override
    config_dir = Process.get(:rubber_duck_config_dir) || @config_dir
    File.mkdir_p!(config_dir)
  end
end
