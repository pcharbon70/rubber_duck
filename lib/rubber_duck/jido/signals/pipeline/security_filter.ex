defmodule RubberDuck.Jido.Signals.Pipeline.SecurityFilter do
  @moduledoc """
  Filters sensitive data from signals for security.
  
  This transformer removes or masks sensitive information from signals
  to prevent data leakage, ensure compliance, and maintain security
  standards while preserving signal functionality.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalTransformer,
    name: "SecurityFilter",
    priority: 70  # Run after schema validation
  
  @impl true
  def transform(signal, opts) do
    filter_config = build_filter_config(opts)
    
    filtered = signal
      |> filter_sensitive_fields(filter_config)
      |> mask_sensitive_patterns(filter_config)
      |> redact_pii_data(filter_config)
      |> sanitize_extensions(filter_config)
    
    {:ok, mark_as_filtered(filtered)}
  rescue
    error ->
      Logger.error("Security filtering failed: #{inspect(error)}")
      # In case of error, be conservative and filter aggressively
      {:ok, emergency_filter(signal)}
  end
  
  @impl true
  def should_transform?(signal, opts) do
    # Always filter unless explicitly disabled
    Keyword.get(opts, :enabled, true) && not Map.get(signal, :_security_filtered, false)
  end
  
  # Private functions
  
  defp build_filter_config(opts) do
    %{
      sensitive_fields: Keyword.get(opts, :sensitive_fields, default_sensitive_fields()),
      patterns: Keyword.get(opts, :patterns, default_patterns()),
      pii_detection: Keyword.get(opts, :pii_detection, true),
      masking_strategy: Keyword.get(opts, :masking_strategy, :partial),
      whitelist: Keyword.get(opts, :whitelist, []),
      log_filtered: Keyword.get(opts, :log_filtered, true)
    }
  end
  
  defp filter_sensitive_fields(signal, config) do
    filtered_fields = []
    
    filtered = Enum.reduce(config.sensitive_fields, signal, fn field, acc ->
      if has_sensitive_field?(acc, field) && field not in config.whitelist do
        {updated, _} = remove_field(acc, field)
        updated
      else
        acc
      end
    end)
    
    # Filter nested data field
    filtered = if Map.has_key?(filtered, :data) do
      update_in(filtered, [:data], fn data ->
        filter_nested_sensitive(data, config)
      end)
    else
      filtered
    end
    
    if config.log_filtered && not Enum.empty?(filtered_fields) do
      Logger.debug("Filtered sensitive fields: #{inspect(filtered_fields)}")
    end
    
    filtered
  end
  
  defp filter_nested_sensitive(data, config) when is_map(data) do
    Enum.reduce(config.sensitive_fields, data, fn field, acc ->
      field_str = to_string(field)
      cond do
        Map.has_key?(acc, field) -> Map.delete(acc, field)
        Map.has_key?(acc, field_str) -> Map.delete(acc, field_str)
        true -> acc
      end
    end)
    |> Map.new(fn {k, v} ->
      {k, (if is_map(v), do: filter_nested_sensitive(v, config), else: v)}
    end)
  end
  defp filter_nested_sensitive(data, _config), do: data
  
  defp mask_sensitive_patterns(signal, config) do
    # Apply pattern-based masking to string values
    mask_in_map(signal, config.patterns, config.masking_strategy)
  end
  
  defp mask_in_map(map, patterns, strategy) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {k, mask_value(v, patterns, strategy)}
    end)
  end
  defp mask_in_map(value, patterns, strategy), do: mask_value(value, patterns, strategy)
  
  defp mask_value(value, patterns, strategy) when is_binary(value) do
    Enum.reduce(patterns, value, fn {pattern, type}, acc ->
      apply_pattern_mask(acc, pattern, type, strategy)
    end)
  end
  defp mask_value(value, patterns, strategy) when is_map(value) do
    mask_in_map(value, patterns, strategy)
  end
  defp mask_value(value, patterns, strategy) when is_list(value) do
    Enum.map(value, &mask_value(&1, patterns, strategy))
  end
  defp mask_value(value, _, _), do: value
  
  defp apply_pattern_mask(text, pattern, type, strategy) do
    Regex.replace(pattern, text, fn match ->
      mask_match(match, type, strategy)
    end)
  end
  
  defp mask_match(match, type, :full) do
    String.duplicate("*", String.length(match))
  end
  defp mask_match(match, :email, :partial) do
    case String.split(match, "@") do
      [local, domain] ->
        masked_local = String.slice(local, 0, 2) <> String.duplicate("*", max(String.length(local) - 2, 3))
        "#{masked_local}@#{domain}"
      _ -> mask_match(match, :email, :full)
    end
  end
  defp mask_match(match, :credit_card, :partial) do
    # Show last 4 digits only
    if String.length(match) >= 4 do
      String.duplicate("*", String.length(match) - 4) <> String.slice(match, -4, 4)
    else
      mask_match(match, :credit_card, :full)
    end
  end
  defp mask_match(match, :ssn, :partial) do
    # Show last 4 digits only for SSN
    if String.length(match) >= 4 do
      "***-**-" <> String.slice(match, -4, 4)
    else
      mask_match(match, :ssn, :full)
    end
  end
  defp mask_match(match, :phone, :partial) do
    # Show area code and last 2 digits
    if String.length(match) >= 10 do
      String.slice(match, 0, 3) <> "-***-**" <> String.slice(match, -2, 2)
    else
      mask_match(match, :phone, :full)
    end
  end
  defp mask_match(match, _, :partial) do
    # Generic partial masking - show first and last characters
    if String.length(match) > 2 do
      String.first(match) <> String.duplicate("*", String.length(match) - 2) <> String.last(match)
    else
      String.duplicate("*", String.length(match))
    end
  end
  
  defp redact_pii_data(signal, %{pii_detection: false} = _config), do: signal
  defp redact_pii_data(signal, config) do
    # Additional PII detection beyond patterns
    signal
    |> redact_field_by_name(config)
    |> redact_high_entropy_fields(config)
  end
  
  defp redact_field_by_name(signal, _config) do
    pii_field_names = ~w(
      ssn social_security_number
      tax_id tin
      passport passport_number
      driver_license drivers_license
      bank_account account_number
      routing_number
      pin password pwd
      secret api_key api_secret
      token access_token refresh_token
      private_key secret_key
    )
    
    Enum.reduce(pii_field_names, signal, fn field_name, acc ->
      remove_field_recursive(acc, field_name)
    end)
  end
  
  defp redact_high_entropy_fields(signal, _config) do
    # Detect and redact fields with high entropy (likely secrets)
    check_entropy_recursive(signal)
  end
  
  defp check_entropy_recursive(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      cond do
        is_binary(v) && high_entropy?(v) ->
          {k, "[REDACTED-HIGH-ENTROPY]"}
        is_map(v) ->
          {k, check_entropy_recursive(v)}
        true ->
          {k, v}
      end
    end)
  end
  defp check_entropy_recursive(value), do: value
  
  defp high_entropy?(string) when is_binary(string) do
    # Simple entropy check - could be made more sophisticated
    String.length(string) >= 20 && 
      String.match?(string, ~r/^[A-Za-z0-9+\/=_-]+$/) &&
      entropy_score(string) > 4.0
  end
  defp high_entropy?(_), do: false
  
  defp entropy_score(string) do
    # Shannon entropy calculation
    chars = String.graphemes(string)
    total = length(chars)
    
    if total == 0 do
      0.0
    else
      freq_map = Enum.frequencies(chars)
      
      Enum.reduce(freq_map, 0.0, fn {_char, count}, acc ->
        probability = count / total
        acc - probability * :math.log2(probability)
      end)
    end
  end
  
  defp sanitize_extensions(signal, _config) do
    # Remove potentially sensitive extension fields
    if Map.has_key?(signal, :extensions) do
      update_in(signal, [:extensions], fn ext ->
        ext
        |> Map.delete("auth_token")
        |> Map.delete("api_key")
        |> Map.delete("session_id")
        |> Map.delete("cookie")
      end)
    else
      signal
    end
  end
  
  defp has_sensitive_field?(map, field) do
    field_str = to_string(field)
    Map.has_key?(map, field) || Map.has_key?(map, field_str)
  end
  
  defp remove_field(map, field) do
    field_str = to_string(field)
    removed = Map.has_key?(map, field) || Map.has_key?(map, field_str)
    
    updated = map
      |> Map.delete(field)
      |> Map.delete(field_str)
    
    {updated, removed}
  end
  
  defp remove_field_recursive(map, field_name) when is_map(map) do
    map
    |> Enum.reject(fn {k, _} -> 
      String.downcase(to_string(k)) =~ field_name
    end)
    |> Map.new()
    |> Map.new(fn {k, v} ->
      {k, (if is_map(v), do: remove_field_recursive(v, field_name), else: v)}
    end)
  end
  defp remove_field_recursive(value, _), do: value
  
  defp mark_as_filtered(signal) do
    signal
    |> Map.put(:_security_filtered, true)
    |> Map.put(:_filtered_at, DateTime.utc_now())
  end
  
  defp emergency_filter(signal) do
    # Aggressive filtering for error cases
    %{
      type: Map.get(signal, :type, "unknown"),
      source: Map.get(signal, :source, "unknown"),
      data: %{message: "[FILTERED DUE TO ERROR]"},
      _security_filtered: true,
      _emergency_filtered: true
    }
  end
  
  defp default_sensitive_fields do
    [:password, :pwd, :secret, :token, :api_key, :private_key, :auth_token,
     :access_token, :refresh_token, :session_id, :cookie, :authorization,
     :credit_card, :card_number, :cvv, :ssn, :social_security_number]
  end
  
  defp default_patterns do
    %{
      # Email addresses
      ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/ => :email,
      
      # Credit card numbers (basic pattern)
      ~r/\b(?:\d[ -]*?){13,16}\b/ => :credit_card,
      
      # SSN (US)
      ~r/\b\d{3}-\d{2}-\d{4}\b/ => :ssn,
      
      # Phone numbers (US)
      ~r/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/ => :phone,
      
      # API keys (common patterns)
      ~r/[a-zA-Z0-9]{32,}/ => :api_key
    }
  end
end