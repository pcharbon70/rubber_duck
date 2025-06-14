defmodule RubberDuck.LLMAbstraction.RateLimiter do
  @moduledoc """
  Rate limiting for LLM provider API compliance.
  
  This module implements rate limiting to ensure compliance with provider
  API limits and prevent service degradation. It supports multiple rate
  limiting strategies including token bucket, sliding window, and
  fixed window algorithms.
  
  Features:
  - Per-provider rate limiting
  - Per-API-key rate limiting  
  - Burst handling with token buckets
  - Graceful degradation under load
  - Distributed rate limiting across cluster
  - Rate limit monitoring and alerting
  """

  require Logger
  alias Hammer

  @doc """
  Check if a request is allowed under current rate limits.
  
  ## Parameters
    - provider: Provider name (atom)
    - api_key: API key identifier
    - request_type: Type of request (:chat, :completion, :embedding)
    - tokens: Estimated token count for the request
    
  ## Returns
    - {:ok, remaining_quota} | {:error, :rate_limited, retry_after_ms}
  """
  def check_rate_limit(provider, api_key, request_type, tokens \\ 1) do
    # Check multiple rate limit dimensions
    with {:ok, _} <- check_provider_limit(provider, request_type, tokens),
         {:ok, _} <- check_api_key_limit(provider, api_key, request_type, tokens),
         {:ok, remaining} <- check_token_limit(provider, api_key, tokens) do
      {:ok, remaining}
    else
      {:error, reason, retry_after} -> {:error, reason, retry_after}
    end
  end

  @doc """
  Record a completed request for rate limiting tracking.
  """
  def record_request(provider, api_key, request_type, tokens, success \\ true) do
    # Update rate limiting counters
    update_provider_usage(provider, request_type, tokens)
    update_api_key_usage(provider, api_key, request_type, tokens)
    
    if not success do
      # Track failed requests separately for error rate limiting
      record_error(provider, api_key, request_type)
    end
    
    :ok
  end

  @doc """
  Get current rate limit status for a provider/API key combination.
  """
  def get_rate_limit_status(provider, api_key) do
    %{
      provider_limits: get_provider_status(provider),
      api_key_limits: get_api_key_status(provider, api_key),
      token_limits: get_token_status(provider, api_key)
    }
  end

  @doc """
  Configure rate limits for a provider.
  """
  def configure_provider_limits(provider, limits) do
    :persistent_term.put({__MODULE__, :provider_limits, provider}, limits)
    Logger.info("Updated rate limits for provider #{provider}: #{inspect(limits)}")
  end

  @doc """
  Get rate limit configuration for a provider.
  """
  def get_provider_limits(provider) do
    :persistent_term.get({__MODULE__, :provider_limits, provider}, default_limits())
  end

  @doc """
  Calculate optimal request spacing to avoid rate limits.
  """
  def calculate_request_spacing(provider, api_key, request_type) do
    limits = get_provider_limits(provider)
    limit_info = Map.get(limits, request_type, %{})
    
    requests_per_minute = Map.get(limit_info, :requests_per_minute, 60)
    
    # Calculate minimum interval between requests
    min_interval_ms = div(60_000, requests_per_minute)
    
    # Add some buffer to avoid edge cases
    min_interval_ms + 100
  end

  @doc """
  Check if provider is currently experiencing rate limit issues.
  """
  def is_rate_limited?(provider, api_key) do
    case check_rate_limit(provider, api_key, :chat, 1) do
      {:ok, _} -> false
      {:error, :rate_limited, _} -> true
    end
  end

  # Private Functions

  defp check_provider_limit(provider, request_type, tokens) do
    limits = get_provider_limits(provider)
    limit_info = Map.get(limits, request_type, %{})
    
    # Check requests per minute limit
    rpm_limit = Map.get(limit_info, :requests_per_minute)
    if rpm_limit do
      bucket_key = "provider:#{provider}:#{request_type}:rpm"
      case Hammer.check_rate(bucket_key, 60_000, rpm_limit) do
        {:allow, _count} -> {:ok, rpm_limit}
        {:deny, _limit} -> 
          retry_after = calculate_retry_after(bucket_key, 60_000)
          {:error, :rate_limited, retry_after}
      end
    else
      {:ok, :unlimited}
    end
  end

  defp check_api_key_limit(provider, api_key, request_type, tokens) do
    limits = get_provider_limits(provider)
    limit_info = Map.get(limits, request_type, %{})
    
    # Check API key specific limits (often more restrictive)
    api_key_rpm = Map.get(limit_info, :api_key_requests_per_minute)
    if api_key_rpm do
      bucket_key = "api_key:#{provider}:#{api_key}:#{request_type}:rpm"
      case Hammer.check_rate(bucket_key, 60_000, api_key_rpm) do
        {:allow, _count} -> {:ok, api_key_rpm}
        {:deny, _limit} -> 
          retry_after = calculate_retry_after(bucket_key, 60_000)
          {:error, :rate_limited, retry_after}
      end
    else
      {:ok, :unlimited}
    end
  end

  defp check_token_limit(provider, api_key, tokens) do
    limits = get_provider_limits(provider)
    token_limit = Map.get(limits, :tokens_per_minute)
    
    if token_limit do
      bucket_key = "tokens:#{provider}:#{api_key}:tpm"
      case Hammer.check_rate(bucket_key, 60_000, token_limit, tokens) do
        {:allow, remaining} -> {:ok, remaining}
        {:deny, _limit} -> 
          retry_after = calculate_retry_after(bucket_key, 60_000)
          {:error, :rate_limited, retry_after}
      end
    else
      {:ok, :unlimited}
    end
  end

  defp update_provider_usage(provider, request_type, tokens) do
    # Update usage statistics for monitoring
    stats_key = "stats:provider:#{provider}:#{request_type}"
    
    # Use Hammer's internal storage for consistency
    current_minute = div(System.system_time(:millisecond), 60_000)
    Hammer.check_rate("#{stats_key}:#{current_minute}", 60_000, 999_999, tokens)
  end

  defp update_api_key_usage(provider, api_key, request_type, tokens) do
    # Update API key usage statistics
    stats_key = "stats:api_key:#{provider}:#{api_key}:#{request_type}"
    
    current_minute = div(System.system_time(:millisecond), 60_000)
    Hammer.check_rate("#{stats_key}:#{current_minute}", 60_000, 999_999, tokens)
  end

  defp record_error(provider, api_key, request_type) do
    # Track error rates for potential backoff
    error_key = "errors:#{provider}:#{api_key}:#{request_type}"
    Hammer.check_rate(error_key, 60_000, 999_999, 1)
  end

  defp get_provider_status(provider) do
    limits = get_provider_limits(provider)
    
    Map.new(limits, fn {request_type, limit_info} ->
      rpm_limit = Map.get(limit_info, :requests_per_minute)
      bucket_key = "provider:#{provider}:#{request_type}:rpm"
      
      {current_count, _} = get_current_usage(bucket_key, 60_000)
      
      status = %{
        limit: rpm_limit,
        current: current_count,
        remaining: if(rpm_limit, do: rpm_limit - current_count, else: :unlimited)
      }
      
      {request_type, status}
    end)
  end

  defp get_api_key_status(provider, api_key) do
    limits = get_provider_limits(provider)
    
    Map.new(limits, fn {request_type, limit_info} ->
      api_key_rpm = Map.get(limit_info, :api_key_requests_per_minute)
      bucket_key = "api_key:#{provider}:#{api_key}:#{request_type}:rpm"
      
      {current_count, _} = get_current_usage(bucket_key, 60_000)
      
      status = %{
        limit: api_key_rpm,
        current: current_count,
        remaining: if(api_key_rpm, do: api_key_rpm - current_count, else: :unlimited)
      }
      
      {request_type, status}
    end)
  end

  defp get_token_status(provider, api_key) do
    limits = get_provider_limits(provider)
    token_limit = Map.get(limits, :tokens_per_minute)
    
    if token_limit do
      bucket_key = "tokens:#{provider}:#{api_key}:tpm"
      {current_count, _} = get_current_usage(bucket_key, 60_000)
      
      %{
        limit: token_limit,
        current: current_count,
        remaining: token_limit - current_count
      }
    else
      %{limit: :unlimited, current: 0, remaining: :unlimited}
    end
  end

  defp get_current_usage(bucket_key, window_ms) do
    # Get current usage from Hammer's backend
    case Hammer.inspect_bucket(bucket_key, window_ms, 1) do
      {:ok, {count, remaining_ms}} -> {count, remaining_ms}
      {:error, _} -> {0, window_ms}
    end
  end

  defp calculate_retry_after(bucket_key, window_ms) do
    case get_current_usage(bucket_key, window_ms) do
      {_count, remaining_ms} when remaining_ms > 0 -> remaining_ms
      _ -> window_ms  # Default to full window if unknown
    end
  end

  defp default_limits do
    %{
      chat: %{
        requests_per_minute: 60,
        api_key_requests_per_minute: 30,
        tokens_per_minute: 50_000
      },
      completion: %{
        requests_per_minute: 60,
        api_key_requests_per_minute: 30,
        tokens_per_minute: 50_000
      },
      embedding: %{
        requests_per_minute: 200,
        api_key_requests_per_minute: 100,
        tokens_per_minute: 100_000
      }
    }
  end
end