defmodule RubberDuck.Agents.TokenPersistenceAgent do
  @moduledoc """
  Agent responsible for persisting token usage data to PostgreSQL.
  
  Listens for token usage signals and handles:
  - Batch persistence of token usage records
  - Provenance tracking
  - Error handling and retries
  - Performance optimization
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "token_persistence_agent",
    description: "Persists token usage data to PostgreSQL",
    schema: [
      buffer: [type: :list, default: []],
      buffer_size: [type: :integer, default: 100],
      flush_interval: [type: :integer, default: 5000],
      retry_attempts: [type: :integer, default: 3],
      last_flush: [type: :utc_datetime_usec, default: nil],
      stats: [type: :map, default: %{
        persisted_count: 0,
        failed_count: 0,
        retry_count: 0
      }]
    ]
  
  require Logger
  alias RubberDuck.Tokens
  
  @doc """
  Initializes the persistence agent.
  """
  @impl true
  def pre_init(config) do
    # Subscribe to token usage signals
    config = Map.put(config, :signal_subscriptions, [
      %{type: "token_usage_flush"},
      %{type: "token_usage_single"},
      %{type: "shutdown"}
    ])
    
    {:ok, config}
  end
  
  @doc """
  Starts the flush timer after initialization.
  """
  @impl true
  def post_init(agent) do
    # Schedule periodic flush
    schedule_flush(agent.state.flush_interval)
    {:ok, agent}
  end
  
  @doc """
  Handles incoming signals.
  """
  def handle_signal(agent, %{"type" => "token_usage_flush", "data" => usage_records}) do
    Logger.debug("TokenPersistenceAgent received flush signal with #{length(usage_records)} records")
    
    # Add records to buffer
    new_buffer = agent.state.buffer ++ usage_records
    new_state = Map.put(agent.state, :buffer, new_buffer)
    
    # Flush if buffer is full
    if length(new_buffer) >= agent.state.buffer_size do
      flush_buffer(%{agent | state: new_state})
    else
      {:ok, %{agent | state: new_state}}
    end
  end
  
  def handle_signal(agent, %{"type" => "token_usage_single", "data" => usage_record}) do
    Logger.debug("TokenPersistenceAgent received single usage record")
    
    # Add single record to buffer
    new_buffer = [usage_record | agent.state.buffer]
    new_state = Map.put(agent.state, :buffer, new_buffer)
    
    # Flush if buffer is full
    if length(new_buffer) >= agent.state.buffer_size do
      flush_buffer(%{agent | state: new_state})
    else
      {:ok, %{agent | state: new_state}}
    end
  end
  
  def handle_signal(agent, %{"type" => "shutdown"}) do
    Logger.info("TokenPersistenceAgent shutting down, flushing remaining records")
    
    # Flush any remaining records
    if length(agent.state.buffer) > 0 do
      flush_buffer(agent)
    else
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "flush_timer"}) do
    # Periodic flush
    if should_flush?(agent) do
      flush_buffer(agent)
    else
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, _signal) do
    # Ignore other signals
    {:ok, agent}
  end
  
  # Private functions
  
  defp flush_buffer(agent) do
    buffer = agent.state.buffer
    
    if length(buffer) == 0 do
      {:ok, agent}
    else
      Logger.info("Flushing #{length(buffer)} token usage records to database")
      
      case persist_records(buffer, agent.state.retry_attempts) do
        {:ok, persisted_count} ->
          # Update stats
          new_stats = Map.update!(agent.state.stats, :persisted_count, &(&1 + persisted_count))
          
          new_state = agent.state
          |> Map.put(:buffer, [])
          |> Map.put(:last_flush, DateTime.utc_now())
          |> Map.put(:stats, new_stats)
          
          # Emit success signal
          signal = Jido.Signal.new!(%{
            type: "token.persistence.success",
            source: "agent:#{agent.id}",
            data: %{
              count: persisted_count,
              timestamp: DateTime.utc_now()
            }
          })
          emit_signal(agent, signal)
          
          # Schedule next flush
          schedule_flush(agent.state.flush_interval)
          
          {:ok, %{agent | state: new_state}}
          
        {:error, reason} ->
          Logger.error("Failed to persist token usage records: #{inspect(reason)}")
          
          # Update failure stats
          new_stats = Map.update!(agent.state.stats, :failed_count, &(&1 + length(buffer)))
          new_state = Map.put(agent.state, :stats, new_stats)
          
          # Emit failure signal
          signal = Jido.Signal.new!(%{
            type: "token.persistence.failure",
            source: "agent:#{agent.id}",
            data: %{
              count: length(buffer),
              reason: inspect(reason),
              timestamp: DateTime.utc_now()
            }
          })
          emit_signal(agent, signal)
          
          {:ok, %{agent | state: new_state}}
      end
    end
  end
  
  defp persist_records(records, retry_attempts) do
    # Transform records for bulk insert
    usage_records = Enum.map(records, &transform_usage_record/1)
    
    # Persist with retries
    persist_with_retry(usage_records, retry_attempts)
  end
  
  defp persist_with_retry(records, attempts_left) when attempts_left > 0 do
    case Tokens.bulk_record_usage(records) do
      {:ok, results} ->
        {:ok, length(results)}
        
      {:error, _reason} when attempts_left > 1 ->
        Logger.warning("Token persistence failed, retrying. Attempts left: #{attempts_left - 1}")
        # Exponential backoff
        Process.sleep(:math.pow(2, 4 - attempts_left) * 100 |> round())
        persist_with_retry(records, attempts_left - 1)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp persist_with_retry(_records, 0) do
    {:error, :max_retries_exceeded}
  end
  
  defp transform_usage_record(record) do
    # Transform the record from internal format to Ash resource format
    %{
      provider: record["provider"] || record[:provider],
      model: record["model"] || record[:model],
      prompt_tokens: record["prompt_tokens"] || record[:prompt_tokens] || 0,
      completion_tokens: record["completion_tokens"] || record[:completion_tokens] || 0,
      total_tokens: record["total_tokens"] || record[:total_tokens] || 0,
      cost: Decimal.new(to_string(record["cost"] || record[:cost] || "0")),
      currency: record["currency"] || record[:currency] || "USD",
      user_id: record["user_id"] || record[:user_id],
      project_id: record["project_id"] || record[:project_id],
      team_id: record["team_id"] || record[:team_id],
      feature: record["feature"] || record[:feature],
      request_id: record["request_id"] || record[:request_id],
      metadata: record["metadata"] || record[:metadata] || %{}
    }
  end
  
  defp should_flush?(agent) do
    case agent.state.last_flush do
      nil -> 
        length(agent.state.buffer) > 0
        
      last_flush ->
        time_since_flush = DateTime.diff(DateTime.utc_now(), last_flush, :millisecond)
        time_since_flush >= agent.state.flush_interval && length(agent.state.buffer) > 0
    end
  end
  
  defp schedule_flush(_interval) do
    # In a real implementation, this would schedule a timer
    # For now, we'll rely on external signals
    :ok
  end
  
  @doc """
  Health check for the persistence agent.
  """
  @impl true
  def health_check(agent) do
    stats = agent.state.stats
    buffer_health = length(agent.state.buffer) < agent.state.buffer_size * 0.9
    
    failure_rate = if stats.persisted_count > 0 do
      stats.failed_count / (stats.persisted_count + stats.failed_count)
    else
      0.0
    end
    
    if buffer_health && failure_rate < 0.1 do
      {:healthy, %{
        buffer_size: length(agent.state.buffer),
        persisted_count: stats.persisted_count,
        failure_rate: failure_rate
      }}
    else
      {:unhealthy, %{
        buffer_size: length(agent.state.buffer),
        buffer_full: !buffer_health,
        failure_rate: failure_rate,
        failed_count: stats.failed_count
      }}
    end
  end
end