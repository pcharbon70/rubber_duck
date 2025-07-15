defmodule RubberDuck.Commands.Handlers.Generate do
  @moduledoc """
  Handler for code generation commands.
  
  Generates code from natural language descriptions using the generation engine.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.Engine.Manager
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.GenerationChain

  require Logger

  @impl true
  def execute(%Command{name: :generate, args: args, options: options} = command) do
    with :ok <- validate(command) do
      language = Map.get(options, :language, "elixir")
      
      # Build context for CoT
      cot_context = %{
        query: args.description,
        language: language,
        context: %{
          project_files: Map.get(command.context.metadata, :project_files, []),
          current_file: Map.get(command.context.metadata, :current_file),
          imports: Map.get(command.context.metadata, :imports, [])
        },
        similar_patterns: get_similar_patterns(command.context),
        available_libraries: get_available_libraries(language)
      }

      Logger.debug("Executing CoT generation chain with context: #{inspect(cot_context)}")

      # Execute CoT generation chain
      case ConversationManager.execute_chain(GenerationChain, args.description, cot_context) do
        {:ok, cot_session} ->
          generation_result = extract_generation_result(cot_session)
          
          {:ok, %{
            generated_code: generation_result.code,
            language: language,
            description: args.description,
            imports: generation_result.dependencies,
            documentation: generation_result.documentation,
            tests: generation_result.tests,
            alternatives: generation_result.alternatives,
            validation: generation_result.validation,
            timestamp: DateTime.utc_now()
          }}
        
        {:error, reason} ->
          Logger.error("CoT generation chain error: #{inspect(reason)}")
          Logger.warning("Falling back to engine-based generation")
          
          # Fallback to engine-based generation
          fallback_to_engine(args.description, language, command.context)
      end
    end
  end

  def execute(_command) do
    {:error, "Invalid command for generate handler"}
  end

  @impl true
  def validate(%Command{name: :generate, args: args}) do
    Handler.validate_required_args(%{args: args}, [:description])
  end
  
  def validate(_), do: {:error, "Invalid command for generate handler"}

  # Private functions

  defp extract_generation_result(cot_session) do
    # Extract results from the CoT session steps
    requirements = get_step_result(cot_session, :understand_requirements)
    _context_review = get_step_result(cot_session, :review_context)
    structure = get_step_result(cot_session, :plan_structure)
    dependencies = get_step_result(cot_session, :identify_dependencies)
    implementation = get_step_result(cot_session, :generate_implementation)
    documentation = get_step_result(cot_session, :add_documentation)
    tests = get_step_result(cot_session, :generate_tests)
    validation = get_step_result(cot_session, :validate_output)
    alternatives = get_step_result(cot_session, :provide_alternatives)
    
    %{
      code: extract_code(documentation || implementation),
      dependencies: parse_dependencies(dependencies),
      documentation: extract_documentation(documentation),
      tests: extract_tests(tests),
      alternatives: parse_alternatives(alternatives),
      validation: parse_validation(validation),
      structure: structure,
      requirements: requirements
    }
  end
  
  defp get_step_result(cot_session, step_name) do
    case Map.get(cot_session.steps, step_name) do
      %{result: result} -> result
      _ -> nil
    end
  end
  
  defp extract_code(text) when is_binary(text) do
    # Extract code blocks from the text
    case Regex.scan(~r/```(?:elixir|ex)?\n(.*?)```/s, text) do
      [[_, code] | _] -> String.trim(code)
      _ -> 
        # If no code block found, try to extract from the text
        text
        |> String.split("\n")
        |> Enum.drop_while(&(!String.starts_with?(&1, "defmodule") && !String.starts_with?(&1, "def ")))
        |> Enum.join("\n")
        |> String.trim()
    end
  end
  defp extract_code(_), do: ""
  
  defp parse_dependencies(deps_text) when is_binary(deps_text) do
    # Extract imports and dependencies
    imports = Regex.scan(~r/(?:import|alias|use|require)\s+([A-Z][\w.]+)/, deps_text)
    |> Enum.map(fn [_, module] -> module end)
    |> Enum.uniq()
    
    deps = Regex.scan(~r/{:(\w+),\s*"~> ([\d.]+)"}/, deps_text)
    |> Enum.map(fn [_, name, version] -> {name, version} end)
    
    %{imports: imports, dependencies: deps}
  end
  defp parse_dependencies(_), do: %{imports: [], dependencies: []}
  
  defp extract_documentation(doc_text) when is_binary(doc_text) do
    # Extract documentation sections
    doc_text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["@doc", "@moduledoc", "@spec"]))
    |> Enum.join("\n")
  end
  defp extract_documentation(_), do: ""
  
  defp extract_tests(tests_text) when is_binary(tests_text) do
    # Extract test code
    case Regex.scan(~r/```(?:elixir|ex)?\n(.*?)```/s, tests_text) do
      [_ | _] = codes ->
        codes
        |> Enum.map(fn [_, code] -> String.trim(code) end)
        |> Enum.join("\n\n")
      _ -> tests_text || ""
    end
  end
  defp extract_tests(_), do: ""
  
  defp parse_alternatives(alt_text) when is_binary(alt_text) do
    # Extract alternative approaches
    alt_text
    |> String.split(~r/\d+\./)
    |> Enum.drop(1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.length(&1) > 10))
  end
  defp parse_alternatives(_), do: []
  
  defp parse_validation(val_text) when is_binary(val_text) do
    # Extract validation results
    %{
      passed: !String.contains?(String.downcase(val_text || ""), ["error", "fail", "issue"]),
      checks: extract_validation_checks(val_text),
      warnings: extract_warnings(val_text)
    }
  end
  defp parse_validation(_), do: %{passed: true, checks: [], warnings: []}
  
  defp extract_validation_checks(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
    |> Enum.map(&String.replace(&1, ~r/^\d+\.\s*/, ""))
  end
  defp extract_validation_checks(_), do: []
  
  defp extract_warnings(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(String.downcase(&1), ["warning", "note", "caution"]))
    |> Enum.map(&String.trim/1)
  end
  defp extract_warnings(_), do: []
  
  defp get_similar_patterns(context) do
    # Extract similar code patterns from the context
    Map.get(context.metadata, :similar_code_patterns, [])
  end
  
  defp get_available_libraries(language) do
    # Return common libraries for the language
    case language do
      "elixir" -> ["Enum", "GenServer", "Task", "Process", "Ecto", "Phoenix"]
      "python" -> ["os", "sys", "json", "datetime", "requests", "pandas"]
      _ -> []
    end
  end
  
  defp fallback_to_engine(description, language, context) do
    engine_input = %{
      prompt: description,
      language: String.to_atom(language),
      context: %{
        project_files: Map.get(context.metadata, :project_files, []),
        current_file: Map.get(context.metadata, :current_file),
        imports: Map.get(context.metadata, :imports, [])
      }
    }
    
    case Manager.execute(:generation, engine_input) do
      {:ok, result} ->
        {:ok, %{
          generated_code: result.code,
          language: language,
          description: description,
          imports: result.imports,
          confidence: result.confidence,
          explanation: result.explanation,
          timestamp: DateTime.utc_now(),
          fallback: true
        }}
        
      {:error, :engine_not_found} ->
        # Final fallback to mock
        generated_code = generate_mock_code(description, language)
        
        {:ok, %{
          generated_code: generated_code,
          language: language,
          description: description,
          timestamp: DateTime.utc_now(),
          fallback: true,
          mock: true
        }}
        
      {:error, reason} = error ->
        Logger.error("Engine fallback error: #{inspect(reason)}")
        error
    end
  end

  defp generate_mock_code(description, language) do
    case language do
      "elixir" ->
        """
        # Generated from: #{description}
        defmodule GeneratedModule do
          @moduledoc \"\"\"
          #{description}
          \"\"\"

          def example_function do
            :ok
          end
        end
        """
        
      "python" ->
        """
        # Generated from: #{description}
        class GeneratedClass:
            \"\"\"#{description}\"\"\"
            
            def example_method(self):
                return True
        """
        
      _ ->
        """
        // Generated from: #{description}
        // Language: #{language}
        // This is a placeholder implementation
        """
    end
  end
end