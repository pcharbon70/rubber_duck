defmodule RubberDuck.Instructions.TemplateProcessorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Instructions.{TemplateProcessor, TemplateError, SecurityError}

  describe "process_template/3" do
    test "processes simple variable substitution" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}

      assert {:ok, result} = TemplateProcessor.process_template(template, variables)
      assert result =~ "Hello World"
    end

    test "processes conditional logic" do
      template = "{% if admin %}Secret{% endif %}"

      assert {:ok, result} = TemplateProcessor.process_template(template, %{"admin" => true})
      assert result =~ "Secret"

      assert {:ok, result} = TemplateProcessor.process_template(template, %{"admin" => false})
      refute result =~ "Secret"
    end

    test "processes loops" do
      template = "{% for item in items %}{{ item }}{% endfor %}"
      variables = %{"items" => ["a", "b", "c"]}

      assert {:ok, result} = TemplateProcessor.process_template(template, variables)
      assert result =~ "abc"
    end

    test "converts to markdown by default" do
      template = "# Hello {{ name }}"
      variables = %{"name" => "World"}

      assert {:ok, result} = TemplateProcessor.process_template(template, variables)
      assert result =~ "<h1>"
      assert result =~ "Hello World"
    end

    test "skips markdown conversion when disabled" do
      template = "# Hello {{ name }}"
      variables = %{"name" => "World"}

      assert {:ok, result} = TemplateProcessor.process_template(template, variables, markdown: false)
      assert result == "# Hello World"
    end

    test "validates template by default" do
      # Exceeds max size
      template = String.duplicate("x", 60_000)

      assert {:error, _} = TemplateProcessor.process_template(template, %{})
    end

    test "skips validation when disabled" do
      # Exceeds max size
      template = String.duplicate("x", 60_000)

      assert {:ok, _} = TemplateProcessor.process_template(template, %{}, validate: false)
    end
  end

  describe "process_template_with_inheritance/4" do
    test "processes template with includes" do
      template = "Hello {% include \"greeting.liquid\" %}"
      variables = %{"name" => "World"}

      loader = fn "greeting.liquid" -> {:ok, "{{ name }}"} end

      assert {:ok, result} =
               TemplateProcessor.process_template_with_inheritance(
                 template,
                 variables,
                 loader
               )

      assert result =~ "Hello World"
    end

    test "processes template with extends" do
      template = "{% extends \"base.liquid\" %}{% block content %}Hello {{ name }}{% endblock %}"
      variables = %{"name" => "World"}

      loader = fn "base.liquid" ->
        {:ok, "<!DOCTYPE html><html><body>{% block content %}{% endblock %}</body></html>"}
      end

      assert {:ok, result} =
               TemplateProcessor.process_template_with_inheritance(
                 template,
                 variables,
                 loader,
                 # Disable markdown to prevent HTML escaping
                 markdown: false
               )

      assert result =~ "Hello World"
      assert result =~ "<!DOCTYPE html>"
    end

    test "handles loader errors" do
      template = "{% include \"missing.liquid\" %}"

      loader = fn _ -> {:error, :not_found} end

      assert {:error, _} =
               TemplateProcessor.process_template_with_inheritance(
                 template,
                 %{},
                 loader
               )
    end
  end

  describe "validate_template/2" do
    test "validates user templates with Solid" do
      template = "Hello {{ name }}"

      assert {:ok, _} = TemplateProcessor.validate_template(template, :user)
    end

    test "validates system templates with EEx" do
      template = "Hello <%= name %>"

      # System templates require environment variable
      System.put_env("ALLOW_SYSTEM_TEMPLATES", "true")

      assert {:ok, _} = TemplateProcessor.validate_template(template, :system)

      System.delete_env("ALLOW_SYSTEM_TEMPLATES")
    end

    test "rejects invalid template types" do
      template = "Hello {{ name }}"

      assert {:error, {:invalid_template_type, :unknown}} =
               TemplateProcessor.validate_template(template, :unknown)
    end

    test "detects Solid syntax errors" do
      # Missing closing brace
      template = "Hello {{ name"

      assert {:error, {:parse_error, _}} = TemplateProcessor.validate_template(template, :user)
    end

    test "detects EEx syntax errors" do
      # Missing closing tag
      template = "Hello <%= name"

      System.put_env("ALLOW_SYSTEM_TEMPLATES", "true")

      assert {:error, {:parse_error, _}} = TemplateProcessor.validate_template(template, :system)

      System.delete_env("ALLOW_SYSTEM_TEMPLATES")
    end
  end

  describe "extract_metadata/1" do
    test "extracts YAML frontmatter" do
      template = """
      ---
      title: Test Template
      priority: high
      ---
      Hello {{ name }}
      """

      assert {:ok, metadata, content} = TemplateProcessor.extract_metadata(template)
      assert metadata["title"] == "Test Template"
      assert metadata["priority"] == "high"
      assert content =~ "Hello {{ name }}"
    end

    test "handles template without frontmatter" do
      template = "Hello {{ name }}"

      assert {:ok, metadata, content} = TemplateProcessor.extract_metadata(template)
      assert metadata == %{}
      assert content == template
    end

    test "validates metadata format" do
      template = """
      ---
      title: Test Template
      priority: high
      tags: [security, auth]
      ---
      Hello {{ name }}
      """

      assert {:ok, metadata, _} = TemplateProcessor.extract_metadata(template)
      assert metadata["title"] == "Test Template"
      assert metadata["priority"] == "high"
      assert metadata["tags"] == ["security", "auth"]
    end

    test "rejects invalid YAML" do
      template = """
      ---
      title: Test Template
      invalid: [unclosed
      ---
      Hello {{ name }}
      """

      assert {:error, {:yaml_parse_error, _}} = TemplateProcessor.extract_metadata(template)
    end

    test "rejects invalid frontmatter format" do
      template = """
      ---
      title: Test Template
      ---
      Some content
      ---
      More content
      """

      assert {:error, :invalid_frontmatter_format} = TemplateProcessor.extract_metadata(template)
    end
  end

  describe "build_standard_context/1" do
    test "includes standard variables" do
      context = TemplateProcessor.build_standard_context()

      assert context["timestamp"]
      assert context["date"]
      assert context["env"]
    end

    test "merges custom variables" do
      custom = %{name: "test", value: 42}
      context = TemplateProcessor.build_standard_context(custom)

      assert context["name"] == "test"
      assert context["value"] == 42
      assert context["timestamp"]
    end

    test "converts atom keys to strings" do
      custom = %{name: "test", symbol: "value"}
      context = TemplateProcessor.build_standard_context(custom)

      assert context["name"] == "test"
      assert context["symbol"] == "value"
    end
  end

  describe "security features" do
    test "rejects templates that are too large" do
      template = String.duplicate("x", 60_000)

      assert {:error, _} = TemplateProcessor.process_template(template, %{})
    end

    test "rejects dangerous patterns" do
      dangerous_templates = [
        "{{ System.cmd('rm', ['-rf', '/']) }}",
        "{{ File.read('/etc/passwd') }}",
        "{{ IO.inspect(System.get_env()) }}",
        "{{ Code.eval_string('System.halt()') }}"
      ]

      for template <- dangerous_templates do
        assert {:error, _} = TemplateProcessor.process_template(template, %{})
      end
    end

    test "validates variable content" do
      template = "Hello {{ name }}"
      dangerous_vars = %{"name" => "{{ System.cmd('rm', ['-rf', '/']) }}"}

      assert {:error, _} = TemplateProcessor.process_template(template, dangerous_vars)
    end

    test "limits variable count" do
      template = "Hello {{ name }}"
      too_many_vars = 1..200 |> Enum.map(&{"var#{&1}", "value"}) |> Enum.into(%{})

      assert {:error, _} = TemplateProcessor.process_template(template, too_many_vars)
    end

    test "limits variable value size" do
      template = "Hello {{ name }}"
      large_value = String.duplicate("x", 15_000)

      assert {:error, _} = TemplateProcessor.process_template(template, %{"name" => large_value})
    end
  end

  describe "error handling" do
    test "handles Solid rendering errors gracefully" do
      template = "{{ undefined_function() }}"

      assert {:error, {:template_error, _}} = TemplateProcessor.process_template(template, %{})
    end

    test "handles EEx rendering errors gracefully" do
      template = "<%= undefined_function() %>"

      System.put_env("ALLOW_SYSTEM_TEMPLATES", "true")

      assert {:error, {:render_error, _}} =
               TemplateProcessor.process_template(
                 template,
                 %{},
                 type: :system
               )

      System.delete_env("ALLOW_SYSTEM_TEMPLATES")
    end

    test "handles markdown conversion errors" do
      # Create a template that would cause markdown parsing issues
      template = "# Invalid\n\n```elixir\nunclosed code block"

      # The template should fail with markdown error
      assert {:error, {:markdown_error, _}} = TemplateProcessor.process_template(template, %{})
    end
  end

  describe "performance" do
    test "processes simple templates efficiently" do
      template = "Hello {{ name }}"
      variables = %{"name" => "World"}

      {time, {:ok, _}} =
        :timer.tc(fn ->
          TemplateProcessor.process_template(template, variables)
        end)

      # Should complete in under 100ms for simple templates
      assert time < 100_000
    end

    test "handles moderate template complexity" do
      template = """
      {% for user in users %}
        {% if user.active %}
          Hello {{ user.name }}!
          {% if user.admin %}
            You have admin access.
          {% endif %}
        {% endif %}
      {% endfor %}
      """

      variables = %{
        "users" => [
          %{"name" => "Alice", "active" => true, "admin" => true},
          %{"name" => "Bob", "active" => true, "admin" => false},
          %{"name" => "Charlie", "active" => false, "admin" => false}
        ]
      }

      {time, {:ok, result}} =
        :timer.tc(fn ->
          TemplateProcessor.process_template(template, variables)
        end)

      assert result =~ "Hello Alice!"
      assert result =~ "admin access"
      assert result =~ "Hello Bob!"
      refute result =~ "Charlie"

      # Should complete in under 100ms for moderate complexity
      assert time < 100_000
    end
  end
end
