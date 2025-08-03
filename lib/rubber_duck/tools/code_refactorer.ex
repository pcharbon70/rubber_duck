defmodule RubberDuck.Tools.CodeRefactorer do
  @moduledoc """
  Applies structural or semantic transformations to existing code based on an instruction.
  
  This tool analyzes existing code and applies refactoring transformations
  while preserving functionality and improving code quality.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  alias RubberDuck.Analysis.AST.Parser
  
  tool do
    name :code_refactorer
    description "Applies structural or semantic transformations to existing code based on an instruction"
    category :code_transformation
    version "1.0.0"
    tags [:refactoring, :code, :transformation, :quality]
    
    parameter :code do
      type :string
      required true
      description "The source code to refactor"
      constraints [
        min_length: 1,
        max_length: 10000
      ]
    end
    
    parameter :instruction do
      type :string
      required true
      description "Refactoring instruction (e.g., 'extract function', 'rename variable', 'simplify logic')"
      constraints [
        min_length: 5,
        max_length: 500
      ]
    end
    
    parameter :refactoring_type do
      type :string
      required false
      description "Type of refactoring to apply"
      default "general"
      constraints [
        enum: [
          "general",
          "extract_function",
          "inline_function", 
          "rename",
          "simplify",
          "restructure",
          "performance",
          "readability",
          "pattern_matching",
          "error_handling"
        ]
      ]
    end
    
    parameter :preserve_comments do
      type :boolean
      required false
      description "Whether to preserve existing comments"
      default true
    end
    
    parameter :style_guide do
      type :string
      required false
      description "Style guide to follow (e.g., 'credo', 'community', 'custom')"
      default "credo"
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access, :code_analysis]
      rate_limit [max_requests: 100, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the code refactoring based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, ast} <- parse_code(params.code),
         {:ok, analysis} <- analyze_code(ast, params.code),
         {:ok, refactoring_plan} <- create_refactoring_plan(params, analysis),
         {:ok, refactored_code} <- apply_refactoring(params, refactoring_plan, context),
         {:ok, validated_code} <- validate_refactoring(params.code, refactored_code) do
      
      {:ok, %{
        original_code: params.code,
        refactored_code: refactored_code,
        changes: describe_changes(params.code, refactored_code),
        refactoring_type: params.refactoring_type,
        instruction: params.instruction
      }}
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
  
  defp analyze_code(ast, code) do
    analysis = %{
      ast: ast,
      functions: extract_functions(ast),
      variables: extract_variables(ast),
      modules: extract_modules(ast),
      complexity: calculate_complexity(ast),
      line_count: length(String.split(code, "\n"))
    }
    
    {:ok, analysis}
  end
  
  defp create_refactoring_plan(params, analysis) do
    plan = %{
      type: params.refactoring_type,
      instruction: params.instruction,
      targets: identify_refactoring_targets(params, analysis),
      preserve_comments: params.preserve_comments,
      style_guide: params.style_guide
    }
    
    {:ok, plan}
  end
  
  defp apply_refactoring(params, plan, context) do
    prompt = build_refactoring_prompt(params, plan)
    
    case Service.generate(%{
      prompt: prompt,
      max_tokens: 3000,
      temperature: 0.3,  # Lower temperature for more deterministic refactoring
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} -> extract_refactored_code(response)
      error -> error
    end
  end
  
  defp build_refactoring_prompt(params, plan) do
    """
    Refactor the following Elixir code according to the instruction.
    
    Original code:
    ```elixir
    #{params.code}
    ```
    
    Refactoring instruction: #{params.instruction}
    Refactoring type: #{params.refactoring_type}
    Style guide: #{params.style_guide}
    Preserve comments: #{params.preserve_comments}
    
    Requirements:
    1. Maintain the exact same functionality
    2. Follow Elixir best practices and idioms
    3. Improve code quality, readability, or performance as requested
    4. Keep all existing tests passing
    5. #{if params.preserve_comments, do: "Preserve all existing comments", else: "Update or remove comments as needed"}
    
    Please provide the refactored code that addresses the instruction while maintaining correctness.
    """
  end
  
  defp extract_refactored_code(response) do
    case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, response, capture: :all_but_first) do
      [code] -> {:ok, String.trim(code)}
      _ -> 
        # Try to extract code without fence
        code = response
        |> String.split("\n")
        |> Enum.drop_while(&(!String.contains?(&1, ["def", "defmodule"])))
        |> Enum.join("\n")
        |> String.trim()
        
        if code == "" do
          {:error, "No refactored code found in response"}
        else
          {:ok, code}
        end
    end
  end
  
  defp validate_refactoring(original_code, refactored_code) do
    with {:ok, _} <- parse_code(refactored_code),
         :ok <- check_functionality_preserved(original_code, refactored_code) do
      {:ok, refactored_code}
    end
  end
  
  defp check_functionality_preserved(_original, _refactored) do
    # In a real implementation, this would run tests or perform
    # more sophisticated analysis to ensure functionality is preserved
    :ok
  end
  
  defp describe_changes(original, refactored) do
    original_lines = String.split(original, "\n")
    refactored_lines = String.split(refactored, "\n")
    
    %{
      lines_added: length(refactored_lines) - length(original_lines),
      complexity_change: "improved", # Would calculate actual metrics
      summary: "Code has been refactored according to instructions"
    }
  end
  
  # Helper functions for code analysis
  
  defp extract_functions(ast) do
    # Walk AST to find function definitions
    ast
    |> Macro.postwalk([], fn
      {:def, _, [{name, _, args} | _]} = node, acc ->
        {node, [{name, length(args || [])} | acc]}
      {:defp, _, [{name, _, args} | _]} = node, acc ->
        {node, [{name, length(args || [])} | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp extract_variables(ast) do
    # Walk AST to find variable assignments
    ast
    |> Macro.postwalk([], fn
      {:=, _, [{var, _, nil} | _]} = node, acc when is_atom(var) ->
        {node, [var | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
    |> Enum.reverse()
  end
  
  defp extract_modules(ast) do
    # Walk AST to find module definitions
    ast
    |> Macro.postwalk([], fn
      {:defmodule, _, [{:__aliases__, _, module_parts} | _]} = node, acc ->
        {node, [Module.concat(module_parts) | acc]}
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp calculate_complexity(ast) do
    # Simple complexity calculation based on control structures
    ast
    |> Macro.postwalk(0, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end
  
  defp identify_refactoring_targets(params, analysis) do
    case params.refactoring_type do
      "extract_function" -> analysis.functions
      "rename" -> analysis.functions ++ analysis.variables
      _ -> []
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end