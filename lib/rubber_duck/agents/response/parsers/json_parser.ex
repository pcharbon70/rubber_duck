defmodule RubberDuck.Agents.Response.Parser.JSONParser do
  @moduledoc """
  JSON response parser with error recovery and validation.
  """

  use RubberDuck.Agents.Response.Parser
  require Logger

  @impl true
  def parse(content, options \\ %{}) do
    content = clean_json_content(content)
    
    case Jason.decode(content) do
      {:ok, parsed} ->
        {:ok, parsed}
        
      {:error, %Jason.DecodeError{} = error} ->
        # Try to recover from common JSON formatting issues
        case attempt_json_recovery(content, error) do
          {:ok, recovered_content} ->
            case Jason.decode(recovered_content) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, _} -> {:error, "JSON parsing failed after recovery attempt"}
            end
            
          {:error, _} ->
            # If recovery fails, try extracting partial JSON
            extract_partial_json(content, options)
        end
    end
  end

  @impl true
  def detect(content) do
    confidence = calculate_json_confidence(content)
    {:ok, confidence}
  end

  @impl true
  def format, do: :json

  @impl true
  def supports_streaming?, do: false

  # Private functions

  defp clean_json_content(content) do
    content
    |> String.trim()
    |> remove_markdown_code_blocks()
    |> remove_leading_text()
    |> fix_common_issues()
  end

  defp remove_markdown_code_blocks(content) do
    case Regex.run(~r/```(?:json)?\s*(\{.*\}|\[.*\])\s*```/s, content, capture: :all_but_first) do
      [json_content] -> json_content
      _ -> content
    end
  end

  defp remove_leading_text(content) do
    # Remove leading explanatory text
    case Regex.run(~r/(\{.*\}|\[.*\])$/s, content, capture: :all_but_first) do
      [json_content] -> json_content
      _ -> content
    end
  end

  defp fix_common_issues(content) do
    content
    |> fix_trailing_commas()
    |> fix_single_quotes()
    |> fix_unquoted_keys()
  end

  defp fix_trailing_commas(content) do
    content
    |> String.replace(~r/,(\s*[\}\]])/, "\\1")
  end

  defp fix_single_quotes(content) do
    # Convert single quotes to double quotes for keys and string values
    content
    |> String.replace(~r/'([^']*)'(\s*:)/, "\"\\1\"\\2")  # Keys
    |> String.replace(~r/:\s*'([^']*)'/, ": \"\\1\"")    # Values
  end

  defp fix_unquoted_keys(content) do
    # Add quotes around unquoted keys
    Regex.replace(~r/(\{|\,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/, content, "\\1\"\\2\":")
  end

  defp attempt_json_recovery(content, error) do
    recovery_strategies = [
      &fix_missing_quotes/1,
      &fix_truncated_json/1,
      &extract_first_complete_object/1,
      &fix_escaped_quotes/1
    ]
    
    Enum.reduce_while(recovery_strategies, {:error, error}, fn strategy, _acc ->
      case strategy.(content) do
        {:ok, recovered} -> {:halt, {:ok, recovered}}
        {:error, _} -> {:cont, {:error, error}}
      end
    end)
  end

  defp fix_missing_quotes(content) do
    # Try to fix missing quotes around string values
    fixed = Regex.replace(~r/:\s*([a-zA-Z][a-zA-Z0-9\s]*[a-zA-Z0-9])\s*([,\}])/, content, ": \"\\1\"\\2")
    
    if fixed != content do
      {:ok, fixed}
    else
      {:error, "No missing quotes found"}
    end
  end

  defp fix_truncated_json(content) do
    # Try to close incomplete JSON structures
    open_braces = String.graphemes(content) |> Enum.count(&(&1 == "{"))
    close_braces = String.graphemes(content) |> Enum.count(&(&1 == "}"))
    open_brackets = String.graphemes(content) |> Enum.count(&(&1 == "["))
    close_brackets = String.graphemes(content) |> Enum.count(&(&1 == "]"))
    
    missing_close_braces = open_braces - close_braces
    missing_close_brackets = open_brackets - close_brackets
    
    if missing_close_braces > 0 or missing_close_brackets > 0 do
      fixed = content <>
        String.duplicate("}", missing_close_braces) <>
        String.duplicate("]", missing_close_brackets)
      {:ok, fixed}
    else
      {:error, "JSON appears complete"}
    end
  end

  defp extract_first_complete_object(content) do
    # Extract the first complete JSON object or array
    case find_complete_json_structure(content) do
      {:ok, extracted} -> {:ok, extracted}
      :error -> {:error, "No complete JSON structure found"}
    end
  end

  defp fix_escaped_quotes(content) do
    # Fix improperly escaped quotes
    fixed = String.replace(content, ~r/\\"/,  "\"")
    
    if fixed != content do
      {:ok, fixed}
    else
      {:error, "No escaped quotes found"}
    end
  end

  defp find_complete_json_structure(content) do
    # Try to find a complete JSON object starting from the beginning
    case find_matching_brace(content, 0, 0, 0) do
      {:ok, end_pos} -> {:ok, String.slice(content, 0..end_pos)}
      :error -> 
        case find_matching_bracket(content, 0, 0, 0) do
          {:ok, end_pos} -> {:ok, String.slice(content, 0..end_pos)}
          :error -> :error
        end
    end
  end

  defp find_matching_brace(content, pos, depth, start_pos) do
    if pos < String.length(content) do
      char = String.at(content, pos)
      
      case char do
        "{" when depth == 0 -> find_matching_brace(content, pos + 1, 1, pos)
        "{" -> find_matching_brace(content, pos + 1, depth + 1, start_pos)
        "}" when depth == 1 -> {:ok, pos}
        "}" -> find_matching_brace(content, pos + 1, depth - 1, start_pos)
        _ -> find_matching_brace(content, pos + 1, depth, start_pos)
      end
    else
      {:error, "No matching brace found"}
    end
  end

  defp find_matching_bracket(content, pos, depth, start_pos) do
    if pos < String.length(content) do
      char = String.at(content, pos)
      
      case char do
        "[" when depth == 0 -> find_matching_bracket(content, pos + 1, 1, pos)
        "[" -> find_matching_bracket(content, pos + 1, depth + 1, start_pos)
        "]" when depth == 1 -> {:ok, pos}
        "]" -> find_matching_bracket(content, pos + 1, depth - 1, start_pos)
        _ -> find_matching_bracket(content, pos + 1, depth, start_pos)
      end
    else
      {:error, "No matching bracket found"}
    end
  end

  defp extract_partial_json(content, options) do
    if Map.get(options, :allow_partial, false) do
      # Extract key-value pairs even from malformed JSON
      case extract_key_value_pairs(content) do
        {:ok, pairs} when pairs != [] -> {:ok, Map.new(pairs)}
        _ -> {:error, "No valid JSON content found"}
      end
    else
      {:error, "JSON parsing failed and partial extraction not allowed"}
    end
  end

  defp extract_key_value_pairs(content) do
    # Extract key-value pairs using regex
    pairs = Regex.scan(~r/"([^"]+)"\s*:\s*"([^"]+)"|"([^"]+)"\s*:\s*([^,\}\]]+)/, content)
    |> Enum.map(fn
      [_, key, value, "", ""] -> {key, value}
      [_, "", "", key, value] -> {key, String.trim(value)}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    
    {:ok, pairs}
  end

  defp calculate_json_confidence(content) do
    indicators = [
      {~r/^\s*[\{\[]/, 0.3},
      {~r/[\}\]]\s*$/, 0.3},
      {~r/"[^"]*"\s*:\s*/, 0.4},
      {~r/^\s*\{.*\}\s*$/s, 0.8},
      {~r/^\s*\[.*\]\s*$/s, 0.8}
    ]
    
    indicators
    |> Enum.map(fn {pattern, weight} ->
      if Regex.match?(pattern, content), do: weight, else: 0.0
    end)
    |> Enum.sum()
    |> min(1.0)
  end
end