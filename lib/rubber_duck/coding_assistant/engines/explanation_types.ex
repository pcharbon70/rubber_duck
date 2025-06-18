defmodule RubberDuck.CodingAssistant.Engines.ExplanationTypes do
  @moduledoc """
  Explanation type definitions and formatters for the ExplanationEngine.
  
  This module provides standardized explanation types with specific formatting
  and prompting strategies optimized for different use cases.
  """
  
  
  @explanation_types %{
    summary: %{
      name: "Summary",
      description: "Brief overview of code functionality",
      max_length: 500,
      complexity: :low,
      target_audience: :general
    },
    detailed: %{
      name: "Detailed Analysis",
      description: "Comprehensive explanation with context",
      max_length: 2000,
      complexity: :medium,
      target_audience: :developer
    },
    step_by_step: %{
      name: "Step-by-Step Walkthrough",
      description: "Line-by-line code explanation",
      max_length: 3000,
      complexity: :high,
      target_audience: :beginner
    },
    architectural: %{
      name: "Architectural Analysis",
      description: "Design patterns and architectural decisions",
      max_length: 1500,
      complexity: :high,
      target_audience: :architect
    },
    documentation: %{
      name: "Documentation Generation",
      description: "Formal documentation with examples",
      max_length: 2500,
      complexity: :medium,
      target_audience: :maintainer
    }
  }
  
  @doc """
  Get all available explanation types.
  """
  def available_types do
    Map.keys(@explanation_types)
  end
  
  @doc """
  Get metadata for a specific explanation type.
  """
  def get_type_metadata(type) do
    Map.get(@explanation_types, type)
  end
  
  @doc """
  Build an explanation prompt based on type and context.
  """
  def build_prompt(type, code, language, context \\ %{}) do
    case type do
      :summary -> build_summary_prompt(code, language, context)
      :detailed -> build_detailed_prompt(code, language, context)
      :step_by_step -> build_step_by_step_prompt(code, language, context)
      :architectural -> build_architectural_prompt(code, language, context)
      :documentation -> build_documentation_prompt(code, language, context)
      _ -> build_default_prompt(code, language, context)
    end
  end
  
  @doc """
  Format explanation output based on type.
  """
  def format_output(type, content, metadata \\ %{}) do
    case type do
      :summary -> format_summary(content, metadata)
      :detailed -> format_detailed(content, metadata)
      :step_by_step -> format_step_by_step(content, metadata)
      :architectural -> format_architectural(content, metadata)
      :documentation -> format_documentation(content, metadata)
      _ -> format_default(content, metadata)
    end
  end
  
  @doc """
  Determine appropriate explanation type based on code characteristics.
  """
  def suggest_type(code, language, context \\ %{}) do
    code_length = String.length(code)
    complexity = estimate_complexity(code, language)
    
    cond do
      code_length < 100 -> :summary
      Map.get(context, :beginner_mode, false) -> :step_by_step
      complexity == :high and code_length > 500 -> :architectural
      Map.get(context, :documentation_mode, false) -> :documentation
      true -> :detailed
    end
  end
  
  # Private Functions - Prompt Builders
  
  defp build_summary_prompt(code, language, context) do
    symbols = Map.get(context, :symbols, [])
    main_purpose = infer_main_purpose(symbols, language)
    
    """
    Provide a concise summary (max 3-4 sentences) of this #{language} code:
    
    ```#{language}
    #{code}
    ```
    
    #{if main_purpose, do: "Focus on: #{main_purpose}", else: ""}
    
    Include only the core functionality and primary purpose. Avoid implementation details.
    """
  end
  
  defp build_detailed_prompt(code, language, context) do
    symbols = Map.get(context, :symbols, [])
    structure = Map.get(context, :structure, %{})
    
    """
    Provide a comprehensive explanation of this #{language} code:
    
    ```#{language}
    #{code}
    ```
    
    #{format_context_info(symbols, structure)}
    
    Include:
    1. **Purpose**: What this code does and why
    2. **Components**: Key functions, classes, or modules and their roles
    3. **Data Flow**: How data moves through the code
    4. **Logic**: Important algorithms or business logic
    5. **Patterns**: Notable design patterns or programming techniques
    
    Provide clear explanations suitable for a developer familiar with #{language}.
    """
  end
  
  defp build_step_by_step_prompt(code, language, _context) do
    numbered_lines = code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, num} -> "#{num}: #{line}" end)
    |> Enum.join("\n")
    
    """
    Provide a step-by-step walkthrough of this #{language} code:
    
    ```#{language}
    #{numbered_lines}
    ```
    
    For each significant line or block:
    1. Reference the line number(s)
    2. Explain what happens
    3. Explain why it's important
    4. Show how it connects to other parts
    
    Use simple language and assume the reader is learning #{language}.
    Focus on building understanding progressively.
    """
  end
  
  defp build_architectural_prompt(code, language, context) do
    structure = Map.get(context, :structure, %{})
    complexity = Map.get(context, :complexity, :unknown)
    
    """
    Analyze the architectural patterns and design decisions in this #{language} code:
    
    ```#{language}
    #{code}
    ```
    
    #{format_structural_context(structure, complexity)}
    
    Focus on:
    1. **Design Patterns**: What patterns are used and why
    2. **Architecture**: Overall structure and organization
    3. **Principles**: SOLID, DRY, or other principles applied
    4. **Trade-offs**: Design decisions and their implications
    5. **Relationships**: How components interact
    6. **Extensibility**: How the design supports future changes
    
    Analyze from a software architecture perspective.
    """
  end
  
  defp build_documentation_prompt(code, language, context) do
    symbols = Map.get(context, :symbols, [])
    
    """
    Generate comprehensive documentation for this #{language} code:
    
    ```#{language}
    #{code}
    ```
    
    #{format_symbols_for_docs(symbols)}
    
    Include:
    1. **Overview**: Brief description of purpose
    2. **Usage**: How to use this code with examples
    3. **Parameters**: Input parameters and their types/purposes
    4. **Returns**: Return values and their meaning
    5. **Examples**: Practical usage examples
    6. **Notes**: Important considerations, limitations, or warnings
    7. **Dependencies**: External dependencies or requirements
    
    Format as professional API documentation.
    """
  end
  
  defp build_default_prompt(code, language, _context) do
    """
    Explain this #{language} code:
    
    ```#{language}
    #{code}
    ```
    
    Provide a clear explanation of what the code does and how it works.
    """
  end
  
  # Private Functions - Output Formatters
  
  defp format_summary(content, metadata) do
    language = Map.get(metadata, :language, "code")
    
    """
    ## Summary
    
    #{content}
    
    *Language: #{String.capitalize(to_string(language))}*
    """
  end
  
  defp format_detailed(content, metadata) do
    language = Map.get(metadata, :language, "code")
    confidence = Map.get(metadata, :confidence, 0.0)
    
    """
    ## Detailed Code Analysis
    
    #{content}
    
    ---
    *Analysis for #{String.capitalize(to_string(language))} • Confidence: #{trunc(confidence * 100)}%*
    """
  end
  
  defp format_step_by_step(content, metadata) do
    language = Map.get(metadata, :language, "code")
    
    """
    ## Step-by-Step Walkthrough
    
    #{content}
    
    ---
    *#{String.capitalize(to_string(language))} Code Walkthrough*
    """
  end
  
  defp format_architectural(content, metadata) do
    language = Map.get(metadata, :language, "code")
    complexity = Map.get(metadata, :complexity, "unknown")
    
    """
    ## Architectural Analysis
    
    #{content}
    
    ---
    *#{String.capitalize(to_string(language))} Architecture • Complexity: #{complexity}*
    """
  end
  
  defp format_documentation(content, metadata) do
    language = Map.get(metadata, :language, "code")
    timestamp = DateTime.utc_now() |> DateTime.to_date() |> Date.to_string()
    
    """
    # Code Documentation
    
    #{content}
    
    ---
    *Generated on #{timestamp} for #{String.capitalize(to_string(language))} code*
    """
  end
  
  defp format_default(content, metadata) do
    language = Map.get(metadata, :language, "code")
    
    """
    ## Code Explanation
    
    #{content}
    
    *Language: #{String.capitalize(to_string(language))}*
    """
  end
  
  # Private Functions - Context Helpers
  
  defp format_context_info(symbols, structure) do
    parts = []
    
    parts = if length(symbols) > 0 do
      symbol_info = symbols
      |> Enum.take(5)
      |> Enum.map(&"- #{&1}")
      |> Enum.join("\n")
      
      ["\n**Key Symbols Found:**\n#{symbol_info}" | parts]
    else
      parts
    end
    
    parts = if map_size(structure) > 0 do
      structure_info = structure
      |> Enum.take(3)
      |> Enum.map(fn {key, value} -> "- #{key}: #{value}" end)
      |> Enum.join("\n")
      
      ["\n**Code Structure:**\n#{structure_info}" | parts]
    else
      parts
    end
    
    Enum.reverse(parts) |> Enum.join("\n")
  end
  
  defp format_structural_context(structure, complexity) do
    parts = []
    
    parts = if map_size(structure) > 0 do
      ["**Detected Structure:** #{inspect(structure)}" | parts]
    else
      parts
    end
    
    parts = if complexity != :unknown do
      ["**Complexity Level:** #{complexity}" | parts]
    else
      parts
    end
    
    case parts do
      [] -> ""
      _ -> "\n" <> Enum.join(Enum.reverse(parts), "\n") <> "\n"
    end
  end
  
  defp format_symbols_for_docs(symbols) do
    case symbols do
      [] -> ""
      _ ->
        symbol_list = symbols
        |> Enum.take(10)
        |> Enum.map(&"- #{&1}")
        |> Enum.join("\n")
        
        "\n**Symbols to document:**\n#{symbol_list}\n"
    end
  end
  
  defp infer_main_purpose(symbols, language) do
    cond do
      language == :elixir and Enum.any?(symbols, &String.contains?(&1, "GenServer")) ->
        "GenServer implementation"
      
      language == :elixir and Enum.any?(symbols, &String.contains?(&1, "defmodule")) ->
        "Module definition"
      
      Enum.any?(symbols, &String.contains?(&1, "test")) ->
        "Test implementation"
      
      Enum.any?(symbols, &String.contains?(&1, "main")) ->
        "Main program logic"
      
      true -> nil
    end
  end
  
  defp estimate_complexity(code, _language) do
    lines = String.split(code, "\n") |> length()
    
    cond do
      lines < 20 -> :low
      lines < 100 -> :medium
      true -> :high
    end
  end
end