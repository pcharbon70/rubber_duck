defmodule RubberDuck.Tools.CodeExplainer do
  @moduledoc """
  Produces a human-readable explanation or docstring for the provided Elixir code.
  
  This tool analyzes code structure and generates clear explanations of what
  the code does, including purpose, parameters, return values, and behavior.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  alias RubberDuck.Analysis.AST.Parser
  
  tool do
    name :code_explainer
    description "Produces a human-readable explanation or docstring for the provided Elixir code"
    category :documentation
    version "1.0.0"
    tags [:documentation, :explanation, :understanding, :learning]
    
    parameter :code do
      type :string
      required true
      description "The Elixir code to explain"
      constraints [
        min_length: 1,
        max_length: 10000
      ]
    end
    
    parameter :explanation_type do
      type :string
      required false
      description "Type of explanation to generate"
      default "comprehensive"
      constraints [
        enum: [
          "comprehensive",    # Full explanation with examples
          "summary",         # Brief overview
          "docstring",       # Generate @moduledoc or @doc
          "inline_comments", # Add inline comments
          "beginner",        # Detailed explanation for beginners
          "technical"        # Technical deep-dive
        ]
      ]
    end
    
    parameter :include_examples do
      type :boolean
      required false
      description "Whether to include usage examples"
      default true
    end
    
    parameter :target_audience do
      type :string
      required false
      description "Target audience for the explanation"
      default "intermediate"
      constraints [
        enum: ["beginner", "intermediate", "expert"]
      ]
    end
    
    parameter :focus_areas do
      type :list
      required false
      description "Specific aspects to focus on"
      default []
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 20_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access, :code_analysis]
      rate_limit [max_requests: 150, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the code explanation based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, ast} <- parse_code(params.code),
         {:ok, analysis} <- analyze_code_structure(ast, params.code),
         {:ok, explanation} <- generate_explanation(params, analysis, context),
         {:ok, formatted} <- format_explanation(explanation, params) do
      
      result = %{
        explanation: formatted,
        code: params.code,
        type: params.explanation_type,
        analysis: %{
          functions: analysis.functions,
          modules: analysis.modules,
          complexity: analysis.complexity
        }
      }
      
      result = if params.include_examples && params.explanation_type != "inline_comments" do
        case generate_examples(params.code, analysis, context) do
          {:ok, examples} -> Map.put(result, :examples, examples)
          _ -> result
        end
      else
        result
      end
      
      {:ok, result}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp parse_code(code) do
    case Code.string_to_quoted(code, columns: true, token_metadata: true) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, _}} -> 
        {:error, "Parse error on line #{line}: #{error}"}
    end
  end
  
  defp analyze_code_structure(ast, code) do
    analysis = %{
      ast: ast,
      functions: analyze_functions(ast),
      modules: analyze_modules(ast),
      patterns: identify_patterns(ast),
      complexity: calculate_complexity(ast),
      dependencies: extract_dependencies(ast),
      type_specs: extract_type_specs(ast),
      docs: extract_existing_docs(ast),
      line_count: length(String.split(code, "\n"))
    }
    
    {:ok, analysis}
  end
  
  defp generate_explanation(params, analysis, context) do
    prompt = build_explanation_prompt(params, analysis)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 2000,
      temperature: 0.5,  # Balanced for accuracy and creativity
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> {:ok, response}
      error -> error
    end
  end
  
  defp build_explanation_prompt(params, analysis) do
    base_prompt = """
    Explain the following Elixir code in a #{params.target_audience}-friendly way.
    
    Code to explain:
    ```elixir
    #{params.code}
    ```
    
    Code analysis:
    - Functions: #{inspect(analysis.functions)}
    - Complexity score: #{analysis.complexity}
    - Patterns used: #{inspect(analysis.patterns)}
    """
    
    type_specific = case params.explanation_type do
      "comprehensive" ->
        """
        
        Provide a comprehensive explanation including:
        1. Overview of what the code does
        2. Detailed explanation of each function
        3. How the code works step-by-step
        4. Any notable patterns or techniques used
        5. Potential use cases
        """
      
      "summary" ->
        """
        
        Provide a brief summary (2-3 sentences) of what this code does.
        Focus on the main purpose and key functionality.
        """
      
      "docstring" ->
        """
        
        Generate appropriate Elixir documentation:
        - @moduledoc for modules
        - @doc for public functions
        - Include parameter descriptions and return values
        - Follow Elixir documentation best practices
        """
      
      "inline_comments" ->
        """
        
        Add helpful inline comments to the code:
        - Explain complex logic
        - Clarify non-obvious operations
        - Note important assumptions
        - Keep comments concise and relevant
        Return the code with comments added.
        """
      
      "beginner" ->
        """
        
        Explain this code for someone new to Elixir:
        1. Define any Elixir-specific terms
        2. Explain syntax that might be unfamiliar
        3. Break down each line if necessary
        4. Relate to common programming concepts
        5. Avoid jargon or overly technical terms
        """
      
      "technical" ->
        """
        
        Provide a technical deep-dive:
        1. Analyze algorithmic complexity
        2. Discuss performance characteristics
        3. Examine memory usage patterns
        4. Identify potential optimizations
        5. Compare with alternative approaches
        """
    end
    
    focus = if params.focus_areas != [] do
      "\n\nPay special attention to: #{Enum.join(params.focus_areas, ", ")}"
    else
      ""
    end
    
    base_prompt <> type_specific <> focus
  end
  
  defp format_explanation(explanation, params) do
    formatted = case params.explanation_type do
      "inline_comments" ->
        # Extract code with comments from response
        extract_commented_code(explanation)
      
      "docstring" ->
        # Format as proper Elixir documentation
        format_as_docstring(explanation)
      
      _ ->
        # Clean up and format the explanation
        explanation
        |> String.trim()
        |> format_markdown()
    end
    
    {:ok, formatted}
  end
  
  defp generate_examples(code, analysis, context) do
    return_type = if Enum.any?(analysis.functions, fn {name, _, _} -> name == :main end) do
      "module usage"
    else
      "function usage"
    end
    
    prompt = """
    Generate practical usage examples for this Elixir code:
    
    ```elixir
    #{code}
    ```
    
    Provide 2-3 clear examples showing how to use the #{return_type}.
    Include expected inputs and outputs.
    """
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 1000,
      temperature: 0.7,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_code_examples(response)
      error -> error
    end
  end
  
  # Analysis helper functions
  
  defp analyze_functions(ast) do
    ast
    |> Macro.postwalk([], fn
      {:def, meta, [{name, _, args} | rest]} = node, acc ->
        arity = length(args || [])
        doc = extract_function_doc(rest)
        {node, [{name, arity, %{public: true, doc: doc, line: meta[:line]}} | acc]}
      
      {:defp, meta, [{name, _, args} | _]} = node, acc ->
        arity = length(args || [])
        {node, [{name, arity, %{public: false, doc: nil, line: meta[:line]}} | acc]}
      
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp analyze_modules(ast) do
    ast
    |> Macro.postwalk([], fn
      {:defmodule, meta, [{:__aliases__, _, module_parts} | rest]} = node, acc ->
        module_name = Module.concat(module_parts)
        doc = extract_module_doc(rest)
        {node, [{module_name, %{doc: doc, line: meta[:line]}} | acc]}
      
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp identify_patterns(ast) do
    patterns = []
    
    patterns = if has_pattern?(ast, :with), do: [:with_pattern | patterns], else: patterns
    patterns = if has_pattern?(ast, :case), do: [:pattern_matching | patterns], else: patterns
    patterns = if has_pipe_operator?(ast), do: [:pipe_operator | patterns], else: patterns
    patterns = if has_pattern?(ast, :try), do: [:error_handling | patterns], else: patterns
    patterns = if has_pattern?(ast, :receive), do: [:message_passing | patterns], else: patterns
    
    Enum.reverse(patterns)
  end
  
  defp has_pattern?(ast, pattern) do
    ast
    |> Macro.postwalk(false, fn
      {^pattern, _, _}, _ -> {nil, true}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end
  
  defp has_pipe_operator?(ast) do
    ast
    |> Macro.postwalk(false, fn
      {:|>, _, _}, _ -> {nil, true}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end
  
  defp calculate_complexity(ast) do
    ast
    |> Macro.postwalk(0, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      {:try, _, _} = node, acc -> {node, acc + 3}
      {:receive, _, _} = node, acc -> {node, acc + 2}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end
  
  defp extract_dependencies(ast) do
    ast
    |> Macro.postwalk([], fn
      {:alias, _, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [Module.concat(parts) | acc]}
      {:import, _, [module | _]} = node, acc ->
        {node, [module | acc]}
      {:require, _, [module | _]} = node, acc ->
        {node, [module | acc]}
      {:use, _, [module | _]} = node, acc ->
        {node, [module | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
    |> Enum.reverse()
  end
  
  defp extract_type_specs(ast) do
    ast
    |> Macro.postwalk([], fn
      {:@, _, [{:spec, _, _} | _]} = node, acc ->
        {node, [:has_specs | acc]}
      {:@, _, [{:type, _, _} | _]} = node, acc ->
        {node, [:has_types | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
  end
  
  defp extract_existing_docs(ast) do
    ast
    |> Macro.postwalk([], fn
      {:@, _, [{:moduledoc, _, [doc]} | _]} = node, acc ->
        {node, [{:moduledoc, doc} | acc]}
      {:@, _, [{:doc, _, [doc]} | _]} = node, acc ->
        {node, [{:doc, doc} | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp extract_function_doc([{:do, block} | _]), do: nil
  defp extract_function_doc(_), do: nil
  
  defp extract_module_doc([{:do, _} | _]), do: nil
  defp extract_module_doc(_), do: nil
  
  defp extract_commented_code(response) do
    case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, response, capture: :all_but_first) do
      [code] -> String.trim(code)
      _ -> response
    end
  end
  
  defp format_as_docstring(explanation) do
    # Clean up the explanation to be valid Elixir doc format
    explanation
    |> String.trim()
    |> String.replace(~r/^```elixir\n/, "")
    |> String.replace(~r/\n```$/, "")
  end
  
  defp format_markdown(text) do
    # Basic markdown formatting cleanup
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
  
  defp extract_code_examples(response) do
    examples = Regex.scan(~r/```(?:elixir|ex)?\n(.*?)\n```/s, response)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
    
    if examples == [] do
      {:error, "No examples generated"}
    else
      {:ok, examples}
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end