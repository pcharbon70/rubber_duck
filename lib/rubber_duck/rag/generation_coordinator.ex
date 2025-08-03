defmodule RubberDuck.RAG.GenerationCoordinator do
  @moduledoc """
  Coordinates generation phase of the RAG pipeline.
  
  Handles prompt construction, quality assessment, and integration
  with LLM services for response generation.
  """

  alias RubberDuck.RAG.AugmentedContext

  @default_templates %{
    "default" => """
    Based on the following context, please provide a helpful and accurate response.
    
    Context:
    <%= context %>
    
    Question: <%= query %>
    
    Response:
    """,
    
    "technical" => """
    You are a technical expert. Based on the following technical documentation and references, 
    provide a detailed and accurate technical response.
    
    Technical Context:
    <%= context %>
    
    Technical Question: <%= query %>
    
    Please provide a comprehensive technical answer with examples where appropriate:
    """,
    
    "conversational" => """
    Here's some relevant information that might help answer your question:
    
    <%= context %>
    
    Your question: <%= query %>
    
    Let me explain this in a clear and friendly way:
    """,
    
    "analytical" => """
    Analyze the following information to answer the question comprehensively.
    
    Information Sources:
    <%= context %>
    
    Analysis Question: <%= query %>
    
    Provide a structured analysis covering key points, trade-offs, and recommendations:
    """
  }

  @doc """
  Builds a prompt from template and augmented context.
  """
  def build_prompt(template_name, context, config \\ %{})
  
  def build_prompt(template_name, context, config) when is_binary(template_name) do
    template = get_template(template_name)
    
    prompt_data = %{
      context: format_context_for_prompt(context, config),
      query: config[:query] || "",
      metadata: format_metadata(context.metadata)
    }
    
    rendered = EEx.eval_string(template, assigns: prompt_data)
    
    # Apply token limits if specified
    if config[:max_prompt_length] do
      truncate_prompt(rendered, config[:max_prompt_length])
    else
      rendered
    end
  end

  def build_prompt(custom_template, context, config) when is_function(custom_template) do
    custom_template.(context, config)
  end

  @doc """
  Assesses the quality of a generated response.
  """
  def assess_quality(response, context) do
    scores = %{
      relevance: assess_relevance(response, context),
      completeness: assess_completeness(response),
      coherence: assess_coherence(response),
      accuracy: assess_accuracy(response, context)
    }
    
    # Weighted average
    weights = %{relevance: 0.4, completeness: 0.2, coherence: 0.2, accuracy: 0.2}
    
    total_score = Enum.reduce(scores, 0.0, fn {metric, score}, acc ->
      acc + score * weights[metric]
    end)
    
    %{
      total_score: Float.round(total_score, 2),
      scores: scores,
      passed: total_score >= 0.7
    }
  end

  @doc """
  Constructs a prompt for a specific generation strategy.
  """
  def build_strategic_prompt(strategy, context, query) do
    case strategy do
      :comprehensive ->
        build_comprehensive_prompt(context, query)
        
      :concise ->
        build_concise_prompt(context, query)
        
      :step_by_step ->
        build_step_by_step_prompt(context, query)
        
      :comparative ->
        build_comparative_prompt(context, query)
        
      _ ->
        build_prompt("default", context, %{query: query})
    end
  end

  @doc """
  Formats generation parameters for LLM service.
  """
  def format_generation_params(prompt, config) do
    %{
      prompt: prompt,
      max_tokens: config[:max_tokens] || 2000,
      temperature: config[:temperature] || 0.7,
      top_p: config[:top_p] || 0.9,
      frequency_penalty: config[:frequency_penalty] || 0.0,
      presence_penalty: config[:presence_penalty] || 0.0,
      stop_sequences: config[:stop_sequences] || [],
      stream: config[:streaming] || false
    }
  end

  @doc """
  Post-processes generated response.
  """
  def post_process_response(response, context) do
    response
    |> clean_response()
    |> add_citations(context)
    |> format_output()
  end

  # Private functions

  defp get_template(name) do
    @default_templates[name] || @default_templates["default"]
  end

  defp format_context_for_prompt(context, config) do
    format_style = config[:context_format] || :numbered
    
    case format_style do
      :numbered ->
        context.documents
        |> Enum.with_index(1)
        |> Enum.map(fn {doc, idx} ->
          "[#{idx}] #{doc.content}"
        end)
        |> Enum.join("\n\n")
        
      :sourced ->
        context.documents
        |> Enum.group_by(& &1.source)
        |> Enum.map(fn {source, docs} ->
          content = Enum.map(docs, & &1.content) |> Enum.join("\n")
          "Source: #{source}\n#{content}"
        end)
        |> Enum.join("\n\n---\n\n")
        
      :flat ->
        context.documents
        |> Enum.map(& &1.content)
        |> Enum.join("\n\n")
        
      _ ->
        AugmentedContext.to_prompt_format(context)
    end
  end

  defp format_metadata(metadata) do
    if map_size(metadata) > 0 do
      metadata
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join(", ")
    else
      ""
    end
  end

  defp truncate_prompt(prompt, max_length) do
    if String.length(prompt) <= max_length do
      prompt
    else
      # Try to truncate at a sentence boundary
      truncated = String.slice(prompt, 0, max_length - 100)
      
      # Find last complete sentence
      case Regex.scan(~r/[.!?]\s/, truncated) do
        [] -> truncated <> "..."
        matches ->
          last_match = List.last(matches) |> hd()
          last_pos = :binary.match(truncated, last_match) |> elem(0)
          String.slice(prompt, 0, last_pos + 1)
      end
    end
  end

  defp assess_relevance(response, context) do
    # Check if response references context content
    context_terms = extract_key_terms(context)
    response_lower = String.downcase(response)
    
    matching_terms = Enum.count(context_terms, fn term ->
      String.contains?(response_lower, term)
    end)
    
    min(matching_terms / max(length(context_terms), 1), 1.0)
  end

  defp assess_completeness(response) do
    # Check response length and structure
    word_count = length(String.split(response))
    
    cond do
      word_count < 20 -> 0.2
      word_count < 50 -> 0.5
      word_count < 100 -> 0.7
      word_count < 300 -> 0.9
      true -> 1.0
    end
  end

  defp assess_coherence(response) do
    # Simple coherence check based on sentence structure
    sentences = String.split(response, ~r/[.!?]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    if length(sentences) == 0 do
      0.0
    else
      # Check for proper sentence structure
      valid_sentences = Enum.count(sentences, fn sentence ->
        words = String.split(sentence)
        length(words) >= 3 and String.match?(hd(words), ~r/^[A-Z]/)
      end)
      
      valid_sentences / length(sentences)
    end
  end

  defp assess_accuracy(_response, _context) do
    # Check if response contradicts context
    # This is simplified - in production, use NLI models
    
    # For now, give high score if no obvious contradictions
    0.8
  end

  defp extract_key_terms(context) do
    context.documents
    |> Enum.flat_map(fn doc ->
      doc.content
      |> String.downcase()
      |> String.split()
      |> Enum.filter(fn word ->
        String.length(word) > 4 and not common_word?(word)
      end)
    end)
    |> Enum.uniq()
    |> Enum.take(20)
  end

  defp common_word?(word) do
    common = ~w(about after before being below above along among within without 
                through during toward against between beneath beside besides)
    word in common
  end

  defp build_comprehensive_prompt(context, query) do
    """
    Please provide a comprehensive analysis based on the following information.
    
    Context from #{length(context.documents)} sources:
    #{AugmentedContext.to_prompt_format(context, :structured)}
    
    Question: #{query}
    
    Provide a detailed response covering:
    1. Direct answer to the question
    2. Supporting evidence from the context
    3. Any relevant additional considerations
    4. Potential limitations or caveats
    """
  end

  defp build_concise_prompt(context, query) do
    """
    Based on this context, provide a brief and direct answer:
    
    #{AugmentedContext.to_prompt_format(context, :flat)}
    
    Question: #{query}
    
    Answer concisely in 2-3 sentences:
    """
  end

  defp build_step_by_step_prompt(context, query) do
    """
    Using the following information, provide a step-by-step answer:
    
    #{AugmentedContext.to_prompt_format(context, :numbered)}
    
    Question: #{query}
    
    Break down your response into clear steps:
    """
  end

  defp build_comparative_prompt(context, query) do
    """
    Compare and contrast the information from these sources:
    
    #{AugmentedContext.to_prompt_format(context, :sourced)}
    
    Question: #{query}
    
    Analyze the different perspectives and provide a balanced comparison:
    """
  end

  defp clean_response(response) do
    response
    |> String.trim()
    |> remove_incomplete_sentences()
    |> fix_formatting_issues()
  end

  defp remove_incomplete_sentences(response) do
    # Remove incomplete sentence at the end
    if String.match?(response, ~r/[.!?]$/) do
      response
    else
      # Try to find last complete sentence
      case Regex.scan(~r/[.!?]/, response) do
        [] -> response
        _ ->
          last_complete = response
          |> String.split(~r/[.!?]/)
          |> Enum.drop(-1)
          |> Enum.join(". ")
          
          last_complete <> "."
      end
    end
  end

  defp fix_formatting_issues(response) do
    response
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  defp add_citations(response, context) do
    # Add source citations if not already present
    if String.contains?(response, "[") and String.contains?(response, "]") do
      response
    else
      sources = context.documents
      |> Enum.map(& &1.source)
      |> Enum.uniq()
      |> Enum.join(", ")
      
      response <> "\n\n*Sources: #{sources}*"
    end
  end

  defp format_output(response) do
    # Final formatting for output
    response
    |> ensure_proper_ending()
    |> add_line_breaks()
  end

  defp ensure_proper_ending(response) do
    if String.match?(response, ~r/[.!?*]$/) do
      response
    else
      response <> "."
    end
  end

  defp add_line_breaks(response) do
    # Add line breaks for better readability
    response
    |> String.replace(". ", ".\n")
    |> String.replace("? ", "?\n")
    |> String.replace("! ", "!\n")
    |> String.replace("\n\n", "\n")
    |> String.replace("\n", "\n\n")
  end
end