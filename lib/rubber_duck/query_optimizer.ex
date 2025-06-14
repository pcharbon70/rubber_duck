defmodule RubberDuck.QueryOptimizer do
  @moduledoc """
  Optimizes Mnesia query patterns for AI workloads.
  
  This module analyzes query patterns and provides optimized
  query functions for common AI assistant operations.
  """
  
  require Logger
  alias RubberDuck.CacheManager
  
  @doc """
  Retrieves AI context with optimized query and caching
  """
  def get_context(session_id, opts \\ []) do
    use_cache = Keyword.get(opts, :use_cache, true)
    
    # Try cache first
    if use_cache do
      case CacheManager.get_context(session_id) do
        {:ok, nil} ->
          # Cache miss, query Mnesia
          fetch_and_cache_context(session_id)
        {:ok, context} ->
          {:ok, context}
        error ->
          error
      end
    else
      # Direct Mnesia query
      query_context_from_mnesia(session_id)
    end
  end
  
  @doc """
  Batch retrieves multiple contexts efficiently
  """
  def get_contexts_batch(session_ids) when is_list(session_ids) do
    # Use parallel queries for better performance
    tasks = Enum.map(session_ids, fn session_id ->
      Task.async(fn -> get_context(session_id) end)
    end)
    
    results = Task.await_many(tasks, 5000)
    
    Enum.zip(session_ids, results)
    |> Enum.into(%{})
  end
  
  @doc """
  Queries code analysis with intelligent indexing
  """
  def get_analysis(file_path, opts \\ []) do
    use_cache = Keyword.get(opts, :use_cache, true)
    force_refresh = Keyword.get(opts, :force_refresh, false)
    
    if use_cache and not force_refresh do
      case CacheManager.get_analysis(file_path) do
        {:ok, nil} ->
          fetch_and_cache_analysis(file_path)
        {:ok, analysis} ->
          {:ok, analysis}
        error ->
          error
      end
    else
      query_analysis_from_mnesia(file_path)
    end
  end
  
  @doc """
  Performs efficient range queries for time-based data
  """
  def get_recent_interactions(limit \\ 100, since \\ nil) do
    since_timestamp = since || DateTime.add(DateTime.utc_now(), -86400, :second)
    
    query = fn ->
      :mnesia.select(:llm_interaction, [
        {
          {:llm_interaction, :"$1", :"$2", :"$3", :"$4", :"$5"},
          [{:>, :"$5", since_timestamp}],
          [:"$$"]
        }
      ])
    end
    
    case :mnesia.transaction(query) do
      {:atomic, results} ->
        # Sort by timestamp and limit
        sorted_results = results
        |> Enum.sort_by(&elem(&1, 4), {:desc, DateTime})
        |> Enum.take(limit)
        |> Enum.map(&tuple_to_map/1)
        
        {:ok, sorted_results}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Aggregates metrics for performance monitoring
  """
  def aggregate_metrics(metric_type, time_range \\ :hour) do
    start_time = calculate_start_time(time_range)
    
    query = fn ->
      :mnesia.foldl(
        fn record, acc ->
          case record do
            {:llm_interaction, _id, _session, _prompt, _response, timestamp, metadata} ->
              if DateTime.compare(timestamp, start_time) == :gt do
                update_metrics_accumulator(acc, metadata, metric_type)
              else
                acc
              end
            _ ->
              acc
          end
        end,
        %{count: 0, total: 0, max: 0, min: nil},
        :llm_interaction
      )
    end
    
    case :mnesia.transaction(query) do
      {:atomic, metrics} ->
        {:ok, finalize_metrics(metrics)}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Performs full-text search across contexts
  """
  def search_contexts(search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    
    query = fn ->
      :mnesia.foldl(
        fn record, acc ->
          case record do
            {:ai_context, _id, _session, content, _metadata, _timestamp} ->
              if String.contains?(to_string(content), search_term) do
                [record | acc]
              else
                acc
              end
            _ ->
              acc
          end
        end,
        [],
        :ai_context
      )
    end
    
    case :mnesia.transaction(query) do
      {:atomic, results} ->
        sorted_results = results
        |> Enum.take(limit)
        |> Enum.map(&tuple_to_map/1)
        
        {:ok, sorted_results}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Creates optimized indexes for common query patterns
  """
  def create_optimized_indexes do
    indexes = [
      {:ai_context, :session_id},
      {:code_analysis_cache, :file_path},
      {:llm_interaction, :timestamp},
      {:llm_interaction, :session_id}
    ]
    
    results = Enum.map(indexes, fn {table, field} ->
      case :mnesia.add_table_index(table, field) do
        {:atomic, :ok} ->
          Logger.info("Created index on #{table}.#{field}")
          {:ok, {table, field}}
        {:aborted, {:already_exists, _}} ->
          Logger.debug("Index already exists on #{table}.#{field}")
          {:ok, {table, field}}
        {:aborted, reason} ->
          Logger.error("Failed to create index on #{table}.#{field}: #{inspect(reason)}")
          {:error, {table, field, reason}}
      end
    end)
    
    {successes, failures} = Enum.split_with(results, &match?({:ok, _}, &1))
    
    %{
      created: length(successes),
      failed: length(failures),
      details: results
    }
  end
  
  # Private functions
  
  defp fetch_and_cache_context(session_id) do
    case query_context_from_mnesia(session_id) do
      {:ok, context} when context != nil ->
        CacheManager.cache_context(session_id, context)
        {:ok, context}
      other ->
        other
    end
  end
  
  defp query_context_from_mnesia(session_id) do
    query = fn ->
      :mnesia.index_read(:ai_context, session_id, :session_id)
    end
    
    case :mnesia.transaction(query) do
      {:atomic, [record | _]} ->
        {:ok, tuple_to_map(record)}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp fetch_and_cache_analysis(file_path) do
    case query_analysis_from_mnesia(file_path) do
      {:ok, analysis} when analysis != nil ->
        CacheManager.cache_analysis(file_path, analysis)
        {:ok, analysis}
      other ->
        other
    end
  end
  
  defp query_analysis_from_mnesia(file_path) do
    query = fn ->
      :mnesia.index_read(:code_analysis_cache, file_path, :file_path)
    end
    
    case :mnesia.transaction(query) do
      {:atomic, [record | _]} ->
        {:ok, tuple_to_map(record)}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, reason}
    end
  end
  
  defp calculate_start_time(time_range) do
    seconds = case time_range do
      :minute -> 60
      :hour -> 3600
      :day -> 86400
      :week -> 604800
      custom when is_integer(custom) -> custom
    end
    
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end
  
  defp update_metrics_accumulator(acc, metadata, metric_type) do
    value = Map.get(metadata, metric_type, 0)
    
    %{
      count: acc.count + 1,
      total: acc.total + value,
      max: max(acc.max, value),
      min: if(acc.min, do: min(acc.min, value), else: value)
    }
  end
  
  defp finalize_metrics(%{count: 0} = metrics), do: metrics
  defp finalize_metrics(metrics) do
    Map.put(metrics, :average, metrics.total / metrics.count)
  end
  
  defp tuple_to_map(record) do
    case record do
      {:ai_context, id, session_id, content, metadata, timestamp} ->
        %{
          id: id,
          session_id: session_id,
          content: content,
          metadata: metadata,
          timestamp: timestamp
        }
      
      {:code_analysis_cache, id, file_path, analysis, metadata, timestamp} ->
        %{
          id: id,
          file_path: file_path,
          analysis: analysis,
          metadata: metadata,
          timestamp: timestamp
        }
      
      {:llm_interaction, id, session_id, prompt, response, timestamp, metadata} ->
        %{
          id: id,
          session_id: session_id,
          prompt: prompt,
          response: response,
          timestamp: timestamp,
          metadata: metadata
        }
      
      {:llm_interaction, id, session_id, prompt, response, timestamp} ->
        %{
          id: id,
          session_id: session_id,
          prompt: prompt,
          response: response,
          timestamp: timestamp,
          metadata: %{}
        }
        
      _ ->
        record
    end
  end
end