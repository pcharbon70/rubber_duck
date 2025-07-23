defmodule RubberDuck.Projects.FileCacheWrapper do
  @moduledoc """
  Wrapper module that adds CacheStats integration to the existing FileCache.
  
  This module wraps the FileCache operations to track statistics without
  modifying the original FileCache implementation.
  """
  
  alias RubberDuck.Projects.FileCache
  alias RubberDuck.Projects.CacheStats
  
  @doc """
  Gets a value from the cache with statistics tracking.
  """
  def get(project_id, path) do
    result = FileCache.get(project_id, path)
    
    case result do
      {:ok, value} ->
        size = estimate_size(value)
        CacheStats.record_hit(project_id, path, size)
        {:ok, value}
        
      :miss ->
        CacheStats.record_miss(project_id, path)
        :miss
    end
  end
  
  @doc """
  Puts a value in the cache with statistics tracking.
  """
  def put(project_id, path, value, opts \\ []) do
    size = estimate_size(value)
    result = FileCache.put(project_id, path, value, opts)
    
    if result == :ok do
      CacheStats.record_put(project_id, path, size)
    end
    
    result
  end
  
  @doc """
  Invalidates a cache entry with statistics tracking.
  """
  def invalidate(project_id, path) do
    # Try to get the size before deletion
    size = case FileCache.get(project_id, path) do
      {:ok, value} -> estimate_size(value)
      :miss -> 0
    end
    
    result = FileCache.invalidate(project_id, path)
    
    if result == :ok and size > 0 do
      CacheStats.record_delete(project_id, path, size)
    end
    
    result
  end
  
  @doc """
  Invalidates all cache entries for a project with statistics tracking.
  """
  def invalidate_project(project_id) do
    # We can't track individual deletions here, so just clear the project
    result = FileCache.invalidate_project(project_id)
    
    # Reset stats for the project
    CacheStats.reset_stats(project_id)
    
    result
  end
  
  @doc """
  Gets cache statistics from both FileCache and CacheStats.
  """
  def get_combined_stats(project_id \\ :all) do
    file_cache_stats = FileCache.stats()
    cache_stats = case CacheStats.get_stats(project_id) do
      {:ok, stats} -> stats
      _ -> %{}
    end
    
    Map.merge(file_cache_stats, cache_stats)
  end
  
  @doc """
  Delegates all other functions to FileCache.
  """
  defdelegate invalidate_pattern(project_id, pattern), to: FileCache
  defdelegate clear(), to: FileCache
  defdelegate stats(), to: FileCache
  
  # Private functions
  
  defp estimate_size(value) do
    :erlang.external_size(value)
  end
end