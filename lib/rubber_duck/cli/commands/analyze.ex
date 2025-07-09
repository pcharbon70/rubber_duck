defmodule RubberDuck.CLI.Commands.Analyze do
  @moduledoc """
  CLI command for analyzing code files and projects.

  Integrates with the existing analysis engines to provide comprehensive
  code analysis including semantic, style, and security checks.
  """

  alias RubberDuck.Analysis.Analyzer
  alias RubberDuck.CLI.Utils.Progress

  @doc """
  Runs the analyze command with the given arguments and configuration.
  """
  def run(args, config) do
    path = args[:path]
    analysis_type = args[:type] || :all
    recursive = Keyword.get(args[:flags], :recursive, true)
    include_suggestions = Keyword.get(args[:flags], :include_suggestions, false)

    with {:ok, files} <- get_files_to_analyze(path, recursive),
         {:ok, results} <- analyze_files(files, analysis_type, include_suggestions, config) do
      format_results(results)
    end
  end

  defp get_files_to_analyze(path, recursive) do
    cond do
      File.regular?(path) ->
        {:ok, [path]}

      File.dir?(path) ->
        get_directory_files(path, recursive)

      true ->
        {:error, "Path does not exist: #{path}"}
    end
  end

  defp get_directory_files(dir, recursive) do
    pattern = if recursive, do: "**/*.{ex,exs,py,js,ts}", else: "*.{ex,exs,py,js,ts}"

    files =
      Path.join(dir, pattern)
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    if Enum.empty?(files) do
      {:error, "No supported files found in #{dir}"}
    else
      {:ok, files}
    end
  end

  defp analyze_files(files, analysis_type, include_suggestions, config) do
    total = length(files)

    unless config.quiet do
      IO.puts("Analyzing #{total} file(s)...")
    end

    results =
      files
      |> Enum.with_index(1)
      |> Enum.map(fn {file, idx} ->
        unless config.quiet do
          Progress.show("Analyzing", idx, total, Path.basename(file))
        end

        analyze_single_file(file, analysis_type, include_suggestions)
      end)
      |> Enum.reject(&match?({:error, _}, &1))
      |> Enum.map(fn {:ok, result} -> result end)

    unless config.quiet do
      Progress.clear()
      IO.puts("Analysis complete!")
    end

    {:ok, results}
  end

  defp analyze_single_file(file, analysis_type, include_suggestions) do
    options = %{
      analysis_types: normalize_analysis_types(analysis_type),
      include_suggestions: include_suggestions,
      file_path: file
    }

    case Analyzer.analyze_file(file, options) do
      {:ok, result} ->
        {:ok, format_file_result(file, result)}

      {:error, reason} ->
        {:error, "Failed to analyze #{file}: #{reason}"}
    end
  rescue
    e ->
      {:error, "Error analyzing #{file}: #{Exception.message(e)}"}
  end

  defp normalize_analysis_types(:all), do: [:semantic, :style, :security]
  defp normalize_analysis_types(type) when is_atom(type), do: [type]
  defp normalize_analysis_types(types) when is_list(types), do: types

  defp format_file_result(file, analysis_result) do
    issues = extract_issues(analysis_result)
    severity = calculate_overall_severity(issues)

    %{
      file: file,
      issues: issues,
      severity: severity,
      summary: build_summary(analysis_result)
    }
  end

  defp extract_issues(analysis_result) do
    # Extract issues from different analysis types
    semantic_issues = get_in(analysis_result, [:semantic, :issues]) || []
    style_issues = get_in(analysis_result, [:style, :issues]) || []
    security_issues = get_in(analysis_result, [:security, :issues]) || []

    (semantic_issues ++ style_issues ++ security_issues)
    |> Enum.map(&normalize_issue/1)
    |> Enum.sort_by(fn issue -> {issue.line, issue.column} end)
  end

  defp normalize_issue(%{} = issue) do
    %{
      line: issue[:line] || 0,
      column: issue[:column] || 0,
      severity: issue[:severity] || :info,
      type: issue[:type] || :unknown,
      message: issue[:message] || "Unknown issue",
      suggestion: issue[:suggestion]
    }
  end

  defp calculate_overall_severity(issues) do
    severities = Enum.map(issues, & &1.severity)

    cond do
      :error in severities -> :error
      :warning in severities -> :warning
      :info in severities -> :info
      true -> :none
    end
  end

  defp build_summary(analysis_result) do
    %{
      total_issues: count_all_issues(analysis_result),
      by_severity: count_by_severity(analysis_result),
      by_type: count_by_type(analysis_result)
    }
  end

  defp count_all_issues(analysis_result) do
    [:semantic, :style, :security]
    |> Enum.map(fn type ->
      get_in(analysis_result, [type, :issues]) || []
    end)
    |> Enum.map(&length/1)
    |> Enum.sum()
  end

  defp count_by_severity(analysis_result) do
    all_issues =
      [:semantic, :style, :security]
      |> Enum.flat_map(fn type ->
        get_in(analysis_result, [type, :issues]) || []
      end)

    Enum.reduce(all_issues, %{error: 0, warning: 0, info: 0}, fn issue, acc ->
      severity = issue[:severity] || :info
      Map.update(acc, severity, 1, &(&1 + 1))
    end)
  end

  defp count_by_type(analysis_result) do
    [:semantic, :style, :security]
    |> Enum.map(fn type ->
      issues = get_in(analysis_result, [type, :issues]) || []
      {type, length(issues)}
    end)
    |> Enum.into(%{})
  end

  defp format_results(results) do
    %{
      type: :analysis,
      results: results,
      summary: build_overall_summary(results)
    }
  end

  defp build_overall_summary(results) do
    total_files = length(results)
    total_issues = Enum.sum(Enum.map(results, fn r -> r.summary.total_issues end))
    files_with_issues = Enum.count(results, fn r -> r.summary.total_issues > 0 end)

    %{
      total_files: total_files,
      files_with_issues: files_with_issues,
      total_issues: total_issues
    }
  end
end
