defmodule RubberDuck.CodingAssistant.Engines.ExplanationFallbacks do
  @moduledoc """
  Fallback mechanisms for ExplanationEngine when LLM services are unavailable or fail.
  
  This module provides multiple fallback strategies to ensure the ExplanationEngine
  can still provide useful responses even when external LLM services are down,
  rate-limited, or experiencing issues.
  """
  
  alias RubberDuck.ILP.Parser.TreeSitterWrapper
  
  require Logger
  
  
  @doc """
  Generate a fallback explanation when LLM services are unavailable.
  """
  def generate_fallback(request, reason, context \\ %{}) do
    Logger.info("Generating fallback explanation due to: #{inspect(reason)}")
    
    strategy = select_fallback_strategy(request, reason, context)
    
    case strategy do
      :static_analysis -> static_analysis_fallback(request, context)
      :template_based -> template_based_fallback(request, context)
      :cached_similar -> cached_similar_fallback(request, context)
      :basic_parsing -> basic_parsing_fallback(request, context)
      :minimal_response -> minimal_response_fallback(request, context)
    end
  end
  
  @doc """
  Select the most appropriate fallback strategy based on request and failure reason.
  """
  def select_fallback_strategy(request, reason, context \\ %{}) do
    cond do
      # If we have good parsing capability, use static analysis
      can_parse_language?(request.language) and reason != :parsing_failed ->
        :static_analysis
      
      # If LLM is temporarily unavailable, try cached similar
      reason in [:llm_unavailable, :rate_limited] and has_cache?(context) ->
        :cached_similar
      
      # For simple code, template-based works well
      is_simple_code?(request.content) ->
        :template_based
      
      # If parsing works but LLM failed, use basic parsing
      can_parse_language?(request.language) ->
        :basic_parsing
      
      # Last resort
      true ->
        :minimal_response
    end
  end
  
  @doc """
  Validate if a fallback result meets minimum quality standards.
  """
  def validate_fallback_quality(result, min_length \\ 50) do
    explanation_length = String.length(result.explanation)
    
    cond do
      explanation_length < min_length ->
        {:invalid, :too_short}
      
      String.contains?(result.explanation, "Error") ->
        {:invalid, :contains_error}
      
      result.confidence < 0.3 ->
        {:invalid, :low_confidence}
      
      true ->
        {:valid, result}
    end
  end
  
  # Fallback Strategy Implementations
  
  defp static_analysis_fallback(request, context) do
    Logger.debug("Using static analysis fallback")
    
    case analyze_code_statically(request.content, request.language) do
      {:ok, analysis} ->
        explanation = format_static_analysis(analysis, request.type, request.language)
        
        %{
          explanation: explanation,
          metadata: %{
            type: :static_analysis_fallback,
            language: request.language,
            analysis: analysis,
            fallback_reason: :llm_unavailable
          },
          confidence: calculate_static_confidence(analysis),
          processing_time: 0
        }
      
      {:error, reason} ->
        Logger.warning("Static analysis failed: #{inspect(reason)}")
        template_based_fallback(request, context)
    end
  end
  
  defp template_based_fallback(request, _context) do
    Logger.debug("Using template-based fallback")
    
    template = get_fallback_template(request.type, request.language)
    
    explanation = render_fallback_template(template, %{
      language: request.language,
      content: request.content,
      code_length: String.length(request.content),
      line_count: length(String.split(request.content, "\n"))
    })
    
    %{
      explanation: explanation,
      metadata: %{
        type: :template_based_fallback,
        language: request.language,
        template: request.type,
        fallback_reason: :llm_unavailable
      },
      confidence: 0.6,
      processing_time: 0
    }
  end
  
  defp cached_similar_fallback(request, context) do
    Logger.debug("Using cached similar fallback")
    
    cache = Map.get(context, :cache)
    
    case find_similar_cached_explanation(request, cache) do
      {:ok, similar_result} ->
        adapted_explanation = adapt_cached_explanation(
          similar_result.explanation,
          request.language,
          request.type
        )
        
        %{
          explanation: adapted_explanation,
          metadata: %{
            type: :cached_similar_fallback,
            language: request.language,
            original_confidence: similar_result.confidence,
            adaptation_applied: true,
            fallback_reason: :llm_unavailable
          },
          confidence: similar_result.confidence * 0.8,  # Reduced confidence for adapted content
          processing_time: 0
        }
      
      {:error, _reason} ->
        template_based_fallback(request, context)
    end
  end
  
  defp basic_parsing_fallback(request, _context) do
    Logger.debug("Using basic parsing fallback")
    
    case TreeSitterWrapper.parse_with_treesitter(request.content, request.language, %{}) do
      {:ok, ast} ->
        basic_info = extract_basic_info(ast, request.language)
        explanation = format_basic_parsing_explanation(basic_info, request.type, request.language)
        
        %{
          explanation: explanation,
          metadata: %{
            type: :basic_parsing_fallback,
            language: request.language,
            symbols_found: length(basic_info.symbols),
            fallback_reason: :llm_unavailable
          },
          confidence: 0.5,
          processing_time: 0
        }
      
      {:error, reason} ->
        Logger.warning("Basic parsing failed: #{inspect(reason)}")
        minimal_response_fallback(request, %{})
    end
  end
  
  defp minimal_response_fallback(request, _context) do
    Logger.debug("Using minimal response fallback")
    
    explanation = case request.type do
      :summary ->
        "This #{request.language} code snippet contains #{count_lines(request.content)} lines of code."
      
      :detailed ->
        """
        This is a #{request.language} code implementation. The code is #{assess_complexity_simple(request.content)} complexity
        with #{count_lines(request.content)} lines.
        
        For a detailed analysis, please try again when the analysis service is available.
        """
      
      :step_by_step ->
        """
        Step-by-step analysis for this #{request.language} code:
        
        1. The code contains #{count_lines(request.content)} lines
        2. Written in #{String.capitalize(to_string(request.language))} programming language
        3. Detailed step-by-step analysis requires the full analysis service
        
        Please try again when the analysis service is available.
        """
      
      _ ->
        """
        Basic information about this #{request.language} code:
        - Lines of code: #{count_lines(request.content)}
        - Language: #{String.capitalize(to_string(request.language))}
        
        A detailed explanation requires the full analysis service.
        """
    end
    
    %{
      explanation: explanation,
      metadata: %{
        type: :minimal_response_fallback,
        language: request.language,
        line_count: count_lines(request.content),
        fallback_reason: :service_unavailable
      },
      confidence: 0.3,
      processing_time: 0
    }
  end
  
  # Helper Functions
  
  defp can_parse_language?(language) do
    language in [:elixir, :erlang, :javascript, :python, :typescript, :rust, :go, :java, :c, :cpp]
  end
  
  defp has_cache?(context) do
    Map.has_key?(context, :cache) and not is_nil(context.cache)
  end
  
  defp is_simple_code?(content) do
    line_count = count_lines(content)
    line_count < 50 and not String.contains?(content, ["class", "module", "defmodule", "struct"])
  end
  
  defp count_lines(content) do
    String.split(content, "\n") |> length()
  end
  
  defp assess_complexity_simple(content) do
    line_count = count_lines(content)
    
    cond do
      line_count < 10 -> "low"
      line_count < 50 -> "medium"
      true -> "high"
    end
  end
  
  defp analyze_code_statically(content, language) do
    case TreeSitterWrapper.parse_with_treesitter(content, language, %{}) do
      {:ok, ast} ->
        analysis = %{
          symbols: extract_symbols_from_ast(ast, language),
          structure: analyze_code_structure(ast, language),
          complexity: estimate_complexity_from_ast(ast),
          patterns: detect_common_patterns(content, language)
        }
        {:ok, analysis}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp extract_symbols_from_ast(_ast, language) do
    # Simplified symbol extraction - would be more sophisticated in practice
    case language do
      :elixir -> ["defmodule", "def", "defp"]
      :javascript -> ["function", "class", "const", "let"]
      :python -> ["def", "class", "import"]
      _ -> []
    end
  end
  
  defp analyze_code_structure(_ast, _language) do
    %{
      functions: 1,
      classes: 0,
      modules: 1
    }
  end
  
  defp estimate_complexity_from_ast(_ast) do
    :medium  # Simplified - would analyze actual AST complexity
  end
  
  defp detect_common_patterns(content, language) do
    patterns = []
    
    patterns = if language == :elixir and String.contains?(content, "GenServer") do
      ["GenServer Pattern" | patterns]
    else
      patterns
    end
    
    patterns = if String.contains?(content, "def test") do
      ["Test Pattern" | patterns]
    else
      patterns
    end
    
    patterns
  end
  
  defp format_static_analysis(analysis, type, language) do
    case type do
      :summary ->
        """
        #{String.capitalize(to_string(language))} code summary:
        - Contains #{length(analysis.symbols)} code elements
        - Complexity: #{analysis.complexity}
        #{if length(analysis.patterns) > 0, do: "- Patterns: #{Enum.join(analysis.patterns, ", ")}", else: ""}
        """
      
      :detailed ->
        """
        ## Static Analysis of #{String.capitalize(to_string(language))} Code
        
        **Structure:**
        - Functions: #{analysis.structure.functions}
        - Classes: #{analysis.structure.classes}  
        - Modules: #{analysis.structure.modules}
        
        **Complexity:** #{analysis.complexity}
        
        #{if length(analysis.patterns) > 0 do
          "**Detected Patterns:**\n" <> Enum.map(analysis.patterns, &"- #{&1}") |> Enum.join("\n")
        else
          ""
        end}
        
        *Note: This analysis was generated using static code analysis as the LLM service is currently unavailable.*
        """
      
      _ ->
        """
        Basic #{String.capitalize(to_string(language))} code analysis:
        - Complexity: #{analysis.complexity}
        - Elements found: #{length(analysis.symbols)}
        """
    end
  end
  
  defp calculate_static_confidence(analysis) do
    base_confidence = 0.7
    
    # Increase confidence based on what we found
    confidence_boost = 0.0
    
    confidence_boost = confidence_boost + if length(analysis.symbols) > 0, do: 0.1, else: 0.0
    confidence_boost = confidence_boost + if length(analysis.patterns) > 0, do: 0.1, else: 0.0
    confidence_boost = confidence_boost + if analysis.complexity != :unknown, do: 0.05, else: 0.0
    
    min(1.0, base_confidence + confidence_boost)
  end
  
  defp get_fallback_template(type, language) do
    base_templates = %{
      summary: "This #{language} code appears to be a code implementation with {{line_count}} lines.",
      detailed: """
      ## #{String.capitalize(to_string(language))} Code Analysis
      
      This code implementation contains {{line_count}} lines of #{language} code.
      The code appears to be {{complexity}} complexity based on its structure.
      
      *Note: Detailed analysis is limited while the full analysis service is unavailable.*
      """,
      step_by_step: """
      ## Step-by-Step Analysis
      
      1. This is a #{language} code file
      2. Contains {{line_count}} lines of code
      3. Appears to be {{complexity}} complexity
      
      *Note: Detailed step-by-step analysis requires the full analysis service.*
      """
    }
    
    Map.get(base_templates, type, base_templates.summary)
  end
  
  defp render_fallback_template(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
  
  defp find_similar_cached_explanation(_request, nil), do: {:error, :no_cache}
  defp find_similar_cached_explanation(_request, _cache) do
    # Simplified - would implement similarity matching
    {:error, :no_similar_found}
  end
  
  defp adapt_cached_explanation(explanation, language, type) do
    adapted = explanation
    |> String.replace(~r/\b\w+\s+code\b/, "#{language} code")
    |> add_adaptation_note(type)
    
    adapted
  end
  
  defp add_adaptation_note(explanation, _type) do
    explanation <> "\n\n*Note: This explanation has been adapted from similar code analysis.*"
  end
  
  defp extract_basic_info(_ast, _language) do
    %{
      symbols: ["function", "variable"],
      line_count: 10,
      complexity: :medium
    }
  end
  
  defp format_basic_parsing_explanation(info, type, language) do
    case type do
      :summary ->
        "#{String.capitalize(to_string(language))} code with #{info.line_count} lines, #{info.complexity} complexity."
      
      _ ->
        """
        ## Basic #{String.capitalize(to_string(language))} Code Information
        
        - Lines: #{info.line_count}
        - Complexity: #{info.complexity}
        - Elements: #{length(info.symbols)}
        
        *Note: Limited analysis available while full service is unavailable.*
        """
    end
  end
end