defmodule RubberDuck.Workflows.ASTParsingWorkflow do
  @moduledoc """
  Workflow for batch parsing AST of multiple code files.

  Efficiently processes multiple files in parallel, with error handling
  and progress tracking.
  """

  use RubberDuck.Workflows.Workflow

  alias RubberDuck.Workspace.CodeFile

  @impl true
  def name, do: :ast_parsing

  @impl true
  def description, do: "Parse AST for multiple code files"

  @impl true
  def version, do: "1.0.0"

  workflow do
    step :validate_input do
      run ValidateInput
    end

    step :fetch_files do
      run FetchFiles
      argument :filters, result(:validate_input)
    end

    step :parse_ast_batch do
      run ParseASTBatch
      argument :files, result(:fetch_files)
      argument :options, result(:validate_input)
      max_retries 2
    end

    step :generate_summary do
      run GenerateSummary
      argument :results, result(:parse_ast_batch)
    end
  end

  # Step implementations

  defmodule ValidateInput do
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      filters = arguments[:filters] || %{}
      options = arguments[:options] || %{}

      validated = %{
        project_id: filters[:project_id],
        language: filters[:language],
        force: options[:force] || false,
        batch_size: options[:batch_size] || 10
      }

      {:ok, validated}
    end
  end

  defmodule FetchFiles do
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      filters = arguments[:filters] || %{}

      query = CodeFile

      query =
        if pid = filters[:project_id] do
          require Ash.Query
          Ash.Query.filter(query, project_id == ^pid)
        else
          query
        end

      query =
        if lang = filters[:language] do
          require Ash.Query
          Ash.Query.filter(query, language == ^lang)
        else
          query
        end

      # Filter for files that need AST parsing
      query =
        if !filters[:force] do
          require Ash.Query
          Ash.Query.filter(query, is_nil(ast_cache) or fragment("?->>'error' = ?", ast_cache, "true"))
        else
          query
        end

      case Ash.read(query) do
        {:ok, files} -> {:ok, files}
        {:error, error} -> {:error, {:fetch_failed, error}}
      end
    end
  end

  defmodule ParseASTBatch do
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      files = arguments[:files] || []
      options = arguments[:options] || %{}
      batch_size = options[:batch_size] || 10

      results =
        files
        |> Enum.chunk_every(batch_size)
        |> Enum.flat_map(&parse_batch(&1, options))

      successful = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _, _}, &1))

      {:ok,
       %{
         total: length(files),
         successful: length(successful),
         failed: length(failed),
         results: results
       }}
    end

    defp parse_batch(files, options) do
      files
      |> Task.async_stream(
        fn file ->
          case Ash.update(file, :parse_ast, %{force: options[:force]}) do
            {:ok, updated_file} ->
              {:ok,
               %{
                 file_id: file.id,
                 file_path: file.file_path,
                 parsed: true,
                 ast_summary: summarize_ast(updated_file.ast_cache)
               }}

            {:error, error} ->
              {:error, file.id, error}
          end
        end,
        max_concurrency: 5,
        timeout: 30_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, nil, :timeout}
        {:exit, reason} -> {:error, nil, reason}
      end)
    end

    defp summarize_ast(nil), do: nil
    defp summarize_ast(%{"error" => true} = ast), do: %{error: ast["reason"]}

    defp summarize_ast(ast) do
      %{
        type: ast["type"],
        module_name: ast["name"],
        function_count: length(ast["functions"] || []),
        dependency_count:
          length(ast["aliases"] || []) +
            length(ast["imports"] || []) +
            length(ast["requires"] || []),
        call_count: length(ast["calls"] || [])
      }
    end
  end

  defmodule GenerateSummary do
    use Reactor.Step

    @impl true
    def run(arguments, _context, _options) do
      results = arguments[:results]

      summary = %{
        workflow: "ast_parsing",
        completed_at: DateTime.utc_now(),
        statistics: %{
          total_files: results.total,
          successful: results.successful,
          failed: results.failed,
          success_rate: if(results.total > 0, do: results.successful / results.total * 100, else: 0)
        },
        insights: generate_insights(results.results)
      }

      {:ok, summary}
    end

    defp generate_insights(results) do
      successful_results = Enum.filter(results, &match?({:ok, _}, &1))

      ast_summaries =
        successful_results
        |> Enum.map(fn {:ok, result} -> result.ast_summary end)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&Map.has_key?(&1, :error))

      %{
        total_modules: Enum.count(ast_summaries, &(&1.type == "module")),
        total_functions: Enum.reduce(ast_summaries, 0, &(&1.function_count + &2)),
        average_functions_per_module: calculate_average(ast_summaries, :function_count),
        average_dependencies_per_module: calculate_average(ast_summaries, :dependency_count),
        most_complex_modules: find_most_complex(ast_summaries, 5)
      }
    end

    defp calculate_average([], _), do: 0

    defp calculate_average(summaries, field) do
      sum = Enum.reduce(summaries, 0, &(Map.get(&1, field, 0) + &2))
      Float.round(sum / length(summaries), 2)
    end

    defp find_most_complex(summaries, limit) do
      summaries
      |> Enum.sort_by(&(&1.function_count + &1.dependency_count), :desc)
      |> Enum.take(limit)
      |> Enum.map(&Map.take(&1, [:module_name, :function_count, :dependency_count]))
    end
  end

  @doc """
  Convenience function to run AST parsing for a project.

  ## Options

  - `:force` - Force reparsing even if AST cache exists (default: false)
  - `:batch_size` - Number of files to process in each batch (default: 10)

  ## Examples

      iex> ASTParsingWorkflow.parse_project(project_id)
      {:ok, %{statistics: %{total_files: 50, successful: 48, failed: 2}}}
  """
  def parse_project(project_id, opts \\ []) do
    input = %{
      filters: %{project_id: project_id},
      options: Keyword.take(opts, [:force, :batch_size])
    }

    run(input)
  end

  @doc """
  Parse AST for files of a specific language.
  """
  def parse_by_language(language, opts \\ []) do
    input = %{
      filters: %{language: to_string(language)},
      options: Keyword.take(opts, [:force, :batch_size])
    }

    run(input)
  end
end
