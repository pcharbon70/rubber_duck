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
    
    # Validate path first
    if is_nil(path) do
      {:error, "Path is required"}
    else
      analysis_type = args[:type] || :all
      recursive = if is_nil(args[:flags]), do: true, else: Keyword.get(args[:flags], :recursive, true)
      include_suggestions = if is_nil(args[:flags]), do: false, else: Keyword.get(args[:flags], :include_suggestions, false)

      require Logger
      Logger.info("Analyze command called with path: #{inspect(path)}, type: #{inspect(analysis_type)}")

      with {:ok, files} <- get_files_to_analyze(path, recursive),
           {:ok, results} <- analyze_files(files, analysis_type, include_suggestions, config) do
        Logger.info("Analysis completed with #{length(results)} file results")
        {:ok, format_results(results)}
      else
        {:error, _} = error ->
          Logger.error("Analysis failed: #{inspect(error)}")
          error
        error ->
          Logger.error("Analysis failed: #{inspect(error)}")
          {:error, error}
      end
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
    # Get all issues from the analysis result
    all_issues = Map.get(analysis_result, :all_issues, [])
    
    # Group issues by engine/analyzer type
    issues_by_engine = Map.get(analysis_result, :issues_by_engine, %{})
    
    # Create results for each analyzer that found issues
    analyzer_results = 
      issues_by_engine
      |> Enum.map(fn {analyzer_name, _issue_count} ->
        # Find issues for this analyzer
        analyzer_issues = 
          all_issues
          |> Enum.filter(fn issue ->
            # Extract analyzer from rule (e.g., "semantic/unused_function" -> :semantic)
            rule = Map.get(issue, :rule, "")
            String.starts_with?(rule, "#{analyzer_name}/")
          end)
          |> Enum.map(&format_issue_for_output/1)
        
        %{
          analyzer: analyzer_name,
          issues: analyzer_issues
        }
      end)
      |> Enum.filter(fn %{issues: issues} -> length(issues) > 0 end)

    %{
      file: file,
      results: analyzer_results,
      summary: %{
        total_issues: analysis_result.total_issues
      }
    }
  end
  
  defp format_issue_for_output(issue) do
    %{
      type: issue.type,
      details: issue.message,
      severity: issue.severity,
      line: get_in(issue, [:location, :line]) || 0,
      column: get_in(issue, [:location, :column]) || 0
    }
  end
  



  defp format_results([]) do
    {:error, "No files to analyze"}
  end
  
  defp format_results([single_result]) when is_map(single_result) do
    # Single file analysis
    %{
      type: :analysis,
      path: single_result.file,
      results: single_result.results
    }
  end
  
  defp format_results(results) when is_list(results) do
    # Multiple file analysis
    %{
      type: :analysis,
      results: results
    }
  end
end
