defmodule RubberDuck.Jido.Signals.SignalValidator do
  @moduledoc """
  Validates signals against taxonomy rules and CloudEvents specification.
  
  This module ensures all signals in the system conform to the established
  taxonomy, have proper structure, and are CloudEvents-compliant through
  Jido.Signal validation.
  """
  
  alias RubberDuck.Jido.Signals.SignalCategory
  
  @required_fields [:type, :source, :data]
  @optional_fields [:subject, :id, :time, :datacontenttype, :dataschema]
  
  @type validation_result :: {:ok, map()} | {:error, [validation_error()]}
  @type validation_error :: {atom(), String.t()}
  
  @doc """
  Validates a signal against taxonomy and CloudEvents rules.
  
  ## Examples
  
      iex> validate(%{type: "user.created", source: "agent:123", data: %{}})
      {:ok, %{type: "user.created", source: "agent:123", data: %{}, category: :event}}
      
      iex> validate(%{type: "invalid"})
      {:error, [{:missing_field, "source"}, {:missing_field, "data"}]}
  """
  @spec validate(map()) :: validation_result()
  def validate(signal) do
    errors = []
      |> validate_required_fields(signal)
      |> validate_signal_type(signal)
      |> validate_source_format(signal)
      |> validate_data_field(signal)
      |> validate_optional_fields(signal)
      |> validate_category_compliance(signal)
    
    if Enum.empty?(errors) do
      enriched_signal = enrich_signal(signal)
      {:ok, enriched_signal}
    else
      {:error, errors}
    end
  end
  
  @doc """
  Validates a signal strictly as a Jido.Signal.
  """
  @spec validate_jido_signal(map()) :: {:ok, map()} | {:error, term()}
  def validate_jido_signal(signal) do
    case Jido.Signal.new(signal) do
      {:ok, jido_signal} ->
        # Extract the signal data and validate against taxonomy
        signal_map = Map.from_struct(jido_signal)
        validate(signal_map)
        
      {:error, reason} ->
        {:error, [{:jido_signal_invalid, inspect(reason)}]}
    end
  end
  
  @doc """
  Validates a batch of signals.
  """
  @spec validate_batch([map()]) :: {:ok, [map()]} | {:error, map()}
  def validate_batch(signals) do
    results = Enum.map(signals, &validate/1)
    
    valid_signals = Enum.filter_map(
      results,
      fn {status, _} -> status == :ok end,
      fn {:ok, signal} -> signal end
    )
    
    invalid_signals = Enum.filter_map(
      Enum.with_index(results),
      fn {{status, _}, _} -> status == :error end,
      fn {{:error, errors}, index} -> {index, errors} end
    )
    
    if Enum.empty?(invalid_signals) do
      {:ok, valid_signals}
    else
      {:error, %{
        valid_count: length(valid_signals),
        invalid_count: length(invalid_signals),
        errors: Map.new(invalid_signals)
      }}
    end
  end
  
  @doc """
  Checks if a signal type matches a category's patterns.
  """
  @spec matches_category?(String.t(), SignalCategory.category()) :: boolean()
  def matches_category?(signal_type, category) do
    patterns = SignalCategory.category_patterns(category)
    
    Enum.any?(patterns, fn pattern ->
      regex = pattern
        |> String.replace("*", ".*")
        |> Regex.compile!()
      
      Regex.match?(regex, signal_type)
    end)
  end
  
  @doc """
  Suggests a valid signal type based on input.
  """
  @spec suggest_type(String.t(), SignalCategory.category()) :: String.t()
  def suggest_type(base_type, category) do
    # Clean the base type
    cleaned = base_type
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9._]/, "")
    
    # Add appropriate suffix based on category
    case category do
      :request -> ensure_suffix(cleaned, ".request")
      :event -> suggest_event_suffix(cleaned)
      :command -> ensure_suffix(cleaned, ".execute")
      :query -> ensure_suffix(cleaned, ".query")
      :notification -> ensure_suffix(cleaned, ".notify")
    end
  end
  
  # Private validation functions
  
  defp validate_required_fields(errors, signal) do
    @required_fields
    |> Enum.reduce(errors, fn field, acc ->
      if Map.has_key?(signal, field) or Map.has_key?(signal, Atom.to_string(field)) do
        acc
      else
        [{:missing_field, Atom.to_string(field)} | acc]
      end
    end)
  end
  
  defp validate_signal_type(errors, signal) do
    type = Map.get(signal, :type, Map.get(signal, "type"))
    
    cond do
      is_nil(type) ->
        errors
        
      not is_binary(type) ->
        [{:invalid_type_format, "type must be a string"} | errors]
        
      String.length(type) < 3 ->
        [{:invalid_type_format, "type too short"} | errors]
        
      not String.contains?(type, ".") ->
        [{:invalid_type_format, "type must use hierarchical format (domain.action)"} | errors]
        
      true ->
        errors
    end
  end
  
  defp validate_source_format(errors, signal) do
    source = Map.get(signal, :source, Map.get(signal, "source"))
    
    cond do
      is_nil(source) ->
        errors
        
      not is_binary(source) ->
        [{:invalid_source_format, "source must be a string"} | errors]
        
      String.length(source) < 3 ->
        [{:invalid_source_format, "source too short"} | errors]
        
      not (String.contains?(source, ":") or String.contains?(source, "/")) ->
        [{:invalid_source_format, "source should identify the origin (e.g., agent:123)"} | errors]
        
      true ->
        errors
    end
  end
  
  defp validate_data_field(errors, signal) do
    data = Map.get(signal, :data, Map.get(signal, "data"))
    
    cond do
      is_nil(data) ->
        [{:missing_field, "data"} | errors]
        
      not is_map(data) ->
        [{:invalid_data_format, "data must be a map"} | errors]
        
      true ->
        errors
    end
  end
  
  defp validate_optional_fields(errors, signal) do
    Enum.reduce(@optional_fields, errors, fn field, acc ->
      value = Map.get(signal, field, Map.get(signal, Atom.to_string(field)))
      
      if not is_nil(value) do
        validate_optional_field(acc, field, value)
      else
        acc
      end
    end)
  end
  
  defp validate_optional_field(errors, :subject, subject) do
    if is_binary(subject) do
      errors
    else
      [{:invalid_field_format, "subject must be a string"} | errors]
    end
  end
  
  defp validate_optional_field(errors, :id, id) do
    if is_binary(id) and String.length(id) > 0 do
      errors
    else
      [{:invalid_field_format, "id must be a non-empty string"} | errors]
    end
  end
  
  defp validate_optional_field(errors, _, _), do: errors
  
  defp validate_category_compliance(errors, signal) do
    type = Map.get(signal, :type, Map.get(signal, "type"))
    
    if type do
      case SignalCategory.infer_category(type) do
        {:ok, category} ->
          # Check if the signal follows category conventions
          if properly_formatted_for_category?(type, category) do
            errors
          else
            [{:category_compliance, "Signal type doesn't follow #{category} conventions"} | errors]
          end
          
        {:error, :unknown_category} ->
          [{:unknown_category, "Cannot determine category for signal type: #{type}"} | errors]
      end
    else
      errors
    end
  end
  
  defp properly_formatted_for_category?(type, category) do
    # Check if type matches expected patterns for the category
    patterns = SignalCategory.category_patterns(category)
    
    Enum.any?(patterns, fn pattern ->
      regex = pattern
        |> String.replace("*", ".*")
        |> Regex.compile!()
      
      Regex.match?(regex, type)
    end)
  end
  
  defp enrich_signal(signal) do
    type = Map.get(signal, :type, Map.get(signal, "type"))
    
    # Add category information
    enriched = case SignalCategory.infer_category(type) do
      {:ok, category} ->
        Map.put(signal, :category, category)
      _ ->
        signal
    end
    
    # Add timestamp if missing
    enriched = if Map.has_key?(enriched, :time) or Map.has_key?(enriched, "time") do
      enriched
    else
      Map.put(enriched, :time, DateTime.utc_now() |> DateTime.to_iso8601())
    end
    
    # Add ID if missing
    if Map.has_key?(enriched, :id) or Map.has_key?(enriched, "id") do
      enriched
    else
      Map.put(enriched, :id, generate_signal_id())
    end
  end
  
  defp ensure_suffix(base, suffix) do
    if String.ends_with?(base, suffix) do
      base
    else
      base <> suffix
    end
  end
  
  defp suggest_event_suffix(base) do
    cond do
      String.contains?(base, "create") -> ensure_suffix(base, ".created")
      String.contains?(base, "update") -> ensure_suffix(base, ".updated")
      String.contains?(base, "delete") -> ensure_suffix(base, ".deleted")
      String.contains?(base, "complete") -> ensure_suffix(base, ".completed")
      String.contains?(base, "fail") -> ensure_suffix(base, ".failed")
      true -> ensure_suffix(base, ".occurred")
    end
  end
  
  defp generate_signal_id do
    "sig_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end
end