defmodule RubberDuck.Agents.Prompt.BuilderTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Agents.Prompt.{Template, Builder}

  describe "build/3" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Greeting Template",
        content: "Hello {{name}}, welcome to {{platform}}!",
        variables: [
          %{name: "name", type: :string, required: true, description: "User name"},
          %{name: "platform", type: :string, required: true, description: "Platform name"}
        ]
      })

      %{template: template}
    end

    test "builds prompt with valid context", %{template: template} do
      context = %{
        context: %{
          "name" => "Alice",
          "platform" => "RubberDuck"
        }
      }

      {:ok, result} = Builder.build(template, context)

      assert result == "Hello Alice, welcome to RubberDuck!"
    end

    test "includes metadata when requested", %{template: template} do
      context = %{
        provider: :openai,
        model: "gpt-4",
        context: %{
          "name" => "Alice",
          "platform" => "RubberDuck"
        }
      }

      opts = %{include_metadata: true}

      {:ok, result} = Builder.build(template, context, opts)

      assert is_map(result)
      assert Map.has_key?(result, :content)
      assert Map.has_key?(result, :metadata)
      assert result.content == "Hello Alice, welcome to RubberDuck!"
      assert result.metadata.template_id == template.id
      assert result.metadata.provider == :openai
      assert result.metadata.model == "gpt-4"
    end

    test "fails with missing required variables", %{template: template} do
      context = %{
        context: %{
          "name" => "Alice"
          # Missing "platform"
        }
      }

      {:error, reason} = Builder.build(template, context)
      assert String.contains?(reason, "Missing required variables")
      assert String.contains?(reason, "platform")
    end

    test "handles default values", %{} do
      {:ok, template} = Template.new(%{
        name: "Default Template",
        content: "Hello {{name|World}}!",
        variables: [
          %{name: "name", type: :string, required: false, default: "World"}
        ]
      })

      context = %{context: %{}}

      {:ok, result} = Builder.build(template, context)
      assert result == "Hello World!"
    end

    test "validates variable types in strict mode", %{} do
      {:ok, template} = Template.new(%{
        name: "Type Template",
        content: "Count: {{count}}",
        variables: [
          %{name: "count", type: :integer, required: true}
        ]
      })

      context = %{
        context: %{
          "count" => "not_an_integer"
        }
      }

      opts = %{strict_validation: true}

      {:error, reason} = Builder.build(template, context, opts)
      assert String.contains?(reason, "Invalid type for variable count")
    end

    test "skips type validation in non-strict mode", %{} do
      {:ok, template} = Template.new(%{
        name: "Type Template",
        content: "Count: {{count}}",
        variables: [
          %{name: "count", type: :integer, required: true}
        ]
      })

      context = %{
        context: %{
          "count" => "not_an_integer"
        }
      }

      opts = %{strict_validation: false}

      {:ok, result} = Builder.build(template, context, opts)
      assert result == "Count: not_an_integer"
    end
  end

  describe "variable substitution" do
    test "handles simple substitution" do
      {:ok, template} = Template.new(%{
        name: "Simple Template",
        content: "The {{animal}} jumps over the {{object}}.",
        variables: [
          %{name: "animal", type: :string, required: true},
          %{name: "object", type: :string, required: true}
        ]
      })

      context = %{
        context: %{
          "animal" => "cat",
          "object" => "fence"
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "The cat jumps over the fence."
    end

    test "handles nested variable access" do
      {:ok, template} = Template.new(%{
        name: "Nested Template",
        content: "Hello {{user.name}} from {{user.location}}!",
        variables: [
          %{name: "user.name", type: :string, required: true},
          %{name: "user.location", type: :string, required: true}
        ]
      })

      context = %{
        context: %{
          "user" => %{
            "name" => "Alice",
            "location" => "Wonderland"
          }
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "Hello Alice from Wonderland!"
    end

    test "handles default values with pipe syntax" do
      {:ok, template} = Template.new(%{
        name: "Default Template",
        content: "Hello {{name|Anonymous}} and {{title|Guest}}!",
        variables: [
          %{name: "name", type: :string, required: false},
          %{name: "title", type: :string, required: false}
        ]
      })

      context = %{
        context: %{
          "name" => "Alice"
          # Missing "title", should use default
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "Hello Alice and Guest!"
    end

    test "converts non-string values to strings" do
      {:ok, template} = Template.new(%{
        name: "Mixed Types Template",
        content: "Count: {{count}}, Active: {{active}}, Price: {{price}}",
        variables: [
          %{name: "count", type: :integer, required: true},
          %{name: "active", type: :boolean, required: true},
          %{name: "price", type: :float, required: true}
        ]
      })

      context = %{
        context: %{
          "count" => 42,
          "active" => true,
          "price" => 19.99
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "Count: 42, Active: true, Price: 19.99"
    end
  end

  describe "conditional logic" do
    test "handles if statements" do
      {:ok, template} = Template.new(%{
        name: "Conditional Template",
        content: "Hello{{%if premium%}} Premium{{%endif%}} User!",
        variables: [
          %{name: "premium", type: :boolean, required: true}
        ]
      })

      # Test with premium = true
      context = %{context: %{"premium" => true}}
      {:ok, result} = Builder.build(template, context)
      assert result == "Hello Premium User!"

      # Test with premium = false
      context = %{context: %{"premium" => false}}
      {:ok, result} = Builder.build(template, context)
      assert result == "Hello User!"
    end

    test "handles unless statements" do
      {:ok, template} = Template.new(%{
        name: "Unless Template",
        content: "{{%unless guest%}}Welcome back!{{%endunless%}}{{%if guest%}}Welcome, new user!{{%endif%}}",
        variables: [
          %{name: "guest", type: :boolean, required: true}
        ]
      })

      # Test with guest = false
      context = %{context: %{"guest" => false}}
      {:ok, result} = Builder.build(template, context)
      assert result == "Welcome back!"

      # Test with guest = true
      context = %{context: %{"guest" => true}}
      {:ok, result} = Builder.build(template, context)
      assert result == "Welcome, new user!"
    end

    test "handles for loops" do
      {:ok, template} = Template.new(%{
        name: "Loop Template",
        content: "Items: {%for item in items%}{{item}} {%endfor%}",
        variables: [
          %{name: "items", type: :list, required: true}
        ]
      })

      context = %{
        context: %{
          "items" => ["apple", "banana", "cherry"]
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "Items: apple banana cherry "
    end

    test "handles empty lists in for loops" do
      {:ok, template} = Template.new(%{
        name: "Empty Loop Template",
        content: "Items: {%for item in items%}{{item}} {%endfor%}Done.",
        variables: [
          %{name: "items", type: :list, required: true}
        ]
      })

      context = %{
        context: %{
          "items" => []
        }
      }

      {:ok, result} = Builder.build(template, context)
      assert result == "Items: Done."
    end

    test "evaluates conditions with comparison operators" do
      {:ok, template} = Template.new(%{
        name: "Comparison Template",
        content: "{%if status == \"active\"%}System is running{%endif%}{%if status != \"active\"%}System is down{%endif%}",
        variables: [
          %{name: "status", type: :string, required: true}
        ]
      })

      # Test equality
      context = %{context: %{"status" => "active"}}
      {:ok, result} = Builder.build(template, context)
      assert result == "System is running"

      # Test inequality
      context = %{context: %{"status" => "inactive"}}
      {:ok, result} = Builder.build(template, context)
      assert result == "System is down"
    end
  end

  describe "provider-specific formatting" do
    setup do
      {:ok, template} = Template.new(%{
        name: "Provider Template",
        content: "Analyze this: {{input}}",
        variables: [
          %{name: "input", type: :string, required: true}
        ]
      })

      %{template: template}
    end

    test "formats for OpenAI", %{template: template} do
      context = %{
        provider: :openai,
        context: %{"input" => "test data"}
      }

      opts = %{format_for_provider: true}

      {:ok, result} = Builder.build(template, context, opts)
      # Basic test - in production would have more specific formatting
      assert is_binary(result)
      assert String.contains?(result, "test data")
    end

    test "formats for Anthropic", %{template: template} do
      context = %{
        provider: :anthropic,
        context: %{"input" => "test data"}
      }

      opts = %{format_for_provider: true}

      {:ok, result} = Builder.build(template, context, opts)
      assert is_binary(result)
      assert String.contains?(result, "test data")
    end

    test "skips formatting when disabled", %{template: template} do
      context = %{
        provider: :openai,
        context: %{"input" => "test data"}
      }

      opts = %{format_for_provider: false}

      {:ok, result} = Builder.build(template, context, opts)
      assert result == "Analyze this: test data"
    end
  end

  describe "token optimization" do
    test "removes excessive whitespace" do
      {:ok, template} = Template.new(%{
        name: "Whitespace Template",
        content: "This    has     lots\n\n\n\nof   whitespace   {{var}}",
        variables: [
          %{name: "var", type: :string, required: true}
        ]
      })

      context = %{
        context: %{"var" => "here"}
      }

      opts = %{optimize_tokens: true}

      {:ok, result} = Builder.build(template, context, opts)
      
      # Should compress multiple spaces and newlines
      refute String.contains?(result, "    ")
      refute String.contains?(result, "\n\n\n")
      assert String.contains?(result, "here")
    end

    test "truncates content when over token limit" do
      long_content = String.duplicate("word ", 1000)
      
      {:ok, template} = Template.new(%{
        name: "Long Template",
        content: "#{long_content} {{var}}",
        variables: [
          %{name: "var", type: :string, required: true}
        ]
      })

      context = %{
        max_tokens: 100,
        context: %{"var" => "end"}
      }

      opts = %{optimize_tokens: true}

      {:ok, result} = Builder.build(template, context, opts)
      
      # Should be truncated
      assert String.length(result) < String.length(long_content)
      assert String.ends_with?(result, "...")
    end

    test "skips optimization when disabled" do
      {:ok, template} = Template.new(%{
        name: "Whitespace Template",
        content: "This    has     excessive   whitespace",
        variables: []
      })

      context = %{context: %{}}
      opts = %{optimize_tokens: false}

      {:ok, result} = Builder.build(template, context, opts)
      
      # Should preserve original whitespace
      assert String.contains?(result, "    ")
      assert String.contains?(result, "     ")
    end
  end

  describe "token estimation" do
    test "estimates tokens for content" do
      content = "This is a test prompt with some content."
      
      {:ok, tokens} = Builder.estimate_tokens(content, :openai)
      
      assert is_integer(tokens)
      assert tokens > 0
      # Rough estimate: should be around 10 tokens for this content
      assert tokens >= 8 and tokens <= 15
    end

    test "estimates differently for different providers" do
      content = "Same content for different providers."
      
      {:ok, openai_tokens} = Builder.estimate_tokens(content, :openai)
      {:ok, anthropic_tokens} = Builder.estimate_tokens(content, :anthropic)
      {:ok, local_tokens} = Builder.estimate_tokens(content, :local)
      
      assert is_integer(openai_tokens)
      assert is_integer(anthropic_tokens)
      assert is_integer(local_tokens)
      
      # Local models might be less efficient
      assert local_tokens >= openai_tokens
    end

    test "handles empty content" do
      {:ok, tokens} = Builder.estimate_tokens("", :openai)
      assert tokens == 0
    end
  end

  describe "context validation" do
    test "validates required variables" do
      {:ok, template} = Template.new(%{
        name: "Required Template",
        content: "{{required_var}} and {{optional_var|default}}",
        variables: [
          %{name: "required_var", type: :string, required: true},
          %{name: "optional_var", type: :string, required: false, default: "default"}
        ]
      })

      context = %{context: %{}}  # Missing required_var
      opts = %{strict_validation: true}

      {:error, reason} = Builder.validate_context(template, context, opts)
      assert String.contains?(reason, "Missing required variables")
      assert String.contains?(reason, "required_var")
    end

    test "validates variable types" do
      {:ok, template} = Template.new(%{
        name: "Type Template",
        content: "{{number_var}}",
        variables: [
          %{name: "number_var", type: :integer, required: true}
        ]
      })

      context = %{context: %{"number_var" => "not_a_number"}}
      opts = %{strict_validation: true}

      {:error, reason} = Builder.validate_context(template, context, opts)
      assert String.contains?(reason, "Invalid type for variable")
      assert String.contains?(reason, "number_var")
    end

    test "passes validation with correct types" do
      {:ok, template} = Template.new(%{
        name: "Valid Template",
        content: "{{str}} {{num}} {{bool}}",
        variables: [
          %{name: "str", type: :string, required: true},
          %{name: "num", type: :integer, required: true},
          %{name: "bool", type: :boolean, required: true}
        ]
      })

      context = %{
        context: %{
          "str" => "hello",
          "num" => 42,
          "bool" => true
        }
      }
      
      opts = %{strict_validation: true}

      {:ok, validated_context} = Builder.validate_context(template, context, opts)
      assert Map.has_key?(validated_context, :validated_vars)
    end
  end

  describe "error handling" do
    test "handles malformed template content gracefully" do
      {:ok, template} = Template.new(%{
        name: "Malformed Template",
        content: "{{unclosed_var and normal {{var}}",
        variables: [
          %{name: "var", type: :string, required: true}
        ]
      })

      context = %{context: %{"var" => "value"}}

      # Should not crash, but may not substitute unclosed variable
      {:ok, result} = Builder.build(template, context)
      assert String.contains?(result, "value")
    end

    test "handles missing context gracefully" do
      {:ok, template} = Template.new(%{
        name: "No Context Template",
        content: "No variables here",
        variables: []
      })

      # Empty context should work fine
      {:ok, result} = Builder.build(template, %{})
      assert result == "No variables here"
    end

    test "provides helpful error messages" do
      {:ok, template} = Template.new(%{
        name: "Error Template",
        content: "{{missing_var}}",
        variables: [
          %{name: "other_var", type: :string, required: true}
        ]
      })

      context = %{context: %{}}

      {:error, reason} = Builder.build(template, context)
      
      # Should mention both the undefined variable and missing required variable
      assert is_binary(reason)
      assert String.length(reason) > 0
    end
  end
end