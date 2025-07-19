defmodule RubberDuck.Instructions.SecurityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Instructions.{Security, SecurityError}

  describe "validate_template/2" do
    test "accepts safe templates" do
      safe_templates = [
        "Hello {{ name }}",
        "{% if user.admin %}Admin panel{% endif %}",
        "{% for item in items %}{{ item.name }}{% endfor %}",
        "{{ items | join: ', ' }}",
        "# Welcome {{ user.name }}\n\nYour score: {{ score }}"
      ]

      for template <- safe_templates do
        assert :ok = Security.validate_template(template)
      end
    end

    test "rejects templates that are too large" do
      large_template = String.duplicate("x", 60_000)

      assert {:error, %SecurityError{reason: :template_too_large}} =
               Security.validate_template(large_template)
    end

    test "rejects dangerous patterns" do
      dangerous_templates = [
        "{{ System.cmd('rm', ['-rf', '/']) }}",
        "{{ File.read('/etc/passwd') }}",
        "{{ IO.inspect(data) }}",
        "{{ Code.eval_string('System.halt()') }}",
        "{{ Kernel.apply(System, :halt, []) }}",
        "{{ Process.exit(self(), :kill) }}"
      ]

      for template <- dangerous_templates do
        assert {:error, %SecurityError{reason: :injection_attempt}} =
                 Security.validate_template(template)
      end
    end

    test "rejects excessive nesting" do
      nested_template = String.duplicate("{% if true %}", 15) <> "content" <> String.duplicate("{% endif %}", 15)

      assert {:error, %SecurityError{reason: :excessive_nesting}} =
               Security.validate_template(nested_template)
    end

    test "rejects suspicious variable names" do
      suspicious_templates = [
        "{{ system }}",
        "{{ file }}",
        "{{ eval }}",
        "{{ kernel }}",
        "{{ process }}"
      ]

      for template <- suspicious_templates do
        assert {:error, %SecurityError{reason: :injection_attempt}} =
                 Security.validate_template(template)
      end
    end
  end

  describe "validate_variables/1" do
    test "accepts safe variables" do
      safe_variables = %{
        "name" => "John Doe",
        "age" => 30,
        "admin" => false,
        "items" => ["apple", "banana", "cherry"],
        "config" => %{"theme" => "dark", "lang" => "en"}
      }

      assert :ok = Security.validate_variables(safe_variables)
    end

    test "rejects too many variables" do
      too_many_vars = 1..150 |> Enum.map(&{"var#{&1}", "value"}) |> Enum.into(%{})

      assert {:error, %SecurityError{reason: :too_many_variables}} =
               Security.validate_variables(too_many_vars)
    end

    test "rejects variables with dangerous content" do
      dangerous_variables = %{
        "name" => "{{ System.cmd('rm', ['-rf', '/']) }}",
        "script" => "<script>alert('xss')</script>",
        "large" => String.duplicate("x", 15_000)
      }

      assert {:error, %SecurityError{}} = Security.validate_variables(dangerous_variables)
    end

    test "rejects large lists" do
      large_list = 1..2000 |> Enum.to_list()

      assert {:error, %SecurityError{reason: :list_too_large}} =
               Security.validate_variables(%{"items" => large_list})
    end

    test "rejects large maps" do
      large_map = 1..200 |> Enum.map(&{"key#{&1}", "value"}) |> Enum.into(%{})

      assert {:error, %SecurityError{reason: :map_too_large}} =
               Security.validate_variables(%{"config" => large_map})
    end

    test "rejects invalid variable types" do
      invalid_variables = %{
        "function" => fn -> :ok end,
        "pid" => self(),
        "ref" => make_ref()
      }

      assert {:error, %SecurityError{reason: :invalid_value_type}} =
               Security.validate_variables(invalid_variables)
    end

    test "rejects non-map input" do
      assert {:error, :invalid_variables} = Security.validate_variables("not a map")
      assert {:error, :invalid_variables} = Security.validate_variables([:a, :b, :c])
    end
  end

  describe "validate_path/2" do
    test "accepts paths within allowed root" do
      allowed_root = "/tmp/templates"

      safe_paths = [
        "/tmp/templates/base.liquid",
        "/tmp/templates/partials/header.liquid",
        "/tmp/templates/layouts/main.liquid"
      ]

      for path <- safe_paths do
        assert :ok = Security.validate_path(path, allowed_root)
      end
    end

    test "rejects paths outside allowed root" do
      allowed_root = "/tmp/templates"

      dangerous_paths = [
        "/etc/passwd",
        "/tmp/other/file.liquid",
        "/home/user/secrets.txt"
      ]

      for path <- dangerous_paths do
        assert {:error, %SecurityError{reason: :path_traversal}} =
                 Security.validate_path(path, allowed_root)
      end
    end

    test "handles relative paths correctly" do
      allowed_root = "/tmp/templates"

      # These should resolve to paths outside the allowed root
      dangerous_paths = [
        "/tmp/templates/../../../etc/passwd",
        "/tmp/templates/../other/file.liquid"
      ]

      for path <- dangerous_paths do
        assert {:error, %SecurityError{reason: :path_traversal}} =
                 Security.validate_path(path, allowed_root)
      end
    end
  end

  describe "validate_include_path/1" do
    test "accepts safe include paths" do
      safe_paths = [
        "header.liquid",
        "partials/nav.liquid",
        "layouts/base.liquid"
      ]

      for path <- safe_paths do
        assert :ok = Security.validate_include_path(path)
      end
    end

    test "rejects path traversal attempts" do
      dangerous_paths = [
        "../../../etc/passwd",
        "../../secrets.txt",
        "~/private/data.liquid"
      ]

      for path <- dangerous_paths do
        assert {:error, %SecurityError{reason: :path_traversal}} =
                 Security.validate_include_path(path)
      end
    end

    test "rejects absolute paths" do
      absolute_paths = [
        "/etc/passwd",
        "/tmp/file.liquid",
        "/home/user/template.liquid"
      ]

      for path <- absolute_paths do
        assert {:error, %SecurityError{reason: :unauthorized_access}} =
                 Security.validate_include_path(path)
      end
    end
  end

  describe "sanitize_path/1" do
    test "removes dangerous characters" do
      dangerous_path = "../../../etc/passwd"
      sanitized = Security.sanitize_path(dangerous_path)

      refute String.contains?(sanitized, "..")
      refute String.starts_with?(sanitized, "/")
    end

    test "preserves safe characters" do
      safe_path = "templates/base.liquid"
      sanitized = Security.sanitize_path(safe_path)

      assert sanitized == "templates/base.liquid"
    end

    test "handles complex paths" do
      complex_path = "/../templates/./header.liquid"
      sanitized = Security.sanitize_path(complex_path)

      assert sanitized == "templates/header.liquid"
    end
  end

  describe "sandbox_context/1" do
    test "includes safe functions" do
      variables = %{"name" => "test", "items" => ["a", "b", "c"]}
      context = Security.sandbox_context(variables)

      assert context["name"] == "test"
      assert context["items"] == ["a", "b", "c"]
      assert is_function(context["upcase"])
      assert is_function(context["join"])
      assert is_function(context["now"])
    end

    test "provides string manipulation functions" do
      context = Security.sandbox_context(%{})

      assert context["upcase"].("hello") == "HELLO"
      assert context["downcase"].("HELLO") == "hello"
      assert context["trim"].("  hello  ") == "hello"
      assert context["length"].("hello") == 5
    end

    test "provides list manipulation functions" do
      context = Security.sandbox_context(%{})

      assert context["join"].(["a", "b", "c"], ", ") == "a, b, c"
      assert context["count"].(["a", "b", "c"]) == 3
    end

    test "provides safe date/time functions" do
      context = Security.sandbox_context(%{})

      now = context["now"].()
      today = context["today"].()

      assert is_binary(now)
      assert is_binary(today)
      # ISO 8601 format
      assert String.contains?(now, "T")
      assert String.match?(today, ~r/\d{4}-\d{2}-\d{2}/)
    end

    test "merges with provided variables" do
      variables = %{"custom" => "value"}
      context = Security.sandbox_context(variables)

      assert context["custom"] == "value"
      assert is_function(context["upcase"])
    end
  end

  describe "integration with various input types" do
    test "handles nested data structures" do
      nested_data = %{
        "user" => %{
          "profile" => %{
            "name" => "John Doe",
            "preferences" => ["dark_mode", "notifications"],
            "settings" => %{
              "language" => "en",
              "timezone" => "UTC"
            }
          }
        }
      }

      assert :ok = Security.validate_variables(nested_data)
    end

    test "handles mixed data types" do
      mixed_data = %{
        "string" => "hello",
        "number" => 42,
        "float" => 3.14,
        "boolean" => true,
        "nil" => nil,
        "list" => [1, 2, 3],
        "map" => %{"key" => "value"}
      }

      assert :ok = Security.validate_variables(mixed_data)
    end

    test "validates complex templates" do
      complex_template = """
      {% for user in users %}
        {% if user.active %}
          <div class="user">
            <h3>{{ user.name | upcase }}</h3>
            <p>{{ user.bio | truncate: 100 }}</p>
            {% if user.admin %}
              <span class="admin-badge">Admin</span>
            {% endif %}
          </div>
        {% endif %}
      {% endfor %}
      """

      assert :ok = Security.validate_template(complex_template)
    end
  end
end
