defmodule RubberDuck.Agents.Critics.SyntaxValidatorAgent do
  @moduledoc """
  A critic agent that validates code syntax in plans and tasks.
  
  This agent demonstrates how individual critics can be implemented
  as Jido agents that respond to validation requests from the
  Critics Coordinator Agent.
  
  ## Signals
  
  ### Input Signals
  - `validate` - Request to validate a target
    - Required: `target_type`, `target_id`, `target_data`, `request_id`
  
  ### Output Signals
  - `validation_result` - Result of the validation
    - Contains: `request_id`, `status`, `message`, `details`, `suggestions`
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "syntax_validator_agent",
    description: "Validates code syntax in plans and tasks",
    schema: [
      validations_performed: [type: :integer, default: 0],
      last_validation_at: [type: :any, default: nil],
      supported_languages: [type: {:list, :string}, default: ["elixir", "javascript", "python"]]
    ]
  
  alias RubberDuck.Analysis.AST
  
  require Logger
  
  @impl true
  def handle_signal(agent, %{"type" => "validate"} = signal) do
    request_id = signal["request_id"]
    target_data = signal["target_data"]
    
    if is_nil(request_id) or is_nil(target_data) do
      emit_validation_error(agent, request_id, "Missing required fields")
      {:ok, agent}
    else
      # Perform validation
      result = validate_syntax(target_data, agent.state.supported_languages)
      
      # Update state
      updated_state = %{agent.state |
        validations_performed: agent.state.validations_performed + 1,
        last_validation_at: DateTime.utc_now()
      }
      
      # Emit result
      emit_validation_result(agent, request_id, result)
      
      {:ok, %{agent | state: updated_state}}
    end
  end
  
  def handle_signal(agent, signal) do
    super(agent, signal)
  end
  
  # Private validation logic
  
  defp validate_syntax(target_data, supported_languages) do
    code_blocks = extract_code_blocks(target_data)
    
    if Enum.empty?(code_blocks) do
      %{
        status: "passed",
        message: "No code blocks found to validate",
        details: %{code_blocks_found: 0}
      }
    else
      results = Enum.map(code_blocks, fn block ->
        validate_code_block(block, supported_languages)
      end)
      
      aggregate_validation_results(results)
    end
  end
  
  defp extract_code_blocks(target_data) when is_map(target_data) do
    blocks = []
    
    # Check for code in various fields
    blocks = if target_data["code"], do: [%{code: target_data["code"], language: "elixir"}] ++ blocks, else: blocks
    blocks = if target_data["snippets"], do: extract_snippets(target_data["snippets"]) ++ blocks, else: blocks
    blocks = if target_data["description"], do: extract_from_markdown(target_data["description"]) ++ blocks, else: blocks
    
    blocks
  end
  
  defp extract_snippets(snippets) when is_list(snippets) do
    Enum.map(snippets, fn snippet ->
      case snippet do
        %{"code" => code, "language" => lang} -> %{code: code, language: lang}
        code when is_binary(code) -> %{code: code, language: "elixir"}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_snippets(_), do: []
  
  defp extract_from_markdown(text) when is_binary(text) do
    # Simple regex to extract code blocks from markdown
    ~r/```(\w+)?\n(.*?)```/s
    |> Regex.scan(text)
    |> Enum.map(fn
      [_, "", code] -> %{code: code, language: "elixir"}
      [_, lang, code] -> %{code: code, language: lang}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_from_markdown(_), do: []
  
  defp validate_code_block(%{code: code, language: language}, supported_languages) do
    if language in supported_languages do
      case validate_syntax_for_language(code, language) do
        :ok -> 
          %{status: :passed, language: language}
        {:error, reason} -> 
          %{status: :failed, language: language, error: reason}
      end
    else
      %{status: :skipped, language: language, reason: "Language not supported"}
    end
  end
  
  defp validate_syntax_for_language(code, "elixir") do
    case AST.parse(code, "elixir") do
      {:ok, _ast} -> :ok
      {:error, {line, error, _}} -> {:error, "Line #{line}: #{error}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
  
  defp validate_syntax_for_language(_code, language) do
    # Placeholder for other language validators
    Logger.debug("Syntax validation for #{language} not yet implemented")
    :ok
  end
  
  defp aggregate_validation_results(results) do
    failed = Enum.filter(results, fn r -> r.status == :failed end)
    passed = Enum.filter(results, fn r -> r.status == :passed end)
    skipped = Enum.filter(results, fn r -> r.status == :skipped end)
    
    cond do
      not Enum.empty?(failed) ->
        errors = Enum.map(failed, fn r -> 
          "#{r.language}: #{r.error}"
        end)
        
        %{
          status: "failed",
          message: "Syntax errors found in #{length(failed)} code block(s)",
          details: %{
            total_blocks: length(results),
            failed: length(failed),
            passed: length(passed),
            skipped: length(skipped),
            errors: errors
          },
          suggestions: [
            "Fix the syntax errors in the highlighted code blocks",
            "Run a linter on your code before submitting"
          ]
        }
        
      not Enum.empty?(skipped) and Enum.empty?(passed) ->
        %{
          status: "warning",
          message: "Could not validate code blocks - unsupported languages",
          details: %{
            total_blocks: length(results),
            skipped: length(skipped),
            languages: Enum.map(skipped, & &1.language) |> Enum.uniq()
          }
        }
        
      true ->
        %{
          status: "passed",
          message: "All code blocks have valid syntax",
          details: %{
            total_blocks: length(results),
            passed: length(passed),
            skipped: length(skipped)
          }
        }
    end
  end
  
  # Signal emission helpers
  
  defp emit_validation_result(agent, request_id, result) do
    emit_signal(agent, Map.merge(%{
      "type" => "validation_result",
      "request_id" => request_id,
      "critic_id" => agent.id,
      "critic_type" => "hard",
      "timestamp" => DateTime.utc_now()
    }, result))
  end
  
  defp emit_validation_error(agent, request_id, reason) do
    emit_signal(agent, %{
      "type" => "validation_result",
      "request_id" => request_id,
      "critic_id" => agent.id,
      "critic_type" => "hard",
      "status" => "error",
      "message" => reason,
      "timestamp" => DateTime.utc_now()
    })
  end
  
  # Health check
  
  @impl true
  def health_check(agent) do
    {:healthy, %{
      validations_performed: agent.state.validations_performed,
      last_validation_at: agent.state.last_validation_at,
      supported_languages: agent.state.supported_languages
    }}
  end
  
  # Registration helper
  
  @doc """
  Returns the registration signal for this critic.
  """
  def registration_signal(agent_id) do
    %{
      "type" => "register_critic",
      "critic_id" => agent_id,
      "critic_type" => "hard",
      "capabilities" => %{
        "targets" => ["task", "plan"],
        "languages" => ["elixir", "javascript", "python"],
        "priority" => 10,
        "description" => "Validates code syntax using AST parsing"
      }
    }
  end
end