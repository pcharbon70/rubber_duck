defmodule RubberDuck.MCP.Client.Registry do
  @moduledoc """
  Registry for tracking active MCP client connections.
  
  Provides a central registry for all MCP clients, enabling lookup
  by name and tracking of client status.
  """

  @registry_name RubberDuck.MCP.ClientRegistry

  @doc """
  Registers a client with the given name and PID.
  """
  def register(name, pid) when is_atom(name) and is_pid(pid) do
    Registry.register(@registry_name, name, pid)
  end

  @doc """
  Unregisters a client by name.
  """
  def unregister(name) when is_atom(name) do
    Registry.unregister(@registry_name, name)
  end

  @doc """
  Looks up a client by name.
  """
  def lookup(name) when is_atom(name) do
    case Registry.lookup(@registry_name, name) do
      [{_pid, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all registered clients.
  """
  def list_clients do
    Registry.select(@registry_name, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.map(fn {name, pid} -> {name, pid} end)
  end

  @doc """
  Returns the count of registered clients.
  """
  def count do
    Registry.count(@registry_name)
  end

  @doc """
  Checks if a client is registered.
  """
  def registered?(name) when is_atom(name) do
    case lookup(name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end
end