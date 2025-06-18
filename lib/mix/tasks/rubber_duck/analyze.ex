defmodule Mix.Tasks.RubberDuck.Analyze do
  @shortdoc "Analyze code files for complexity, security vulnerabilities, and code smells"
  @moduledoc """
  Analyze code files using the CodeAnalyser engine.

  ## Usage

      # Analyze a single file
      mix rubber_duck.analyze path/to/file.ex

      # Analyze multiple files
      mix rubber_duck.analyze file1.ex file2.js file3.py

      # Analyze with specific options
      mix rubber_duck.analyze --format json --output results.json file.ex

      # Analyze all files in a directory
      mix rubber_duck.analyze --recursive lib/

  ## Options

    * `--format` - Output format: `text` (default), `json`, `csv`
    * `--output` - Output file path (default: stdout)
    * `--recursive` - Recursively analyze directories
    * `--language` - Override language detection (elixir, javascript, python)
    * `--include-security` - Include security vulnerability analysis (default: true)
    * `--include-complexity` - Include complexity metrics (default: true)
    * `--include-smells` - Include code smell detection (default: true)
    * `--quiet` - Minimal output, only show issues

  ## Examples

      # Basic analysis
      mix rubber_duck.analyze lib/my_module.ex

      # JSON output for CI/CD integration
      mix rubber_duck.analyze --format json --output analysis.json lib/

      # Security-focused analysis
      mix rubber_duck.analyze --include-complexity false --include-smells false lib/
  """

  use Mix.Task

  alias RubberDuck.CodingAssistant.EngineRegistry

  @switches [
    format: :string,
    output: :string,
    recursive: :boolean,
    language: :string,
    include_security: :boolean,
    include_complexity: :boolean,
    include_smells: :boolean,
    quiet: :boolean,
    help: :boolean
  ]

  @aliases [
    f: :format,
    o: :output,
    r: :recursive,
    l: :language,
    q: :quiet,
    h: :help
  ]

  @impl Mix.Task
  def run(args) do
    {opts, files, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    if opts[:help] do
      Mix.shell().info(@moduledoc)
      System.halt(0)
    end

    # Start the application to ensure engines are running
    Application.ensure_all_started(:rubber_duck)

    # Wait for engine to be available
    case wait_for_engine() do
      {:ok, engine_info} ->
        # Process files
        case get_files_to_analyze(files, opts) do
          [] ->
            Mix.shell().error("No files specified for analysis")
            
          file_list ->
            results = analyze_files(file_list, engine_info, opts)
            output_results(results, opts)
        end
        
      {:error, reason} ->
        Mix.shell().error("CodeAnalyser engine not available: #{inspect(reason)}")
        Mix.shell().error("Make sure the application is running with: mix run --no-halt")
    end
  end

  defp wait_for_engine(attempts \\ 10) do
    case EngineRegistry.find_engines_by_capability([:syntax_analysis, :complexity_analysis]) do
      [] when attempts > 0 ->
        Mix.shell().info("Waiting for CodeAnalyser engine...")
        Process.sleep(1000)
        wait_for_engine(attempts - 1)
        
      [] ->
        {:error, :engine_not_found}
        
      [engine_info | _] ->
        {:ok, engine_info}
    end
  end

  defp get_files_to_analyze([], opts) do
    if opts[:recursive] do
      # Default to current directory if recursive and no files specified
      find_files_recursive(".", get_supported_extensions())
    else
      []
    end
  end
  defp get_files_to_analyze(files, opts) do
    Enum.flat_map(files, fn file_or_dir ->
      cond do
        File.regular?(file_or_dir) ->
          [file_or_dir]
          
        File.dir?(file_or_dir) and opts[:recursive] ->
          find_files_recursive(file_or_dir, get_supported_extensions())
          
        File.dir?(file_or_dir) ->
          Mix.shell().error("#{file_or_dir} is a directory. Use --recursive to analyze directories.")
          []
          
        true ->
          Mix.shell().error("File not found: #{file_or_dir}")
          []
      end
    end)
  end

  defp find_files_recursive(dir, extensions) do
    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.filter(fn path ->
      File.regular?(path) and Path.extname(path) in extensions
    end)
  end

  defp get_supported_extensions do
    [".ex", ".exs", ".js", ".jsx", ".ts", ".tsx", ".py"]
  end

  defp analyze_files(files, engine_info, opts) do
    unless opts[:quiet] do
      Mix.shell().info("Analyzing #{length(files)} files...")
    end

    Enum.map(files, fn file_path ->
      unless opts[:quiet] do
        Mix.shell().info("Analyzing: #{file_path}")
      end
      
      analyze_single_file(file_path, engine_info, opts)
    end)
  end

  defp analyze_single_file(file_path, engine_info, opts) do
    case File.read(file_path) do
      {:ok, content} ->
        language = detect_language(file_path, opts[:language])
        
        code_data = %{
          file_path: file_path,
          content: content,
          language: language
        }
        
        case GenServer.call(engine_info.pid, {:process_real_time, code_data}, 10_000) do
          {:ok, result} ->
            filter_result(result, opts, file_path)
            
          {:error, reason} ->
            %{
              file_path: file_path,
              status: :error,
              error: reason
            }
        end
        
      {:error, reason} ->
        %{
          file_path: file_path,
          status: :error,
          error: {:file_read_error, reason}
        }
    end
  end

  defp detect_language(file_path, override_language) do
    case override_language do
      nil ->
        case Path.extname(file_path) do
          ext when ext in [".ex", ".exs"] -> :elixir
          ext when ext in [".js", ".jsx", ".ts", ".tsx"] -> :javascript
          ".py" -> :python
          _ -> :elixir  # Default fallback
        end
        
      lang_string ->
        String.to_atom(lang_string)
    end
  end

  defp filter_result(result, opts, file_path) do
    data = result.data
    filtered_data = %{}
    
    filtered_data = if opts[:include_complexity] != false do
      Map.put(filtered_data, :complexity, data.complexity)
    else
      filtered_data
    end
    
    filtered_data = if opts[:include_security] != false do
      Map.put(filtered_data, :security, data.security)
    else
      filtered_data
    end
    
    filtered_data = if opts[:include_smells] != false do
      Map.put(filtered_data, :code_smells, data.code_smells)
    else
      filtered_data
    end

    %{
      file_path: file_path,
      status: result.status,
      data: filtered_data,
      processing_time: Map.get(result, :processing_time)
    }
  end

  defp output_results(results, opts) do
    case opts[:format] do
      "json" ->
        output_json(results, opts)
      "csv" ->
        output_csv(results, opts)
      _ ->
        output_text(results, opts)
    end
  end

  defp output_json(results, opts) do
    # Simple JSON-like output without Jason dependency
    json_output = inspect(results, pretty: true, limit: :infinity)
    
    case opts[:output] do
      nil ->
        Mix.shell().info(json_output)
      file_path ->
        File.write!(file_path, json_output)
        Mix.shell().info("Results written to #{file_path}")
    end
  end

  defp output_csv(results, opts) do
    headers = ["file_path", "status", "cyclomatic_complexity", "security_score", "smell_score", "processing_time"]
    
    # Simple CSV output without CSV library
    csv_lines = [
      Enum.join(headers, ",")
      | Enum.map(results, fn result ->
          [
            "\"#{result.file_path}\"",
            result.status,
            get_in(result, [:data, :complexity, :cyclomatic]) || "",
            get_in(result, [:data, :security, :security_score]) || "",
            get_in(result, [:data, :code_smells, :smell_score]) || "",
            result[:processing_time] || ""
          ]
          |> Enum.join(",")
        end)
    ]
    
    csv_content = Enum.join(csv_lines, "\n")
    
    case opts[:output] do
      nil ->
        Mix.shell().info(csv_content)
      file_path ->
        File.write!(file_path, csv_content)
        Mix.shell().info("Results written to #{file_path}")
    end
  end

  defp output_text(results, opts) do
    quiet = opts[:quiet]
    
    unless quiet do
      Mix.shell().info("\n=== Code Analysis Results ===")
    end

    Enum.each(results, fn result ->
      case result.status do
        :success ->
          output_file_analysis(result, quiet)
        :error ->
          Mix.shell().error("Error analyzing #{result.file_path}: #{inspect(result.error)}")
      end
    end)

    unless quiet do
      output_summary(results)
    end
    
    case opts[:output] do
      nil -> :ok
      _file_path ->
        # For text output to file, we'd need to capture the output
        Mix.shell().info("Text output to file not yet implemented. Use --format json for file output.")
    end
  end

  defp output_file_analysis(result, quiet) do
    unless quiet do
      Mix.shell().info("\n--- #{result.file_path} ---")
    end

    data = result.data

    # Complexity metrics
    if complexity = data[:complexity] do
      unless quiet do
        Mix.shell().info("Complexity Metrics:")
        Mix.shell().info("  Cyclomatic: #{complexity.cyclomatic}")
        Mix.shell().info("  Cognitive: #{complexity.cognitive}")
        Mix.shell().info("  Lines of Code: #{complexity.lines_of_code}")
        Mix.shell().info("  Maintainability Index: #{Float.round(complexity.maintainability_index, 2)}")
      end
    end

    # Security analysis
    if security = data[:security] do
      vulnerabilities = security.vulnerabilities || []
      
      if length(vulnerabilities) > 0 do
        Mix.shell().error("Security Issues Found:")
        Enum.each(vulnerabilities, fn vuln ->
          Mix.shell().error("  #{vuln.severity |> to_string() |> String.upcase()}: #{vuln.message}")
        end)
      else
        unless quiet do
          Mix.shell().info("Security: No vulnerabilities detected")
        end
      end
    end

    # Code smells
    if smells = data[:code_smells] do
      detected_smells = smells.detected || []
      
      if length(detected_smells) > 0 do
        Mix.shell().error("Code Smells Detected:")
        Enum.each(detected_smells, fn smell ->
          Mix.shell().error("  #{smell.severity |> to_string() |> String.upcase()}: #{smell.description}")
        end)
      else
        unless quiet do
          Mix.shell().info("Code Quality: No smells detected")
        end
      end
    end
  end

  defp output_summary(results) do
    total = length(results)
    successful = Enum.count(results, &(&1.status == :success))
    errors = total - successful
    
    Mix.shell().info("\n--- Summary ---")
    Mix.shell().info("Total files: #{total}")
    Mix.shell().info("Successfully analyzed: #{successful}")
    if errors > 0 do
      Mix.shell().error("Errors: #{errors}")
    end

    # Aggregate metrics for successful analyses
    if successful > 0 do
      successful_results = Enum.filter(results, &(&1.status == :success))
      
      # Count issues
      total_vulnerabilities = count_total_issues(successful_results, [:data, :security, :vulnerabilities])
      total_smells = count_total_issues(successful_results, [:data, :code_smells, :detected])
      
      if total_vulnerabilities > 0 do
        Mix.shell().error("Total security vulnerabilities: #{total_vulnerabilities}")
      end
      
      if total_smells > 0 do
        Mix.shell().error("Total code smells: #{total_smells}")
      end
      
      if total_vulnerabilities == 0 and total_smells == 0 do
        Mix.shell().info("✅ No security vulnerabilities or code smells detected")
      end
    end
  end

  defp count_total_issues(results, path) do
    results
    |> Enum.map(&get_in(&1, path))
    |> Enum.filter(& &1)
    |> Enum.map(&length/1)
    |> Enum.sum()
  end
end