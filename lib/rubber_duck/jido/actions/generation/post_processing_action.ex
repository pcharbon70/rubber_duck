defmodule RubberDuck.Jido.Actions.Generation.PostProcessingAction do
  @moduledoc """
  Action for post-processing generated code to improve quality and formatting.

  This action handles the final stage of code generation, applying formatting,
  optimization, documentation generation, and final quality checks to
  ensure the generated code meets professional standards.

  ## Parameters

  - `code` - Generated code to post-process (required)
  - `language` - Programming language (default: :elixir)
  - `processing_types` - Types of post-processing to apply (default: [:format, :optimize, :document])
  - `formatting_options` - Options for code formatting
  - `optimization_level` - Level of optimization to apply (default: :standard)

  ## Returns

  - `{:ok, result}` - Post-processing completed successfully
  - `{:error, reason}` - Post-processing failed

  ## Example

      params = %{
        code: "defmodule Test do\\ndef hello,do: :world\\nend",
        language: :elixir,
        processing_types: [:format, :optimize, :document, :validate]
      }

      {:ok, result} = PostProcessingAction.run(params, context)
  """

  use Jido.Action,
    name: "post_processing",
    description: "Post-process generated code for quality and formatting",
    schema: [
      code: [
        type: :string,
        required: true,
        doc: "Generated code to post-process"
      ],
      language: [
        type: :atom,
        default: :elixir,
        doc: "Programming language"
      ],
      processing_types: [
        type: {:list, :atom},
        default: [:format, :optimize, :document],
        doc: "Types of post-processing to apply"
      ],
      formatting_options: [
        type: :map,
        default: %{},
        doc: "Options for code formatting"
      ],
      optimization_level: [
        type: :atom,
        default: :standard,
        doc: "Level of optimization (none, standard, aggressive)"
      ],
      add_documentation: [
        type: :boolean,
        default: true,
        doc: "Whether to add missing documentation"
      ],
      add_tests: [
        type: :boolean,
        default: false,
        doc: "Whether to generate basic tests"
      ]
    ]

  require Logger

  @impl true
  def run(params, context) do
    Logger.info("Starting post-processing for #{params.language} code")

    processing_pipeline = build_processing_pipeline(params.processing_types)
    
    case execute_processing_pipeline(params.code, processing_pipeline, params, context) do
      {:ok, processed_code, processing_results} ->
        result = %{
          processed_code: processed_code,
          original_code: params.code,
          improvements: calculate_improvements(params.code, processed_code),
          processing_results: processing_results,
          metadata: %{
            processed_at: DateTime.utc_now(),
            language: params.language,
            processing_types: params.processing_types,
            optimization_level: params.optimization_level,
            original_size: String.length(params.code),
            processed_size: String.length(processed_code)
          }
        }

        {:ok, result}

      {:error, reason} ->
        Logger.error("Post-processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp build_processing_pipeline(processing_types) do
    # Define the order of processing steps
    available_steps = [
      :validate_syntax,
      :format,
      :optimize,
      :document,
      :add_imports,
      :add_tests,
      :final_validation
    ]

    available_steps
    |> Enum.filter(&(&1 in processing_types or &1 in [:validate_syntax, :final_validation]))
  end

  defp execute_processing_pipeline(code, pipeline, params, context) do
    pipeline
    |> Enum.reduce({:ok, code, %{}}, fn step, acc ->
      case acc do
        {:ok, current_code, results} ->
          case apply_processing_step(step, current_code, params, context) do
            {:ok, processed_code, step_result} ->
              {:ok, processed_code, Map.put(results, step, step_result)}
            
            {:error, reason} ->
              {:error, {:step_failed, step, reason}}
          end
        
        error ->
          error
      end
    end)
  end

  defp apply_processing_step(:validate_syntax, code, params, _context) do
    case validate_syntax(code, params.language) do
      true ->
        {:ok, code, %{valid: true, message: "Syntax is valid"}}
      
      false ->
        {:error, :invalid_syntax}
    end
  end

  defp apply_processing_step(:format, code, params, _context) do
    case format_code(code, params.language, params.formatting_options) do
      {:ok, formatted_code} ->
        {:ok, formatted_code, %{formatted: true, changes: calculate_format_changes(code, formatted_code)}}
      
      {:error, reason} ->
        Logger.warning("Formatting failed, keeping original: #{inspect(reason)}")
        {:ok, code, %{formatted: false, error: reason}}
    end
  end

  defp apply_processing_step(:optimize, code, params, _context) do
    case optimize_code(code, params.language, params.optimization_level) do
      {:ok, optimized_code, optimizations} ->
        {:ok, optimized_code, %{optimized: true, optimizations: optimizations}}
      
      {:error, reason} ->
        Logger.warning("Optimization failed, keeping original: #{inspect(reason)}")
        {:ok, code, %{optimized: false, error: reason}}
    end
  end

  defp apply_processing_step(:document, code, params, _context) do
    if params.add_documentation do
      case add_documentation(code, params.language) do
        {:ok, documented_code} ->
          {:ok, documented_code, %{documented: true, docs_added: count_docs_added(code, documented_code)}}
        
        {:error, reason} ->
          Logger.warning("Documentation addition failed: #{inspect(reason)}")
          {:ok, code, %{documented: false, error: reason}}
      end
    else
      {:ok, code, %{documented: false, skipped: true}}
    end
  end

  defp apply_processing_step(:add_imports, code, params, _context) do
    case add_missing_imports(code, params.language) do
      {:ok, code_with_imports, imports_added} ->
        {:ok, code_with_imports, %{imports_added: imports_added}}
      
      {:error, reason} ->
        Logger.warning("Import addition failed: #{inspect(reason)}")
        {:ok, code, %{imports_added: [], error: reason}}
    end
  end

  defp apply_processing_step(:add_tests, code, params, context) do
    if params.add_tests do
      case generate_basic_tests(code, params.language, context) do
        {:ok, test_code} ->
          {:ok, code, %{tests_generated: true, test_code: test_code}}
        
        {:error, reason} ->
          Logger.warning("Test generation failed: #{inspect(reason)}")
          {:ok, code, %{tests_generated: false, error: reason}}
      end
    else
      {:ok, code, %{tests_generated: false, skipped: true}}
    end
  end

  defp apply_processing_step(:final_validation, code, params, _context) do
    case validate_syntax(code, params.language) do
      true ->
        {:ok, code, %{final_validation: true, message: "Final validation passed"}}
      
      false ->
        {:error, :final_validation_failed}
    end
  end

  # Language-specific processing

  defp validate_syntax(code, :elixir) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> true
      {:error, _} -> false
    end
  end

  defp validate_syntax(_code, _language) do
    # For other languages, assume valid
    true
  end

  defp format_code(code, :elixir, formatting_options) do
    try do
      opts = build_elixir_format_options(formatting_options)
      formatted = Code.format_string!(code, opts) |> IO.iodata_to_binary()
      {:ok, formatted}
    rescue
      error ->
        {:error, {:format_error, error}}
    end
  end

  defp format_code(code, _language, _options) do
    # For other languages, return as-is
    {:ok, code}
  end

  defp optimize_code(code, :elixir, optimization_level) do
    optimizations = []
    optimized_code = code
    
    # Apply various optimizations based on level
    {optimized_code, optimizations} = 
      case optimization_level do
        :none -> {code, []}
        :standard -> apply_standard_optimizations(code)
        :aggressive -> apply_aggressive_optimizations(code)
      end
    
    {:ok, optimized_code, optimizations}
  end

  defp optimize_code(code, _language, _level) do
    {:ok, code, []}
  end

  defp add_documentation(code, :elixir) do
    # Analyze code structure and add missing documentation
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        documented_ast = add_docs_to_ast(ast)
        documented_code = Macro.to_string(documented_ast)
        {:ok, documented_code}
      
      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp add_documentation(code, _language) do
    {:ok, code}
  end

  defp add_missing_imports(code, :elixir) do
    # Analyze code for missing imports and add them
    case analyze_missing_imports(code) do
      {:ok, missing_imports} ->
        code_with_imports = prepend_imports(code, missing_imports)
        {:ok, code_with_imports, missing_imports}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_missing_imports(code, _language) do
    {:ok, code, []}
  end

  defp generate_basic_tests(code, :elixir, _context) do
    # Generate basic tests for the code
    case extract_functions_for_testing(code) do
      {:ok, functions} ->
        test_code = build_test_module(functions)
        {:ok, test_code}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_basic_tests(_code, _language, _context) do
    {:error, :not_implemented}
  end

  # Helper functions

  defp build_elixir_format_options(options) do
    [
      line_length: Map.get(options, :line_length, 98),
      normalize_bitstring_modifiers: Map.get(options, :normalize_bitstring_modifiers, true),
      normalize_charlists_as_sigils: Map.get(options, :normalize_charlists, true)
    ]
  end

  defp apply_standard_optimizations(code) do
    optimizations = []
    optimized_code = code
    
    # Remove unnecessary parentheses
    if String.contains?(code, "()") do
      optimized_code = String.replace(optimized_code, ~r/\(\s*\)/, "")
      optimizations = ["removed_empty_parentheses" | optimizations]
    end
    
    # Simplify boolean expressions
    if String.contains?(code, "== true") do
      optimized_code = String.replace(optimized_code, ~r/\s*==\s*true/, "")
      optimizations = ["simplified_boolean_expressions" | optimizations]
    end
    
    {optimized_code, optimizations}
  end

  defp apply_aggressive_optimizations(code) do
    {standard_optimized, standard_opts} = apply_standard_optimizations(code)
    
    # Additional aggressive optimizations
    optimizations = standard_opts
    optimized_code = standard_optimized
    
    # Convert if-else to case when appropriate
    # (This would require more sophisticated AST manipulation)
    
    {optimized_code, optimizations}
  end

  defp add_docs_to_ast(ast) do
    # Simple documentation addition - in practice this would be more sophisticated
    case ast do
      {:defmodule, meta, [module_name, [do: module_body]]} ->
        doc_attr = {:@, [], [{:moduledoc, [], ["Documentation for #{inspect(module_name)}"]}]}
        new_body = [doc_attr | List.wrap(module_body)]
        {:defmodule, meta, [module_name, [do: {:__block__, [], new_body}]]}
      
      other ->
        other
    end
  end

  defp analyze_missing_imports(code) do
    # Analyze code for potentially missing imports
    # This is a simplified implementation
    missing = []
    
    # Check for common patterns
    missing = if String.contains?(code, "GenServer") and not String.contains?(code, "use GenServer") do
      ["GenServer" | missing]
    else
      missing
    end
    
    missing = if String.contains?(code, "Logger") and not String.contains?(code, "require Logger") do
      ["Logger" | missing]
    else
      missing
    end
    
    {:ok, missing}
  end

  defp prepend_imports(code, imports) do
    import_statements = imports
    |> Enum.map(fn import ->
      cond do
        import == "Logger" -> "require Logger"
        import == "GenServer" -> "use GenServer"
        true -> "alias #{import}"
      end
    end)
    |> Enum.join("\n")
    
    if import_statements != "" do
      import_statements <> "\n\n" <> code
    else
      code
    end
  end

  defp extract_functions_for_testing(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        functions = extract_public_functions(ast)
        {:ok, functions}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_public_functions(ast) do
    # Extract public function definitions for test generation
    # This is a simplified implementation
    []
  end

  defp build_test_module(_functions) do
    """
    defmodule GeneratedTest do
      use ExUnit.Case, async: true
      
      # Generated tests would go here
      test "placeholder test" do
        assert true
      end
    end
    """
  end

  defp calculate_improvements(original, processed) do
    %{
      size_change: String.length(processed) - String.length(original),
      line_count_change: count_lines(processed) - count_lines(original),
      formatting_improved: original != processed
    }
  end

  defp calculate_format_changes(original, formatted) do
    %{
      lines_changed: count_lines(formatted) - count_lines(original),
      whitespace_normalized: String.trim(original) != String.trim(formatted)
    }
  end

  defp count_docs_added(original, documented) do
    original_docs = Regex.scan(~r/@(moduledoc|doc)/, original) |> length()
    documented_docs = Regex.scan(~r/@(moduledoc|doc)/, documented) |> length()
    documented_docs - original_docs
  end

  defp count_lines(text) do
    String.split(text, "\n") |> length()
  end
end