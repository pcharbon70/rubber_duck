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

    require Logger
    Logger.info("Analyze command called with path: #{inspect(path)}, type: #{inspect(analysis_type)}")

    with {:ok, files} <- get_files_to_analyze(path, recursive),
         {:ok, results} <- analyze_files(files, analysis_type, include_suggestions, config) do
      Logger.info("Analysis completed with #{length(results)} file results")
      format_results(results)
    else
      error ->
        Logger.error("Analysis failed: #{inspect(error)}")
        error
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

    require Logger
    Logger.info("Files to analyze: #{inspect(files)}")

    results =
      files
      |> Enum.with_index(1)
      |> Enum.map(fn {file, idx} ->
        unless config.quiet do
          Progress.show("Analyzing", idx, total, Path.basename(file))
        end

        result = analyze_single_file(file, analysis_type, include_suggestions)
        Logger.info("Single file result for #{file}: #{inspect(result)}")
        result
      end)
      |> Enum.reject(&match?({:error, _}, &1))
      |> Enum.map(fn {:ok, result} -> result end)

    Logger.info("Total results after filtering: #{length(results)}")

    unless config.quiet do
      Progress.clear()
      IO.puts("Analysis complete!")
    end

    {:ok, results}
  end

  defp analyze_single_file(file, analysis_type, _include_suggestions) do
    options = [
      engines: engines_for_type(analysis_type),
      min_severity: :info,
      parallel: true,
      cache: true
    ]

    case Analyzer.analyze_file(file, options) do
      {:ok, result} ->
        # Debug logging
        require Logger
        Logger.info("Analysis result for #{file}:")
        Logger.info("Result keys: #{inspect(Map.keys(result))}")
        Logger.info("Full result: #{inspect(result, pretty: true, limit: :infinity)}")

        {:ok, format_file_result(file, result)}

      {:error, reason} ->
        {:error, "Failed to analyze #{file}: #{reason}"}
    end
  rescue
    e ->
      {:error, "Error analyzing #{file}: #{Exception.message(e)}"}
  end

  defp engines_for_type(:all) do
    [RubberDuck.Analysis.Semantic, RubberDuck.Analysis.Style, RubberDuck.Analysis.Security]
  end

  defp engines_for_type(:semantic), do: [RubberDuck.Analysis.Semantic]
  defp engines_for_type(:style), do: [RubberDuck.Analysis.Style]
  defp engines_for_type(:security), do: [RubberDuck.Analysis.Security]
  defp engines_for_type(_), do: engines_for_type(:all)

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
    # The Analyzer returns issues in :all_issues field
    issues = Map.get(analysis_result, :all_issues, [])

    issues
    |> Enum.map(&normalize_issue/1)
    |> Enum.sort_by(fn issue -> {issue.line, issue.column} end)
  end

  defp normalize_issue(%{} = issue) do
    %{
      line: get_in(issue, [:location, :line]) || issue[:line] || 0,
      column: get_in(issue, [:location, :column]) || issue[:column] || 0,
      severity: issue[:severity] || :info,
      type: issue[:type] || :unknown,
      message: issue[:message] || "Unknown issue",
      suggestion: issue[:suggestion],
      category: issue[:category] || :unknown,
      rule: issue[:rule]
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
      total_issues: Map.get(analysis_result, :total_issues, 0),
      by_severity: Map.get(analysis_result, :issues_by_severity, %{}),
      by_type: Map.get(analysis_result, :issues_by_engine, %{})
    }
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
