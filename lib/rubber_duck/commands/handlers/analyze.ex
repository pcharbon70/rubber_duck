defmodule RubberDuck.Commands.Handlers.Analyze do
  @moduledoc """
  Handler for code analysis commands.
  
  Integrates with the existing analysis engines to provide comprehensive
  code analysis including semantic, style, and security checks.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Commands.{Command, Handler}
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain

  @impl true
  def execute(%Command{name: :analyze, args: args, options: options} = command) do
    with :ok <- validate(command),
         {:ok, files} <- get_files_to_analyze(args.path, options),
         {:ok, results} <- analyze_files_with_cot(files, options) do
      {:ok, %{
        analysis_results: results,
        file_count: length(files),
        timestamp: DateTime.utc_now()
      }}
    end
  end

  def execute(_command) do
    {:error, "Invalid command for analyze handler"}
  end

  @impl true
  def validate(%Command{name: :analyze, args: args}) do
    with :ok <- Handler.validate_required_args(%{args: args}, [:path]) do
      # Path validation will be done when getting files to analyze
      :ok
    end
  end
  
  def validate(_), do: {:error, "Invalid command for analyze handler"}

  # Private functions

  defp get_files_to_analyze(path, options) do
    recursive = Map.get(options, :recursive, false)
    
    cond do
      File.regular?(path) ->
        {:ok, [path]}
        
      File.dir?(path) ->
        get_directory_files(path, recursive)
        
      true ->
        {:error, "Path not found: #{path}"}
    end
  end

  defp get_directory_files(dir, recursive) do
    try do
      files = if recursive do
        Path.wildcard(Path.join(dir, "**/*.{ex,exs}"))
      else
        Path.wildcard(Path.join(dir, "*.{ex,exs}"))
      end
      
      {:ok, files}
    rescue
      e -> {:error, "Failed to read directory: #{Exception.message(e)}"}
    end
  end

  defp analyze_files_with_cot(files, options) do
    analysis_type = Map.get(options, :type, "all")
    
    results = Enum.map(files, fn file ->
      case analyze_single_file_with_cot(file, analysis_type, options) do
        {:ok, result} -> result
        {:error, reason} ->
          %{
            file: file,
            error: reason,
            timestamp: DateTime.utc_now()
          }
      end
    end)
    
    {:ok, results}
  end

  defp analyze_single_file_with_cot(file_path, analysis_type, options) do
    with {:ok, content} <- File.read(file_path) do
      # Build context for CoT
      cot_context = %{
        code: content,
        context: %{
          file_path: file_path,
          analysis_type: analysis_type,
          project_context: Map.get(options, :project_context, %{}),
          language: "elixir"
        }
      }
      
      # Execute CoT analysis chain
      case ConversationManager.execute_chain(AnalysisChain, content, cot_context) do
        {:ok, cot_session} ->
          analysis_result = extract_analysis_result(cot_session)
          
          {:ok, %{
            file: file_path,
            type: analysis_type,
            issues: analysis_result.issues,
            suggestions: analysis_result.suggestions,
            metrics: %{
              lines: count_lines(file_path),
              complexity: analysis_result.complexity || 1
            },
            patterns: analysis_result.patterns,
            priorities: analysis_result.priorities,
            timestamp: DateTime.utc_now()
          }}
          
        {:error, reason} ->
          {:error, "CoT analysis failed: #{inspect(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end
  
  defp extract_analysis_result(cot_session) do
    # Extract results from the CoT session steps
    understanding = get_step_result(cot_session, :understand_code)
    patterns = get_step_result(cot_session, :identify_patterns)
    issues = get_step_result(cot_session, :analyze_issues)
    suggestions = get_step_result(cot_session, :suggest_improvements)
    priorities = get_step_result(cot_session, :prioritize_actions)
    
    # Parse and structure the results
    %{
      understanding: understanding,
      patterns: parse_patterns(patterns),
      issues: parse_issues(issues),
      suggestions: parse_suggestions(suggestions),
      priorities: parse_priorities(priorities),
      complexity: estimate_complexity(understanding, patterns)
    }
  end
  
  defp get_step_result(cot_session, step_name) do
    case Map.get(cot_session.steps, step_name) do
      %{result: result} -> result
      _ -> nil
    end
  end
  
  defp parse_patterns(patterns_text) when is_binary(patterns_text) do
    # Extract patterns from the text
    patterns_text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["pattern", "design", "structure"]))
    |> Enum.map(&String.trim/1)
  end
  defp parse_patterns(_), do: []
  
  defp parse_issues(issues_text) when is_binary(issues_text) do
    # Extract issues from the text
    issues_text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
    |> Enum.map(fn line ->
      %{
        description: String.replace(line, ~r/^\d+\.\s*/, ""),
        severity: determine_severity(line)
      }
    end)
  end
  defp parse_issues(_), do: []
  
  defp parse_suggestions(suggestions_text) when is_binary(suggestions_text) do
    # Extract suggestions from the text
    suggestions_text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
    |> Enum.map(&String.replace(&1, ~r/^\d+\.\s*/, ""))
  end
  defp parse_suggestions(_), do: []
  
  defp parse_priorities(priorities_text) when is_binary(priorities_text) do
    # Extract priority actions from the text
    %{
      critical: extract_priority_level(priorities_text, "critical"),
      high: extract_priority_level(priorities_text, "high"),
      medium: extract_priority_level(priorities_text, "medium"),
      low: extract_priority_level(priorities_text, "low")
    }
  end
  defp parse_priorities(_), do: %{critical: [], high: [], medium: [], low: []}
  
  defp extract_priority_level(text, level) do
    text
    |> String.downcase()
    |> String.split(level)
    |> Enum.at(1, "")
    |> String.split("\n")
    |> Enum.take(5)
    |> Enum.filter(&String.contains?(&1, ["-", "*", "•"]))
    |> Enum.map(&String.trim/1)
  end
  
  defp determine_severity(line) do
    cond do
      String.contains?(String.downcase(line), ["error", "bug", "security"]) -> :high
      String.contains?(String.downcase(line), ["warning", "performance"]) -> :medium
      true -> :low
    end
  end
  
  defp estimate_complexity(understanding, patterns) do
    # Simple heuristic for complexity estimation
    factors = [
      if(String.contains?(understanding || "", ["complex", "nested"]), do: 2, else: 0),
      if(String.contains?(patterns || "", ["recursion", "callback"]), do: 3, else: 0),
      if(String.contains?(understanding || "", ["simple", "straightforward"]), do: -1, else: 0)
    ]
    
    base_complexity = 1
    Enum.sum([base_complexity | factors]) |> max(1) |> min(10)
  end

  defp count_lines(file_path) do
    try do
      File.read!(file_path)
      |> String.split("\n")
      |> length()
    rescue
      _ -> 0
    end
  end
end