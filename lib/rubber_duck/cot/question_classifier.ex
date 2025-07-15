defmodule RubberDuck.CoT.QuestionClassifier do
  @moduledoc """
  Classifies questions to determine if they need Chain-of-Thought reasoning
  or can be answered directly by the LLM.
  
  This module analyzes user messages to detect:
  - Simple factual questions
  - Basic code explanations
  - Straightforward requests
  - Complex problems requiring reasoning
  
  Simple questions bypass CoT for faster responses.
  """
  
  require Logger
  
  @type classification :: :simple | :complex
  @type question_type :: :factual | :basic_code | :straightforward | :complex_problem | :multi_step
  
  @simple_patterns [
    # Direct questions
    ~r/^what\s+is\s+/i,
    ~r/^how\s+do\s+i\s+/i,
    ~r/^where\s+is\s+/i,
    ~r/^when\s+/i,
    ~r/^why\s+/i,
    ~r/^who\s+/i,
    
    # Single concept explanations
    ~r/^explain\s+\w+$/i,
    ~r/^define\s+\w+$/i,
    ~r/^what\s+does\s+\w+\s+mean/i,
    
    # Simple code questions
    ~r/^how\s+to\s+\w+\s+in\s+\w+$/i,
    ~r/^syntax\s+for\s+/i,
    ~r/^example\s+of\s+/i,
    
    # Status/version questions
    ~r/^what\s+version\s+/i,
    ~r/^which\s+\w+\s+should\s+i\s+use/i,
    ~r/^is\s+\w+\s+better\s+than\s+\w+/i
  ]
  
  @complex_indicators [
    # Multi-step processes
    "step by step",
    "walkthrough",
    "implementation",
    "architecture",
    "design pattern",
    "best approach",
    "optimize",
    "refactor",
    "debug",
    "troubleshoot",
    "analyze",
    "compare and contrast",
    "pros and cons",
    "trade-offs",
    
    # Problem-solving keywords
    "problem",
    "issue",
    "error",
    "bug",
    "not working",
    "failed",
    "help me with",
    "how can I",
    "what's wrong",
    
    # Complex code operations
    "generate code",
    "create function",
    "build system",
    "implement feature",
    "write test",
    "review code",
    "suggest improvements",
    
    # System design and architecture
    "distributed system",
    "fault tolerance",
    "scalable",
    "microservices",
    "load balancing",
    "performance",
    "concurrent",
    "parallel",
    "real-time",
    
    # Advanced programming concepts
    "algorithm",
    "data structure",
    "complexity",
    "optimization",
    "design pattern",
    "concurrency",
    "async",
    "streaming"
  ]
  
  @simple_indicators [
    # Basic factual requests
    "what is",
    "define",
    "explain",
    "meaning of",
    "definition",
    "syntax",
    "example",
    "usage",
    
    # Quick references
    "command for",
    "shortcut",
    "version",
    "documentation",
    "docs",
    "reference",
    "cheat sheet"
  ]
  
  @doc """
  Classifies a question as simple or complex.
  
  Returns:
  - `:simple` for questions that can be answered directly by LLM
  - `:complex` for questions requiring Chain-of-Thought reasoning
  """
  @spec classify(String.t(), map()) :: classification()
  def classify(question, context \\ %{}) do
    question_type = determine_question_type(question, context)
    
    case question_type do
      type when type in [:factual, :basic_code, :straightforward] ->
        Logger.debug("[QuestionClassifier] Classified as simple: #{type}")
        :simple
        
      type when type in [:complex_problem, :multi_step] ->
        Logger.debug("[QuestionClassifier] Classified as complex: #{type}")
        :complex
        
      _ ->
        Logger.debug("[QuestionClassifier] Defaulting to complex classification")
        :complex
    end
  end
  
  @doc """
  Determines the specific type of question.
  """
  @spec determine_question_type(String.t(), map()) :: question_type()
  def determine_question_type(question, context \\ %{}) do
    clean_question = String.trim(question)
    question_lower = String.downcase(clean_question)
    
    cond do
      # Check for complex indicators first (override simple patterns)
      has_complex_indicators?(question_lower) ->
        :complex_problem
        
      # Check for code blocks or multiple sentences
      has_code_blocks?(clean_question) or has_multiple_sentences?(clean_question) ->
        :complex_problem
        
      # Check conversation context
      is_multi_step_from_context?(context) ->
        :multi_step
        
      # Questions longer than 100 characters are likely complex
      String.length(clean_question) > 100 ->
        :complex_problem
        
      # Check for simple patterns only after excluding complex ones
      matches_simple_pattern?(clean_question) ->
        :factual
        
      # Check message length - very short questions are usually simple
      String.length(clean_question) < 50 and has_simple_indicators?(question_lower) ->
        :basic_code
        
      # Default to straightforward for remaining short questions
      String.length(clean_question) < 100 ->
        :straightforward
        
      # Default to complex for anything else
      true ->
        :complex_problem
    end
  end
  
  @doc """
  Provides reasoning for why a question was classified a certain way.
  """
  @spec explain_classification(String.t(), map()) :: String.t()
  def explain_classification(question, context \\ %{}) do
    classification = classify(question, context)
    question_type = determine_question_type(question, context)
    
    case {classification, question_type} do
      {:simple, :factual} ->
        "Simple factual question matching known patterns"
        
      {:simple, :basic_code} ->
        "Basic code question with simple indicators"
        
      {:simple, :straightforward} ->
        "Straightforward question under 100 characters"
        
      {:complex, :complex_problem} ->
        "Complex problem requiring step-by-step reasoning"
        
      {:complex, :multi_step} ->
        "Multi-step process indicated by conversation context"
        
      _ ->
        "Defaulted to complex classification for safety"
    end
  end
  
  @doc """
  Returns statistics about classification patterns.
  """
  @spec get_classification_stats() :: map()
  def get_classification_stats do
    %{
      simple_patterns: length(@simple_patterns),
      complex_indicators: length(@complex_indicators),
      simple_indicators: length(@simple_indicators),
      classification_types: [:factual, :basic_code, :straightforward, :complex_problem, :multi_step]
    }
  end
  
  # Private helper functions
  
  defp matches_simple_pattern?(question) do
    Enum.any?(@simple_patterns, fn pattern ->
      Regex.match?(pattern, question)
    end)
  end
  
  defp has_simple_indicators?(question_lower) do
    Enum.any?(@simple_indicators, fn indicator ->
      String.contains?(question_lower, indicator)
    end)
  end
  
  defp has_complex_indicators?(question_lower) do
    Enum.any?(@complex_indicators, fn indicator ->
      String.contains?(question_lower, indicator)
    end)
  end
  
  defp is_multi_step_from_context?(context) do
    # Check if previous messages indicate a multi-step process
    messages = Map.get(context, :messages, [])
    message_count = Map.get(context, :message_count, 0)
    
    # Multi-step if conversation has multiple exchanges
    message_count > 4 or
    Enum.any?(messages, fn msg ->
      content = get_message_content(msg)
      String.contains?(String.downcase(content), ["follow up", "next step", "continue", "also"])
    end)
  end
  
  defp has_code_blocks?(question) do
    String.contains?(question, "```") or 
    String.contains?(question, "`") or
    Regex.match?(~r/\w+\(\)/, question)
  end
  
  defp has_multiple_sentences?(question) do
    # Count sentences by periods, question marks, exclamation marks
    sentences = String.split(question, ~r/[.!?]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    length(sentences) > 1
  end
  
  defp get_message_content(msg) when is_map(msg) do
    Map.get(msg, "content", "") || Map.get(msg, :content, "")
  end
  defp get_message_content(_), do: ""
end