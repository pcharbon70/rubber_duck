defmodule RubberDuck.Tool.ResultProcessor do
  @moduledoc """
  Result processing pipeline for tool execution results.

  Handles post-execution result transformation, formatting, caching, and event emission.
  This module provides a comprehensive pipeline for processing tool execution results
  with support for various output formats, caching strategies, and event notifications.
  """

  require Logger

  @type processing_options :: [
          format: atom(),
          cache: boolean(),
          emit_events: boolean(),
          transform: atom(),
          persist: boolean(),
          validate: boolean()
        ]

  @type result_format :: :json | :xml | :yaml | :binary | :plain | :structured

  @type processing_result :: {:ok, processed_result()} | {:error, atom(), term()}

  @type processed_result :: %{
          output: term(),
          status: :success | :error,
          execution_time: integer(),
          metadata: map(),
          retry_count: non_neg_integer(),
          processing_metadata: map()
        }

  @doc """
  Processes a raw execution result through the complete pipeline.

  ## Parameters

  - `raw_result` - The raw result from tool execution
  - `tool_module` - The tool module that was executed
  - `context` - Execution context
  - `opts` - Processing options

  ## Options

  - `:format` - Output format (:json, :xml, :yaml, :binary, :plain, :structured)
  - `:cache` - Whether to cache the result (default: true)
  - `:emit_events` - Whether to emit processing events (default: true)
  - `:transform` - Result transformation strategy (default: :default)
  - `:persist` - Whether to persist result to storage (default: false)
  - `:validate` - Whether to validate result structure (default: true)

  ## Returns

  - `{:ok, processed_result}` - Successfully processed result
  - `{:error, :processing_failed, reason}` - Processing failed
  - `{:error, :validation_failed, errors}` - Result validation failed
  - `{:error, :formatting_failed, reason}` - Output formatting failed
  """
  @spec process_result(term(), module(), map(), processing_options()) :: processing_result()
  def process_result(raw_result, tool_module, context, opts \\ []) do
    processing_start = System.monotonic_time(:millisecond)

    with {:ok, validated_result} <- validate_result(raw_result, tool_module, opts),
         {:ok, transformed_result} <- transform_result(validated_result, tool_module, context, opts),
         {:ok, formatted_result} <- format_result(transformed_result, tool_module, opts),
         {:ok, enriched_result} <- enrich_result(formatted_result, tool_module, context, opts),
         :ok <- cache_result(enriched_result, tool_module, context, opts),
         :ok <- persist_result(enriched_result, tool_module, context, opts),
         :ok <- emit_processing_events(enriched_result, tool_module, context, opts) do
      processing_time = System.monotonic_time(:millisecond) - processing_start

      final_result = add_processing_metadata(enriched_result, processing_time, opts)

      {:ok, final_result}
    else
      {:error, reason, details} -> {:error, reason, details}
      {:error, reason} -> {:error, :processing_failed, reason}
    end
  end

  @doc """
  Formats a result according to the specified format.

  ## Examples

      iex> ResultProcessor.format_output("hello world", :json)
      {:ok, "\\\"hello world\\\""}
      
      iex> ResultProcessor.format_output(%{message: "hello"}, :xml)
      {:ok, "<message>hello</message>"}
  """
  @spec format_output(term(), result_format()) :: {:ok, term()} | {:error, atom(), term()}
  def format_output(output, format) do
    case format do
      :json -> format_json(output)
      :xml -> format_xml(output)
      :yaml -> format_yaml(output)
      :binary -> format_binary(output)
      :plain -> format_plain(output)
      :structured -> {:ok, output}
      _ -> {:error, :unsupported_format, format}
    end
  end

  @doc """
  Validates a result structure against tool requirements.
  """
  @spec validate_result_structure(term(), module()) :: {:ok, term()} | {:error, atom(), term()}
  def validate_result_structure(result, _tool_module) do
    try do
      case result do
        %{output: _, status: status, execution_time: time, metadata: _, retry_count: _}
        when status in [:success, :error] and is_integer(time) ->
          {:ok, result}

        %{output: _, status: status} when status in [:success, :error] ->
          # Add missing fields with defaults
          enriched =
            result
            |> Map.put_new(:execution_time, 0)
            |> Map.put_new(:metadata, %{})
            |> Map.put_new(:retry_count, 0)

          {:ok, enriched}

        _ ->
          {:error, :invalid_structure, "Result must contain output and status fields"}
      end
    rescue
      error -> {:error, :validation_error, Exception.message(error)}
    end
  end

  @doc """
  Transforms result output using specified transformer.
  """
  @spec transform_output(term(), atom(), module(), map()) :: {:ok, term()} | {:error, atom(), term()}
  def transform_output(output, transformer, tool_module, context) do
    case transformer do
      :default -> {:ok, output}
      :sanitize -> sanitize_output(output)
      :compress -> compress_output(output)
      :encrypt -> encrypt_output(output, context)
      :normalize -> normalize_output(output, tool_module)
      _ -> {:error, :unsupported_transformer, transformer}
    end
  end

  @doc """
  Caches a processed result.
  """
  @spec cache_processed_result(processed_result(), module(), map(), keyword()) :: :ok | {:error, atom()}
  def cache_processed_result(result, tool_module, context, opts \\ []) do
    if Keyword.get(opts, :cache, true) do
      cache_key = build_cache_key(tool_module, context, opts)
      # 1 hour default
      ttl = Keyword.get(opts, :cache_ttl, 3600)

      case cache_store().put(cache_key, result, ttl) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to cache result: #{inspect(reason)}")
          # Don't fail processing if cache fails
          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Retrieves a cached result.
  """
  @spec get_cached_result(module(), map(), keyword()) :: {:ok, processed_result()} | {:error, :not_found}
  def get_cached_result(tool_module, context, opts \\ []) do
    cache_key = build_cache_key(tool_module, context, opts)

    case cache_store().get(cache_key) do
      {:ok, result} -> {:ok, result}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  @doc """
  Persists a processed result to storage.
  """
  @spec persist_processed_result(processed_result(), module(), map(), keyword()) :: :ok | {:error, atom()}
  def persist_processed_result(result, tool_module, context, opts \\ []) do
    if Keyword.get(opts, :persist, false) do
      storage_key = build_storage_key(tool_module, context)

      case storage_backend().store(storage_key, result) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to persist result: #{inspect(reason)}")
          {:error, :persistence_failed}
      end
    else
      :ok
    end
  end

  # Private functions

  defp validate_result(raw_result, tool_module, opts) do
    if Keyword.get(opts, :validate, true) do
      validate_result_structure(raw_result, tool_module)
    else
      {:ok, raw_result}
    end
  end

  defp transform_result(result, tool_module, context, opts) do
    transformer = Keyword.get(opts, :transform, :default)

    case transform_output(result.output, transformer, tool_module, context) do
      {:ok, transformed_output} ->
        {:ok, %{result | output: transformed_output}}

      {:error, reason, details} ->
        {:error, :transformation_failed, {reason, details}}
    end
  end

  defp format_result(result, _tool_module, opts) do
    format = Keyword.get(opts, :format, :structured)

    case format_output(result.output, format) do
      {:ok, formatted_output} ->
        {:ok, %{result | output: formatted_output}}

      {:error, reason, details} ->
        {:error, :formatting_failed, {reason, details}}
    end
  end

  defp enrich_result(result, tool_module, context, opts) do
    # Add additional metadata and context
    enriched_metadata =
      result.metadata
      |> Map.put(:tool_module, tool_module)
      |> Map.put(:processing_options, opts)
      |> Map.put(:context_id, context[:execution_id])
      |> Map.put(:processed_at, DateTime.utc_now())
      |> Map.put(:format, Keyword.get(opts, :format, :structured))
      |> Map.put(:transformer, Keyword.get(opts, :transform, :default))

    enriched_result = %{result | metadata: enriched_metadata}

    {:ok, enriched_result}
  end

  defp cache_result(result, tool_module, context, opts) do
    if Keyword.get(opts, :cache, true) do
      cache_key = build_cache_key(tool_module, context, opts)
      # 1 hour default
      ttl = Keyword.get(opts, :cache_ttl, 3600)

      case RubberDuck.Cache.ETS.put(cache_key, result, ttl: ttl) do
        :ok ->
          # Emit cache event
          emit_cache_event(:cached, tool_module, context, cache_key)
          :ok

        {:error, _reason} ->
          # Log but don't fail on cache errors
          :ok
      end
    else
      :ok
    end
  end

  defp persist_result(result, tool_module, context, opts) do
    case persist_processed_result(result, tool_module, context, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, :persistence_failed, reason}
    end
  end

  defp emit_processing_events(result, tool_module, context, opts) do
    if Keyword.get(opts, :emit_events, true) do
      emit_result_processed_event(result, tool_module, context)
      emit_telemetry_event(result, tool_module, context)
    end

    :ok
  end

  defp add_processing_metadata(result, processing_time, opts) do
    processing_metadata = %{
      processing_time: processing_time,
      processed_at: DateTime.utc_now(),
      processing_options: opts,
      version: "1.0"
    }

    Map.put(result, :processing_metadata, processing_metadata)
  end

  defp format_json(output) do
    try do
      {:ok, Jason.encode!(output)}
    rescue
      error -> {:error, :json_encoding_failed, Exception.message(error)}
    end
  end

  defp format_xml(output) when is_map(output) do
    try do
      xml_content = map_to_xml(output)
      {:ok, xml_content}
    rescue
      error -> {:error, :xml_encoding_failed, Exception.message(error)}
    end
  end

  defp format_xml(output) when is_binary(output) do
    {:ok, "<data>#{output}</data>"}
  end

  defp format_xml(output) do
    {:ok, "<data>#{inspect(output)}</data>"}
  end

  defp format_yaml(output) do
    try do
      # Simple YAML-like format for basic types
      yaml_content = to_yaml(output)
      {:ok, yaml_content}
    rescue
      error -> {:error, :yaml_encoding_failed, Exception.message(error)}
    end
  end

  defp format_binary(output) when is_binary(output) do
    {:ok, output}
  end

  defp format_binary(output) do
    try do
      {:ok, :erlang.term_to_binary(output)}
    rescue
      error -> {:error, :binary_encoding_failed, Exception.message(error)}
    end
  end

  defp format_plain(output) when is_binary(output) do
    {:ok, output}
  end

  defp format_plain(output) do
    {:ok, to_string(output)}
  end

  defp sanitize_output(output) when is_binary(output) do
    # Remove potentially dangerous characters
    sanitized =
      output
      |> String.replace(~r/[<>&"']/, "")
      |> String.replace(~r/\p{C}/, "")

    {:ok, sanitized}
  end

  defp sanitize_output(output) when is_map(output) do
    try do
      sanitized =
        Map.new(output, fn {k, v} ->
          {:ok, clean_v} = sanitize_output(v)
          {k, clean_v}
        end)

      {:ok, sanitized}
    rescue
      error -> {:error, :sanitization_failed, Exception.message(error)}
    end
  end

  defp sanitize_output(output) do
    {:ok, output}
  end

  defp compress_output(output) when is_binary(output) do
    try do
      compressed = :zlib.compress(output)
      {:ok, compressed}
    rescue
      error -> {:error, :compression_failed, Exception.message(error)}
    end
  end

  defp compress_output(output) do
    try do
      binary_output = :erlang.term_to_binary(output)
      compressed = :zlib.compress(binary_output)
      {:ok, compressed}
    rescue
      error -> {:error, :compression_failed, Exception.message(error)}
    end
  end

  defp encrypt_output(output, context) do
    # Simple encryption placeholder - in production use proper encryption
    try do
      secret = context[:encryption_key] || "default_secret"
      encrypted = :crypto.crypto_one_time(:aes_128_cbc, secret, "1234567890123456", to_string(output), true)
      {:ok, encrypted}
    rescue
      error -> {:error, :encryption_failed, Exception.message(error)}
    end
  end

  defp normalize_output(output, _tool_module) do
    # Normalize output based on tool type
    case output do
      %{} = map -> {:ok, Map.new(map, fn {k, v} -> {to_string(k), v} end)}
      list when is_list(list) -> {:ok, Enum.map(list, &normalize_item/1)}
      _ -> {:ok, output}
    end
  end

  defp normalize_item(item) when is_map(item) do
    Map.new(item, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_item(item), do: item

  defp map_to_xml(map) do
    content =
      Enum.map(map, fn {k, v} ->
        "<#{k}>#{xml_escape(v)}</#{k}>"
      end)
      |> Enum.join("")

    "<result>#{content}</result>"
  end

  defp xml_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp xml_escape(value), do: to_string(value)

  defp to_yaml(map) when is_map(map) do
    content =
      Enum.map(map, fn {k, v} ->
        "#{k}: #{yaml_value(v)}"
      end)
      |> Enum.join("\n")

    "---\n#{content}"
  end

  defp to_yaml(value), do: yaml_value(value)

  defp yaml_value(value) when is_binary(value), do: "\"#{value}\""
  defp yaml_value(value) when is_number(value), do: to_string(value)
  defp yaml_value(value) when is_boolean(value), do: to_string(value)
  defp yaml_value(value), do: "\"#{inspect(value)}\""

  defp build_cache_key(tool_module, context, opts) do
    metadata = RubberDuck.Tool.metadata(tool_module)
    format = Keyword.get(opts, :format, :structured)
    transformer = Keyword.get(opts, :transform, :default)

    key_parts = [
      metadata.name,
      context[:execution_id],
      format,
      transformer
    ]

    "result:#{Enum.join(key_parts, ":")}"
  end

  defp build_storage_key(tool_module, context) do
    metadata = RubberDuck.Tool.metadata(tool_module)
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    "results/#{metadata.name}/#{context[:execution_id]}/#{timestamp}"
  end

  defp emit_result_processed_event(result, tool_module, context) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    event_data = %{
      tool: metadata.name,
      user: context.user,
      result: result,
      processing_time: result.processing_metadata.processing_time
    }

    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "tool_results",
      {:result_processed, event_data}
    )
  end

  defp emit_telemetry_event(result, tool_module, context) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    :telemetry.execute(
      [:rubber_duck, :tool, :result, :processed],
      %{
        processing_time: result.processing_metadata.processing_time,
        output_size: calculate_output_size(result.output)
      },
      %{
        tool: metadata.name,
        user_id: context.user.id,
        status: result.status,
        format: result.metadata.format
      }
    )
  end

  defp calculate_output_size(output) when is_binary(output) do
    byte_size(output)
  end

  defp calculate_output_size(output) do
    try do
      output
      |> :erlang.term_to_binary()
      |> byte_size()
    rescue
      _ -> 0
    end
  end

  defp cache_store do
    # In production, this would be configurable
    RubberDuck.Cache.ETS
  end

  defp storage_backend do
    # In production, this would be configurable
    RubberDuck.Storage.FileSystem
  end

  defp emit_cache_event(event, tool_module, context, cache_key) do
    metadata = RubberDuck.Tool.metadata(tool_module)

    RubberDuck.Tool.Telemetry.cache_operation(
      metadata.name,
      event,
      :success,
      %{cache_key: cache_key, execution_id: context[:execution_id]}
    )
  end
end
