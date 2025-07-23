defmodule RubberDuck.Planning.Repository.RepositoryAnalyzer do
  @moduledoc """
  Analyzes repository structure and file relationships using AST parsing.

  This module provides comprehensive analysis of Elixir projects to understand:
  - Module dependencies through imports, aliases, and usage
  - File relationships and dependency graphs
  - Architectural patterns (Phoenix contexts, OTP supervision trees)
  - Repository structure (Mix projects, umbrella applications)
  """

  alias RubberDuck.Planning.Repository.DependencyGraph

  require Logger

  @type analysis_result :: %{
          files: [file_info()],
          dependencies: DependencyGraph.t(),
          patterns: [architectural_pattern()],
          structure: repository_structure()
        }

  @type file_info :: %{
          path: String.t(),
          type: file_type(),
          modules: [module_info()],
          dependencies: [String.t()],
          test_files: [String.t()],
          complexity: complexity_level()
        }

  @type module_info :: %{
          name: String.t(),
          type: module_type(),
          exports: [atom()],
          imports: [String.t()],
          aliases: [String.t()],
          uses: [String.t()],
          behaviours: [String.t()]
        }

  @type file_type :: :lib | :test | :config | :mix | :other
  @type module_type :: :genserver | :supervisor | :phoenix_controller | :phoenix_context | :regular
  @type complexity_level :: :simple | :medium | :complex | :very_complex
  @type architectural_pattern :: %{
          type: :phoenix_context | :otp_application | :umbrella_project | :custom,
          name: String.t(),
          files: [String.t()],
          confidence: float()
        }

  @type repository_structure :: %{
          type: :mix_project | :umbrella_project | :plain_elixir,
          root_path: String.t(),
          mix_projects: [mix_project_info()],
          config_files: [String.t()],
          deps: [dependency_info()]
        }

  @type mix_project_info :: %{
          name: String.t(),
          path: String.t(),
          apps: [String.t()]
        }

  @type dependency_info :: %{
          name: String.t(),
          version: String.t() | nil,
          source: :hex | :git | :path
        }

  @doc """
  Analyzes the repository starting from the given root path.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, analysis_result()} | {:error, term()}
  def analyze(root_path, opts \\ []) do
    Logger.info("Starting repository analysis for path: #{root_path}")

    with {:ok, structure} <- analyze_repository_structure(root_path),
         {:ok, files} <- discover_files(root_path, opts),
         {:ok, file_analyses} <- analyze_files(files),
         {:ok, dependency_graph} <- build_dependency_graph(file_analyses),
         {:ok, patterns} <- detect_architectural_patterns(file_analyses, structure) do
      result = %{
        files: file_analyses,
        dependencies: dependency_graph,
        patterns: patterns,
        structure: structure
      }

      Logger.info("Repository analysis complete: #{length(file_analyses)} files analyzed")
      {:ok, result}
    else
      error ->
        Logger.error("Repository analysis failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Analyzes the impact of changing specific files.
  """
  @spec analyze_change_impact(analysis_result(), [String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  def analyze_change_impact(%{dependencies: graph}, changed_files) do
    Logger.debug("Analyzing impact of changes to: #{inspect(changed_files)}")

    affected_files = DependencyGraph.get_dependent_files(graph, changed_files)

    Logger.debug("Impact analysis found #{length(affected_files)} affected files")
    {:ok, affected_files}
  end

  @doc """
  Gets the compilation order for files based on dependencies.
  """
  @spec get_compilation_order(analysis_result()) :: {:ok, [String.t()]} | {:error, term()}
  def get_compilation_order(%{dependencies: graph}) do
    DependencyGraph.topological_sort(graph)
  end

  @doc """
  Finds test files associated with implementation files.
  """
  @spec find_associated_tests(analysis_result(), [String.t()]) :: [String.t()]
  def find_associated_tests(%{files: files}, implementation_files) when is_list(implementation_files) do
    test_associations = build_test_associations(files)

    implementation_files
    |> Enum.flat_map(fn file ->
      Map.get(test_associations, file, [])
    end)
    |> Enum.uniq()
  end

  # Handle case where affected_files is a map with :direct and :transitive keys
  def find_associated_tests(%{files: files}, %{direct: direct, transitive: transitive}) do
    find_associated_tests(%{files: files}, direct ++ transitive)
  end

  # Private functions

  defp analyze_repository_structure(root_path) do
    mix_file = Path.join(root_path, "mix.exs")

    cond do
      File.exists?(mix_file) ->
        analyze_mix_project(root_path, mix_file)

      File.dir?(Path.join(root_path, "apps")) ->
        analyze_umbrella_project(root_path)

      true ->
        {:ok,
         %{
           type: :plain_elixir,
           root_path: root_path,
           mix_projects: [],
           config_files: find_config_files(root_path),
           deps: []
         }}
    end
  end

  defp analyze_mix_project(root_path, mix_file) do
    case parse_mix_file(mix_file) do
      {:ok, mix_config} ->
        {:ok,
         %{
           type: :mix_project,
           root_path: root_path,
           mix_projects: [
             %{
               name: mix_config[:app] || "unknown",
               path: root_path,
               apps: []
             }
           ],
           config_files: find_config_files(root_path),
           deps: parse_dependencies(mix_config[:deps] || [])
         }}

      error ->
        error
    end
  end

  defp analyze_umbrella_project(root_path) do
    apps_path = Path.join(root_path, "apps")

    case File.ls(apps_path) do
      {:ok, app_dirs} ->
        apps =
          Enum.map(app_dirs, fn dir ->
            %{
              name: dir,
              path: Path.join(apps_path, dir),
              apps: []
            }
          end)

        {:ok,
         %{
           type: :umbrella_project,
           root_path: root_path,
           mix_projects: apps,
           config_files: find_config_files(root_path),
           deps: []
         }}

      error ->
        error
    end
  end

  defp discover_files(root_path, opts) do
    patterns = Keyword.get(opts, :patterns, ["**/*.ex", "**/*.exs"])
    exclude = Keyword.get(opts, :exclude, ["_build/**", "deps/**", ".git/**"])

    files =
      patterns
      |> Enum.flat_map(fn pattern ->
        Path.wildcard(Path.join(root_path, pattern))
      end)
      |> Enum.reject(fn file ->
        Enum.any?(exclude, &(Path.wildcard(Path.join(root_path, &1)) |> Enum.member?(file)))
      end)
      |> Enum.uniq()

    {:ok, files}
  end

  defp analyze_files(files) do
    analyses = Enum.map(files, &analyze_file/1)

    case Enum.find(analyses, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(analyses, &elem(&1, 1))}
      error -> error
    end
  end

  defp analyze_file(file_path) do
    try do
      case File.read(file_path) do
        {:ok, content} ->
          case Sourceror.parse_string(content) do
            {:ok, ast} ->
              {:ok, extract_file_info(file_path, ast, content)}

            {:error, _errors} ->
              # Handle parse errors gracefully
              {:ok,
               %{
                 path: file_path,
                 type: determine_file_type(file_path),
                 modules: [],
                 dependencies: [],
                 test_files: [],
                 complexity: :simple
               }}
          end

        {:error, reason} ->
          {:error, {:file_read_error, file_path, reason}}
      end
    rescue
      error ->
        Logger.warning("Failed to analyze file #{file_path}: #{inspect(error)}")

        {:ok,
         %{
           path: file_path,
           type: determine_file_type(file_path),
           modules: [],
           dependencies: [],
           test_files: [],
           complexity: :simple
         }}
    end
  end

  defp extract_file_info(file_path, ast, content) do
    modules = extract_modules(ast)

    %{
      path: file_path,
      type: determine_file_type(file_path),
      modules: modules,
      dependencies: extract_dependencies(modules),
      # Will be populated later
      test_files: [],
      complexity: calculate_complexity(content, modules)
    }
  end

  defp extract_modules(ast) do
    {_ast, modules} =
      Sourceror.postwalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, module_parts}, [do: body]]} = node, acc ->
          module_name = module_parts |> Enum.map(&to_string/1) |> Enum.join(".")
          module_info = extract_module_info(module_name, body)
          {node, [module_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp extract_module_info(name, body) do
    %{
      name: name,
      type: determine_module_type(name, body),
      exports: extract_exports(body),
      imports: extract_imports(body),
      aliases: extract_aliases(body),
      uses: extract_uses(body),
      behaviours: extract_behaviours(body)
    }
  end

  defp determine_module_type(name, body) do
    cond do
      contains_behaviour?(body, "GenServer") -> :genserver
      contains_behaviour?(body, "Supervisor") -> :supervisor
      String.ends_with?(name, "Controller") -> :phoenix_controller
      contains_phoenix_context_patterns?(body) -> :phoenix_context
      true -> :regular
    end
  end

  defp contains_behaviour?(body, behaviour) do
    {_ast, found} =
      Sourceror.postwalk(body, false, fn
        {:use, _, [{:__aliases__, _, parts}]}, _acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          contains_behaviour = String.contains?(module_name, behaviour)
          {nil, contains_behaviour}

        {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]}, _acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          contains_behaviour = String.contains?(module_name, behaviour)
          {nil, contains_behaviour}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp contains_phoenix_context_patterns?(body) do
    # Look for common Phoenix context patterns
    {_ast, found} =
      Sourceror.postwalk(body, false, fn
        {:import, _, [{:__aliases__, _, parts}]}, _acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          is_ecto = String.contains?(module_name, "Ecto")
          {nil, is_ecto}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp extract_exports(body) do
    # Extract function definitions
    {_ast, exports} =
      Sourceror.postwalk(body, [], fn
        {:def, _meta, [{name, _, _args} | _]} = node, acc when is_atom(name) ->
          {node, [name | acc]}

        {:defp, _meta, [{name, _, _args} | _]} = node, acc when is_atom(name) ->
          # Don't include private functions in exports
          {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(exports)
  end

  defp extract_imports(body) do
    extract_module_references(body, :import)
  end

  defp extract_aliases(body) do
    extract_module_references(body, :alias)
  end

  defp extract_uses(body) do
    extract_module_references(body, :use)
  end

  defp extract_behaviours(body) do
    {_ast, behaviours} =
      Sourceror.postwalk(body, [], fn
        {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]} = node, acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(behaviours)
  end

  defp extract_module_references(body, directive) do
    {_ast, modules} =
      Sourceror.postwalk(body, [], fn
        {^directive, _, [{:__aliases__, _, parts}]} = node, acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        {^directive, _, [{:__aliases__, _, parts}, _opts]} = node, acc when is_list(parts) ->
          module_name = parts |> Enum.map(&to_string/1) |> Enum.join(".")
          {node, [module_name | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(modules)
  end

  defp extract_dependencies(modules) do
    modules
    |> Enum.flat_map(fn module ->
      module.imports ++ module.aliases ++ module.uses ++ module.behaviours
    end)
    |> Enum.uniq()
  end

  defp determine_file_type(file_path) do
    cond do
      String.contains?(file_path, "/test/") -> :test
      String.contains?(file_path, "/config/") -> :config
      String.ends_with?(file_path, "mix.exs") -> :mix
      String.ends_with?(file_path, ".ex") or String.ends_with?(file_path, ".exs") -> :lib
      true -> :other
    end
  end

  defp calculate_complexity(content, modules) do
    line_count = String.split(content, "\n") |> length()
    module_count = length(modules)
    function_count = Enum.sum(Enum.map(modules, &length(&1.exports)))

    complexity_score = line_count * 0.1 + module_count * 10 + function_count * 2

    cond do
      complexity_score < 50 -> :simple
      complexity_score < 150 -> :medium
      complexity_score < 300 -> :complex
      true -> :very_complex
    end
  end

  defp build_dependency_graph(file_analyses) do
    DependencyGraph.build(file_analyses)
  end

  defp detect_architectural_patterns(file_analyses, structure) do
    patterns = []

    # Detect Phoenix contexts
    patterns = patterns ++ detect_phoenix_contexts(file_analyses)

    # Detect OTP applications
    patterns = patterns ++ detect_otp_applications(file_analyses, structure)

    # Detect umbrella project patterns
    patterns = patterns ++ detect_umbrella_patterns(structure)

    {:ok, patterns}
  end

  defp detect_phoenix_contexts(file_analyses) do
    context_files =
      Enum.filter(file_analyses, fn file ->
        Enum.any?(file.modules, &(&1.type == :phoenix_context))
      end)

    context_files
    |> Enum.group_by(fn file ->
      # Group by directory structure to identify contexts
      file.path |> Path.dirname() |> Path.basename()
    end)
    |> Enum.map(fn {context_name, files} ->
      %{
        type: :phoenix_context,
        name: context_name,
        files: Enum.map(files, & &1.path),
        confidence: calculate_pattern_confidence(:phoenix_context, files)
      }
    end)
  end

  defp detect_otp_applications(file_analyses, _structure) do
    # Look for supervision tree patterns
    supervisor_files =
      Enum.filter(file_analyses, fn file ->
        Enum.any?(file.modules, &(&1.type == :supervisor))
      end)

    case supervisor_files do
      [] ->
        []

      files ->
        [
          %{
            type: :otp_application,
            name: "Application Supervision Tree",
            files: Enum.map(files, & &1.path),
            confidence: calculate_pattern_confidence(:otp_application, files)
          }
        ]
    end
  end

  defp detect_umbrella_patterns(%{type: :umbrella_project, mix_projects: projects}) do
    [
      %{
        type: :umbrella_project,
        name: "Umbrella Project Structure",
        files: Enum.map(projects, & &1.path),
        confidence: 1.0
      }
    ]
  end

  defp detect_umbrella_patterns(_), do: []

  defp calculate_pattern_confidence(pattern_type, files) do
    base_confidence =
      case pattern_type do
        :phoenix_context -> 0.7
        :otp_application -> 0.8
        :umbrella_project -> 1.0
      end

    # Adjust based on file count and consistency
    file_count_bonus = min(length(files) * 0.05, 0.2)
    base_confidence + file_count_bonus
  end

  defp build_test_associations(files) do
    test_files = Enum.filter(files, &(&1.type == :test))
    implementation_files = Enum.filter(files, &(&1.type == :lib))

    implementation_files
    |> Enum.reduce(%{}, fn impl_file, acc ->
      associated_tests = find_tests_for_file(impl_file.path, test_files)
      Map.put(acc, impl_file.path, associated_tests)
    end)
  end

  defp find_tests_for_file(impl_path, test_files) do
    impl_basename = impl_path |> Path.basename(".ex")

    test_files
    |> Enum.filter(fn test_file ->
      test_basename = test_file.path |> Path.basename("_test.exs")
      String.contains?(test_basename, impl_basename)
    end)
    |> Enum.map(& &1.path)
  end

  defp find_config_files(root_path) do
    config_path = Path.join(root_path, "config")

    if File.dir?(config_path) do
      Path.wildcard(Path.join(config_path, "*.exs"))
    else
      []
    end
  end

  defp parse_mix_file(mix_file) do
    try do
      result = Code.eval_file(mix_file)

      case result do
        {mix_config, _} when is_list(mix_config) ->
          {:ok, mix_config}

        {module, _} ->
          # Call the project/0 function on the module
          try do
            mix_config = module.project()
            {:ok, mix_config}
          rescue
            _ -> {:ok, []}
          end

        _ ->
          {:ok, []}
      end
    rescue
      error ->
        {:error, {:mix_parse_error, error}}
    end
  end

  defp parse_dependencies(deps) when is_list(deps) do
    Enum.map(deps, &parse_dependency/1)
  end

  defp parse_dependencies(_), do: []

  defp parse_dependency({name, version}) when is_atom(name) and is_binary(version) do
    %{name: to_string(name), version: version, source: :hex}
  end

  defp parse_dependency({name, opts}) when is_atom(name) and is_list(opts) do
    source =
      cond do
        Keyword.has_key?(opts, :git) -> :git
        Keyword.has_key?(opts, :path) -> :path
        true -> :hex
      end

    %{name: to_string(name), version: opts[:tag] || opts[:branch], source: source}
  end

  defp parse_dependency(name) when is_atom(name) do
    %{name: to_string(name), version: nil, source: :hex}
  end

  defp parse_dependency(_), do: nil
end
