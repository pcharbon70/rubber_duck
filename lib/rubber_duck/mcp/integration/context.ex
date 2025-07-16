defmodule RubberDuck.MCP.Integration.Context do
  @moduledoc """
  Context building integration for MCP.
  
  This module enhances RubberDuck's context building system to include
  MCP tool states, resource information, and enable MCP-aware prompts.
  """
  
  alias RubberDuck.MCP.{Client, Registry}
  alias RubberDuck.Context
  
  @doc """
  Enhances context with MCP information.
  
  This function adds MCP-specific context including:
  - Available tools and their states
  - Accessible resources
  - Recent tool executions
  - Client connection status
  """
  def enhance_context(base_context, opts \\ []) do
    mcp_context = %{}
    
    # Add tool information
    mcp_context = if opts[:include_tools] != false do
      Map.put(mcp_context, :tools, get_tool_context(opts))
    else
      mcp_context
    end
    
    # Add resource information
    mcp_context = if opts[:include_resources] != false do
      Map.put(mcp_context, :resources, get_resource_context(opts))
    else
      mcp_context
    end
    
    # Add client status
    mcp_context = if opts[:include_clients] != false do
      Map.put(mcp_context, :clients, get_client_context(opts))
    else
      mcp_context
    end
    
    # Add recent executions
    mcp_context = if opts[:include_executions] != false do
      Map.put(mcp_context, :recent_executions, get_execution_context(opts))
    else
      mcp_context
    end
    
    # Add composition information
    mcp_context = if opts[:include_compositions] != false do
      Map.put(mcp_context, :compositions, get_composition_context(opts))
    else
      mcp_context
    end
    
    # Merge with base context
    Map.put(base_context, :mcp, mcp_context)
  end
  
  @doc """
  Creates MCP-aware prompt templates.
  
  This function generates prompts that are aware of available MCP tools
  and resources, helping AI assistants make better use of the MCP ecosystem.
  """
  def create_mcp_prompt(base_prompt, context, opts \\ []) do
    mcp_additions = []
    
    # Add tool availability information
    if opts[:include_tool_info] != false and context[:mcp][:tools] do
      tool_info = format_tool_info(context[:mcp][:tools])
      mcp_additions = [tool_info | mcp_additions]
    end
    
    # Add resource availability information
    if opts[:include_resource_info] != false and context[:mcp][:resources] do
      resource_info = format_resource_info(context[:mcp][:resources])
      mcp_additions = [resource_info | mcp_additions]
    end
    
    # Add recent execution context
    if opts[:include_execution_context] != false and context[:mcp][:recent_executions] do
      execution_info = format_execution_info(context[:mcp][:recent_executions])
      mcp_additions = [execution_info | mcp_additions]
    end
    
    # Add composition suggestions
    if opts[:include_composition_suggestions] != false and context[:mcp][:compositions] do
      composition_info = format_composition_info(context[:mcp][:compositions])
      mcp_additions = [composition_info | mcp_additions]
    end
    
    # Combine with base prompt
    if Enum.empty?(mcp_additions) do
      base_prompt
    else
      mcp_section = Enum.join(mcp_additions, "\n\n")
      """
      #{base_prompt}
      
      ## Available MCP Tools and Resources
      
      #{mcp_section}
      
      You can use these tools and resources to help accomplish the user's request. Consider tool composition for complex tasks.
      """
    end
  end
  
  @doc """
  Builds context for tool execution.
  
  This creates a context object that includes information about the
  current MCP environment for tool execution.
  """
  def build_tool_context(tool_name, params, opts \\ []) do
    base_context = %{
      tool_name: tool_name,
      params: params,
      timestamp: DateTime.utc_now()
    }
    
    # Add system context
    base_context = if opts[:include_system_context] != false do
      Map.put(base_context, :system, get_system_context())
    else
      base_context
    end
    
    # Add user context
    base_context = if user_context = opts[:user_context] do
      Map.put(base_context, :user, user_context)
    else
      base_context
    end
    
    # Add conversation context
    base_context = if conversation_context = opts[:conversation_context] do
      Map.put(base_context, :conversation, conversation_context)
    else
      base_context
    end
    
    # Add related tools
    base_context = if opts[:include_related_tools] != false do
      Map.put(base_context, :related_tools, get_related_tools(tool_name))
    else
      base_context
    end
    
    base_context
  end
  
  @doc """
  Updates context with tool execution results.
  """
  def update_context_with_result(context, tool_name, result, opts \\ []) do
    execution_info = %{
      tool_name: tool_name,
      result: result,
      timestamp: DateTime.utc_now(),
      success: not match?({:error, _}, result)
    }
    
    # Add to execution history
    existing_executions = get_in(context, [:mcp, :recent_executions]) || []
    updated_executions = [execution_info | existing_executions]
    |> Enum.take(opts[:max_executions] || 10)
    
    put_in(context, [:mcp, :recent_executions], updated_executions)
  end
  
  # Private functions
  
  defp get_tool_context(opts) do
    limit = opts[:tool_limit] || 20
    
    case Registry.list_tools(limit: limit) do
      {:ok, tools} ->
        Enum.map(tools, fn tool ->
          %{
            name: tool.name,
            description: tool.description,
            category: tool.category,
            capabilities: tool.capabilities,
            tags: tool.tags,
            quality_score: get_tool_quality_score(tool.module)
          }
        end)
        
      _ -> []
    end
  end
  
  defp get_resource_context(opts) do
    limit = opts[:resource_limit] || 20
    
    # Get resources from all connected clients
    Registry.list_clients()
    |> Enum.flat_map(fn client ->
      case Client.list_resources(client, limit: limit) do
        {:ok, resources} ->
          Enum.map(resources, fn resource ->
            %{
              uri: resource.uri,
              name: resource.name,
              description: resource.description,
              mime_type: resource.mime_type,
              client: client.name
            }
          end)
          
        _ -> []
      end
    end)
    |> Enum.take(limit)
  end
  
  defp get_client_context(_opts) do
    Registry.list_clients()
    |> Enum.map(fn client ->
      %{
        name: client.name,
        status: Client.get_status(client),
        capabilities: Client.get_capabilities(client),
        connected_at: client.connected_at
      }
    end)
  end
  
  defp get_execution_context(opts) do
    limit = opts[:execution_limit] || 5
    
    # Get recent executions from registry metrics
    Registry.list_tools()
    |> case do
      {:ok, tools} ->
        tools
        |> Enum.flat_map(fn tool ->
          case Registry.get_metrics(tool.module) do
            {:ok, metrics} ->
              # Create execution entries from metrics
              if metrics.last_execution do
                [%{
                  tool_name: tool.name,
                  last_execution: metrics.last_execution,
                  success_rate: Registry.Metrics.success_rate(metrics),
                  total_executions: metrics.total_executions
                }]
              else
                []
              end
              
            _ -> []
          end
        end)
        |> Enum.sort_by(& &1.last_execution, {:desc, DateTime})
        |> Enum.take(limit)
        
      _ -> []
    end
  end
  
  defp get_composition_context(opts) do
    limit = opts[:composition_limit] || 5
    
    # Get available compositions
    Registry.list_compositions()
    |> case do
      {:ok, compositions} ->
        compositions
        |> Enum.take(limit)
        |> Enum.map(fn composition ->
          %{
            id: composition.id,
            name: composition.name,
            description: composition.description,
            type: composition.type,
            tool_count: length(composition.tools),
            created_at: composition.created_at
          }
        end)
        
      _ -> []
    end
  end
  
  defp get_system_context do
    %{
      node: node(),
      system_time: System.system_time(:millisecond),
      memory_usage: :erlang.memory()[:total],
      process_count: length(Process.list())
    }
  end
  
  defp get_related_tools(tool_name) do
    case Registry.get_tool(tool_name) do
      {:ok, tool} ->
        # Find tools with similar capabilities
        Registry.discover_by_capability(tool.capabilities)
        |> case do
          {:ok, related} ->
            related
            |> Enum.reject(fn related_tool -> related_tool.name == tool_name end)
            |> Enum.take(3)
            |> Enum.map(fn related_tool ->
              %{
                name: related_tool.name,
                description: related_tool.description,
                shared_capabilities: tool.capabilities -- (tool.capabilities -- related_tool.capabilities)
              }
            end)
            
          _ -> []
        end
        
      _ -> []
    end
  end
  
  defp get_tool_quality_score(module) do
    case Registry.get_metrics(module) do
      {:ok, metrics} -> Registry.Metrics.quality_score(metrics)
      _ -> 0.0
    end
  end
  
  defp format_tool_info(tools) do
    tool_list = tools
    |> Enum.sort_by(& &1.quality_score, :desc)
    |> Enum.take(10)
    |> Enum.map(fn tool ->
      "- **#{tool.name}** (#{tool.category}): #{tool.description} [Quality: #{Float.round(tool.quality_score, 1)}]"
    end)
    |> Enum.join("\n")
    
    """
    ### Available Tools
    #{tool_list}
    """
  end
  
  defp format_resource_info(resources) do
    resource_list = resources
    |> Enum.take(10)
    |> Enum.map(fn resource ->
      "- **#{resource.name}** (#{resource.uri}): #{resource.description}"
    end)
    |> Enum.join("\n")
    
    """
    ### Available Resources
    #{resource_list}
    """
  end
  
  defp format_execution_info(executions) do
    execution_list = executions
    |> Enum.take(5)
    |> Enum.map(fn execution ->
      status = if execution.success_rate > 90, do: "✓", else: "⚠"
      "- #{status} **#{execution.tool_name}**: #{execution.total_executions} executions (#{Float.round(execution.success_rate, 1)}% success)"
    end)
    |> Enum.join("\n")
    
    """
    ### Recent Tool Activity
    #{execution_list}
    """
  end
  
  defp format_composition_info(compositions) do
    composition_list = compositions
    |> Enum.take(3)
    |> Enum.map(fn composition ->
      "- **#{composition.name}** (#{composition.type}): #{composition.description} [#{composition.tool_count} tools]"
    end)
    |> Enum.join("\n")
    
    """
    ### Available Tool Compositions
    #{composition_list}
    
    You can execute these compositions or create new ones by combining available tools.
    """
  end
end