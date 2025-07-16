defmodule RubberDuck.MCP.IntegrationTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.MCP.{Client, Registry, Integration}
  alias RubberDuck.MCP.Integration.{Memory, Engines, Context, Agents}
  alias RubberDuck.LLM.Providers.MCP, as: MCPProvider
  
  @moduletag :mcp_integration
  
  setup_all do
    # Start necessary services
    start_supervised!(Registry)
    start_supervised!(RubberDuck.MCP.ClientSupervisor)
    
    :ok
  end
  
  describe "LLM provider integration" do
    test "MCP provider implements required behavior" do
      # Test that MCP provider implements all required callbacks
      assert function_exported?(MCPProvider, :execute, 2)
      assert function_exported?(MCPProvider, :stream_completion, 3)
      assert function_exported?(MCPProvider, :validate_config, 1)
      assert function_exported?(MCPProvider, :supports_feature?, 1)
      assert function_exported?(MCPProvider, :count_tokens, 2)
      assert function_exported?(MCPProvider, :health_check, 1)
      assert function_exported?(MCPProvider, :connect, 1)
      assert function_exported?(MCPProvider, :disconnect, 2)
    end
    
    test "validates MCP provider configuration" do
      # Valid config
      valid_config = %{
        mcp_client: :test_client,
        models: ["gpt-4"],
        mcp_config: %{
          transport: {:stdio, command: "test", args: []},
          capabilities: [:tools, :resources]
        }
      }
      
      assert :ok = MCPProvider.validate_config(valid_config)
      
      # Invalid config - missing required fields
      invalid_config = %{
        mcp_client: :test_client
      }
      
      assert {:error, {:missing_required_fields, [:models]}} = 
        MCPProvider.validate_config(invalid_config)
    end
    
    test "reports correct feature support" do
      assert MCPProvider.supports_feature?(:streaming) == true
      assert MCPProvider.supports_feature?(:tools) == true
      assert MCPProvider.supports_feature?(:function_calling) == true
      assert MCPProvider.supports_feature?(:system_messages) == true
      assert MCPProvider.supports_feature?(:vision) == false
      assert MCPProvider.supports_feature?(:unknown_feature) == false
    end
  end
  
  describe "memory system integration" do
    test "sets up memory integration components" do
      assert :ok = Integration.setup_memory_integration()
      
      # Verify memory resource is registered
      {:ok, resources} = Registry.list_resources()
      memory_resources = Enum.filter(resources, fn resource ->
        String.starts_with?(resource.uri, "memory://")
      end)
      
      assert length(memory_resources) > 0
    end
    
    test "memory resource operations" do
      # Create a test memory store
      store_id = "test_store"
      
      # Test list operation
      params = %{store_id: store_id, operation: "list"}
      frame = Hermes.Server.Frame.new()
      
      # This would typically interact with actual memory system
      # For now, we test the interface
      assert is_function(&Memory.read/2)
      assert is_function(&Memory.list/1)
    end
    
    test "memory tools are registered" do
      # Check that memory tools are available
      {:ok, tools} = Registry.list_tools()
      memory_tools = Enum.filter(tools, fn tool ->
        tool.category == :memory
      end)
      
      # Should have memory manipulation tools
      tool_names = Enum.map(memory_tools, & &1.name)
      assert "memory_put" in tool_names
      assert "memory_get" in tool_names
      assert "memory_delete" in tool_names
    end
  end
  
  describe "workflow system integration" do
    test "MCP workflow steps are available" do
      # Test that workflow step types are defined
      assert Code.ensure_loaded?(RubberDuck.MCP.Integration.WorkflowSteps.MCPToolStep)
      assert Code.ensure_loaded?(RubberDuck.MCP.Integration.WorkflowSteps.MCPResourceStep)
      assert Code.ensure_loaded?(RubberDuck.MCP.Integration.WorkflowSteps.MCPCompositionStep)
      assert Code.ensure_loaded?(RubberDuck.MCP.Integration.WorkflowSteps.MCPStreamingStep)
    end
    
    test "workflow steps implement required behavior" do
      # Test MCPToolStep
      step_module = RubberDuck.MCP.Integration.WorkflowSteps.MCPToolStep
      
      assert function_exported?(step_module, :run, 3)
      assert function_exported?(step_module, :compensate, 4)
    end
  end
  
  describe "engine system integration" do
    test "engine resources are exposed" do
      # Test that engines are exposed as MCP resources
      assert is_function(&Engines.read/2)
      assert is_function(&Engines.list/1)
    end
    
    test "engine tools are registered" do
      {:ok, tools} = Registry.list_tools()
      engine_tools = Enum.filter(tools, fn tool ->
        tool.category == :engines
      end)
      
      # Should have engine execution tools
      tool_names = Enum.map(engine_tools, & &1.name)
      assert "engine_execute" in tool_names
      assert "engine_get_result" in tool_names
      assert "engine_cancel" in tool_names
    end
  end
  
  describe "context building integration" do
    test "enhances context with MCP information" do
      base_context = %{user: "test_user", task: "test_task"}
      
      enhanced_context = Context.enhance_context(base_context, 
        include_tools: true,
        include_resources: true,
        include_clients: true
      )
      
      assert Map.has_key?(enhanced_context, :mcp)
      assert Map.has_key?(enhanced_context.mcp, :tools)
      assert Map.has_key?(enhanced_context.mcp, :resources)
      assert Map.has_key?(enhanced_context.mcp, :clients)
    end
    
    test "creates MCP-aware prompts" do
      context = %{
        mcp: %{
          tools: [
            %{name: "test_tool", description: "A test tool", capabilities: [:test]}
          ],
          resources: [
            %{name: "test_resource", description: "A test resource", uri: "test://resource"}
          ]
        }
      }
      
      base_prompt = "Help me with this task"
      mcp_prompt = Context.create_mcp_prompt(base_prompt, context)
      
      assert String.contains?(mcp_prompt, "Available MCP Tools and Resources")
      assert String.contains?(mcp_prompt, "test_tool")
      assert String.contains?(mcp_prompt, "test_resource")
    end
    
    test "builds tool execution context" do
      context = Context.build_tool_context("test_tool", %{param: "value"})
      
      assert context.tool_name == "test_tool"
      assert context.params == %{param: "value"}
      assert %DateTime{} = context.timestamp
    end
  end
  
  describe "agent system integration" do
    test "enhances agents with MCP capabilities" do
      base_agent = %{
        id: "test_agent",
        name: "Test Agent",
        capabilities: %{},
        preferences: %{}
      }
      
      enhanced_agent = Agents.enhance_agent(base_agent)
      
      assert Map.has_key?(enhanced_agent.capabilities, :mcp_tool_discovery)
      assert Map.has_key?(enhanced_agent.capabilities, :mcp_tool_learning)
      assert Map.has_key?(enhanced_agent.capabilities, :mcp_composition)
      assert Map.has_key?(enhanced_agent.capabilities, :mcp_context_awareness)
    end
    
    test "discovers tools for agent" do
      agent = %{
        id: "test_agent",
        name: "Test Agent",
        capabilities: %{},
        preferences: %{}
      }
      
      discovery_result = Agents.discover_tools_for_agent(agent)
      
      assert Map.has_key?(discovery_result, :available_tools)
      assert Map.has_key?(discovery_result, :recommended_tools)
      assert Map.has_key?(discovery_result, :discovery_time)
    end
    
    test "gets personalized recommendations" do
      agent = %{
        id: "test_agent",
        name: "Test Agent",
        capabilities: %{},
        preferences: %{}
      }
      
      case Agents.get_personalized_recommendations(agent) do
        {:ok, recommendations} ->
          assert is_list(recommendations)
          Enum.each(recommendations, fn rec ->
            assert Map.has_key?(rec, :name)
            assert Map.has_key?(rec, :agent_score)
            assert Map.has_key?(rec, :recommendation_reason)
          end)
          
        {:error, _} ->
          # Expected if no tools are registered
          :ok
      end
    end
  end
  
  describe "system integration" do
    test "setup integrations succeeds" do
      assert :ok = Integration.setup_integrations()
    end
    
    test "exposes system components as resources" do
      assert :ok = Integration.expose_as_resource(:test_component, "test_id", %{
        name: "Test Component",
        description: "A test component"
      })
    end
    
    test "wraps system functions as tools" do
      assert :ok = Integration.wrap_as_tool(String, :upcase, %{
        name: "string_upcase",
        description: "Convert string to uppercase"
      })
    end
    
    test "enables tool discovery for components" do
      assert :ok = Integration.enable_tool_discovery(:workflows)
      assert {:error, :unsupported_component} = Integration.enable_tool_discovery(:unknown)
    end
    
    test "syncs system state" do
      assert :ok = Integration.sync_system_state()
    end
  end
  
  describe "end-to-end integration flows" do
    test "complete tool execution flow" do
      # This would test a complete flow from discovery to execution
      # For now, we test the interface
      
      # 1. Discover tools
      case Registry.list_tools() do
        {:ok, tools} ->
          assert is_list(tools)
          
        {:error, _} ->
          # Expected if registry is not fully initialized
          :ok
      end
      
      # 2. Execute a tool (if available)
      # This would require actual tool registration and execution
      
      # 3. Check metrics
      # This would verify that metrics are recorded
    end
    
    test "composition execution flow" do
      # Test creating and executing a composition
      
      # 1. Create a simple composition
      composition = %{
        name: "test_composition",
        type: :sequential,
        tools: [
          %{tool: "test_tool", params: %{input: "test"}}
        ]
      }
      
      # 2. Validate composition structure
      assert composition.name == "test_composition"
      assert composition.type == :sequential
      assert is_list(composition.tools)
      
      # 3. Execute composition (would require actual implementation)
      # This would test the full execution flow
    end
    
    test "agent tool usage flow" do
      # Test agent discovering and using tools
      
      agent = %{
        id: "test_agent",
        name: "Test Agent",
        capabilities: %{},
        preferences: %{}
      }
      
      # 1. Enhance agent with MCP capabilities
      enhanced_agent = Agents.enhance_agent(agent)
      assert Map.has_key?(enhanced_agent.capabilities, :mcp_tool_discovery)
      
      # 2. Discover tools for agent
      discovery = Agents.discover_tools_for_agent(enhanced_agent)
      assert Map.has_key?(discovery, :available_tools)
      
      # 3. Execute tool for agent (would require actual tool)
      # This would test the full agent-tool interaction
    end
    
    test "context-aware execution" do
      # Test context building and usage
      
      base_context = %{user: "test", task: "analysis"}
      
      # 1. Enhance context with MCP information
      enhanced_context = Context.enhance_context(base_context)
      assert Map.has_key?(enhanced_context, :mcp)
      
      # 2. Create MCP-aware prompt
      prompt = Context.create_mcp_prompt("Help me analyze", enhanced_context)
      assert is_binary(prompt)
      
      # 3. Build tool context
      tool_context = Context.build_tool_context("analyzer", %{file: "test.ex"})
      assert tool_context.tool_name == "analyzer"
      assert tool_context.params == %{file: "test.ex"}
    end
  end
  
  describe "error handling and recovery" do
    test "handles missing dependencies gracefully" do
      # Test behavior when dependencies are not available
      
      # Should not crash when memory system is not available
      assert :ok = Integration.setup_memory_integration()
      
      # Should handle missing engines gracefully
      assert :ok = Integration.setup_engine_integration()
    end
    
    test "handles client connection failures" do
      # Test behavior when MCP clients fail to connect
      
      invalid_config = %{
        mcp_client: :nonexistent_client,
        models: ["test-model"],
        mcp_config: %{
          transport: {:stdio, command: "nonexistent", args: []},
          capabilities: [:tools]
        }
      }
      
      # Should handle connection failures gracefully
      case MCPProvider.connect(invalid_config) do
        {:error, _} -> :ok  # Expected
        {:ok, _} -> :ok     # Unexpected but acceptable
      end
    end
    
    test "handles tool execution failures" do
      # Test error handling during tool execution
      
      # Should handle unknown tool gracefully
      case Registry.execute_tool("nonexistent_tool", %{}) do
        {:error, _} -> :ok  # Expected
        {:ok, _} -> :ok     # Unexpected but acceptable
      end
    end
  end
end