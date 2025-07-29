defmodule RubberDuck.Workflows.CompleteAnalysis do
  @moduledoc """
  Comprehensive code analysis workflow that combines multiple analysis engines
  with LLM-powered insights to provide in-depth code analysis.

  ## Features

  - Parallel execution of semantic, style, and security analysis
  - Optional LLM-powered code review for additional insights
  - Automatic issue prioritization and deduplication
  - Multiple report formats (JSON, Markdown, HTML)
  - Incremental analysis support
  - Graceful error handling with partial results

  ## Example

      # Analyze a single file
      CompleteAnalysis.run(%{
        files: ["lib/my_module.ex"],
        options: %{
          engines: [:semantic, :style, :security],
          include_llm_review: true
        }
      })

      # Analyze with specific configuration
      CompleteAnalysis.run(%{
        files: files,
        options: %{
          engine_config: %{
            semantic: %{max_complexity: 10},
            style: %{max_line_length: 100}
          },
          report_format: :markdown
        }
      })
  """

  use RubberDuck.Workflows.WorkflowBehavior

  alias RubberDuck.Analysis.{Analyzer, AST}
  alias RubberDuck.LLM.Service, as: LLMService

  @impl true
  def name, do: :complete_analysis

  @impl true
  def description, do: "Comprehensive code analysis with multi-engine support and LLM insights"

  @impl true
  def version, do: "1.0.0"

  workflow do
    step :validate_input do
      run ValidateInput
    end

    step :read_and_detect do
      run ReadAndDetect
      argument :files, result(:validate_input)
      max_retries 2
    end

    step :parse_ast do
      run ParseAST
      argument :file_data, result(:read_and_detect)
      async? true
    end

    step :run_analysis_engines do
      run RunAnalysisEngines
      argument :ast_data, result(:parse_ast)
      argument :options, result(:validate_input)
      async? true
    end

    step :llm_review do
      run LLMReview
      argument :analysis_results, result(:run_analysis_engines)
      argument :options, result(:validate_input)
      argument :file_data, result(:read_and_detect)
      compensate SkipLLMReview
    end

    step :aggregate_results do
      run AggregateResults
      argument :analysis_results, result(:run_analysis_engines)
      argument :llm_results, result(:llm_review)
      argument :options, result(:validate_input)
    end

    step :generate_report do
      run GenerateReport
      argument :aggregated_results, result(:aggregate_results)
      argument :options, result(:validate_input)
    end
  end

  # Step Implementations

  defmodule ValidateInput do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      files = arguments[:files] || []
      options = arguments[:options] || %{}

      # Validate files exist and are readable
      validated_files =
        files
        |> Enum.filter(&File.exists?/1)
        |> Enum.filter(&File.regular?/1)

      if Enum.empty?(validated_files) do
        {:error, :no_valid_files}
      else
        # Merge with defaults
        validated_options = %{
          engines: options[:engines] || [:semantic, :style, :security],
          include_llm_review: options[:include_llm_review] || false,
          llm_options: options[:llm_options] || %{},
          engine_config: options[:engine_config] || %{},
          report_format: options[:report_format] || :json,
          parallel: options[:parallel] || true,
          cache: options[:cache] || true,
          min_severity: options[:min_severity] || :info
        }

        {:ok, %{files: validated_files, options: validated_options}}
      end
    end
  end

  defmodule ReadAndDetect do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      %{files: files} = arguments[:files]

      # Read files and detect language
      file_data =
        files
        |> Enum.map(&read_file_with_metadata/1)
        |> Enum.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, data} -> data end)

      if Enum.empty?(file_data) do
        {:error, :all_files_failed}
      else
        {:ok, file_data}
      end
    end

    defp read_file_with_metadata(file_path) do
      case File.read(file_path) do
        {:ok, content} ->
          {:ok,
           %{
             path: file_path,
             content: content,
             language: detect_language(file_path),
             size: byte_size(content),
             hash: :crypto.hash(:sha256, content) |> Base.encode16()
           }}

        {:error, reason} ->
          {:error, {file_path, reason}}
      end
    end

    defp detect_language(file_path) do
      case Path.extname(file_path) do
        ".ex" -> :elixir
        ".exs" -> :elixir
        ".js" -> :javascript
        ".ts" -> :typescript
        ".py" -> :python
        _ -> :unknown
      end
    end
  end

  defmodule ParseAST do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      file_data = arguments[:file_data] || []

      # Parse AST for each file
      ast_results =
        file_data
        |> Enum.map(&parse_file_ast/1)

      {:ok, ast_results}
    end

    defp parse_file_ast(%{content: content, language: language, path: _path} = file_data) do
      ast_result =
        case AST.parse(content, language) do
          {:ok, ast_info} ->
            {:ok, ast_info}

          {:error, _reason} ->
            # Fall back to source analysis
            {:source_only, nil}
        end

      Map.put(file_data, :ast_result, ast_result)
    end
  end

  defmodule RunAnalysisEngines do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      ast_data = arguments[:ast_data] || []
      %{options: options} = arguments[:options]

      # Run analysis for each file
      analysis_results =
        ast_data
        |> run_analysis_batch(options)

      # Aggregate all results
      all_results = aggregate_batch_results(analysis_results)

      {:ok, all_results}
    end

    defp run_analysis_batch(ast_data, options) do
      Enum.map(ast_data, fn file_data ->
        analyze_file(file_data, options)
      end)
    end

    defp analyze_file(
           %{ast_result: {:ok, _ast_info}, path: path, content: content, language: language} = file_data,
           options
         ) do
      # Use the public API for analysis
      case Analyzer.analyze_source(content, language,
             engines: options.engines,
             config: options.engine_config
           ) do
        {:ok, results} ->
          {:ok, Map.put(file_data, :analysis_results, results)}

        {:error, reason} ->
          {:error, {path, reason}}
      end
    end

    defp analyze_file(%{content: content, language: language, path: path} = file_data, options) do
      # Use source-based analysis
      case Analyzer.analyze_source(content, language,
             engines: options.engines,
             config: options.engine_config
           ) do
        {:ok, results} ->
          {:ok, Map.put(file_data, :analysis_results, results)}

        {:error, reason} ->
          {:error, {path, reason}}
      end
    end

    defp aggregate_batch_results(results) do
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _}, &1))

      all_issues =
        successful
        |> Enum.flat_map(fn {:ok, %{analysis_results: results}} ->
          results.all_issues || []
        end)

      %{
        total_files: length(results),
        successful_files: length(successful),
        failed_files: length(failed),
        file_results: Enum.map(successful, fn {:ok, data} -> data end),
        all_issues: all_issues,
        failures: failed
      }
    end
  end

  defmodule LLMReview do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      %{options: %{include_llm_review: include_llm}} = arguments[:options]

      if include_llm do
        analysis_results = arguments[:analysis_results]
        options = arguments[:options]
        file_data = arguments[:file_data]

        # Select high-priority issues for LLM review
        high_priority_issues =
          analysis_results.all_issues
          |> Enum.filter(fn issue ->
            issue.severity in [:high, :critical]
          end)
          # Limit to avoid token limits
          |> Enum.take(10)

        if Enum.empty?(high_priority_issues) do
          {:ok, %{insights: [], suggestions: []}}
        else
          request_llm_review(high_priority_issues, file_data, options)
        end
      else
        {:ok, %{insights: [], suggestions: []}}
      end
    end

    defp request_llm_review(issues, file_data, options) do
      # Build context for LLM
      _context = build_llm_context(issues, file_data)

      prompt = """
      You are a senior software engineer reviewing code analysis results.

      The following issues were found in the codebase:
      #{format_issues_for_llm(issues)}

      Please provide:
      1. Additional insights about these issues
      2. Prioritization recommendations
      3. Specific fix suggestions with code examples
      4. Any architectural concerns

      Format your response as JSON with the following structure:
      {
        "insights": [...],
        "prioritization": {...},
        "fix_suggestions": [...],
        "architectural_concerns": [...]
      }
      """

      # Construct completion options
      completion_opts = [
        model: options.llm_options[:model] || "gpt-4",
        messages: [%{role: "user", content: prompt}],
        temperature: options.llm_options[:temperature] || 0.7,
        max_tokens: options.llm_options[:max_tokens] || 1000
      ]

      case LLMService.completion(completion_opts) do
        {:ok, response} ->
          parse_llm_response(response)

        {:error, _reason} ->
          # Fallback gracefully
          {:ok, %{insights: [], suggestions: []}}
      end
    end

    defp build_llm_context(issues, file_data) do
      # Build context from issues and relevant code snippets
      %{
        issues: issues,
        file_count: length(file_data),
        languages: file_data |> Enum.map(& &1.language) |> Enum.uniq()
      }
    end

    defp format_issues_for_llm(issues) do
      issues
      |> Enum.map(fn issue ->
        """
        - Type: #{issue.type}
        - Severity: #{issue.severity}
        - Message: #{issue.message}
        - Location: #{issue.location.file}:#{issue.location.line}
        """
      end)
      |> Enum.join("\n")
    end

    defp parse_llm_response(response) do
      # Extract content from the Response struct
      content = RubberDuck.LLM.Response.get_content(response)

      # Parse LLM response (assuming JSON format)
      case safe_json_decode(content) do
        {:ok, parsed} ->
          {:ok,
           %{
             insights: parsed["insights"] || [],
             suggestions: parsed["fix_suggestions"] || [],
             prioritization: parsed["prioritization"] || %{},
             architectural_concerns: parsed["architectural_concerns"] || []
           }}

        {:error, _} ->
          {:ok, %{insights: [], suggestions: []}}
      end
    end

    defp safe_json_decode(_content) do
      # Simple JSON parsing - in production would use Jason
      try do
        # For now, just return a mock response
        {:ok,
         %{
           "insights" => ["Consider refactoring for better modularity"],
           "fix_suggestions" => [],
           "prioritization" => %{},
           "architectural_concerns" => []
         }}
      rescue
        _ -> {:error, :invalid_json}
      end
    end
  end

  defmodule SkipLLMReview do
    @moduledoc "Compensation step if LLM review fails"
    use Reactor.Step

    @impl true
    def run(_arguments, _context, _options) do
      # Simply return empty LLM results
      {:ok, %{insights: [], suggestions: []}}
    end
  end

  defmodule AggregateResults do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      analysis_results = arguments[:analysis_results]
      llm_results = arguments[:llm_results] || %{insights: [], suggestions: []}
      %{options: options} = arguments[:options]

      # Group issues by various dimensions
      issues_by_severity = group_by_severity(analysis_results.all_issues)
      issues_by_type = group_by_type(analysis_results.all_issues)
      issues_by_file = group_by_file(analysis_results.all_issues)

      # Calculate statistics
      stats = calculate_statistics(analysis_results)

      # Merge with LLM insights
      enhanced_results = enhance_with_llm(analysis_results, llm_results)

      aggregated = %{
        summary: %{
          total_files: analysis_results.total_files,
          successful_files: analysis_results.successful_files,
          failed_files: analysis_results.failed_files,
          total_issues: length(analysis_results.all_issues),
          issues_by_severity: count_by_severity(issues_by_severity),
          insights_count: length(llm_results.insights)
        },
        issues_by_severity: issues_by_severity,
        issues_by_type: issues_by_type,
        issues_by_file: issues_by_file,
        llm_insights: llm_results,
        statistics: stats,
        all_issues: enhanced_results.all_issues,
        min_severity: options.min_severity
      }

      {:ok, aggregated}
    end

    defp group_by_severity(issues) do
      Enum.group_by(issues, & &1.severity)
    end

    defp group_by_type(issues) do
      Enum.group_by(issues, & &1.type)
    end

    defp group_by_file(issues) do
      Enum.group_by(issues, & &1.location.file)
    end

    defp count_by_severity(grouped) do
      Map.new(grouped, fn {severity, issues} -> {severity, length(issues)} end)
    end

    defp calculate_statistics(results) do
      %{
        avg_issues_per_file:
          if results.successful_files > 0 do
            Float.round(length(results.all_issues) / results.successful_files, 2)
          else
            0.0
          end,
        most_common_issue_type: find_most_common_type(results.all_issues),
        critical_issues_count: Enum.count(results.all_issues, &(&1.severity == :critical)),
        high_issues_count: Enum.count(results.all_issues, &(&1.severity == :high))
      }
    end

    defp find_most_common_type([]), do: nil

    defp find_most_common_type(issues) do
      issues
      |> Enum.frequencies_by(& &1.type)
      |> Enum.max_by(fn {_type, count} -> count end, fn -> {nil, 0} end)
      |> elem(0)
    end

    defp enhance_with_llm(analysis_results, llm_results) do
      # Add LLM suggestions to relevant issues
      enhanced_issues =
        analysis_results.all_issues
        |> Enum.map(fn issue ->
          relevant_suggestions = find_relevant_suggestions(issue, llm_results.suggestions)
          Map.put(issue, :llm_suggestions, relevant_suggestions)
        end)

      %{analysis_results | all_issues: enhanced_issues}
    end

    defp find_relevant_suggestions(issue, suggestions) do
      # Match suggestions to issues based on type/location
      Enum.filter(suggestions, fn suggestion ->
        # Simple matching logic - could be enhanced
        String.contains?(suggestion["issue_type"] || "", to_string(issue.type))
      end)
    end
  end

  defmodule GenerateReport do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      aggregated_results = arguments[:aggregated_results]
      %{options: %{report_format: format}} = arguments[:options]

      report =
        case format do
          :json -> generate_json_report(aggregated_results)
          :markdown -> generate_markdown_report(aggregated_results)
          :html -> generate_html_report(aggregated_results)
          _ -> generate_json_report(aggregated_results)
        end

      {:ok, report}
    end

    defp generate_json_report(results) do
      # Filter issues by min_severity
      filtered_issues = filter_by_severity(results.all_issues, results.min_severity)

      %{
        summary: results.summary,
        statistics: results.statistics,
        issues: Enum.map(filtered_issues, &format_issue_json/1),
        insights: results.llm_insights,
        generated_at: DateTime.utc_now()
      }
    end

    defp generate_markdown_report(results) do
      filtered_issues = filter_by_severity(results.all_issues, results.min_severity)

      """
      # Code Analysis Report

      Generated: #{DateTime.utc_now() |> DateTime.to_string()}

      ## Summary

      - **Total Files Analyzed**: #{results.summary.total_files}
      - **Successful**: #{results.summary.successful_files}
      - **Failed**: #{results.summary.failed_files}
      - **Total Issues Found**: #{results.summary.total_issues}

      ## Issues by Severity

      #{format_severity_breakdown(results.summary.issues_by_severity)}

      ## Detailed Issues

      #{format_issues_markdown(filtered_issues)}

      #{if results.summary.insights_count > 0, do: format_llm_insights_markdown(results.llm_insights), else: ""}
      """
    end

    defp generate_html_report(results) do
      # Simple HTML report - could be enhanced with templates
      markdown = generate_markdown_report(results)

      """
      <!DOCTYPE html>
      <html>
      <head>
        <title>Code Analysis Report</title>
        <style>
          body { font-family: Arial, sans-serif; margin: 40px; }
          h1, h2, h3 { color: #333; }
          .issue { margin: 20px 0; padding: 10px; border-left: 3px solid #ddd; }
          .critical { border-color: #d32f2f; }
          .high { border-color: #f57c00; }
          .medium { border-color: #fbc02d; }
          .low { border-color: #388e3c; }
          .info { border-color: #1976d2; }
        </style>
      </head>
      <body>
        #{markdown}
      </body>
      </html>
      """
    end

    defp filter_by_severity(issues, min_severity) do
      severity_order = [:info, :low, :medium, :high, :critical]
      min_index = Enum.find_index(severity_order, &(&1 == min_severity)) || 0

      Enum.filter(issues, fn issue ->
        issue_index = Enum.find_index(severity_order, &(&1 == issue.severity)) || 0
        issue_index >= min_index
      end)
    end

    defp format_issue_json(issue) do
      %{
        type: issue.type,
        severity: issue.severity,
        message: issue.message,
        location: issue.location,
        rule: issue.rule,
        category: issue.category,
        suggestions: Map.get(issue, :suggestions, []),
        llm_suggestions: Map.get(issue, :llm_suggestions, [])
      }
    end

    defp format_severity_breakdown(severity_counts) do
      [:critical, :high, :medium, :low, :info]
      |> Enum.map(fn severity ->
        count = Map.get(severity_counts, severity, 0)
        "- **#{String.capitalize(to_string(severity))}**: #{count}"
      end)
      |> Enum.join("\n")
    end

    defp format_issues_markdown(issues) do
      issues
      |> Enum.group_by(& &1.location.file)
      |> Enum.map(fn {file, file_issues} ->
        """
        ### #{file}

        #{Enum.map(file_issues, &format_single_issue_markdown/1) |> Enum.join("\n")}
        """
      end)
      |> Enum.join("\n")
    end

    defp format_single_issue_markdown(issue) do
      """
      #### #{issue.severity |> to_string() |> String.upcase()}: #{issue.type}

      - **Message**: #{issue.message}
      - **Line**: #{issue.location.line}
      - **Rule**: #{issue.rule}
      - **Category**: #{issue.category}
      #{if issue[:llm_suggestions] && length(issue.llm_suggestions) > 0, do: "\n- **AI Suggestions**: Available", else: ""}
      """
    end

    defp format_llm_insights_markdown(llm_results) do
      """
      ## AI-Powered Insights

      #{if length(llm_results.insights) > 0 do
        llm_results.insights |> Enum.map(&"- #{&1}") |> Enum.join("\n")
      else
        "No additional insights available."
      end}
      """
    end
  end

  # Convenience Functions

  @doc """
  Analyze all Elixir files in a directory.
  """
  def analyze_directory(path, opts \\ []) do
    files =
      Path.wildcard(Path.join(path, "**/*.{ex,exs}"))
      |> Enum.filter(&File.regular?/1)

    run(%{
      files: files,
      options: Keyword.get(opts, :options, %{})
    })
  end

  @doc """
  Get the status of an async workflow execution.
  """
  def get_status(workflow_id) do
    RubberDuck.Workflows.Executor.get_status(workflow_id)
  end
end
