defmodule RubberDuck.Nebulex.Cache do
  @moduledoc """
  Multi-tier cache implementation using Nebulex.
  
  Provides L1 (Local) and L2 (Replicated) caches with multilevel coordination
  for optimal performance in distributed AI workloads.
  """
  
  use Nebulex.Cache,
    otp_app: :rubber_duck,
    adapter: Nebulex.Adapters.Multilevel
  
  alias __MODULE__.{L1, L2}
  
  @doc """
  Gets a value from the cache, checking L1 first, then L2
  """
  def get_from(cache_level, key, opts \\ []) do
    case cache_level do
      :l1 -> L1.get(key, opts)
      :l2 -> L2.get(key, opts) 
      :multilevel -> __MODULE__.get(key, opts)
    end
  end
  
  @doc """
  Puts a value in the cache with appropriate replication
  """
  def put_in(cache_level, key, value, opts \\ []) do
    case cache_level do
      :l1 -> L1.put(key, value, opts)
      :l2 -> L2.put(key, value, opts)
      :multilevel -> __MODULE__.put(key, value, opts)
    end
  end
  
  @doc """
  Deletes a key from the cache with cascade to all levels
  """
  def delete_from(cache_level, key, opts \\ []) do
    case cache_level do
      :l1 -> L1.delete(key, opts)
      :l2 -> L2.delete(key, opts)
      :multilevel -> 
        L1.delete(key, opts)
        L2.delete(key, opts)
        __MODULE__.delete(key, opts)
    end
  end
  
  @doc """
  Gets cache statistics for monitoring
  """
  def cache_stats(cache_level \\ :multilevel) do
    case cache_level do
      :l1 -> L1.stats()
      :l2 -> L2.stats()
      :multilevel -> 
        %{
          l1: L1.stats(),
          l2: L2.stats(),
          multilevel: __MODULE__.stats()
        }
    end
  end
end