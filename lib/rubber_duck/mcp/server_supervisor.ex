defmodule RubberDuck.MCP.ServerSupervisor do
  @moduledoc """
  Supervisor for MCP server processes.
  
  This supervisor manages the MCP server and its associated processes,
  including transport-specific workers and support services.
  """
  
  use Supervisor
  
  require Logger
  
  @doc """
  Starts the MCP server supervisor.
  """
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    # Extract configuration
    transport = Keyword.get(opts, :transport, :stdio)
    server_opts = Keyword.get(opts, :server_opts, [])
    
    Logger.info("Starting MCP Server Supervisor with transport: #{transport}")
    
    children = [
      # Registry for server components
      {Registry, keys: :unique, name: RubberDuck.MCP.ServerRegistry},
      
      # The main MCP server
      {RubberDuck.MCP.Server, Keyword.put(server_opts, :transport, transport)}
    ]
    
    # Add transport-specific children if needed
    transport_children = case transport do
      :streamable_http ->
        # Add HTTP-specific processes
        []
        
      :sse ->
        # Add SSE-specific processes
        []
        
      :websocket ->
        # Add WebSocket-specific processes
        []
        
      _ ->
        []
    end
    
    all_children = children ++ transport_children
    
    # Supervisor options
    opts = [
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 10
    ]
    
    Supervisor.init(all_children, opts)
  end
  
  @doc """
  Returns the current status of the MCP server.
  """
  def status do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}
        
      pid ->
        children = Supervisor.which_children(pid)
        
        server_status = Enum.find_value(children, fn
          {RubberDuck.MCP.Server, child_pid, :worker, _} when is_pid(child_pid) ->
            {:ok, :running}
            
          {RubberDuck.MCP.Server, :undefined, :worker, _} ->
            {:ok, :stopped}
            
          _ ->
            nil
        end) || {:ok, :unknown}
        
        server_status
    end
  end
  
  @doc """
  Stops the MCP server gracefully.
  """
  def stop do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}
        
      pid ->
        Supervisor.stop(pid, :normal)
    end
  end
  
  @doc """
  Restarts the MCP server.
  """
  def restart do
    with :ok <- stop(),
         :ok <- Process.sleep(100),
         {:ok, _} <- start_link([]) do
      :ok
    end
  end
end