defmodule RubberDuck.Engine.InputValidator do
  @moduledoc """
  Common input validation logic for engines to ensure provider and model are present.
  
  This module provides shared validation functions to help engines
  validate that required LLM parameters are present in the input.
  """
  
  @doc """
  Validates that the input contains required provider and model fields.
  
  Returns an enriched validated map with all LLM-related fields extracted.
  
  ## Example
  
      input = %{
        query: "Hello",
        provider: :openai,
        model: "gpt-4",
        temperature: 0.7
      }
      
      {:ok, validated} = InputValidator.validate_llm_input(input, [:query])
      
      validated.provider # :openai
      validated.model    # "gpt-4"
  """
  def validate_llm_input(input, required_fields \\ []) when is_map(input) do
    with :ok <- validate_required(input, :provider),
         :ok <- validate_required(input, :model),
         :ok <- validate_all_required(input, required_fields) do
      
      validated = %{
        # Required LLM fields
        provider: Map.fetch!(input, :provider),
        model: Map.fetch!(input, :model),
        
        # Optional LLM fields
        user_id: Map.get(input, :user_id),
        temperature: Map.get(input, :temperature),
        max_tokens: Map.get(input, :max_tokens),
        top_p: Map.get(input, :top_p),
        frequency_penalty: Map.get(input, :frequency_penalty),
        presence_penalty: Map.get(input, :presence_penalty),
        stop: Map.get(input, :stop),
        
        # Common fields
        context: Map.get(input, :context, %{}),
        options: Map.get(input, :options, %{}),
        
        # Cancellation support
        cancellation_token: Map.get(input, :cancellation_token),
        
        # Timestamp
        start_time: DateTime.utc_now()
      }
      
      # Add any additional required fields
      validated = Enum.reduce(required_fields, validated, fn field, acc ->
        Map.put(acc, field, Map.fetch!(input, field))
      end)
      
      {:ok, validated}
    end
  end
  
  @doc """
  Builds LLM options from validated input and engine state.
  
  Merges input parameters with engine defaults, giving precedence to input values.
  """
  def build_llm_opts(validated, messages, state) do
    [
      # Required fields from input
      provider: validated.provider,
      model: validated.model,
      messages: messages,
      
      # Optional fields with fallbacks to state
      temperature: validated.temperature || Map.get(state, :temperature, 0.7),
      max_tokens: validated.max_tokens || Map.get(state, :max_tokens),
      timeout: Map.get(state, :timeout, 30_000),
      
      # User ID for telemetry
      user_id: validated.user_id,
      
      # Additional optional parameters
      top_p: validated.top_p,
      frequency_penalty: validated.frequency_penalty,
      presence_penalty: validated.presence_penalty,
      stop: validated.stop
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end
  
  defp validate_required(input, field) do
    if Map.has_key?(input, field) do
      value = Map.get(input, field)
      validate_field_value(field, value)
    else
      {:error, format_missing_field_error(field)}
    end
  end
  
  defp validate_all_required(input, fields) do
    missing = Enum.filter(fields, fn field -> not Map.has_key?(input, field) end)
    
    case missing do
      [] -> :ok
      [field] -> {:error, format_missing_field_error(field)}
      fields -> {:error, format_missing_fields_error(fields)}
    end
  end
  
  defp validate_field_value(:provider, value) when is_atom(value), do: :ok
  defp validate_field_value(:provider, value) do
    {:error, {:invalid_field_type, :provider, "must be an atom, got: #{inspect(value)}"}}
  end
  
  defp validate_field_value(:model, value) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp validate_field_value(:model, value) do
    {:error, {:invalid_field_type, :model, "must be a non-empty string, got: #{inspect(value)}"}}
  end
  
  defp validate_field_value(_, _), do: :ok
  
  defp format_missing_field_error(:provider) do
    {:missing_required_field, :provider, 
     "Provider is required. Please specify which LLM provider to use (e.g., :openai, :anthropic, :ollama)."}
  end
  
  defp format_missing_field_error(:model) do
    {:missing_required_field, :model,
     "Model is required. Please specify which model to use (e.g., \"gpt-4\", \"claude-3-opus\", \"llama2\")."}
  end
  
  defp format_missing_field_error(:user_id) do
    {:missing_required_field, :user_id,
     "User ID is required for tracking and telemetry purposes."}
  end
  
  defp format_missing_field_error(field) do
    {:missing_required_field, field,
     "Required field '#{field}' is missing from the input."}
  end
  
  defp format_missing_fields_error(fields) do
    field_names = Enum.map_join(fields, ", ", &to_string/1)
    {:missing_required_fields, fields,
     "Multiple required fields are missing: #{field_names}"}
  end
  
  @doc """
  Formats validation errors for user display.
  """
  def format_validation_error({:missing_required_field, _field, message}), do: message
  def format_validation_error({:missing_required_fields, _fields, message}), do: message
  def format_validation_error({:invalid_field_type, _field, message}), do: message
  def format_validation_error(error), do: "Validation error: #{inspect(error)}"
end