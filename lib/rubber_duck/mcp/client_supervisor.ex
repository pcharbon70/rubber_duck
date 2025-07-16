defmodule RubberDuck.MCP.ClientSupervisor do
  @moduledoc """
  Supervisor for MCP client connections.
  
  This module manages the lifecycle of all MCP client connections,
  providing fault tolerance and automatic restart capabilities.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  @doc """
  Starts a new MCP client under supervision.
  """
  def start_client(opts) do
    spec = {RubberDuck.MCP.Client, opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a supervised MCP client.
  """
  def stop_client(client_name) do
    case RubberDuck.MCP.Client.Registry.lookup(client_name) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all supervised MCP clients.
  """
  def list_clients do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  @doc """
  Returns the count of active clients.
  """
  def count_clients do
    DynamicSupervisor.count_children(__MODULE__)
  end
end