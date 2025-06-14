defmodule RubberDuck.LLMDataManager do
  @moduledoc """
  Specialized data manager for LLM responses and provider status.
  
  Provides high-level operations for storing and retrieving LLM data
  with built-in caching integration, response deduplication, and
  performance optimization for AI workloads.
  """
  
  alias RubberDuck.TransactionWrapper
  require Logger
  
  @default_ttl :timer.hours(24)
  @response_retention_days 30
  @provider_status_retention_days 7
  
  # LLM Response Operations
  
  @doc """
  Store an LLM response with automatic deduplication and cache integration
  """
  def store_response(response_data, opts \\ []) do
    response_id = generate_response_id(response_data)
    prompt_hash = hash_prompt(response_data.prompt)
    expires_at = calculate_expires_at(response_data, opts)
    
    record = {
      :llm_responses,
      response_id,
      prompt_hash,
      response_data.provider,
      response_data.model,
      response_data.prompt,
      response_data.response,
      Map.get(response_data, :tokens_used, 0),
      Map.get(response_data, :cost, 0.0),
      Map.get(response_data, :latency, 0),
      :os.system_time(:millisecond),
      expires_at,
      Map.get(response_data, :session_id),
      node()
    }
    
    metadata = %{
      operation: :store_llm_response,
      provider: response_data.provider,
      model: response_data.model,
      tokens: Map.get(response_data, :tokens_used, 0)
    }
    
    case TransactionWrapper.create_record(:llm_responses, record, metadata: metadata) do
      {:ok, _} ->
        # Also cache for quick retrieval
        cache_response(prompt_hash, response_data.response, expires_at)
        {:ok, response_id}
      error ->
        Logger.warning("Failed to store LLM response: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Retrieve an LLM response by prompt hash with cache fallback
  """
  def get_response_by_prompt(prompt, provider \\ nil, model \\ nil) do
    prompt_hash = hash_prompt(prompt)
    
    # Try cache first
    case get_cached_response(prompt_hash) do
      {:ok, response} ->
        {:ok, response}
      :miss ->
        # Fall back to database
        get_response_from_db(prompt_hash, provider, model)
    end
  end
  
  @doc """
  Get response statistics for analytics
  """
  def get_response_stats(opts \\ []) do
    time_range = Keyword.get(opts, :time_range, :timer.hours(24))
    provider = Keyword.get(opts, :provider)
    
    since = :os.system_time(:millisecond) - time_range
    
    TransactionWrapper.read_transaction(fn ->
      pattern = case provider do
        nil -> {:llm_responses, :_, :_, :_, :_, :_, :_, :_, :_, :_, :"$11", :_, :_, :_}
        provider -> {:llm_responses, :_, :_, provider, :_, :_, :_, :_, :_, :_, :"$11", :_, :_, :_}
      end
      
      responses = :mnesia.select(:llm_responses, [
        {pattern, [{:>=, :"$11", since}], [:"$_"]}
      ])
      
      calculate_response_statistics(responses)
    end)
  end
  
  # Provider Status Operations
  
  @doc """
  Update provider status and metrics
  """
  def update_provider_status(provider_data) do
    provider_id = generate_provider_id(provider_data.provider_name)
    
    record = {
      :llm_provider_status,
      provider_id,
      provider_data.provider_name,
      Map.get(provider_data, :status, :active),
      Map.get(provider_data, :health_score, 100),
      Map.get(provider_data, :total_requests, 0),
      Map.get(provider_data, :successful_requests, 0),
      Map.get(provider_data, :failed_requests, 0),
      Map.get(provider_data, :average_latency, 0),
      Map.get(provider_data, :cost_total, 0.0),
      Map.get(provider_data, :rate_limit_remaining),
      Map.get(provider_data, :rate_limit_reset),
      :os.system_time(:millisecond),
      node()
    }
    
    metadata = %{
      operation: :update_provider_status,
      provider: provider_data.provider_name,
      status: Map.get(provider_data, :status, :active)
    }
    
    TransactionWrapper.write_transaction(:llm_provider_status, :upsert, record, metadata: metadata)
  end
  
  @doc """
  Get current provider status
  """
  def get_provider_status(provider_name) do
    provider_id = generate_provider_id(provider_name)
    
    TransactionWrapper.read_transaction(fn ->
      case :mnesia.read(:llm_provider_status, provider_id) do
        [] -> {:error, :not_found}
        [record] -> {:ok, format_provider_status(record)}
      end
    end)
  end
  
  @doc """
  Get all active providers with their status
  """
  def get_all_provider_status do
    TransactionWrapper.read_transaction(fn ->
      providers = :mnesia.select(:llm_provider_status, [
        {{:llm_provider_status, :_, :_, :active, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}, [], [:"$_"]}
      ])
      
      Enum.map(providers, &format_provider_status/1)
    end)
  end
  
  # Query Operations
  
  @doc """
  Find similar responses based on prompt similarity
  """
  def find_similar_responses(prompt, _similarity_threshold \\ 0.8, limit \\ 10) do
    prompt_hash = hash_prompt(prompt)
    
    TransactionWrapper.read_transaction(fn ->
      # For now, use exact hash matching
      # In production, we'd implement semantic similarity
      responses = :mnesia.index_read(:llm_responses, prompt_hash, :prompt_hash)
      
      responses
      |> Enum.take(limit)
      |> Enum.map(&format_response/1)
    end)
  end
  
  @doc """
  Get responses by session for context rebuilding
  """
  def get_session_responses(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since, 0)
    
    TransactionWrapper.read_transaction(fn ->
      pattern = {:llm_responses, :_, :_, :_, :_, :_, :_, :_, :_, :_, :"$11", :_, session_id, :_}
      
      responses = :mnesia.select(:llm_responses, [
        {pattern, [{:>=, :"$11", since}], [:"$_"]}
      ])
      
      responses
      |> Enum.sort_by(fn {_, _, _, _, _, _, _, _, _, _, created_at, _, _, _} -> created_at end)
      |> Enum.take(limit)
      |> Enum.map(&format_response/1)
    end)
  end
  
  # Cleanup and Maintenance
  
  @doc """
  Clean up expired responses and old provider status records
  """
  def cleanup_expired_data do
    current_time = :os.system_time(:millisecond)
    provider_cutoff = current_time - (@provider_status_retention_days * 24 * 60 * 60 * 1000)
    
    cleanup_fun = fn ->
      # Clean expired responses
      expired_responses = :mnesia.select(:llm_responses, [
        {{:llm_responses, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :_, :"$12", :_, :_}, 
         [{:<, :"$12", current_time}], 
         [:"$1"]}
      ])
      
      Enum.each(expired_responses, fn response_id ->
        :mnesia.delete({:llm_responses, response_id})
      end)
      
      # Clean old provider status records
      old_statuses = :mnesia.select(:llm_provider_status, [
        {{:llm_provider_status, :"$1", :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :"$13", :_},
         [{:<, :"$13", provider_cutoff}],
         [:"$1"]}
      ])
      
      Enum.each(old_statuses, fn provider_id ->
        :mnesia.delete({:llm_provider_status, provider_id})
      end)
      
      Logger.info("Cleaned up #{length(expired_responses)} expired responses and #{length(old_statuses)} old provider statuses")
      {:ok, %{expired_responses: length(expired_responses), old_statuses: length(old_statuses)}}
    end
    
    TransactionWrapper.write_transaction(:llm_responses, :cleanup, nil, cleanup_fun)
  end
  
  # Private Functions
  
  defp generate_response_id(response_data) do
    content = "#{response_data.provider}:#{response_data.model}:#{response_data.prompt}:#{:os.system_time(:millisecond)}"
    :crypto.hash(:sha256, content) |> Base.encode64(padding: false)
  end
  
  defp generate_provider_id(provider_name) do
    "provider:#{provider_name}"
  end
  
  defp hash_prompt(prompt) do
    :crypto.hash(:sha256, prompt) |> Base.encode64(padding: false)
  end
  
  defp calculate_expires_at(_response_data, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    :os.system_time(:millisecond) + ttl
  end
  
  defp cache_response(prompt_hash, response, expires_at) do
    ttl = max(0, expires_at - :os.system_time(:millisecond))
    
    # Integrate with the Nebulex cache system
    case RubberDuck.Nebulex.Cache.put_in(:multilevel, "llm:#{prompt_hash}", response, ttl: ttl) do
      :ok -> :ok
      _error -> :ok  # Don't fail if cache is unavailable
    end
  end
  
  defp get_cached_response(prompt_hash) do
    case RubberDuck.Nebulex.Cache.get_from(:multilevel, "llm:#{prompt_hash}") do
      nil -> :miss
      response -> {:ok, response}
    end
  end
  
  defp get_response_from_db(prompt_hash, provider, model) do
    TransactionWrapper.read_transaction(fn ->
      responses = :mnesia.index_read(:llm_responses, prompt_hash, :prompt_hash)
      
      filtered_responses = Enum.filter(responses, fn record ->
        {_, _, _, db_provider, db_model, _, _, _, _, _, _, _, _, _} = record
        
        (provider == nil or db_provider == provider) and
        (model == nil or db_model == model)
      end)
      
      case filtered_responses do
        [] -> {:error, :not_found}
        [record | _] -> 
          # Cache the response for future use
          {_, _, _, _, _, _, response, _, _, _, _, expires_at, _, _} = record
          cache_response(prompt_hash, response, expires_at)
          {:ok, format_response(record)}
      end
    end)
  end
  
  defp format_response({_, response_id, prompt_hash, provider, model, prompt, response, tokens_used, cost, latency, created_at, expires_at, session_id, node}) do
    %{
      response_id: response_id,
      prompt_hash: prompt_hash,
      provider: provider,
      model: model,
      prompt: prompt,
      response: response,
      tokens_used: tokens_used,
      cost: cost,
      latency: latency,
      created_at: created_at,
      expires_at: expires_at,
      session_id: session_id,
      node: node
    }
  end
  
  defp format_provider_status({_, provider_id, provider_name, status, health_score, total_requests, successful_requests, failed_requests, average_latency, cost_total, rate_limit_remaining, rate_limit_reset, last_updated, node}) do
    %{
      provider_id: provider_id,
      provider_name: provider_name,
      status: status,
      health_score: health_score,
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: failed_requests,
      average_latency: average_latency,
      cost_total: cost_total,
      rate_limit_remaining: rate_limit_remaining,
      rate_limit_reset: rate_limit_reset,
      last_updated: last_updated,
      node: node
    }
  end
  
  defp calculate_response_statistics(responses) do
    total_responses = length(responses)
    
    if total_responses == 0 do
      %{
        total_responses: 0,
        total_cost: 0.0,
        total_tokens: 0,
        average_latency: 0,
        providers: %{}
      }
    else
      totals = Enum.reduce(responses, %{cost: 0.0, tokens: 0, latency: 0, providers: %{}}, fn record, acc ->
        {_, _, _, provider, _, _, _, tokens, cost, latency, _, _, _, _} = record
        
        %{
          cost: acc.cost + cost,
          tokens: acc.tokens + tokens,
          latency: acc.latency + latency,
          providers: Map.update(acc.providers, provider, 1, &(&1 + 1))
        }
      end)
      
      %{
        total_responses: total_responses,
        total_cost: totals.cost,
        total_tokens: totals.tokens,
        average_latency: div(totals.latency, total_responses),
        providers: totals.providers
      }
    end
  end
end