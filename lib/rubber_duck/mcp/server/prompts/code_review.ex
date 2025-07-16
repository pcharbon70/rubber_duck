defmodule RubberDuck.MCP.Server.Prompts.CodeReview do
  @moduledoc """
  Generates code review prompts for various programming languages and contexts.
  
  This prompt helps AI assistants perform thorough code reviews by providing
  structured templates that focus on specific aspects of code quality.
  """
  
  use Hermes.Server.Component, type: :prompt
  
  alias Hermes.Server.Frame
  
  schema do
    field :language, {:required, :string},
      description: "Programming language (e.g., elixir, python, javascript)"
      
    field :code, {:required, :string},
      description: "The code to review"
      
    field :context, :string,
      description: "Additional context about the code (e.g., purpose, constraints)"
      
    field :focus_areas, {:list, :string},
      description: "Specific areas to focus on",
      default: ["correctness", "performance", "readability", "maintainability"]
      
    field :severity_level, {:enum, ["strict", "normal", "lenient"]},
      description: "How strict the review should be",
      default: "normal"
  end
  
  @impl true
  def get_messages(%{language: lang, code: code, context: context, focus_areas: areas, severity_level: level}, frame) do
    messages = [
      %{
        "role" => "system",
        "content" => build_system_prompt(lang, areas, level)
      },
      %{
        "role" => "user",
        "content" => build_user_prompt(code, context, lang)
      }
    ]
    
    {:ok, messages, frame}
  end
  
  defp build_system_prompt(language, focus_areas, severity_level) do
    """
    You are an expert #{language} code reviewer. Your task is to provide a thorough, constructive code review.
    
    Review severity: #{severity_level}
    
    Focus on these areas:
    #{Enum.map_join(focus_areas, "\n", &"- #{&1}")}
    
    Structure your review as follows:
    1. **Summary**: Brief overview of the code's purpose and quality
    2. **Strengths**: What the code does well
    3. **Issues**: Problems that need to be addressed
       - Critical: Must fix before deployment
       - Major: Should fix for maintainability
       - Minor: Nice to have improvements
    4. **Suggestions**: Specific recommendations with code examples
    5. **Overall Assessment**: Final thoughts and next steps
    
    Be specific, provide examples, and maintain a constructive tone.
    """
  end
  
  defp build_user_prompt(code, context, language) do
    context_section = if context do
      """
      
      Context:
      #{context}
      """
    else
      ""
    end
    
    """
    Please review the following #{language} code:
    #{context_section}
    
    ```#{language}
    #{code}
    ```
    """
  end
end