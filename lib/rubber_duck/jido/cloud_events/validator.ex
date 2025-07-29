defmodule RubberDuck.Jido.CloudEvents.Validator do
  @moduledoc """
  Validates CloudEvents according to the CloudEvents 1.0 specification.
  
  This module ensures strict compliance with the CloudEvents spec,
  validating all required fields and their types.
  
  ## Required Fields
  - `specversion` - Must be "1.0"
  - `id` - Unique identifier for the event
  - `source` - URI-reference identifying the event source
  - `type` - Type of event occurrence
  
  ## Optional Fields
  - `datacontenttype` - Content type of the data field
  - `dataschema` - URI of the schema for the data field
  - `subject` - Subject of the event
  - `time` - Timestamp of event occurrence (RFC3339)
  - `data` - Event payload
  - `data_base64` - Base64 encoded event payload
  
  ## Extension Fields
  Additional fields are allowed as extensions, following naming rules.
  """
  
  @required_fields ~w(specversion id source type)
  @optional_fields ~w(datacontenttype dataschema subject time data data_base64)
  @spec_version "1.0"
  
  @type validation_error :: {:error, field :: String.t(), reason :: String.t()}
  @type validation_result :: :ok | {:error, [validation_error()]}
  
  @doc """
  Validates a CloudEvent against the specification.
  
  Returns `:ok` if valid, or `{:error, errors}` with a list of validation errors.
  
  ## Examples
  
      iex> validate(%{
      ...>   "specversion" => "1.0",
      ...>   "id" => "123",
      ...>   "source" => "/myapp",
      ...>   "type" => "com.example.event"
      ...> })
      :ok
      
      iex> validate(%{"id" => "123"})
      {:error, [
        {:error, "specversion", "required field missing"},
        {:error, "source", "required field missing"},
        {:error, "type", "required field missing"}
      ]}
  """
  @spec validate(map()) :: validation_result()
  def validate(event) when is_map(event) do
    errors = 
      []
      |> validate_required_fields(event)
      |> validate_specversion(event)
      |> validate_id(event)
      |> validate_source(event)
      |> validate_type(event)
      |> validate_optional_fields(event)
      |> validate_extension_fields(event)
      |> validate_data_fields(event)
    
    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end
  
  def validate(_), do: {:error, [{:error, "event", "must be a map"}]}
  
  @doc """
  Checks if an event is valid without returning detailed errors.
  """
  @spec valid?(map()) :: boolean()
  def valid?(event) do
    case validate(event) do
      :ok -> true
      _ -> false
    end
  end
  
  # Private validation functions
  
  defp validate_required_fields(errors, event) do
    Enum.reduce(@required_fields, errors, fn field, acc ->
      if Map.has_key?(event, field) do
        acc
      else
        [{:error, field, "required field missing"} | acc]
      end
    end)
  end
  
  defp validate_specversion(errors, event) do
    case Map.get(event, "specversion") do
      nil -> errors
      @spec_version -> errors
      other -> [{:error, "specversion", "must be '#{@spec_version}', got '#{other}'"} | errors]
    end
  end
  
  defp validate_id(errors, event) do
    case Map.get(event, "id") do
      nil -> errors
      "" -> [{:error, "id", "must not be empty"} | errors]
      id when is_binary(id) -> errors
      _ -> [{:error, "id", "must be a string"} | errors]
    end
  end
  
  defp validate_source(errors, event) do
    case Map.get(event, "source") do
      nil -> errors
      "" -> [{:error, "source", "must not be empty"} | errors]
      source when is_binary(source) ->
        if valid_uri_reference?(source) do
          errors
        else
          [{:error, "source", "must be a valid URI-reference"} | errors]
        end
      _ -> [{:error, "source", "must be a string"} | errors]
    end
  end
  
  defp validate_type(errors, event) do
    case Map.get(event, "type") do
      nil -> errors
      "" -> [{:error, "type", "must not be empty"} | errors]
      type when is_binary(type) -> errors
      _ -> [{:error, "type", "must be a string"} | errors]
    end
  end
  
  defp validate_optional_fields(errors, event) do
    Enum.reduce(event, errors, fn {key, value}, acc ->
      cond do
        key == "time" -> validate_time(acc, value)
        key == "datacontenttype" -> validate_content_type(acc, value)
        key == "dataschema" -> validate_uri(acc, value, "dataschema")
        key == "subject" -> validate_string(acc, value, "subject")
        true -> acc
      end
    end)
  end
  
  defp validate_extension_fields(errors, event) do
    Enum.reduce(event, errors, fn {key, _value}, acc ->
      if key not in (@required_fields ++ @optional_fields) do
        if valid_extension_name?(key) do
          acc
        else
          [{:error, key, "invalid extension field name (must be lowercase letters/digits, 1-20 chars)"} | acc]
        end
      else
        acc
      end
    end)
  end
  
  defp validate_data_fields(errors, event) do
    has_data = Map.has_key?(event, "data")
    has_data_base64 = Map.has_key?(event, "data_base64")
    
    if has_data and has_data_base64 do
      [{:error, "data", "cannot have both 'data' and 'data_base64' fields"} | errors]
    else
      errors
    end
  end
  
  defp validate_time(errors, value) do
    if is_binary(value) and valid_rfc3339?(value) do
      errors
    else
      [{:error, "time", "must be a valid RFC3339 timestamp"} | errors]
    end
  end
  
  defp validate_content_type(errors, value) do
    if is_binary(value) and value != "" do
      errors
    else
      [{:error, "datacontenttype", "must be a non-empty string"} | errors]
    end
  end
  
  defp validate_uri(errors, value, field) do
    if is_binary(value) and valid_uri?(value) do
      errors
    else
      [{:error, field, "must be a valid URI"} | errors]
    end
  end
  
  defp validate_string(errors, value, field) do
    if is_binary(value) do
      errors
    else
      [{:error, field, "must be a string"} | errors]
    end
  end
  
  # Validation helpers
  
  defp valid_uri_reference?(str) do
    # URI-reference can be absolute URI, relative reference, or empty
    # For simplicity, we'll accept any non-empty string that doesn't contain spaces
    str != "" and not String.contains?(str, " ")
  end
  
  defp valid_uri?(str) do
    case URI.parse(str) do
      %URI{scheme: scheme} when is_binary(scheme) -> true
      _ -> false
    end
  end
  
  defp valid_rfc3339?(str) do
    case DateTime.from_iso8601(str) do
      {:ok, _, _} -> true
      _ -> false
    end
  end
  
  defp valid_extension_name?(name) do
    # Must be lowercase letters/digits, start with letter, 1-20 chars
    Regex.match?(~r/^[a-z][a-z0-9]{0,19}$/, name)
  end
end