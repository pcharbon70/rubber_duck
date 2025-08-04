defmodule RubberDuck.Jido.Signals.Pipeline.SignalEnricher do
  @moduledoc """
  Enriches signals with additional context and metadata.
  
  This transformer adds contextual information to signals such as
  system metadata, correlation IDs, trace information, and domain-specific
  data while maintaining CloudEvents compliance.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalTransformer,
    name: "SignalEnricher",
    priority: 90  # Run after normalizer
  
  alias RubberDuck.Jido.Signals.SignalCategory
  
  @impl true
  def transform(signal, opts) do
    enrichers = Keyword.get(opts, :enrichers, default_enrichers())
    
    enriched = Enum.reduce(enrichers, signal, fn enricher, acc ->
      apply_enricher(enricher, acc, opts)
    end)
    
    {:ok, enriched}
  rescue
    error ->
      Logger.error("Enrichment failed: #{inspect(error)}")
      {:error, {:enrichment_failed, error}}
  end
  
  @impl true
  def should_transform?(signal, opts) do
    # Skip if already enriched recently
    case Map.get(signal, :_enriched_at) do
      nil -> true
      timestamp ->
        ttl = Keyword.get(opts, :enrichment_ttl, :timer.minutes(5))
        age = DateTime.diff(DateTime.utc_now(), timestamp, :millisecond)
        age > ttl
    end
  end
  
  # Private enricher functions
  
  defp apply_enricher(:metadata, signal, _opts) do
    signal
    |> Map.put(:_enriched_at, DateTime.utc_now())
    |> Map.put(:_enriched_by, node())
    |> Map.update(:extensions, %{}, fn ext ->
      Map.merge(ext, %{
        "enriched" => true,
        "enrichment_version" => "1.0",
        "node" => to_string(node()),
        "otp_release" => to_string(:erlang.system_info(:otp_release))
      })
    end)
  end
  
  defp apply_enricher(:category, signal, _opts) do
    # Add category information
    case SignalCategory.infer_category(signal.type) do
      {:ok, category} ->
        signal
        |> Map.put(:category, category)
        |> Map.put(:priority, Map.get(signal, :priority, SignalCategory.default_priority(category)))
        |> update_in([:extensions], fn ext ->
          Map.put(ext || %{}, "category", to_string(category))
        end)
      _ ->
        signal
    end
  end
  
  defp apply_enricher(:correlation, signal, opts) do
    correlation_id = Map.get(signal, :correlation_id) || 
                    Keyword.get(opts, :correlation_id) ||
                    generate_correlation_id()
    
    trace_id = Map.get(signal, :trace_id) ||
              Keyword.get(opts, :trace_id) ||
              correlation_id
    
    signal
    |> Map.put(:correlation_id, correlation_id)
    |> Map.put(:trace_id, trace_id)
    |> update_in([:extensions], fn ext ->
      Map.merge(ext || %{}, %{
        "correlationid" => correlation_id,
        "traceid" => trace_id,
        "spanid" => generate_span_id()
      })
    end)
  end
  
  defp apply_enricher(:context, signal, opts) do
    context = Keyword.get(opts, :context, %{})
    
    # Add contextual data to signal
    enriched_data = signal
      |> Map.get(:data, %{})
      |> Map.merge(%{
        "_context" => %{
          "environment" => Map.get(context, :environment, "production"),
          "version" => Map.get(context, :version, "unknown"),
          "region" => Map.get(context, :region, "default"),
          "tenant" => Map.get(context, :tenant),
          "user" => Map.get(context, :user)
        } |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
      })
    
    Map.put(signal, :data, enriched_data)
  end
  
  defp apply_enricher(:routing, signal, _opts) do
    # Add routing hints based on signal type and category
    routing_key = build_routing_key(signal)
    
    signal
    |> Map.put(:routing_key, routing_key)
    |> update_in([:extensions], fn ext ->
      Map.put(ext || %{}, "routingkey", routing_key)
    end)
  end
  
  defp apply_enricher(:security, signal, opts) do
    # Add security context
    security_context = Keyword.get(opts, :security_context, %{})
    
    signal
    |> update_in([:extensions], fn ext ->
      Map.merge(ext || %{}, %{
        "auth_method" => Map.get(security_context, :auth_method, "none"),
        "auth_subject" => Map.get(security_context, :subject),
        "auth_roles" => Map.get(security_context, :roles, [])
      } |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new())
    end)
  end
  
  defp apply_enricher(:telemetry, signal, _opts) do
    # Add telemetry data
    signal
    |> update_in([:extensions], fn ext ->
      Map.merge(ext || %{}, %{
        "telemetry_enabled" => true,
        "telemetry_sampled" => should_sample?(),
        "telemetry_timestamp" => System.system_time(:microsecond)
      })
    end)
  end
  
  defp apply_enricher({:custom, enricher_fn}, signal, opts) when is_function(enricher_fn) do
    case enricher_fn.(signal, opts) do
      {:ok, enriched} -> enriched
      _ -> signal
    end
  end
  
  defp apply_enricher(_, signal, _opts), do: signal
  
  # Helper functions
  
  defp default_enrichers do
    [:metadata, :category, :correlation, :context, :routing, :security, :telemetry]
  end
  
  defp generate_correlation_id do
    "corr_#{UUID.uuid4()}"
  end
  
  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp build_routing_key(signal) do
    category = Map.get(signal, :category, :unknown)
    
    # Extract domain from type
    domain = case String.split(signal.type || "", ".") do
      [d | _] -> d
      _ -> "unknown"
    end
    
    "#{domain}.#{category}"
  end
  
  defp should_sample? do
    # Simple sampling strategy - can be made configurable
    :rand.uniform() < 0.1  # 10% sampling rate
  end
end