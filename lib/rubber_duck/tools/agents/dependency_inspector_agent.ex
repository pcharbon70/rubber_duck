defmodule RubberDuck.Tools.Agents.DependencyInspectorAgent do
  @moduledoc """
  Agent that orchestrates the DependencyInspector tool for intelligent dependency analysis workflows.
  
  This agent manages dependency analysis requests, tracks dependency changes over time,
  detects potential issues, and provides recommendations for dependency management.
  
  ## Signals
  
  ### Input Signals
  - `analyze_dependencies` - Analyze dependencies in code or files
  - `check_circular_dependencies` - Check for circular dependency issues
  - `find_unused_dependencies` - Find potentially unused dependencies
  - `analyze_dependency_tree` - Analyze full dependency tree
  - `monitor_dependency_health` - Monitor dependency health and security
  - `compare_dependencies` - Compare dependencies between versions or branches
  
  ### Output Signals
  - `dependencies_analyzed` - Dependency analysis completed
  - `circular_dependencies_found` - Circular dependencies detected
  - `unused_dependencies_found` - Unused dependencies identified
  - `dependency_health_report` - Dependency health analysis ready
  - `dependency_changes_detected` - Dependency changes identified
  - `dependency_analysis_error` - Error during dependency analysis
  """
  
  use Jido.Agent,
    name: "dependency_inspector_agent",
    description: "Manages intelligent dependency analysis and monitoring workflows",
    category: "analysis",
    tags: ["dependencies", "architecture", "maintenance", "security", "quality"],
    schema: [
      # Analysis history
      analysis_history: [type: {:list, :map}, default: []],
      max_history_size: [type: :integer, default: 50],
      
      # Dependency tracking
      known_dependencies: [type: :map, default: %{
        external: %{hex: [], erlang: [], elixir: []},
        internal: [],
        last_updated: nil
      }],
      
      # Dependency health metrics
      health_metrics: [type: :map, default: %{
        total_dependencies: 0,
        outdated_count: 0,
        security_issues: 0,
        unused_count: 0,
        circular_count: 0,
        health_score: 100.0
      }],
      
      # Monitoring settings
      monitoring_config: [type: :map, default: %{
        check_outdated: true,
        check_security: true,
        check_licenses: true,
        allowed_licenses: ["MIT", "Apache-2.0", "BSD", "ISC"],
        max_dependency_depth: 3
      }],
      
      # Analysis cache
      analysis_cache: [type: :map, default: %{}],
      cache_ttl: [type: :integer, default: 3600_000], # 1 hour
      
      # Dependency rules and policies
      dependency_policies: [type: :map, default: %{
        "banned_packages" => [],
        "required_packages" => [],
        "version_constraints" => %{},
        "layer_rules" => %{
          "web" => ["phoenix", "phoenix_html", "phoenix_live_view"],
          "data" => ["ecto", "postgrex"],
          "test" => ["ex_unit", "mox", "faker"]
        }
      }],
      
      # Statistics
      analysis_stats: [type: :map, default: %{
        total_analyses: 0,
        issues_found: 0,
        recommendations_made: 0,
        average_dependency_count: 0.0
      }],
      
      # Dependency graph
      dependency_graph: [type: :map, default: %{
        nodes: %{},
        edges: [],
        cycles: [],
        last_built: nil
      }],
      
      # Active analyses
      active_analyses: [type: :map, default: %{}]
    ]
  
  require Logger
  
  # Define additional actions for this agent
  def additional_actions do
    [
      __MODULE__.ExecuteToolAction,
      __MODULE__.AnalyzeDependencyTreeAction,
      __MODULE__.CheckCircularDependenciesAction,
      __MODULE__.FindUnusedDependenciesAction,
      __MODULE__.MonitorDependencyHealthAction,
      __MODULE__.CompareDependenciesAction
    ]
  end
  
  # Action modules
  
  defmodule ExecuteToolAction do
    @moduledoc false
    use Jido.Action,
      name: "execute_tool",
      description: "Execute the DependencyInspector tool with specified parameters",
      schema: [
        params: [type: :map, required: true, doc: "Parameters for the DependencyInspector tool"]
      ]
    
    @impl true
    def run(action_params, context) do
      _agent = context.agent
      params = action_params.params
      
      # Execute the DependencyInspector tool
      case RubberDuck.Tools.DependencyInspector.execute(params, %{}) do
        {:ok, result} -> 
          {:ok, result}
        {:error, reason} -> 
          {:error, reason}
      end
    end
  end
  
  defmodule AnalyzeDependencyTreeAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_dependency_tree",
      description: "Analyze the complete dependency tree with transitive dependencies",
      schema: [
        root_path: [type: :string, required: true, doc: "Root path to analyze"],
        max_depth: [type: :integer, default: 3],
        include_dev: [type: :boolean, default: false],
        include_test: [type: :boolean, default: false],
        visualization_format: [type: :atom, values: [:graph, :tree, :matrix], default: :tree]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # First, get direct dependencies
      direct_deps_params = %{
        file_path: params.root_path,
        analysis_type: "comprehensive",
        include_stdlib: false,
        depth: 1
      }
      
      case RubberDuck.Tools.DependencyInspector.execute(direct_deps_params, %{}) do
        {:ok, direct_result} ->
          # Build dependency tree
          tree = build_dependency_tree(direct_result, params, agent)
          
          # Analyze the tree
          analysis = analyze_tree_structure(tree, params)
          
          {:ok, %{
            root_path: params.root_path,
            tree_depth: params.max_depth,
            total_nodes: analysis.node_count,
            total_edges: analysis.edge_count,
            tree_structure: tree,
            analysis: analysis,
            visualization: generate_visualization(tree, params.visualization_format)
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp build_dependency_tree(direct_result, params, _agent) do
      # Build tree structure from direct dependencies
      root_node = %{
        name: "root",
        type: :project,
        dependencies: build_dependency_nodes(direct_result, params.max_depth - 1)
      }
      
      %{
        root: root_node,
        depth: calculate_actual_depth(root_node),
        total_dependencies: count_all_dependencies(root_node)
      }
    end
    
    defp build_dependency_nodes(result, remaining_depth) do
      if remaining_depth <= 0 do
        []
      else
        # Combine all dependency types
        all_deps = (result.external.hex || []) ++
                   Enum.map(result.external.erlang || [], &{&1, :erlang}) ++
                   Enum.map(result.external.elixir || [], &{&1, :elixir}) ++
                   Enum.map(result.internal || [], &{&1, :internal})
        
        Enum.map(all_deps, fn dep ->
          {name, type} = case dep do
            {mod, package} when is_atom(package) -> {to_string(mod), package}
            {mod, _package} -> {to_string(mod), :hex}
            mod -> {to_string(mod), :unknown}
          end
          
          %{
            name: name,
            type: type,
            version: "unknown", # Would fetch from mix.lock or similar
            dependencies: [] # Would recursively fetch subdependencies
          }
        end)
      end
    end
    
    defp calculate_actual_depth(node, current_depth \\ 0) do
      if node.dependencies == [] do
        current_depth
      else
        node.dependencies
        |> Enum.map(&calculate_actual_depth(&1, current_depth + 1))
        |> Enum.max()
      end
    end
    
    defp count_all_dependencies(node) do
      direct_count = length(node.dependencies)
      nested_count = node.dependencies
      |> Enum.map(&count_all_dependencies/1)
      |> Enum.sum()
      
      direct_count + nested_count
    end
    
    defp analyze_tree_structure(tree, _params) do
      %{
        node_count: count_all_dependencies(tree.root) + 1,
        edge_count: count_all_dependencies(tree.root),
        max_depth: tree.depth,
        breadth_at_levels: calculate_breadth_at_levels(tree.root),
        dependency_types: categorize_dependency_types(tree.root),
        potential_issues: detect_tree_issues(tree)
      }
    end
    
    defp calculate_breadth_at_levels(node, level \\ 0, acc \\ %{}) do
      acc = Map.update(acc, level, 1, &(&1 + 1))
      
      node.dependencies
      |> Enum.reduce(acc, fn dep, acc ->
        calculate_breadth_at_levels(dep, level + 1, acc)
      end)
    end
    
    defp categorize_dependency_types(node, acc \\ %{}) do
      acc = if node.type != :project do
        Map.update(acc, node.type, 1, &(&1 + 1))
      else
        acc
      end
      
      node.dependencies
      |> Enum.reduce(acc, fn dep, acc ->
        categorize_dependency_types(dep, acc)
      end)
    end
    
    defp detect_tree_issues(tree) do
      issues = []
      
      # Check for deep dependency chains
      issues = if tree.depth > 5 do
        ["Deep dependency chain detected (depth: #{tree.depth})" | issues]
      else
        issues
      end
      
      # Check for large dependency count
      issues = if tree.total_dependencies > 100 do
        ["Large number of dependencies (#{tree.total_dependencies})" | issues]
      else
        issues
      end
      
      issues
    end
    
    defp generate_visualization(tree, :tree) do
      # Simple tree representation
      %{
        format: :tree,
        content: format_tree_node(tree.root, 0)
      }
    end
    
    defp generate_visualization(tree, :graph) do
      # Graph representation for visualization tools
      %{
        format: :graph,
        nodes: collect_all_nodes(tree.root),
        edges: collect_all_edges(tree.root)
      }
    end
    
    defp generate_visualization(tree, :matrix) do
      # Dependency matrix representation
      nodes = collect_all_nodes(tree.root)
      %{
        format: :matrix,
        nodes: nodes,
        matrix: build_adjacency_matrix(nodes, tree.root)
      }
    end
    
    defp format_tree_node(node, indent) do
      prefix = String.duplicate("  ", indent)
      lines = ["#{prefix}#{node.name} (#{node.type})"]
      
      child_lines = node.dependencies
      |> Enum.map(&format_tree_node(&1, indent + 1))
      |> List.flatten()
      
      lines ++ child_lines
    end
    
    defp collect_all_nodes(node, acc \\ []) do
      acc = [%{id: node.name, type: node.type} | acc]
      
      node.dependencies
      |> Enum.reduce(acc, fn dep, acc ->
        collect_all_nodes(dep, acc)
      end)
      |> Enum.uniq_by(& &1.id)
    end
    
    defp collect_all_edges(node, parent \\ nil, acc \\ []) do
      acc = if parent do
        [%{from: parent.name, to: node.name} | acc]
      else
        acc
      end
      
      node.dependencies
      |> Enum.reduce(acc, fn dep, acc ->
        collect_all_edges(dep, node, acc)
      end)
    end
    
    defp build_adjacency_matrix(nodes, root) do
      # Simplified adjacency matrix
      node_names = Enum.map(nodes, & &1.id)
      edges = collect_all_edges(root)
      
      Enum.map(node_names, fn from ->
        Enum.map(node_names, fn to ->
          if Enum.any?(edges, &(&1.from == from and &1.to == to)) do
            1
          else
            0
          end
        end)
      end)
    end
  end
  
  defmodule CheckCircularDependenciesAction do
    @moduledoc false
    use Jido.Action,
      name: "check_circular_dependencies",
      description: "Check for circular dependencies in the codebase",
      schema: [
        paths: [type: {:list, :string}, required: true, doc: "Paths to analyze"],
        include_transitive: [type: :boolean, default: true],
        max_cycle_length: [type: :integer, default: 10]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Analyze each path for dependencies
      all_dependencies = Enum.map(params.paths, fn path ->
        dep_params = %{
          file_path: path,
          analysis_type: "circular",
          include_stdlib: false
        }
        
        case RubberDuck.Tools.DependencyInspector.execute(dep_params, %{}) do
          {:ok, result} -> extract_dependency_pairs(result, path)
          {:error, _} -> []
        end
      end)
      |> List.flatten()
      
      # Build dependency graph
      graph = build_dependency_graph(all_dependencies)
      
      # Detect cycles
      cycles = detect_cycles(graph, params.max_cycle_length)
      
      {:ok, %{
        paths_analyzed: params.paths,
        total_modules: map_size(graph.nodes),
        total_dependencies: length(graph.edges),
        circular_dependencies_found: length(cycles) > 0,
        cycles: cycles,
        cycle_analysis: analyze_cycles(cycles),
        recommendations: generate_cycle_recommendations(cycles)
      }}
    end
    
    defp extract_dependency_pairs(result, source_path) do
      source_module = Path.rootname(Path.basename(source_path))
      |> Macro.camelize()
      
      # Extract all dependencies as pairs
      all_deps = (result.internal || []) ++
                 Enum.map(result.external.hex || [], fn {mod, _} -> mod end)
      
      Enum.map(all_deps, fn dep ->
        {source_module, to_string(dep)}
      end)
    end
    
    defp build_dependency_graph(dependency_pairs) do
      nodes = dependency_pairs
      |> Enum.flat_map(fn {from, to} -> [from, to] end)
      |> Enum.uniq()
      |> Enum.map(fn node -> {node, %{id: node}} end)
      |> Enum.into(%{})
      
      edges = dependency_pairs
      
      %{
        nodes: nodes,
        edges: edges,
        adjacency_list: build_adjacency_list(dependency_pairs)
      }
    end
    
    defp build_adjacency_list(pairs) do
      Enum.reduce(pairs, %{}, fn {from, to}, acc ->
        Map.update(acc, from, [to], &[to | &1])
      end)
    end
    
    defp detect_cycles(graph, max_length) do
      graph.nodes
      |> Map.keys()
      |> Enum.flat_map(fn node ->
        find_cycles_from_node(node, graph.adjacency_list, max_length)
      end)
      |> Enum.uniq()
    end
    
    defp find_cycles_from_node(start, adjacency_list, max_length) do
      find_cycles_dfs(start, start, adjacency_list, [], max_length)
    end
    
    defp find_cycles_dfs(current, target, adjacency_list, path, max_length) do
      if length(path) > max_length do
        []
      else
        if current == target and path != [] do
          # Found a cycle
          [[current | Enum.reverse(path)]]
        else
          neighbors = Map.get(adjacency_list, current, [])
          
          Enum.flat_map(neighbors, fn neighbor ->
            if neighbor in path do
              [] # Already visited in this path
            else
              find_cycles_dfs(neighbor, target, adjacency_list, [current | path], max_length)
            end
          end)
        end
      end
    end
    
    defp analyze_cycles(cycles) do
      if cycles == [] do
        %{}
      else
        %{
          total_cycles: length(cycles),
          shortest_cycle: cycles |> Enum.map(&length/1) |> Enum.min(),
          longest_cycle: cycles |> Enum.map(&length/1) |> Enum.max(),
          average_cycle_length: Enum.sum(Enum.map(cycles, &length/1)) / length(cycles),
          modules_involved: cycles |> List.flatten() |> Enum.uniq() |> length(),
          cycle_categories: categorize_cycles(cycles)
        }
      end
    end
    
    defp categorize_cycles(cycles) do
      cycles
      |> Enum.group_by(fn cycle ->
        cond do
          length(cycle) == 2 -> :direct_mutual
          length(cycle) <= 4 -> :small_cycle
          length(cycle) <= 8 -> :medium_cycle
          true -> :large_cycle
        end
      end)
      |> Enum.map(fn {category, cycles} -> {category, length(cycles)} end)
      |> Enum.into(%{})
    end
    
    defp generate_cycle_recommendations(cycles) do
      if cycles == [] do
        []
      else
      
      base_recommendations = [
        %{
          type: "refactoring",
          priority: :high,
          message: "Circular dependencies detected. Consider refactoring to break cycles.",
          action: "Extract common functionality to a separate module"
        }
      ]
      
      # Add specific recommendations based on cycle patterns
      if Enum.any?(cycles, &(length(&1) == 2)) do
        base_recommendations ++ [
          %{
            type: "architecture",
            priority: :high,
            message: "Direct mutual dependencies found between modules",
            action: "Consider introducing an interface or protocol"
          }
        ]
      else
        base_recommendations
      end
      end
    end
  end
  
  defmodule FindUnusedDependenciesAction do
    @moduledoc false
    use Jido.Action,
      name: "find_unused_dependencies",
      description: "Find potentially unused dependencies in the project",
      schema: [
        project_path: [type: :string, required: true],
        check_dev_deps: [type: :boolean, default: false],
        check_test_deps: [type: :boolean, default: false],
        confidence_threshold: [type: :float, default: 0.8]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Get declared dependencies from mix.exs
      declared_deps = get_declared_dependencies(params.project_path, params)
      
      # Analyze actual usage in code
      usage_params = %{
        file_path: Path.join(params.project_path, "lib"),
        analysis_type: "external",
        check_mix_deps: true
      }
      
      case RubberDuck.Tools.DependencyInspector.execute(usage_params, %{}) do
        {:ok, usage_result} ->
          # Find unused dependencies
          unused = find_unused(declared_deps, usage_result, params)
          
          {:ok, %{
            project_path: params.project_path,
            total_declared: length(declared_deps),
            total_used: count_used_deps(usage_result),
            potentially_unused: unused,
            unused_count: length(unused),
            recommendations: generate_unused_recommendations(unused),
            confidence_scores: calculate_confidence_scores(unused, usage_result)
          }}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp get_declared_dependencies(project_path, params) do
      mix_file = Path.join(project_path, "mix.exs")
      
      if File.exists?(mix_file) do
        # Parse mix.exs to get dependencies
        # Simplified - would properly evaluate mix.exs
        {:ok, content} = File.read(mix_file)
        
        deps = Regex.scan(~r/{:([a-z_]+),\s*"[^"]+"/m, content)
        |> Enum.map(fn [_, dep_name] -> String.to_atom(dep_name) end)
        
        # Filter based on params
        if params.check_dev_deps and params.check_test_deps do
          deps
        else
          # Would need to properly distinguish between prod/dev/test deps
          deps
        end
      else
        []
      end
    end
    
    defp count_used_deps(usage_result) do
      length(usage_result.external.hex || [])
    end
    
    defp find_unused(declared_deps, usage_result, _params) do
      used_packages = usage_result.external.hex
      |> Enum.map(fn {_module, package} -> 
        if is_atom(package), do: package, else: String.to_atom(package)
      end)
      |> Enum.uniq()
      
      declared_deps -- used_packages
    end
    
    defp generate_unused_recommendations(unused) do
      if unused == [] do
        []
      else
      
      [
        %{
          type: :cleanup,
          priority: :medium,
          message: "Found #{length(unused)} potentially unused dependencies",
          action: "Review and remove unused dependencies from mix.exs",
          specific_deps: unused
        }
      ]
      end
    end
    
    defp calculate_confidence_scores(unused, _usage_result) do
      # Calculate confidence that deps are truly unused
      Enum.map(unused, fn dep ->
        # Simple heuristic - would be more sophisticated
        confidence = cond do
          dep in [:jason, :poison] -> 0.5 # Common JSON libs might be used indirectly
          dep in [:logger, :telemetry] -> 0.3 # Often used implicitly
          true -> 0.9
        end
        
        {dep, confidence}
      end)
      |> Enum.into(%{})
    end
  end
  
  defmodule MonitorDependencyHealthAction do
    @moduledoc false
    use Jido.Action,
      name: "monitor_dependency_health",
      description: "Monitor overall dependency health including outdated, security, and licensing issues",
      schema: [
        project_path: [type: :string, required: true],
        check_outdated: [type: :boolean, default: true],
        check_security: [type: :boolean, default: true],
        check_licenses: [type: :boolean, default: true],
        security_source: [type: :atom, values: [:built_in, :external_api], default: :built_in]
      ]
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Get current dependencies
      dep_params = %{
        file_path: params.project_path,
        analysis_type: "comprehensive",
        check_mix_deps: true
      }
      
      case RubberDuck.Tools.DependencyInspector.execute(dep_params, %{}) do
        {:ok, deps_result} ->
          health_report = %{
            outdated: if(params.check_outdated, do: check_outdated_deps(deps_result, params), else: %{}),
            security: if(params.check_security, do: check_security_issues(deps_result, params), else: %{}),
            licenses: if(params.check_licenses, do: check_license_compliance(deps_result, agent), else: %{}),
            overall_health: %{}
          }
          
          # Calculate overall health score
          health_score = calculate_health_score(health_report)
          health_report = put_in(health_report.overall_health, %{
            score: health_score,
            rating: rate_health_score(health_score),
            summary: generate_health_summary(health_report)
          })
          
          {:ok, health_report}
        
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp check_outdated_deps(deps_result, _params) do
      # Simulate outdated dependency checking
      # In reality, would check against hex.pm or similar
      hex_deps = deps_result.external.hex || []
      
      outdated = Enum.take_random(hex_deps, div(length(hex_deps), 3))
      |> Enum.map(fn {_module, package} ->
        %{
          package: package,
          current_version: "1.0.0",
          latest_version: "1.2.0",
          severity: Enum.random([:patch, :minor, :major])
        }
      end)
      
      %{
        total_dependencies: length(hex_deps),
        outdated_count: length(outdated),
        outdated_packages: outdated,
        recommendations: if(length(outdated) > 0, do: ["Update outdated dependencies"], else: [])
      }
    end
    
    defp check_security_issues(deps_result, params) do
      # Simulate security checking
      # In reality, would check against vulnerability databases
      hex_deps = deps_result.external.hex || []
      
      vulnerabilities = if params.security_source == :built_in do
        # Check against known vulnerable packages (simplified)
        vulnerable_packages = ["plug", "phoenix", "ecto"] # Example
        
        hex_deps
        |> Enum.filter(fn {_module, package} -> 
          to_string(package) in vulnerable_packages and :rand.uniform() > 0.7
        end)
        |> Enum.map(fn {_module, package} ->
          %{
            package: package,
            vulnerability: "CVE-2024-#{:rand.uniform(9999)}",
            severity: Enum.random([:low, :medium, :high, :critical]),
            description: "Example vulnerability description"
          }
        end)
      else
        []
      end
      
      %{
        vulnerabilities_found: length(vulnerabilities),
        vulnerabilities: vulnerabilities,
        critical_count: Enum.count(vulnerabilities, &(&1.severity == :critical)),
        high_count: Enum.count(vulnerabilities, &(&1.severity == :high)),
        recommendations: generate_security_recommendations(vulnerabilities)
      }
    end
    
    defp check_license_compliance(deps_result, agent) do
      allowed_licenses = agent.state.monitoring_config.allowed_licenses
      hex_deps = deps_result.external.hex || []
      
      # Simulate license checking
      license_issues = hex_deps
      |> Enum.take_random(2)
      |> Enum.map(fn {_module, package} ->
        %{
          package: package,
          license: "GPL-3.0",
          allowed: false,
          risk: :high
        }
      end)
      
      %{
        total_checked: length(hex_deps),
        allowed_licenses: allowed_licenses,
        license_issues: license_issues,
        compliant: length(license_issues) == 0,
        recommendations: if(length(license_issues) > 0, 
          do: ["Review license compliance for flagged packages"],
          else: []
        )
      }
    end
    
    defp calculate_health_score(health_report) do
      base_score = 100.0
      
      # Deduct for outdated dependencies
      outdated_penalty = if health_report.outdated != %{} do
        outdated_ratio = health_report.outdated.outdated_count / max(1, health_report.outdated.total_dependencies)
        outdated_ratio * 20
      else
        0
      end
      
      # Deduct for security issues
      security_penalty = if health_report.security != %{} do
        critical = health_report.security.critical_count * 10
        high = health_report.security.high_count * 5
        critical + high
      else
        0
      end
      
      # Deduct for license issues
      license_penalty = if health_report.licenses != %{} and not health_report.licenses.compliant do
        15
      else
        0
      end
      
      max(0, base_score - outdated_penalty - security_penalty - license_penalty)
    end
    
    defp rate_health_score(score) do
      cond do
        score >= 90 -> :excellent
        score >= 80 -> :good
        score >= 70 -> :fair
        score >= 60 -> :poor
        true -> :critical
      end
    end
    
    defp generate_health_summary(health_report) do
      issues = []
      
      issues = if health_report.outdated != %{} and health_report.outdated.outdated_count > 0 do
        ["#{health_report.outdated.outdated_count} outdated dependencies" | issues]
      else
        issues
      end
      
      issues = if health_report.security != %{} and health_report.security.vulnerabilities_found > 0 do
        ["#{health_report.security.vulnerabilities_found} security vulnerabilities" | issues]
      else
        issues
      end
      
      issues = if health_report.licenses != %{} and not health_report.licenses.compliant do
        ["License compliance issues detected" | issues]
      else
        issues
      end
      
      if issues == [] do
        "All dependency health checks passed"
      else
        "Issues found: " <> Enum.join(issues, ", ")
      end
    end
    
    defp generate_security_recommendations(vulnerabilities) do
      if vulnerabilities == [] do
        []
      else
      
      critical_vulns = Enum.filter(vulnerabilities, &(&1.severity in [:critical, :high]))
      
      recommendations = ["Update packages with security vulnerabilities"]
      
      if length(critical_vulns) > 0 do
        ["URGENT: Address #{length(critical_vulns)} critical/high severity vulnerabilities immediately" | recommendations]
      else
        recommendations
      end
      end
    end
  end
  
  defmodule CompareDependenciesAction do
    @moduledoc false
    use Jido.Action,
      name: "compare_dependencies",
      description: "Compare dependencies between different versions, branches, or projects",
      schema: [
        source_path: [type: :string, required: true],
        target_path: [type: :string, required: true],
        comparison_type: [type: :atom, values: [:versions, :branches, :projects], default: :versions],
        include_transitive: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, context) do
      _agent = context.agent
      
      # Analyze source dependencies
      source_params = %{
        file_path: params.source_path,
        analysis_type: "comprehensive",
        include_stdlib: false
      }
      
      # Analyze target dependencies
      target_params = %{
        file_path: params.target_path,
        analysis_type: "comprehensive",
        include_stdlib: false
      }
      
      with {:ok, source_deps} <- RubberDuck.Tools.DependencyInspector.execute(source_params, %{}),
           {:ok, target_deps} <- RubberDuck.Tools.DependencyInspector.execute(target_params, %{}) do
        
        comparison = compare_dependency_sets(source_deps, target_deps)
        
        {:ok, %{
          source_path: params.source_path,
          target_path: params.target_path,
          comparison_type: params.comparison_type,
          comparison: comparison,
          summary: generate_comparison_summary(comparison),
          recommendations: generate_comparison_recommendations(comparison)
        }}
      else
        {:error, reason} -> {:error, reason}
      end
    end
    
    defp compare_dependency_sets(source, target) do
      source_hex = extract_hex_packages(source)
      target_hex = extract_hex_packages(target)
      
      source_internal = MapSet.new(source.internal || [])
      target_internal = MapSet.new(target.internal || [])
      
      %{
        added: %{
          hex: MapSet.difference(target_hex, source_hex) |> MapSet.to_list(),
          internal: MapSet.difference(target_internal, source_internal) |> MapSet.to_list()
        },
        removed: %{
          hex: MapSet.difference(source_hex, target_hex) |> MapSet.to_list(),
          internal: MapSet.difference(source_internal, target_internal) |> MapSet.to_list()
        },
        unchanged: %{
          hex: MapSet.intersection(source_hex, target_hex) |> MapSet.to_list(),
          internal: MapSet.intersection(source_internal, target_internal) |> MapSet.to_list()
        },
        statistics: %{
          source_total: MapSet.size(source_hex) + MapSet.size(source_internal),
          target_total: MapSet.size(target_hex) + MapSet.size(target_internal),
          change_percentage: calculate_change_percentage(source_hex, target_hex, source_internal, target_internal)
        }
      }
    end
    
    defp extract_hex_packages(deps_result) do
      deps_result.external.hex
      |> Enum.map(fn {_module, package} -> package end)
      |> MapSet.new()
    end
    
    defp calculate_change_percentage(source_hex, target_hex, source_internal, target_internal) do
      total_source = MapSet.size(source_hex) + MapSet.size(source_internal)
      _total_target = MapSet.size(target_hex) + MapSet.size(target_internal)
      
      added = MapSet.size(MapSet.difference(target_hex, source_hex)) +
              MapSet.size(MapSet.difference(target_internal, source_internal))
      removed = MapSet.size(MapSet.difference(source_hex, target_hex)) +
                MapSet.size(MapSet.difference(source_internal, target_internal))
      
      if total_source > 0 do
        ((added + removed) / total_source) * 100
      else
        0
      end
    end
    
    defp generate_comparison_summary(comparison) do
      %{
        total_added: length(comparison.added.hex) + length(comparison.added.internal),
        total_removed: length(comparison.removed.hex) + length(comparison.removed.internal),
        total_unchanged: length(comparison.unchanged.hex) + length(comparison.unchanged.internal),
        change_impact: assess_change_impact(comparison)
      }
    end
    
    defp assess_change_impact(comparison) do
      added_count = length(comparison.added.hex) + length(comparison.added.internal)
      removed_count = length(comparison.removed.hex) + length(comparison.removed.internal)
      
      cond do
        added_count == 0 and removed_count == 0 -> :none
        added_count <= 2 and removed_count <= 2 -> :minor
        added_count <= 5 and removed_count <= 5 -> :moderate
        true -> :major
      end
    end
    
    defp generate_comparison_recommendations(comparison) do
      recommendations = []
      
      # Check for major additions
      recommendations = if length(comparison.added.hex) > 5 do
        [%{
          type: :review,
          priority: :high,
          message: "Significant number of new dependencies added (#{length(comparison.added.hex)})",
          action: "Review new dependencies for necessity and security"
        } | recommendations]
      else
        recommendations
      end
      
      # Check for removals
      recommendations = if length(comparison.removed.hex) > 0 do
        [%{
          type: :compatibility,
          priority: :medium,
          message: "Dependencies removed: #{Enum.join(comparison.removed.hex, ", ")}",
          action: "Ensure no breaking changes from removed dependencies"
        } | recommendations]
      else
        recommendations
      end
      
      recommendations
    end
  
  end
  # Signal handlers
  
  def handle_signal(agent, %{"type" => "analyze_dependencies"} = signal) do
    %{"data" => data} = signal
    
    # Build tool parameters
    params = %{
      code: data["code"] || "",
      file_path: data["file_path"] || "",
      analysis_type: data["analysis_type"] || "comprehensive",
      include_stdlib: data["include_stdlib"] || false,
      depth: data["depth"] || 2,
      group_by: data["group_by"] || "module",
      check_mix_deps: data["check_mix_deps"] || true
    }
    
    # Execute the analysis
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, ExecuteToolAction, %{params: params})
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "check_circular_dependencies"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, CheckCircularDependenciesAction, %{
      paths: data["paths"] || ["lib"],
      include_transitive: data["include_transitive"] || true,
      max_cycle_length: data["max_cycle_length"] || 10
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "find_unused_dependencies"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, FindUnusedDependenciesAction, %{
      project_path: data["project_path"] || ".",
      check_dev_deps: data["check_dev_deps"] || false,
      check_test_deps: data["check_test_deps"] || false,
      confidence_threshold: data["confidence_threshold"] || 0.8
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "analyze_dependency_tree"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, AnalyzeDependencyTreeAction, %{
      root_path: data["root_path"] || ".",
      max_depth: data["max_depth"] || 3,
      include_dev: data["include_dev"] || false,
      include_test: data["include_test"] || false,
      visualization_format: String.to_atom(data["visualization_format"] || "tree")
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "monitor_dependency_health"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, MonitorDependencyHealthAction, %{
      project_path: data["project_path"] || ".",
      check_outdated: data["check_outdated"] || true,
      check_security: data["check_security"] || true,
      check_licenses: data["check_licenses"] || true,
      security_source: String.to_atom(data["security_source"] || "built_in")
    })
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "compare_dependencies"} = signal) do
    %{"data" => data} = signal
    
    {:ok, agent, _directives} = Jido.Agent.cmd(agent, CompareDependenciesAction, %{
      source_path: data["source_path"],
      target_path: data["target_path"],
      comparison_type: String.to_atom(data["comparison_type"] || "versions"),
      include_transitive: data["include_transitive"] || false
    })
    
    {:ok, agent}
  end
  
  # Action result handlers
  
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, _metadata) do
    # Record analysis
    analysis_record = %{
      type: result[:analysis_type] || "comprehensive",
      summary: result.summary,
      external_count: get_in(result, [:summary, :external_count]) || 0,
      internal_count: get_in(result, [:summary, :internal_count]) || 0,
      warnings: result[:warnings] || [],
      timestamp: DateTime.utc_now()
    }
    
    # Add to history
    agent = update_in(agent.state.analysis_history, fn history ->
      new_history = [analysis_record | history]
      if length(new_history) > agent.state.max_history_size do
        Enum.take(new_history, agent.state.max_history_size)
      else
        new_history
      end
    end)
    
    # Update known dependencies
    agent = if result[:external] && result[:internal] do
      put_in(agent.state.known_dependencies, %{
        external: result.external,
        internal: result.internal,
        last_updated: DateTime.utc_now()
      })
    else
      agent
    end
    
    # Update statistics
    agent = update_in(agent.state.analysis_stats, fn stats ->
      new_avg = if stats.total_analyses > 0 do
        total_deps = analysis_record.external_count + analysis_record.internal_count
        (stats.average_dependency_count * stats.total_analyses + total_deps) / (stats.total_analyses + 1)
      else
        analysis_record.external_count + analysis_record.internal_count
      end
      
      stats
      |> Map.update!(:total_analyses, &(&1 + 1))
      |> Map.put(:average_dependency_count, new_avg)
    end)
    
    # Emit completion signal
    signal = Jido.Signal.new!(%{
      type: "dependencies_analyzed",
      source: "agent:#{agent.id}",
      data: %{
        total_dependencies: analysis_record.external_count + analysis_record.internal_count,
        external_count: analysis_record.external_count,
        internal_count: analysis_record.internal_count
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, CheckCircularDependenciesAction, {:ok, result}, _metadata) do
    # Update dependency graph
    agent = if result.circular_dependencies_found do
      update_in(agent.state.dependency_graph, fn graph ->
        graph
        |> Map.put(:cycles, result.cycles)
        |> Map.put(:last_built, DateTime.utc_now())
      end)
    else
      agent
    end
    
    # Update health metrics
    agent = update_in(agent.state.health_metrics, fn metrics ->
      Map.put(metrics, :circular_count, length(result.cycles))
    end)
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "circular_dependencies_found",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, FindUnusedDependenciesAction, {:ok, result}, _metadata) do
    # Update health metrics
    agent = update_in(agent.state.health_metrics, fn metrics ->
      Map.put(metrics, :unused_count, result.unused_count)
    end)
    
    # Update statistics
    agent = update_in(agent.state.analysis_stats.issues_found, &(&1 + result.unused_count))
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "unused_dependencies_found",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, MonitorDependencyHealthAction, {:ok, result}, _metadata) do
    # Update health metrics
    agent = update_in(agent.state.health_metrics, fn metrics ->
      metrics
      |> Map.put(:health_score, result.overall_health.score)
      |> Map.put(:outdated_count, get_in(result, [:outdated, :outdated_count]) || 0)
      |> Map.put(:security_issues, get_in(result, [:security, :vulnerabilities_found]) || 0)
    end)
    
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "dependency_health_report",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, CompareDependenciesAction, {:ok, result}, _metadata) do
    # Emit signal
    signal = Jido.Signal.new!(%{
      type: "dependency_changes_detected",
      source: "agent:#{agent.id}",
      data: result
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_action_result(agent, _, {:error, reason}, metadata) do
    # Update statistics
    agent = update_in(agent.state.analysis_stats.issues_found, &(&1 + 1))
    
    # Emit error signal
    signal = Jido.Signal.new!(%{
      type: "dependency_analysis_error",
      source: "agent:#{agent.id}",
      data: %{
        error: reason,
        metadata: metadata
      }
    })
    Jido.Agent.emit_signal(agent, signal)
    
    {:error, reason}
  end
end