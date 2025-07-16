defmodule RubberDuck.MCP.Server.Prompts.FeatureImplementation do
  @moduledoc """
  Generates prompts for implementing new features in a codebase.
  
  This prompt helps AI assistants plan and implement features by providing
  structured guidance based on the project's architecture and conventions.
  """
  
  use Hermes.Server.Component, type: :prompt
  
  alias Hermes.Server.Frame
  
  schema do
    field :feature_description, {:required, :string},
      description: "Description of the feature to implement"
      
    field :project_type, {:required, :string},
      description: "Type of project (e.g., phoenix, nerves, library)"
      
    field :existing_code_context, :string,
      description: "Relevant existing code or modules"
      
    field :requirements, {:list, :string},
      description: "Specific requirements or constraints"
      
    field :implementation_approach, {:enum, ["incremental", "full", "prototype"]},
      description: "How to approach the implementation",
      default: "incremental"
  end
  
  @impl true
  def get_messages(params, frame) do
    %{
      feature_description: feature,
      project_type: project,
      existing_code_context: context,
      requirements: reqs,
      implementation_approach: approach
    } = params
    
    messages = [
      %{
        "role" => "system",
        "content" => build_system_prompt(project, approach)
      },
      %{
        "role" => "user", 
        "content" => build_user_prompt(feature, context, reqs)
      }
    ]
    
    {:ok, messages, frame}
  end
  
  defp build_system_prompt(project_type, approach) do
    """
    You are an expert Elixir developer implementing features in a #{project_type} project.
    
    Implementation approach: #{approach}
    
    Follow these principles:
    1. **Understand First**: Analyze existing code patterns and architecture
    2. **Plan Thoroughly**: Break down the feature into clear, manageable steps
    3. **Follow Conventions**: Match the project's existing style and patterns
    4. **Test Driven**: Write tests alongside implementation
    5. **Document Well**: Include clear documentation and type specs
    
    For #{approach} implementation:
    #{approach_guidelines(approach)}
    
    Structure your response:
    1. **Analysis**: Understanding of the feature and its impact
    2. **Design**: Architectural decisions and module structure
    3. **Implementation Plan**: Step-by-step breakdown
    4. **Code Examples**: Key pieces of implementation
    5. **Testing Strategy**: How to test the feature
    6. **Integration Points**: How it fits with existing code
    """
  end
  
  defp build_user_prompt(feature, context, requirements) do
    context_section = if context do
      """
      
      Existing code context:
      #{context}
      """
    else
      ""
    end
    
    requirements_section = if requirements && length(requirements) > 0 do
      """
      
      Requirements:
      #{Enum.map_join(requirements, "\n", &"- #{&1}")}
      """
    else
      ""
    end
    
    """
    I need to implement the following feature:
    
    #{feature}
    #{context_section}
    #{requirements_section}
    
    Please provide a comprehensive implementation plan and key code examples.
    """
  end
  
  defp approach_guidelines("incremental") do
    """
    - Start with the core functionality
    - Build in small, testable increments
    - Integrate gradually with existing systems
    - Refactor as patterns emerge
    """
  end
  
  defp approach_guidelines("full") do
    """
    - Design the complete solution upfront
    - Consider all edge cases and interactions
    - Implement comprehensively with full test coverage
    - Document all public APIs thoroughly
    """
  end
  
  defp approach_guidelines("prototype") do
    """
    - Focus on proving the concept works
    - Use simplified implementations where appropriate
    - Mark areas that need hardening with TODO comments
    - Prioritize learning and iteration
    """
  end
end