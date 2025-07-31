defmodule RubberDuck.Agents.PromptManagerAgentTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.PromptManagerAgent
  alias RubberDuck.Agents.Prompt.Template
  alias RubberDuck.Jido.Actions.PromptManager.{
    CreateTemplateAction,
    GetTemplateAction,
    ListTemplatesAction,
    BuildPromptAction,
    ValidateTemplateAction,
    GetAnalyticsAction,
    GetUsageStatsAction,
    OptimizeTemplateAction,
    GetStatusAction,
    ClearCacheAction
  }
  
  describe "agent initialization" do
    test "initializes with default templates" do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager")
      state = :sys.get_state(agent)
      
      assert map_size(state.templates) > 0
      assert Map.has_key?(state, :config)
      assert state.config.cache_ttl == 3600
      
      GenServer.stop(agent)
    end
  end
  
  describe "template management actions" do
    setup do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager-#{System.unique_integer()}")
      %{agent: agent}
    end
    
    test "creates template successfully", %{agent: agent} do
      template_data = %{
        "name" => "Test Template",
        "description" => "A test template",
        "content" => "Hello {{name}}!",
        "variables" => [
          %{"name" => "name", "type" => "string", "required" => true, "description" => "User name"}
        ],
        "category" => "greeting",
        "tags" => ["test", "greeting"]
      }
      
      params = %{template_data: template_data}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, params)
      assert Map.has_key?(result, :template)
      assert result.template.name == "Test Template"
      
      GenServer.stop(agent)
    end
    
    test "handles template creation failure", %{agent: agent} do
      # Invalid template data (missing required fields)
      template_data = %{
        "description" => "Missing name and content"
      }
      
      params = %{template_data: template_data}
      
      assert {:error, _reason} = PromptManagerAgent.cmd(agent, CreateTemplateAction, params)
      
      GenServer.stop(agent)
    end
    
    test "retrieves template by ID", %{agent: agent} do
      # First create a template
      template_data = %{
        "name" => "Test Template",
        "description" => "A test template",
        "content" => "Hello {{name}}!",
        "variables" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }
      
      {:ok, create_result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template_data})
      template_id = create_result.template.id
      
      # Now retrieve it
      params = %{id: template_id}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, GetTemplateAction, params)
      assert result.template.id == template_id
      assert Map.has_key?(result, :stats)
      
      GenServer.stop(agent)
    end
    
    test "handles template not found", %{agent: agent} do
      params = %{id: "non-existent-id"}
      
      assert {:error, :template_not_found} = PromptManagerAgent.cmd(agent, GetTemplateAction, params)
      
      GenServer.stop(agent)
    end
    
    test "lists templates with filters", %{agent: agent} do
      # Create some test templates
      template1_data = %{
        "name" => "Template 1",
        "description" => "First template",
        "content" => "Content 1",
        "category" => "coding",
        "tags" => ["test"]
      }
      
      template2_data = %{
        "name" => "Template 2",
        "description" => "Second template", 
        "content" => "Content 2",
        "category" => "analysis",
        "tags" => ["analysis"]
      }
      
      {:ok, _result1} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template1_data})
      {:ok, _result2} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template2_data})
      
      # List with category filter
      params = %{filters: %{"category" => "coding"}}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, ListTemplatesAction, params)
      assert result.count == 1
      assert length(result.templates) == 1
      
      template = List.first(result.templates)
      assert template.category == "coding"
      
      GenServer.stop(agent)
    end
  end
  
  describe "prompt building actions" do
    setup do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager-#{System.unique_integer()}")
      
      template_data = %{
        "name" => "Greeting Template",
        "content" => "Hello {{name}}, welcome to {{platform}}!",
        "variables" => [
          %{"name" => "name", "type" => "string", "required" => true},
          %{"name" => "platform", "type" => "string", "required" => true}
        ]
      }
      
      {:ok, create_result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template_data})
      
      %{agent: agent, template: create_result.template}
    end
    
    test "builds prompt successfully", %{agent: agent, template: template} do
      params = %{
        template_id: template.id,
        context: %{
          "name" => "Alice",
          "platform" => "RubberDuck"
        },
        options: %{}
      }
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, BuildPromptAction, params)
      assert result["template_id"] == template.id
      assert String.contains?(result["prompt"], "Hello Alice")
      assert String.contains?(result["prompt"], "welcome to RubberDuck")
      assert Map.has_key?(result, "metadata")
      
      GenServer.stop(agent)
    end
    
    test "handles prompt building failure due to missing variables", %{agent: agent, template: template} do
      params = %{
        template_id: template.id,
        context: %{
          "name" => "Alice"
          # Missing "platform" variable
        },
        options: %{}
      }
      
      assert {:error, _reason} = PromptManagerAgent.cmd(agent, BuildPromptAction, params)
      
      GenServer.stop(agent)
    end
    
    test "validates template successfully", %{agent: agent} do
      template_data = %{
        "name" => "Valid Template",
        "content" => "Hello {{name}}!",
        "variables" => [
          %{"name" => "name", "type" => "string", "required" => true}
        ]
      }
      
      params = %{template: template_data}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, ValidateTemplateAction, params)
      assert result.valid == true
      assert Map.has_key?(result, :template_id)
      
      GenServer.stop(agent)
    end
    
    test "validates template with errors", %{agent: agent} do
      template_data = %{
        "name" => "Invalid Template",
        "content" => "Hello {{name}} and {{missing_var}}!",
        "variables" => [
          %{"name" => "name", "type" => "string", "required" => true}
          # Missing definition for "missing_var"
        ]
      }
      
      params = %{template: template_data}
      
      assert {:error, _reason} = PromptManagerAgent.cmd(agent, ValidateTemplateAction, params)
      
      GenServer.stop(agent)
    end
  end
  
  describe "analytics actions" do
    setup do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager-#{System.unique_integer()}")
      
      template_data = %{
        "name" => "Analytics Template",
        "content" => "Test content {{param}}",
        "variables" => [%{"name" => "param", "type" => "string", "required" => true}]
      }
      
      {:ok, create_result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template_data})
      
      %{agent: agent, template: create_result.template}
    end
    
    test "gets analytics report", %{agent: agent} do
      params = %{filters: %{}}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, GetAnalyticsAction, params)
      assert Map.has_key?(result, "total_templates")
      assert Map.has_key?(result, "templates_by_category")
      assert Map.has_key?(result, "most_used_templates")
      assert Map.has_key?(result, "generated_at")
      
      GenServer.stop(agent)
    end
    
    test "gets usage stats for specific template", %{agent: agent, template: template} do
      params = %{template_id: template.id}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, GetUsageStatsAction, params)
      assert result.template_id == template.id
      assert Map.has_key?(result, :stats)
      assert Map.has_key?(result, :detailed_analytics)
      
      GenServer.stop(agent)
    end
    
    test "gets optimization suggestions", %{agent: agent, template: template} do
      params = %{template_id: template.id}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, OptimizeTemplateAction, params)
      assert result.template_id == template.id
      assert Map.has_key?(result, :suggestions)
      assert Map.has_key?(result, :confidence_score)
      assert is_list(result.suggestions)
      
      GenServer.stop(agent)
    end
  end
  
  describe "system actions" do
    setup do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager-#{System.unique_integer()}")
      %{agent: agent}
    end
    
    test "gets status report", %{agent: agent} do
      params = %{}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, GetStatusAction, params)
      assert Map.has_key?(result, "templates_count")
      assert Map.has_key?(result, "cache_size")
      assert Map.has_key?(result, "memory_usage")
      assert Map.has_key?(result, "uptime")
      assert result["health"] == "healthy"
      
      GenServer.stop(agent)
    end
    
    test "clears cache", %{agent: agent} do
      # First, add something to cache by building a prompt
      template_data = %{
        "name" => "Cache Test Template",
        "content" => "Hello {{name}}!",
        "variables" => [%{"name" => "name", "type" => "string", "required" => true}]
      }
      
      {:ok, create_result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template_data})
      
      # Build a prompt to populate cache
      {:ok, _build_result} = PromptManagerAgent.cmd(agent, BuildPromptAction, %{
        template_id: create_result.template.id,
        context: %{"name" => "Alice"},
        options: %{}
      })
      
      # Clear cache
      params = %{}
      
      assert {:ok, result} = PromptManagerAgent.cmd(agent, ClearCacheAction, params)
      assert Map.has_key?(result, :timestamp)
      
      GenServer.stop(agent)
    end
  end
  
  describe "caching functionality" do
    setup do
      {:ok, agent} = PromptManagerAgent.start_link(id: "test-prompt-manager-#{System.unique_integer()}")
      
      template_data = %{
        "name" => "Cached Template",
        "content" => "Hello {{name}}!",
        "variables" => [%{"name" => "name", "type" => "string", "required" => true}]
      }
      
      {:ok, create_result} = PromptManagerAgent.cmd(agent, CreateTemplateAction, %{template_data: template_data})
      
      %{agent: agent, template: create_result.template}
    end
    
    test "caches built prompts", %{agent: agent, template: template} do
      params = %{
        template_id: template.id,
        context: %{"name" => "Alice"},
        options: %{}
      }
      
      # First request should build and cache
      {:ok, result1} = PromptManagerAgent.cmd(agent, BuildPromptAction, params)
      refute Map.get(result1, "cache_hit", false)
      
      # Second request should hit cache
      {:ok, result2} = PromptManagerAgent.cmd(agent, BuildPromptAction, params)
      assert result2["cache_hit"] == true
      
      GenServer.stop(agent)
    end
  end
end