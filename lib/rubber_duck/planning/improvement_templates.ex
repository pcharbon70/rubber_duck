defmodule RubberDuck.Planning.ImprovementTemplates do
  @moduledoc """
  LLM prompt templates for improving plans based on validation warnings.
  
  Provides structured templates for different types of improvements:
  - Task description enhancement
  - Security requirement generation
  - Success criteria creation
  - Best practice additions
  """
  
  @doc """
  Template for enhancing vague task descriptions.
  """
  def task_description_enhancement_template(params) do
    """
    Enhance this task description to be more specific and actionable.
    
    Task Name: #{params.task_name}
    Current Description: #{params.current_description}
    Plan Context: #{params.plan_context}
    Task Position: #{params.task_position}
    
    Requirements:
    1. Expand the description to at least 15-20 words
    2. Make it specific and actionable
    3. Include what needs to be done and how
    4. End with proper punctuation
    5. Add 3-5 specific success criteria
    6. Add 2-3 validation rules
    
    Respond with JSON:
    {
      "description": "Enhanced description here",
      "success_criteria": [
        "Specific measurable outcome 1",
        "Specific measurable outcome 2",
        "Specific measurable outcome 3"
      ],
      "validation_rules": [
        "Validation check 1",
        "Validation check 2"
      ]
    }
    """
  end
  
  @doc """
  Template for enhancing plan descriptions.
  """
  def plan_description_enhancement_template(params) do
    """
    Enhance this plan description to be more comprehensive.
    
    Plan Name: #{params.name}
    Current Description: #{params.current_description}
    Plan Type: #{params.type}
    Context: #{inspect(params.context)}
    
    Requirements:
    1. Expand to 30-50 words
    2. Clearly state the goal and approach
    3. Include key technical details
    4. Mention expected outcomes
    5. End with proper punctuation
    
    Respond with just the enhanced description text.
    """
  end
  
  @doc """
  Template for generating security requirements.
  """
  def security_requirements_template(params) do
    """
    Generate comprehensive security requirements for this authentication-related plan.
    
    Plan: #{params.plan_name}
    Description: #{params.plan_description}
    Tasks: #{params.task_summary}
    
    Generate security requirements covering:
    1. Authentication mechanisms
    2. Data protection
    3. Session management
    4. Access control
    5. Security best practices
    
    Respond with JSON:
    {
      "security_requirements": [
        "Requirement 1",
        "Requirement 2",
        "..."
      ],
      "authentication_strategy": "Brief description of auth approach",
      "security_considerations": [
        "Key security consideration 1",
        "Key security consideration 2"
      ]
    }
    """
  end
  
  @doc """
  Template for generating success criteria.
  """
  def success_criteria_template(params) do
    """
    Generate specific, measurable success criteria for this task.
    
    Task: #{params.task_name}
    Description: #{params.task_description}
    Plan Context: #{params.plan_context}
    
    Create 3-5 success criteria that are:
    1. Specific and measurable
    2. Directly related to the task
    3. Verifiable through testing or inspection
    4. Clear and unambiguous
    
    Respond with JSON:
    {
      "success_criteria": [
        "Criterion 1",
        "Criterion 2",
        "Criterion 3"
      ]
    }
    """
  end
  
  @doc """
  Template for adding testing strategy.
  """
  def testing_strategy_template(params) do
    """
    Create a comprehensive testing strategy for this plan.
    
    Plan: #{params.plan_name}
    Type: #{params.plan_type}
    Tasks: #{params.task_count} tasks
    Technologies: #{params.technologies}
    
    Include:
    1. Unit testing approach
    2. Integration testing needs
    3. Test coverage targets
    4. Testing tools/frameworks
    5. Critical test scenarios
    
    Respond with JSON:
    {
      "unit_test_approach": "Description",
      "integration_tests": ["Test scenario 1", "Test scenario 2"],
      "coverage_target": "percentage",
      "testing_framework": "framework name",
      "critical_scenarios": ["Scenario 1", "Scenario 2"]
    }
    """
  end
  
  @doc """
  Template for generating milestones.
  """
  def milestones_template(params) do
    """
    Generate incremental milestones for this plan.
    
    Plan: #{params.plan_name}
    Total Tasks: #{params.task_count}
    Estimated Duration: #{params.estimated_days} days
    Plan Type: #{params.plan_type}
    
    Create 3-5 milestones that:
    1. Represent meaningful progress points
    2. Are achievable and measurable
    3. Build upon each other
    4. Include rough timing estimates
    
    Respond with JSON:
    {
      "milestones": [
        {
          "name": "Milestone 1",
          "description": "What is achieved",
          "percentage_complete": 25,
          "estimated_day": 2
        }
      ]
    }
    """
  end
  
  @doc """
  Template for addressing feasibility concerns.
  """
  def feasibility_improvement_template(params) do
    """
    Address feasibility concerns for this plan.
    
    Plan: #{params.plan_name}
    Concerns: #{params.concerns}
    Current Scope: #{params.task_count} tasks
    
    Provide recommendations to improve feasibility:
    1. Scope adjustments if needed
    2. Task prioritization
    3. Risk mitigation strategies
    4. Resource requirements
    5. Timeline considerations
    
    Respond with JSON:
    {
      "scope_recommendations": ["Recommendation 1", "Recommendation 2"],
      "priority_tasks": ["Task ID 1", "Task ID 2"],
      "risk_mitigation": ["Strategy 1", "Strategy 2"],
      "resource_needs": ["Resource 1", "Resource 2"],
      "timeline_adjustment": "Recommendation for timeline"
    }
    """
  end
  
  @doc """
  Template for improving task complexity assessment.
  """
  def complexity_assessment_template(params) do
    """
    Assess and adjust task complexity based on description and dependencies.
    
    Task: #{params.task_name}
    Description: #{params.task_description}
    Current Complexity: #{params.current_complexity}
    Dependencies: #{params.dependency_count} dependencies
    
    Evaluate:
    1. Technical complexity
    2. Time requirements
    3. Skill requirements
    4. Risk factors
    
    Respond with JSON:
    {
      "recommended_complexity": "simple|medium|complex|very_complex",
      "complexity_factors": ["Factor 1", "Factor 2"],
      "time_estimate_hours": number,
      "required_skills": ["Skill 1", "Skill 2"],
      "main_risks": ["Risk 1", "Risk 2"]
    }
    """
  end
  
  @doc """
  Template for generating validation rules.
  """
  def validation_rules_template(params) do
    """
    Generate validation rules for this task.
    
    Task: #{params.task_name}
    Description: #{params.task_description}
    Task Type: #{params.task_type}
    Technologies: #{params.technologies}
    
    Create 2-4 validation rules that:
    1. Are specific to this task
    2. Can be objectively verified
    3. Cover both technical and quality aspects
    4. Are actionable
    
    Respond with JSON:
    {
      "validation_rules": [
        "Rule 1: Specific check",
        "Rule 2: Quality standard",
        "Rule 3: Technical requirement"
      ]
    }
    """
  end
  
  @doc """
  Template for adding interface definitions.
  """
  def interface_definition_template(params) do
    """
    Define interfaces and contracts for this task.
    
    Task: #{params.task_name}
    Description: #{params.task_description}
    Dependencies: #{params.dependencies}
    Plan Context: #{params.plan_context}
    
    Define:
    1. Input interfaces/parameters
    2. Output interfaces/return values
    3. Error handling contracts
    4. Integration points
    
    Respond with JSON:
    {
      "inputs": [
        {"name": "param1", "type": "string", "description": "Purpose"}
      ],
      "outputs": [
        {"name": "result1", "type": "map", "description": "What it contains"}
      ],
      "errors": [
        {"type": "validation_error", "description": "When it occurs"}
      ],
      "integration_points": [
        {"system": "System name", "interface": "Interface description"}
      ]
    }
    """
  end
  
  @doc """
  Template for generating documentation requirements.
  """
  def documentation_requirements_template(params) do
    """
    Generate documentation requirements for this plan.
    
    Plan: #{params.plan_name}
    Type: #{params.plan_type}
    Complexity: #{params.complexity}
    User-Facing: #{params.user_facing}
    
    Specify documentation needs:
    1. Code documentation standards
    2. API documentation if applicable
    3. User documentation if needed
    4. Architecture/design docs
    5. Deployment/operations docs
    
    Respond with JSON:
    {
      "code_documentation": ["Standard 1", "Standard 2"],
      "api_documentation": ["Endpoint docs", "Example usage"],
      "user_documentation": ["Guide 1", "Guide 2"],
      "technical_documentation": ["Architecture doc", "Design decisions"],
      "operational_documentation": ["Deployment guide", "Monitoring setup"]
    }
    """
  end
end