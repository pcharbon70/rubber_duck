defmodule RubberDuck.Agents.Prompt.TemplateTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.Prompt.Template

  describe "new/1" do
    test "creates template with valid attributes" do
      attrs = %{
        name: "Test Template",
        content: "Hello {{name}}!",
        variables: [
          %{name: "name", type: :string, required: true, description: "User name"}
        ],
        description: "A greeting template",
        category: "greeting",
        tags: ["test", "greeting"],
        access_level: :public
      }

      {:ok, template} = Template.new(attrs)

      assert template.name == "Test Template"
      assert template.content == "Hello {{name}}!"
      assert length(template.variables) == 1
      assert template.category == "greeting"
      assert template.access_level == :public
      assert template.version == "1.0.0"
      assert %DateTime{} = template.created_at
      assert %DateTime{} = template.updated_at
    end

    test "fails with missing required fields" do
      attrs = %{
        description: "Missing name and content"
      }

      {:error, reason} = Template.new(attrs)
      assert String.contains?(reason, "Missing required fields")
      assert String.contains?(reason, "name")
      assert String.contains?(reason, "content")
    end

    test "fails with invalid variable types" do
      attrs = %{
        name: "Invalid Template",
        content: "Hello {{name}}!",
        variables: [
          %{name: "name", type: :invalid_type, required: true}
        ]
      }

      {:error, reason} = Template.new(attrs)
      assert String.contains?(reason, "Invalid variable type")
    end

    test "fails with undefined variables in content" do
      attrs = %{
        name: "Undefined Vars Template",
        content: "Hello {{name}} and {{undefined_var}}!",
        variables: [
          %{name: "name", type: :string, required: true}
        ]
      }

      {:error, reason} = Template.new(attrs)
      assert String.contains?(reason, "Undefined variables")
      assert String.contains?(reason, "undefined_var")
    end

    test "sets default values" do
      attrs = %{
        name: "Minimal Template",
        content: "Simple content"
      }

      {:ok, template} = Template.new(attrs)

      assert template.description == ""
      assert template.variables == []
      assert template.category == "general"
      assert template.access_level == :private
      assert template.tags == []
      assert template.version == "1.0.0"
      assert is_binary(template.id)
    end
  end

  describe "update/2" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Original Template",
        content: "Hello {{name}}!",
        variables: [%{name: "name", type: :string, required: true}],
        version: "1.0.0"
      })

      %{template: template}
    end

    test "updates template attributes", %{template: template} do
      updates = %{
        name: "Updated Template",
        description: "New description",
        tags: ["updated"]
      }

      {:ok, updated_template} = Template.update(template, updates)

      assert updated_template.name == "Updated Template"
      assert updated_template.description == "New description"
      assert updated_template.tags == ["updated"]
      assert updated_template.version == "1.0.1"  # Version incremented
      assert DateTime.compare(updated_template.updated_at, template.updated_at) == :gt
    end

    test "validates updated content and variables", %{template: template} do
      updates = %{
        content: "Hello {{new_var}}!",
        variables: [%{name: "new_var", type: :string, required: true}]
      }

      {:ok, updated_template} = Template.update(template, updates)

      assert updated_template.content == "Hello {{new_var}}!"
      assert length(updated_template.variables) == 1
      assert List.first(updated_template.variables).name == "new_var"
    end

    test "fails validation on invalid updates", %{template: template} do
      updates = %{
        content: "Hello {{undefined}}!",
        variables: []  # No variables defined for {{undefined}}
      }

      {:error, reason} = Template.update(template, updates)
      assert String.contains?(reason, "Undefined variables")
    end
  end

  describe "extract_variables/1" do
    test "extracts variables from content" do
      content = "Hello {{name}}, welcome to {{platform}}! Your score is {{score}}."
      
      variables = Template.extract_variables(content)
      
      assert variables == ["name", "platform", "score"]
    end

    test "handles duplicate variables" do
      content = "{{name}} and {{name}} again, plus {{other}}"
      
      variables = Template.extract_variables(content)
      
      assert variables == ["name", "other"]
    end

    test "handles variables with spaces" do
      content = "{{ name }} and {{  other  }}"
      
      variables = Template.extract_variables(content)
      
      assert variables == ["name", "other"]
    end

    test "returns empty list for no variables" do
      content = "No variables here!"
      
      variables = Template.extract_variables(content)
      
      assert variables == []
    end
  end

  describe "variables_complete?/1" do
    test "returns true when all variables are defined" do
      {:ok, template} = Template.new(%{
        name: "Complete Template",
        content: "Hello {{name}} from {{location}}!",
        variables: [
          %{name: "name", type: :string, required: true},
          %{name: "location", type: :string, required: true}
        ]
      })

      assert Template.variables_complete?(template)
    end

    test "returns false when variables are missing" do
      {:ok, template} = Template.new(%{
        name: "Incomplete Template", 
        content: "Hello {{name}} from {{location}}!",
        variables: [
          %{name: "name", type: :string, required: true}
          # Missing "location" variable
        ]
      })

      # This should fail validation during creation
      # But if we manually construct for testing:
      template = %{template | variables: [%{name: "name", type: :string, required: true}]}
      
      refute Template.variables_complete?(template)
    end
  end

  describe "get_stats/1" do
    test "returns default stats for new template" do
      {:ok, template} = Template.new(%{
        name: "Stats Template",
        content: "Content {{var}}",
        variables: [%{name: "var", type: :string, required: true}]
      })

      stats = Template.get_stats(template)

      assert stats.usage_count == 0
      assert stats.success_rate == 0.0
      assert stats.avg_tokens == 0
      assert stats.error_count == 0
      assert is_nil(stats.last_used)
    end

    test "returns custom stats from metadata" do
      {:ok, template} = Template.new(%{
        name: "Stats Template",
        content: "Content {{var}}",
        variables: [%{name: "var", type: :string, required: true}],
        metadata: %{
          usage_count: 50,
          success_rate: 0.96,
          avg_tokens: 25,
          error_count: 2,
          last_used: ~U[2024-01-01 12:00:00Z]
        }
      })

      stats = Template.get_stats(template)

      assert stats.usage_count == 50
      assert stats.success_rate == 0.96
      assert stats.avg_tokens == 25
      assert stats.error_count == 2
      assert stats.last_used == ~U[2024-01-01 12:00:00Z]
    end
  end

  describe "validation" do
    test "validates required fields" do
      template = %Template{
        name: nil,
        content: "Some content",
        variables: []
      }

      {:error, reason} = Template.validate(template)
      assert String.contains?(reason, "Template name is required")
    end

    test "validates variable definitions" do
      template = %Template{
        name: "Test",
        content: "Hello {{name}}!",
        variables: [
          %{name: "name", type: :invalid_type, required: true}
        ]
      }

      {:error, reason} = Template.validate(template)
      assert String.contains?(reason, "Invalid variable type")
    end

    test "validates content variables match definitions" do
      template = %Template{
        name: "Test",
        content: "Hello {{name}} and {{missing}}!",
        variables: [
          %{name: "name", type: :string, required: true}
        ]
      }

      {:error, reason} = Template.validate(template)
      assert String.contains?(reason, "Undefined variables")
      assert String.contains?(reason, "missing")
    end

    test "passes validation for valid template" do
      template = %Template{
        name: "Valid Template",
        content: "Hello {{name}}!",
        variables: [
          %{name: "name", type: :string, required: true}
        ]
      }

      {:ok, validated_template} = Template.validate(template)
      assert validated_template == template
    end
  end

  describe "variable validation" do
    test "accepts valid variable definitions" do
      valid_variables = [
        %{name: "string_var", type: :string, required: true, description: "A string"},
        %{name: "int_var", type: :integer, required: false, description: "An integer"},
        %{name: "float_var", type: :float, required: true, description: "A float"},
        %{name: "bool_var", type: :boolean, required: false, description: "A boolean"},
        %{name: "list_var", type: :list, required: true, description: "A list"},
        %{name: "map_var", type: :map, required: false, description: "A map"}
      ]

      attrs = %{
        name: "Variable Test Template",
        content: "{{string_var}} {{int_var}} {{float_var}} {{bool_var}} {{list_var}} {{map_var}}",
        variables: valid_variables
      }

      {:ok, template} = Template.new(attrs)
      assert length(template.variables) == 6
    end

    test "rejects invalid variable definitions" do
      invalid_variables = [
        %{name: "bad_var", type: :invalid_type, required: true}
      ]

      attrs = %{
        name: "Invalid Variable Template",
        content: "{{bad_var}}",
        variables: invalid_variables
      }

      {:error, reason} = Template.new(attrs)
      assert String.contains?(reason, "Invalid variable type")
    end
  end

  describe "version management" do
    test "increments patch version on update" do
      {:ok, template} = Template.new(%{
        name: "Version Test",
        content: "Original {{var}}",
        variables: [%{name: "var", type: :string, required: true}],
        version: "2.1.3"
      })

      {:ok, updated_template} = Template.update(template, %{
        description: "Updated description"
      })

      assert updated_template.version == "2.1.4"
    end

    test "handles non-semver versions" do
      {:ok, template} = Template.new(%{
        name: "Version Test",
        content: "Original {{var}}",
        variables: [%{name: "var", type: :string, required: true}],
        version: "custom"
      })

      {:ok, updated_template} = Template.update(template, %{
        description: "Updated description"
      })

      assert updated_template.version == "custom.1"
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      {:error, reason} = Template.new(%{
        name: "Empty Content",
        content: "",
        variables: []
      })

      assert String.contains?(reason, "Template content is required")
    end

    test "handles complex variable patterns" do
      content = """
      Multi-line template with {{var1}} and 
      {{var2}} on different lines.
      Even {{var1}} repeated multiple times.
      """

      variables = Template.extract_variables(content)
      assert variables == ["var1", "var2"]
    end

    test "handles special characters in variable names" do
      # Note: This tests the current implementation
      # In production, might want to restrict variable name patterns
      content = "{{var_with_underscore}} and {{var-with-dash}}"
      
      variables = Template.extract_variables(content)
      assert variables == ["var_with_underscore", "var-with-dash"]
    end
  end
end