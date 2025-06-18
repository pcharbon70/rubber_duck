defmodule YamlElixir do
  @moduledoc """
  Simple YAML stub implementation.
  
  This module provides a basic interface for YAML operations using
  standard Elixir data structures as a fallback when YamlElixir
  dependency is not available.
  """
  
  require Logger
  
  @doc """
  Read YAML from file.
  
  Returns parsed data structure or error.
  For stub implementation, treats files as Elixir term files.
  """
  def read_from_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Try to parse as Elixir terms first, fallback to simple key-value
        try do
          {result, _} = Code.eval_string(content)
          {:ok, result}
        rescue
          _ ->
            # Fallback: simple line-based parsing for basic YAML
            parse_simple_yaml(content)
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Read YAML from string.
  """
  def read_from_string(yaml_string) do
    try do
      {result, _} = Code.eval_string(yaml_string)
      {:ok, result}
    rescue
      _ ->
        parse_simple_yaml(yaml_string)
    end
  end
  
  @doc """
  Write data to YAML file.
  
  For stub implementation, writes as Elixir terms.
  """
  def write_to_file(data, file_path) do
    content = inspect(data, pretty: true)
    File.write(file_path, content)
  end
  
  # Simple YAML parser for basic key-value pairs
  defp parse_simple_yaml(content) do
    try do
      result = content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = String.trim(value) |> parse_yaml_value()
            Map.put(acc, key, value)
          _ ->
            acc
        end
      end)
      
      {:ok, result}
    rescue
      _ ->
        Logger.warning("Failed to parse YAML content, returning empty map")
        {:ok, %{}}
    end
  end
  
  defp parse_yaml_value(value) do
    cond do
      value == "true" -> true
      value == "false" -> false
      value == "null" or value == "~" -> nil
      String.match?(value, ~r/^\d+$/) -> String.to_integer(value)
      String.match?(value, ~r/^\d+\.\d+$/) -> String.to_float(value)
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2)
      true -> value
    end
  end
end