defmodule RubberDuck.MCP.Client do
  @moduledoc """
  Main MCP client module for managing connections to external MCP servers.

  This module provides the public API for:
  - Creating and managing MCP client connections
  - Discovering and invoking tools from MCP servers
  - Managing resources and prompts
  - Handling client lifecycle and health monitoring

  ## Example

      # Start a client connection
      {:ok, client} = RubberDuck.MCP.Client.start_link(
        name: :github_client,
        transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-github"]},
        capabilities: [:tools, :resources]
      )

      # List available tools
      {:ok, tools} = RubberDuck.MCP.Client.list_tools(:github_client)

      # Invoke a tool
      {:ok, result} = RubberDuck.MCP.Client.call_tool(:github_client, "search_repositories", %{
        query: "elixir mcp"
      })
  """

  use GenServer
  require Logger

  alias RubberDuck.MCP.Client.{State, Connection, Registry}

  @default_timeout 30_000
  @heartbeat_interval 30_000

  # Client API

  @doc """
  Starts a new MCP client with the given options.

  ## Options

    * `:name` - Required. The name to register the client under
    * `:transport` - Required. The transport configuration (e.g., `{:stdio, command: "cmd", args: []}`)
    * `:capabilities` - Optional. List of client capabilities. Defaults to `[:tools, :resources, :prompts]`
    * `:auth` - Optional. Authentication configuration
    * `:timeout` - Optional. Default timeout for operations. Defaults to 30 seconds
    * `:auto_reconnect` - Optional. Whether to automatically reconnect on disconnect. Defaults to true
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc """
  Stops a client connection.
  """
  def stop(client, reason \\ :normal) do
    GenServer.stop(via_tuple(client), reason)
  end

  @doc """
  Lists all available tools from the MCP server.
  """
  def list_tools(client, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), :list_tools, timeout)
  end

  @doc """
  Calls a tool on the MCP server.
  """
  def call_tool(client, tool_name, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), {:call_tool, tool_name, args}, timeout)
  end

  @doc """
  Lists available resources from the MCP server.
  """
  def list_resources(client, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), :list_resources, timeout)
  end

  @doc """
  Reads a resource from the MCP server.
  """
  def read_resource(client, uri, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), {:read_resource, uri}, timeout)
  end

  @doc """
  Lists available prompts from the MCP server.
  """
  def list_prompts(client, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), :list_prompts, timeout)
  end

  @doc """
  Gets a prompt from the MCP server.
  """
  def get_prompt(client, prompt_name, args \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(via_tuple(client), {:get_prompt, prompt_name, args}, timeout)
  end

  @doc """
  Gets the current health status of the client.
  """
  def health_check(client) do
    GenServer.call(via_tuple(client), :health_check)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %State{
      name: Keyword.fetch!(opts, :name),
      transport: Keyword.fetch!(opts, :transport),
      capabilities: Keyword.get(opts, :capabilities, [:tools, :resources, :prompts]),
      auth: Keyword.get(opts, :auth),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      auto_reconnect: Keyword.get(opts, :auto_reconnect, true),
      status: :initializing
    }

    # Register with the client registry
    Registry.register(state.name, self())

    # Start connection process
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case Connection.connect(state) do
      {:ok, connection} ->
        # Start heartbeat
        schedule_heartbeat()
        
        # Update telemetry
        :telemetry.execute(
          [:rubber_duck, :mcp, :client, :connected],
          %{count: 1},
          %{client: state.name, transport: elem(state.transport, 0)}
        )
        
        {:noreply, %{state | connection: connection, status: :connected}}
      
      {:error, reason} ->
        Logger.error("Failed to connect MCP client #{state.name}: #{inspect(reason)}")
        
        if state.auto_reconnect do
          schedule_reconnect()
          {:noreply, %{state | status: :disconnected, last_error: reason}}
        else
          {:stop, {:connection_failed, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_tools, _from, %{status: :connected} = state) do
    case Connection.request(state.connection, "tools/list", %{}) do
      {:ok, %{"tools" => tools}} ->
        {:reply, {:ok, tools}, state}
      
      {:error, reason} = error ->
        Logger.error("Failed to list tools: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:list_tools, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call({:call_tool, tool_name, args}, _from, %{status: :connected} = state) do
    params = %{
      "name" => tool_name,
      "arguments" => args
    }
    
    case Connection.request(state.connection, "tools/call", params) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}
      
      {:error, reason} = error ->
        Logger.error("Failed to call tool #{tool_name}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:call_tool, _, _}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    health = %{
      status: state.status,
      connected: state.status == :connected,
      last_error: state.last_error,
      uptime: System.monotonic_time(:second) - state.connected_at
    }
    
    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_info(:heartbeat, %{status: :connected} = state) do
    case Connection.ping(state.connection) do
      :ok ->
        schedule_heartbeat()
        {:noreply, state}
      
      {:error, reason} ->
        Logger.warn("Heartbeat failed for #{state.name}: #{inspect(reason)}")
        handle_disconnect(state, reason)
    end
  end

  def handle_info(:heartbeat, state) do
    # Not connected, skip heartbeat
    schedule_heartbeat()
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect MCP client #{state.name}")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("MCP client #{state.name} terminating: #{inspect(reason)}")
    
    # Clean up connection
    if state.connection do
      Connection.disconnect(state.connection)
    end
    
    # Unregister from registry
    Registry.unregister(state.name)
    
    :ok
  end

  # Private functions

  defp via_tuple(name) do
    {:via, Registry, {RubberDuck.MCP.ClientRegistry, name}}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  defp schedule_reconnect do
    Process.send_after(self(), :reconnect, 5_000)
  end

  defp handle_disconnect(state, reason) do
    :telemetry.execute(
      [:rubber_duck, :mcp, :client, :disconnected],
      %{count: 1},
      %{client: state.name, reason: reason}
    )
    
    if state.auto_reconnect do
      schedule_reconnect()
      {:noreply, %{state | status: :disconnected, connection: nil, last_error: reason}}
    else
      {:stop, {:disconnected, reason}, state}
    end
  end
end