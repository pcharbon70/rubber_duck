defmodule RubberDuck.Interface.Transformer do
  @moduledoc """
  Transforms requests and responses between interface-specific and internal formats.
  
  This module provides utilities for normalizing requests from different interfaces
  into a unified internal format, and denormalizing responses back to interface-specific
  formats. It handles type conversions, field transformations, and metadata management.
  """

  alias RubberDuck.Interface.Behaviour

  @type transformation_rule :: {atom(), atom()} | {atom(), atom(), function()}
  @type transformation_config :: %{
    required(:field_mappings) => [transformation_rule()],
    optional(:type_conversions) => map(),
    optional(:defaults) => map(),
    optional(:validators) => map()
  }

  @doc """
  Normalizes a request from interface-specific format to internal format.
  
  ## Parameters
  - `request` - The interface-specific request
  - `interface` - The source interface (e.g., :cli, :web, :lsp)
  - `config` - Optional transformation configuration
  
  ## Returns
  - `{:ok, normalized_request}` - Successfully normalized request
  - `{:error, reason}` - Normalization failed
  
  ## Examples
  
      # CLI request normalization
      iex> cli_request = %{"operation" => "chat", "message" => "Hello"}
      iex> Transformer.normalize_request(cli_request, :cli)
      {:ok, %{
        id: "req_...",
        operation: :chat,
        params: %{message: "Hello"},
        interface: :cli,
        timestamp: ~U[...]
      }}
  """
  def normalize_request(request, interface, config \\ %{}) do
    try do
      normalized = request
      |> ensure_map()
      |> add_default_fields(interface)
      |> apply_field_mappings(get_field_mappings(interface, config))
      |> apply_type_conversions(get_type_conversions(interface, config))
      |> apply_defaults(get_defaults(interface, config))
      |> validate_normalized(get_validators(interface, config))
      
      {:ok, normalized}
    rescue
      error -> {:error, "Normalization failed: #{inspect(error)}"}
    end
  end

  @doc """
  Denormalizes a response from internal format to interface-specific format.
  
  ## Parameters
  - `response` - The internal response
  - `interface` - The target interface
  - `original_request` - The original request for context
  - `config` - Optional transformation configuration
  
  ## Returns
  - `{:ok, denormalized_response}` - Successfully denormalized response
  - `{:error, reason}` - Denormalization failed
  """
  def denormalize_response(response, interface, original_request \\ %{}, config \\ %{}) do
    try do
      denormalized = response
      |> ensure_map()
      |> apply_response_field_mappings(get_response_field_mappings(interface, config))
      |> apply_response_type_conversions(get_response_type_conversions(interface, config))
      |> add_interface_metadata(interface, original_request)
      |> sanitize_response(interface, config)
      
      {:ok, denormalized}
    rescue
      error -> {:error, "Denormalization failed: #{inspect(error)}"}
    end
  end

  @doc """
  Extracts and normalizes context from a raw request.
  
  ## Parameters
  - `raw_request` - The raw request from the interface
  - `interface` - The source interface
  
  ## Returns
  - `{:ok, context}` - Extracted context
  - `{:error, reason}` - Context extraction failed
  """
  def extract_context(raw_request, interface) do
    try do
      context = case interface do
        :cli ->
          extract_cli_context(raw_request)
        :web ->
          extract_web_context(raw_request)
        :lsp ->
          extract_lsp_context(raw_request)
        _ ->
          extract_generic_context(raw_request)
      end
      
      {:ok, context}
    rescue
      error -> {:error, "Context extraction failed: #{inspect(error)}"}
    end
  end

  @doc """
  Merges metadata from request and response processing.
  
  ## Parameters
  - `request_metadata` - Metadata from request processing
  - `response_metadata` - Metadata from response processing
  
  ## Returns
  - Merged metadata map
  """
  def merge_metadata(request_metadata, response_metadata) do
    Map.merge(request_metadata || %{}, response_metadata || %{}, fn
      _k, v1, v2 when is_map(v1) and is_map(v2) -> Map.merge(v1, v2)
      _k, _v1, v2 -> v2  # Response metadata takes precedence
    end)
  end

  @doc """
  Sanitizes data by removing sensitive information.
  
  ## Parameters
  - `data` - Data to sanitize
  - `sensitive_fields` - List of sensitive field names
  
  ## Returns
  - Sanitized data
  """
  def sanitize_data(data, sensitive_fields \\ [:password, :token, :secret, :key, :auth]) do
    sanitize_recursive(data, sensitive_fields)
  end

  # Private functions

  defp ensure_map(data) when is_map(data), do: data
  defp ensure_map(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{raw: data}
    end
  end
  defp ensure_map(data), do: %{raw: data}

  defp add_default_fields(request, interface) do
    request
    |> Map.put_new(:id, Behaviour.generate_request_id())
    |> Map.put_new(:interface, interface)
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> Map.put_new(:priority, :normal)
  end

  defp apply_field_mappings(data, mappings) do
    Enum.reduce(mappings, data, fn mapping, acc ->
      apply_field_mapping(acc, mapping)
    end)
  end

  defp apply_field_mapping(data, {from_field, to_field}) do
    case Map.pop(data, from_field) do
      {nil, data} -> data
      {value, data} -> Map.put(data, to_field, value)
    end
  end

  defp apply_field_mapping(data, {from_field, to_field, transformer}) when is_function(transformer) do
    case Map.get(data, from_field) do
      nil -> data
      value ->
        try do
          transformed = transformer.(value)
          data
          |> Map.delete(from_field)
          |> Map.put(to_field, transformed)
        rescue
          _ -> data  # Keep original if transformation fails
        end
    end
  end

  defp apply_type_conversions(data, conversions) do
    Enum.reduce(conversions, data, fn {field, converter}, acc ->
      case Map.get(acc, field) do
        nil -> acc
        value ->
          try do
            converted = apply_type_converter(value, converter)
            Map.put(acc, field, converted)
          rescue
            _ -> acc  # Keep original if conversion fails
          end
      end
    end)
  end

  defp apply_type_converter(value, :string) when not is_binary(value), do: to_string(value)
  defp apply_type_converter(value, :atom) when is_binary(value), do: String.to_existing_atom(value)
  defp apply_type_converter(value, :integer) when is_binary(value), do: String.to_integer(value)
  defp apply_type_converter(value, :float) when is_binary(value), do: String.to_float(value)
  defp apply_type_converter(value, :boolean) when value in ["true", "1", 1], do: true
  defp apply_type_converter(value, :boolean) when value in ["false", "0", 0], do: false
  defp apply_type_converter(value, converter) when is_function(converter), do: converter.(value)
  defp apply_type_converter(value, _), do: value

  defp apply_defaults(data, defaults) do
    Map.merge(defaults, data)
  end

  defp validate_normalized(data, validators) do
    Enum.reduce_while(validators, data, fn {field, validator}, acc ->
      case Map.get(acc, field) do
        nil -> {:cont, acc}
        value ->
          if validator.(value) do
            {:cont, acc}
          else
            {:halt, raise("Validation failed for field #{field}")}
          end
      end
    end)
  end

  defp apply_response_field_mappings(response, mappings) do
    apply_field_mappings(response, mappings)
  end

  defp apply_response_type_conversions(response, conversions) do
    apply_type_conversions(response, conversions)
  end

  defp add_interface_metadata(response, interface, original_request) do
    metadata = %{
      interface: interface,
      request_id: Map.get(original_request, :id),
      processed_at: DateTime.utc_now()
    }
    
    Map.update(response, :metadata, metadata, &Map.merge(metadata, &1))
  end

  defp sanitize_response(response, interface, config) do
    sensitive_fields = get_sensitive_fields(interface, config)
    sanitize_data(response, sensitive_fields)
  end

  defp extract_cli_context(request) do
    %{
      user_id: Map.get(request, "user"),
      session_id: Map.get(request, "session"),
      working_directory: Map.get(request, "cwd"),
      environment: Map.get(request, "env", %{}),
      arguments: Map.get(request, "args", [])
    }
  end

  defp extract_web_context(request) do
    headers = Map.get(request, "headers", %{})
    
    %{
      user_id: get_header(headers, "x-user-id"),
      session_id: get_header(headers, "x-session-id"),
      auth_token: get_auth_token(headers),
      source_ip: get_header(headers, "x-forwarded-for") || get_header(headers, "x-real-ip"),
      user_agent: get_header(headers, "user-agent"),
      origin: get_header(headers, "origin"),
      referer: get_header(headers, "referer")
    }
  end

  defp extract_lsp_context(request) do
    %{
      workspace_uri: Map.get(request, "workspaceUri"),
      document_uri: Map.get(request, "textDocument", %{}) |> Map.get("uri"),
      client_name: Map.get(request, "clientInfo", %{}) |> Map.get("name"),
      client_version: Map.get(request, "clientInfo", %{}) |> Map.get("version"),
      capabilities: Map.get(request, "capabilities", %{})
    }
  end

  defp extract_generic_context(request) do
    Map.take(request, ["user_id", "session_id", "metadata"])
    |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp get_header(headers, name) do
    headers[name] || headers[String.downcase(name)] || headers[String.upcase(name)]
  end

  defp get_auth_token(headers) do
    case get_header(headers, "authorization") do
      "Bearer " <> token -> token
      token when is_binary(token) -> token
      _ -> nil
    end
  end

  defp sanitize_recursive(data, sensitive_fields) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      cond do
        key_sensitive?(key, sensitive_fields) ->
          Map.put(acc, key, "[REDACTED]")
        is_map(value) or is_list(value) ->
          Map.put(acc, key, sanitize_recursive(value, sensitive_fields))
        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp sanitize_recursive(data, sensitive_fields) when is_list(data) do
    Enum.map(data, &sanitize_recursive(&1, sensitive_fields))
  end

  defp sanitize_recursive(data, _), do: data

  defp key_sensitive?(key, sensitive_fields) when is_atom(key) do
    Enum.any?(sensitive_fields, fn field ->
      key == field or String.contains?(Atom.to_string(key), Atom.to_string(field))
    end)
  end

  defp key_sensitive?(key, sensitive_fields) when is_binary(key) do
    key_atom = String.to_atom(String.downcase(key))
    key_sensitive?(key_atom, sensitive_fields)
  end

  defp key_sensitive?(_, _), do: false

  # Configuration getters with defaults

  defp get_field_mappings(:cli, config), do: Map.get(config, :cli_field_mappings, default_cli_mappings())
  defp get_field_mappings(:web, config), do: Map.get(config, :web_field_mappings, default_web_mappings())
  defp get_field_mappings(:lsp, config), do: Map.get(config, :lsp_field_mappings, default_lsp_mappings())
  defp get_field_mappings(_, config), do: Map.get(config, :field_mappings, [])

  defp get_type_conversions(:cli, config), do: Map.get(config, :cli_type_conversions, default_cli_conversions())
  defp get_type_conversions(_, config), do: Map.get(config, :type_conversions, %{})

  defp get_defaults(interface, config), do: Map.get(config, :"#{interface}_defaults", %{})

  defp get_validators(interface, config), do: Map.get(config, :"#{interface}_validators", %{})

  defp get_response_field_mappings(interface, config) do
    Map.get(config, :"#{interface}_response_mappings", [])
  end

  defp get_response_type_conversions(interface, config) do
    Map.get(config, :"#{interface}_response_conversions", %{})
  end

  defp get_sensitive_fields(interface, config) do
    default_sensitive = [:password, :token, :secret, :key, :auth, :authorization]
    Map.get(config, :"#{interface}_sensitive_fields", default_sensitive)
  end

  # Default transformation configurations

  defp default_cli_mappings do
    [
      {"command", :operation},
      {"args", :params, &normalize_cli_args/1},
      {"message", :params, &(&1 |> Map.new() |> Map.put(:message, &1))},
      {"options", :params, &Map.merge(&2 || %{}, &1)}
    ]
  end

  defp default_web_mappings do
    [
      {"method", :operation, &String.to_atom(String.downcase(&1))},
      {"body", :params},
      {"query", :params, &Map.merge(&2 || %{}, &1)}
    ]
  end

  defp default_lsp_mappings do
    [
      {"method", :operation, &String.to_atom(&1)},
      {"params", :params}
    ]
  end

  defp default_cli_conversions do
    %{
      operation: :atom
    }
  end

  defp normalize_cli_args(args) when is_list(args) do
    args
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn
      [key, value], acc when is_binary(key) ->
        atom_key = key |> String.trim_leading("-") |> String.to_atom()
        Map.put(acc, atom_key, value)
      [key], acc when is_binary(key) ->
        atom_key = key |> String.trim_leading("-") |> String.to_atom()
        Map.put(acc, atom_key, true)
      _, acc ->
        acc
    end)
  end

  defp normalize_cli_args(args), do: args
end