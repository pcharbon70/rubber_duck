defmodule RubberDuckEngines.Config do
  @moduledoc """
  Configuration helpers for the engines application.
  """

  @doc """
  Gets the engine pool size.
  """
  def pool_size do
    Application.get_env(:rubber_duck_engines, :engine_pool_size, 10)
  end

  @doc """
  Gets the engine timeout in milliseconds.
  """
  def engine_timeout do
    Application.get_env(:rubber_duck_engines, :engine_timeout, :timer.seconds(30))
  end

  @doc """
  Gets the maximum number of concurrent analyses.
  """
  def max_concurrent_analyses do
    Application.get_env(:rubber_duck_engines, :max_concurrent_analyses, 5)
  end

  @doc """
  Gets configuration for a specific engine.
  """
  def engine_config(engine_name) do
    engines = Application.get_env(:rubber_duck_engines, :engines, [])
    Keyword.get(engines, engine_name, %{})
  end

  @doc """
  Checks if an engine is enabled.
  """
  def engine_enabled?(engine_name) do
    config = engine_config(engine_name)
    Map.get(config, :enabled, false)
  end

  @doc """
  Lists all enabled engines.
  """
  def enabled_engines do
    engines = Application.get_env(:rubber_duck_engines, :engines, [])
    
    engines
    |> Enum.filter(fn {_name, config} -> Map.get(config, :enabled, false) end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  @doc """
  Gets engine-specific settings with defaults.
  """
  def get_engine_setting(engine_name, setting, default \\ nil) do
    config = engine_config(engine_name)
    Map.get(config, setting, default)
  end
end