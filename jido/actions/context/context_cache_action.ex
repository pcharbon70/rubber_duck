defmodule RubberDuck.Jido.Actions.Context.ContextCacheAction do
  @moduledoc """
  Action for managing context caching, invalidation, and cache optimization.

  This action handles all aspects of context cache management including cache
  storage, retrieval, invalidation, cleanup, and optimization strategies to
  improve context assembly performance.

  ## Parameters

  - `operation` - Cache operation to perform (required: :get, :set, :invalidate, :cleanup, :stats)
  - `request_id` - Context request ID for cache operations (required for most operations)
  - `context_data` - Context data to cache (required for :set operation)
  - `cache_key` - Custom cache key (optional, auto-generated if not provided)
  - `ttl_seconds` - Time-to-live for cache entries in seconds (default: 3600)
  - `max_entries` - Maximum number of cache entries to maintain (default: 1000)
  - `invalidation_pattern` - Pattern for bulk invalidation (optional)
  - `compression_enabled` - Whether to compress cached data (default: true)
  - `metrics_enabled` - Whether to collect cache metrics (default: true)

  ## Returns

  - `{:ok, result}` - Cache operation completed successfully
  - `{:error, reason}` - Cache operation failed

  ## Example

      # Get from cache
      params = %{
        operation: :get,
        request_id: "ctx_req_12345",
        metrics_enabled: true
      }

      {:ok, result} = ContextCacheAction.run(params, context)

      # Set cache entry
      params = %{
        operation: :set,
        request_id: "ctx_req_12345",
        context_data: assembled_context,
        ttl_seconds: 1800,
        compression_enabled: true
      }

      {:ok, result} = ContextCacheAction.run(params, context)
  """

  use Jido.Action,
    name: "context_cache",
    description: "Manage context caching, invalidation, and cache optimization",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Cache operation to perform (get, set, invalidate, cleanup, stats, optimize)"
      ],
      request_id: [
        type: :string,
        default: nil,
        doc: "Context request ID for cache operations"
      ],
      context_data: [
        type: :map,
        default: %{},
        doc: "Context data to cache (for set operation)"
      ],
      cache_key: [
        type: :string,
        default: nil,
        doc: "Custom cache key (auto-generated if not provided)"
      ],
      ttl_seconds: [
        type: :integer,
        default: 3600,
        doc: "Time-to-live for cache entries in seconds"
      ],
      max_entries: [
        type: :integer,
        default: 1000,
        doc: "Maximum number of cache entries to maintain"
      ],
      invalidation_pattern: [
        type: :string,
        default: nil,
        doc: "Pattern for bulk invalidation (glob pattern)"
      ],
      compression_enabled: [
        type: :boolean,
        default: true,
        doc: "Whether to compress cached data"
      ],
      metrics_enabled: [
        type: :boolean,
        default: true,
        doc: "Whether to collect cache metrics"
      ],
      force_refresh: [
        type: :boolean,
        default: false,
        doc: "Force cache refresh even if valid entry exists"
      ],
      cleanup_threshold: [
        type: :float,
        default: 0.8,
        doc: "Cache usage threshold to trigger automatic cleanup"
      ]
    ]

  require Logger

  alias RubberDuck.Context.ContextEntry

  @impl true
  def run(params, context) do
    Logger.info("Executing cache operation: #{params.operation}")

    case params.operation do
      :get -> get_from_cache(params, context)
      :set -> set_cache_entry(params, context)
      :invalidate -> invalidate_cache(params, context)
      :cleanup -> cleanup_cache(params, context)
      :stats -> get_cache_stats(params, context)
      :optimize -> optimize_cache(params, context)
      :warm -> warm_cache(params, context)
      _ -> {:error, {:invalid_operation, params.operation}}
    end
  end

  # Cache retrieval

  defp get_from_cache(params, context) do
    cache_key = params.cache_key || generate_cache_key(params.request_id, params)
    
    case fetch_cache_entry(cache_key, context) do
      {:ok, cache_entry} ->
        if cache_entry_valid?(cache_entry, params) and not params.force_refresh do
          record_cache_hit(cache_key, params.metrics_enabled)
          
          result = %{
            cache_hit: true,
            cache_key: cache_key,
            data: decompress_if_needed(cache_entry.data, cache_entry.compressed),
            metadata: cache_entry.metadata,
            cached_at: cache_entry.cached_at,
            expires_at: cache_entry.expires_at,
            access_count: cache_entry.access_count + 1
          }
          
          # Update access statistics
          update_cache_access(cache_key, context)
          
          {:ok, result}
        else
          record_cache_miss(cache_key, params.metrics_enabled)
          {:ok, %{cache_hit: false, cache_key: cache_key, reason: :expired_or_invalid}}
        end
        
      :not_found ->
        record_cache_miss(cache_key, params.metrics_enabled)
        {:ok, %{cache_hit: false, cache_key: cache_key, reason: :not_found}}
        
      {:error, reason} ->
        Logger.error("Cache retrieval failed for key #{cache_key}: #{inspect(reason)}")
        {:error, {:cache_retrieval_failed, reason}}
    end
  end

  # Cache storage

  defp set_cache_entry(params, context) do
    if Map.has_key?(params.context_data, :entries) do
      cache_key = params.cache_key || generate_cache_key(params.request_id, params)
      
      with {:ok, processed_data} <- prepare_cache_data(params.context_data, params),
           {:ok, cache_entry} <- build_cache_entry(processed_data, params),
           {:ok, _} <- store_cache_entry(cache_key, cache_entry, context) do
        
        # Trigger cleanup if cache is getting full
        maybe_trigger_cleanup(context, params)
        
        result = %{
          cache_key: cache_key,
          cached_at: cache_entry.cached_at,
          expires_at: cache_entry.expires_at,
          size_bytes: cache_entry.size_bytes,
          compressed: cache_entry.compressed,
          metadata: %{
            entries_count: length(params.context_data.entries),
            total_tokens: calculate_total_tokens(params.context_data.entries),
            compression_ratio: cache_entry.compression_ratio
          }
        }
        
        record_cache_set(cache_key, params.metrics_enabled)
        {:ok, result}
      else
        {:error, reason} ->
          Logger.error("Cache storage failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, {:invalid_context_data, "Missing entries field"}}
    end
  end

  # Cache invalidation

  defp invalidate_cache(params, context) do
    cond do
      params.invalidation_pattern ->
        invalidate_by_pattern(params.invalidation_pattern, context, params.metrics_enabled)
        
      params.request_id ->
        cache_key = params.cache_key || generate_cache_key(params.request_id, params)
        invalidate_single_entry(cache_key, context, params.metrics_enabled)
        
      params.cache_key ->
        invalidate_single_entry(params.cache_key, context, params.metrics_enabled)
        
      true ->
        {:error, {:insufficient_parameters, "Need request_id, cache_key, or invalidation_pattern"}}
    end
  end

  defp invalidate_single_entry(cache_key, context, metrics_enabled) do
    case remove_cache_entry(cache_key, context) do
      :ok ->
        record_cache_invalidation(cache_key, metrics_enabled)
        
        result = %{
          invalidated_keys: [cache_key],
          invalidated_count: 1,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, {:invalidation_failed, reason}}
    end
  end

  defp invalidate_by_pattern(pattern, context, metrics_enabled) do
    case find_keys_by_pattern(pattern, context) do
      {:ok, matching_keys} ->
        invalidated_keys = Enum.reduce(matching_keys, [], fn key, acc ->
          case remove_cache_entry(key, context) do
            :ok -> [key | acc]
            {:error, _} -> acc
          end
        end)
        
        Enum.each(invalidated_keys, fn key ->
          record_cache_invalidation(key, metrics_enabled)
        end)
        
        result = %{
          invalidated_keys: Enum.reverse(invalidated_keys),
          invalidated_count: length(invalidated_keys),
          pattern: pattern,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, {:pattern_invalidation_failed, reason}}
    end
  end

  # Cache cleanup

  defp cleanup_cache(params, context) do
    Logger.info("Starting cache cleanup with threshold: #{params.cleanup_threshold}")
    
    with {:ok, cache_stats} <- get_cache_statistics(context),
         {:ok, cleanup_strategy} <- determine_cleanup_strategy(cache_stats, params),
         {:ok, cleanup_results} <- execute_cleanup_strategy(cleanup_strategy, context) do
      
      result = %{
        cleanup_strategy: cleanup_strategy.name,
        entries_before: cache_stats.total_entries,
        entries_after: cleanup_results.remaining_entries,
        entries_removed: cleanup_results.removed_count,
        space_freed_bytes: cleanup_results.space_freed,
        cleanup_duration_ms: cleanup_results.duration_ms,
        timestamp: DateTime.utc_now()
      }
      
      record_cache_cleanup(cleanup_results, params.metrics_enabled)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Cache cleanup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp determine_cleanup_strategy(stats, params) do
    usage_ratio = stats.total_entries / params.max_entries
    
    strategy = cond do
      usage_ratio >= params.cleanup_threshold ->
        %{name: :aggressive, target_ratio: 0.6, criteria: [:lru, :expired, :large]}
        
      usage_ratio >= 0.7 ->
        %{name: :moderate, target_ratio: 0.7, criteria: [:expired, :lru]}
        
      usage_ratio >= 0.5 ->
        %{name: :gentle, target_ratio: 0.8, criteria: [:expired]}
        
      true ->
        %{name: :minimal, target_ratio: 0.9, criteria: [:expired]}
    end
    
    {:ok, strategy}
  end

  defp execute_cleanup_strategy(strategy, context) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, candidate_keys} <- find_cleanup_candidates(strategy, context),
         {:ok, removal_results} <- remove_selected_entries(candidate_keys, strategy, context) do
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      result = %{
        removed_count: removal_results.removed_count,
        remaining_entries: removal_results.remaining_entries,
        space_freed: removal_results.space_freed,
        duration_ms: duration
      }
      
      {:ok, result}
    end
  end

  # Cache statistics

  defp get_cache_stats(params, context) do
    case get_cache_statistics(context) do
      {:ok, stats} ->
        enhanced_stats = if params.metrics_enabled do
          Map.merge(stats, get_performance_metrics(context))
        else
          stats
        end
        
        result = %{
          statistics: enhanced_stats,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, {:stats_retrieval_failed, reason}}
    end
  end

  defp get_cache_statistics(context) do
    # This would interact with the actual cache implementation
    # For now, return mock statistics
    stats = %{
      total_entries: 0,
      total_size_bytes: 0,
      hit_rate: 0.0,
      miss_rate: 0.0,
      average_entry_size: 0,
      oldest_entry_age_seconds: 0,
      newest_entry_age_seconds: 0,
      compression_ratio: 0.0,
      expired_entries: 0
    }
    
    {:ok, stats}
  end

  defp get_performance_metrics(context) do
    %{
      average_retrieval_time_ms: 0.0,
      average_storage_time_ms: 0.0,
      cache_efficiency_score: 0.0,
      memory_pressure: 0.0,
      last_cleanup_at: nil
    }
  end

  # Cache optimization

  defp optimize_cache(params, context) do
    Logger.info("Starting cache optimization")
    
    with {:ok, optimization_plan} <- build_optimization_plan(context, params),
         {:ok, optimization_results} <- execute_optimization_plan(optimization_plan, context) do
      
      result = %{
        optimization_plan: optimization_plan.name,
        actions_taken: optimization_results.actions,
        performance_improvement: optimization_results.improvement,
        space_saved_bytes: optimization_results.space_saved,
        entries_optimized: optimization_results.entries_optimized,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Cache optimization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_optimization_plan(context, params) do
    with {:ok, stats} <- get_cache_statistics(context) do
      actions = []
      
      # Add compression optimization if beneficial
      actions = if stats.compression_ratio < 0.7 and params.compression_enabled do
        [:recompress_large_entries | actions]
      else
        actions
      end
      
      # Add defragmentation if needed
      actions = if stats.total_entries > params.max_entries * 0.8 do
        [:defragment_cache | actions]
      else
        actions
      end
      
      # Add rebalancing if hit rate is low
      actions = if stats.hit_rate < 0.6 do
        [:rebalance_priorities | actions]
      else
        actions
      end
      
      plan = %{
        name: :comprehensive,
        actions: Enum.reverse(actions),
        target_improvements: %{
          hit_rate: min(stats.hit_rate + 0.1, 0.95),
          compression_ratio: min(stats.compression_ratio + 0.1, 0.9),
          space_efficiency: 0.8
        }
      }
      
      {:ok, plan}
    end
  end

  defp execute_optimization_plan(plan, context) do
    results = Enum.reduce(plan.actions, %{actions: [], improvement: 0.0, space_saved: 0, entries_optimized: 0}, fn action, acc ->
      case execute_optimization_action(action, context) do
        {:ok, action_result} ->
          %{
            actions: [action | acc.actions],
            improvement: acc.improvement + action_result.improvement,
            space_saved: acc.space_saved + action_result.space_saved,
            entries_optimized: acc.entries_optimized + action_result.entries_affected
          }
          
        {:error, _reason} ->
          acc
      end
    end)
    
    {:ok, results}
  end

  defp execute_optimization_action(:recompress_large_entries, _context) do
    # Mock implementation - would recompress cache entries
    {:ok, %{improvement: 0.05, space_saved: 1024, entries_affected: 10}}
  end

  defp execute_optimization_action(:defragment_cache, _context) do
    # Mock implementation - would defragment cache storage
    {:ok, %{improvement: 0.03, space_saved: 512, entries_affected: 0}}
  end

  defp execute_optimization_action(:rebalance_priorities, _context) do
    # Mock implementation - would rebalance cache priorities
    {:ok, %{improvement: 0.02, space_saved: 0, entries_affected: 25}}
  end

  defp execute_optimization_action(_unknown_action, _context) do
    {:error, :unknown_action}
  end

  # Cache warming

  defp warm_cache(params, context) do
    Logger.info("Starting cache warming")
    
    # This would pre-populate cache with frequently accessed contexts
    # For now, return success with mock data
    result = %{
      warmed_entries: 0,
      estimated_performance_gain: 0.0,
      warming_duration_ms: 0,
      timestamp: DateTime.utc_now()
    }
    
    {:ok, result}
  end

  # Data processing helpers

  defp prepare_cache_data(context_data, params) do
    processed_data = if params.compression_enabled do
      compress_context_data(context_data)
    else
      %{
        data: context_data,
        compressed: false,
        compression_ratio: 1.0,
        original_size: estimate_data_size(context_data)
      }
    end
    
    {:ok, processed_data}
  end

  defp compress_context_data(context_data) do
    original_size = estimate_data_size(context_data)
    
    # Simple compression simulation - would use actual compression
    compressed_data = context_data  # In reality, this would be compressed
    compressed_size = div(original_size, 3)  # Assume 3:1 compression ratio
    
    %{
      data: compressed_data,
      compressed: true,
      compression_ratio: compressed_size / original_size,
      original_size: original_size,
      compressed_size: compressed_size
    }
  end

  defp decompress_if_needed(data, compressed) do
    if compressed do
      # Would decompress the data in real implementation
      data
    else
      data
    end
  end

  defp build_cache_entry(processed_data, params) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, params.ttl_seconds, :second)
    
    cache_entry = %{
      data: processed_data.data,
      compressed: processed_data.compressed,
      compression_ratio: processed_data.compression_ratio || 1.0,
      size_bytes: processed_data.compressed_size || processed_data.original_size,
      cached_at: now,
      expires_at: expires_at,
      access_count: 0,
      last_accessed: now,
      metadata: %{
        ttl_seconds: params.ttl_seconds,
        cache_version: "1.0"
      }
    }
    
    {:ok, cache_entry}
  end

  # Cache storage interface (would interact with actual cache backend)

  defp store_cache_entry(_cache_key, _cache_entry, _context) do
    # Mock implementation - would store in actual cache
    {:ok, :stored}
  end

  defp fetch_cache_entry(_cache_key, _context) do
    # Mock implementation - would fetch from actual cache
    :not_found
  end

  defp remove_cache_entry(_cache_key, _context) do
    # Mock implementation - would remove from actual cache
    :ok
  end

  defp update_cache_access(_cache_key, _context) do
    # Mock implementation - would update access statistics
    :ok
  end

  defp find_keys_by_pattern(_pattern, _context) do
    # Mock implementation - would find keys matching pattern
    {:ok, []}
  end

  defp find_cleanup_candidates(_strategy, _context) do
    # Mock implementation - would find entries to clean up
    {:ok, []}
  end

  defp remove_selected_entries(_candidate_keys, _strategy, _context) do
    # Mock implementation - would remove selected entries
    {:ok, %{removed_count: 0, remaining_entries: 0, space_freed: 0}}
  end

  # Cache validation

  defp cache_entry_valid?(cache_entry, _params) do
    now = DateTime.utc_now()
    DateTime.compare(cache_entry.expires_at, now) == :gt
  end

  defp maybe_trigger_cleanup(context, params) do
    case get_cache_statistics(context) do
      {:ok, stats} ->
        usage_ratio = stats.total_entries / params.max_entries
        if usage_ratio >= params.cleanup_threshold do
          # Would trigger async cleanup
          Logger.info("Cache usage at #{Float.round(usage_ratio * 100, 1)}%, triggering cleanup")
        end
        
      {:error, _} ->
        :ok
    end
  end

  # Metrics recording

  defp record_cache_hit(_cache_key, true) do
    # Would record hit metric
    :ok
  end
  defp record_cache_hit(_cache_key, false), do: :ok

  defp record_cache_miss(_cache_key, true) do
    # Would record miss metric
    :ok
  end
  defp record_cache_miss(_cache_key, false), do: :ok

  defp record_cache_set(_cache_key, true) do
    # Would record set metric
    :ok
  end
  defp record_cache_set(_cache_key, false), do: :ok

  defp record_cache_invalidation(_cache_key, true) do
    # Would record invalidation metric
    :ok
  end
  defp record_cache_invalidation(_cache_key, false), do: :ok

  defp record_cache_cleanup(_cleanup_results, true) do
    # Would record cleanup metrics
    :ok
  end
  defp record_cache_cleanup(_cleanup_results, false), do: :ok

  # Helper functions

  defp generate_cache_key(request_id, params) do
    base_key = request_id || "unknown"
    purpose = Map.get(params, :purpose, "general")
    
    # Create deterministic key based on request parameters
    key_data = "#{base_key}:#{purpose}"
    hash = :crypto.hash(:sha256, key_data) |> Base.encode16(case: :lower)
    
    "ctx_cache_#{String.slice(hash, 0, 16)}"
  end

  defp calculate_total_tokens(entries) when is_list(entries) do
    Enum.sum(Enum.map(entries, fn entry -> 
      Map.get(entry, :size_tokens, 0)
    end))
  end
  defp calculate_total_tokens(_), do: 0

  defp estimate_data_size(data) when is_map(data) do
    # Rough estimation of map size in bytes
    data
    |> Jason.encode!()
    |> byte_size()
  end
  defp estimate_data_size(data) when is_binary(data), do: byte_size(data)
  defp estimate_data_size(_), do: 0
end