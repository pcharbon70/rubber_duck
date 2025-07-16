defmodule RubberDuck.MCP.Server do
  @moduledoc """
  Main MCP server implementation for RubberDuck.
  
  This module provides the public API for the MCP server that exposes
  RubberDuck's capabilities to AI assistants through the Model Context Protocol.
  
  The server supports:
  - Tools: Execute RubberDuck operations like code analysis, workflow execution
  - Resources: Access to project files, documentation, and system state
  - Prompts: Pre-defined interaction templates for common tasks
  
  ## Architecture
  
  The server is built on top of Hermes MCP and integrates with:
  - RubberDuck's workflow engine for tool execution
  - The instruction system for resource access
  - The conversation system for context management
  
  ## Example
  
      # Start the server with STDIO transport
      {:ok, _pid} = RubberDuck.MCP.Server.start_link(transport: :stdio)
      
      # Start with HTTP/SSE transport
      {:ok, _pid} = RubberDuck.MCP.Server.start_link(
        transport: :streamable_http,
        port: 8080
      )
  """
  
  use Hermes.Server,
    name: "RubberDuck AI Assistant",
    version: "0.1.0",
    capabilities: [:tools, :resources, :prompts, :logging]
  
  require Logger
  
  alias RubberDuck.MCP.Server.{State, ToolRegistry, ResourceProvider, PromptManager}
  alias Hermes.Server.Frame
  
  # Component registration
  component RubberDuck.MCP.Server.Tools.WorkflowExecutor
  component RubberDuck.MCP.Server.Tools.CodeAnalyzer
  component RubberDuck.MCP.Server.Tools.FileOperations
  component RubberDuck.MCP.Server.Tools.ConversationManager
  
  component RubberDuck.MCP.Server.Resources.ProjectFiles
  component RubberDuck.MCP.Server.Resources.Documentation
  component RubberDuck.MCP.Server.Resources.SystemState
  
  component RubberDuck.MCP.Server.Prompts.CodeReview
  component RubberDuck.MCP.Server.Prompts.FeatureImplementation
  component RubberDuck.MCP.Server.Prompts.BugFix
  
  @doc """
  Starts the MCP server with the given options.
  
  ## Options
  
    * `:transport` - The transport to use (:stdio, :streamable_http, :websocket)
    * `:port` - Port for HTTP transports (default: 8080)
    * `:name` - Optional name for the server process
    * `:tool_filter` - Function to filter available tools
    * `:resource_filter` - Function to filter available resources
  """
  def start_link(opts \\ []) do
    transport = Keyword.get(opts, :transport, :stdio)
    
    server_opts = [
      transport: build_transport_config(transport, opts)
    ]
    
    # Add name if provided
    if name = Keyword.get(opts, :name) do
      server_opts = Keyword.put(server_opts, :name, name)
    end
    
    Hermes.Server.start_link(__MODULE__, opts, server_opts)
  end
  
  @doc """
  Returns child spec for supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end
  
  # Hermes.Server callbacks
  
  @impl true
  def init(opts, frame) do
    state = %State{
      transport: Keyword.get(opts, :transport, :stdio),
      tool_filter: Keyword.get(opts, :tool_filter),
      resource_filter: Keyword.get(opts, :resource_filter),
      start_time: System.monotonic_time(:second)
    }
    
    # Log server startup
    Logger.info("MCP Server started with transport: #{state.transport}")
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :mcp, :server, :started],
      %{count: 1},
      %{transport: state.transport}
    )
    
    {:ok, Frame.assign(frame, :server_state, state)}
  end
  
  @impl true
  def handle_notification(%{"method" => "notifications/cancelled", "params" => %{"requestId" => id}}, frame) do
    Logger.debug("Cancelling request #{id}")
    # TODO: Implement request cancellation
    {:noreply, frame}
  end
  
  def handle_notification(%{"method" => "logging/setLevel", "params" => %{"level" => level}}, frame) do
    Logger.debug("Setting log level to #{level}")
    # Update frame with new log level
    # Store log level in frame assigns
    {:noreply, Frame.assign(frame, :log_level, level)}
  end
  
  def handle_notification(notification, frame) do
    Logger.warning("Unhandled notification: #{inspect(notification)}")
    {:noreply, frame}
  end
  
  @impl true
  def handle_info(:cleanup_expired_sessions, frame) do
    # TODO: Implement session cleanup
    schedule_cleanup()
    {:noreply, frame}
  end
  
  def handle_info(msg, frame) do
    Logger.debug("Unhandled info: #{inspect(msg)}")
    {:noreply, frame}
  end
  
  # Private functions
  
  defp build_transport_config(:stdio, _opts) do
    :stdio
  end
  
  defp build_transport_config(:streamable_http, opts) do
    port = Keyword.get(opts, :port, 8080)
    {:streamable_http, port: port}
  end
  
  defp build_transport_config(:websocket, opts) do
    # WebSocket transport will be implemented later
    port = Keyword.get(opts, :port, 8080)
    {:websocket, port: port}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_sessions, :timer.minutes(5))
  end
end