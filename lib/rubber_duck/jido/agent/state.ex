defmodule RubberDuck.Jido.Agent.State do
  @moduledoc """
  State management utilities for Jido agents.
  
  Provides validation, persistence, and recovery mechanisms for agent state.
  """
  
  require Logger
  
  @type validation_result :: :ok | {:error, term()}
  @type state :: map()
  
  @doc """
  Validates state against a schema.
  
  Schema format:
  ```
  [
    field_name: [type: :atom, required: boolean],
    ...
  ]
  ```
  """
  @spec validate(state(), keyword()) :: validation_result()
  def validate(state, schema) when is_list(schema) do
    errors = 
      Enum.reduce(schema, [], fn {field, rules}, errors ->
        case validate_field(state, field, rules) do
          :ok -> errors
          {:error, reason} -> [{field, reason} | errors]
        end
      end)
    
    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end
  
  def validate(_state, _schema), do: :ok
  
  @doc """
  Persists state to storage.
  """
  @spec persist(String.t(), state()) :: :ok | {:error, term()}
  def persist(key, state) do
    table = ensure_table()
    
    try do
      :ets.insert(table, {key, state})
      :ok
    rescue
      e -> {:error, e}
    end
  end
  
  @doc """
  Recovers state from storage.
  """
  @spec recover(String.t()) :: {:ok, state()} | {:error, :not_found}
  def recover(key) do
    table = ensure_table()
    
    case :ets.lookup(table, key) do
      [{^key, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Deletes persisted state.
  """
  @spec delete(String.t()) :: :ok
  def delete(key) do
    table = ensure_table()
    :ets.delete(table, key)
    :ok
  end
  
  # Private functions
  
  defp validate_field(state, field, rules) do
    value = Map.get(state, field)
    required = Keyword.get(rules, :required, false)
    type = Keyword.get(rules, :type)
    
    cond do
      required and is_nil(value) ->
        {:error, "is required"}
      
      not is_nil(value) and not is_nil(type) and not valid_type?(value, type) ->
        {:error, "expected type #{type}, got #{inspect(value)}"}
      
      true ->
        :ok
    end
  end
  
  defp valid_type?(value, :integer), do: is_integer(value)
  defp valid_type?(value, :float), do: is_float(value) or is_integer(value)
  defp valid_type?(value, :number), do: is_number(value)
  defp valid_type?(value, :string), do: is_binary(value)
  defp valid_type?(value, :atom), do: is_atom(value)
  defp valid_type?(value, :boolean), do: is_boolean(value)
  defp valid_type?(value, :list), do: is_list(value)
  defp valid_type?(value, :map), do: is_map(value)
  defp valid_type?(value, :tuple), do: is_tuple(value)
  defp valid_type?(value, :pid), do: is_pid(value)
  defp valid_type?(value, :reference), do: is_reference(value)
  defp valid_type?(value, :function), do: is_function(value)
  defp valid_type?(_value, _type), do: false
  
  defp ensure_table do
    table_name = :rubber_duck_agent_state
    
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:named_table, :public, :set])
      
      ref ->
        ref
    end
  end
end