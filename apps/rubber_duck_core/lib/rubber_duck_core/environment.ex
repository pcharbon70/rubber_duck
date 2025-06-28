defmodule RubberDuckCore.Environment do
  @moduledoc """
  Environment detection and helpers.
  """

  @doc """
  Returns the current environment as an atom.
  """
  def current do
    Mix.env()
  end

  @doc """
  Checks if the application is running in development mode.
  """
  def dev? do
    current() == :dev
  end

  @doc """
  Checks if the application is running in test mode.
  """
  def test? do
    current() == :test
  end

  @doc """
  Checks if the application is running in production mode.
  """
  def prod? do
    current() == :prod
  end

  @doc """
  Checks if debug mode is enabled.
  """
  def debug? do
    Application.get_env(:rubber_duck_core, :debug_mode, false)
  end

  @doc """
  Gets the log level for the current environment.
  """
  def log_level do
    Application.get_env(:rubber_duck_core, :log_level, :info)
  end

  @doc """
  Executes a function only in specific environments.
  """
  def when_env(env_or_envs, fun) when is_atom(env_or_envs) do
    if current() == env_or_envs, do: fun.()
  end

  def when_env(envs, fun) when is_list(envs) do
    if current() in envs, do: fun.()
  end

  @doc """
  Executes a function only in development.
  """
  def when_dev(fun) do
    when_env(:dev, fun)
  end

  @doc """
  Executes a function only in test.
  """
  def when_test(fun) do
    when_env(:test, fun)
  end

  @doc """
  Executes a function only in production.
  """
  def when_prod(fun) do
    when_env(:prod, fun)
  end

  @doc """
  Returns a value based on the current environment.
  """
  def if_env(env_values) when is_list(env_values) do
    Keyword.get(env_values, current())
  end
end