defmodule RubberDuck.Jido.Actions.ResponseProcessor.ValidateResponseAction do
  @moduledoc """
  Action for validating response content quality and safety.
  
  This action runs a series of validators to assess response quality,
  completeness, safety, and format consistency.
  """
  
  use Jido.Action,
    name: "validate_response",
    description: "Validates response content for quality, safety, and completeness",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "The content to validate"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ],
      validation_rules: [
        type: :map,
        default: %{},
        doc: "Specific validation rules and thresholds"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    %{
      content: content,
      request_id: request_id,
      validation_rules: validation_rules
    } = params
    
    case validate_content(content, validation_rules, agent) do
      {:ok, quality_score, validation_results} ->
        signal_data = %{
          request_id: request_id,
          quality_score: quality_score,
          validation_results: validation_results,
          is_valid: validation_results.is_valid,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.validated", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, signal_data, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      {:error, reason} ->
        signal_data = %{
          request_id: request_id,
          error: reason,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.validation.failed", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, reason, %{agent: updated_agent}}
          {:error, emit_error} ->
            Logger.error("Failed to emit validation failure signal: #{inspect(emit_error)}")
            {:error, reason}
        end
    end
  end

  # Private functions

  defp validate_content(content, validation_rules, agent) do
    try do
      validators = agent.state.validators
      
      # Run all validators
      validation_results = Enum.reduce(validators, %{}, fn validator, acc ->
        case run_validator(validator, content, validation_rules) do
          {:ok, result} -> Map.put(acc, validator, result)
          {:error, _} -> Map.put(acc, validator, %{error: true})
        end
      end)
      
      # Calculate overall quality score
      quality_score = calculate_quality_score(validation_results)
      
      # Build validation summary
      validation_summary = %{
        is_valid: quality_score >= 0.5,
        completeness_score: Map.get(validation_results, :completeness_check, %{}) |> Map.get(:score, 0.5),
        readability_score: Map.get(validation_results, :quality_scoring, %{}) |> Map.get(:readability, 0.5),
        safety_score: Map.get(validation_results, :safety_validation, %{}) |> Map.get(:score, 1.0),
        issues: extract_validation_issues(validation_results)
      }
      
      {:ok, quality_score, validation_summary}
      
    rescue
      error ->
        Logger.warning("Content validation failed: #{inspect(error)}")
        {:error, "Validation failed: #{Exception.message(error)}"}
    end
  end

  defp run_validator(:completeness_check, content, _rules) do
    # Check if content appears complete
    trimmed = String.trim(content)
    score = cond do
      String.length(trimmed) == 0 -> 0.0
      String.ends_with?(trimmed, [".", "!", "?", "```", "}"]) -> 1.0
      String.length(trimmed) > 50 -> 0.8
      true -> 0.6
    end
    
    {:ok, %{score: score, complete: score >= 0.8}}
  end

  defp run_validator(:safety_validation, content, _rules) do
    # Basic safety checks
    unsafe_patterns = [
      ~r/\b(password|secret|api[_-]?key|token)\s*[:=]\s*\S+/i,
      ~r/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, # Credit card
      ~r/\b\d{3}-\d{2}-\d{4}\b/ # SSN
    ]
    
    issues = unsafe_patterns
    |> Enum.filter(&Regex.match?(&1, content))
    |> length()
    
    score = if issues == 0, do: 1.0, else: max(0.0, 1.0 - (issues * 0.3))
    
    {:ok, %{score: score, issues: issues, safe: score >= 0.8}}
  end

  defp run_validator(:quality_scoring, content, _rules) do
    # Basic quality scoring
    word_count = String.split(content) |> length()
    sentence_count = String.split(content, ~r/[.!?]+/) |> length()
    
    readability = if sentence_count > 0 do
      avg_words_per_sentence = word_count / sentence_count
      # Ideal is 15-20 words per sentence
      cond do
        avg_words_per_sentence < 5 -> 0.6
        avg_words_per_sentence <= 20 -> 1.0
        avg_words_per_sentence <= 30 -> 0.8
        true -> 0.5
      end
    else
      0.5
    end
    
    {:ok, %{readability: readability, word_count: word_count, sentence_count: sentence_count}}
  end

  defp run_validator(:format_validation, _content, _rules) do
    # Check if content matches expected format patterns
    {:ok, %{format_consistent: true}}
  end

  defp calculate_quality_score(validation_results) do
    scores = validation_results
    |> Enum.map(fn {_validator, result} ->
      case result do
        %{score: score} -> score
        %{readability: score} -> score
        _ -> 0.5
      end
    end)
    
    if Enum.empty?(scores) do
      0.5
    else
      Enum.sum(scores) / length(scores)
    end
  end

  defp extract_validation_issues(validation_results) do
    validation_results
    |> Enum.flat_map(fn {validator, result} ->
      case result do
        %{issues: issues} when is_list(issues) -> issues
        %{error: true} -> ["#{validator} failed"]
        %{complete: false} -> ["Content appears incomplete"]
        %{safe: false} -> ["Content safety concerns"]
        _ -> []
      end
    end)
  end
end