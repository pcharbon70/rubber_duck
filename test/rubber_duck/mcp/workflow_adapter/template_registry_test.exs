defmodule RubberDuck.MCP.WorkflowAdapter.TemplateRegistryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.WorkflowAdapter.TemplateRegistry

  setup do
    # Start a fresh registry for each test
    {:ok, pid} = start_supervised(TemplateRegistry)
    %{registry: pid}
  end

  describe "register_template/1" do
    test "registers a valid template" do
      template_data = %{
        "name" => "test_template",
        "version" => "1.0.0",
        "description" => "A test template",
        "category" => "testing",
        "parameters" => [
          %{"name" => "input", "type" => "string", "required" => true}
        ],
        "definition" => %{
          "type" => "sequential",
          "steps" => [
            %{"tool" => "test_tool", "params" => %{"input" => "{{input}}"}}
          ]
        },
        "examples" => [
          %{"name" => "Basic usage", "params" => %{"input" => "hello"}}
        ]
      }

      {:ok, template} = TemplateRegistry.register_template(template_data)
      
      assert template.name == "test_template"
      assert template.version == "1.0.0"
      assert template.description == "A test template"
      assert template.category == "testing"
      assert length(template.parameters) == 1
      assert length(template.examples) == 1
      assert %DateTime{} = template.created_at
      assert %DateTime{} = template.updated_at
    end

    test "returns error for template missing required fields" do
      template_data = %{
        "name" => "incomplete_template",
        "version" => "1.0.0"
        # Missing description and definition
      }

      assert {:error, reason} = TemplateRegistry.register_template(template_data)
      assert reason =~ "Missing required field"
    end

    test "assigns default values for optional fields" do
      template_data = %{
        "name" => "minimal_template",
        "version" => "1.0.0",
        "description" => "Minimal template",
        "definition" => %{
          "type" => "sequential",
          "steps" => []
        }
      }

      {:ok, template} = TemplateRegistry.register_template(template_data)
      
      assert template.category == "general"
      assert template.parameters == []
      assert template.examples == []
      assert template.metadata == %{}
    end
  end

  describe "get_template/1" do
    test "retrieves a registered template" do
      template_data = %{
        "name" => "retrievable_template",
        "version" => "1.0.0",
        "description" => "A template for retrieval",
        "definition" => %{"type" => "sequential", "steps" => []}
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      {:ok, template} = TemplateRegistry.get_template("retrievable_template")
      
      assert template.name == "retrievable_template"
      assert template.version == "1.0.0"
      assert template.description == "A template for retrieval"
    end

    test "returns error for non-existent template" do
      assert {:error, :not_found} = TemplateRegistry.get_template("non_existent")
    end
  end

  describe "get_template/2" do
    test "retrieves a specific version of a template" do
      template_data = %{
        "name" => "versioned_template",
        "version" => "2.1.0",
        "description" => "A versioned template",
        "definition" => %{"type" => "sequential", "steps" => []}
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      {:ok, template} = TemplateRegistry.get_template("versioned_template", "2.1.0")
      
      assert template.name == "versioned_template"
      assert template.version == "2.1.0"
    end

    test "returns error for wrong version" do
      template_data = %{
        "name" => "versioned_template",
        "version" => "1.0.0",
        "description" => "A versioned template",
        "definition" => %{"type" => "sequential", "steps" => []}
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      assert {:error, :version_not_found} = TemplateRegistry.get_template("versioned_template", "2.0.0")
    end
  end

  describe "list_templates/1" do
    test "lists all templates" do
      # Register multiple templates
      templates_data = [
        %{
          "name" => "template_1",
          "version" => "1.0.0",
          "description" => "First template",
          "category" => "data",
          "definition" => %{"type" => "sequential", "steps" => []}
        },
        %{
          "name" => "template_2",
          "version" => "1.0.0",
          "description" => "Second template",
          "category" => "user",
          "definition" => %{"type" => "sequential", "steps" => []}
        }
      ]

      for template_data <- templates_data do
        {:ok, _} = TemplateRegistry.register_template(template_data)
      end

      templates = TemplateRegistry.list_templates()
      
      # Should include built-in templates plus the registered ones
      assert length(templates) >= 2
      
      template_names = Enum.map(templates, & &1.name)
      assert "template_1" in template_names
      assert "template_2" in template_names
    end

    test "filters templates by category" do
      templates_data = [
        %{
          "name" => "data_template",
          "version" => "1.0.0",
          "description" => "Data template",
          "category" => "data_processing",
          "definition" => %{"type" => "sequential", "steps" => []}
        },
        %{
          "name" => "user_template",
          "version" => "1.0.0",
          "description" => "User template",
          "category" => "user_management",
          "definition" => %{"type" => "sequential", "steps" => []}
        }
      ]

      for template_data <- templates_data do
        {:ok, _} = TemplateRegistry.register_template(template_data)
      end

      data_templates = TemplateRegistry.list_templates(category: "data_processing")
      user_templates = TemplateRegistry.list_templates(category: "user_management")
      
      data_names = Enum.map(data_templates, & &1.name)
      user_names = Enum.map(user_templates, & &1.name)
      
      assert "data_template" in data_names
      assert "data_processing_pipeline" in data_names  # Built-in template
      assert "user_template" in user_names
      assert "user_onboarding" in user_names  # Built-in template
    end

    test "limits number of templates returned" do
      # Register multiple templates
      for i <- 1..5 do
        template_data = %{
          "name" => "template_#{i}",
          "version" => "1.0.0",
          "description" => "Template #{i}",
          "definition" => %{"type" => "sequential", "steps" => []}
        }
        {:ok, _} = TemplateRegistry.register_template(template_data)
      end

      limited_templates = TemplateRegistry.list_templates(limit: 3)
      
      assert length(limited_templates) == 3
    end
  end

  describe "instantiate_template/2" do
    test "instantiates template with valid parameters" do
      template_data = %{
        "name" => "parameterized_template",
        "version" => "1.0.0",
        "description" => "A parameterized template",
        "parameters" => [
          %{"name" => "source", "type" => "string", "required" => true},
          %{"name" => "destination", "type" => "string", "required" => true},
          %{"name" => "format", "type" => "string", "required" => false, "default" => "json"}
        ],
        "definition" => %{
          "type" => "sequential",
          "steps" => [
            %{"tool" => "fetcher", "params" => %{"source" => "{{source}}"}},
            %{"tool" => "transformer", "params" => %{"format" => "{{format}}"}},
            %{"tool" => "saver", "params" => %{"destination" => "{{destination}}"}}
          ]
        }
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      params = %{
        "source" => "api_endpoint",
        "destination" => "database",
        "format" => "xml"
      }

      {:ok, instantiated} = TemplateRegistry.instantiate_template("parameterized_template", params)
      
      assert instantiated["type"] == "sequential"
      assert length(instantiated["steps"]) == 3
      
      # Check parameter substitution
      steps_json = Jason.encode!(instantiated["steps"])
      assert String.contains?(steps_json, "api_endpoint")
      assert String.contains?(steps_json, "database")
      assert String.contains?(steps_json, "xml")
    end

    test "returns error for missing required parameters" do
      template_data = %{
        "name" => "required_params_template",
        "version" => "1.0.0",
        "description" => "Template with required params",
        "parameters" => [
          %{"name" => "required_param", "type" => "string", "required" => true}
        ],
        "definition" => %{
          "type" => "sequential",
          "steps" => [
            %{"tool" => "test_tool", "params" => %{"input" => "{{required_param}}"}}
          ]
        }
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      params = %{} # Missing required parameter

      assert {:error, reason} = TemplateRegistry.instantiate_template("required_params_template", params)
      assert reason =~ "Missing required parameters"
    end

    test "returns error for template not found" do
      params = %{"test" => "value"}
      
      assert {:error, :template_not_found} = TemplateRegistry.instantiate_template("non_existent", params)
    end

    test "handles nested parameter substitution" do
      template_data = %{
        "name" => "nested_template",
        "version" => "1.0.0",
        "description" => "Template with nested structure",
        "parameters" => [
          %{"name" => "user_id", "type" => "string", "required" => true},
          %{"name" => "action", "type" => "string", "required" => true}
        ],
        "definition" => %{
          "type" => "conditional",
          "condition" => %{
            "tool" => "validator",
            "params" => %{
              "user_id" => "{{user_id}}",
              "action" => "{{action}}"
            }
          },
          "success" => [
            %{"tool" => "processor", "params" => %{"user_id" => "{{user_id}}"}}
          ]
        }
      }

      {:ok, _} = TemplateRegistry.register_template(template_data)
      
      params = %{
        "user_id" => "user123",
        "action" => "process"
      }

      {:ok, instantiated} = TemplateRegistry.instantiate_template("nested_template", params)
      
      # Check nested parameter substitution
      condition_json = Jason.encode!(instantiated["condition"])
      assert String.contains?(condition_json, "user123")
      assert String.contains?(condition_json, "process")
      
      success_json = Jason.encode!(instantiated["success"])
      assert String.contains?(success_json, "user123")
    end
  end

  describe "register_trigger/1" do
    test "registers a valid trigger" do
      trigger_data = %{
        "event" => "user_created",
        "condition" => %{"user_type" => "premium"},
        "workflow" => "premium_onboarding",
        "delay" => 5000,
        "metadata" => %{"priority" => "high"}
      }

      assert :ok = TemplateRegistry.register_trigger(trigger_data)
    end

    test "returns error for trigger missing required fields" do
      trigger_data = %{
        "event" => "incomplete_event"
        # Missing required "workflow" field
      }

      assert {:error, reason} = TemplateRegistry.register_trigger(trigger_data)
      assert reason =~ "Missing required field"
    end

    test "assigns default values for optional fields" do
      trigger_data = %{
        "event" => "simple_event",
        "workflow" => "simple_workflow"
      }

      assert :ok = TemplateRegistry.register_trigger(trigger_data)
      
      # Verify trigger was registered with defaults
      triggers = TemplateRegistry.list_triggers()
      registered_trigger = Enum.find(triggers, &(&1.event == "simple_event"))
      
      assert registered_trigger.delay == 0
      assert registered_trigger.active == true
      assert registered_trigger.condition == nil
      assert registered_trigger.metadata == %{}
    end
  end

  describe "list_triggers/0" do
    test "lists all registered triggers" do
      trigger_data_list = [
        %{
          "event" => "event_1",
          "workflow" => "workflow_1",
          "delay" => 1000
        },
        %{
          "event" => "event_2",
          "workflow" => "workflow_2",
          "delay" => 2000
        }
      ]

      for trigger_data <- trigger_data_list do
        :ok = TemplateRegistry.register_trigger(trigger_data)
      end

      triggers = TemplateRegistry.list_triggers()
      
      assert length(triggers) >= 2
      
      events = Enum.map(triggers, & &1.event)
      assert "event_1" in events
      assert "event_2" in events
    end

    test "returns empty list when no triggers registered" do
      # Start with fresh registry
      {:ok, _pid} = start_supervised({TemplateRegistry, [auto_load: false]})
      
      triggers = TemplateRegistry.list_triggers()
      
      assert triggers == []
    end
  end

  describe "get_triggers_for_event/1" do
    test "returns triggers for specific event" do
      trigger_data_list = [
        %{
          "event" => "user_signup",
          "workflow" => "welcome_workflow",
          "active" => true
        },
        %{
          "event" => "user_signup",
          "workflow" => "analytics_workflow",
          "active" => true
        },
        %{
          "event" => "user_login",
          "workflow" => "login_workflow",
          "active" => true
        }
      ]

      for trigger_data <- trigger_data_list do
        :ok = TemplateRegistry.register_trigger(trigger_data)
      end

      signup_triggers = TemplateRegistry.get_triggers_for_event("user_signup")
      login_triggers = TemplateRegistry.get_triggers_for_event("user_login")
      
      assert length(signup_triggers) == 2
      assert length(login_triggers) == 1
      
      signup_workflows = Enum.map(signup_triggers, & &1.workflow)
      assert "welcome_workflow" in signup_workflows
      assert "analytics_workflow" in signup_workflows
      
      login_workflows = Enum.map(login_triggers, & &1.workflow)
      assert "login_workflow" in login_workflows
    end

    test "filters out inactive triggers" do
      trigger_data_list = [
        %{
          "event" => "test_event",
          "workflow" => "active_workflow",
          "active" => true
        },
        %{
          "event" => "test_event",
          "workflow" => "inactive_workflow",
          "active" => false
        }
      ]

      for trigger_data <- trigger_data_list do
        :ok = TemplateRegistry.register_trigger(trigger_data)
      end

      active_triggers = TemplateRegistry.get_triggers_for_event("test_event")
      
      assert length(active_triggers) == 1
      assert hd(active_triggers).workflow == "active_workflow"
    end

    test "returns empty list for non-existent event" do
      triggers = TemplateRegistry.get_triggers_for_event("non_existent_event")
      
      assert triggers == []
    end
  end

  describe "remove_trigger/1" do
    test "removes an existing trigger" do
      trigger_data = %{
        "event" => "removable_event",
        "workflow" => "removable_workflow"
      }

      :ok = TemplateRegistry.register_trigger(trigger_data)
      
      # Find the trigger to get its ID
      triggers = TemplateRegistry.list_triggers()
      trigger = Enum.find(triggers, &(&1.event == "removable_event"))
      
      assert :ok = TemplateRegistry.remove_trigger(trigger.id)
      
      # Verify it was removed
      updated_triggers = TemplateRegistry.list_triggers()
      remaining_events = Enum.map(updated_triggers, & &1.event)
      
      assert "removable_event" not in remaining_events
    end

    test "returns error for non-existent trigger" do
      assert {:error, :not_found} = TemplateRegistry.remove_trigger("non_existent_trigger_id")
    end
  end

  describe "built-in templates" do
    test "loads built-in templates on start" do
      templates = TemplateRegistry.list_templates()
      
      built_in_names = Enum.map(templates, & &1.name)
      
      assert "data_processing_pipeline" in built_in_names
      assert "user_onboarding" in built_in_names
      assert "content_moderation" in built_in_names
      assert "batch_processing" in built_in_names
      assert "api_integration" in built_in_names
    end

    test "built-in templates have proper structure" do
      templates = TemplateRegistry.list_templates()
      
      for template <- templates do
        assert is_binary(template.name)
        assert is_binary(template.version)
        assert is_binary(template.description)
        assert is_binary(template.category)
        assert is_list(template.parameters)
        assert is_map(template.definition)
        assert is_list(template.examples)
        assert %DateTime{} = template.created_at
        assert %DateTime{} = template.updated_at
      end
    end

    test "built-in templates can be instantiated" do
      # Test instantiation of data processing pipeline
      params = %{
        "source" => "test_api",
        "destination" => "test_db",
        "format" => "json"
      }

      {:ok, instantiated} = TemplateRegistry.instantiate_template("data_processing_pipeline", params)
      
      assert instantiated["type"] == "sequential"
      assert length(instantiated["steps"]) == 3
      
      # Verify parameter substitution
      steps_json = Jason.encode!(instantiated["steps"])
      assert String.contains?(steps_json, "test_api")
      assert String.contains?(steps_json, "test_db")
      assert String.contains?(steps_json, "json")
    end
  end

  describe "error handling and edge cases" do
    test "handles concurrent template registration" do
      # Test concurrent registration of templates
      tasks = for i <- 1..10 do
        Task.async(fn ->
          template_data = %{
            "name" => "concurrent_template_#{i}",
            "version" => "1.0.0",
            "description" => "Concurrent template #{i}",
            "definition" => %{"type" => "sequential", "steps" => []}
          }
          TemplateRegistry.register_template(template_data)
        end)
      end

      results = Task.await_many(tasks)
      
      # All registrations should succeed
      assert Enum.all?(results, fn {:ok, _} -> true; _ -> false end)
      
      # All templates should be retrievable
      templates = TemplateRegistry.list_templates()
      template_names = Enum.map(templates, & &1.name)
      
      for i <- 1..10 do
        assert "concurrent_template_#{i}" in template_names
      end
    end

    test "handles template with complex nested structure" do
      complex_template = %{
        "name" => "complex_template",
        "version" => "1.0.0",
        "description" => "Complex nested template",
        "parameters" => [
          %{"name" => "config", "type" => "object", "required" => true}
        ],
        "definition" => %{
          "type" => "conditional",
          "condition" => %{
            "tool" => "validator",
            "params" => %{
              "config" => "{{config}}",
              "nested" => %{
                "deep" => %{
                  "value" => "{{config.deep_value}}"
                }
              }
            }
          },
          "success" => [
            %{
              "tool" => "processor",
              "params" => %{
                "items" => ["{{config.item1}}", "{{config.item2}}"]
              }
            }
          ]
        }
      }

      {:ok, template} = TemplateRegistry.register_template(complex_template)
      
      assert template.name == "complex_template"
      assert Map.has_key?(template.definition, "condition")
      assert Map.has_key?(template.definition, "success")
    end

    test "validates parameter types and constraints" do
      # This test ensures the registry can handle various parameter types
      template_data = %{
        "name" => "typed_template",
        "version" => "1.0.0",
        "description" => "Template with typed parameters",
        "parameters" => [
          %{"name" => "string_param", "type" => "string", "required" => true},
          %{"name" => "number_param", "type" => "number", "required" => false, "default" => 42},
          %{"name" => "boolean_param", "type" => "boolean", "required" => false, "default" => true},
          %{"name" => "array_param", "type" => "array", "required" => false, "default" => []}
        ],
        "definition" => %{
          "type" => "sequential",
          "steps" => [
            %{"tool" => "test_tool", "params" => %{"input" => "{{string_param}}"}}
          ]
        }
      }

      {:ok, template} = TemplateRegistry.register_template(template_data)
      
      assert length(template.parameters) == 4
      
      # Verify parameter structure
      param_names = Enum.map(template.parameters, &Map.get(&1, "name"))
      assert "string_param" in param_names
      assert "number_param" in param_names
      assert "boolean_param" in param_names
      assert "array_param" in param_names
    end
  end
end