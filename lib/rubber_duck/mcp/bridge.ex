defmodule RubberDuck.MCP.Bridge do
  @moduledoc """
  Bridge between MCP protocol and RubberDuck's internal tool system.
  
  Translates MCP requests into RubberDuck tool executions and converts
  the results back to MCP format. Also exposes RubberDuck's resources
  and prompts through the MCP interface.
  
  Enhanced with ToolAdapter for comprehensive tool metadata, parameter
  transformation, progress reporting, and error handling.
  """
  
  alias RubberDuck.Tool.Registry
  alias RubberDuck.MCP.ToolAdapter
  alias RubberDuck.Workspace
  
  require Logger
  
  # Tool-related functions
  
  @doc """
  Lists available tools in MCP format with enhanced metadata.
  """
  def list_tools do
    case Registry.list_all() do
      tools when is_list(tools) ->
        # Use ToolAdapter for comprehensive conversion
        mcp_tools = tools
        |> Enum.map(fn tool -> 
          # Get the actual module from the tool record
          module = Map.get(tool, :module) || tool
          ToolAdapter.convert_tool_to_mcp(module)
        end)
        |> Enum.reject(&is_nil/1)
        
        %{"tools" => mcp_tools}
        
      _ ->
        Logger.error("Failed to list tools")
        %{"tools" => []}
    end
  end
  
  @doc """
  Executes a tool by name with enhanced parameter handling and progress reporting.
  """
  def execute_tool(tool_name, arguments, context) do
    # Use ToolAdapter for comprehensive execution handling
    case ToolAdapter.map_mcp_call(tool_name, arguments, context) do
      {:ok, result} ->
        result
        
      {:error, error} ->
        # Error is already formatted by ToolAdapter
        %{
          "content" => [
            %{
              "type" => "text", 
              "text" => "Tool execution failed: #{inspect(error)}"
            }
          ],
          "isError" => true
        }
    end
  end
  
  # Resource-related functions
  
  @doc """
  Lists available resources in MCP format.
  """
  def list_resources(params \\ %{}) do
    # List different types of resources
    resources = []
    
    # Add workspace resources
    workspace_resources = list_workspace_resources()
    resources = resources ++ workspace_resources
    
    # Add memory resources
    memory_resources = list_memory_resources()
    resources = resources ++ memory_resources
    
    # Add tool resources
    tool_resources = list_tool_resources()
    resources = resources ++ tool_resources
    
    # Apply cursor-based pagination if requested
    resources = apply_pagination(resources, params)
    
    %{"resources" => resources}
  end
  
  @doc """
  Reads a specific resource by URI.
  """
  def read_resource(uri, context) do
    case parse_resource_uri(uri) do
      {:ok, {:workspace, type, id}} ->
        read_workspace_resource(type, id, context)
        
      {:ok, {:memory, type, id}} ->
        read_memory_resource(type, id, context)
        
      {:ok, {:tool, tool_name, resource_type}} ->
        read_tool_resource(tool_name, resource_type, context)
        
      {:error, :invalid_uri} ->
        %{
          "contents" => [
            %{
              "type" => "text",
              "text" => "Invalid resource URI: #{uri}"
            }
          ],
          "isError" => true
        }
    end
  end
  
  # Prompt-related functions
  
  @doc """
  Lists available prompts.
  """
  def list_prompts do
    # Get tool-specific prompts from all registered tools
    tool_prompts = Registry.list_all()
    |> Enum.flat_map(fn tool ->
      module = Map.get(tool, :module) || tool
      ToolAdapter.prompt_templates(module)
    end)
    
    # Add built-in prompts
    built_in_prompts = [
      %{
        "name" => "analyze_code",
        "description" => "Analyze code for issues and improvements",
        "arguments" => [
          %{
            "name" => "code",
            "description" => "The code to analyze",
            "required" => true
          },
          %{
            "name" => "language",
            "description" => "Programming language",
            "required" => false
          }
        ]
      },
      %{
        "name" => "generate_tests",
        "description" => "Generate test cases for code",
        "arguments" => [
          %{
            "name" => "code",
            "description" => "The code to test",
            "required" => true
          },
          %{
            "name" => "framework",
            "description" => "Test framework to use",
            "required" => false
          }
        ]
      },
      %{
        "name" => "refactor_code",
        "description" => "Suggest refactoring improvements",
        "arguments" => [
          %{
            "name" => "code",
            "description" => "The code to refactor",
            "required" => true
          },
          %{
            "name" => "goal",
            "description" => "Refactoring goal",
            "required" => false
          }
        ]
      }
    ]
    
    %{"prompts" => built_in_prompts ++ tool_prompts}
  end
  
  @doc """
  Gets a specific prompt by name.
  """
  def get_prompt(name) do
    prompts = list_prompts()["prompts"]
    
    case Enum.find(prompts, fn p -> p["name"] == name end) do
      nil ->
        %{
          "description" => "Prompt not found",
          "messages" => [],
          "isError" => true
        }
        
      prompt ->
        # Return prompt with example messages
        %{
          "description" => prompt["description"],
          "arguments" => prompt["arguments"],
          "messages" => build_prompt_messages(name)
        }
    end
  end
  
  # Private functions
  
  defp list_workspace_resources do
    case Workspace.list_projects(%{}) do
      {:ok, projects} ->
        Enum.map(projects, fn project ->
          %{
            "uri" => "workspace://project/#{project.id}",
            "name" => project.name,
            "description" => project.description || "Workspace project",
            "mimeType" => "application/json"
          }
        end)
        
      _ ->
        []
    end
  end
  
  defp list_memory_resources do
    # List memory contexts as resources
    [
      %{
        "uri" => "memory://short-term/current",
        "name" => "Current Session Memory",
        "description" => "Short-term memory for current session",
        "mimeType" => "application/json"
      },
      %{
        "uri" => "memory://patterns/recent",
        "name" => "Recent Code Patterns",
        "description" => "Recently identified code patterns",
        "mimeType" => "application/json"
      }
    ]
  end
  
  defp apply_pagination(resources, %{"cursor" => cursor}) do
    # Simple cursor-based pagination
    # In real implementation, would use proper cursor logic
    start_index = String.to_integer(cursor || "0")
    Enum.slice(resources, start_index, 100)
  end
  defp apply_pagination(resources, _), do: resources
  
  defp parse_resource_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: "workspace", host: type, path: "/" <> id} ->
        {:ok, {:workspace, type, id}}
        
      %URI{scheme: "memory", host: type, path: "/" <> id} ->
        {:ok, {:memory, type, id}}
        
      %URI{scheme: "tool", host: tool_name, path: "/" <> resource_type} ->
        {:ok, {:tool, tool_name, resource_type}}
        
      _ ->
        {:error, :invalid_uri}
    end
  end
  
  defp read_workspace_resource("project", id, _context) do
    case Workspace.get_project(id) do
      {:ok, project} ->
        %{
          "contents" => [
            %{
              "uri" => "workspace://project/#{id}",
              "mimeType" => "application/json",
              "text" => Jason.encode!(%{
                id: project.id,
                name: project.name,
                description: project.description,
                created_at: project.created_at,
                updated_at: project.updated_at
              })
            }
          ]
        }
        
      _ ->
        %{
          "contents" => [
            %{
              "type" => "text",
              "text" => "Project not found"
            }
          ],
          "isError" => true
        }
    end
  end
  
  defp read_memory_resource("short-term", "current", context) do
    # Get current session memory
    # TODO: Implement proper memory retrieval
    memory_content = %{
      session_id: context.session_id,
      items: []
    }
    
    %{
      "contents" => [
        %{
          "uri" => "memory://short-term/current",
          "mimeType" => "application/json",
          "text" => Jason.encode!(memory_content)
        }
      ]
    }
  end
  
  defp read_memory_resource("patterns", "recent", _context) do
    # Get recent patterns
    # TODO: Implement proper pattern retrieval
    patterns = []
    
    %{
      "contents" => [
        %{
          "uri" => "memory://patterns/recent",
          "mimeType" => "application/json",
          "text" => Jason.encode!(patterns)
        }
      ]
    }
  end
  
  defp build_prompt_messages("analyze_code") do
    [
      %{
        "role" => "user",
        "content" => %{
          "type" => "text",
          "text" => "Please analyze the following {{language}} code:\n\n{{code}}"
        }
      }
    ]
  end
  
  defp build_prompt_messages("generate_tests") do
    [
      %{
        "role" => "user", 
        "content" => %{
          "type" => "text",
          "text" => "Generate {{framework}} test cases for this code:\n\n{{code}}"
        }
      }
    ]
  end
  
  defp build_prompt_messages("refactor_code") do
    [
      %{
        "role" => "user",
        "content" => %{
          "type" => "text", 
          "text" => "Suggest refactoring improvements for this code with goal: {{goal}}\n\n{{code}}"
        }
      }
    ]
  end
  
  defp build_prompt_messages(_), do: []
  
  defp list_tool_resources do
    Registry.list_all()
    |> Enum.flat_map(fn tool ->
      module = Map.get(tool, :module) || tool
      ToolAdapter.discover_tool_resources(module)
    end)
  end
  
  defp read_tool_resource(tool_name, resource_type, _context) do
    case Registry.get(String.to_atom(tool_name)) do
      {:ok, tool_module} ->
        case resource_type do
          "documentation" ->
            metadata = tool_module.__tool__(:metadata)
            %{
              "contents" => [
                %{
                  "uri" => "tool://#{tool_name}/documentation",
                  "mimeType" => "text/markdown",
                  "text" => metadata.description || "No documentation available"
                }
              ]
            }
            
          "schema" ->
            metadata = tool_module.__tool__(:metadata)
            schema = ToolAdapter.parameter_schema_to_mcp(metadata.parameters)
            %{
              "contents" => [
                %{
                  "uri" => "tool://#{tool_name}/schema",
                  "mimeType" => "application/schema+json",
                  "text" => Jason.encode!(schema, pretty: true)
                }
              ]
            }
            
          "examples" ->
            metadata = tool_module.__tool__(:metadata)
            examples = metadata.examples || []
            %{
              "contents" => [
                %{
                  "uri" => "tool://#{tool_name}/examples",
                  "mimeType" => "application/json",
                  "text" => Jason.encode!(examples, pretty: true)
                }
              ]
            }
            
          _ ->
            %{
              "contents" => [
                %{
                  "type" => "text",
                  "text" => "Unknown resource type: #{resource_type}"
                }
              ],
              "isError" => true
            }
        end
        
      _ ->
        %{
          "contents" => [
            %{
              "type" => "text",
              "text" => "Tool not found: #{tool_name}"
            }
          ],
          "isError" => true
        }
    end
  end
end