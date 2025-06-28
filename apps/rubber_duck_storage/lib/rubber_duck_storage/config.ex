defmodule RubberDuckStorage.Config do
  @moduledoc """
  Configuration helpers for the storage application.
  """

  @doc """
  Gets the cache TTL in milliseconds.
  """
  def cache_ttl do
    Application.get_env(:rubber_duck_storage, :cache_ttl, :timer.hours(1))
  end

  @doc """
  Gets the maximum cache size.
  """
  def cache_max_size do
    Application.get_env(:rubber_duck_storage, :cache_max_size, 1000)
  end

  @doc """
  Checks if query logging is enabled.
  """
  def log_queries? do
    Application.get_env(:rubber_duck_storage, :log_queries, false)
  end

  @doc """
  Gets the Ecto repository module.
  """
  def repo do
    case Application.get_env(:rubber_duck_storage, :ecto_repos, []) do
      [repo | _] -> repo
      [] -> raise "No Ecto repository configured for rubber_duck_storage"
    end
  end

  @doc """
  Gets database pool configuration.
  """
  def pool_config do
    repo_config = Application.get_env(:rubber_duck_storage, repo())
    
    %{
      size: Keyword.get(repo_config, :pool_size, 10),
      timeout: Keyword.get(repo_config, :ownership_timeout, 60_000),
      queue_target: Keyword.get(repo_config, :queue_target, 5_000),
      queue_interval: Keyword.get(repo_config, :queue_interval, 10_000)
    }
  end
end