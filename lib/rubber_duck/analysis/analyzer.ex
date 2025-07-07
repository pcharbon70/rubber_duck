defmodule RubberDuck.Analysis.Analyzer do
  @moduledoc """
  Orchestrates multiple analysis engines to provide comprehensive code analysis.

  The Analyzer coordinates the execution of semantic, style, and security
  analysis engines, aggregates their results, and provides a unified
  analysis report with prioritized issues and suggestions.
  """

  alias RubberDuck.Analysis.{AST, Engine, Security, Semantic, Style}
  alias RubberDuck.Workspace

  require Logger

  @type analysis_options :: [
          engines: list(module()),
          config: map(),
          min_severity: Engine.severity(),
          parallel: boolean(),
          cache: boolean()
        ]

  @type aggregated_result :: %{
          file: String.t(),
          total_issues: non_neg_integer(),
          issues_by_severity: map(),
          issues_by_engine: map(),
          all_issues: list(Engine.issue()),
          metrics: map(),
          suggestions: map(),
          execution_time: non_neg_integer()
        }

  @default_engines [Semantic, Style, Security]

  @doc """
  Analyzes a code file using all configured analysis engines.

  Options:
  - `:engines` - List of engine modules to use (default: all)
  - `:config` - Configuration overrides for engines
  - `:min_severity` - Minimum severity to include in results
  - `:parallel` - Run engines in parallel (default: true)
  - `:cache` - Use cached results if available (default: true)
  """
  @spec analyze_file(String.t(), analysis_options()) :: {:ok, aggregated_result()} | {:error, term()}
  def analyze_file(file_path, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, content} <- File.read(file_path),
         {:ok, ast_info} <- parse_file(file_path, content),
         {:ok, results} <- run_engines(ast_info, file_path, opts) do
      aggregated = aggregate_results(results, file_path)
      execution_time = System.monotonic_time(:millisecond) - start_time

      {:ok, Map.put(aggregated, :execution_time, execution_time)}
    end
  end

  @doc """
  Analyzes source code directly without a file.
  """
  @spec analyze_source(String.t(), atom(), analysis_options()) :: {:ok, aggregated_result()} | {:error, term()}
  def analyze_source(source, language, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Try to parse AST if it's Elixir
    ast_result =
      if language == :elixir do
        AST.parse(source, :elixir)
      else
        {:error, :unsupported_language}
      end

    engines = Keyword.get(opts, :engines, @default_engines)
    parallel = Keyword.get(opts, :parallel, true)

    results =
      case ast_result do
        {:ok, ast_info} ->
          # Run AST-based analysis
          run_engines(ast_info, "source", opts)

        {:error, _} ->
          # Fall back to source-based analysis
          if parallel do
            run_engines_parallel_source(engines, source, language, opts)
          else
            run_engines_sequential_source(engines, source, language, opts)
          end
      end

    case results do
      {:ok, engine_results} ->
        aggregated = aggregate_results(engine_results, "source")
        execution_time = System.monotonic_time(:millisecond) - start_time

        {:ok, Map.put(aggregated, :execution_time, execution_time)}

      error ->
        error
    end
  end

  @doc """
  Analyzes a CodeFile resource from the database.
  """
  @spec analyze_code_file(Workspace.CodeFile.t(), analysis_options()) :: {:ok, aggregated_result()} | {:error, term()}
  def analyze_code_file(%Workspace.CodeFile{} = code_file, opts \\ []) do
    # Check if we have cached AST
    ast_info =
      if code_file.ast_cache && !code_file.ast_cache["error"] do
        # Convert cached AST back to our format
        deserialize_ast_info(code_file.ast_cache)
      else
        # Parse the content
        case AST.parse(code_file.content, String.to_atom(code_file.language || "elixir")) do
          {:ok, ast} -> ast
          _ -> nil
        end
      end

    if ast_info do
      run_engines(ast_info, code_file.file_path, opts)
      |> case do
        {:ok, results} -> {:ok, aggregate_results(results, code_file.file_path)}
        error -> error
      end
    else
      # Fallback to source analysis
      analyze_source(code_file.content, String.to_atom(code_file.language || "unknown"), opts)
    end
  end

  @doc """
  Returns available analysis engines.
  """
  @spec available_engines() :: list(module())
  def available_engines, do: @default_engines

  @doc """
  Returns the combined default configuration for all engines.
  """
  @spec default_config() :: map()
  def default_config do
    @default_engines
    |> Enum.map(fn engine -> {engine.name(), engine.default_config()} end)
    |> Map.new()
  end

  # Private functions

  defp parse_file(file_path, content) do
    language = detect_language(file_path)

    case AST.parse(content, language) do
      {:ok, ast_info} -> {:ok, ast_info}
      # Continue with source analysis
      {:error, _reason} -> {:ok, nil}
    end
  end

  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".ts" -> :typescript
      _ -> :unknown
    end
  end

  defp run_engines(nil, file_path, opts) do
    # No AST available, run source-based analysis
    content = File.read!(file_path)
    language = detect_language(file_path)
    engines = Keyword.get(opts, :engines, @default_engines)

    if Keyword.get(opts, :parallel, true) do
      run_engines_parallel_source(engines, content, language, opts)
    else
      run_engines_sequential_source(engines, content, language, opts)
    end
  end

  defp run_engines(ast_info, file_path, opts) do
    engines = Keyword.get(opts, :engines, @default_engines)
    config = Keyword.get(opts, :config, %{})

    if Keyword.get(opts, :parallel, true) do
      run_engines_parallel(engines, ast_info, config)
    else
      run_engines_sequential(engines, ast_info, config)
    end
  end

  defp run_engines_parallel(engines, ast_info, config) do
    tasks =
      Enum.map(engines, fn engine ->
        Task.async(fn ->
          engine_config = Map.get(config, engine.name(), %{})
          {engine, engine.analyze(ast_info, config: engine_config)}
        end)
      end)

    results = Task.await_many(tasks, 30_000)

    # Check for errors
    errors =
      Enum.filter(results, fn {_, result} ->
        match?({:error, _}, result)
      end)

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {engine, {:ok, result}} -> {engine, result} end)}
    else
      {:error, {:engine_errors, Enum.map(errors, fn {engine, {:error, reason}} -> {engine, reason} end)}}
    end
  end

  defp run_engines_sequential(engines, ast_info, config) do
    results =
      Enum.reduce_while(engines, {:ok, []}, fn engine, {:ok, acc} ->
        engine_config = Map.get(config, engine.name(), %{})

        case engine.analyze(ast_info, config: engine_config) do
          {:ok, result} -> {:cont, {:ok, [{engine, result} | acc]}}
          {:error, reason} -> {:halt, {:error, {engine, reason}}}
        end
      end)

    case results do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp run_engines_parallel_source(engines, source, language, opts) do
    config = Keyword.get(opts, :config, %{})

    tasks =
      Enum.map(engines, fn engine ->
        Task.async(fn ->
          if function_exported?(engine, :analyze_source, 3) do
            engine_config = Map.get(config, engine.name(), %{})
            {engine, engine.analyze_source(source, language, config: engine_config)}
          else
            {engine, {:ok, %{engine: engine.name(), issues: [], metrics: %{}, suggestions: %{}}}}
          end
        end)
      end)

    results = Task.await_many(tasks, 30_000)

    # Filter out errors
    successful =
      Enum.filter(results, fn {_, result} ->
        match?({:ok, _}, result)
      end)

    {:ok, Enum.map(successful, fn {engine, {:ok, result}} -> {engine, result} end)}
  end

  defp run_engines_sequential_source(engines, source, language, opts) do
    config = Keyword.get(opts, :config, %{})

    results =
      Enum.map(engines, fn engine ->
        if function_exported?(engine, :analyze_source, 3) do
          engine_config = Map.get(config, engine.name(), %{})

          case engine.analyze_source(source, language, config: engine_config) do
            {:ok, result} -> {engine, result}
            _ -> nil
          end
        else
          {engine, %{engine: engine.name(), issues: [], metrics: %{}, suggestions: %{}}}
        end
      end)
      |> Enum.filter(& &1)

    {:ok, results}
  end

  defp aggregate_results(engine_results, file_path) do
    # Collect all issues
    all_issues =
      engine_results
      |> Enum.flat_map(fn {_engine, result} ->
        # Add file path to issues
        Enum.map(result.issues, fn issue ->
          Map.update!(issue, :location, &Map.put(&1, :file, file_path))
        end)
      end)

    # Group by severity
    issues_by_severity =
      all_issues
      |> Enum.group_by(& &1.severity)
      |> Enum.map(fn {severity, issues} -> {severity, length(issues)} end)
      |> Map.new()

    # Group by engine
    issues_by_engine =
      engine_results
      |> Enum.map(fn {engine, result} ->
        {engine.name(), length(result.issues)}
      end)
      |> Map.new()

    # Merge metrics
    all_metrics =
      engine_results
      |> Enum.map(fn {engine, result} ->
        {engine.name(), result.metrics}
      end)
      |> Map.new()

    # Merge suggestions
    all_suggestions =
      engine_results
      |> Enum.reduce(%{}, fn {_engine, result}, acc ->
        Map.merge(acc, result.suggestions)
      end)

    %{
      file: file_path,
      total_issues: length(all_issues),
      issues_by_severity: issues_by_severity,
      issues_by_engine: issues_by_engine,
      all_issues: Engine.sort_issues(all_issues),
      metrics: all_metrics,
      suggestions: all_suggestions
    }
  end

  defp deserialize_ast_info(ast_cache) do
    # Convert the cached AST data back to our internal format
    %{
      type: String.to_atom(ast_cache["type"] || "script"),
      name: if(ast_cache["name"], do: String.to_atom(ast_cache["name"]), else: nil),
      functions: deserialize_functions(ast_cache["functions"] || []),
      aliases: Enum.map(ast_cache["aliases"] || [], &String.to_atom/1),
      imports: Enum.map(ast_cache["imports"] || [], &String.to_atom/1),
      requires: Enum.map(ast_cache["requires"] || [], &String.to_atom/1),
      calls: deserialize_calls(ast_cache["calls"] || []),
      metadata: %{}
    }
  end

  defp deserialize_functions(functions) do
    Enum.map(functions, fn func ->
      %{
        name: String.to_atom(func["name"]),
        arity: func["arity"],
        line: func["line"],
        private: func["private"]
      }
    end)
  end

  defp deserialize_calls(calls) do
    Enum.map(calls, fn call ->
      %{
        from: deserialize_mfa(call["from"]),
        to: deserialize_mfa(call["to"]),
        line: call["line"]
      }
    end)
  end

  defp deserialize_mfa(mfa) do
    {
      String.to_atom(mfa["module"]),
      String.to_atom(mfa["function"]),
      mfa["arity"]
    }
  end
end
