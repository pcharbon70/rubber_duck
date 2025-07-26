defmodule RubberDuck.Config.Timeouts do
  @moduledoc """
  Centralized timeout configuration access for RubberDuck.
  
  This module provides a unified interface to access timeout configurations
  defined in config/timeouts.exs and optionally overridden in runtime.exs.
  
  ## Usage
  
      # Get a specific timeout
      timeout = Timeouts.get([:channels, :conversation])
      
      # Get with a default fallback
      timeout = Timeouts.get([:custom, :timeout], 5_000)
      
      # Get all timeouts for a category
      channel_timeouts = Timeouts.get_category(:channels)
      
  ## Configuration Structure
  
  Timeouts are organized hierarchically:
  
  - `:channels` - WebSocket and channel timeouts
  - `:engines` - Engine and processing timeouts  
  - `:tools` - Tool execution timeouts
  - `:llm_providers` - LLM provider-specific timeouts
  - `:chains` - Chain of Thought timeouts
  - `:workflows` - Workflow execution timeouts
  - `:agents` - Agent coordination timeouts
  - `:mcp` - Model Context Protocol timeouts
  - `:infrastructure` - System infrastructure timeouts
  - `:test` - Testing-specific timeouts
  """

  @doc """
  Gets a timeout value by its path in the configuration.
  
  ## Parameters
  
  - `path` - List of atoms representing the path to the timeout value
  - `default` - Default value if timeout is not configured (optional)
  
  ## Examples
  
      iex> Timeouts.get([:channels, :conversation])
      60_000
      
      iex> Timeouts.get([:custom, :timeout], 5_000)
      5_000
  """
  @spec get(list(atom()), integer() | nil) :: integer() | nil
  def get(path, default \\ nil) when is_list(path) do
    config = Application.get_env(:rubber_duck, :timeouts, %{})
    get_in(config, path) || default
  end

  @doc """
  Gets all timeout configurations for a specific category.
  
  ## Examples
  
      iex> Timeouts.get_category(:channels)
      %{conversation: 60_000, mcp_heartbeat: 15_000}
  """
  @spec get_category(atom()) :: map() | nil
  def get_category(category) when is_atom(category) do
    config = Application.get_env(:rubber_duck, :timeouts, %{})
    Map.get(config, category)
  end

  @doc """
  Gets all configured timeouts.
  
  ## Examples
  
      iex> Timeouts.all()
      %{channels: %{...}, engines: %{...}, ...}
  """
  @spec all() :: map()
  def all do
    Application.get_env(:rubber_duck, :timeouts, %{})
  end

  @doc """
  Gets a timeout value with support for dynamic calculation based on context.
  
  This is useful for timeouts that need to be adjusted based on 
  runtime conditions like model size, request complexity, etc.
  
  ## Examples
  
      iex> Timeouts.get_dynamic([:llm_providers, :ollama, :request], %{model: "llama2:70b"})
      120_000  # Doubled for large model
  """
  @spec get_dynamic(list(atom()), map(), integer() | nil) :: integer()
  def get_dynamic(path, context \\ %{}, default \\ nil) do
    base_timeout = get(path, default)
    
    case base_timeout do
      nil -> nil
      timeout -> apply_modifiers(timeout, path, context)
    end
  end

  @doc """
  Checks if a timeout path exists in the configuration.
  
  ## Examples
  
      iex> Timeouts.exists?([:channels, :conversation])
      true
      
      iex> Timeouts.exists?([:invalid, :path])
      false
  """
  @spec exists?(list(atom())) :: boolean()
  def exists?(path) when is_list(path) do
    config = Application.get_env(:rubber_duck, :timeouts, %{})
    
    case get_in(config, path) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Lists all available timeout paths.
  
  Useful for documentation and debugging.
  
  ## Examples
  
      iex> Timeouts.list_paths()
      [[:channels, :conversation], [:channels, :mcp_heartbeat], ...]
  """
  @spec list_paths() :: list(list(atom()))
  def list_paths do
    config = Application.get_env(:rubber_duck, :timeouts, %{})
    collect_paths(config, [])
  end

  @doc """
  Formats a timeout value for display.
  
  ## Examples
  
      iex> Timeouts.format(60_000)
      "60s"
      
      iex> Timeouts.format(1_500)
      "1.5s"
      
      iex> Timeouts.format(500)
      "500ms"
  """
  @spec format(integer()) :: String.t()
  def format(timeout) when is_integer(timeout) do
    cond do
      timeout >= 60_000 ->
        minutes = div(timeout, 60_000)
        seconds = rem(timeout, 60_000) / 1_000
        if seconds == 0 do
          "#{minutes}m"
        else
          "#{minutes}m #{format_seconds(seconds)}"
        end
        
      timeout >= 1_000 ->
        format_seconds(timeout / 1_000)
        
      true ->
        "#{timeout}ms"
    end
  end

  # Private functions

  defp apply_modifiers(timeout, path, context) do
    timeout
    |> apply_model_modifier(path, context)
    |> apply_environment_modifier(context)
    |> apply_load_modifier(context)
  end

  defp apply_model_modifier(timeout, [:llm_providers | _rest], %{model: model}) do
    # Increase timeout for larger models
    cond do
      String.contains?(model, "70b") -> round(timeout * 2)
      String.contains?(model, "30b") or String.contains?(model, "34b") -> round(timeout * 1.5)
      String.contains?(model, "13b") -> round(timeout * 1.2)
      true -> timeout
    end
  end
  defp apply_model_modifier(timeout, _path, _context), do: timeout

  defp apply_environment_modifier(timeout, %{env: env}) do
    # Increase timeouts in dev/test environments
    case env do
      :dev -> round(timeout * 1.5)
      :test -> round(timeout * 0.5)
      _ -> timeout
    end
  end
  defp apply_environment_modifier(timeout, _context), do: timeout

  defp apply_load_modifier(timeout, %{load: load}) when is_atom(load) do
    # Adjust timeouts based on system load
    case load do
      :high -> round(timeout * 1.5)
      :critical -> round(timeout * 2)
      _ -> timeout
    end
  end
  defp apply_load_modifier(timeout, _context), do: timeout

  defp collect_paths(config, prefix) when is_map(config) do
    Enum.flat_map(config, fn {key, value} ->
      new_prefix = prefix ++ [key]
      
      case value do
        %{} = nested -> collect_paths(nested, new_prefix)
        _ -> [new_prefix]
      end
    end)
  end
  defp collect_paths(config, prefix) when is_list(config) do
    # Handle keyword lists by converting to map
    if Keyword.keyword?(config) do
      config |> Enum.into(%{}) |> collect_paths(prefix)
    else
      []
    end
  end
  defp collect_paths(_config, _prefix), do: []

  defp format_seconds(seconds) when seconds == trunc(seconds) do
    "#{trunc(seconds)}s"
  end
  defp format_seconds(seconds) do
    # Round to 3 decimal places to handle edge cases like 59.999
    rounded = Float.round(seconds, 3)
    if rounded == Float.round(rounded, 1) do
      "#{Float.round(rounded, 1)}s"
    else
      "#{rounded}s"
    end
  end
end