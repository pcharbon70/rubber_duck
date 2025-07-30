defmodule RubberDuck.Agents.PromptManagerAgentTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.PromptManagerAgent
  alias RubberDuck.Agents.Prompt.{Template, Builder, Experiment}
  
  describe "agent initialization" do
    test "initializes with default templates" do
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{},
        experiments: %{},
        analytics: %{},
        cache: %{},
        config: %{
          cache_ttl: 3600,
          max_templates: 1000,
          analytics_retention_days: 30
        }
      })
      
      assert map_size(agent.templates) > 0
      assert Map.has_key?(agent, :config)
      assert agent.config.cache_ttl == 3600
    end
  end
  
  describe "template management signals" do
    setup do
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{},
        experiments: %{},
        analytics: %{},
        cache: %{},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
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
      
      signal = %{
        "type" => "create_template",
        "data" => template_data
      }
      
      # Mock emit_signal to capture the response
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      # Check that template was created
      assert map_size(updated_agent.templates) > map_size(agent.templates)
      
      # Check signal was emitted
      assert_receive {:signal_emitted, "template_created", response_data}
      assert Map.has_key?(response_data, "template_id")
      assert response_data["name"] == "Test Template"
    end
    
    test "handles template creation failure", %{agent: agent} do
      # Invalid template data (missing required fields)
      template_data = %{
        "description" => "Missing name and content"
      }
      
      signal = %{
        "type" => "create_template",
        "data" => template_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      # Check error signal was emitted
      assert_receive {:signal_emitted, "template_creation_failed", error_data}
      assert Map.has_key?(error_data, "error")
    end
    
    test "retrieves template by ID", %{agent: agent} do
      # First create a template
      {:ok, template} = Template.new(%{
        name: "Test Template",
        content: "Hello {{name}}!",
        variables: [%{name: "name", type: :string, required: true}]
      })
      
      agent = put_in(agent.templates[template.id], template)
      
      signal = %{
        "type" => "get_template",
        "data" => %{"id" => template.id}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "template_response", response_data}
      assert response_data["template"].id == template.id
      assert Map.has_key?(response_data, "stats")
    end
    
    test "handles template not found", %{agent: agent} do
      signal = %{
        "type" => "get_template",
        "data" => %{"id" => "non-existent-id"}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "template_not_found", error_data}
      assert error_data["template_id"] == "non-existent-id"
    end
    
    test "lists templates with filters", %{agent: agent} do
      # Create some test templates
      {:ok, template1} = Template.new(%{
        name: "Template 1",
        content: "Content 1",
        category: "coding",
        tags: ["test"]
      })
      
      {:ok, template2} = Template.new(%{
        name: "Template 2", 
        content: "Content 2",
        category: "analysis",
        tags: ["analysis"]
      })
      
      agent = agent
      |> put_in([:templates, template1.id], template1)
      |> put_in([:templates, template2.id], template2)
      
      signal = %{
        "type" => "list_templates",
        "data" => %{"category" => "coding"}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "templates_list", response_data}
      assert response_data["count"] == 1
      assert length(response_data["templates"]) == 1
      
      template = List.first(response_data["templates"])
      assert template["category"] == "coding"
    end
  end
  
  describe "prompt building signals" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Greeting Template",
        content: "Hello {{name}}, welcome to {{platform}}!",
        variables: [
          %{name: "name", type: :string, required: true},
          %{name: "platform", type: :string, required: true}
        ]
      })
      
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{template.id => template},
        experiments: %{},
        analytics: %{},
        cache: %{},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
      %{agent: agent, template: template}
    end
    
    test "builds prompt successfully", %{agent: agent, template: template} do
      signal = %{
        "type" => "build_prompt",
        "data" => %{
          "template_id" => template.id,
          "context" => %{
            "name" => "Alice",
            "platform" => "RubberDuck"
          }
        }
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "prompt_built", response_data}
      assert response_data["template_id"] == template.id
      assert String.contains?(response_data["prompt"], "Hello Alice")
      assert String.contains?(response_data["prompt"], "welcome to RubberDuck")
      assert Map.has_key?(response_data, "metadata")
    end
    
    test "handles prompt building failure due to missing variables", %{agent: agent, template: template} do
      signal = %{
        "type" => "build_prompt",
        "data" => %{
          "template_id" => template.id,
          "context" => %{
            "name" => "Alice"
            # Missing "platform" variable
          }
        }
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "prompt_build_failed", error_data}
      assert error_data["template_id"] == template.id
      assert String.contains?(error_data["error"], "platform")
    end
    
    test "validates template successfully", %{agent: agent} do
      template_data = %{
        "template" => %{
          "name" => "Valid Template",
          "content" => "Hello {{name}}!",
          "variables" => [
            %{"name" => "name", "type" => "string", "required" => true}
          ]
        }
      }
      
      signal = %{
        "type" => "validate_template",
        "data" => template_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "template_valid", response_data}
      assert response_data["valid"] == true
      assert Map.has_key?(response_data, "template_id")
    end
    
    test "validates template with errors", %{agent: agent} do
      template_data = %{
        "template" => %{
          "name" => "Invalid Template",
          "content" => "Hello {{name}} and {{missing_var}}!",
          "variables" => [
            %{"name" => "name", "type" => "string", "required" => true}
            # Missing definition for "missing_var"
          ]
        }
      }
      
      signal = %{
        "type" => "validate_template",
        "data" => template_data
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "template_invalid", error_data}
      assert error_data["valid"] == false
      assert String.contains?(error_data["error"], "missing_var")
    end
  end
  
  describe "analytics signals" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Analytics Template",
        content: "Test content {{param}}",
        variables: [%{name: "param", type: :string, required: true}],
        metadata: %{usage_count: 10, error_count: 1}
      })
      
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{template.id => template},
        experiments: %{},
        analytics: %{template.id => %{response_times: [100, 150, 200]}},
        cache: %{},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
      %{agent: agent, template: template}
    end
    
    test "gets analytics report", %{agent: agent} do
      signal = %{
        "type" => "get_analytics",
        "data" => %{}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "analytics_report", report_data}
      assert Map.has_key?(report_data, "total_templates")
      assert Map.has_key?(report_data, "templates_by_category")
      assert Map.has_key?(report_data, "most_used_templates")
      assert Map.has_key?(report_data, "generated_at")
    end
    
    test "gets usage stats for specific template", %{agent: agent, template: template} do
      signal = %{
        "type" => "get_usage_stats",
        "data" => %{"template_id" => template.id}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "usage_stats", stats_data}
      assert stats_data["template_id"] == template.id
      assert Map.has_key?(stats_data, "stats")
      assert Map.has_key?(stats_data, "detailed_analytics")
    end
    
    test "gets optimization suggestions", %{agent: agent, template: template} do
      signal = %{
        "type" => "optimize_template",
        "data" => %{"template_id" => template.id}
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "optimization_suggestions", suggestions_data}
      assert suggestions_data["template_id"] == template.id
      assert Map.has_key?(suggestions_data, "suggestions")
      assert Map.has_key?(suggestions_data, "confidence_score")
      assert is_list(suggestions_data["suggestions"])
    end
  end
  
  describe "system signals" do
    setup do
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{},
        experiments: %{},
        analytics: %{},
        cache: %{"cached_key" => %{data: "cached_data", expires_at: DateTime.add(DateTime.utc_now(), 3600)}},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
      %{agent: agent}
    end
    
    test "gets status report", %{agent: agent} do
      signal = %{
        "type" => "get_status"
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "status_report", status_data}
      assert Map.has_key?(status_data, "templates_count")
      assert Map.has_key?(status_data, "cache_size")
      assert Map.has_key?(status_data, "memory_usage")
      assert Map.has_key?(status_data, "uptime")
      assert status_data["health"] == "healthy"
    end
    
    test "clears cache", %{agent: agent} do
      # Verify cache has content initially
      assert map_size(agent.cache) > 0
      
      signal = %{
        "type" => "clear_cache"
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      {:ok, updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      # Verify cache was cleared
      assert map_size(updated_agent.cache) == 0
      
      assert_receive {:signal_emitted, "cache_cleared", clear_data}
      assert Map.has_key?(clear_data, "timestamp")
    end
  end
  
  describe "caching functionality" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Cached Template",
        content: "Hello {{name}}!",
        variables: [%{name: "name", type: :string, required: true}]
      })
      
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{template.id => template},
        experiments: %{},
        analytics: %{},
        cache: %{},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
      %{agent: agent, template: template}
    end
    
    test "caches built prompts", %{agent: agent, template: template} do
      context = %{"name" => "Alice"}
      
      signal = %{
        "type" => "build_prompt",
        "data" => %{
          "template_id" => template.id,
          "context" => context
        }
      }
      
      test_pid = self()
      
      agent_with_mock = %{agent | 
        emit_signal: fn type, data ->
          send(test_pid, {:signal_emitted, type, data})
        end
      }
      
      # First request should build and cache
      {:ok, updated_agent} = PromptManagerAgent.handle_signal(agent_with_mock, signal)
      
      assert_receive {:signal_emitted, "prompt_built", response_data}
      refute Map.get(response_data, "cache_hit", false)
      
      # Verify something was cached
      assert map_size(updated_agent.cache) > 0
      
      # Second request should hit cache
      {:ok, _final_agent} = PromptManagerAgent.handle_signal(updated_agent, signal)
      
      assert_receive {:signal_emitted, "prompt_built", cached_response_data}
      assert cached_response_data["cache_hit"] == true
    end
  end
  
  describe "unknown signals" do
    setup do
      {:ok, agent} = PromptManagerAgent.mount(%{}, %{
        templates: %{},
        experiments: %{},
        analytics: %{},
        cache: %{},
        config: %{cache_ttl: 3600, max_templates: 1000, analytics_retention_days: 30}
      })
      
      %{agent: agent}
    end
    
    test "handles unknown signal gracefully", %{agent: agent} do
      signal = %{
        "type" => "unknown_signal",
        "data" => %{"some" => "data"}
      }
      
      # Should not crash
      {:ok, _updated_agent} = PromptManagerAgent.handle_signal(agent, signal)
    end
  end
end