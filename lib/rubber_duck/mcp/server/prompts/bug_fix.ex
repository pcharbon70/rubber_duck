defmodule RubberDuck.MCP.Server.Prompts.BugFix do
  @moduledoc """
  Generates prompts for debugging and fixing issues in code.
  
  This prompt helps AI assistants systematically approach bug fixing by
  providing structured debugging strategies and fix verification steps.
  """
  
  use Hermes.Server.Component, type: :prompt
  
  alias Hermes.Server.Frame
  
  schema do
    field :bug_description, {:required, :string},
      description: "Description of the bug or issue"
      
    field :error_message, :string,
      description: "Error message or stack trace if available"
      
    field :reproduction_steps, {:list, :string},
      description: "Steps to reproduce the issue"
      
    field :affected_code, :string,
      description: "Code suspected to contain the bug"
      
    field :expected_behavior, :string,
      description: "What should happen instead"
      
    field :debugging_level, {:enum, ["quick", "thorough", "deep"]},
      description: "How deep to go in debugging",
      default: "thorough"
  end
  
  @impl true
  def get_messages(params, frame) do
    messages = [
      %{
        "role" => "system",
        "content" => build_system_prompt(params.debugging_level)
      },
      %{
        "role" => "user",
        "content" => build_user_prompt(params)
      }
    ]
    
    {:ok, messages, frame}
  end
  
  defp build_system_prompt(debugging_level) do
    """
    You are an expert debugger and problem solver. Your task is to identify and fix bugs systematically.
    
    Debugging approach: #{debugging_level}
    
    Follow this methodology:
    1. **Understand**: Analyze the bug report and symptoms
    2. **Reproduce**: Verify you understand how to trigger the issue
    3. **Investigate**: Trace through the code to find root causes
    4. **Diagnose**: Identify why the bug occurs
    5. **Fix**: Implement a robust solution
    6. **Verify**: Ensure the fix works and doesn't break other things
    
    #{debugging_level_guidelines(debugging_level)}
    
    Structure your response:
    1. **Bug Analysis**: What's happening and why it's wrong
    2. **Root Cause**: The underlying issue(s)
    3. **Solution**: Specific fix with code
    4. **Testing**: How to verify the fix
    5. **Prevention**: How to avoid similar bugs
    """
  end
  
  defp build_user_prompt(params) do
    %{
      bug_description: description,
      error_message: error,
      reproduction_steps: steps,
      affected_code: code,
      expected_behavior: expected
    } = params
    
    error_section = if error do
      """
      
      Error message/stack trace:
      ```
      #{error}
      ```
      """
    else
      ""
    end
    
    steps_section = if steps && length(steps) > 0 do
      """
      
      Steps to reproduce:
      #{Enum.map_join(steps, "\n", &"#{&1}")}
      """
    else
      ""
    end
    
    code_section = if code do
      """
      
      Suspected code:
      ```elixir
      #{code}
      ```
      """
    else
      ""
    end
    
    expected_section = if expected do
      """
      
      Expected behavior:
      #{expected}
      """
    else
      ""
    end
    
    """
    Bug Description:
    #{description}
    #{error_section}
    #{steps_section}
    #{code_section}
    #{expected_section}
    
    Please help me debug and fix this issue.
    """
  end
  
  defp debugging_level_guidelines("quick") do
    """
    For quick debugging:
    - Focus on the most likely causes
    - Provide a direct fix if obvious
    - Skip extensive investigation if unnecessary
    """
  end
  
  defp debugging_level_guidelines("thorough") do
    """
    For thorough debugging:
    - Investigate multiple potential causes
    - Consider edge cases and interactions
    - Provide comprehensive fix with tests
    - Document any assumptions made
    """
  end
  
  defp debugging_level_guidelines("deep") do
    """
    For deep debugging:
    - Trace through all related code paths
    - Analyze system state and side effects
    - Consider performance and concurrency issues
    - Provide multiple solution approaches
    - Include detailed prevention strategies
    """
  end
end