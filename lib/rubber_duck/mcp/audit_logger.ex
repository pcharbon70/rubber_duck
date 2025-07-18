defmodule RubberDuck.MCP.AuditLogger do
  @moduledoc """
  Comprehensive audit logging for MCP protocol operations.
  
  Provides structured logging of all MCP activities for:
  - Security analysis and threat detection
  - Compliance and regulatory requirements
  - Performance monitoring and optimization
  - Debugging and troubleshooting
  
  ## Features
  
  - Structured log format with consistent schema
  - Automatic sensitive data redaction
  - Log retention and rotation policies
  - Real-time streaming for monitoring
  - Query interface for analysis
  """
  
  use GenServer
  
  require Logger
  
  @type log_entry :: %{
    id: String.t(),
    timestamp: DateTime.t(),
    type: atom(),
    client_id: String.t() | nil,
    user_id: String.t() | nil,
    session_id: String.t() | nil,
    operation: String.t() | nil,
    params: map(),
    result: term(),
    metadata: map()
  }
  
  @type query_filter :: %{
    optional(:from) => DateTime.t(),
    optional(:to) => DateTime.t(),
    optional(:type) => atom() | [atom()],
    optional(:user_id) => String.t(),
    optional(:client_id) => String.t(),
    optional(:operation) => String.t(),
    optional(:limit) => pos_integer()
  }
  
  # Log types
  @log_types [:authentication, :authorization, :operation, :security_event, :rate_limit, :error]
  
  # Sensitive fields to redact
  @sensitive_fields ["password", "token", "secret", "apiKey", "credentials"]
  
  # Client API
  
  @doc """
  Starts the audit logger.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Logs an authentication event.
  """
  @spec log_authentication(map()) :: :ok
  def log_authentication(event) do
    GenServer.cast(__MODULE__, {:log, :authentication, event})
  end
  
  @doc """
  Logs an authorization decision.
  """
  @spec log_authorization(map()) :: :ok
  def log_authorization(event) do
    GenServer.cast(__MODULE__, {:log, :authorization, event})
  end
  
  @doc """
  Logs an MCP operation execution.
  """
  @spec log_operation(map()) :: :ok
  def log_operation(event) do
    GenServer.cast(__MODULE__, {:log, :operation, event})
  end
  
  @doc """
  Logs a security-relevant event.
  """
  @spec log_security_event(map()) :: :ok
  def log_security_event(event) do
    GenServer.cast(__MODULE__, {:log, :security_event, event})
  end
  
  @doc """
  Logs a rate limiting event.
  """
  @spec log_rate_limit(map()) :: :ok
  def log_rate_limit(event) do
    GenServer.cast(__MODULE__, {:log, :rate_limit, event})
  end
  
  @doc """
  Logs an error or exception.
  """
  @spec log_error(map()) :: :ok
  def log_error(event) do
    GenServer.cast(__MODULE__, {:log, :error, event})
  end
  
  @doc """
  Queries audit logs with filters.
  """
  @spec query(query_filter()) :: {:ok, [log_entry()]} | {:error, term()}
  def query(filter \\ %{}) do
    GenServer.call(__MODULE__, {:query, filter})
  end
  
  @doc """
  Gets audit log statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Updates logger configuration.
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  @doc """
  Exports logs for a time range.
  """
  @spec export_logs(DateTime.t(), DateTime.t(), String.t()) :: :ok | {:error, term()}
  def export_logs(from, to, format \\ "json") do
    GenServer.call(__MODULE__, {:export_logs, from, to, format})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS table for logs
    table = :ets.new(:mcp_audit_logs, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true
    ])
    
    # Create index tables
    user_index = :ets.new(:mcp_audit_user_index, [:bag, :public])
    operation_index = :ets.new(:mcp_audit_operation_index, [:bag, :public])
    
    # Initialize configuration
    config = load_config(opts)
    
    # Schedule retention cleanup
    if config.retention_enabled do
      schedule_retention_cleanup(config.retention_check_interval)
    end
    
    # Set up telemetry
    init_telemetry()
    
    state = %{
      table: table,
      user_index: user_index,
      operation_index: operation_index,
      config: config,
      stats: init_stats(),
      log_file: open_log_file(config)
    }
    
    Logger.info("MCP Audit Logger started with retention: #{config.retention_days} days")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_cast({:log, type, event}, state) do
    entry = build_log_entry(type, event)
    
    # Redact sensitive data
    sanitized_entry = redact_sensitive_data(entry)
    
    # Store in ETS
    key = {entry.timestamp, entry.id}
    :ets.insert(state.table, {key, sanitized_entry})
    
    # Update indexes
    update_indexes(state, sanitized_entry)
    
    # Write to file if configured
    if state.log_file do
      write_to_file(state.log_file, sanitized_entry)
    end
    
    # Stream to monitoring if configured
    if state.config.streaming_enabled do
      stream_log_entry(sanitized_entry)
    end
    
    # Update stats
    new_state = update_stats(state, type)
    
    # Check if we need to trigger alerts
    check_security_alerts(type, sanitized_entry, state.config)
    
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_call({:query, filter}, _from, state) do
    logs = query_logs(state, filter)
    {:reply, {:ok, logs}, state}
  end
  
  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      total_entries: :ets.info(state.table, :size),
      oldest_entry: get_oldest_entry(state.table),
      newest_entry: get_newest_entry(state.table)
    })
    
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_call({:update_config, config}, _from, state) do
    new_config = DeepMerge.deep_merge(state.config, config)
    
    # Handle config changes
    new_state = handle_config_changes(state, new_config)
    
    {:reply, :ok, %{new_state | config: new_config}}
  end
  
  @impl GenServer
  def handle_call({:export_logs, from, to, format}, _from, state) do
    result = export_logs_range(state, from, to, format)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_info(:retention_cleanup, state) do
    if state.config.retention_enabled do
      deleted = cleanup_old_logs(state)
      
      if deleted > 0 do
        Logger.info("Audit log retention: deleted #{deleted} old entries")
      end
      
      schedule_retention_cleanup(state.config.retention_check_interval)
    end
    
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info({:rotate_log_file}, state) do
    # Rotate log file if size exceeded
    new_state = rotate_log_file_if_needed(state)
    {:noreply, new_state}
  end
  
  @impl GenServer
  def terminate(_reason, state) do
    # Close log file
    if state.log_file do
      File.close(state.log_file)
    end
    
    :ok
  end
  
  # Private functions
  
  defp load_config(opts) do
    %{
      retention_enabled: Keyword.get(opts, :retention_enabled, true),
      retention_days: Keyword.get(opts, :retention_days, 90),
      retention_check_interval: Keyword.get(opts, :retention_check_interval, 86_400_000), # 24 hours
      file_logging_enabled: Keyword.get(opts, :file_logging_enabled, true),
      log_dir: Keyword.get(opts, :log_dir, "priv/audit_logs"),
      max_file_size: Keyword.get(opts, :max_file_size, 100_000_000), # 100MB
      streaming_enabled: Keyword.get(opts, :streaming_enabled, true),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, default_alert_thresholds())
    }
  end
  
  defp default_alert_thresholds do
    %{
      auth_failures_per_minute: 10,
      rate_limits_per_minute: 50,
      security_events_per_minute: 5
    }
  end
  
  defp init_stats do
    Map.new(@log_types, fn type -> {type, 0} end)
    |> Map.merge(%{
      total_logged: 0,
      files_rotated: 0,
      alerts_triggered: 0
    })
  end
  
  defp build_log_entry(type, event) do
    %{
      id: generate_log_id(),
      timestamp: Map.get(event, :timestamp, DateTime.utc_now()),
      type: type,
      client_id: Map.get(event, :client_id),
      user_id: Map.get(event, :user_id),
      session_id: Map.get(event, :session_id),
      operation: Map.get(event, :operation),
      params: Map.get(event, :params, %{}),
      result: Map.get(event, :result),
      metadata: build_metadata(event)
    }
  end
  
  defp build_metadata(event) do
    %{
      ip_address: Map.get(event, :ip_address),
      user_agent: Map.get(event, :user_agent),
      request_id: Map.get(event, :request_id),
      duration_ms: Map.get(event, :duration_ms),
      error_message: Map.get(event, :error_message)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
  
  defp redact_sensitive_data(entry) do
    entry
    |> update_in([:params], &redact_map/1)
    |> update_in([:metadata], &redact_map/1)
  end
  
  defp redact_map(nil), do: nil
  defp redact_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = to_string(k)
      
      if Enum.any?(@sensitive_fields, &String.contains?(key, &1)) do
        Map.put(acc, k, "[REDACTED]")
      else
        Map.put(acc, k, redact_value(v))
      end
    end)
  end
  defp redact_map(value), do: value
  
  defp redact_value(map) when is_map(map), do: redact_map(map)
  defp redact_value(list) when is_list(list), do: Enum.map(list, &redact_value/1)
  defp redact_value(value), do: value
  
  defp update_indexes(state, entry) do
    # Update user index
    if entry.user_id do
      :ets.insert(state.user_index, {entry.user_id, {entry.timestamp, entry.id}})
    end
    
    # Update operation index
    if entry.operation do
      :ets.insert(state.operation_index, {entry.operation, {entry.timestamp, entry.id}})
    end
  end
  
  defp open_log_file(%{file_logging_enabled: true} = config) do
    File.mkdir_p!(config.log_dir)
    
    filename = Path.join(config.log_dir, "mcp_audit_#{Date.to_iso8601(Date.utc_today())}.log")
    
    case File.open(filename, [:append, :utf8]) do
      {:ok, file} ->
        # Schedule file rotation check
        Process.send_after(self(), {:rotate_log_file}, 3_600_000) # 1 hour
        file
        
      {:error, reason} ->
        Logger.error("Failed to open audit log file: #{reason}")
        nil
    end
  end
  
  defp open_log_file(_), do: nil
  
  defp write_to_file(file, entry) do
    json = Jason.encode!(entry)
    IO.puts(file, json)
  rescue
    error ->
      Logger.error("Failed to write audit log: #{inspect(error)}")
  end
  
  defp stream_log_entry(entry) do
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "mcp_audit_stream",
      {:audit_log, entry}
    )
  end
  
  defp query_logs(state, filter) do
    # Build match spec based on filter
    match_spec = build_match_spec(filter)
    
    # Query main table
    results = :ets.select(state.table, match_spec)
    
    # Sort and limit
    results
    |> Enum.sort_by(fn {key, _} -> key end, :desc)
    |> Enum.take(Map.get(filter, :limit, 1000))
    |> Enum.map(fn {_, entry} -> entry end)
  end
  
  defp build_match_spec(filter) do
    guards = []
    
    # Add time range guards
    if from = filter[:from] do
      guards = [{:>, :"$1", from} | guards]
    end
    
    if to = filter[:to] do
      guards = [{:<, :"$1", to} | guards]
    end
    
    # Build basic match pattern
    match_head = {
      {:"$1", :_},  # timestamp key
      %{
        type: :"$2",
        user_id: :"$3",
        client_id: :"$4",
        operation: :"$5"
      }
    }
    
    # Add type filter
    if types = filter[:type] do
      type_list = if is_list(types), do: types, else: [types]
      guards = [{:member, :"$2", type_list} | guards]
    end
    
    # Add user filter
    if user_id = filter[:user_id] do
      guards = [{:==, :"$3", user_id} | guards]
    end
    
    # Add client filter
    if client_id = filter[:client_id] do
      guards = [{:==, :"$4", client_id} | guards]
    end
    
    # Add operation filter
    if operation = filter[:operation] do
      guards = [{:==, :"$5", operation} | guards]
    end
    
    [{match_head, guards, [:"$_"]}]
  end
  
  defp cleanup_old_logs(state) do
    cutoff = DateTime.add(DateTime.utc_now(), -state.config.retention_days, :day)
    
    # Find old entries
    old_entries = :ets.select(state.table, [
      {
        {{:"$1", :_}, :_},
        [{:<, :"$1", cutoff}],
        [:"$_"]
      }
    ])
    
    # Delete from main table and indexes
    Enum.each(old_entries, fn {{timestamp, id}, entry} ->
      :ets.delete(state.table, {timestamp, id})
      
      if entry.user_id do
        :ets.delete_object(state.user_index, {entry.user_id, {timestamp, id}})
      end
      
      if entry.operation do
        :ets.delete_object(state.operation_index, {entry.operation, {timestamp, id}})
      end
    end)
    
    length(old_entries)
  end
  
  defp export_logs_range(state, from, to, format) do
    filter = %{from: from, to: to}
    
    case query_logs(state, filter) do
      logs when is_list(logs) ->
        case format do
          "json" ->
            json = logs
            |> Enum.map(&Jason.encode!/1)
            |> Enum.join("\n")
            {:ok, json}
            
          "csv" ->
            csv = export_to_csv(logs)
            {:ok, csv}
            
          _ ->
            {:error, :unsupported_format}
        end
        
      error ->
        error
    end
  end
  
  defp export_to_csv(logs) do
    headers = ["timestamp", "type", "user_id", "client_id", "operation", "result", "ip_address"]
    
    rows = Enum.map(logs, fn log ->
      [
        DateTime.to_iso8601(log.timestamp),
        log.type,
        log.user_id || "",
        log.client_id || "",
        log.operation || "",
        inspect(log.result),
        get_in(log.metadata, [:ip_address]) || ""
      ]
    end)
    
    CSV.encode([headers | rows])
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end
  
  defp rotate_log_file_if_needed(state) do
    if state.log_file do
      {:ok, %{size: size}} = File.stat(state.log_file)
      
      if size > state.config.max_file_size do
        File.close(state.log_file)
        
        # Rename current file
        timestamp = DateTime.to_unix(DateTime.utc_now())
        :ok = File.rename(
          state.log_file,
          "#{state.log_file}.#{timestamp}"
        )
        
        # Open new file
        new_file = open_log_file(state.config)
        
        update_in(state.stats.files_rotated, &(&1 + 1))
        |> Map.put(:log_file, new_file)
      else
        state
      end
    else
      state
    end
  end
  
  defp check_security_alerts(type, entry, config) do
    # Check authentication failures
    if type == :authentication and entry.result == :failure do
      check_threshold_alert(
        :auth_failures,
        config.alert_thresholds.auth_failures_per_minute,
        "High authentication failure rate"
      )
    end
    
    # Check rate limiting
    if type == :rate_limit do
      check_threshold_alert(
        :rate_limits,
        config.alert_thresholds.rate_limits_per_minute,
        "High rate limiting activity"
      )
    end
    
    # Check security events
    if type == :security_event do
      check_threshold_alert(
        :security_events,
        config.alert_thresholds.security_events_per_minute,
        "High security event rate"
      )
    end
  end
  
  defp check_threshold_alert(metric, threshold, message) do
    # Simple threshold checking - could be enhanced with sliding windows
    # For now, just log warnings
    recent_count = count_recent_events(metric, 60)
    
    if recent_count > threshold do
      Logger.warning("Security alert: #{message} (#{recent_count} in last minute)")
      
      Phoenix.PubSub.broadcast(
        RubberDuck.PubSub,
        "mcp_security_alerts",
        {:security_alert, metric, message, recent_count}
      )
    end
  end
  
  defp count_recent_events(_metric, _seconds) do
    # Simplified - would need proper implementation
    0
  end
  
  defp update_stats(state, type) do
    state
    |> update_in([:stats, type], &(&1 + 1))
    |> update_in([:stats, :total_logged], &(&1 + 1))
  end
  
  defp get_oldest_entry(table) do
    case :ets.first(table) do
      :"$end_of_table" -> nil
      {timestamp, _id} -> timestamp
    end
  end
  
  defp get_newest_entry(table) do
    case :ets.last(table) do
      :"$end_of_table" -> nil
      {timestamp, _id} -> timestamp
    end
  end
  
  defp handle_config_changes(state, new_config) do
    # Handle file logging changes
    cond do
      not state.config.file_logging_enabled and new_config.file_logging_enabled ->
        # Open log file
        %{state | log_file: open_log_file(new_config)}
        
      state.config.file_logging_enabled and not new_config.file_logging_enabled ->
        # Close log file
        if state.log_file, do: File.close(state.log_file)
        %{state | log_file: nil}
        
      true ->
        state
    end
  end
  
  defp schedule_retention_cleanup(interval) do
    Process.send_after(self(), :retention_cleanup, interval)
  end
  
  defp init_telemetry do
    :telemetry.attach(
      "mcp_audit_logger",
      [:mcp, :audit, :log],
      &handle_telemetry_event/4,
      nil
    )
  end
  
  defp handle_telemetry_event(_event_name, measurements, metadata, _config) do
    Logger.debug("Audit telemetry: #{inspect(measurements)} #{inspect(metadata)}")
  end
  
  defp generate_log_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end