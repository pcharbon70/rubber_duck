defmodule RubberDuck.MCP.Integration do
  @moduledoc """
  Integration layer for connecting MCP with RubberDuck's existing systems.
  
  This module provides functions to bridge between MCP protocol and
  RubberDuck's internal systems like memory, workflows, engines, and agents.
  """
  
  alias RubberDuck.MCP.{Client, Registry}
  alias RubberDuck.Memory
  alias RubberDuck.Workflows
  alias RubberDuck.Engines
  alias RubberDuck.Agents
  
  require Logger
  
  @doc """
  Registers system integrations with MCP.
  
  This function sets up the necessary integrations between MCP and
  RubberDuck's internal systems.
  """
  def setup_integrations do
    Logger.info("Setting up MCP system integrations")
    
    with :ok <- setup_memory_integration(),
         :ok <- setup_workflow_integration(),
         :ok <- setup_engine_integration(),
         :ok <- setup_agent_integration() do
      :ok
    else
      error ->
        Logger.error("Failed to setup MCP integrations: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Exposes a system component as an MCP resource.
  """
  def expose_as_resource(component_type, component_id, metadata \\ %{}) do
    resource_spec = %{
      uri: "system://#{component_type}/#{component_id}",
      name: metadata[:name] || "#{component_type}_#{component_id}",
      description: metadata[:description] || "System #{component_type} resource",
      mime_type: "application/json"
    }
    
    Registry.register_resource(resource_spec)
  end
  
  @doc """
  Wraps a system function as an MCP tool.
  """
  def wrap_as_tool(module, function, metadata \\ %{}) do
    tool_spec = %{
      name: metadata[:name] || "#{module}_#{function}",
      description: metadata[:description] || "System function #{module}.#{function}",
      module: module,
      function: function,
      input_schema: metadata[:input_schema] || %{
        "type" => "object",
        "properties" => %{},
        "required" => []
      }
    }
    
    Registry.register_tool(tool_spec)
  end
  
  @doc """
  Enables MCP tool discovery within system components.
  """
  def enable_tool_discovery(component) do
    case component do
      :workflows -> setup_workflow_tool_discovery()
      :engines -> setup_engine_tool_discovery()
      :agents -> setup_agent_tool_discovery()
      _ -> {:error, :unsupported_component}
    end
  end
  
  # Memory System Integration
  
  defp setup_memory_integration do
    Logger.debug("Setting up memory system integration")
    
    # Register memory stores as MCP resources
    Memory.list_stores()
    |> Enum.each(fn store ->
      expose_as_resource(:memory_store, store.id, %{
        name: store.name,
        description: "Memory store: #{store.description}"
      })
    end)
    
    # Register memory manipulation tools
    memory_tools = [
      {Memory, :get, %{
        name: "memory_get",
        description: "Retrieve data from memory store",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "store_id" => %{"type" => "string"},
            "key" => %{"type" => "string"}
          },
          "required" => ["store_id", "key"]
        }
      }},
      {Memory, :put, %{
        name: "memory_put",
        description: "Store data in memory store",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "store_id" => %{"type" => "string"},
            "key" => %{"type" => "string"},
            "value" => %{"type" => "any"}
          },
          "required" => ["store_id", "key", "value"]
        }
      }},
      {Memory, :search, %{
        name: "memory_search",
        description: "Search memory store",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "store_id" => %{"type" => "string"},
            "query" => %{"type" => "string"}
          },
          "required" => ["store_id", "query"]
        }
      }}
    ]
    
    Enum.each(memory_tools, fn {module, function, metadata} ->
      wrap_as_tool(module, function, metadata)
    end)
    
    :ok
  end
  
  # Workflow System Integration
  
  defp setup_workflow_integration do
    Logger.debug("Setting up workflow system integration")
    
    # Register workflows as MCP resources
    Workflows.list_workflows()
    |> Enum.each(fn workflow ->
      expose_as_resource(:workflow, workflow.id, %{
        name: workflow.name,
        description: "Workflow: #{workflow.description}"
      })
    end)
    
    # Register workflow execution tools
    workflow_tools = [
      {Workflows, :execute, %{
        name: "workflow_execute",
        description: "Execute a workflow",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "workflow_id" => %{"type" => "string"},
            "params" => %{"type" => "object"}
          },
          "required" => ["workflow_id"]
        }
      }},
      {Workflows, :get_status, %{
        name: "workflow_status",
        description: "Get workflow execution status",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "execution_id" => %{"type" => "string"}
          },
          "required" => ["execution_id"]
        }
      }}
    ]
    
    Enum.each(workflow_tools, fn {module, function, metadata} ->
      wrap_as_tool(module, function, metadata)
    end)
    
    :ok
  end
  
  # Engine System Integration
  
  defp setup_engine_integration do
    Logger.debug("Setting up engine system integration")
    
    # Register engines as MCP resources
    Engines.list_engines()
    |> Enum.each(fn engine ->
      expose_as_resource(:engine, engine.id, %{
        name: engine.name,
        description: "Engine: #{engine.description}"
      })
    end)
    
    # Register engine execution tools
    engine_tools = [
      {Engines, :execute, %{
        name: "engine_execute",
        description: "Execute an engine",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "engine_id" => %{"type" => "string"},
            "input" => %{"type" => "any"}
          },
          "required" => ["engine_id", "input"]
        }
      }}
    ]
    
    Enum.each(engine_tools, fn {module, function, metadata} ->
      wrap_as_tool(module, function, metadata)
    end)
    
    :ok
  end
  
  # Agent System Integration
  
  defp setup_agent_integration do
    Logger.debug("Setting up agent system integration")
    
    # Register agents as MCP resources
    Agents.list_agents()
    |> Enum.each(fn agent ->
      expose_as_resource(:agent, agent.id, %{
        name: agent.name,
        description: "Agent: #{agent.description}"
      })
    end)
    
    # Register agent interaction tools
    agent_tools = [
      {Agents, :send_message, %{
        name: "agent_message",
        description: "Send message to agent",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "message" => %{"type" => "string"}
          },
          "required" => ["agent_id", "message"]
        }
      }},
      {Agents, :get_status, %{
        name: "agent_status",
        description: "Get agent status",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"}
          },
          "required" => ["agent_id"]
        }
      }}
    ]
    
    Enum.each(agent_tools, fn {module, function, metadata} ->
      wrap_as_tool(module, function, metadata)
    end)
    
    :ok
  end
  
  # Tool Discovery Setup
  
  defp setup_workflow_tool_discovery do
    # Enable workflows to discover and use MCP tools
    Logger.debug("Setting up workflow tool discovery")
    
    # Register MCP tool step type with Reactor
    Reactor.register_step_type(:mcp_tool, RubberDuck.MCP.Integration.WorkflowSteps.MCPToolStep)
    
    :ok
  end
  
  defp setup_engine_tool_discovery do
    # Enable engines to discover and use MCP tools
    Logger.debug("Setting up engine tool discovery")
    
    # This would integrate with the engine system
    :ok
  end
  
  defp setup_agent_tool_discovery do
    # Enable agents to discover and use MCP tools
    Logger.debug("Setting up agent tool discovery")
    
    # This would integrate with the agent system
    :ok
  end
  
  @doc """
  Synchronizes system state with MCP resources.
  """
  def sync_system_state do
    Logger.debug("Synchronizing system state with MCP")
    
    # Re-register all system components
    setup_integrations()
    
    # Notify MCP clients of state changes
    notify_state_change()
    
    :ok
  end
  
  defp notify_state_change do
    # Notify all connected MCP clients about state changes
    Registry.list_clients()
    |> Enum.each(fn client ->
      Client.notify_state_change(client, %{
        timestamp: DateTime.utc_now(),
        changes: ["system_state_updated"]
      })
    end)
  end
  
  @doc """
  Handles MCP tool execution within system context.
  """
  def execute_system_tool(tool_name, params, context \\ %{}) do
    Logger.debug("Executing system tool: #{tool_name}")
    
    case Registry.get_tool(tool_name) do
      {:ok, tool} ->
        # Add system context to params
        enhanced_params = Map.merge(params, %{
          system_context: context,
          timestamp: DateTime.utc_now()
        })
        
        # Execute the tool
        apply(tool.module, tool.function, [enhanced_params])
        
      {:error, :not_found} ->
        {:error, "Tool not found: #{tool_name}"}
    end
  end
  
  @doc """
  Retrieves system resource via MCP.
  """
  def get_system_resource(resource_uri, params \\ %{}) do
    Logger.debug("Retrieving system resource: #{resource_uri}")
    
    case parse_resource_uri(resource_uri) do
      {:ok, {component_type, component_id}} ->
        get_component_data(component_type, component_id, params)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp parse_resource_uri("system://" <> path) do
    case String.split(path, "/", parts: 2) do
      [component_type, component_id] ->
        {:ok, {String.to_existing_atom(component_type), component_id}}
      _ ->
        {:error, :invalid_resource_uri}
    end
  end
  defp parse_resource_uri(_), do: {:error, :invalid_resource_uri}
  
  defp get_component_data(:memory_store, store_id, params) do
    case Memory.get_store(store_id) do
      {:ok, store} ->
        data = if key = params["key"] do
          Memory.get(store, key)
        else
          Memory.list_keys(store)
        end
        
        {:ok, %{
          store: store,
          data: data,
          timestamp: DateTime.utc_now()
        }}
        
      error -> error
    end
  end
  
  defp get_component_data(:workflow, workflow_id, _params) do
    case Workflows.get_workflow(workflow_id) do
      {:ok, workflow} ->
        {:ok, %{
          workflow: workflow,
          status: Workflows.get_status(workflow_id),
          timestamp: DateTime.utc_now()
        }}
        
      error -> error
    end
  end
  
  defp get_component_data(:engine, engine_id, _params) do
    case Engines.get_engine(engine_id) do
      {:ok, engine} ->
        {:ok, %{
          engine: engine,
          status: Engines.get_status(engine_id),
          timestamp: DateTime.utc_now()
        }}
        
      error -> error
    end
  end
  
  defp get_component_data(:agent, agent_id, _params) do
    case Agents.get_agent(agent_id) do
      {:ok, agent} ->
        {:ok, %{
          agent: agent,
          status: Agents.get_status(agent_id),
          timestamp: DateTime.utc_now()
        }}
        
      error -> error
    end
  end
  
  defp get_component_data(component_type, _component_id, _params) do
    {:error, "Unsupported component type: #{component_type}"}
  end
end