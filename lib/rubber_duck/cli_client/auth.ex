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
    
    config = %{
      "api_key" => api_key,
      "server_url" => server_url,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    case Jason.encode(config, pretty: true) do
      {:ok, json} ->
        File.write(@config_file, json)
        
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
    case File.rm(@config_file) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @doc """
  Check if credentials are configured.
  """
  def configured? do
    get_api_key() != nil
  end

  # Private functions

  defp load_config do
    case File.read(@config_file) do
      {:ok, content} ->
        Jason.decode(content)
        
      {:error, :enoent} ->
        {:error, :not_configured}
        
      error ->
        error
    end
  end

  defp ensure_config_dir do
    File.mkdir_p!(@config_dir)
  end
end