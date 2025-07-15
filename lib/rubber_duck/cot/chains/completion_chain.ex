defmodule RubberDuck.CoT.Chains.CompletionChain do
  @moduledoc """
  Chain-of-Thought reasoning chain for code completion.
  
  This chain guides the reasoning process through analyzing context,
  determining intent, generating appropriate completions, and validating fit.
  """
  
  @behaviour RubberDuck.CoT.ChainBehaviour
  
  def config do
    %{
      name: :completion,
      description: "Intelligent code completion with context-aware reasoning",
      max_steps: 7,
      timeout: 20_000,  # Faster for completions
      template: :analytical,
      cache_ttl: 600  # 10 minutes
    }
  end
  
  def steps do
    [
      %{
        name: :analyze_context,
        prompt: """
        Let me analyze the code context for completion:
        
        Prefix (before cursor): {{prefix}}
        Suffix (after cursor): {{suffix}}
        Current file: {{current_file}}
        Cursor position: {{cursor_position}}
        
        I'll examine:
        1. Current code structure and syntax
        2. Variable and function scope
        3. Import statements and dependencies
        4. Code patterns in use
        5. Indentation and formatting style
        
        Context analysis:
        """,
        validates: [:context_analyzed],
        timeout: 5_000
      },
      %{
        name: :determine_intent,
        prompt: """
        Now I'll determine what the user intends to write:
        
        Context: {{previous_result}}
        Recent edits: {{recent_edits}}
        
        Possible completion intents:
        1. Complete a function call
        2. Implement a function body
        3. Add a conditional statement
        4. Complete a data structure
        5. Import a module
        6. Write documentation
        7. Add error handling
        
        Detected intent:
        """,
        depends_on: :analyze_context,
        validates: [:intent_determined],
        timeout: 4_000
      },
      %{
        name: :identify_patterns,
        prompt: """
        Let me identify relevant patterns and idioms:
        
        Intent: {{previous_result}}
        Language: {{language}}
        Project patterns: {{project_patterns}}
        
        I'll look for:
        1. Language-specific idioms
        2. Project coding conventions
        3. Common patterns in similar contexts
        4. Framework-specific approaches
        5. Best practices for this scenario
        
        Relevant patterns:
        """,
        depends_on: :determine_intent,
        validates: [:patterns_identified],
        timeout: 4_000
      },
      %{
        name: :generate_completions,
        prompt: """
        I'll generate appropriate code completions:
        
        Intent: {{determine_intent_result}}
        Patterns: {{previous_result}}
        Context: {{analyze_context_result}}
        
        Generating completions that:
        1. Match the detected intent
        2. Follow identified patterns
        3. Fit the current context
        4. Maintain code style
        5. Are syntactically correct
        
        Completions (in order of relevance):
        """,
        depends_on: :identify_patterns,
        validates: [:completions_generated],
        timeout: 6_000
      },
      %{
        name: :rank_completions,
        prompt: """
        Let me rank the completions by relevance:
        
        Completions: {{previous_result}}
        User preferences: {{user_preferences}}
        
        Ranking criteria:
        1. Exact match to likely intent
        2. Code correctness
        3. Style consistency
        4. Common usage patterns
        5. Performance considerations
        
        Ranked completions:
        """,
        depends_on: :generate_completions,
        validates: [:completions_ranked],
        timeout: 3_000
      },
      %{
        name: :validate_fit,
        prompt: """
        I'll validate how well the top completions fit:
        
        Top completions: {{previous_result}}
        Full context: {{prefix}}[COMPLETION]{{suffix}}
        
        Validation checks:
        1. Syntax correctness when inserted
        2. Type compatibility
        3. Variable/function availability
        4. Import requirements
        5. No breaking changes
        
        Validation results:
        """,
        depends_on: :rank_completions,
        validates: [:fit_validated],
        timeout: 4_000
      },
      %{
        name: :format_suggestions,
        prompt: """
        Let me format the final completion suggestions:
        
        Validated completions: {{previous_result}}
        
        For each completion, I'll provide:
        1. The completion text
        2. Brief explanation
        3. Any required imports
        4. Cursor position after completion
        5. Additional context or warnings
        
        Final suggestions:
        """,
        depends_on: :validate_fit,
        validates: [:suggestions_formatted],
        timeout: 3_000
      }
    ]
  end
  
  # Validation functions
  
  def context_analyzed(%{result: result}) do
    result != nil && String.length(result) > 30
  end
  
  def intent_determined(%{result: result}) do
    result != nil && String.contains?(result, ["complete", "implement", "add", "write", "import"])
  end
  
  def patterns_identified(%{result: result}) do
    result != nil && String.contains?(result, ["pattern", "idiom", "convention", "practice"])
  end
  
  def completions_generated(%{result: result}) do
    result != nil && String.length(result) > 20
  end
  
  def completions_ranked(%{result: result}) do
    result != nil && (String.contains?(result, ["1.", "2.", "first", "second"]) || String.contains?(result, "completion"))
  end
  
  def fit_validated(%{result: result}) do
    result != nil && !String.contains?(String.downcase(result), ["error", "invalid", "incompatible"])
  end
  
  def suggestions_formatted(%{result: result}) do
    result != nil && String.length(result) > 20
  end
end