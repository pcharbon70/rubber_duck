defmodule RubberDuck.Commands.Handlers.Test do
  @moduledoc """
  Handler for test generation commands.
  
  Generates comprehensive tests for existing code using the generation engine
  with support for multiple test frameworks and edge cases.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.Engine.Manager

  @impl true
  def execute(%Command{name: :test, args: args, options: options} = command) do
    with :ok <- validate(command),
         {:ok, content} <- File.read(args.file),
         {:ok, tests} <- generate_tests(content, args.file, options) do
      handle_output(tests, args.file, options)
    end
  end

  def execute(_command) do
    {:error, "Invalid command for test handler"}
  end

  @impl true
  def validate(%Command{name: :test, args: args}) do
    with :ok <- Handler.validate_required_args(%{args: args}, [:file]),
         :ok <- Handler.validate_file_exists(args.file) do
      :ok
    end
  end
  
  def validate(_), do: {:error, "Invalid command for test handler"}

  # Private functions

  defp generate_tests(content, file_path, options) do
    framework = Map.get(options, :framework, "exunit")
    include_edge_cases = Map.get(options, :include_edge_cases, false)
    include_property_tests = Map.get(options, :include_property_tests, false)
    
    # Detect language from file extension
    language = detect_language(file_path)
    
    # Build prompt for test generation
    prompt = """
    Generate comprehensive tests for the following #{language} code using #{framework} framework.
    #{if include_edge_cases, do: "Include edge case tests.", else: ""}
    #{if include_property_tests, do: "Include property-based tests.", else: ""}
    
    Code to test:
    ```#{language}
    #{content}
    ```
    
    Please provide the test code without any explanations or markdown formatting.
    """
    
    input = %{
      prompt: prompt,
      language: language,
      context: %{
        current_file: file_path,
        framework: framework
      }
    }

    timeout = Map.get(options, :timeout, 300_000)

    case Manager.execute(:generation, input, timeout) do
      {:ok, %{code: test_code}} ->
        {:ok, test_code}
        
      {:error, :no_provider_available} ->
        # Fallback to template if no LLM is available
        module_name = extract_module_name(content, file_path)
        tests = generate_test_template(module_name, framework, include_edge_cases, include_property_tests)
        {:ok, tests}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      _ -> "unknown"
    end
  end

  defp extract_module_name(content, file_path) do
    case Regex.run(~r/defmodule\s+([A-Za-z0-9_.]+)/, content) do
      [_, module_name] -> module_name
      _ -> Path.basename(file_path, Path.extname(file_path)) |> Macro.camelize()
    end
  end

  defp generate_test_template(module_name, "exunit", include_edge_cases, include_property_tests) do
    edge_case_tests = if include_edge_cases, do: edge_case_template(), else: ""
    property_tests = if include_property_tests, do: property_test_template(), else: ""

    """
    defmodule #{module_name}Test do
      use ExUnit.Case
      doctest #{module_name}

      describe "#{module_name}" do
        test "basic functionality" do
          # TODO: Add test implementation
          assert true
        end
        #{edge_case_tests}
        #{property_tests}
      end
    end
    """
  end

  defp generate_test_template(module_name, framework, _, _) do
    "# Test framework '#{framework}' not yet implemented for #{module_name}"
  end

  defp edge_case_template do
    """
        test "handles edge cases" do
          # TODO: Add edge case tests
          assert true
        end
    """
  end

  defp property_test_template do
    """
        property "maintains invariants" do
          # TODO: Add property-based tests
          check all value <- term() do
            assert true
          end
        end
    """
  end

  defp handle_output(tests, file, options) do
    output_file = Map.get(options, :output)
    framework = Map.get(options, :framework, "exunit")
    
    if output_file do
      # Write to file
      case File.write(output_file, tests) do
        :ok ->
          {:ok, %{
            type: "test_generation",
            tests: tests,
            framework: framework,
            output_file: output_file,
            message: "Tests written to #{output_file}",
            timestamp: DateTime.utc_now()
          }}

        {:error, reason} ->
          {:error, "Failed to write output file: #{reason}"}
      end
    else
      # Return tests with suggested path
      suggested_path = suggest_test_file_path(file)

      {:ok, %{
        type: "test_generation",
        tests: tests,
        framework: framework,
        suggested_path: suggested_path,
        timestamp: DateTime.utc_now()
      }}
    end
  end

  defp suggest_test_file_path(source_file) do
    dir = Path.dirname(source_file)
    filename = Path.basename(source_file, Path.extname(source_file))

    # Try to determine if we're in lib/ and suggest test/ path
    suggested_dir =
      if String.contains?(dir, "/lib/") do
        String.replace(dir, "/lib/", "/test/")
      else
        Path.join("test", dir)
      end

    Path.join(suggested_dir, "#{filename}_test.exs")
  end
end