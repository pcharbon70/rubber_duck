defmodule RubberDuck.Tools.DependencyInspector do
  @moduledoc """
  Detects internal and external dependencies used in code.
  
  This tool analyzes Elixir code to identify module dependencies,
  external library usage, and dependency relationships.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :dependency_inspector
    description "Detects internal and external dependencies used in code"
    category :analysis
    version "1.0.0"
    tags [:analysis, :dependencies, :architecture, :maintenance]
    
    parameter :code do
      type :string
      required false
      description "The code to analyze for dependencies"
      default ""
      constraints [
        max_length: 50000
      ]
    end
    
    parameter :file_path do
      type :string
      required false
      description "Path to file or directory to analyze"
      default ""
    end
    
    parameter :analysis_type do
      type :string
      required false
      description "Type of dependency analysis to perform"
      default "comprehensive"
      constraints [
        enum: [
          "comprehensive",  # All dependency information
          "external",      # Only external deps (hex packages)
          "internal",      # Only internal project modules
          "circular",      # Check for circular dependencies
          "unused"         # Find potentially unused dependencies
        ]
      ]
    end
    
    parameter :include_stdlib do
      type :boolean
      required false
      description "Include Elixir/Erlang stdlib modules in analysis"
      default false
    end
    
    parameter :depth do
      type :integer
      required false
      description "How deep to analyze transitive dependencies"
      default 2
      constraints [
        min: 1,
        max: 5
      ]
    end
    
    parameter :group_by do
      type :string
      required false
      description "How to group the results"
      default "module"
      constraints [
        enum: ["module", "package", "layer", "none"]
      ]
    end
    
    parameter :check_mix_deps do
      type :boolean
      required false
      description "Cross-reference with mix.exs dependencies"
      default true
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 1
    end
    
    security do
      sandbox :restricted
      capabilities [:file_read]
      rate_limit 50
    end
  end
  
  @doc """
  Executes dependency analysis based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, code_to_analyze} <- get_code_to_analyze(params, context),
         {:ok, ast} <- parse_code(code_to_analyze),
         {:ok, raw_deps} <- extract_dependencies(ast, params),
         {:ok, categorized} <- categorize_dependencies(raw_deps, params, context),
         {:ok, analyzed} <- analyze_dependencies(categorized, params),
         {:ok, formatted} <- format_results(analyzed, params) do
      
      {:ok, formatted}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp get_code_to_analyze(params, context) do
    cond do
      params.code != "" ->
        {:ok, params.code}
      
      params.file_path != "" ->
        read_file_or_directory(params.file_path, context)
      
      true ->
        {:error, "Either 'code' or 'file_path' parameter must be provided"}
    end
  end
  
  defp read_file_or_directory(path, context) do
    full_path = if Path.type(path) == :absolute do
      path
    else
      Path.join(context[:project_root] || File.cwd!(), path)
    end
    
    cond do
      File.regular?(full_path) ->
        File.read(full_path)
      
      File.dir?(full_path) ->
        files = Path.wildcard(Path.join(full_path, "**/*.{ex,exs}"))
        contents = Enum.map(files, fn file ->
          case File.read(file) do
            {:ok, content} -> content
            _ -> ""
          end
        end)
        {:ok, Enum.join(contents, "\n\n")}
      
      true ->
        {:error, "Path does not exist: #{full_path}"}
    end
  end
  
  defp parse_code(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, _}} -> 
        {:error, "Parse error on line #{line}: #{error}"}
    end
  end
  
  defp extract_dependencies(ast, params) do
    {_, deps} = Macro.postwalk(ast, %{
      modules: MapSet.new(),
      functions: [],
      aliases: %{},
      imports: MapSet.new(),
      uses: MapSet.new(),
      requires: MapSet.new(),
      behaviours: MapSet.new()
    }, &extract_dependency_node/2)
    
    # Convert MapSets to lists for easier processing
    deps = %{
      modules: MapSet.to_list(deps.modules),
      functions: deps.functions,
      aliases: deps.aliases,
      imports: MapSet.to_list(deps.imports),
      uses: MapSet.to_list(deps.uses),
      requires: MapSet.to_list(deps.requires),
      behaviours: MapSet.to_list(deps.behaviours)
    }
    
    {:ok, deps}
  end
  
  defp extract_dependency_node(node, acc) do
    case node do
      # Alias tracking
      {:alias, _, [{:__aliases__, _, parts}]} ->
        module = Module.concat(parts)
        {node, put_in(acc.modules, MapSet.put(acc.modules, module))}
      
      {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, as_parts}]]} ->
        module = Module.concat(parts)
        as_module = Module.concat(as_parts)
        acc = put_in(acc.modules, MapSet.put(acc.modules, module))
        acc = put_in(acc.aliases[as_module], module)
        {node, acc}
      
      # Import tracking
      {:import, _, [{:__aliases__, _, parts} | _]} ->
        module = Module.concat(parts)
        {node, put_in(acc.imports, MapSet.put(acc.imports, module))}
      
      # Use tracking
      {:use, _, [{:__aliases__, _, parts} | _]} ->
        module = Module.concat(parts)
        {node, put_in(acc.uses, MapSet.put(acc.uses, module))}
      
      # Require tracking
      {:require, _, [{:__aliases__, _, parts} | _]} ->
        module = Module.concat(parts)
        {node, put_in(acc.requires, MapSet.put(acc.requires, module))}
      
      # Behaviour tracking
      {:@, _, [{:behaviour, _, [module]}]} when is_atom(module) ->
        {node, put_in(acc.behaviours, MapSet.put(acc.behaviours, module))}
      
      {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]} ->
        module = Module.concat(parts)
        {node, put_in(acc.behaviours, MapSet.put(acc.behaviours, module))}
      
      # Function calls with module
      {{:., _, [{:__aliases__, _, parts}, func_name]}, meta, args} when is_atom(func_name) ->
        module = Module.concat(parts)
        acc = put_in(acc.modules, MapSet.put(acc.modules, module))
        func_info = %{
          module: module,
          function: func_name,
          arity: length(args || []),
          line: meta[:line]
        }
        {node, update_in(acc.functions, &[func_info | &1])}
      
      # Kernel function calls that might reference modules
      {func_name, _, args} when func_name in [:apply, :spawn, :spawn_link] and is_list(args) ->
        case args do
          [{:__aliases__, _, parts} | _] ->
            module = Module.concat(parts)
            {node, put_in(acc.modules, MapSet.put(acc.modules, module))}
          _ ->
            {node, acc}
        end
      
      # Module attribute access
      {{:., _, [{:__aliases__, _, parts}, :__info__]}, _, _} ->
        module = Module.concat(parts)
        {node, put_in(acc.modules, MapSet.put(acc.modules, module))}
      
      # Struct creation
      {:%, _, [{:__aliases__, _, parts}, _]} ->
        module = Module.concat(parts)
        {node, put_in(acc.modules, MapSet.put(acc.modules, module))}
      
      _ ->
        {node, acc}
    end
  end
  
  defp categorize_dependencies(deps, params, context) do
    project_modules = if context[:project_modules] do
      context[:project_modules]
    else
      detect_project_modules(context)
    end
    
    mix_deps = if params.check_mix_deps do
      load_mix_dependencies(context)
    else
      %{}
    end
    
    categorized = %{
      external: %{
        hex: [],
        erlang: [],
        elixir: []
      },
      internal: [],
      unknown: []
    }
    
    all_modules = Enum.uniq(
      deps.modules ++ 
      deps.imports ++ 
      deps.uses ++ 
      deps.requires ++ 
      deps.behaviours
    )
    
    categorized = Enum.reduce(all_modules, categorized, fn module, acc ->
      module_str = to_string(module)
      
      cond do
        # Check if it's an internal project module
        Enum.any?(project_modules, &String.starts_with?(module_str, &1)) ->
          update_in(acc.internal, &[module | &1])
        
        # Check if it's a hex dependency
        Map.has_key?(mix_deps, module) ->
          update_in(acc.external.hex, &[{module, mix_deps[module]} | &1])
        
        # Check if it's Erlang stdlib
        String.starts_with?(module_str, ":erlang") or module in erlang_stdlib_modules() ->
          if params.include_stdlib do
            update_in(acc.external.erlang, &[module | &1])
          else
            acc
          end
        
        # Check if it's Elixir stdlib
        module in elixir_stdlib_modules() ->
          if params.include_stdlib do
            update_in(acc.external.elixir, &[module | &1])
          else
            acc
          end
        
        # Otherwise unknown
        true ->
          update_in(acc.unknown, &[module | &1])
      end
    end)
    
    # Add detailed usage information
    categorized = Map.put(categorized, :usage_details, %{
      aliases: deps.aliases,
      imports: deps.imports,
      uses: deps.uses,
      requires: deps.requires,
      behaviours: deps.behaviours,
      function_calls: group_function_calls(deps.functions)
    })
    
    {:ok, categorized}
  end
  
  defp detect_project_modules(context) do
    project_root = context[:project_root] || File.cwd!()
    app_name = context[:app_name] || get_app_name(project_root)
    
    base_modules = if app_name do
      [Macro.camelize(to_string(app_name))]
    else
      []
    end
    
    # Try to detect from lib directory
    lib_path = Path.join(project_root, "lib")
    if File.dir?(lib_path) do
      File.ls!(lib_path)
      |> Enum.filter(&File.dir?(Path.join(lib_path, &1)))
      |> Enum.map(&Macro.camelize/1)
      |> Enum.concat(base_modules)
      |> Enum.uniq()
    else
      base_modules
    end
  end
  
  defp get_app_name(project_root) do
    mix_file = Path.join(project_root, "mix.exs")
    if File.exists?(mix_file) do
      case File.read(mix_file) do
        {:ok, content} ->
          case Regex.run(~r/app:\s*:([a-z_]+)/, content) do
            [_, app_name] -> String.to_atom(app_name)
            _ -> nil
          end
        _ -> nil
      end
    else
      nil
    end
  end
  
  defp load_mix_dependencies(context) do
    project_root = context[:project_root] || File.cwd!()
    mix_file = Path.join(project_root, "mix.exs")
    
    if File.exists?(mix_file) do
      # In a real implementation, we would properly evaluate mix.exs
      # For now, we'll do simple pattern matching
      case File.read(mix_file) do
        {:ok, content} ->
          extract_mix_deps_from_content(content)
        _ ->
          %{}
      end
    else
      %{}
    end
  end
  
  defp extract_mix_deps_from_content(content) do
    # Simple regex-based extraction of dependencies
    # In reality, we'd want to properly evaluate the mix file
    Regex.scan(~r/{:([a-z_]+),/, content)
    |> Enum.map(fn [_, dep_name] -> 
      module_name = Macro.camelize(dep_name)
      {String.to_atom(module_name), dep_name}
    end)
    |> Enum.into(%{})
  end
  
  defp group_function_calls(functions) do
    functions
    |> Enum.group_by(& &1.module)
    |> Enum.map(fn {module, calls} ->
      {module, Enum.map(calls, &{&1.function, &1.arity})}
    end)
    |> Enum.into(%{})
  end
  
  defp analyze_dependencies(categorized, params) do
    analysis = %{
      categorized: categorized,
      statistics: calculate_statistics(categorized),
      warnings: []
    }
    
    analysis = case params.analysis_type do
      "circular" ->
        circular = detect_circular_dependencies(categorized)
        %{analysis | circular_dependencies: circular}
      
      "unused" ->
        unused = detect_potentially_unused(categorized)
        %{analysis | potentially_unused: unused}
      
      _ ->
        analysis
    end
    
    # Add warnings
    warnings = []
    warnings = if length(categorized.unknown) > 0 do
      ["Found #{length(categorized.unknown)} unknown module references" | warnings]
    else
      warnings
    end
    
    {:ok, %{analysis | warnings: warnings}}
  end
  
  defp calculate_statistics(categorized) do
    %{
      total_dependencies: 
        length(categorized.external.hex) +
        length(categorized.external.erlang) +
        length(categorized.external.elixir) +
        length(categorized.internal),
      external_count: 
        length(categorized.external.hex) +
        length(categorized.external.erlang) +
        length(categorized.external.elixir),
      internal_count: length(categorized.internal),
      hex_deps_count: length(categorized.external.hex),
      unknown_count: length(categorized.unknown),
      usage_breakdown: %{
        imports: length(categorized.usage_details.imports),
        uses: length(categorized.usage_details.uses),
        aliases: map_size(categorized.usage_details.aliases),
        behaviours: length(categorized.usage_details.behaviours)
      }
    }
  end
  
  defp detect_circular_dependencies(_categorized) do
    # Simplified - would need more sophisticated graph analysis
    []
  end
  
  defp detect_potentially_unused(_categorized) do
    # Would cross-reference with actual usage
    []
  end
  
  defp format_results(analysis, params) do
    formatted = case params.analysis_type do
      "external" ->
        %{
          external_dependencies: analysis.categorized.external,
          statistics: %{
            total_external: analysis.statistics.external_count,
            hex_packages: analysis.statistics.hex_deps_count
          }
        }
      
      "internal" ->
        %{
          internal_dependencies: analysis.categorized.internal,
          statistics: %{
            total_internal: analysis.statistics.internal_count
          }
        }
      
      "circular" ->
        %{
          circular_dependencies: Map.get(analysis, :circular_dependencies, []),
          has_circular: length(Map.get(analysis, :circular_dependencies, [])) > 0
        }
      
      "unused" ->
        %{
          potentially_unused: Map.get(analysis, :potentially_unused, []),
          recommendation: "Review these dependencies for potential removal"
        }
      
      _ -> # comprehensive
        %{
          summary: analysis.statistics,
          external: analysis.categorized.external,
          internal: analysis.categorized.internal,
          unknown: analysis.categorized.unknown,
          usage: analysis.categorized.usage_details,
          warnings: analysis.warnings
        }
    end
    
    # Group results if requested
    formatted = if params.group_by != "none" do
      Map.put(formatted, :grouped, group_results(analysis, params.group_by))
    else
      formatted
    end
    
    {:ok, formatted}
  end
  
  defp group_results(analysis, "package") do
    # Group by package/library
    analysis.categorized.external.hex
    |> Enum.group_by(fn {_module, package} -> package end)
    |> Enum.map(fn {package, modules} ->
      {package, Enum.map(modules, fn {mod, _} -> mod end)}
    end)
    |> Enum.into(%{})
  end
  
  defp group_results(analysis, "layer") do
    # Simple layer detection based on module naming
    all_modules = analysis.categorized.internal ++ 
                  Enum.map(analysis.categorized.external.hex, fn {mod, _} -> mod end)
    
    all_modules
    |> Enum.group_by(&detect_layer/1)
    |> Enum.into(%{})
  end
  
  defp group_results(analysis, _) do
    # Default module grouping
    %{
      external: analysis.categorized.external,
      internal: analysis.categorized.internal
    }
  end
  
  defp detect_layer(module) do
    module_str = to_string(module)
    cond do
      module_str =~ ~r/Web|Controller|View|Live/ -> :web
      module_str =~ ~r/Repo|Schema|Query/ -> :data
      module_str =~ ~r/Service|Business|Core/ -> :business
      module_str =~ ~r/Worker|Job|Task/ -> :background
      module_str =~ ~r/Test|Spec/ -> :test
      true -> :other
    end
  end
  
  defp elixir_stdlib_modules do
    [
      Agent, Application, Atom, Base, Behaviour, Bitwise, Calendar, Code,
      Date, DateTime, Dict, Enum, Exception, File, Float, Function,
      GenEvent, GenServer, HashDict, HashSet, IO, Integer, Kernel,
      Keyword, List, Logger, Macro, Map, MapSet, Module, NaiveDateTime,
      Node, Port, Process, Protocol, Range, Record, Regex, Registry,
      Set, Stream, String, StringIO, Supervisor, System, Task, Time,
      Tuple, URI, Version
    ]
  end
  
  defp erlang_stdlib_modules do
    [
      :array, :base64, :binary, :calendar, :crypto, :dict, :digraph,
      :digraph_utils, :ets, :file, :filelib, :filename, :gen_event,
      :gen_fsm, :gen_server, :gen_statem, :gen_tcp, :inet, :io,
      :lists, :maps, :math, :os, :proplists, :queue, :rand, :random,
      :re, :sets, :string, :timer, :unicode, :uri_string, :zip
    ]
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end