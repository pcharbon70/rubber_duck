defmodule RubberDuck.Jido.Actions.Middleware.LoggingMiddleware do
  @moduledoc """
  Middleware for structured logging of action execution.
  
  This middleware logs action execution details including parameters,
  results, duration, and errors. It supports different log levels
  and can filter sensitive data from logs.
  
  ## Options
  
  - `:level` - Log level (:debug, :info, :warning, :error). Default: :info
  - `:log_params` - Whether to log parameters. Default: true
  - `:log_result` - Whether to log results. Default: false
  - `:filter_keys` - List of keys to filter from logs. Default: [:password, :token, :secret]
  - `:metadata` - Additional metadata to include in logs
  """
  
  use RubberDuck.Jido.Actions.Middleware, priority: 90
  require Logger
  
  @impl true
  def init(opts) do
    config = %{
      level: Keyword.get(opts, :level, :info),
      log_params: Keyword.get(opts, :log_params, true),
      log_result: Keyword.get(opts, :log_result, false),
      filter_keys: Keyword.get(opts, :filter_keys, [:password, :token, :secret, :api_key]),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    {:ok, config}
  end
  
  @impl true
  def call(action, params, context, next) do
    {:ok, config} = init([])
    
    # Generate request ID for correlation
    request_id = generate_request_id()
    
    # Log action start
    log_start(action, params, context, config, request_id)
    
    # Execute action with timing
    start_time = System.monotonic_time(:microsecond)
    
    result = try do
      next.(params, context)
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time
        log_error(action, error, duration, config, request_id)
        reraise error, __STACKTRACE__
    end
    
    # Calculate duration
    duration = System.monotonic_time(:microsecond) - start_time
    
    # Log action completion
    log_completion(action, result, duration, config, request_id)
    
    result
  end
  
  # Private functions
  
  defp log_start(action, params, context, config, request_id) do
    metadata = build_metadata(action, context, config, request_id)
    
    message = "Action starting: #{inspect(action)}"
    
    log_data = %{
      event: "action.start",
      action: inspect(action),
      request_id: request_id
    }
    
    log_data = if config.log_params do
      Map.put(log_data, :params, filter_sensitive(params, config.filter_keys))
    else
      log_data
    end
    
    log(config.level, message, Map.merge(metadata, log_data))
  end
  
  defp log_completion(action, result, duration, config, request_id) do
    metadata = build_metadata(action, %{}, config, request_id)
    
    {status, message} = case result do
      {:ok, _, _} -> {:success, "Action completed successfully: #{inspect(action)}"}
      {:error, _} -> {:failure, "Action failed: #{inspect(action)}"}
    end
    
    log_data = %{
      event: "action.complete",
      action: inspect(action),
      request_id: request_id,
      status: status,
      duration_us: duration,
      duration_ms: div(duration, 1000)
    }
    
    log_data = case result do
      {:ok, result_data, _} when config.log_result ->
        Map.put(log_data, :result, filter_sensitive(result_data, config.filter_keys))
      {:error, error} ->
        Map.put(log_data, :error, inspect(error))
      _ ->
        log_data
    end
    
    level = if status == :success, do: config.level, else: :warning
    log(level, message, Map.merge(metadata, log_data))
  end
  
  defp log_error(action, error, duration, config, request_id) do
    metadata = build_metadata(action, %{}, config, request_id)
    
    log_data = %{
      event: "action.error",
      action: inspect(action),
      request_id: request_id,
      error: inspect(error),
      error_message: Exception.message(error),
      duration_us: duration,
      duration_ms: div(duration, 1000)
    }
    
    log(:error, "Action crashed: #{inspect(action)} - #{Exception.message(error)}", 
        Map.merge(metadata, log_data))
  end
  
  defp build_metadata(action, context, config, request_id) do
    %{
      middleware: "LoggingMiddleware",
      request_id: request_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Map.merge(config.metadata)
    |> Map.merge(extract_context_metadata(context))
  end
  
  defp extract_context_metadata(%{agent: %{id: agent_id}}), do: %{agent_id: agent_id}
  defp extract_context_metadata(%{agent: agent}) when is_atom(agent), do: %{agent: agent}
  defp extract_context_metadata(_), do: %{}
  
  defp filter_sensitive(data, filter_keys) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      cond do
        key in filter_keys ->
          Map.put(acc, key, "[FILTERED]")
        is_map(value) ->
          Map.put(acc, key, filter_sensitive(value, filter_keys))
        is_list(value) ->
          Map.put(acc, key, filter_sensitive_list(value, filter_keys))
        true ->
          Map.put(acc, key, value)
      end
    end)
  end
  defp filter_sensitive(data, _), do: data
  
  defp filter_sensitive_list(list, filter_keys) do
    Enum.map(list, fn item ->
      if is_map(item), do: filter_sensitive(item, filter_keys), else: item
    end)
  end
  
  defp generate_request_id do
    "req_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp log(:debug, message, metadata), do: Logger.debug(message, metadata)
  defp log(:info, message, metadata), do: Logger.info(message, metadata)
  defp log(:warning, message, metadata), do: Logger.warning(message, metadata)
  defp log(:error, message, metadata), do: Logger.error(message, metadata)
  defp log(_, message, metadata), do: Logger.info(message, metadata)
end