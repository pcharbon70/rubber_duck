defmodule RubberDuck.LoadBalancing.RateLimiter do
  @moduledoc """
  Rate limiting implementation using Hammer for provider API compliance.
  
  This module provides distributed rate limiting capabilities to ensure
  compliance with provider API rate limits while supporting multiple
  limiting strategies including per-provider, per-user, and global limits.
  """
  
  use GenServer
  require Logger
  
  @type limit_scope :: :global | :provider | :user | :session
  @type limit_config :: %{
    scope: limit_scope(),
    provider_id: term() | nil,
    user_id: String.t() | nil,
    session_id: String.t() | nil,
    limit: non_neg_integer(),
    window_ms: non_neg_integer(),
    strategy: :token_bucket | :sliding_window | :fixed_window
  }
  
  @type rate_limit_result :: 
    {:ok, %{allowed: boolean(), remaining: non_neg_integer(), reset_time: non_neg_integer()}} |
    {:error, term()}
  
  @default_provider_limits %{
    openai: %{requests_per_minute: 3000, tokens_per_minute: 250_000},
    anthropic: %{requests_per_minute: 1000, tokens_per_minute: 100_000},
    cohere: %{requests_per_minute: 500, tokens_per_minute: 50_000}
  }
  
  @default_user_limits %{
    free: %{requests_per_hour: 100, tokens_per_hour: 10_000},
    premium: %{requests_per_hour: 1000, tokens_per_hour: 100_000},
    enterprise: %{requests_per_hour: 10_000, tokens_per_hour: 1_000_000}
  }
  
  # Client API
  
  @doc """
  Start the RateLimiter GenServer.
  
  ## Examples
  
      {:ok, pid} = RateLimiter.start_link()
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Check if a request is allowed under rate limits.
  
  ## Examples
  
      {:ok, %{allowed: true, remaining: 99}} = RateLimiter.check_rate_limit(:openai, %{
        user_id: "user123",
        estimated_tokens: 100
      })
      
      {:ok, %{allowed: false, remaining: 0, reset_time: 1234567890}} = RateLimiter.check_rate_limit(:openai, %{
        user_id: "user123",
        estimated_tokens: 100
      })
  """
  def check_rate_limit(provider_id, request_params) do
    GenServer.call(__MODULE__, {:check_rate_limit, provider_id, request_params})
  end
  
  @doc """
  Record a completed request for rate limiting tracking.
  
  ## Examples
  
      :ok = RateLimiter.record_request(:openai, %{
        user_id: "user123",
        tokens_used: 150,
        success: true
      })
  """
  def record_request(provider_id, request_info) do
    GenServer.cast(__MODULE__, {:record_request, provider_id, request_info})
  end
  
  @doc """
  Get current rate limit status for a provider and user.
  
  ## Examples
  
      status = RateLimiter.get_status(:openai, "user123")
      # %{
      #   provider_requests_remaining: 2999,
      #   user_requests_remaining: 99,
      #   provider_tokens_remaining: 249900,
      #   user_tokens_remaining: 9900
      # }
  """
  def get_status(provider_id, user_id \\ nil) do
    GenServer.call(__MODULE__, {:get_status, provider_id, user_id})
  end
  
  @doc """
  Update provider rate limits dynamically.
  
  ## Examples
  
      :ok = RateLimiter.update_provider_limits(:openai, %{
        requests_per_minute: 5000,
        tokens_per_minute: 500_000
      })
  """
  def update_provider_limits(provider_id, new_limits) do
    GenServer.call(__MODULE__, {:update_provider_limits, provider_id, new_limits})
  end
  
  @doc """
  Get comprehensive rate limiting statistics.
  
  ## Examples
  
      stats = RateLimiter.get_stats()
      # %{
      #   total_requests_checked: 10000,
      #   total_requests_blocked: 150,
      #   provider_stats: %{...},
      #   user_tier_stats: %{...}
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    provider_limits = Keyword.get(opts, :provider_limits, @default_provider_limits)
    user_limits = Keyword.get(opts, :user_limits, @default_user_limits)
    
    # Initialize Hammer backends
    :ok = setup_hammer_backends()
    
    state = %{
      provider_limits: provider_limits,
      user_limits: user_limits,
      stats: %{
        total_requests_checked: 0,
        total_requests_blocked: 0,
        requests_by_provider: %{},
        requests_by_user_tier: %{}
      }
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_rate_limit, provider_id, request_params}, _from, state) do
    user_id = Map.get(request_params, :user_id)
    session_id = Map.get(request_params, :session_id)
    estimated_tokens = Map.get(request_params, :estimated_tokens, 100)
    user_tier = Map.get(request_params, :user_tier, :free)
    
    # Check all applicable rate limits
    checks = [
      check_provider_request_limit(provider_id, state),
      check_provider_token_limit(provider_id, estimated_tokens, state),
      check_user_request_limit(user_id, user_tier, state),
      check_user_token_limit(user_id, user_tier, estimated_tokens, state),
      check_session_limit(session_id, state)
    ]
    
    # Find the most restrictive limit
    result = aggregate_limit_checks(checks)
    
    # Update stats
    updated_state = update_check_stats(state, provider_id, user_tier, result)
    
    {:reply, {:ok, result}, updated_state}
  end
  
  @impl true
  def handle_call({:get_status, provider_id, user_id}, _from, state) do
    status = %{
      provider_requests_remaining: get_remaining_requests(provider_id, :provider, state),
      provider_tokens_remaining: get_remaining_tokens(provider_id, :provider, state),
      user_requests_remaining: if(user_id, do: get_remaining_requests(user_id, :user, state), else: nil),
      user_tokens_remaining: if(user_id, do: get_remaining_tokens(user_id, :user, state), else: nil),
      global_requests_remaining: get_remaining_requests(:global, :global, state)
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:update_provider_limits, provider_id, new_limits}, _from, state) do
    updated_provider_limits = Map.put(state.provider_limits, provider_id, new_limits)
    updated_state = %{state | provider_limits: updated_provider_limits}
    
    Logger.info("Updated rate limits for provider #{provider_id}: #{inspect(new_limits)}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
  
  @impl true
  def handle_cast({:record_request, provider_id, request_info}, state) do
    user_id = Map.get(request_info, :user_id)
    tokens_used = Map.get(request_info, :tokens_used, 100)
    success = Map.get(request_info, :success, true)
    
    if success do
      # Record successful request for rate limiting
      :ok = record_provider_usage(provider_id, tokens_used)
      if user_id, do: record_user_usage(user_id, tokens_used)
    end
    
    # Update usage stats
    updated_state = update_usage_stats(state, provider_id, request_info)
    
    {:noreply, updated_state}
  end
  
  # Private Functions
  
  defp setup_hammer_backends do
    # Configure Hammer for distributed rate limiting
    # Using ETS backend for simplicity, but could use Redis for true distribution
    Application.put_env(:hammer, :backend, {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2, cleanup_interval_ms: 60_000]})
    :ok
  end
  
  defp check_provider_request_limit(provider_id, state) do
    limits = Map.get(state.provider_limits, provider_id, %{})
    requests_per_minute = Map.get(limits, :requests_per_minute, 1000)
    
    bucket_key = "provider:#{provider_id}:requests"
    
    case Hammer.check_rate(bucket_key, 60_000, requests_per_minute) do
      {:allow, count} ->
        {:ok, %{allowed: true, remaining: requests_per_minute - count, scope: :provider_requests}}
      
      {:deny, limit} ->
        reset_time = get_bucket_reset_time(bucket_key)
        {:ok, %{allowed: false, remaining: 0, reset_time: reset_time, scope: :provider_requests}}
      
      {:error, reason} ->
        Logger.error("Rate limit check failed for #{bucket_key}: #{inspect(reason)}")
        {:ok, %{allowed: true, remaining: requests_per_minute, scope: :provider_requests}}
    end
  end
  
  defp check_provider_token_limit(provider_id, estimated_tokens, state) do
    limits = Map.get(state.provider_limits, provider_id, %{})
    tokens_per_minute = Map.get(limits, :tokens_per_minute, 100_000)
    
    bucket_key = "provider:#{provider_id}:tokens"
    
    case Hammer.check_rate(bucket_key, 60_000, tokens_per_minute) do
      {:allow, count} ->
        remaining = tokens_per_minute - count
        if remaining >= estimated_tokens do
          {:ok, %{allowed: true, remaining: remaining, scope: :provider_tokens}}
        else
          reset_time = get_bucket_reset_time(bucket_key)
          {:ok, %{allowed: false, remaining: remaining, reset_time: reset_time, scope: :provider_tokens}}
        end
      
      {:deny, _limit} ->
        reset_time = get_bucket_reset_time(bucket_key)
        {:ok, %{allowed: false, remaining: 0, reset_time: reset_time, scope: :provider_tokens}}
      
      {:error, reason} ->
        Logger.error("Token rate limit check failed for #{bucket_key}: #{inspect(reason)}")
        {:ok, %{allowed: true, remaining: tokens_per_minute, scope: :provider_tokens}}
    end
  end
  
  defp check_user_request_limit(nil, _user_tier, _state), do: {:ok, %{allowed: true, remaining: 999999, scope: :user_requests}}
  defp check_user_request_limit(user_id, user_tier, state) do
    limits = Map.get(state.user_limits, user_tier, %{})
    requests_per_hour = Map.get(limits, :requests_per_hour, 100)
    
    bucket_key = "user:#{user_id}:requests"
    
    case Hammer.check_rate(bucket_key, 60_000 * 60, requests_per_hour) do
      {:allow, count} ->
        {:ok, %{allowed: true, remaining: requests_per_hour - count, scope: :user_requests}}
      
      {:deny, _limit} ->
        reset_time = get_bucket_reset_time(bucket_key)
        {:ok, %{allowed: false, remaining: 0, reset_time: reset_time, scope: :user_requests}}
      
      {:error, reason} ->
        Logger.error("User rate limit check failed for #{bucket_key}: #{inspect(reason)}")
        {:ok, %{allowed: true, remaining: requests_per_hour, scope: :user_requests}}
    end
  end
  
  defp check_user_token_limit(nil, _user_tier, _estimated_tokens, _state), do: {:ok, %{allowed: true, remaining: 999999, scope: :user_tokens}}
  defp check_user_token_limit(user_id, user_tier, estimated_tokens, state) do
    limits = Map.get(state.user_limits, user_tier, %{})
    tokens_per_hour = Map.get(limits, :tokens_per_hour, 10_000)
    
    bucket_key = "user:#{user_id}:tokens"
    
    case Hammer.check_rate(bucket_key, 60_000 * 60, tokens_per_hour) do
      {:allow, count} ->
        remaining = tokens_per_hour - count
        if remaining >= estimated_tokens do
          {:ok, %{allowed: true, remaining: remaining, scope: :user_tokens}}
        else
          reset_time = get_bucket_reset_time(bucket_key)
          {:ok, %{allowed: false, remaining: remaining, reset_time: reset_time, scope: :user_tokens}}
        end
      
      {:deny, _limit} ->
        reset_time = get_bucket_reset_time(bucket_key)
        {:ok, %{allowed: false, remaining: 0, reset_time: reset_time, scope: :user_tokens}}
      
      {:error, reason} ->
        Logger.error("User token limit check failed for #{bucket_key}: #{inspect(reason)}")
        {:ok, %{allowed: true, remaining: tokens_per_hour, scope: :user_tokens}}
    end
  end
  
  defp check_session_limit(nil, _state), do: {:ok, %{allowed: true, remaining: 999999, scope: :session}}
  defp check_session_limit(session_id, _state) do
    # Prevent session abuse with basic session limits
    bucket_key = "session:#{session_id}:requests"
    requests_per_minute = 100  # Conservative session limit
    
    case Hammer.check_rate(bucket_key, 60_000, requests_per_minute) do
      {:allow, count} ->
        {:ok, %{allowed: true, remaining: requests_per_minute - count, scope: :session}}
      
      {:deny, _limit} ->
        reset_time = get_bucket_reset_time(bucket_key)
        {:ok, %{allowed: false, remaining: 0, reset_time: reset_time, scope: :session}}
      
      {:error, reason} ->
        Logger.error("Session rate limit check failed for #{bucket_key}: #{inspect(reason)}")
        {:ok, %{allowed: true, remaining: requests_per_minute, scope: :session}}
    end
  end
  
  defp aggregate_limit_checks(checks) do
    # Find the most restrictive limit (first one that denies)
    case Enum.find(checks, fn {:ok, result} -> not result.allowed end) do
      nil ->
        # All checks passed, return the most restrictive remaining count
        {:ok, most_restrictive} = Enum.min_by(checks, fn {:ok, result} -> result.remaining end)
        most_restrictive
      
      {:ok, denied_result} ->
        denied_result
    end
  end
  
  defp get_bucket_reset_time(bucket_key) do
    # Estimate reset time based on bucket window
    # In a real implementation, this would query Hammer for exact reset time
    System.system_time(:second) + 60
  end
  
  defp record_provider_usage(provider_id, tokens_used) do
    # Record actual usage for token bucket consumption
    provider_requests_key = "provider:#{provider_id}:requests"
    provider_tokens_key = "provider:#{provider_id}:tokens"
    
    Hammer.check_rate_inc(provider_requests_key, 60_000, 1000, 1)
    Hammer.check_rate_inc(provider_tokens_key, 60_000, 100_000, tokens_used)
    
    :ok
  end
  
  defp record_user_usage(user_id, tokens_used) do
    # Record actual usage for user limits
    user_requests_key = "user:#{user_id}:requests"
    user_tokens_key = "user:#{user_id}:tokens"
    
    Hammer.check_rate_inc(user_requests_key, 60_000 * 60, 1000, 1)
    Hammer.check_rate_inc(user_tokens_key, 60_000 * 60, 100_000, tokens_used)
    
    :ok
  end
  
  defp update_check_stats(state, provider_id, user_tier, result) do
    new_total_checked = state.stats.total_requests_checked + 1
    new_total_blocked = if result.allowed, do: state.stats.total_requests_blocked, else: state.stats.total_requests_blocked + 1
    
    new_provider_stats = Map.update(state.stats.requests_by_provider, provider_id, 1, &(&1 + 1))
    new_tier_stats = Map.update(state.stats.requests_by_user_tier, user_tier, 1, &(&1 + 1))
    
    updated_stats = %{state.stats |
      total_requests_checked: new_total_checked,
      total_requests_blocked: new_total_blocked,
      requests_by_provider: new_provider_stats,
      requests_by_user_tier: new_tier_stats
    }
    
    %{state | stats: updated_stats}
  end
  
  defp update_usage_stats(state, provider_id, request_info) do
    # Could add more detailed usage tracking here
    state
  end
  
  defp get_remaining_requests(id, scope, state) do
    # Simplified remaining count estimation
    # In production, this would query Hammer backends directly
    case scope do
      :provider -> 
        limits = Map.get(state.provider_limits, id, %{})
        Map.get(limits, :requests_per_minute, 1000)
      :user -> 1000
      :global -> 10000
    end
  end
  
  defp get_remaining_tokens(id, scope, state) do
    case scope do
      :provider ->
        limits = Map.get(state.provider_limits, id, %{})
        Map.get(limits, :tokens_per_minute, 100_000)
      :user -> 100_000
      :global -> 1_000_000
    end
  end
end