defmodule RubberDuck.Jido.Signals.Pipeline.SignalNormalizer do
  @moduledoc """
  Normalizes signal formats for consistent processing.
  
  This transformer ensures all signals have a consistent structure,
  converts field names to expected formats, and handles various
  input formats while maintaining CloudEvents compliance.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalTransformer,
    name: "SignalNormalizer",
    priority: 100  # Run first
  
  alias RubberDuck.Jido.Signals.SignalValidator
  
  @impl true
  def transform(signal, opts) do
    with {:ok, normalized} <- normalize_structure(signal, opts),
         {:ok, converted} <- convert_field_names(normalized, opts),
         {:ok, validated} <- ensure_required_fields(converted, opts) do
      {:ok, validated}
    end
  end
  
  @impl true
  def should_transform?(signal, _opts) do
    # Always normalize unless already normalized
    not Map.get(signal, :_normalized, false)
  end
  
  # Private functions
  
  defp normalize_structure(signal, opts) when is_map(signal) do
    # Convert string keys to atoms for internal processing
    normalized = signal
      |> stringify_or_atomize_keys(Keyword.get(opts, :key_format, :atom))
      |> Map.put(:_normalized, true)
      |> Map.put(:_normalized_at, DateTime.utc_now())
    
    {:ok, normalized}
  end
  
  defp normalize_structure(signal, _opts) do
    {:error, {:invalid_signal_format, "Signal must be a map, got: #{inspect(signal)}"}}
  end
  
  defp convert_field_names(signal, opts) do
    field_mappings = Keyword.get(opts, :field_mappings, default_field_mappings())
    
    converted = Enum.reduce(field_mappings, signal, fn {from, to}, acc ->
      case Map.pop(acc, from) do
        {nil, _} -> acc
        {value, rest} -> Map.put(rest, to, value)
      end
    end)
    
    # Handle nested data field
    converted = if Map.has_key?(converted, :data) do
      update_in(converted, [:data], fn data ->
        normalize_data_field(data, opts)
      end)
    else
      converted
    end
    
    {:ok, converted}
  end
  
  defp ensure_required_fields(signal, opts) do
    # Add defaults for missing optional fields
    defaults = Keyword.get(opts, :defaults, default_values())
    
    with_defaults = Enum.reduce(defaults, signal, fn {field, default_fn}, acc ->
      Map.put_new_lazy(acc, field, default_fn)
    end)
    
    # Ensure CloudEvents compliance
    case ensure_cloudevents_fields(with_defaults) do
      {:ok, compliant} -> {:ok, compliant}
      error -> error
    end
  end
  
  defp stringify_or_atomize_keys(map, :atom) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
      {k, v} -> {inspect(k) |> String.to_atom(), v}
    end)
  rescue
    ArgumentError ->
      # If atom doesn't exist, keep as string
      Map.new(map, fn
        {k, v} when is_binary(k) -> {String.to_atom(k), v}
        {k, v} -> {k, v}
      end)
  end
  
  defp stringify_or_atomize_keys(map, :string) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
      {k, v} -> {inspect(k), v}
    end)
  end
  
  defp normalize_data_field(data, _opts) when is_map(data) do
    # Recursively normalize nested data
    Map.new(data, fn {k, v} ->
      key = if is_binary(k), do: k, else: to_string(k)
      value = if is_map(v), do: normalize_data_field(v, []), else: v
      {key, value}
    end)
  end
  defp normalize_data_field(data, _opts), do: data
  
  defp ensure_cloudevents_fields(signal) do
    # Required CloudEvents fields
    required = [:type, :source, :data]
    
    missing = required -- Map.keys(signal)
    
    if Enum.empty?(missing) do
      # Ensure proper formatting
      formatted = signal
        |> ensure_type_format()
        |> ensure_source_format()
        |> ensure_id_format()
        |> ensure_time_format()
      
      {:ok, formatted}
    else
      {:error, {:missing_required_fields, missing}}
    end
  end
  
  defp ensure_type_format(%{type: type} = signal) when is_binary(type) do
    # Ensure hierarchical format
    if String.contains?(type, ".") do
      signal
    else
      Map.put(signal, :type, "unknown.#{type}")
    end
  end
  defp ensure_type_format(signal), do: signal
  
  defp ensure_source_format(%{source: source} = signal) when is_binary(source) do
    # Ensure source has proper format
    if String.contains?(source, ":") or String.contains?(source, "/") do
      signal
    else
      Map.put(signal, :source, "unknown:#{source}")
    end
  end
  defp ensure_source_format(signal), do: signal
  
  defp ensure_id_format(signal) do
    Map.put_new_lazy(signal, :id, fn ->
      "sig_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
    end)
  end
  
  defp ensure_time_format(signal) do
    Map.put_new_lazy(signal, :time, fn ->
      DateTime.utc_now() |> DateTime.to_iso8601()
    end)
  end
  
  defp default_field_mappings do
    %{
      # Common variations
      "event_type" => :type,
      "eventType" => :type,
      "signal_type" => :type,
      "event_source" => :source,
      "eventSource" => :source,
      "signal_source" => :source,
      "payload" => :data,
      "body" => :data,
      "content" => :data,
      "timestamp" => :time,
      "created_at" => :time,
      "createdAt" => :time
    }
  end
  
  defp default_values do
    %{
      id: fn -> "sig_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}" end,
      time: fn -> DateTime.utc_now() |> DateTime.to_iso8601() end,
      specversion: fn -> "1.0" end,
      datacontenttype: fn -> "application/json" end
    }
  end
end