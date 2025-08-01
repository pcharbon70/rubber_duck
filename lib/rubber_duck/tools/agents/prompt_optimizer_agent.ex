defmodule RubberDuck.Tools.Agents.PromptOptimizerAgent do
  @moduledoc """
  Agent for the PromptOptimizer tool.
  
  Optimizes prompts for better AI model performance through analysis,
  enhancement, and iterative refinement based on effectiveness metrics.
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :prompt_optimizer,
    name: "prompt_optimizer_agent",
    description: "Optimizes prompts for better AI model performance and effectiveness",
    schema: [
      # Optimization history and tracking
      optimization_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 100],
      
      # Performance metrics and analysis
      performance_metrics: [type: :map, default: %{}],
      baseline_metrics: [type: :map, default: %{}],
      
      # Optimization strategies and techniques
      optimization_strategies: [type: :map, default: %{
        clarity_enhancement: %{enabled: true, weight: 0.3},
        specificity_improvement: %{enabled: true, weight: 0.25},
        context_enrichment: %{enabled: true, weight: 0.2},
        instruction_structuring: %{enabled: true, weight: 0.15},
        example_integration: %{enabled: true, weight: 0.1}
      }],
      
      # Templates and patterns
      prompt_templates: [type: :map, default: %{
        code_generation: %{
          structure: "Task: {task}\nContext: {context}\nRequirements: {requirements}\nOutput format: {format}",
          variables: [:task, :context, :requirements, :format]
        },
        analysis: %{
          structure: "Analyze the following {subject}:\n{content}\n\nProvide analysis on: {aspects}",
          variables: [:subject, :content, :aspects]
        },
        explanation: %{
          structure: "Explain {concept} in the context of {domain}.\nAudience: {audience}\nDetail level: {detail_level}",
          variables: [:concept, :domain, :audience, :detail_level]
        }
      }],
      
      # A/B testing and experimentation
      active_experiments: [type: :map, default: %{}],
      experiment_results: [type: {:list, :map}, default: []],
      
      # Model-specific optimizations
      model_profiles: [type: :map, default: %{
        gpt4: %{
          max_tokens: 8000,
          prefers_structured: true,
          responds_to_examples: true,
          instruction_style: :direct
        },
        claude: %{
          max_tokens: 100000,
          prefers_conversational: true,
          responds_to_context: true,
          instruction_style: :collaborative
        },
        gemini: %{
          max_tokens: 32000,
          prefers_detailed: true,
          responds_to_reasoning: true,
          instruction_style: :step_by_step
        }
      }]
    ]
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.AnalyzePromptAction,
      __MODULE__.OptimizePromptAction,
      __MODULE__.ABTestPromptsAction,
      __MODULE__.GenerateVariationsAction,
      __MODULE__.EvaluateEffectivenessAction,
      __MODULE__.ApplyTemplateAction
    ]
  end
  
  # Action modules
  defmodule AnalyzePromptAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_prompt",
      description: "Analyze prompt quality and identify improvement opportunities",
      schema: [
        prompt: [type: :string, required: true],
        analysis_aspects: [
          type: {:list, :atom},
          default: [:clarity, :specificity, :structure, :completeness, :bias],
          doc: "Aspects to analyze"
        ],
        target_model: [type: :atom, required: false],
        context: [type: :map, default: %{}]
      ]
    
    @impl true
    def run(params, agent_context) do
      prompt = params.prompt
      aspects = params.analysis_aspects
      target_model = params.target_model
      context = params.context
      
      analysis_results = Enum.map(aspects, fn aspect ->
        {aspect, analyze_aspect(prompt, aspect, target_model, agent_context)}
      end) |> Map.new()
      
      # Calculate overall score
      overall_score = calculate_overall_score(analysis_results)
      
      # Generate recommendations
      recommendations = generate_recommendations(analysis_results, target_model, agent_context)
      
      {:ok, %{
        prompt: prompt,
        analysis_results: analysis_results,
        overall_score: overall_score,
        recommendations: recommendations,
        target_model: target_model,
        analyzed_at: DateTime.utc_now()
      }}
    end
    
    defp analyze_aspect(prompt, :clarity, _target_model, _context) do
      issues = []
      
      # Check for ambiguous language
      issues = if has_ambiguous_language?(prompt) do
        ["Contains ambiguous or vague language" | issues]
      else
        issues
      end
      
      # Check for overly complex sentences
      issues = if has_complex_sentences?(prompt) do
        ["Contains overly complex sentences" | issues]
      else
        issues
      end
      
      # Check for unclear instructions
      issues = if has_unclear_instructions?(prompt) do
        ["Instructions could be clearer" | issues]
      else
        issues
      end
      
      score = calculate_clarity_score(prompt, issues)
      
      %{
        score: score,
        issues: issues,
        suggestions: generate_clarity_suggestions(issues)
      }
    end
    
    defp analyze_aspect(prompt, :specificity, _target_model, _context) do
      issues = []
      
      # Check for generic language
      issues = if has_generic_language?(prompt) do
        ["Uses generic or non-specific language" | issues]
      else
        issues
      end
      
      # Check for missing constraints
      issues = if missing_constraints?(prompt) do
        ["Missing important constraints or parameters" | issues]
      else
        issues
      end
      
      # Check for undefined terms
      issues = if has_undefined_terms?(prompt) do
        ["Contains undefined or context-dependent terms" | issues]
      else
        issues
      end
      
      score = calculate_specificity_score(prompt, issues)
      
      %{
        score: score,
        issues: issues,
        suggestions: generate_specificity_suggestions(issues)
      }
    end
    
    defp analyze_aspect(prompt, :structure, target_model, context) do
      issues = []
      
      # Check for logical flow
      issues = if poor_logical_flow?(prompt) do
        ["Poor logical flow or organization" | issues]
      else
        issues
      end
      
      # Check for appropriate formatting
      issues = if poor_formatting?(prompt, target_model, context) do
        ["Could benefit from better formatting" | issues]
      else
        issues
      end
      
      # Check for missing sections
      issues = if missing_sections?(prompt) do
        ["Missing important sections (context, examples, constraints)" | issues]
      else
        issues
      end
      
      score = calculate_structure_score(prompt, issues)
      
      %{
        score: score,
        issues: issues,
        suggestions: generate_structure_suggestions(issues, target_model)
      }
    end
    
    defp analyze_aspect(prompt, :completeness, _target_model, _context) do
      issues = []
      
      # Check for missing context
      issues = if missing_context?(prompt) do
        ["Lacks sufficient context" | issues]
      else
        issues
      end
      
      # Check for missing examples
      issues = if missing_examples?(prompt) do
        ["Could benefit from examples" | issues]
      else
        issues
      end
      
      # Check for missing output format specification
      issues = if missing_output_format?(prompt) do
        ["Output format not specified" | issues]
      else
        issues
      end
      
      score = calculate_completeness_score(prompt, issues)
      
      %{
        score: score,
        issues: issues,
        suggestions: generate_completeness_suggestions(issues)
      }
    end
    
    defp analyze_aspect(prompt, :bias, _target_model, _context) do
      issues = []
      
      # Check for leading questions
      issues = if has_leading_questions?(prompt) do
        ["Contains leading or biased questions" | issues]
      else
        issues
      end
      
      # Check for assumptions
      issues = if has_assumptions?(prompt) do
        ["Makes unwarranted assumptions" | issues]
      else
        issues
      end
      
      # Check for inclusive language
      issues = if has_exclusive_language?(prompt) do
        ["Could use more inclusive language" | issues]
      else
        issues
      end
      
      score = calculate_bias_score(prompt, issues)
      
      %{
        score: score,
        issues: issues,
        suggestions: generate_bias_suggestions(issues)
      }
    end
    
    defp analyze_aspect(_prompt, _aspect, _target_model, _context) do
      %{
        score: 0.5,
        issues: ["Analysis not implemented for this aspect"],
        suggestions: []
      }
    end
    
    # Helper functions for analysis
    defp has_ambiguous_language?(prompt) do
      ambiguous_words = ["thing", "stuff", "maybe", "perhaps", "might", "could"]
      Enum.any?(ambiguous_words, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp has_complex_sentences?(prompt) do
      sentences = String.split(prompt, ~r/[.!?]/)
      avg_length = sentences |> Enum.map(&String.length/1) |> Enum.sum() |> div(length(sentences))
      avg_length > 200
    end
    
    defp has_unclear_instructions?(prompt) do
      instruction_keywords = ["please", "try to", "if possible", "maybe"]
      Enum.any?(instruction_keywords, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp has_generic_language?(prompt) do
      generic_terms = ["general", "basic", "simple", "normal", "usual", "typical"]
      count = Enum.count(generic_terms, &String.contains?(String.downcase(prompt), &1))
      count > 2
    end
    
    defp missing_constraints?(prompt) do
      constraint_indicators = ["must", "should", "requirements", "constraints", "format", "length"]
      found = Enum.count(constraint_indicators, &String.contains?(String.downcase(prompt), &1))
      found < 2
    end
    
    defp has_undefined_terms?(prompt) do
      # Simple heuristic: check for technical terms without explanation
      technical_indicators = ["API", "SDK", "framework", "architecture", "algorithm"]
      found_technical = Enum.any?(technical_indicators, &String.contains?(prompt, &1))
      has_definitions = String.contains?(String.downcase(prompt), "means") || 
                      String.contains?(String.downcase(prompt), "defined as")
      
      found_technical && !has_definitions
    end
    
    defp poor_logical_flow?(prompt) do
      # Check for logical connectors
      connectors = ["first", "then", "next", "finally", "because", "therefore", "however"]
      found_connectors = Enum.count(connectors, &String.contains?(String.downcase(prompt), &1))
      
      # If prompt is long but has few connectors, flow might be poor
      prompt_length = String.length(prompt)
      prompt_length > 500 && found_connectors < 2
    end
    
    defp poor_formatting?(prompt, target_model, _context) do
      # Check if prompt would benefit from formatting based on model preferences
      model_profiles = %{
        gpt4: %{prefers_structured: true},
        claude: %{prefers_conversational: true},
        gemini: %{prefers_detailed: true}
      }
      
      profile = model_profiles[target_model] || %{}
      
      if profile[:prefers_structured] do
        !String.contains?(prompt, "\n") && String.length(prompt) > 300
      else
        false
      end
    end
    
    defp missing_sections?(prompt) do
      sections = ["context", "example", "format", "requirement"]
      found_sections = Enum.count(sections, &String.contains?(String.downcase(prompt), &1))
      found_sections < 2
    end
    
    defp missing_context?(prompt) do
      context_indicators = ["context", "background", "situation", "scenario"]
      !Enum.any?(context_indicators, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp missing_examples?(prompt) do
      example_indicators = ["example", "instance", "sample", "like", "such as"]
      !Enum.any?(example_indicators, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp missing_output_format?(prompt) do
      format_indicators = ["format", "structure", "output", "response", "return"]
      !Enum.any?(format_indicators, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp has_leading_questions?(prompt) do
      leading_patterns = ["don't you think", "isn't it true", "wouldn't you agree", "obviously"]
      Enum.any?(leading_patterns, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp has_assumptions?(prompt) do
      assumption_words = ["obviously", "clearly", "everyone knows", "it's common"]
      Enum.any?(assumption_words, &String.contains?(String.downcase(prompt), &1))
    end
    
    defp has_exclusive_language?(prompt) do
      exclusive_terms = ["guys", "manpower", "blacklist", "whitelist"]
      Enum.any?(exclusive_terms, &String.contains?(String.downcase(prompt), &1))
    end
    
    # Scoring functions
    defp calculate_clarity_score(_prompt, issues) do
      base_score = 1.0
      penalty_per_issue = 0.2
      max(0.0, base_score - (length(issues) * penalty_per_issue))
    end
    
    defp calculate_specificity_score(_prompt, issues) do
      base_score = 1.0
      penalty_per_issue = 0.25
      max(0.0, base_score - (length(issues) * penalty_per_issue))
    end
    
    defp calculate_structure_score(_prompt, issues) do
      base_score = 1.0
      penalty_per_issue = 0.3
      max(0.0, base_score - (length(issues) * penalty_per_issue))
    end
    
    defp calculate_completeness_score(_prompt, issues) do
      base_score = 1.0
      penalty_per_issue = 0.2
      max(0.0, base_score - (length(issues) * penalty_per_issue))
    end
    
    defp calculate_bias_score(_prompt, issues) do
      base_score = 1.0
      penalty_per_issue = 0.4
      max(0.0, base_score - (length(issues) * penalty_per_issue))
    end
    
    defp calculate_overall_score(analysis_results) do
      scores = Map.values(analysis_results) |> Enum.map(& &1.score)
      if length(scores) > 0 do
        Enum.sum(scores) / length(scores)
      else
        0.0
      end
    end
    
    # Suggestion generators
    defp generate_clarity_suggestions(issues) do
      base_suggestions = [
        "Use specific, concrete language instead of vague terms",
        "Break complex sentences into simpler ones",
        "Define technical terms and acronyms"
      ]
      
      issue_specific = issues
      |> Enum.flat_map(fn issue ->
        case issue do
          "Contains ambiguous or vague language" -> ["Replace words like 'thing', 'stuff' with specific terms"]
          "Contains overly complex sentences" -> ["Use shorter, clearer sentences"]
          "Instructions could be clearer" -> ["Use direct commands instead of polite requests"]
          _ -> []
        end
      end)
      
      (base_suggestions ++ issue_specific) |> Enum.uniq()
    end
    
    defp generate_specificity_suggestions(issues) do
      base_suggestions = [
        "Add specific constraints and requirements",
        "Include concrete examples",
        "Define success criteria"
      ]
      
      issue_specific = issues
      |> Enum.flat_map(fn issue ->
        case issue do
          "Uses generic or non-specific language" -> ["Replace generic terms with specific ones"]
          "Missing important constraints or parameters" -> ["Add clear constraints and parameters"]
          "Contains undefined or context-dependent terms" -> ["Define all technical terms"]
          _ -> []
        end
      end)
      
      (base_suggestions ++ issue_specific) |> Enum.uniq()
    end
    
    defp generate_structure_suggestions(issues, target_model) do
      base_suggestions = [
        "Organize content with clear sections",
        "Use logical flow and transitions",
        "Format for readability"
      ]
      
      model_specific = case target_model do
        :gpt4 -> ["Use structured format with headers and bullet points"]
        :claude -> ["Use conversational but organized structure"]
        :gemini -> ["Use step-by-step detailed structure"]
        _ -> []
      end
      
      issue_specific = issues
      |> Enum.flat_map(fn issue ->
        case issue do
          "Poor logical flow or organization" -> ["Add transition words and logical connectors"]
          "Could benefit from better formatting" -> ["Use headers, bullets, and white space"]
          "Missing important sections" -> ["Add context, examples, and format sections"]
          _ -> []
        end
      end)
      
      (base_suggestions ++ model_specific ++ issue_specific) |> Enum.uniq()
    end
    
    defp generate_completeness_suggestions(issues) do
      base_suggestions = [
        "Provide sufficient context",
        "Include relevant examples",
        "Specify desired output format"
      ]
      
      issue_specific = issues
      |> Enum.flat_map(fn issue ->
        case issue do
          "Lacks sufficient context" -> ["Add background information and context"]
          "Could benefit from examples" -> ["Include concrete examples of desired output"]
          "Output format not specified" -> ["Clearly specify the expected output format"]
          _ -> []
        end
      end)
      
      (base_suggestions ++ issue_specific) |> Enum.uniq()
    end
    
    defp generate_bias_suggestions(issues) do
      base_suggestions = [
        "Use neutral, objective language",
        "Avoid leading questions",
        "Check for inclusive language"
      ]
      
      issue_specific = issues
      |> Enum.flat_map(fn issue ->
        case issue do
          "Contains leading or biased questions" -> ["Rephrase questions to be neutral"]
          "Makes unwarranted assumptions" -> ["Remove assumptions and state facts clearly"]
          "Could use more inclusive language" -> ["Replace exclusive terms with inclusive alternatives"]
          _ -> []
        end
      end)
      
      (base_suggestions ++ issue_specific) |> Enum.uniq()
    end
    
    defp generate_recommendations(analysis_results, target_model, agent_context) do
      # Get all suggestions from analysis results
      all_suggestions = analysis_results
      |> Map.values()
      |> Enum.flat_map(& &1.suggestions)
      |> Enum.uniq()
      
      # Add model-specific recommendations
      model_recommendations = get_model_specific_recommendations(target_model, agent_context)
      
      # Prioritize recommendations based on impact
      prioritized = prioritize_recommendations(all_suggestions ++ model_recommendations, analysis_results)
      
      %{
        high_impact: Enum.take(prioritized, 3),
        medium_impact: Enum.slice(prioritized, 3, 3),
        low_impact: Enum.slice(prioritized, 6, -1)
      }
    end
    
    defp get_model_specific_recommendations(target_model, agent_context) do
      profiles = agent_context.agent.state.model_profiles
      profile = profiles[target_model] || %{}
      
      recommendations = []
      
      recommendations = if profile[:prefers_structured] do
        ["Structure your prompt with clear sections and headers" | recommendations]
      else
        recommendations
      end
      
      recommendations = if profile[:responds_to_examples] do
        ["Include concrete examples to improve response quality" | recommendations]
      else
        recommendations
      end
      
      recommendations = if profile[:responds_to_context] do
        ["Provide rich context and background information" | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
    
    defp prioritize_recommendations(recommendations, analysis_results) do
      # Score recommendations based on the severity of issues they address
      scored_recommendations = recommendations
      |> Enum.map(fn rec ->
        score = calculate_recommendation_score(rec, analysis_results)
        {rec, score}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.map(&elem(&1, 0))
      
      scored_recommendations
    end
    
    defp calculate_recommendation_score(recommendation, analysis_results) do
      # Simple scoring based on keyword matching with low-scoring aspects
      base_score = 1.0
      
      # Give higher scores to recommendations that address low-scoring aspects
      low_score_aspects = analysis_results
      |> Enum.filter(fn {_aspect, result} -> result.score < 0.6 end)
      |> Enum.map(&elem(&1, 0))
      
      if Enum.any?(low_score_aspects, fn aspect ->
        String.contains?(String.downcase(recommendation), Atom.to_string(aspect))
      end) do
        base_score + 0.5
      else
        base_score
      end
    end
  end
  
  defmodule OptimizePromptAction do
    @moduledoc false
    use Jido.Action,
      name: "optimize_prompt",
      description: "Apply optimizations to improve prompt effectiveness",
      schema: [
        prompt: [type: :string, required: true],
        optimization_strategies: [
          type: {:list, :atom},
          default: [:clarity_enhancement, :specificity_improvement, :structure_optimization],
          doc: "Optimization strategies to apply"
        ],
        target_model: [type: :atom, required: false],
        preserve_intent: [type: :boolean, default: true],
        max_length: [type: :integer, required: false]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      prompt = params.prompt
      strategies = params.optimization_strategies
      target_model = params.target_model
      preserve_intent = params.preserve_intent
      max_length = params.max_length
      
      # First analyze the prompt to understand current state
      case AnalyzePromptAction.run(%{
        prompt: prompt,
        target_model: target_model
      }, context) do
        {:ok, analysis} ->
          # Apply optimizations based on strategies
          case apply_optimizations(prompt, strategies, analysis, target_model, context) do
            {:ok, optimized_prompt} ->
              # Validate the optimization
              validation_result = validate_optimization(
                prompt, 
                optimized_prompt, 
                preserve_intent, 
                max_length, 
                context
              )
              
              {:ok, %{
                original_prompt: prompt,
                optimized_prompt: optimized_prompt,
                optimization_strategies: strategies,
                target_model: target_model,
                analysis_before: analysis,
                validation: validation_result,
                optimized_at: DateTime.utc_now()
              }}
              
            {:error, reason} -> {:error, reason}
          end
          
        {:error, reason} -> {:error, {:analysis_failed, reason}}
      end
    end
    
    defp apply_optimizations(prompt, strategies, analysis, target_model, context) do
      # Apply each strategy in sequence
      Enum.reduce_while(strategies, {:ok, prompt}, fn strategy, {:ok, current_prompt} ->
        case apply_single_optimization(current_prompt, strategy, analysis, target_model, context) do
          {:ok, improved_prompt} -> {:cont, {:ok, improved_prompt}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
    
    defp apply_single_optimization(prompt, :clarity_enhancement, analysis, _target_model, _context) do
      clarity_result = analysis.analysis_results[:clarity]
      
      if clarity_result && clarity_result.score < 0.7 do
        enhanced = prompt
        |> replace_ambiguous_language()
        |> simplify_complex_sentences()
        |> strengthen_instructions()
        
        {:ok, enhanced}
      else
        {:ok, prompt}
      end
    end
    
    defp apply_single_optimization(prompt, :specificity_improvement, analysis, _target_model, _context) do
      specificity_result = analysis.analysis_results[:specificity]
      
      if specificity_result && specificity_result.score < 0.7 do
        improved = prompt
        |> add_specific_constraints()
        |> replace_generic_terms()
        |> add_context_details()
        
        {:ok, improved}
      else
        {:ok, prompt}
      end
    end
    
    defp apply_single_optimization(prompt, :structure_optimization, analysis, target_model, context) do
      structure_result = analysis.analysis_results[:structure]
      
      if structure_result && structure_result.score < 0.7 do
        optimized = prompt
        |> improve_organization()
        |> add_sections()
        |> format_for_model(target_model, context)
        
        {:ok, optimized}
      else
        {:ok, prompt}
      end
    end
    
    defp apply_single_optimization(prompt, :context_enrichment, analysis, _target_model, _context) do
      completeness_result = analysis.analysis_results[:completeness]
      
      if completeness_result && completeness_result.score < 0.7 do
        enriched = prompt
        |> add_background_context()
        |> include_examples()
        |> specify_output_format()
        
        {:ok, enriched}
      else
        {:ok, prompt}
      end
    end
    
    defp apply_single_optimization(prompt, :bias_reduction, analysis, _target_model, _context) do
      bias_result = analysis.analysis_results[:bias]
      
      if bias_result && bias_result.score < 0.8 do
        improved = prompt
        |> neutralize_language()
        |> remove_assumptions()
        |> use_inclusive_language()
        
        {:ok, improved}
      else
        {:ok, prompt}
      end
    end
    
    defp apply_single_optimization(prompt, _strategy, _analysis, _target_model, _context) do
      {:ok, prompt}
    end
    
    # Optimization implementation functions
    defp replace_ambiguous_language(prompt) do
      replacements = [
        {"thing", "element"},
        {"stuff", "items"},
        {"maybe", ""},
        {"perhaps", ""},
        {"might", "will"},
        {"could", "should"}
      ]
      
      Enum.reduce(replacements, prompt, fn {old, new}, acc ->
        String.replace(acc, old, new)
      end)
    end
    
    defp simplify_complex_sentences(prompt) do
      # Simple heuristic: split long sentences at conjunctions
      prompt
      |> String.replace(~r/,\s+(and|but|or|so)\s+/, ". ")
      |> String.replace(~r/;\s+/, ". ")
    end
    
    defp strengthen_instructions(prompt) do
      # Replace weak instruction language with strong directives
      replacements = [
        {"please", ""},
        {"try to", ""},
        {"if possible", ""},
        {"maybe you could", ""},
        {"would you", ""}
      ]
      
      Enum.reduce(replacements, prompt, fn {old, new}, acc ->
        String.replace(acc, old, new, global: true)
      end)
    end
    
    defp add_specific_constraints(prompt) do
      if String.contains?(prompt, "Requirements:") || String.contains?(prompt, "Constraints:") do
        prompt
      else
        prompt <> "\n\nRequirements:\n- Be specific and detailed\n- Provide concrete examples\n- Follow the specified format"
      end
    end
    
    defp replace_generic_terms(prompt) do
      replacements = [
        {"general", "specific"},
        {"basic", "fundamental"},
        {"simple", "straightforward"},
        {"normal", "standard"},
        {"usual", "typical"},
        {"regular", "standard"}
      ]
      
      Enum.reduce(replacements, prompt, fn {old, new}, acc ->
        String.replace(acc, old, new)
      end)
    end
    
    defp add_context_details(prompt) do
      if String.contains?(prompt, "Context:") || String.contains?(prompt, "Background:") do
        prompt
      else
        "\nContext: Please consider the following background information when responding.\n" <> prompt
      end
    end
    
    defp improve_organization(prompt) do
      # Add structure if the prompt is long and unstructured
      if String.length(prompt) > 200 && !String.contains?(prompt, "\n\n") do
        # Simple restructuring by adding paragraph breaks
        prompt
        |> String.replace(~r/\.\s+([A-Z])/, ".\n\n\\1")
      else
        prompt
      end
    end
    
    defp add_sections(prompt) do
      sections = ["Task:", "Context:", "Requirements:", "Output:"]
      missing_sections = Enum.reject(sections, &String.contains?(prompt, &1))
      
      if length(missing_sections) > 2 do
        "Task: " <> prompt <> "\n\nOutput: Please provide a clear and detailed response."
      else
        prompt
      end
    end
    
    defp format_for_model(prompt, target_model, context) do
      profiles = context.agent.state.model_profiles
      profile = profiles[target_model] || %{}
      
      cond do
        profile[:prefers_structured] && !String.contains?(prompt, "##") ->
          "## Task\n#{prompt}\n\n## Instructions\nProvide a comprehensive response following the above requirements."
          
        profile[:prefers_conversational] && String.contains?(prompt, "##") ->
          # Remove excessive formatting for conversational models
          String.replace(prompt, ~r/##\s*/, "")
          
        true -> prompt
      end
    end
    
    defp add_background_context(prompt) do
      if String.contains?(String.downcase(prompt), "context") do
        prompt
      else
        "Context: This request is part of a larger task requiring detailed analysis.\n\n" <> prompt
      end
    end
    
    defp include_examples(prompt) do
      if String.contains?(String.downcase(prompt), "example") do
        prompt
      else
        prompt <> "\n\nPlease include specific examples in your response to illustrate key points."
      end
    end
    
    defp specify_output_format(prompt) do
      if String.contains?(String.downcase(prompt), "format") do
        prompt
      else
        prompt <> "\n\nFormat: Provide your response in a clear, structured format with headings and bullet points where appropriate."
      end
    end
    
    defp neutralize_language(prompt) do
      # Remove leading/biased language
      replacements = [
        {"don't you think", "consider whether"},
        {"isn't it true", "evaluate if"},
        {"wouldn't you agree", "assess whether"},
        {"obviously", ""},
        {"clearly", ""}
      ]
      
      Enum.reduce(replacements, prompt, fn {old, new}, acc ->
        String.replace(acc, old, new, global: true)
      end)
    end
    
    defp remove_assumptions(prompt) do
      assumption_phrases = [
        "everyone knows",
        "it's common knowledge",
        "as we all know",
        "it's obvious that"
      ]
      
      Enum.reduce(assumption_phrases, prompt, fn phrase, acc ->
        String.replace(acc, phrase, "", global: true)
      end)
    end
    
    defp use_inclusive_language(prompt) do
      inclusive_replacements = [
        {"guys", "everyone"},
        {"manpower", "workforce"},
        {"blacklist", "blocklist"},
        {"whitelist", "allowlist"},
        {"master/slave", "primary/secondary"}
      ]
      
      Enum.reduce(inclusive_replacements, prompt, fn {old, new}, acc ->
        String.replace(acc, old, new, global: true)
      end)
    end
    
    defp validate_optimization(original, optimized, preserve_intent, max_length, context) do
      issues = []
      
      # Check length constraints
      issues = if max_length && String.length(optimized) > max_length do
        ["Optimized prompt exceeds maximum length (#{String.length(optimized)}/#{max_length})" | issues]
      else
        issues
      end
      
      # Check intent preservation (simplified)
      issues = if preserve_intent && intent_significantly_changed?(original, optimized) do
        ["Original intent may have been altered during optimization" | issues]
      else
        issues
      end
      
      # Basic quality checks
      issues = if String.length(optimized) < String.length(original) * 0.5 do
        ["Optimized prompt is significantly shorter, content may be lost" | issues]
      else
        issues
      end
      
      %{
        valid: length(issues) == 0,
        issues: issues,
        length_change: String.length(optimized) - String.length(original),
        improvement_score: calculate_improvement_score(original, optimized, context)
      }
    end
    
    defp intent_significantly_changed?(original, optimized) do
      # Simple heuristic: check if key terms are preserved
      original_words = original |> String.downcase() |> String.split() |> MapSet.new()
      optimized_words = optimized |> String.downcase() |> String.split() |> MapSet.new()
      
      preserved_ratio = MapSet.intersection(original_words, optimized_words) 
                       |> MapSet.size() 
                       |> div(MapSet.size(original_words))
      
      preserved_ratio < 0.7
    end
    
    defp calculate_improvement_score(original, optimized, context) do
      # Run analysis on both versions and compare scores
      case AnalyzePromptAction.run(%{prompt: original}, context) do
        {:ok, original_analysis} ->
          case AnalyzePromptAction.run(%{prompt: optimized}, context) do
            {:ok, optimized_analysis} ->
              optimized_analysis.overall_score - original_analysis.overall_score
            _ -> 0.0
          end
        _ -> 0.0
      end
    end
  end
  
  defmodule ABTestPromptsAction do
    @moduledoc false
    use Jido.Action,
      name: "ab_test_prompts",
      description: "Set up A/B testing for prompt variations",
      schema: [
        test_name: [type: :string, required: true],
        prompt_variants: [
          type: {:list, :map},
          required: true,
          doc: "List of prompt variants to test"
        ],
        test_criteria: [
          type: {:list, :atom},
          default: [:response_quality, :response_time, :user_satisfaction],
          doc: "Criteria to evaluate"
        ],
        sample_size: [type: :integer, default: 100],
        confidence_level: [type: :float, default: 0.95]
      ]
    
    @impl true
    def run(params, _context) do
      test_name = params.test_name
      variants = params.prompt_variants
      criteria = params.test_criteria
      sample_size = params.sample_size
      confidence_level = params.confidence_level
      
      # Validate variants
      case validate_variants(variants) do
        {:ok, validated_variants} ->
          # Create test configuration
          test_config = %{
            name: test_name,
            variants: validated_variants,
            criteria: criteria,
            sample_size: sample_size,
            confidence_level: confidence_level,
            status: :active,
            created_at: DateTime.utc_now(),
            results: %{}
          }
          
          {:ok, %{
            test_config: test_config,
            next_steps: generate_test_instructions(test_config)
          }}
          
        {:error, reason} -> {:error, reason}
      end
    end
    
    defp validate_variants(variants) do
      if length(variants) < 2 do
        {:error, "At least 2 variants required for A/B testing"}
      else
        validated = variants
        |> Enum.with_index()
        |> Enum.map(fn {variant, index} ->
          Map.merge(variant, %{
            id: "variant_#{index + 1}",
            weight: variant[:weight] || 1.0 / length(variants)
          })
        end)
        
        {:ok, validated}
      end
    end
    
    defp generate_test_instructions(test_config) do
      [
        "Set up data collection for #{length(test_config.variants)} variants",
        "Implement random assignment with weights: #{inspect(Enum.map(test_config.variants, & &1.weight))}",
        "Track metrics: #{Enum.join(test_config.criteria, ", ")}",
        "Collect #{test_config.sample_size} samples per variant",
        "Run statistical significance testing at #{test_config.confidence_level} confidence level"
      ]
    end
  end
  
  defmodule GenerateVariationsAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_variations",
      description: "Generate multiple variations of a prompt for testing",
      schema: [
        base_prompt: [type: :string, required: true],
        variation_types: [
          type: {:list, :atom},
          default: [:tone, :length, :structure, :specificity],
          doc: "Types of variations to generate"
        ],
        count: [type: :integer, default: 3, doc: "Number of variations per type"],
        target_model: [type: :atom, required: false]
      ]
    
    @impl true
    def run(params, context) do
      base_prompt = params.base_prompt
      variation_types = params.variation_types
      count = params.count
      target_model = params.target_model
      
      variations = Enum.flat_map(variation_types, fn type ->
        generate_variations_of_type(base_prompt, type, count, target_model, context)
      end)
      
      {:ok, %{
        base_prompt: base_prompt,
        variations: variations,
        total_variations: length(variations),
        variation_types: variation_types,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp generate_variations_of_type(base_prompt, :tone, count, _target_model, _context) do
      tones = [:formal, :casual, :direct, :friendly, :professional]
      
      tones
      |> Enum.take(count)
      |> Enum.map(fn tone ->
        %{
          type: :tone,
          variation: tone,
          prompt: apply_tone_variation(base_prompt, tone),
          description: "#{tone} tone variation"
        }
      end)
    end
    
    defp generate_variations_of_type(base_prompt, :length, count, _target_model, _context) do
      variations = [
        %{type: :length, variation: :concise, prompt: make_concise(base_prompt), description: "Concise version"},
        %{type: :length, variation: :detailed, prompt: make_detailed(base_prompt), description: "Detailed version"},
        %{type: :length, variation: :minimal, prompt: make_minimal(base_prompt), description: "Minimal version"}
      ]
      
      Enum.take(variations, count)
    end
    
    defp generate_variations_of_type(base_prompt, :structure, count, target_model, context) do
      structures = [:bulleted, :numbered, :sectioned, :conversational]
      
      structures
      |> Enum.take(count)
      |> Enum.map(fn structure ->
        %{
          type: :structure,
          variation: structure,
          prompt: apply_structure_variation(base_prompt, structure, target_model, context),
          description: "#{structure} structure variation"
        }
      end)
    end
    
    defp generate_variations_of_type(base_prompt, :specificity, count, _target_model, _context) do
      variations = [
        %{type: :specificity, variation: :high, prompt: increase_specificity(base_prompt), description: "High specificity"},
        %{type: :specificity, variation: :medium, prompt: base_prompt, description: "Medium specificity (original)"},
        %{type: :specificity, variation: :low, prompt: decrease_specificity(base_prompt), description: "Low specificity"}
      ]
      
      Enum.take(variations, count)
    end
    
    defp generate_variations_of_type(_base_prompt, _type, _count, _target_model, _context) do
      []
    end
    
    # Variation implementation functions
    defp apply_tone_variation(prompt, :formal) do
      "Please provide a comprehensive analysis of the following request:\n\n#{prompt}\n\nYour response should be thorough and professionally formatted."
    end
    
    defp apply_tone_variation(prompt, :casual) do
      "Hey! Can you help me out with this?\n\n#{prompt}\n\nThanks!"
    end
    
    defp apply_tone_variation(prompt, :direct) do
      "#{prompt}\n\nBe direct and concise."
    end
    
    defp apply_tone_variation(prompt, :friendly) do
      "I'd really appreciate your help with this:\n\n#{prompt}\n\nThank you so much for your assistance!"
    end
    
    defp apply_tone_variation(prompt, :professional) do
      "Request for Analysis:\n\n#{prompt}\n\nPlease provide a professional response with supporting details."
    end
    
    defp apply_tone_variation(prompt, _), do: prompt
    
    defp make_concise(prompt) do
      # Remove unnecessary words and phrases
      prompt
      |> String.replace(~r/\s+/, " ")
      |> String.replace(~r/please|kindly|if you could/, "")
      |> String.replace(~r/I would like|I need|I want/, "")
      |> String.trim()
    end
    
    defp make_detailed(prompt) do
      """
      Detailed Request:
      
      #{prompt}
      
      Please provide:
      1. A comprehensive analysis
      2. Specific examples where applicable
      3. Step-by-step explanations
      4. Relevant context and background
      5. Practical implications and recommendations
      
      Format your response with clear headings and detailed explanations for each point.
      """
    end
    
    defp make_minimal(prompt) do
      # Extract just the core request
      prompt
      |> String.split(".")
      |> List.first()
      |> String.trim()
    end
    
    defp apply_structure_variation(prompt, :bulleted, _target_model, _context) do
      """
      Request:
      • #{prompt}
      
      Please respond with:
      • Clear bullet points
      • Organized information
      • Easy-to-scan format
      """
    end
    
    defp apply_structure_variation(prompt, :numbered, _target_model, _context) do
      """
      1. Request: #{prompt}
      
      2. Please provide your response in numbered format:
         a. Main points
         b. Supporting details
         c. Conclusions
      """
    end
    
    defp apply_structure_variation(prompt, :sectioned, _target_model, _context) do
      """
      ## Task
      #{prompt}
      
      ## Requirements
      Please structure your response with clear sections and headings.
      
      ## Output Format
      Use appropriate formatting for readability.
      """
    end
    
    defp apply_structure_variation(prompt, :conversational, _target_model, _context) do
      "I'm working on something and could use your thoughts. #{prompt} What's your take on this?"
    end
    
    defp apply_structure_variation(prompt, _, _target_model, _context), do: prompt
    
    defp increase_specificity(prompt) do
      """
      #{prompt}
      
      Specific Requirements:
      - Provide concrete examples
      - Include specific numbers or metrics where applicable
      - Reference particular methods, tools, or frameworks
      - Give detailed step-by-step instructions
      - Specify exact format and structure for the response
      """
    end
    
    defp decrease_specificity(prompt) do
      # Make the prompt more general
      prompt
      |> String.replace(~r/specific|exactly|precisely/, "generally")
      |> String.replace(~r/must|should|need to/, "could")
      |> String.replace(~r/\d+/, "some")
    end
  end
  
  defmodule EvaluateEffectivenessAction do
    @moduledoc false
    use Jido.Action,
      name: "evaluate_effectiveness",
      description: "Evaluate prompt effectiveness based on response quality metrics",
      schema: [
        prompt: [type: :string, required: true],
        responses: [
          type: {:list, :map},
          required: true,
          doc: "List of responses to evaluate"
        ],
        evaluation_criteria: [
          type: {:list, :atom},
          default: [:relevance, :completeness, :accuracy, :clarity, :usefulness],
          doc: "Criteria for evaluation"
        ],
        baseline_scores: [type: :map, default: %{}]
      ]
    
    @impl true
    def run(params, _context) do
      prompt = params.prompt
      responses = params.responses
      criteria = params.evaluation_criteria
      baseline_scores = params.baseline_scores
      
      # Evaluate each response
      response_evaluations = Enum.map(responses, fn response ->
        evaluate_single_response(response, criteria, prompt)
      end)
      
      # Calculate aggregate metrics
      aggregate_scores = calculate_aggregate_scores(response_evaluations, criteria)
      
      # Compare with baseline if provided
      comparison = if map_size(baseline_scores) > 0 do
        compare_with_baseline(aggregate_scores, baseline_scores)
      else
        %{baseline_comparison: "No baseline provided"}
      end
      
      {:ok, %{
        prompt: prompt,
        response_count: length(responses),
        individual_evaluations: response_evaluations,
        aggregate_scores: aggregate_scores,
        baseline_comparison: comparison,
        overall_effectiveness: calculate_overall_effectiveness(aggregate_scores),
        evaluated_at: DateTime.utc_now()
      }}
    end
    
    defp evaluate_single_response(response, criteria, prompt) do
      scores = Enum.map(criteria, fn criterion ->
        {criterion, evaluate_criterion(response, criterion, prompt)}
      end) |> Map.new()
      
      %{
        response_id: response[:id] || generate_response_id(),
        response_length: String.length(response[:content] || ""),
        scores: scores,
        overall_score: Map.values(scores) |> Enum.sum() |> div(length(criteria))
      }
    end
    
    defp evaluate_criterion(response, :relevance, prompt) do
      # Simple relevance scoring based on keyword overlap
      prompt_words = extract_keywords(prompt)
      response_words = extract_keywords(response[:content] || "")
      
      overlap = MapSet.intersection(prompt_words, response_words) |> MapSet.size()
      total_prompt_keywords = MapSet.size(prompt_words)
      
      if total_prompt_keywords > 0 do
        min(1.0, overlap / total_prompt_keywords)
      else
        0.5
      end
    end
    
    defp evaluate_criterion(response, :completeness, _prompt) do
      content = response[:content] || ""
      
      # Simple completeness scoring based on response length and structure
      length_score = min(1.0, String.length(content) / 500)
      
      structure_indicators = ["first", "second", "finally", "conclusion", "summary"]
      structure_score = Enum.count(structure_indicators, &String.contains?(String.downcase(content), &1)) / length(structure_indicators)
      
      (length_score + structure_score) / 2
    end
    
    defp evaluate_criterion(response, :accuracy, _prompt) do
      content = response[:content] || ""
      
      # Simple accuracy indicators (in real implementation, this would be more sophisticated)
      accuracy_indicators = ["according to", "research shows", "studies indicate", "data suggests"]
      uncertainty_indicators = ["might", "maybe", "possibly", "unclear", "unknown"]
      
      accuracy_signals = Enum.count(accuracy_indicators, &String.contains?(String.downcase(content), &1))
      uncertainty_signals = Enum.count(uncertainty_indicators, &String.contains?(String.downcase(content), &1))
      
      if accuracy_signals + uncertainty_signals == 0 do
        0.7 # Neutral score when no indicators present
      else
        accuracy_signals / (accuracy_signals + uncertainty_signals)
      end
    end
    
    defp evaluate_criterion(response, :clarity, _prompt) do
      content = response[:content] || ""
      
      # Simple clarity scoring
      sentence_count = String.split(content, ~r/[.!?]/) |> length()
      word_count = String.split(content) |> length()
      
      avg_sentence_length = if sentence_count > 0, do: word_count / sentence_count, else: 0
      
      # Shorter sentences generally indicate better clarity
      clarity_score = cond do
        avg_sentence_length <= 15 -> 1.0
        avg_sentence_length <= 25 -> 0.8
        avg_sentence_length <= 35 -> 0.6
        true -> 0.4
      end
      
      # Check for clarity indicators
      clarity_words = ["clearly", "specifically", "for example", "in other words"]
      clarity_boost = Enum.count(clarity_words, &String.contains?(String.downcase(content), &1)) * 0.1
      
      min(1.0, clarity_score + clarity_boost)
    end
    
    defp evaluate_criterion(response, :usefulness, prompt) do
      content = response[:content] || ""
      
      # Check if response provides actionable information
      actionable_words = ["step", "method", "approach", "technique", "strategy", "solution"]
      actionable_count = Enum.count(actionable_words, &String.contains?(String.downcase(content), &1))
      
      # Check if response addresses the prompt directly
      prompt_keywords = extract_keywords(prompt) |> MapSet.to_list()
      addressed_keywords = Enum.count(prompt_keywords, fn keyword ->
        String.contains?(String.downcase(content), String.downcase(keyword))
      end)
      
      actionable_score = min(1.0, actionable_count / 3)
      relevance_score = if length(prompt_keywords) > 0 do
        addressed_keywords / length(prompt_keywords)
      else
        0.5
      end
      
      (actionable_score + relevance_score) / 2
    end
    
    defp evaluate_criterion(_response, _criterion, _prompt) do
      0.5 # Default score for unknown criteria
    end
    
    defp extract_keywords(text) do
      # Simple keyword extraction (in real implementation, use NLP libraries)
      text
      |> String.downcase()
      |> String.replace(~r/[^\w\s]/, "")
      |> String.split()
      |> Enum.filter(&(String.length(&1) > 3))
      |> Enum.filter(&(&1 not in ["this", "that", "with", "have", "will", "from", "they", "been", "said", "each", "which", "their"]))
      |> MapSet.new()
    end
    
    defp calculate_aggregate_scores(evaluations, criteria) do
      Enum.map(criteria, fn criterion ->
        scores = Enum.map(evaluations, &(&1.scores[criterion]))
        avg_score = Enum.sum(scores) / length(scores)
        {criterion, avg_score}
      end) |> Map.new()
    end
    
    defp compare_with_baseline(current_scores, baseline_scores) do
      improvements = Enum.map(current_scores, fn {criterion, current_score} ->
        baseline_score = baseline_scores[criterion] || 0.5
        improvement = current_score - baseline_score
        {criterion, %{current: current_score, baseline: baseline_score, improvement: improvement}}
      end) |> Map.new()
      
      overall_improvement = improvements
      |> Map.values()
      |> Enum.map(& &1.improvement)
      |> Enum.sum()
      |> div(map_size(improvements))
      
      %{
        criterion_comparisons: improvements,
        overall_improvement: overall_improvement,
        improved_criteria: Enum.count(improvements, fn {_, data} -> data.improvement > 0 end)
      }
    end
    
    defp calculate_overall_effectiveness(aggregate_scores) do
      if map_size(aggregate_scores) > 0 do
        total_score = Map.values(aggregate_scores) |> Enum.sum()
        avg_score = total_score / map_size(aggregate_scores)
        
        cond do
          avg_score >= 0.8 -> :excellent
          avg_score >= 0.6 -> :good
          avg_score >= 0.4 -> :fair
          true -> :poor
        end
      else
        :unknown
      end
    end
    
    defp generate_response_id do
      "resp_#{System.unique_integer([:positive, :monotonic])}"
    end
  end
  
  defmodule ApplyTemplateAction do
    @moduledoc false
    use Jido.Action,
      name: "apply_template",
      description: "Apply a template to generate a structured prompt",
      schema: [
        template_name: [type: :string, required: true],
        variables: [type: :map, required: true, doc: "Template variable values"],
        customizations: [type: :map, default: %{}, doc: "Additional customizations"]
      ]
    
    @impl true
    def run(params, context) do
      template_name = params.template_name
      variables = params.variables
      customizations = params.customizations
      
      templates = context.agent.state.prompt_templates
      
      case Map.get(templates, template_name) do
        nil -> {:error, "Template '#{template_name}' not found"}
        template ->
          case apply_template_with_variables(template, variables, customizations) do
            {:ok, generated_prompt} ->
              {:ok, %{
                template_name: template_name,
                variables_used: variables,
                customizations: customizations,
                generated_prompt: generated_prompt,
                template_structure: template.structure,
                applied_at: DateTime.utc_now()
              }}
            {:error, reason} -> {:error, reason}
          end
      end
    end
    
    defp apply_template_with_variables(template, variables, customizations) do
      structure = template.structure
      required_vars = template.variables || []
      
      # Check if all required variables are provided
      missing_vars = required_vars -- Map.keys(variables)
      if length(missing_vars) > 0 do
        {:error, "Missing required variables: #{inspect(missing_vars)}"}
      else
        # Replace variables in template
        generated = Enum.reduce(variables, structure, fn {var, value}, acc ->
          String.replace(acc, "{#{var}}", to_string(value))
        end)
        
        # Apply customizations
        final_prompt = apply_customizations(generated, customizations)
        
        {:ok, final_prompt}
      end
    end
    
    defp apply_customizations(prompt, customizations) do
      Enum.reduce(customizations, prompt, fn {key, value}, acc ->
        case key do
          :add_examples -> add_examples_section(acc, value)
          :add_constraints -> add_constraints_section(acc, value)
          :set_tone -> apply_tone_customization(acc, value)
          :add_context -> add_context_section(acc, value)
          _ -> acc
        end
      end)
    end
    
    defp add_examples_section(prompt, examples) when is_list(examples) do
      examples_text = examples
      |> Enum.with_index(1)
      |> Enum.map(fn {example, index} -> "Example #{index}: #{example}" end)
      |> Enum.join("\n")
      
      prompt <> "\n\nExamples:\n" <> examples_text
    end
    
    defp add_examples_section(prompt, example) when is_binary(example) do
      prompt <> "\n\nExample: " <> example
    end
    
    defp add_examples_section(prompt, _), do: prompt
    
    defp add_constraints_section(prompt, constraints) when is_list(constraints) do
      constraints_text = constraints
      |> Enum.map(&("- #{&1}"))
      |> Enum.join("\n")
      
      prompt <> "\n\nConstraints:\n" <> constraints_text
    end
    
    defp add_constraints_section(prompt, constraints) when is_binary(constraints) do
      prompt <> "\n\nConstraints: " <> constraints
    end
    
    defp add_constraints_section(prompt, _), do: prompt
    
    defp apply_tone_customization(prompt, :formal) do
      "Please provide a formal and comprehensive response to the following:\n\n" <> prompt
    end
    
    defp apply_tone_customization(prompt, :casual) do
      "Hey! " <> prompt <> " Thanks!"
    end
    
    defp apply_tone_customization(prompt, :professional) do
      "Professional Request:\n\n" <> prompt <> "\n\nPlease provide a detailed professional response."
    end
    
    defp apply_tone_customization(prompt, _), do: prompt
    
    defp add_context_section(prompt, context) when is_binary(context) do
      "Context: " <> context <> "\n\n" <> prompt
    end
    
    defp add_context_section(prompt, _), do: prompt
  end
  
  # Tool-specific signal handlers using the new action system
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "analyze_prompt"} = signal) do
    prompt = get_in(signal, ["data", "prompt"])
    analysis_aspects = get_in(signal, ["data", "analysis_aspects"]) || [:clarity, :specificity, :structure, :completeness, :bias]
    target_model = get_in(signal, ["data", "target_model"])
    context = get_in(signal, ["data", "context"]) || %{}
    
    # Execute prompt analysis action
    {:ok, _ref} = __MODULE__.cmd_async(agent, AnalyzePromptAction, %{
      prompt: prompt,
      analysis_aspects: analysis_aspects,
      target_model: if(target_model, do: String.to_atom(target_model)),
      context: context
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "optimize_prompt"} = signal) do
    prompt = get_in(signal, ["data", "prompt"])
    optimization_strategies = get_in(signal, ["data", "optimization_strategies"]) || [:clarity_enhancement, :specificity_improvement, :structure_optimization]
    target_model = get_in(signal, ["data", "target_model"])
    preserve_intent = get_in(signal, ["data", "preserve_intent"]) || true
    max_length = get_in(signal, ["data", "max_length"])
    
    # Execute prompt optimization action
    {:ok, _ref} = __MODULE__.cmd_async(agent, OptimizePromptAction, %{
      prompt: prompt,
      optimization_strategies: optimization_strategies,
      target_model: if(target_model, do: String.to_atom(target_model)),
      preserve_intent: preserve_intent,
      max_length: max_length
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "ab_test_prompts"} = signal) do
    test_name = get_in(signal, ["data", "test_name"])
    prompt_variants = get_in(signal, ["data", "prompt_variants"]) || []
    test_criteria = get_in(signal, ["data", "test_criteria"]) || [:response_quality, :response_time, :user_satisfaction]
    sample_size = get_in(signal, ["data", "sample_size"]) || 100
    confidence_level = get_in(signal, ["data", "confidence_level"]) || 0.95
    
    # Execute A/B testing setup action
    {:ok, _ref} = __MODULE__.cmd_async(agent, ABTestPromptsAction, %{
      test_name: test_name,
      prompt_variants: prompt_variants,
      test_criteria: test_criteria,
      sample_size: sample_size,
      confidence_level: confidence_level
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_variations"} = signal) do
    base_prompt = get_in(signal, ["data", "base_prompt"])
    variation_types = get_in(signal, ["data", "variation_types"]) || [:tone, :length, :structure, :specificity]
    count = get_in(signal, ["data", "count"]) || 3
    target_model = get_in(signal, ["data", "target_model"])
    
    # Execute variation generation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, GenerateVariationsAction, %{
      base_prompt: base_prompt,
      variation_types: variation_types,
      count: count,
      target_model: if(target_model, do: String.to_atom(target_model))
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "evaluate_effectiveness"} = signal) do
    prompt = get_in(signal, ["data", "prompt"])
    responses = get_in(signal, ["data", "responses"]) || []
    evaluation_criteria = get_in(signal, ["data", "evaluation_criteria"]) || [:relevance, :completeness, :accuracy, :clarity, :usefulness]
    baseline_scores = get_in(signal, ["data", "baseline_scores"]) || %{}
    
    # Execute effectiveness evaluation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, EvaluateEffectivenessAction, %{
      prompt: prompt,
      responses: responses,
      evaluation_criteria: evaluation_criteria,
      baseline_scores: baseline_scores
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "apply_template"} = signal) do
    template_name = get_in(signal, ["data", "template_name"])
    variables = get_in(signal, ["data", "variables"]) || %{}
    customizations = get_in(signal, ["data", "customizations"]) || %{}
    
    # Execute template application action
    {:ok, _ref} = __MODULE__.cmd_async(agent, ApplyTemplateAction, %{
      template_name: template_name,
      variables: variables,
      customizations: customizations
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, _signal), do: super(agent, _signal)
  
  # Process optimization results
  @impl true
  def process_result(result, _context) do
    # Add processing timestamp
    Map.put(result, :processed_at, DateTime.utc_now())
  end
  
  # Override action result handler to update optimization history and metrics
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Let parent handle the standard processing
    {:ok, agent} = super(agent, ExecuteToolAction, {:ok, result}, metadata)
    
    # Update optimization history if not from cache
    if result[:from_cache] == false && result[:result] do
      history_entry = %{
        type: :prompt_optimization,
        operation: metadata[:operation] || :general,
        input_prompt: metadata[:input_prompt],
        result_summary: extract_optimization_summary(result[:result]),
        processed_at: DateTime.utc_now()
      }
      
      agent = update_in(agent.state.optimization_history, fn history ->
        [history_entry | history]
        |> Enum.take(agent.state.max_history)
      end)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, OptimizePromptAction, {:ok, result}, _metadata) do
    # Update performance metrics
    if result[:validation][:improvement_score] do
      improvement = result.validation.improvement_score
      
      agent = update_in(agent.state.performance_metrics, fn metrics ->
        current_avg = metrics[:average_improvement] || 0.0
        current_count = metrics[:total_optimizations] || 0
        
        new_count = current_count + 1
        new_avg = (current_avg * current_count + improvement) / new_count
        
        metrics
        |> Map.put(:average_improvement, new_avg)
        |> Map.put(:total_optimizations, new_count)
        |> Map.put(:last_improvement, improvement)
        |> Map.put(:updated_at, DateTime.utc_now())
      end)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, ABTestPromptsAction, {:ok, result}, _metadata) do
    # Store active experiment
    test_config = result.test_config
    
    agent = put_in(agent.state.active_experiments[test_config.name], test_config)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, action, result, metadata) do
    # Let parent handle other actions
    super(agent, action, result, metadata)
  end
  
  # Helper functions
  
  defp extract_optimization_summary(result) do
    %{
      original_length: String.length(result[:original_prompt] || ""),
      optimized_length: String.length(result[:optimized_prompt] || ""),
      strategies_applied: result[:optimization_strategies] || [],
      improvement_score: result[:validation][:improvement_score] || 0.0
    }
  end
end