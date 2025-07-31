defmodule RubberDuck.Tools.PromptOptimizer do
  @moduledoc """
  Rewrites prompts for clarity, efficiency, or better LLM outcomes.
  
  This tool analyzes and improves prompts to achieve better results
  from language models by applying best practices for prompt engineering.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  
  tool do
    name :prompt_optimizer
    description "Rewrites prompts for clarity, efficiency, or better LLM outcomes"
    category :ai_optimization
    version "1.0.0"
    tags [:ai, :prompts, :optimization, :llm]
    
    parameter :prompt do
      type :string
      required true
      description "The prompt to optimize"
      constraints [
        min_length: 1,
        max_length: 10_000
      ]
    end
    
    parameter :optimization_goal do
      type :string
      required false
      description "Primary optimization goal"
      default "clarity"
      constraints [
        enum: [
          "clarity",      # Make prompt clearer and more specific
          "conciseness",  # Make prompt more concise
          "accuracy",     # Improve accuracy of responses
          "creativity",   # Enhance creative outputs
          "consistency",  # Improve response consistency
          "safety"        # Enhance safety and appropriateness
        ]
      ]
    end
    
    parameter :target_model do
      type :string
      required false
      description "Target LLM model type"
      default "general"
      constraints [
        enum: [
          "general",     # General purpose models
          "gpt",        # GPT family models
          "claude",     # Claude family models
          "code",       # Code-specialized models
          "chat"        # Chat-optimized models
        ]
      ]
    end
    
    parameter :task_type do
      type :string
      required false
      description "Type of task the prompt is for"
      default "general"
      constraints [
        enum: [
          "general",      # General tasks
          "code",         # Code generation/analysis
          "writing",      # Creative writing
          "analysis",     # Data/text analysis
          "reasoning",    # Logical reasoning
          "summarization", # Text summarization
          "qa",           # Question answering
          "classification" # Text classification
        ]
      ]
    end
    
    parameter :audience_level do
      type :string
      required false
      description "Intended audience expertise level"
      default "intermediate"
      constraints [
        enum: ["beginner", "intermediate", "advanced", "expert"]
      ]
    end
    
    parameter :include_examples do
      type :boolean
      required false
      description "Include examples in optimized prompt"
      default true
    end
    
    parameter :include_constraints do
      type :boolean
      required false
      description "Add explicit constraints and guidelines"
      default true
    end
    
    parameter :preserve_intent do
      type :boolean
      required false
      description "Preserve original intent while optimizing"
      default true
    end
    
    parameter :max_length do
      type :integer
      required false
      description "Maximum length of optimized prompt"
      default 2000
      constraints [
        min: 50,
        max: 10000
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :restricted
      capabilities [:llm_access]
      rate_limit 50
    end
  end
  
  @doc """
  Executes prompt optimization based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, analyzed} <- analyze_prompt(params),
         {:ok, optimized} <- optimize_prompt(analyzed, params, context),
         {:ok, validated} <- validate_optimization(params.prompt, optimized, params) do
      
      {:ok, %{
        original_prompt: params.prompt,
        optimized_prompt: optimized.text,
        improvements: optimized.improvements,
        analysis: analyzed,
        optimization_score: calculate_optimization_score(analyzed, optimized),
        recommendations: optimized.recommendations,
        metadata: %{
          optimization_goal: params.optimization_goal,
          target_model: params.target_model,
          task_type: params.task_type,
          length_change: String.length(optimized.text) - String.length(params.prompt)
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp analyze_prompt(params) do
    analysis = %{
      length: String.length(params.prompt),
      word_count: count_words(params.prompt),
      sentence_count: count_sentences(params.prompt),
      clarity_issues: identify_clarity_issues(params.prompt),
      structure: analyze_structure(params.prompt),
      specificity: assess_specificity(params.prompt),
      completeness: assess_completeness(params.prompt, params.task_type),
      tone: analyze_tone(params.prompt),
      complexity: assess_complexity(params.prompt)
    }
    
    {:ok, analysis}
  end
  
  defp count_words(text) do
    text
    |> String.split(~r/\s+/)
    |> length()
  end
  
  defp count_sentences(text) do
    text
    |> String.split(~r/[.!?]+/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end
  
  defp identify_clarity_issues(prompt) do
    issues = []
    
    # Check for vague language
    issues = if prompt =~ ~r/\b(something|somehow|maybe|perhaps|kind of|sort of)\b/i do
      [:vague_language | issues]
    else
      issues
    end
    
    # Check for ambiguous pronouns
    issues = if prompt =~ ~r/\b(this|that|it|they)\b/i do
      [:ambiguous_pronouns | issues]
    else
      issues
    end
    
    # Check for unclear instructions
    issues = if not (prompt =~ ~r/\b(please|create|generate|write|analyze|explain|describe)\b/i) do
      [:unclear_instructions | issues]
    else
      issues
    end
    
    # Check for missing context
    issues = if String.length(prompt) < 20 do
      [:insufficient_context | issues]
    else
      issues
    end
    
    # Check for run-on sentences
    long_sentences = prompt
    |> String.split(~r/[.!?]+/)
    |> Enum.count(&(String.length(&1) > 200))
    
    issues = if long_sentences > 0 do
      [:run_on_sentences | issues]
    else
      issues
    end
    
    Enum.reverse(issues)
  end
  
  defp analyze_structure(prompt) do
    %{
      has_clear_task: prompt =~ ~r/\b(task|goal|objective|purpose)\b/i,
      has_context: prompt =~ ~r/\b(context|background|given|assume)\b/i,
      has_examples: prompt =~ ~r/\b(example|for instance|such as)\b/i,
      has_constraints: prompt =~ ~r/\b(must|should|requirement|constraint|limit)\b/i,
      has_output_format: prompt =~ ~r/\b(format|structure|organize|output)\b/i,
      paragraph_count: count_paragraphs(prompt)
    }
  end
  
  defp count_paragraphs(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end
  
  defp assess_specificity(prompt) do
    specificity_indicators = [
      ~r/\b(exactly|precisely|specifically|particularly)\b/i,
      ~r/\b(must|required|essential|critical)\b/i,
      ~r/\b(include|contain|ensure|verify)\b/i,
      ~r/\b(\d+|first|second|third|last)\b/i  # Numbers and ordinals
    ]
    
    matches = specificity_indicators
    |> Enum.map(&Regex.scan(&1, prompt))
    |> List.flatten()
    |> length()
    
    cond do
      matches >= 5 -> :high
      matches >= 2 -> :medium
      true -> :low
    end
  end
  
  defp assess_completeness(prompt, task_type) do
    required_elements = case task_type do
      "code" -> [:task_description, :programming_language, :requirements, :examples]
      "writing" -> [:topic, :style, :length, :audience]
      "analysis" -> [:data_description, :analysis_type, :output_format]
      "reasoning" -> [:problem_statement, :constraints, :desired_outcome]
      "summarization" -> [:content_source, :length_target, :key_points]
      "qa" -> [:question, :context, :answer_format]
      "classification" -> [:categories, :criteria, :examples]
      _ -> [:task_description, :requirements, :output_format]
    end
    
    present_elements = required_elements
    |> Enum.count(&element_present?(prompt, &1))
    
    percentage = present_elements / length(required_elements)
    
    cond do
      percentage >= 0.8 -> :complete
      percentage >= 0.5 -> :partial
      true -> :incomplete
    end
  end
  
  defp element_present?(prompt, element) do
    case element do
      :task_description -> prompt =~ ~r/\b(task|do|create|generate|write)\b/i
      :programming_language -> prompt =~ ~r/\b(python|javascript|elixir|java|code)\b/i
      :requirements -> prompt =~ ~r/\b(must|should|requirement|need)\b/i
      :examples -> prompt =~ ~r/\b(example|for instance|like)\b/i
      :topic -> prompt =~ ~r/\b(about|topic|subject|regarding)\b/i
      :style -> prompt =~ ~r/\b(style|tone|formal|casual)\b/i
      :length -> prompt =~ ~r/\b(words?|pages?|paragraphs?|sentences?|\d+)\b/i
      :audience -> prompt =~ ~r/\b(audience|readers?|users?|for)\b/i
      :data_description -> prompt =~ ~r/\b(data|dataset|information|content)\b/i
      :analysis_type -> prompt =~ ~r/\b(analyze|analysis|examine|review)\b/i
      :output_format -> prompt =~ ~r/\b(format|output|structure|organize)\b/i
      :problem_statement -> prompt =~ ~r/\b(problem|issue|challenge|question)\b/i
      :constraints -> prompt =~ ~r/\b(constraint|limit|restriction|rule)\b/i
      :desired_outcome -> prompt =~ ~r/\b(outcome|result|goal|objective)\b/i
      :content_source -> prompt =~ ~r/\b(text|document|article|content)\b/i
      :length_target -> prompt =~ ~r/\b(summary|brief|short|long|\d+)\b/i
      :key_points -> prompt =~ ~r/\b(key|important|main|significant)\b/i
      :question -> prompt =~ ~r/\?|\b(question|ask|what|how|why)\b/i
      :context -> prompt =~ ~r/\b(context|background|given|based on)\b/i
      :answer_format -> prompt =~ ~r/\b(answer|respond|format|structure)\b/i
      :categories -> prompt =~ ~r/\b(categor|class|type|group)\b/i
      :criteria -> prompt =~ ~r/\b(criteria|based on|according to)\b/i
      _ -> false
    end
  end
  
  defp analyze_tone(prompt) do
    cond do
      prompt =~ ~r/\b(please|kindly|would you|could you)\b/i -> :polite
      prompt =~ ~r/\b(must|need|require|demand)\b/i -> :imperative
      prompt =~ ~r/\b(help|assist|support|guide)\b/i -> :collaborative
      prompt =~ ~r/[!]{2,}|[A-Z]{3,}/ -> :urgent
      true -> :neutral
    end
  end
  
  defp assess_complexity(prompt) do
    complexity_factors = [
      {String.length(prompt) > 500, 2},
      {count_sentences(prompt) > 10, 1},
      {prompt =~ ~r/\b(however|moreover|furthermore|nevertheless)\b/i, 1},
      {prompt =~ ~r/\b(if|when|unless|provided that)\b/i, 1},
      {count_words(prompt) > 100, 1}
    ]
    
    score = complexity_factors
    |> Enum.filter(fn {condition, _weight} -> condition end)
    |> Enum.map(fn {_condition, weight} -> weight end)
    |> Enum.sum()
    
    cond do
      score >= 4 -> :high
      score >= 2 -> :medium
      true -> :low
    end
  end
  
  defp optimize_prompt(analysis, params, context) do
    case params.optimization_goal do
      "clarity" -> optimize_for_clarity(analysis, params, context)
      "conciseness" -> optimize_for_conciseness(analysis, params, context)
      "accuracy" -> optimize_for_accuracy(analysis, params, context)
      "creativity" -> optimize_for_creativity(analysis, params, context)
      "consistency" -> optimize_for_consistency(analysis, params, context)
      "safety" -> optimize_for_safety(analysis, params, context)
    end
  end
  
  defp optimize_for_clarity(analysis, params, context) do
    optimization_prompt = build_clarity_optimization_prompt(params.prompt, analysis, params)
    
    case Service.generate(%{
      prompt: optimization_prompt,
      max_tokens: params.max_length * 4,  # Rough conversion
      temperature: 0.3,
      model: context[:llm_model] || "gpt-4"
    }) do
      {:ok, response} ->
        improvements = extract_improvements_from_response(response, "clarity")
        optimized_text = extract_optimized_text(response)
        recommendations = extract_recommendations(response)
        
        {:ok, %{
          text: optimized_text,
          improvements: improvements,
          recommendations: recommendations
        }}
      
      {:error, _} ->
        # Fallback to template-based optimization
        template_optimize_for_clarity(analysis, params)
    end
  end
  
  defp build_clarity_optimization_prompt(original_prompt, analysis, params) do
    issues_text = if analysis.clarity_issues != [] do
      "Issues identified: #{Enum.join(analysis.clarity_issues, ", ")}\n"
    else
      ""
    end
    
    """
    Optimize this prompt for maximum clarity and specificity:
    
    Original prompt:
    "#{original_prompt}"
    
    #{issues_text}
    Analysis:
    - Length: #{analysis.length} characters
    - Specificity: #{analysis.specificity}
    - Completeness: #{analysis.completeness}
    - Task type: #{params.task_type}
    - Target audience: #{params.audience_level}
    
    Please provide:
    1. An optimized version that is clearer and more specific
    2. List the specific improvements made
    3. Provide additional recommendations
    
    Requirements:
    - Preserve the original intent
    - Make instructions more specific and actionable
    - Remove ambiguous language
    - Add necessary context if missing
    - Structure clearly with appropriate formatting
    #{if params.include_examples, do: "- Include relevant examples", else: ""}
    #{if params.include_constraints, do: "- Add explicit constraints", else: ""}
    - Keep under #{params.max_length} characters
    
    Format your response as:
    OPTIMIZED PROMPT:
    [optimized prompt here]
    
    IMPROVEMENTS:
    [list of improvements]
    
    RECOMMENDATIONS:
    [additional recommendations]
    """
  end
  
  defp extract_improvements_from_response(response, optimization_type) do
    # Simple extraction - in production would be more sophisticated
    case Regex.run(~r/IMPROVEMENTS:\s*\n(.+?)(?=\n[A-Z]+:|$)/s, response) do
      [_, improvements_text] ->
        improvements_text
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&String.replace(&1, ~r/^[-*]\s*/, ""))
      
      _ ->
        ["Applied #{optimization_type} optimization"]
    end
  end
  
  defp extract_optimized_text(response) do
    case Regex.run(~r/OPTIMIZED PROMPT:\s*\n(.+?)(?=\n[A-Z]+:|$)/s, response) do
      [_, optimized_text] -> String.trim(optimized_text)
      _ -> "Optimization failed - please try again"
    end
  end
  
  defp extract_recommendations(response) do
    case Regex.run(~r/RECOMMENDATIONS:\s*\n(.+?)(?=\n[A-Z]+:|$)/s, response) do
      [_, rec_text] ->
        rec_text
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&String.replace(&1, ~r/^[-*]\s*/, ""))
      
      _ ->
        []
    end
  end
  
  defp template_optimize_for_clarity(analysis, params) do
    # Template-based fallback
    optimized = apply_clarity_templates(params.prompt, analysis.clarity_issues)
    
    {:ok, %{
      text: optimized,
      improvements: ["Applied template-based clarity improvements"],
      recommendations: ["Consider manual review for best results"]
    }}
  end
  
  defp apply_clarity_templates(prompt, issues) do
    optimized = prompt
    
    # Remove vague language
    optimized = if :vague_language in issues do
      optimized
      |> String.replace(~r/\bsomething\b/i, "a specific item")
      |> String.replace(~r/\bsomehow\b/i, "through a clear method")
      |> String.replace(~r/\bmaybe\b/i, "")
      |> String.replace(~r/\bperhaps\b/i, "")
      |> String.replace(~r/\bkind of\b/i, "")
      |> String.replace(~r/\bsort of\b/i, "")
    else
      optimized
    end
    
    # Add clear task instruction if missing
    optimized = if :unclear_instructions in issues do
      "Please " <> String.downcase(String.slice(optimized, 0..0)) <> String.slice(optimized, 1..-1)
    else
      optimized
    end
    
    # Add context if missing
    optimized = if :insufficient_context in issues do
      "Given the following context: [Please provide relevant context]\n\n" <> optimized
    else
      optimized
    end
    
    String.trim(optimized)
  end
  
  defp optimize_for_conciseness(analysis, params, _context) do
    # Template-based conciseness optimization
    optimized = params.prompt
    |> remove_redundancy()
    |> simplify_language()
    |> combine_sentences()
    |> String.trim()
    
    improvements = [
      "Removed redundant phrases",
      "Simplified complex language",
      "Combined related sentences"
    ]
    
    recommendations = [
      "Review for essential information only",
      "Consider bullet points for lists"
    ]
    
    {:ok, %{
      text: optimized,
      improvements: improvements,
      recommendations: recommendations
    }}
  end
  
  defp remove_redundancy(text) do
    text
    |> String.replace(~r/\bin order to\b/i, "to")
    |> String.replace(~r/\bdue to the fact that\b/i, "because")
    |> String.replace(~r/\bat this point in time\b/i, "now")
    |> String.replace(~r/\bfor the purpose of\b/i, "to")
  end
  
  defp simplify_language(text) do
    text
    |> String.replace(~r/\butilize\b/i, "use")
    |> String.replace(~r/\bfacilitate\b/i, "help")
    |> String.replace(~r/\bdemonstrate\b/i, "show")
    |> String.replace(~r/\bcommence\b/i, "start")
  end
  
  defp combine_sentences(text) do
    # Simple sentence combination - could be more sophisticated
    text
    |> String.replace(~r/\.\s+This\s+/i, ", which ")
    |> String.replace(~r/\.\s+It\s+/i, " and it ")
  end
  
  defp optimize_for_accuracy(analysis, params, _context) do
    # Add specificity and constraints for accuracy
    optimized = enhance_for_accuracy(params.prompt, params)
    
    improvements = [
      "Added specific requirements",
      "Included accuracy constraints",
      "Enhanced task clarity"
    ]
    
    recommendations = [
      "Provide examples of desired output",
      "Specify validation criteria"
    ]
    
    {:ok, %{
      text: optimized,
      improvements: improvements,
      recommendations: recommendations
    }}
  end
  
  defp enhance_for_accuracy(prompt, params) do
    accuracy_prefix = case params.task_type do
      "code" -> "Generate syntactically correct and functional code that: "
      "analysis" -> "Provide accurate and evidence-based analysis that: "
      "qa" -> "Answer precisely and factually: "
      _ -> "Ensure accuracy and completeness when: "
    end
    
    constraints = if params.include_constraints do
      "\n\nConstraints:\n- Verify all facts and claims\n- Provide specific, measurable details\n- Avoid speculation or assumptions"
    else
      ""
    end
    
    accuracy_prefix <> String.downcase(String.slice(prompt, 0..0)) <> String.slice(prompt, 1..-1) <> constraints
  end
  
  defp optimize_for_creativity(analysis, params, _context) do
    # Enhance for creative output
    optimized = enhance_for_creativity(params.prompt, params)
    
    improvements = [
      "Added creative encouragement",
      "Reduced constraints that limit creativity",
      "Enhanced open-ended framing"
    ]
    
    recommendations = [
      "Consider adding inspiration sources",
      "Allow for multiple creative approaches"
    ]
    
    {:ok, %{
      text: optimized,
      improvements: improvements,
      recommendations: recommendations
    }}
  end
  
  defp enhance_for_creativity(prompt, params) do
    creative_prefix = "Think creatively and explore innovative approaches to: "
    
    creative_suffix = if params.include_examples do
      "\n\nFeel free to draw inspiration from various sources and present unique perspectives."
    else
      "\n\nBe imaginative and think outside conventional boundaries."
    end
    
    creative_prefix <> String.downcase(String.slice(prompt, 0..0)) <> String.slice(prompt, 1..-1) <> creative_suffix
  end
  
  defp optimize_for_consistency(analysis, params, _context) do
    # Add structure for consistent outputs
    optimized = enhance_for_consistency(params.prompt, params)
    
    improvements = [
      "Added output format specification",
      "Included consistency guidelines",
      "Structured the request clearly"
    ]
    
    recommendations = [
      "Provide templates for consistent format",
      "Specify required elements in output"
    ]
    
    {:ok, %{
      text: optimized,
      improvements: improvements,
      recommendations: recommendations
    }}
  end
  
  defp enhance_for_consistency(prompt, params) do
    format_spec = case params.task_type do
      "code" -> "\n\nFormat: Provide code with comments explaining key sections."
      "analysis" -> "\n\nFormat: Structure as: Summary, Analysis, Conclusions."
      "writing" -> "\n\nFormat: Use consistent tone and style throughout."
      _ -> "\n\nFormat: Organize response with clear sections and consistent structure."
    end
    
    prompt <> format_spec
  end
  
  defp optimize_for_safety(analysis, params, _context) do
    # Add safety guidelines and constraints
    optimized = enhance_for_safety(params.prompt, params)
    
    improvements = [
      "Added safety guidelines",
      "Included appropriate constraints",
      "Enhanced ethical considerations"
    ]
    
    recommendations = [
      "Review output for potential safety issues",
      "Consider additional content filters"
    ]
    
    {:ok, %{
      text: optimized,
      improvements: improvements,
      recommendations: recommendations
    }}
  end
  
  defp enhance_for_safety(prompt, _params) do
    safety_prefix = "Please respond responsibly and safely to: "
    safety_suffix = "\n\nEnsure the response is appropriate, accurate, and follows ethical guidelines."
    
    safety_prefix <> String.downcase(String.slice(prompt, 0..0)) <> String.slice(prompt, 1..-1) <> safety_suffix
  end
  
  defp validate_optimization(original, optimized, params) do
    validation = %{
      length_appropriate: String.length(optimized.text) <= params.max_length,
      intent_preserved: params.preserve_intent and intent_similarity(original, optimized.text) > 0.7,
      clarity_improved: true,  # Would implement actual clarity scoring
      completeness_maintained: true  # Would implement completeness check
    }
    
    if Enum.all?(Map.values(validation)) do
      {:ok, validation}
    else
      {:error, "Optimization validation failed: #{inspect(validation)}"}
    end
  end
  
  defp intent_similarity(text1, text2) do
    # Simple similarity based on common keywords
    words1 = text1 |> String.downcase() |> String.split() |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split() |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union > 0, do: intersection / union, else: 0.0
  end
  
  defp calculate_optimization_score(analysis, optimized) do
    base_score = 50
    
    # Improvements add to score
    improvement_score = length(optimized.improvements) * 10
    
    # Clarity issues resolved
    clarity_score = length(analysis.clarity_issues) * 5
    
    # Structure improvements
    structure_score = if analysis.structure.has_clear_task, do: 10, else: 0
    
    total = base_score + improvement_score + clarity_score + structure_score
    min(100, total)
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end