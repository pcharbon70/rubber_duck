defmodule RubberDuck.Engine.Pool do
  @moduledoc """
  Manages pools of engine workers using poolboy.
  
  This module provides pool management for engines, allowing multiple
  instances of each engine type to handle concurrent requests.
  """
  
  require Logger
  
  @doc """
  Starts a pool of engine workers.
  """
  def start_link(engine_config) do
    pool_name = pool_name(engine_config.name)
    
    pool_config = [
      name: {:local, pool_name},
      worker_module: RubberDuck.Engine.Pool.Worker,
      size: engine_config.pool_size,
      max_overflow: engine_config.max_overflow
    ]
    
    # Start poolboy with our worker module
    case :poolboy.start_link(pool_config, engine_config) do
      {:ok, pid} ->
        Logger.info("Started engine pool #{engine_config.name} with #{engine_config.pool_size} workers")
        {:ok, pid}
        
      error ->
        Logger.error("Failed to start engine pool #{engine_config.name}: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Gets a child spec for the pool.
  """
  def child_spec(engine_config) do
    %{
      id: pool_name(engine_config.name),
      start: {__MODULE__, :start_link, [engine_config]},
      restart: :permanent,
      type: :supervisor
    }
  end
  
  @doc """
  Executes a function with a worker from the pool.
  """
  def transaction(engine_name, fun, timeout \\ 5_000) do
    pool = pool_name(engine_name)
    
    try do
      :poolboy.transaction(
        pool,
        fun,
        timeout
      )
    catch
      :exit, {:timeout, _} ->
        {:error, :checkout_timeout}
        
      :exit, {:noproc, _} ->
        {:error, :pool_not_found}
    end
  end
  
  @doc """
  Gets the status of a pool.
  """
  def status(engine_name) do
    pool = pool_name(engine_name)
    
    case Process.whereis(pool) do
      nil ->
        :not_found
        
      pid when is_pid(pid) ->
        # poolboy.status returns a tuple: {State, WorkersAvailable, Overflow, TotalWorkers}
        case :poolboy.status(pool) do
          {_state, available, overflow, _total} ->
            # Get pool configuration from CapabilityRegistry
            engine_config = RubberDuck.Engine.CapabilityRegistry.get_engine(engine_name)
            
            pool_size = engine_config.pool_size || 3
            max_overflow = engine_config.max_overflow || 0
            
            %{
              pool_pid: pid,
              available_workers: available,
              overflow: overflow,
              pool_size: pool_size,
              max_overflow: max_overflow,
              checked_out: pool_size - available,
              total_workers: pool_size + overflow  # Calculate total_workers correctly
            }
        end
    end
  end
  
  @doc """
  Stops a pool.
  """
  def stop(engine_name) do
    pool = pool_name(engine_name)
    
    case Process.whereis(pool) do
      nil ->
        :ok
        
      pid when is_pid(pid) ->
        :poolboy.stop(pool)
    end
  end
  
  @doc """
  Emits telemetry metrics for a pool.
  """
  def emit_metrics(engine_name) do
    case status(engine_name) do
      :not_found ->
        :ok
        
      status ->
        :telemetry.execute(
          [:rubber_duck, :engine, :pool],
          %{
            available_workers: status.available_workers,
            checked_out: status.checked_out,
            overflow: status.overflow,
            total_workers: status.total_workers
          },
          %{
            engine: engine_name,
            pool_size: status.pool_size,
            max_overflow: status.max_overflow
          }
        )
    end
  end
  
  # Private functions
  
  defp pool_name(engine_name) do
    :"#{engine_name}_pool"
  end
end