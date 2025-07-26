defmodule RubberDuck.Engines.TestGeneration do
  @moduledoc """
  Test generation engine that creates comprehensive test suites for code.

  This engine generates:
  - Unit tests for individual functions
  - Edge case tests
  - Property-based tests
  - Integration tests
  - Test fixtures and mocks

  Supports multiple testing frameworks per language.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.LLM
  alias RubberDuck.Engine.InputValidator

  @impl true
  def init(config) do
    state = %{
      config: config,
      frameworks: load_test_frameworks()
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, analysis} <- analyze_code_for_testing(validated, state),
         {:ok, test_plan} <- create_test_plan(analysis, validated, state),
         {:ok, tests} <- generate_tests(test_plan, validated, state) do
      result = %{
        source_file: validated.file_path,
        test_file: suggested_test_file_path(validated),
        framework: validated.framework,
        tests: tests,
        coverage_estimate: estimate_coverage(tests, analysis)
      }

      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:test_generation, :test_framework_support, :edge_case_detection, :property_testing]
  end

  defp validate_input(%{file_path: path} = input) when is_binary(path) do
    case InputValidator.validate_llm_input(input, [:file_path]) do
      {:ok, validated} ->
        content = read_file_content(path)
        language = detect_language(path)
        
        validated = Map.merge(validated, %{
          content: content,
          language: language,
          framework: Map.get(input, :framework) || default_framework(language),
          include_edge_cases: Map.get(input, :include_edge_cases, true),
          include_property_tests: Map.get(input, :include_property_tests, false),
          output_file: Map.get(input, :output_file)
        })
        
        {:ok, validated}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp read_file_content(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".py" -> :python
      _ -> :unknown
    end
  end

  defp default_framework(:elixir), do: :exunit
  defp default_framework(:javascript), do: :jest
  defp default_framework(:python), do: :pytest
  defp default_framework(_), do: :unknown

  defp analyze_code_for_testing(input, _state) do
    analysis = %{
      module_name: extract_module_name(input.content, input.language),
      functions: extract_testable_functions(input.content, input.language),
      dependencies: extract_dependencies(input.content, input.language),
      complexity: analyze_complexity(input.content)
    }

    {:ok, analysis}
  end

  defp extract_module_name(content, :elixir) do
    case Regex.run(~r/defmodule\s+([\w.]+)/, content) do
      [_, module] -> module
      _ -> "UnknownModule"
    end
  end

  defp extract_module_name(_content, _language), do: "UnknownModule"

  defp extract_testable_functions(content, :elixir) do
    # Extract public functions
    ~r/def\s+(\w+)\((.*?)\).*?do(.*?)end/s
    |> Regex.scan(content)
    |> Enum.map(fn [_full, name, params, _body] ->
      %{
        name: name,
        params: parse_params(params),
        is_public: true,
        has_guard: String.contains?(params, "when"),
        # Would calculate actual complexity
        complexity: :medium
      }
    end)
  end

  defp extract_testable_functions(_content, _language), do: []

  defp parse_params(params_string) do
    params_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn param ->
      # Extract parameter name (before any default value or type)
      case String.split(param, ~r/\s*[=\\]\s*/) do
        [name | _] -> String.trim(name)
        _ -> param
      end
    end)
  end

  defp extract_dependencies(content, :elixir) do
    # Extract imports and aliases
    imports =
      Regex.scan(~r/(?:import|alias|use)\s+([\w.]+)/, content)
      |> Enum.map(&List.last/1)

    %{
      imports: imports,
      requires_mocking: detect_external_calls(content)
    }
  end

  defp extract_dependencies(_content, _language), do: %{imports: [], requires_mocking: false}

  defp detect_external_calls(content) do
    # Simple heuristic: check for common external call patterns
    String.contains?(content, ["HTTPoison", "Ecto.", "File.", "GenServer.call"])
  end

  defp analyze_complexity(content) do
    lines = String.split(content, "\n")

    %{
      total_lines: length(lines),
      has_conditionals: String.contains?(content, ["if", "case", "cond"]),
      has_recursion: detect_recursion(content),
      has_error_handling: String.contains?(content, ["try", "rescue", "catch"])
    }
  end

  defp detect_recursion(content) do
    # Simple recursion detection - function calling itself
    functions = Regex.scan(~r/def\s+(\w+)/, content) |> Enum.map(&List.last/1)

    Enum.any?(functions, fn func ->
      Regex.match?(~r/def\s+#{func}.*?#{func}\(/s, content)
    end)
  end

  defp create_test_plan(analysis, input, _state) do
    # Broadcast test plan creation
    conversation_id = input[:conversation_id] || input[:context][:conversation_id]
    if conversation_id do
      RubberDuck.Status.engine(
        conversation_id,
        "Creating test plan",
        %{
          engine: :test_generation,
          file_path: input.file_path,
          status: :planning
        }
      )
    end
    
    plan = %{
      test_cases: plan_test_cases(analysis.functions, input),
      fixtures_needed: plan_fixtures(analysis.dependencies),
      property_tests: if(input.include_property_tests, do: plan_property_tests(analysis.functions), else: []),
      integration_tests: plan_integration_tests(analysis)
    }

    {:ok, plan}
  end

  defp plan_test_cases(functions, input) do
    Enum.flat_map(functions, fn function ->
      base_cases = [
        %{
          type: :happy_path,
          function: function.name,
          description: "#{function.name} with valid inputs"
        }
      ]

      edge_cases =
        if input.include_edge_cases do
          [
            %{
              type: :edge_case,
              function: function.name,
              description: "#{function.name} with nil input"
            },
            %{
              type: :edge_case,
              function: function.name,
              description: "#{function.name} with empty input"
            }
          ]
        else
          []
        end

      base_cases ++ edge_cases
    end)
  end

  defp plan_fixtures(dependencies) do
    if dependencies.requires_mocking do
      [:mock_external_services]
    else
      []
    end
  end

  defp plan_property_tests(functions) do
    functions
    |> Enum.filter(fn f -> f.complexity != :simple end)
    |> Enum.map(fn f ->
      %{
        function: f.name,
        properties: ["idempotence", "invariants"]
      }
    end)
  end

  defp plan_integration_tests(analysis) do
    if length(analysis.functions) > 3 do
      [%{type: :integration, description: "Full module integration test"}]
    else
      []
    end
  end

  defp generate_tests(test_plan, input, state) do
    # Broadcast test generation start
    conversation_id = input[:conversation_id] || input[:context][:conversation_id]
    if conversation_id do
      RubberDuck.Status.engine(
        conversation_id,
        "Generating tests",
        %{
          engine: :test_generation,
          framework: input.framework,
          status: :generating
        }
      )
    end
    
    prompt = build_test_generation_prompt(test_plan, input)

    opts = [
      provider: input.provider,  # Required from input
      model: input.model,        # Required from input
      messages: [
        %{"role" => "system", "content" => get_test_system_prompt(input.language, input.framework)},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: input.temperature || 0.3,
      max_tokens: input.max_tokens || state.config[:max_tokens] || 4096,
      user_id: input.user_id
    ]

    # Broadcast LLM call
    if conversation_id do
      RubberDuck.Status.engine(
        conversation_id,
        "Calling LLM for test generation",
        %{
          engine: :test_generation,
          provider: input.provider,
          model: input.model,
          status: :llm_call
        }
      )
    end

    case LLM.Service.completion(opts) do
      {:ok, response} ->
        # Broadcast completion
        if conversation_id do
          RubberDuck.Status.engine(
            conversation_id,
            "Tests generated successfully",
            %{
              engine: :test_generation,
              status: :completed
            }
          )
        end
        
        parse_test_response(response, input)

      {:error, reason} ->
        Logger.warning("LLM test generation failed: #{inspect(reason)}")
        generate_fallback_tests(test_plan, input)
    end
  end

  defp build_test_generation_prompt(test_plan, input) do
    """
    Generate comprehensive tests for the following #{input.language} code using #{input.framework}:

    ```#{input.language}
    #{input.content}
    ```

    Test plan:
    #{format_test_plan(test_plan)}

    Requirements:
    - Generate tests for all public functions
    - Include assertions that verify correct behavior
    - Add descriptive test names
    - Include setup/teardown if needed
    #{if input.include_edge_cases, do: "- Include edge case tests", else: ""}
    #{if input.include_property_tests, do: "- Include property-based tests", else: ""}

    Use #{input.framework} testing conventions and best practices.
    """
  end

  defp format_test_plan(plan) do
    sections = []

    sections =
      if length(plan.test_cases) > 0 do
        cases =
          Enum.map(plan.test_cases, fn tc ->
            "  - #{tc.description}"
          end)
          |> Enum.join("\n")

        sections ++ ["Test cases:\n#{cases}"]
      else
        sections
      end

    sections =
      if length(plan.fixtures_needed) > 0 do
        sections ++ ["Fixtures needed: #{Enum.join(plan.fixtures_needed, ", ")}"]
      else
        sections
      end

    Enum.join(sections, "\n\n")
  end

  defp get_test_system_prompt(:elixir, :exunit) do
    """
    You are an expert Elixir developer writing ExUnit tests.
    Follow ExUnit conventions and best practices.
    Use descriptive test names with "test" macro.
    Include proper assertions with assert/refute.
    Use describe blocks to group related tests.
    """
  end

  defp get_test_system_prompt(:javascript, :jest) do
    """
    You are an expert JavaScript developer writing Jest tests.
    Follow Jest conventions and best practices.
    Use describe/it blocks for organization.
    Include expect assertions.
    Use beforeEach/afterEach for setup/teardown.
    """
  end

  defp get_test_system_prompt(:python, :pytest) do
    """
    You are an expert Python developer writing pytest tests.
    Follow pytest conventions and best practices.
    Use descriptive test function names starting with test_.
    Include assert statements.
    Use fixtures for setup when needed.
    """
  end

  defp get_test_system_prompt(_language, _framework) do
    "You are an expert developer writing comprehensive tests."
  end

  defp parse_test_response(response, input) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    # Extract test code
    test_code = extract_code_block(content, input.language)

    # Parse individual tests
    tests = parse_individual_tests(test_code, input.framework)

    {:ok,
     %{
       full_code: test_code,
       individual_tests: tests,
       setup_code: extract_setup_code(test_code, input.framework),
       imports: extract_test_imports(test_code, input.language)
     }}
  end

  defp extract_code_block(content, language) do
    case Regex.run(~r/```#{language}?\n(.*?)```/s, content) do
      [_, code] -> String.trim(code)
      _ -> content
    end
  end

  defp parse_individual_tests(code, :exunit) do
    ~r/test\s+"([^"]+)"\s+do(.*?)end/s
    |> Regex.scan(code)
    |> Enum.map(fn [_full, name, body] ->
      %{
        name: name,
        body: String.trim(body),
        type: categorize_test(name)
      }
    end)
  end

  defp parse_individual_tests(code, :jest) do
    ~r/it\(['"]([^'"]+)['"]/
    |> Regex.scan(code)
    |> Enum.map(fn [_full, name] ->
      %{
        name: name,
        type: categorize_test(name)
      }
    end)
  end

  defp parse_individual_tests(_code, _framework), do: []

  defp categorize_test(name) do
    cond do
      String.contains?(String.downcase(name), ["edge", "nil", "empty"]) -> :edge_case
      String.contains?(String.downcase(name), ["error", "invalid"]) -> :error_case
      String.contains?(String.downcase(name), "property") -> :property
      true -> :happy_path
    end
  end

  defp extract_setup_code(code, :exunit) do
    case Regex.run(~r/setup\s+do(.*?)end/s, code) do
      [_, setup] -> String.trim(setup)
      _ -> nil
    end
  end

  defp extract_setup_code(_code, _framework), do: nil

  defp extract_test_imports(code, :elixir) do
    ~r/(?:import|alias|use)\s+([\w.]+)/
    |> Regex.scan(code)
    |> Enum.map(&List.last/1)
  end

  defp extract_test_imports(_code, _language), do: []

  defp generate_fallback_tests(test_plan, input) do
    # Generate basic template tests
    template =
      case input.framework do
        :exunit -> generate_exunit_template(test_plan, input)
        :jest -> generate_jest_template(test_plan, input)
        :pytest -> generate_pytest_template(test_plan, input)
        _ -> "# Test generation not supported for this framework"
      end

    {:ok,
     %{
       full_code: template,
       individual_tests: [],
       setup_code: nil,
       imports: []
     }}
  end

  defp generate_exunit_template(_test_plan, input) do
    module_name = String.replace(Path.basename(input.file_path, ".ex"), ~r/[^A-Za-z0-9]/, "")

    """
    defmodule #{module_name}Test do
      use ExUnit.Case
      
      # Import the module under test
      # alias YourApp.#{module_name}
      
      describe "#{module_name}" do
        test "placeholder test" do
          assert true
        end
      end
    end
    """
  end

  defp generate_jest_template(_test_plan, _input) do
    """
    describe('Module', () => {
      it('should pass placeholder test', () => {
        expect(true).toBe(true);
      });
    });
    """
  end

  defp generate_pytest_template(_test_plan, _input) do
    """
    def test_placeholder():
        assert True
    """
  end

  defp suggested_test_file_path(input) do
    case input.language do
      :elixir ->
        input.file_path
        |> String.replace("/lib/", "/test/")
        |> String.replace(".ex", "_test.exs")

      :javascript ->
        String.replace(input.file_path, ".js", ".test.js")

      :python ->
        String.replace(input.file_path, ".py", "_test.py")

      _ ->
        input.file_path <> ".test"
    end
  end

  defp estimate_coverage(tests, analysis) do
    total_functions = length(analysis.functions)

    tested_functions =
      tests.individual_tests
      |> Enum.map(& &1.name)
      |> Enum.uniq()
      |> length()

    if total_functions > 0 do
      Float.round(tested_functions / total_functions * 100, 1)
    else
      0.0
    end
  end

  defp load_test_frameworks do
    %{
      elixir: [:exunit, :espec],
      javascript: [:jest, :mocha, :jasmine],
      python: [:pytest, :unittest, :nose]
    }
  end
end
