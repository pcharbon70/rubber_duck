defmodule Hammer do
  @moduledoc """
  Simple rate limiting stub implementation using Cachex.
  
  This module provides a compatible interface to Hammer for basic rate limiting
  functionality using the already available Cachex cache.
  """
  
  require Logger
  
  @cache_name RubberDuck.Nebulex.Cache
  
  @doc """
  Check if request is allowed under rate limit.
  
  Returns:
  - `{:allow, count}` if allowed
  - `{:deny, remaining_ms}` if denied
  """
  def check_rate(bucket_key, window_ms, limit, increment \\ 1) do
    current_time = System.monotonic_time(:millisecond)
    window_start = div(current_time, window_ms) * window_ms
    cache_key = "rate_limit:#{bucket_key}:#{window_start}"
    
    try do
      # Get current count
      current_count = @cache_name.get(cache_key, 0)
      new_count = current_count + increment
      
      if new_count <= limit do
        # Allow request and update count
        @cache_name.put(cache_key, new_count, ttl: window_ms)
        {:allow, new_count}
      else
        # Deny request
        remaining_ms = window_start + window_ms - current_time
        {:deny, remaining_ms}
      end
    catch
      _, _ ->
        # If cache fails, allow request but log warning
        Logger.warning("Rate limiting cache failure for #{bucket_key}, allowing request")
        {:allow, 1}
    end
  end
  
  @doc """
  Increment rate counter without checking limit.
  
  Returns:
  - `{:allow, count}` always (stub implementation)
  """
  def check_rate_inc(bucket_key, window_ms, _limit, increment) do
    current_time = System.monotonic_time(:millisecond)
    window_start = div(current_time, window_ms) * window_ms
    cache_key = "rate_limit:#{bucket_key}:#{window_start}"
    
    try do
      current_count = @cache_name.get(cache_key, 0)
      new_count = current_count + increment
      @cache_name.put(cache_key, new_count, ttl: window_ms)
      {:allow, new_count}
    catch
      _, _ ->
        Logger.warning("Rate limiting cache failure for #{bucket_key}, allowing increment")
        {:allow, increment}
    end
  end
  
  @doc """
  Inspect bucket state.
  
  Returns:
  - `{:ok, count}` with current count
  - `{:error, reason}` on failure
  """
  def inspect_bucket(bucket_key, window_ms, _limit) do
    current_time = System.monotonic_time(:millisecond)
    window_start = div(current_time, window_ms) * window_ms
    cache_key = "rate_limit:#{bucket_key}:#{window_start}"
    
    try do
      current_count = @cache_name.get(cache_key, 0)
      {:ok, current_count}
    catch
      _, reason ->
        {:error, reason}
    end
  end
  
  # Backend configuration stub
  defmodule Backend do
    defmodule ETS do
      def new(_opts), do: :ok
    end
  end
end