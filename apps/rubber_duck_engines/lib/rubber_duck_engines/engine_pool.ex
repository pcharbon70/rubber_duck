defmodule RubberDuckEngines.EnginePool do
  @moduledoc """
  Engine pool management with structured supervision and resource pooling.

  This module provides a layered pooling approach with rest_for_one supervision
  strategy to ensure proper dependency management between pool components.
  """

  alias RubberDuckEngines.EnginePool.{Supervisor, Manager, Router}

  @doc """
  Starts the engine pool supervision tree.
  """
  def start_link(init_arg \\ []) do
    Supervisor.start_link(init_arg)
  end

  @doc """
  Gets an available engine from the pool for the specified analysis type.
  """
  def checkout_engine(analysis_type, opts \\ []) do
    Router.checkout_engine(analysis_type, opts)
  end

  @doc """
  Returns an engine to the pool after use.
  """
  def checkin_engine(engine_pid, analysis_type) do
    Router.checkin_engine(engine_pid, analysis_type)
  end

  @doc """
  Gets pool statistics for monitoring and debugging.
  """
  def pool_stats do
    Router.pool_stats()
  end

  @doc """
  Gets pool configuration for a specific engine type.
  """
  def get_pool_config(engine_type) do
    Manager.get_pool_config(engine_type)
  end

  @doc """
  Updates pool configuration for a specific engine type.
  """
  def update_pool_config(engine_type, config) do
    Manager.update_pool_config(engine_type, config)
  end

  @doc """
  Lists all available pools and their current status.
  """
  def list_pools do
    Manager.list_pools()
  end

  @doc """
  Health check for the entire pool system.
  """
  def health_check do
    Router.health_check()
  end
end
