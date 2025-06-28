defmodule RubberDuckWeb.Config do
  @moduledoc """
  Configuration helpers for the web application.
  """

  @doc """
  Checks if WebSocket debugging is enabled.
  """
  def debug_websockets? do
    Application.get_env(:rubber_duck_web, :debug_websockets, false)
  end

  @doc """
  Gets the WebSocket timeout in milliseconds.
  """
  def websocket_timeout do
    Application.get_env(:rubber_duck_web, :websocket_timeout, :timer.minutes(30))
  end

  @doc """
  Checks if development routes are enabled.
  """
  def dev_routes? do
    Application.get_env(:rubber_duck_web, :dev_routes, false)
  end

  @doc """
  Gets the endpoint URL configuration.
  """
  def endpoint_url do
    config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    Keyword.get(config, :url, [host: "localhost"])
  end

  @doc """
  Gets the port the server is running on.
  """
  def port do
    config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    http_config = Keyword.get(config, :http, [])
    Keyword.get(http_config, :port, 4000)
  end

  @doc """
  Checks if the server is running in SSL mode.
  """
  def ssl? do
    config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    Keyword.has_key?(config, :https)
  end

  @doc """
  Gets the secret key base.
  """
  def secret_key_base do
    config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    Keyword.get(config, :secret_key_base)
  end
end