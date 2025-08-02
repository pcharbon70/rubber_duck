defmodule RubberDuck.Tools.Agents.DependencyAnalyzerAgent do
  @moduledoc """
  Agent that analyzes project dependencies and provides insights on dependency management.
  
  Capabilities:
  - Dependency tree analysis
  - Version conflict detection
  - Security vulnerability checking
  - License compatibility analysis
  - Update recommendations
  - Dependency graph visualization
  """
  
  use RubberDuck.Tools.BaseToolAgent, tool: :dependency_analyzer
  
  alias Jido.Agent.Server.State
  
  # Custom actions for dependency analysis
  defmodule AnalyzeDependencyTreeAction do
    @moduledoc """
    Analyzes the project dependency tree structure.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        manifest_files: [type: {:list, :map}, required: true, doc: "Package manifest files (package.json, mix.exs, etc.)"],
        lock_files: [type: {:list, :map}, doc: "Lock files for exact versions"],
        depth_limit: [type: :integer, default: 5, doc: "Maximum depth to analyze"],
        include_dev: [type: :boolean, default: true, doc: "Include dev dependencies"]
      }
    end
    
    @impl true
    def run(params, _context) do
      tree = build_dependency_tree(
        params.manifest_files,
        params.lock_files,
        params.depth_limit,
        params.include_dev
      )
      
      analysis = analyze_tree_structure(tree)
      
      {:ok, %{
        dependency_tree: tree,
        tree_analysis: analysis,
        statistics: calculate_tree_statistics(tree),
        circular_dependencies: detect_circular_dependencies(tree),
        orphaned_dependencies: find_orphaned_dependencies(tree)
      }}
    end
    
    defp build_dependency_tree(manifests, lock_files, depth_limit, include_dev) do
      # Parse manifest files
      dependencies = parse_manifests(manifests, include_dev)
      
      # Apply lock file versions if available
      dependencies = if lock_files do
        apply_lock_versions(dependencies, lock_files)
      else
        dependencies
      end
      
      # Build tree structure
      root = %{
        name: detect_project_name(manifests),
        version: detect_project_version(manifests),
        dependencies: dependencies,
        type: :root,
        depth: 0
      }
      
      expand_tree(root, depth_limit)
    end
    
    defp parse_manifests(manifests, include_dev) do
      manifests
      |> Enum.flat_map(fn manifest ->
        case manifest.type do
          "package.json" -> parse_npm_manifest(manifest.content, include_dev)
          "mix.exs" -> parse_mix_manifest(manifest.content, include_dev)
          "requirements.txt" -> parse_pip_manifest(manifest.content)
          "Gemfile" -> parse_bundler_manifest(manifest.content, include_dev)
          "pom.xml" -> parse_maven_manifest(manifest.content)
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.name)
    end
    
    defp parse_npm_manifest(content, include_dev) do
      parsed = Jason.decode!(content)
      
      prod_deps = Map.get(parsed, "dependencies", %{})
        |> Enum.map(fn {name, version} ->
          %{name: name, version: version, type: :production}
        end)
      
      dev_deps = if include_dev do
        Map.get(parsed, "devDependencies", %{})
        |> Enum.map(fn {name, version} ->
          %{name: name, version: version, type: :development}
        end)
      else
        []
      end
      
      prod_deps ++ dev_deps
    end
    
    defp parse_mix_manifest(content, include_dev) do
      # Simplified parsing - would need actual Elixir AST parsing
      deps = Regex.scan(~r/{:(\w+),\s*"([^"]+)"/, content)
        |> Enum.map(fn [_, name, version] ->
          %{name: name, version: version, type: :production}
        end)
      
      if include_dev do
        dev_deps = Regex.scan(~r/{:(\w+),\s*"([^"]+)",\s*only:\s*:dev/, content)
          |> Enum.map(fn [_, name, version] ->
            %{name: name, version: version, type: :development}
          end)
        deps ++ dev_deps
      else
        deps
      end
    end
    
    defp parse_pip_manifest(content) do
      content
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) == "" || String.starts_with?(&1, "#")))
      |> Enum.map(fn line ->
        case String.split(line, "==") do
          [name, version] -> %{name: String.trim(name), version: String.trim(version), type: :production}
          [name] -> %{name: String.trim(name), version: "*", type: :production}
        end
      end)
    end
    
    defp parse_bundler_manifest(content, include_dev) do
      # Simplified Gemfile parsing
      gems = Regex.scan(~r/gem\s+['"]([^'"]+)['"](?:,\s*['"]([^'"]+)['"])?/, content)
        |> Enum.map(fn
          [_, name, version] when version != "" -> 
            %{name: name, version: version, type: :production}
          [_, name] -> 
            %{name: name, version: "*", type: :production}
        end)
      
      if include_dev do
        # Would need more sophisticated parsing for group :development blocks
        gems
      else
        gems
      end
    end
    
    defp parse_maven_manifest(content) do
      # Simplified POM parsing
      Regex.scan(~r/<dependency>.*?<groupId>([^<]+)<\/groupId>.*?<artifactId>([^<]+)<\/artifactId>.*?<version>([^<]+)<\/version>.*?<\/dependency>/s, content)
        |> Enum.map(fn [_, group, artifact, version] ->
          %{name: "#{group}:#{artifact}", version: version, type: :production}
        end)
    end
    
    defp detect_project_name(manifests) do
      manifest = List.first(manifests)
      if manifest do
        case manifest.type do
          "package.json" ->
            parsed = Jason.decode!(manifest.content)
            Map.get(parsed, "name", "unknown")
          _ -> "project"
        end
      else
        "unknown"
      end
    end
    
    defp detect_project_version(manifests) do
      manifest = List.first(manifests)
      if manifest do
        case manifest.type do
          "package.json" ->
            parsed = Jason.decode!(manifest.content)
            Map.get(parsed, "version", "0.0.0")
          _ -> "0.0.0"
        end
      else
        "0.0.0"
      end
    end
    
    defp apply_lock_versions(dependencies, lock_files) do
      lock_versions = parse_lock_files(lock_files)
      
      Enum.map(dependencies, fn dep ->
        locked_version = Map.get(lock_versions, dep.name)
        if locked_version do
          Map.put(dep, :version, locked_version)
        else
          dep
        end
      end)
    end
    
    defp parse_lock_files(lock_files) do
      lock_files
      |> Enum.reduce(%{}, fn lock_file, acc ->
        versions = case lock_file.type do
          "package-lock.json" -> parse_npm_lock(lock_file.content)
          "mix.lock" -> parse_mix_lock(lock_file.content)
          "Pipfile.lock" -> parse_pipfile_lock(lock_file.content)
          _ -> %{}
        end
        Map.merge(acc, versions)
      end)
    end
    
    defp parse_npm_lock(content) do
      # Simplified parsing
      parsed = Jason.decode!(content)
      
      packages = Map.get(parsed, "packages", %{})
      Enum.reduce(packages, %{}, fn {path, info}, acc ->
        if String.starts_with?(path, "node_modules/") do
          name = String.replace_prefix(path, "node_modules/", "")
          Map.put(acc, name, info["version"])
        else
          acc
        end
      end)
    end
    
    defp parse_mix_lock(_content) do
      # Would need Elixir term parsing
      %{}
    end
    
    defp parse_pipfile_lock(content) do
      parsed = Jason.decode!(content)
      
      default_deps = Map.get(parsed, "default", %{})
      Enum.reduce(default_deps, %{}, fn {name, info}, acc ->
        Map.put(acc, name, info["version"])
      end)
    end
    
    defp expand_tree(node, depth_limit) do
      if node.depth >= depth_limit do
        Map.put(node, "dependencies", [])
      else
        # In real implementation, would fetch subdependencies
        # For now, just mark that expansion would happen
        Map.put(node, :expanded, node.depth < depth_limit)
      end
    end
    
    defp analyze_tree_structure(tree) do
      %{
        max_depth: calculate_max_depth(tree),
        total_dependencies: count_all_dependencies(tree),
        unique_dependencies: count_unique_dependencies(tree),
        dependency_types: analyze_dependency_types(tree),
        complexity_score: calculate_complexity_score(tree)
      }
    end
    
    defp calculate_max_depth(node, current_depth \\ 0) do
      if node["dependencies"] && length(node.dependencies) > 0 do
        child_depths = Enum.map(node.dependencies, fn dep ->
          calculate_max_depth(dep, current_depth + 1)
        end)
        Enum.max(child_depths)
      else
        current_depth
      end
    end
    
    defp count_all_dependencies(node) do
      direct_count = length(node["dependencies"] || [])
      
      child_counts = if node["dependencies"] do
        Enum.map(node.dependencies, &count_all_dependencies/1)
        |> Enum.sum()
      else
        0
      end
      
      direct_count + child_counts
    end
    
    defp count_unique_dependencies(tree) do
      collect_all_dependencies(tree)
      |> Enum.uniq_by(& &1.name)
      |> length()
    end
    
    defp collect_all_dependencies(node, acc \\ []) do
      deps = node["dependencies"] || []
      
      all_deps = deps ++ acc
      
      Enum.reduce(deps, all_deps, fn dep, acc ->
        collect_all_dependencies(dep, acc)
      end)
    end
    
    defp analyze_dependency_types(tree) do
      all_deps = collect_all_dependencies(tree)
      
      Enum.reduce(all_deps, %{}, fn dep, acc ->
        type = dep[:type] || :production
        Map.update(acc, type, 1, &(&1 + 1))
      end)
    end
    
    defp calculate_complexity_score(tree) do
      depth = calculate_max_depth(tree)
      total = count_all_dependencies(tree)
      unique = count_unique_dependencies(tree)
      
      # Higher score = more complex
      depth_score = depth * 10
      total_score = total * 0.5
      duplication_score = (total - unique) * 2
      
      depth_score + total_score + duplication_score
    end
    
    defp calculate_tree_statistics(tree) do
      all_deps = collect_all_dependencies(tree)
      
      %{
        total_dependencies: length(all_deps),
        unique_dependencies: all_deps |> Enum.uniq_by(& &1.name) |> length(),
        production_dependencies: Enum.count(all_deps, &(&1.type == :production)),
        development_dependencies: Enum.count(all_deps, &(&1.type == :development)),
        average_depth: calculate_average_depth(tree),
        most_common_dependencies: find_most_common_dependencies(all_deps)
      }
    end
    
    defp calculate_average_depth(tree) do
      depths = collect_node_depths(tree)
      if length(depths) > 0 do
        Enum.sum(depths) / length(depths)
      else
        0
      end
    end
    
    defp collect_node_depths(node, current_depth \\ 0, acc \\ []) do
      acc = [current_depth | acc]
      
      if node["dependencies"] do
        Enum.reduce(node.dependencies, acc, fn dep, acc ->
          collect_node_depths(dep, current_depth + 1, acc)
        end)
      else
        acc
      end
    end
    
    defp find_most_common_dependencies(all_deps) do
      all_deps
      |> Enum.frequencies_by(& &1.name)
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.take(5)
      |> Enum.map(fn {name, count} -> %{name: name, usage_count: count} end)
    end
    
    defp detect_circular_dependencies(tree) do
      # Simplified circular dependency detection
      []
    end
    
    defp find_orphaned_dependencies(tree) do
      # Dependencies declared but not used
      []
    end
  end
  
  defmodule DetectVersionConflictsAction do
    @moduledoc """
    Detects version conflicts in the dependency tree.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependency_tree: [type: :map, required: true, doc: "Analyzed dependency tree"],
        resolution_strategy: [type: :string, default: "latest", doc: "Strategy: latest, stable, compatible"],
        check_peer_deps: [type: :boolean, default: true, doc: "Check peer dependency conflicts"]
      }
    end
    
    @impl true
    def run(params, _context) do
      conflicts = detect_conflicts(
        params.dependency_tree,
        params.check_peer_deps
      )
      
      resolutions = suggest_resolutions(
        conflicts,
        params.resolution_strategy
      )
      
      {:ok, %{
        conflicts: conflicts,
        conflict_count: length(conflicts),
        severity_breakdown: analyze_conflict_severity(conflicts),
        resolutions: resolutions,
        compatibility_matrix: build_compatibility_matrix(conflicts),
        risk_assessment: assess_conflict_risks(conflicts)
      }}
    end
    
    defp detect_conflicts(tree, check_peer_deps) do
      all_deps = collect_all_dependencies_with_path(tree)
      
      # Group by package name
      grouped = Enum.group_by(all_deps, & &1.name)
      
      # Find conflicts
      conflicts = grouped
        |> Enum.flat_map(fn {name, occurrences} ->
          if length(occurrences) > 1 do
            versions = occurrences |> Enum.map(& &1.version) |> Enum.uniq()
            
            if length(versions) > 1 do
              [%{
                package: name,
                conflicts: analyze_version_conflicts(occurrences),
                severity: determine_conflict_severity(versions),
                affected_paths: Enum.map(occurrences, & &1.path)
              }]
            else
              []
            end
          else
            []
          end
        end)
      
      # Add peer dependency conflicts if requested
      if check_peer_deps do
        peer_conflicts = detect_peer_dependency_conflicts(all_deps)
        conflicts ++ peer_conflicts
      else
        conflicts
      end
    end
    
    defp collect_all_dependencies_with_path(node, path \\ []) do
      current_path = path ++ [node.name]
      
      deps = node["dependencies"] || []
      
      dep_entries = Enum.map(deps, fn dep ->
        %{
          name: dep.name,
          version: dep.version,
          path: current_path,
          type: dep[:type] || :production
        }
      end)
      
      # Recursively collect from children
      child_entries = deps
        |> Enum.flat_map(fn dep ->
          collect_all_dependencies_with_path(dep, current_path)
        end)
      
      dep_entries ++ child_entries
    end
    
    defp analyze_version_conflicts(occurrences) do
      occurrences
      |> Enum.map(fn occ ->
        %{
          version: occ.version,
          path: Enum.join(occ.path, " -> "),
          type: occ.type
        }
      end)
      |> Enum.sort_by(& &1.version)
    end
    
    defp determine_conflict_severity(versions) do
      # Parse versions and determine severity based on differences
      parsed_versions = Enum.map(versions, &parse_version/1)
      
      major_diff = check_major_difference(parsed_versions)
      minor_diff = check_minor_difference(parsed_versions)
      
      cond do
        major_diff -> :critical
        minor_diff -> :moderate
        true -> :low
      end
    end
    
    defp parse_version(version_string) do
      # Handle various version formats
      cleaned = version_string
        |> String.replace(~r/^[~^>=<]+/, "")
        |> String.split(".")
        |> Enum.map(&String.to_integer(&1))
        |> Enum.take(3)
      
      case cleaned do
        [major, minor, patch] -> %{major: major, minor: minor, patch: patch}
        [major, minor] -> %{major: major, minor: minor, patch: 0}
        [major] -> %{major: major, minor: 0, patch: 0}
        _ -> %{major: 0, minor: 0, patch: 0}
      end
    end
    
    defp check_major_difference(parsed_versions) do
      majors = Enum.map(parsed_versions, & &1.major) |> Enum.uniq()
      length(majors) > 1
    end
    
    defp check_minor_difference(parsed_versions) do
      majors = Enum.map(parsed_versions, & &1.major) |> Enum.uniq()
      
      if length(majors) == 1 do
        minors = Enum.map(parsed_versions, & &1.minor) |> Enum.uniq()
        length(minors) > 1
      else
        false
      end
    end
    
    defp detect_peer_dependency_conflicts(_all_deps) do
      # Would check package metadata for peer dependency requirements
      []
    end
    
    defp suggest_resolutions(conflicts, strategy) do
      Enum.map(conflicts, fn conflict ->
        %{
          package: conflict.package,
          current_versions: extract_versions(conflict.conflicts),
          suggested_version: determine_resolution_version(conflict, strategy),
          resolution_strategy: strategy,
          implementation_steps: generate_resolution_steps(conflict, strategy),
          potential_risks: assess_resolution_risks(conflict, strategy)
        }
      end)
    end
    
    defp extract_versions(conflicts) do
      conflicts |> Enum.map(& &1.version) |> Enum.uniq()
    end
    
    defp determine_resolution_version(conflict, strategy) do
      versions = extract_versions(conflict.conflicts)
      
      case strategy do
        "latest" -> 
          # Get the highest version
          versions |> Enum.sort() |> List.last()
        
        "stable" ->
          # Prefer non-prerelease versions
          versions
          |> Enum.reject(&String.contains?(&1, "-"))
          |> Enum.sort()
          |> List.last() || List.last(Enum.sort(versions))
        
        "compatible" ->
          # Find highest version that satisfies all constraints
          find_compatible_version(versions)
        
        _ ->
          List.last(Enum.sort(versions))
      end
    end
    
    defp find_compatible_version(versions) do
      # Simplified - would need proper semver range checking
      versions |> Enum.sort() |> List.last()
    end
    
    defp generate_resolution_steps(conflict, strategy) do
      [
        "Update #{conflict.package} to suggested version across all usages",
        "Run dependency installation to verify resolution",
        "Test affected components for compatibility",
        "Update lock file to ensure consistent versions"
      ]
    end
    
    defp assess_resolution_risks(conflict, _strategy) do
      case conflict.severity do
        :critical ->
          ["Breaking changes likely", "Extensive testing required", "May require code updates"]
        :moderate ->
          ["Some API changes possible", "Test critical paths", "Review changelog"]
        :low ->
          ["Minimal risk", "Basic testing recommended"]
      end
    end
    
    defp analyze_conflict_severity(conflicts) do
      %{
        critical: Enum.count(conflicts, &(&1.severity == :critical)),
        moderate: Enum.count(conflicts, &(&1.severity == :moderate)),
        low: Enum.count(conflicts, &(&1.severity == :low)),
        total: length(conflicts)
      }
    end
    
    defp build_compatibility_matrix(conflicts) do
      # For each conflict, show which versions are compatible
      Enum.map(conflicts, fn conflict ->
        %{
          package: conflict.package,
          matrix: build_version_compatibility_matrix(conflict.conflicts)
        }
      end)
    end
    
    defp build_version_compatibility_matrix(version_conflicts) do
      versions = extract_versions(version_conflicts)
      
      # Simplified compatibility check
      Enum.map(versions, fn v1 ->
        %{
          version: v1,
          compatible_with: Enum.filter(versions, fn v2 ->
            check_version_compatibility(v1, v2)
          end)
        }
      end)
    end
    
    defp check_version_compatibility(v1, v2) do
      parsed1 = parse_version(v1)
      parsed2 = parse_version(v2)
      
      # Same major version = likely compatible
      parsed1.major == parsed2.major
    end
    
    defp assess_conflict_risks(conflicts) do
      critical_count = Enum.count(conflicts, &(&1.severity == :critical))
      
      %{
        overall_risk: determine_overall_risk(conflicts),
        immediate_action_required: critical_count > 0,
        estimated_effort: estimate_resolution_effort(conflicts),
        testing_scope: determine_testing_scope(conflicts)
      }
    end
    
    defp determine_overall_risk(conflicts) do
      severity_scores = Enum.map(conflicts, fn c ->
        case c.severity do
          :critical -> 3
          :moderate -> 2
          :low -> 1
        end
      end)
      
      if length(severity_scores) == 0 do
        :minimal
      else
        avg_score = Enum.sum(severity_scores) / length(severity_scores)
        
        cond do
          avg_score >= 2.5 -> :high
          avg_score >= 1.5 -> :medium
          true -> :low
        end
      end
    end
    
    defp estimate_resolution_effort(conflicts) do
      hours = conflicts
        |> Enum.map(fn c ->
          case c.severity do
            :critical -> 4
            :moderate -> 2
            :low -> 0.5
          end
        end)
        |> Enum.sum()
      
      "#{hours}-#{hours * 1.5} hours"
    end
    
    defp determine_testing_scope(conflicts) do
      if Enum.any?(conflicts, &(&1.severity == :critical)) do
        "Full regression testing required"
      else
        "Targeted testing of affected components"
      end
    end
  end
  
  defmodule CheckSecurityVulnerabilitiesAction do
    @moduledoc """
    Checks dependencies for known security vulnerabilities.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependencies: [type: {:list, :map}, required: true, doc: "List of dependencies with versions"],
        vulnerability_db: [type: :string, default: "auto", doc: "Vulnerability database to use"],
        severity_threshold: [type: :string, default: "low", doc: "Minimum severity to report"],
        include_dev: [type: :boolean, default: false, doc: "Check dev dependencies"]
      }
    end
    
    @impl true
    def run(params, context) do
      vulnerabilities = if cve_checker_available?() do
        # Use CVE checker tool for more comprehensive scanning
        check_vulnerabilities_with_cve_tool(
          params.dependencies,
          params.severity_threshold,
          params.include_dev,
          context
        )
      else
        # Fall back to built-in vulnerability database
        check_vulnerabilities(
          params.dependencies,
          params.vulnerability_db,
          params.severity_threshold,
          params.include_dev
        )
      end
      
      # Create unified result structure
      security_summary = %{
        total_vulnerabilities: length(vulnerabilities),
        by_severity: analyze_severity_breakdown(vulnerabilities),
        dependencies_affected: length(get_affected_dependencies(vulnerabilities)),
        risk_level: calculate_risk_level(vulnerabilities)
      }
      
      {:ok, %{
        vulnerabilities: vulnerabilities,
        security_summary: security_summary,
        remediation_plan: generate_remediation_plan(vulnerabilities),
        security_score: calculate_security_score(vulnerabilities)
      }}
    end
    
    defp cve_checker_available?() do
      # Check if CVE checker tool is registered
      case RubberDuck.Tool.Registry.get(:cve_checker) do
        {:ok, _} -> true
        _ -> false
      end
    rescue
      _ -> false
    end
    
    defp check_vulnerabilities_with_cve_tool(dependencies, threshold, include_dev, context) do
      # Convert dependencies to CVE checker format
      dep_list = dependencies
      |> Map.values()
      |> Enum.map(fn dep ->
        %{
          name: dep.name,
          version: dep.version,
          registry: Map.get(dep, :registry, guess_registry(dep.name))
        }
      end)
      
      # Use CVE checker tool
      tool_call = %RubberDuck.Types.ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: dep_list,
          check_transitive: true,
          severity_threshold: threshold,
          include_patched: true,
          sources: Map.get(context, :cve_sources, ["nvd", "osv", "ghsa"])
        }
      }
      
      case RubberDuck.Tools.CVEChecker.execute(tool_call) do
        {:ok, %{result: cve_result}} ->
          # Convert CVE checker results to our format
          cve_result.vulnerabilities
          |> Enum.map(fn vuln ->
            %{
              dependency: vuln.package,
              severity: String.to_atom(vuln.severity),
              cve_ids: [vuln.cve_id],
              description: vuln.description,
              patched_versions: vuln.patched_versions,
              current_version: vuln.version,
              exploitability: vuln.exploitability,
              cvss_score: vuln.cvss_score,
              published_date: vuln.published_date,
              references: vuln.references
            }
          end)
        
        {:error, _reason} ->
          # Fall back to built-in database
          check_vulnerabilities(dependencies, "built-in", threshold, include_dev)
      end
    rescue
      _ ->
        # Fall back to built-in database
        check_vulnerabilities(dependencies, "built-in", threshold, include_dev)
    end
    
    defp guess_registry(package_name) do
      cond do
        String.contains?(package_name, "/") -> "npm"  # Scoped packages
        String.starts_with?(package_name, "py") -> "pypi"
        String.ends_with?(package_name, "_ex") -> "hex"
        true -> "npm"  # Default
      end
    end
    
    defp check_vulnerabilities(dependencies, db_type, threshold, include_dev) do
      deps_to_check = if include_dev do
        dependencies
      else
        Enum.filter(dependencies, &(&1.type != :development))
      end
      
      deps_to_check
      |> Enum.flat_map(fn dep ->
        find_vulnerabilities_for_package(dep, db_type)
      end)
      |> filter_by_severity(threshold)
      |> Enum.sort_by(&{severity_to_number(&1.severity), &1.package})
    end
    
    defp find_vulnerabilities_for_package(dep, _db_type) do
      # Simulated vulnerability database lookup
      known_vulnerabilities = get_known_vulnerabilities()
      
      case Map.get(known_vulnerabilities, dep.name) do
        nil -> []
        vulns ->
          vulns
          |> Enum.filter(fn vuln ->
            version_affected?(dep.version, vuln.affected_versions)
          end)
          |> Enum.map(fn vuln ->
            Map.merge(vuln, %{
              package: dep.name,
              current_version: dep.version,
              dependency_type: dep.type
            })
          end)
      end
    end
    
    defp get_known_vulnerabilities do
      # Simulated vulnerability database
      %{
        "lodash" => [
          %{
            id: "CVE-2021-23337",
            severity: :high,
            affected_versions: "< 4.17.21",
            description: "Command Injection in lodash",
            published_date: "2021-02-15",
            fixed_versions: ["4.17.21"]
          }
        ],
        "express" => [
          %{
            id: "CVE-2022-24999",
            severity: :moderate,
            affected_versions: ">= 4.0.0, < 4.18.0",
            description: "ReDoS in query parser",
            published_date: "2022-11-26",
            fixed_versions: ["4.18.0", "5.0.0"]
          }
        ],
        "webpack" => [
          %{
            id: "CVE-2023-28154",
            severity: :moderate,
            affected_versions: "< 5.76.0",
            description: "Cross-realm object access",
            published_date: "2023-03-13",
            fixed_versions: ["5.76.0"]
          }
        ],
        "minimist" => [
          %{
            id: "CVE-2021-44906",
            severity: :critical,
            affected_versions: "< 1.2.6",
            description: "Prototype Pollution",
            published_date: "2022-03-17",
            fixed_versions: ["1.2.6"]
          }
        ]
      }
    end
    
    defp version_affected?(current_version, affected_range) do
      # Simplified version checking
      cond do
        String.starts_with?(affected_range, "<") ->
          target = String.trim_leading(affected_range, "< ")
          version_less_than?(current_version, target)
        
        String.contains?(affected_range, ",") ->
          # Range check - simplified
          true
        
        true ->
          false
      end
    end
    
    defp version_less_than?(v1, v2) do
      # Simplified version comparison
      v1 < v2
    end
    
    defp filter_by_severity(vulnerabilities, threshold) do
      threshold_num = severity_to_number(String.to_atom(threshold))
      
      Enum.filter(vulnerabilities, fn vuln ->
        severity_to_number(vuln.severity) >= threshold_num
      end)
    end
    
    defp severity_to_number(:critical), do: 4
    defp severity_to_number(:high), do: 3
    defp severity_to_number(:moderate), do: 2
    defp severity_to_number(:low), do: 1
    defp severity_to_number(_), do: 0
    
    defp analyze_severity_breakdown(vulnerabilities) do
      %{
        critical: Enum.count(vulnerabilities, &(&1.severity == :critical)),
        high: Enum.count(vulnerabilities, &(&1.severity == :high)),
        moderate: Enum.count(vulnerabilities, &(&1.severity == :moderate)),
        low: Enum.count(vulnerabilities, &(&1.severity == :low))
      }
    end
    
    defp get_affected_dependencies(vulnerabilities) do
      vulnerabilities
      |> Enum.map(& &1.package)
      |> Enum.uniq()
      |> Enum.map(fn package ->
        package_vulns = Enum.filter(vulnerabilities, &(&1.package == package))
        %{
          package: package,
          vulnerability_count: length(package_vulns),
          highest_severity: get_highest_severity(package_vulns),
          cve_ids: Enum.map(package_vulns, & &1.id)
        }
      end)
    end
    
    defp get_highest_severity(vulnerabilities) do
      vulnerabilities
      |> Enum.map(& &1.severity)
      |> Enum.max_by(&severity_to_number/1)
    end
    
    defp generate_remediation_plan(vulnerabilities) do
      vulnerabilities
      |> Enum.group_by(& &1.package)
      |> Enum.map(fn {package, vulns} ->
        %{
          package: package,
          current_version: hd(vulns).current_version,
          recommended_version: get_safe_version(vulns),
          vulnerabilities_fixed: length(vulns),
          priority: get_highest_severity(vulns),
          update_command: generate_update_command(package, get_safe_version(vulns))
        }
      end)
      |> Enum.sort_by(&severity_to_number(&1.priority), :desc)
    end
    
    defp get_safe_version(vulnerabilities) do
      # Get the minimum safe version from all vulnerabilities
      vulnerabilities
      |> Enum.flat_map(& &1.fixed_versions)
      |> Enum.sort()
      |> List.last() || "latest"
    end
    
    defp generate_update_command(package, version) do
      # Would detect package manager and generate appropriate command
      "npm install #{package}@#{version}"
    end
    
    defp calculate_risk_score(vulnerabilities) do
      if length(vulnerabilities) == 0 do
        0.0
      else
        scores = Enum.map(vulnerabilities, fn vuln ->
          base_score = case vuln.severity do
            :critical -> 10.0
            :high -> 7.5
            :moderate -> 5.0
            :low -> 2.5
          end
          
          # Adjust for dependency type
          if vuln.dependency_type == :development do
            base_score * 0.5
          else
            base_score
          end
        end)
        
        # Calculate weighted score
        total_score = Enum.sum(scores)
        max_possible = length(vulnerabilities) * 10.0
        
        (total_score / max_possible) * 100
      end
    end
    
    defp calculate_risk_level(vulnerabilities) do
      critical_count = Enum.count(vulnerabilities, &(&1.severity == :critical))
      high_count = Enum.count(vulnerabilities, &(&1.severity == :high))
      
      cond do
        critical_count > 0 -> :critical
        high_count > 2 -> :high
        high_count > 0 -> :medium
        length(vulnerabilities) > 5 -> :medium
        length(vulnerabilities) > 0 -> :low
        true -> :none
      end
    end
    
    defp calculate_security_score(vulnerabilities) do
      # Security score (inverse of risk score)
      calculate_risk_score(vulnerabilities)
    end
  end
  
  defmodule AnalyzeLicenseCompatibilityAction do
    @moduledoc """
    Analyzes license compatibility across dependencies.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependencies: [type: {:list, :map}, required: true, doc: "Dependencies with license info"],
        project_license: [type: :string, required: true, doc: "Project's license"],
        license_policy: [type: :map, doc: "Organization's license policy"],
        check_transitive: [type: :boolean, default: true, doc: "Check transitive dependencies"]
      }
    end
    
    @impl true
    def run(params, _context) do
      compatibility_issues = analyze_compatibility(
        params.dependencies,
        params.project_license,
        params.license_policy,
        params.check_transitive
      )
      
      {:ok, %{
        compatibility_issues: compatibility_issues,
        issue_count: length(compatibility_issues),
        license_summary: summarize_licenses(params.dependencies),
        risk_assessment: assess_license_risks(compatibility_issues),
        recommendations: generate_license_recommendations(compatibility_issues),
        compliance_status: determine_compliance_status(compatibility_issues, params.license_policy)
      }}
    end
    
    defp analyze_compatibility(dependencies, project_license, policy, check_transitive) do
      # Get license for each dependency
      deps_with_licenses = enrich_with_license_info(dependencies)
      
      # Check compatibility
      issues = []
      
      # Check each dependency's license compatibility
      direct_issues = deps_with_licenses
        |> Enum.filter(&(&1.type == :production))
        |> Enum.flat_map(fn dep ->
          check_license_compatibility(dep, project_license, policy)
        end)
      
      issues = issues ++ direct_issues
      
      # Check transitive dependencies if requested
      if check_transitive do
        transitive_issues = check_transitive_license_issues(deps_with_licenses, project_license)
        issues ++ transitive_issues
      else
        issues
      end
    end
    
    defp enrich_with_license_info(dependencies) do
      Enum.map(dependencies, fn dep ->
        license = detect_dependency_license(dep)
        Map.put(dep, :license, license)
      end)
    end
    
    defp detect_dependency_license(dep) do
      # Simulated license detection
      known_licenses = %{
        "react" => "MIT",
        "vue" => "MIT",
        "angular" => "MIT",
        "express" => "MIT",
        "lodash" => "MIT",
        "webpack" => "MIT",
        "gpl-library" => "GPL-3.0",
        "agpl-component" => "AGPL-3.0",
        "commercial-sdk" => "Commercial",
        "apache-commons" => "Apache-2.0",
        "boost" => "BSL-1.0"
      }
      
      Map.get(known_licenses, dep.name, "Unknown")
    end
    
    defp check_license_compatibility(dep, project_license, policy) do
      compatibility = get_license_compatibility_matrix()
      
      issues = []
      
      # Check basic compatibility
      if !is_compatible?(dep.license, project_license, compatibility) do
        issues = [%{
          type: :incompatible_license,
          package: dep.name,
          package_license: dep.license,
          project_license: project_license,
          severity: :high,
          description: "License #{dep.license} may be incompatible with #{project_license}"
        } | issues]
      end
      
      # Check against policy
      if policy && violates_policy?(dep.license, policy) do
        issues = [%{
          type: :policy_violation,
          package: dep.name,
          package_license: dep.license,
          severity: :critical,
          description: "License #{dep.license} violates organization policy"
        } | issues]
      end
      
      # Check for copyleft in production dependencies
      if is_copyleft?(dep.license) && dep.type == :production do
        issues = [%{
          type: :copyleft_license,
          package: dep.name,
          package_license: dep.license,
          severity: :moderate,
          description: "Copyleft license #{dep.license} may require source disclosure"
        } | issues]
      end
      
      issues
    end
    
    defp get_license_compatibility_matrix do
      %{
        "MIT" => ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC", "BSD-2-Clause"],
        "Apache-2.0" => ["Apache-2.0", "MIT", "BSD-3-Clause", "ISC"],
        "GPL-3.0" => ["GPL-3.0", "AGPL-3.0"],
        "AGPL-3.0" => ["AGPL-3.0"],
        "BSD-3-Clause" => ["MIT", "BSD-3-Clause", "Apache-2.0", "ISC"],
        "ISC" => ["MIT", "ISC", "BSD-3-Clause", "Apache-2.0"]
      }
    end
    
    defp is_compatible?(dep_license, project_license, compatibility_matrix) do
      compatible_licenses = Map.get(compatibility_matrix, project_license, [])
      dep_license in compatible_licenses || dep_license == project_license
    end
    
    defp violates_policy?(license, policy) do
      blacklisted = Map.get(policy, :blacklisted_licenses, [])
      license in blacklisted
    end
    
    defp is_copyleft?(license) do
      copyleft_licenses = ["GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-2.1", "LGPL-3.0"]
      license in copyleft_licenses
    end
    
    defp check_transitive_license_issues(_deps_with_licenses, _project_license) do
      # Would check transitive dependency licenses
      []
    end
    
    defp summarize_licenses(dependencies) do
      licenses = dependencies
        |> Enum.map(& &1[:license] || "Unknown")
        |> Enum.frequencies()
      
      %{
        license_breakdown: licenses,
        unique_licenses: Map.keys(licenses),
        most_common_license: get_most_common_license(licenses),
        unknown_licenses: count_unknown_licenses(dependencies)
      }
    end
    
    defp get_most_common_license(license_frequencies) do
      if map_size(license_frequencies) > 0 do
        {license, _count} = Enum.max_by(license_frequencies, fn {_, count} -> count end)
        license
      else
        "None"
      end
    end
    
    defp count_unknown_licenses(dependencies) do
      Enum.count(dependencies, &((&1[:license] || "Unknown") == "Unknown"))
    end
    
    defp assess_license_risks(issues) do
      risk_score = issues
        |> Enum.map(fn issue ->
          case issue.severity do
            :critical -> 10
            :high -> 7
            :moderate -> 4
            :low -> 2
          end
        end)
        |> Enum.sum()
      
      %{
        risk_score: risk_score,
        risk_level: categorize_risk_level(risk_score),
        critical_issues: Enum.count(issues, &(&1.severity == :critical)),
        legal_review_required: risk_score > 20 || Enum.any?(issues, &(&1.type == :copyleft_license))
      }
    end
    
    defp categorize_risk_level(score) do
      cond do
        score >= 30 -> :critical
        score >= 20 -> :high
        score >= 10 -> :moderate
        score > 0 -> :low
        true -> :minimal
      end
    end
    
    defp generate_license_recommendations(issues) do
      recommendations = []
      
      # Group issues by type
      issue_types = Enum.group_by(issues, & &1.type)
      
      # Recommendations for incompatible licenses
      if issue_types[:incompatible_license] do
        recommendations = [
          "Review and possibly replace incompatible dependencies",
          "Consider dual licensing if appropriate"
        ] ++ recommendations
      end
      
      # Recommendations for policy violations
      if issue_types[:policy_violation] do
        recommendations = [
          "Replace dependencies that violate license policy",
          "Request policy exception if dependency is critical"
        ] ++ recommendations
      end
      
      # Recommendations for copyleft licenses
      if issue_types[:copyleft_license] do
        recommendations = [
          "Ensure compliance with copyleft requirements",
          "Consider isolating copyleft dependencies",
          "Document source code availability requirements"
        ] ++ recommendations
      end
      
      recommendations
    end
    
    defp determine_compliance_status(issues, policy) do
      critical_issues = Enum.filter(issues, &(&1.severity == :critical))
      
      status = cond do
        length(critical_issues) > 0 -> :non_compliant
        length(issues) > 5 -> :needs_review
        length(issues) > 0 -> :minor_issues
        true -> :compliant
      end
      
      %{
        status: status,
        compliant: status == :compliant,
        review_required: status in [:non_compliant, :needs_review],
        blockers: critical_issues
      }
    end
  end
  
  defmodule GenerateUpdateRecommendationsAction do
    @moduledoc """
    Generates recommendations for dependency updates.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependencies: [type: {:list, :map}, required: true, doc: "Current dependencies"],
        update_strategy: [type: :string, default: "balanced", doc: "Strategy: conservative, balanced, aggressive"],
        security_vulnerabilities: [type: {:list, :map}, doc: "Known vulnerabilities"],
        check_breaking_changes: [type: :boolean, default: true, doc: "Check for breaking changes"]
      }
    end
    
    @impl true
    def run(params, _context) do
      recommendations = generate_update_recommendations(
        params.dependencies,
        params.update_strategy,
        params.security_vulnerabilities,
        params.check_breaking_changes
      )
      
      {:ok, %{
        update_recommendations: recommendations,
        update_count: count_updates(recommendations),
        priority_updates: identify_priority_updates(recommendations),
        update_plan: create_update_plan(recommendations),
        risk_analysis: analyze_update_risks(recommendations),
        estimated_effort: estimate_update_effort(recommendations)
      }}
    end
    
    defp generate_update_recommendations(dependencies, strategy, vulnerabilities, check_breaking) do
      dependencies
      |> Enum.map(fn dep ->
        latest_version = get_latest_version(dep.name)
        update_type = categorize_update(dep.version, latest_version)
        
        %{
          package: dep.name,
          current_version: dep.version,
          latest_version: latest_version,
          update_type: update_type,
          recommendation: generate_recommendation(dep, latest_version, strategy, update_type),
          security_update: is_security_update?(dep, vulnerabilities),
          breaking_changes: if(check_breaking, do: check_for_breaking_changes(dep, latest_version), else: []),
          changelog_highlights: get_changelog_highlights(dep.name, dep.version, latest_version)
        }
      end)
      |> Enum.filter(&(&1.recommendation != :no_update))
    end
    
    defp get_latest_version(package_name) do
      # Simulated latest version lookup
      latest_versions = %{
        "react" => "18.2.0",
        "vue" => "3.3.4",
        "express" => "4.18.2",
        "lodash" => "4.17.21",
        "webpack" => "5.88.2",
        "typescript" => "5.2.2",
        "jest" => "29.7.0",
        "eslint" => "8.51.0"
      }
      
      Map.get(latest_versions, package_name, "unknown")
    end
    
    defp categorize_update(current, latest) do
      current_parts = parse_version_parts(current)
      latest_parts = parse_version_parts(latest)
      
      cond do
        current_parts.major < latest_parts.major -> :major
        current_parts.minor < latest_parts.minor -> :minor
        current_parts.patch < latest_parts.patch -> :patch
        true -> :none
      end
    end
    
    defp parse_version_parts(version) do
      parts = version
        |> String.replace(~r/^[^0-9]+/, "")
        |> String.split(".")
        |> Enum.map(&String.to_integer(&1))
        |> Enum.take(3)
      
      case parts do
        [major, minor, patch] -> %{major: major, minor: minor, patch: patch}
        [major, minor] -> %{major: major, minor: minor, patch: 0}
        [major] -> %{major: major, minor: 0, patch: 0}
        _ -> %{major: 0, minor: 0, patch: 0}
      end
    end
    
    defp generate_recommendation(dep, latest_version, strategy, update_type) do
      cond do
        dep.version == latest_version -> 
          :no_update
        
        is_security_critical?(dep) ->
          :update_immediately
        
        true ->
          case {strategy, update_type} do
            {"conservative", :major} -> :review_carefully
            {"conservative", :minor} -> :update_after_testing
            {"conservative", :patch} -> :update_recommended
            
            {"balanced", :major} -> :update_after_testing
            {"balanced", _} -> :update_recommended
            
            {"aggressive", _} -> :update_recommended
            
            _ -> :review_carefully
          end
      end
    end
    
    defp is_security_critical?(_dep) do
      # Would check against known critical vulnerabilities
      false
    end
    
    defp is_security_update?(dep, vulnerabilities) do
      vulnerabilities && Enum.any?(vulnerabilities, &(&1.package == dep.name))
    end
    
    defp check_for_breaking_changes(dep, latest_version) do
      # Simulated breaking change detection
      breaking_changes = %{
        "react" => %{
          "18.0.0" => ["New automatic batching", "Stricter StrictMode"],
          "17.0.0" => ["Event delegation changes", "No event pooling"]
        },
        "webpack" => %{
          "5.0.0" => ["Node.js polyfills removed", "New module federation"]
        }
      }
      
      package_changes = Map.get(breaking_changes, dep.name, %{})
      
      package_changes
      |> Enum.filter(fn {version, _} ->
        version > dep.version && version <= latest_version
      end)
      |> Enum.flat_map(fn {version, changes} ->
        Enum.map(changes, &%{version: version, change: &1})
      end)
    end
    
    defp get_changelog_highlights(package, current_version, latest_version) do
      # Simulated changelog highlights
      if current_version != latest_version do
        [
          "Performance improvements",
          "Bug fixes",
          "New features added"
        ]
      else
        []
      end
    end
    
    defp count_updates(recommendations) do
      %{
        total: length(recommendations),
        major: Enum.count(recommendations, &(&1.update_type == :major)),
        minor: Enum.count(recommendations, &(&1.update_type == :minor)),
        patch: Enum.count(recommendations, &(&1.update_type == :patch)),
        security: Enum.count(recommendations, & &1.security_update)
      }
    end
    
    defp identify_priority_updates(recommendations) do
      recommendations
      |> Enum.filter(fn rec ->
        rec.recommendation == :update_immediately ||
        rec.security_update ||
        rec.update_type == :patch
      end)
      |> Enum.sort_by(fn rec ->
        priority_score = case rec.recommendation do
          :update_immediately -> 0
          :update_recommended -> 1
          :update_after_testing -> 2
          _ -> 3
        end
        
        security_score = if rec.security_update, do: 0, else: 10
        
        priority_score + security_score
      end)
      |> Enum.take(10)
    end
    
    defp create_update_plan(recommendations) do
      phases = [
        %{
          phase: 1,
          name: "Security Updates",
          updates: Enum.filter(recommendations, & &1.security_update),
          estimated_duration: "1-2 days",
          risk_level: :low
        },
        %{
          phase: 2,
          name: "Patch Updates",
          updates: Enum.filter(recommendations, &(&1.update_type == :patch && !&1.security_update)),
          estimated_duration: "2-3 days",
          risk_level: :low
        },
        %{
          phase: 3,
          name: "Minor Updates",
          updates: Enum.filter(recommendations, &(&1.update_type == :minor)),
          estimated_duration: "1 week",
          risk_level: :medium
        },
        %{
          phase: 4,
          name: "Major Updates",
          updates: Enum.filter(recommendations, &(&1.update_type == :major)),
          estimated_duration: "2-4 weeks",
          risk_level: :high
        }
      ]
      
      Enum.filter(phases, &(length(&1.updates) > 0))
    end
    
    defp analyze_update_risks(recommendations) do
      major_updates = Enum.filter(recommendations, &(&1.update_type == :major))
      breaking_changes = recommendations
        |> Enum.flat_map(& &1.breaking_changes)
        |> length()
      
      %{
        high_risk_updates: length(major_updates),
        total_breaking_changes: breaking_changes,
        testing_required: determine_testing_scope(recommendations),
        rollback_plan_needed: length(major_updates) > 0,
        estimated_downtime: estimate_downtime(recommendations)
      }
    end
    
    defp determine_testing_scope(recommendations) do
      cond do
        Enum.any?(recommendations, &(&1.update_type == :major)) ->
          "Full regression testing required"
        
        Enum.any?(recommendations, &(&1.update_type == :minor)) ->
          "Integration testing recommended"
        
        true ->
          "Basic smoke testing"
      end
    end
    
    defp estimate_downtime(recommendations) do
      if Enum.any?(recommendations, &(&1.update_type == :major)) do
        "Potential downtime for major updates"
      else
        "No downtime expected"
      end
    end
    
    defp estimate_update_effort(recommendations) do
      effort_hours = recommendations
        |> Enum.map(fn rec ->
          base_effort = case rec.update_type do
            :major -> 8
            :minor -> 4
            :patch -> 1
            :none -> 0
          end
          
          # Adjust for breaking changes
          breaking_effort = length(rec.breaking_changes) * 2
          
          base_effort + breaking_effort
        end)
        |> Enum.sum()
      
      %{
        total_hours: effort_hours,
        developer_days: effort_hours / 8,
        timeline: generate_timeline(effort_hours),
        resources_needed: determine_resources(recommendations)
      }
    end
    
    defp generate_timeline(total_hours) do
      days = total_hours / 8
      
      cond do
        days <= 1 -> "1 day"
        days <= 5 -> "1 week"
        days <= 10 -> "2 weeks"
        days <= 20 -> "1 month"
        true -> "1-2 months"
      end
    end
    
    defp determine_resources(recommendations) do
      if Enum.any?(recommendations, &(&1.update_type == :major)) do
        ["Senior developer", "QA engineer", "DevOps support"]
      else
        ["Developer", "Basic QA"]
      end
    end
  end
  
  defmodule VisualizeDependencyGraphAction do
    @moduledoc """
    Creates visualization data for the dependency graph.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependency_tree: [type: :map, required: true, doc: "Analyzed dependency tree"],
        visualization_format: [type: :string, default: "hierarchical", doc: "Format: hierarchical, force, circular"],
        include_dev: [type: :boolean, default: false, doc: "Include dev dependencies"],
        max_depth: [type: :integer, default: 3, doc: "Maximum depth to visualize"]
      }
    end
    
    @impl true
    def run(params, _context) do
      graph_data = generate_graph_data(
        params.dependency_tree,
        params.visualization_format,
        params.include_dev,
        params.max_depth
      )
      
      {:ok, %{
        graph_data: graph_data,
        visualization_format: params.visualization_format,
        node_count: count_nodes(graph_data),
        edge_count: count_edges(graph_data),
        layout_hints: generate_layout_hints(graph_data, params.visualization_format),
        interaction_config: generate_interaction_config()
      }}
    end
    
    defp generate_graph_data(tree, format, include_dev, max_depth) do
      nodes = collect_nodes(tree, include_dev, max_depth)
      edges = collect_edges(tree, include_dev, max_depth)
      
      %{
        nodes: format_nodes(nodes, format),
        edges: format_edges(edges, format),
        metadata: %{
          root_id: tree.name,
          total_depth: calculate_actual_depth(tree),
          format: format
        }
      }
    end
    
    defp collect_nodes(node, include_dev, max_depth, current_depth \\ 0, acc \\ []) do
      if current_depth > max_depth do
        acc
      else
        node_data = %{
          id: generate_node_id(node, current_depth),
          name: node.name,
          version: node[:version] || "unknown",
          type: node[:type] || :production,
          depth: current_depth,
          size: calculate_node_size(node),
          metadata: extract_node_metadata(node)
        }
        
        acc = [node_data | acc]
        
        deps = node["dependencies"] || []
        filtered_deps = if include_dev do
          deps
        else
          Enum.filter(deps, &(&1.type != :development))
        end
        
        Enum.reduce(filtered_deps, acc, fn dep, acc ->
          collect_nodes(dep, include_dev, max_depth, current_depth + 1, acc)
        end)
      end
    end
    
    defp generate_node_id(node, depth) do
      "#{node.name}_#{depth}_#{:erlang.phash2({node.name, depth})}"
    end
    
    defp calculate_node_size(node) do
      # Size based on number of dependencies
      dep_count = length(node["dependencies"] || [])
      
      cond do
        dep_count == 0 -> 5
        dep_count <= 2 -> 10
        dep_count <= 5 -> 15
        dep_count <= 10 -> 20
        true -> 25
      end
    end
    
    defp extract_node_metadata(node) do
      %{
        has_vulnerabilities: node[:has_vulnerabilities] || false,
        license: node[:license] || "Unknown",
        update_available: node[:update_available] || false,
        dependency_count: length(node["dependencies"] || [])
      }
    end
    
    defp collect_edges(node, include_dev, max_depth, current_depth \\ 0, parent_id \\ nil, acc \\ []) do
      if current_depth > max_depth do
        acc
      else
        node_id = generate_node_id(node, current_depth)
        
        acc = if parent_id do
          edge = %{
            source: parent_id,
            target: node_id,
            type: node[:type] || :production,
            weight: calculate_edge_weight(node)
          }
          [edge | acc]
        else
          acc
        end
        
        deps = node["dependencies"] || []
        filtered_deps = if include_dev do
          deps
        else
          Enum.filter(deps, &(&1.type != :development))
        end
        
        Enum.reduce(filtered_deps, acc, fn dep, acc ->
          collect_edges(dep, include_dev, max_depth, current_depth + 1, node_id, acc)
        end)
      end
    end
    
    defp calculate_edge_weight(node) do
      # Weight based on dependency importance
      case node[:type] do
        :production -> 3
        :development -> 1
        _ -> 2
      end
    end
    
    defp format_nodes(nodes, format) do
      case format do
        "hierarchical" ->
          nodes |> Enum.map(&add_hierarchical_layout(&1))
        
        "force" ->
          nodes |> Enum.map(&add_force_layout(&1))
        
        "circular" ->
          nodes |> add_circular_layout()
        
        _ ->
          nodes
      end
    end
    
    defp add_hierarchical_layout(node) do
      Map.merge(node, %{
        layout: %{
          level: node.depth,
          expandable: node.metadata.dependency_count > 0
        }
      })
    end
    
    defp add_force_layout(node) do
      Map.merge(node, %{
        layout: %{
          charge: -30 * node.size,
          collision_radius: node.size * 1.5
        }
      })
    end
    
    defp add_circular_layout(nodes) do
      total = length(nodes)
      
      nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, index} ->
        angle = (index / total) * 2 * :math.pi()
        radius = 100 + (node.depth * 50)
        
        Map.merge(node, %{
          layout: %{
            x: radius * :math.cos(angle),
            y: radius * :math.sin(angle),
            angle: angle
          }
        })
      end)
    end
    
    defp format_edges(edges, format) do
      case format do
        "hierarchical" ->
          edges |> Enum.map(&add_hierarchical_edge_style(&1))
        
        "force" ->
          edges |> Enum.map(&add_force_edge_style(&1))
        
        _ ->
          edges
      end
    end
    
    defp add_hierarchical_edge_style(edge) do
      Map.merge(edge, %{
        style: %{
          curve: "basis",
          stroke_width: edge.weight,
          dash_array: if(edge.type == :development, do: "5,5", else: nil)
        }
      })
    end
    
    defp add_force_edge_style(edge) do
      Map.merge(edge, %{
        style: %{
          distance: 30 * edge.weight,
          strength: edge.weight / 3
        }
      })
    end
    
    defp calculate_actual_depth(node, current \\ 0) do
      if node["dependencies"] && length(node.dependencies) > 0 do
        child_depths = Enum.map(node.dependencies, fn dep ->
          calculate_actual_depth(dep, current + 1)
        end)
        Enum.max(child_depths)
      else
        current
      end
    end
    
    defp count_nodes(graph_data) do
      length(graph_data.nodes)
    end
    
    defp count_edges(graph_data) do
      length(graph_data.edges)
    end
    
    defp generate_layout_hints(graph_data, format) do
      node_count = length(graph_data.nodes)
      
      case format do
        "hierarchical" ->
          %{
            direction: "top-bottom",
            level_separation: 100,
            node_separation: 50,
            edge_minimization: true
          }
        
        "force" ->
          %{
            force_strength: -300,
            link_distance: 100,
            charge_distance: node_count * 10,
            iterations: 300
          }
        
        "circular" ->
          %{
            start_angle: 0,
            end_angle: 2 * :math.pi(),
            radius_increment: 50,
            sort_by: "dependency_count"
          }
        
        _ ->
          %{}
      end
    end
    
    defp generate_interaction_config do
      %{
        node_interactions: [
          %{event: "click", action: "show_details"},
          %{event: "hover", action: "highlight_connections"},
          %{event: "double_click", action: "expand_collapse"}
        ],
        edge_interactions: [
          %{event: "hover", action: "show_relationship"}
        ],
        canvas_interactions: [
          %{event: "zoom", enabled: true, min: 0.1, max: 5},
          %{event: "pan", enabled: true}
        ]
      }
    end
  end
  
  defmodule GenerateDependencyReportAction do
    @moduledoc """
    Generates comprehensive dependency analysis reports.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        analysis_results: [type: :map, required: true, doc: "Results from dependency analyses"],
        report_format: [type: :string, default: "detailed", doc: "Format: summary, detailed, executive"],
        include_visualizations: [type: :boolean, default: true, doc: "Include graph visualizations"],
        compliance_requirements: [type: {:list, :string}, doc: "Compliance standards to check"]
      }
    end
    
    @impl true
    def run(params, _context) do
      report = generate_dependency_report(
        params.analysis_results,
        params.report_format,
        params.include_visualizations,
        params.compliance_requirements
      )
      
      {:ok, report}
    end
    
    defp generate_dependency_report(results, format, include_viz, compliance_reqs) do
      base_report = build_base_report(results)
      
      formatted_report = case format do
        "executive" -> format_executive_report(base_report)
        "summary" -> format_summary_report(base_report)
        _ -> format_detailed_report(base_report)
      end
      
      report = if include_viz do
        add_visualizations(formatted_report, results)
      else
        formatted_report
      end
      
      if compliance_reqs && length(compliance_reqs) > 0 do
        add_compliance_section(report, results, compliance_reqs)
      else
        report
      end
    end
    
    defp build_base_report(results) do
      %{
        overview: build_dependency_overview(results),
        health_metrics: calculate_health_metrics(results),
        risk_summary: build_risk_summary(results),
        recommendations: consolidate_recommendations(results),
        action_items: generate_action_items(results)
      }
    end
    
    defp build_dependency_overview(results) do
      tree_stats = get_in(results, [:tree_analysis, :statistics]) || %{}
      
      %{
        title: "Dependency Analysis Report",
        timestamp: DateTime.utc_now(),
        summary: generate_overview_summary(results),
        key_findings: extract_key_findings(results),
        statistics: %{
          total_dependencies: tree_stats[:total_dependencies] || 0,
          unique_dependencies: tree_stats[:unique_dependencies] || 0,
          production_dependencies: tree_stats[:production_dependencies] || 0,
          development_dependencies: tree_stats[:development_dependencies] || 0
        }
      }
    end
    
    defp generate_overview_summary(results) do
      issues = []
      
      if results[:conflicts] && results.conflicts[:conflict_count] > 0 do
        issues = ["#{results.conflicts.conflict_count} version conflicts"] ++ issues
      end
      
      if results[:vulnerabilities] && results.vulnerabilities[:vulnerability_count] > 0 do
        issues = ["#{results.vulnerabilities.vulnerability_count} security vulnerabilities"] ++ issues
      end
      
      if results[:license_issues] && results.license_issues[:issue_count] > 0 do
        issues = ["#{results.license_issues.issue_count} license compatibility issues"] ++ issues
      end
      
      if length(issues) > 0 do
        "Analysis found: " <> Enum.join(issues, ", ")
      else
        "Dependency analysis completed successfully with no critical issues"
      end
    end
    
    defp extract_key_findings(results) do
      findings = []
      
      # Version conflicts
      if results[:conflicts] && results.conflicts[:severity_breakdown][:critical] > 0 do
        findings = ["Critical version conflicts require immediate attention"] ++ findings
      end
      
      # Security vulnerabilities
      if results[:vulnerabilities] && results.vulnerabilities[:severity_breakdown][:critical] > 0 do
        findings = ["Critical security vulnerabilities found"] ++ findings
      end
      
      # License issues
      if results[:license_issues] && results.license_issues[:compliance_status][:status] == :non_compliant do
        findings = ["License compliance issues detected"] ++ findings
      end
      
      # Update recommendations
      if results[:updates] && results.updates[:update_count]["security"] > 0 do
        findings = ["Security updates available for #{results.updates.update_count.security} packages"] ++ findings
      end
      
      Enum.take(findings, 5)
    end
    
    defp calculate_health_metrics(results) do
      scores = []
      
      # Version conflict score
      if results[:conflicts] do
        conflict_score = 100 - (results.conflicts.conflict_count * 10)
        scores = [max(0, conflict_score) | scores]
      end
      
      # Security score
      if results[:vulnerabilities] do
        vuln_score = 100 - (results.vulnerabilities.vulnerability_count * 15)
        scores = [max(0, vuln_score) | scores]
      end
      
      # License score
      if results[:license_issues] do
        license_score = if results.license_issues.compliance_status[:compliant], do: 100, else: 50
        scores = [license_score | scores]
      end
      
      # Update freshness score
      if results[:updates] do
        outdated = results.updates.update_count[:total] || 0
        freshness_score = 100 - (outdated * 5)
        scores = [max(0, freshness_score) | scores]
      end
      
      overall_score = if length(scores) > 0 do
        Enum.sum(scores) / length(scores)
      else
        100
      end
      
      %{
        overall_health: overall_score,
        health_grade: score_to_grade(overall_score),
        component_scores: %{
          version_consistency: Enum.at(scores, 0, 100),
          security: Enum.at(scores, 1, 100),
          license_compliance: Enum.at(scores, 2, 100),
          freshness: Enum.at(scores, 3, 100)
        }
      }
    end
    
    defp score_to_grade(score) do
      cond do
        score >= 90 -> "A"
        score >= 80 -> "B"
        score >= 70 -> "C"
        score >= 60 -> "D"
        true -> "F"
      end
    end
    
    defp build_risk_summary(results) do
      risks = []
      
      # Security risks
      if results[:vulnerabilities] do
        security_risk = results.vulnerabilities[:risk_score] || 0
        if security_risk > 50 do
          risks = [%{
            type: "security",
            level: :high,
            description: "High security risk from vulnerable dependencies"
          } | risks]
        end
      end
      
      # License risks
      if results[:license_issues] && results.license_issues[:risk_assessment] do
        license_risk = results.license_issues.risk_assessment[:risk_level]
        if license_risk in [:high, :critical] do
          risks = [%{
            type: :legal,
            level: license_risk,
            description: "License compatibility issues pose legal risk"
          } | risks]
        end
      end
      
      # Technical debt risk
      if results[:updates] && results.updates[:update_count][:major] > 5 do
        risks = [%{
          type: :technical_debt,
          level: :moderate,
          description: "Multiple major version updates indicate technical debt"
        } | risks]
      end
      
      %{
        risk_count: length(risks),
        highest_risk: get_highest_risk_level(risks),
        risk_areas: risks,
        mitigation_priority: prioritize_risk_mitigation(risks)
      }
    end
    
    defp get_highest_risk_level(risks) do
      if length(risks) == 0 do
        :low
      else
        risks
        |> Enum.map(& &1.level)
        |> Enum.max_by(&risk_level_to_number/1)
      end
    end
    
    defp risk_level_to_number(:critical), do: 4
    defp risk_level_to_number(:high), do: 3
    defp risk_level_to_number(:moderate), do: 2
    defp risk_level_to_number(:low), do: 1
    
    defp prioritize_risk_mitigation(risks) do
      risks
      |> Enum.sort_by(&risk_level_to_number(&1.level), :desc)
      |> Enum.map(& &1.type)
    end
    
    defp consolidate_recommendations(results) do
      all_recommendations = []
      
      # Conflict resolutions
      if results[:conflicts] && results.conflicts[:resolutions] do
        conflict_recs = Enum.map(results.conflicts.resolutions, fn res ->
          %{
            type: :version_resolution,
            package: res.package,
            action: "Update to #{res.suggested_version}",
            priority: :high
          }
        end)
        all_recommendations = all_recommendations ++ conflict_recs
      end
      
      # Security updates
      if results[:vulnerabilities] && results.vulnerabilities[:remediation_plan] do
        security_recs = Enum.map(results.vulnerabilities.remediation_plan, fn rem ->
          %{
            type: :security_update,
            package: rem.package,
            action: rem.update_command,
            priority: :critical
          }
        end)
        all_recommendations = all_recommendations ++ security_recs
      end
      
      # License recommendations
      if results[:license_issues] && results.license_issues[:recommendations] do
        license_recs = Enum.map(results.license_issues.recommendations, fn rec ->
          %{
            type: :license_compliance,
            action: rec,
            priority: :medium
          }
        end)
        all_recommendations = all_recommendations ++ license_recs
      end
      
      # Sort by priority and deduplicate
      all_recommendations
      |> Enum.uniq_by(&{&1[:package], &1.type})
      |> Enum.sort_by(&priority_to_number(&1.priority))
      |> Enum.take(20)
    end
    
    defp priority_to_number(:critical), do: 0
    defp priority_to_number(:high), do: 1
    defp priority_to_number(:medium), do: 2
    defp priority_to_number(:low), do: 3
    
    defp generate_action_items(results) do
      items = []
      
      # Critical security updates
      if results[:vulnerabilities] && results.vulnerabilities[:severity_breakdown][:critical] > 0 do
        items = [%{
          action: "Apply critical security updates immediately",
          timeline: "Within 24 hours",
          owner: "Security team",
          priority: :critical
        } | items]
      end
      
      # Version conflict resolution
      if results[:conflicts] && results.conflicts[:conflict_count] > 5 do
        items = [%{
          action: "Resolve version conflicts to ensure stability",
          timeline: "Within 1 week",
          owner: "Development team",
          priority: :high
        } | items]
      end
      
      # License compliance
      if results[:license_issues] && !results.license_issues[:compliance_status][:compliant] do
        items = [%{
          action: "Address license compliance issues",
          timeline: "Within 2 weeks",
          owner: "Legal team",
          priority: :high
        } | items]
      end
      
      # General updates
      if results[:updates] && results.updates[:update_count][:total] > 20 do
        items = [%{
          action: "Plan and execute dependency update cycle",
          timeline: "Within 1 month",
          owner: "Development team",
          priority: :medium
        } | items]
      end
      
      items
    end
    
    defp format_executive_report(base_report) do
      %{
        title: "Executive Dependency Summary",
        date: base_report.overview.timestamp,
        health_score: base_report.health_metrics.overall_health,
        health_grade: base_report.health_metrics.health_grade,
        executive_summary: %{
          key_findings: base_report.overview.key_findings,
          risk_level: base_report.risk_summary.highest_risk,
          immediate_actions: extract_immediate_actions(base_report.action_items),
          investment_required: estimate_remediation_investment(base_report)
        }
      }
    end
    
    defp extract_immediate_actions(action_items) do
      action_items
      |> Enum.filter(&(&1.priority in [:critical, :high]))
      |> Enum.take(3)
      |> Enum.map(& &1.action)
    end
    
    defp estimate_remediation_investment(base_report) do
      action_count = length(base_report.action_items)
      
      cond do
        action_count == 0 -> "Minimal - routine maintenance only"
        action_count <= 3 -> "Low - 1-2 developer days"
        action_count <= 10 -> "Moderate - 1-2 developer weeks"
        true -> "Significant - dedicated sprint required"
      end
    end
    
    defp format_summary_report(base_report) do
      %{
        title: "Dependency Analysis Summary",
        timestamp: base_report.overview.timestamp,
        overview: base_report.overview.summary,
        metrics: %{
          health_score: base_report.health_metrics.overall_health,
          total_dependencies: base_report.overview.statistics.total_dependencies,
          issues_found: count_total_issues(base_report),
          recommendations: length(base_report.recommendations)
        },
        top_issues: extract_top_issues(base_report),
        priority_actions: Enum.take(base_report.action_items, 5)
      }
    end
    
    defp count_total_issues(base_report) do
      base_report.overview.key_findings |> length()
    end
    
    defp extract_top_issues(base_report) do
      base_report.risk_summary.risk_areas
      |> Enum.take(5)
      |> Enum.map(& &1.description)
    end
    
    defp format_detailed_report(base_report) do
      %{
        title: "Comprehensive Dependency Analysis",
        timestamp: base_report.overview.timestamp,
        table_of_contents: [
          "Executive Summary",
          "Dependency Overview",
          "Health Metrics",
          "Risk Analysis",
          "Recommendations",
          "Action Plan",
          "Appendices"
        ],
        sections: %{
          executive_summary: base_report.overview,
          health_metrics: format_health_metrics(base_report.health_metrics),
          risk_analysis: format_risk_analysis(base_report.risk_summary),
          recommendations: format_recommendations(base_report.recommendations),
          action_plan: format_action_plan(base_report.action_items)
        },
        appendices: %{
          methodology: "Dependency analysis methodology",
          glossary: build_dependency_glossary(),
          tools: list_analysis_tools()
        }
      }
    end
    
    defp format_health_metrics(metrics) do
      %{
        overall_score: metrics.overall_health,
        grade: metrics.health_grade,
        breakdown: metrics.component_scores,
        interpretation: interpret_health_score(metrics.overall_health)
      }
    end
    
    defp interpret_health_score(score) do
      cond do
        score >= 90 -> "Excellent - Dependencies are well-maintained and secure"
        score >= 75 -> "Good - Minor issues that should be addressed"
        score >= 60 -> "Fair - Several issues requiring attention"
        score >= 45 -> "Poor - Significant issues affecting project health"
        true -> "Critical - Immediate action required"
      end
    end
    
    defp format_risk_analysis(risk_summary) do
      %{
        risk_level: risk_summary.highest_risk,
        risk_areas: risk_summary.risk_areas,
        mitigation_priorities: risk_summary.mitigation_priority,
        risk_matrix: build_risk_matrix(risk_summary.risk_areas)
      }
    end
    
    defp build_risk_matrix(risk_areas) do
      %{
        high_impact_high_probability: Enum.filter(risk_areas, &(&1.level in [:critical, :high])),
        high_impact_low_probability: [],
        low_impact_high_probability: Enum.filter(risk_areas, &(&1.level == :moderate)),
        low_impact_low_probability: Enum.filter(risk_areas, &(&1.level == :low))
      }
    end
    
    defp format_recommendations(recommendations) do
      recommendations
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, recs} ->
        %{
          category: type,
          recommendations: Enum.map(recs, &format_recommendation/1),
          estimated_effort: estimate_category_effort(recs)
        }
      end)
    end
    
    defp format_recommendation(rec) do
      %{
        action: rec.action,
        priority: rec.priority,
        package: rec[:package],
        rationale: get_recommendation_rationale(rec.type)
      }
    end
    
    defp get_recommendation_rationale(type) do
      case type do
        :version_resolution -> "Resolves version conflicts and ensures compatibility"
        :security_update -> "Addresses known security vulnerabilities"
        :license_compliance -> "Ensures legal compliance with license terms"
        _ -> "Improves overall dependency health"
      end
    end
    
    defp estimate_category_effort(recommendations) do
      hours = length(recommendations) * 2
      "Approximately #{hours} hours"
    end
    
    defp format_action_plan(action_items) do
      action_items
      |> Enum.group_by(& &1.timeline)
      |> Enum.map(fn {timeline, items} ->
        %{
          timeline: timeline,
          actions: Enum.map(items, &format_action_item/1),
          resources_required: identify_required_resources(items)
        }
      end)
    end
    
    defp format_action_item(item) do
      %{
        action: item.action,
        owner: item.owner,
        priority: item.priority,
        success_criteria: define_success_criteria(item)
      }
    end
    
    defp define_success_criteria(item) do
      case item.priority do
        :critical -> "Issue resolved with zero remaining vulnerabilities"
        :high -> "Issue addressed and verified through testing"
        _ -> "Implementation complete and documented"
      end
    end
    
    defp identify_required_resources(items) do
      owners = items |> Enum.map(& &1.owner) |> Enum.uniq()
      
      %{
        teams: owners,
        estimated_hours: length(items) * 4,
        tools: ["Dependency scanner", "Version control", "CI/CD pipeline"]
      }
    end
    
    defp add_visualizations(report, results) do
      if results[:graph_data] do
        Map.put(report, :visualizations, %{
          dependency_graph: results.graph_data.graph_data,
          interaction_config: results.graph_data[:interaction_config],
          layout_hints: results.graph_data[:layout_hints]
        })
      else
        report
      end
    end
    
    defp add_compliance_section(report, results, compliance_reqs) do
      compliance_status = check_compliance_requirements(results, compliance_reqs)
      
      Map.put(report, :compliance, %{
        requirements_checked: compliance_reqs,
        overall_compliance: compliance_status.compliant,
        compliance_gaps: compliance_status.gaps,
        remediation_steps: compliance_status.remediation_steps
      })
    end
    
    defp check_compliance_requirements(results, requirements) do
      gaps = []
      
      # Check each requirement
      gaps = if "SOC2" in requirements && has_security_issues?(results) do
        [%{
          requirement: "SOC2",
          gap: "Security vulnerabilities present",
          severity: :high
        } | gaps]
      else
        gaps
      end
      
      gaps = if "GPL-Free" in requirements && has_gpl_licenses?(results) do
        [%{
          requirement: "GPL-Free",
          gap: "GPL licensed dependencies found",
          severity: :critical
        } | gaps]
      else
        gaps
      end
      
      %{
        compliant: length(gaps) == 0,
        gaps: gaps,
        remediation_steps: generate_compliance_remediation(gaps)
      }
    end
    
    defp has_security_issues?(results) do
      results[:vulnerabilities] && results.vulnerabilities[:vulnerability_count] > 0
    end
    
    defp has_gpl_licenses?(results) do
      if results[:license_issues] && results.license_issues[:license_summary] do
        licenses = results.license_issues.license_summary[:unique_licenses] || []
        Enum.any?(licenses, &String.contains?(&1, "GPL"))
      else
        false
      end
    end
    
    defp generate_compliance_remediation(gaps) do
      Enum.map(gaps, fn gap ->
        case gap.requirement do
          "SOC2" -> "Remediate all security vulnerabilities"
          "GPL-Free" -> "Replace or remove GPL licensed dependencies"
          _ -> "Address compliance gap for #{gap.requirement}"
        end
      end)
    end
    
    defp build_dependency_glossary do
      %{
        "Dependency" => "External package or library required by the project",
        "Transitive Dependency" => "Dependency of a dependency",
        "Version Conflict" => "Multiple versions of the same package required",
        "Vulnerability" => "Known security issue in a dependency",
        "License Compatibility" => "Legal compatibility between licenses",
        "Lock File" => "File specifying exact versions of all dependencies"
      }
    end
    
    defp list_analysis_tools do
      [
        "npm audit - Node.js security scanning",
        "pip-audit - Python vulnerability scanning",
        "bundle audit - Ruby dependency auditing",
        "OWASP Dependency Check - Multi-language scanning"
      ]
    end
  end
  
  @impl BaseToolAgent
  def initial_state do
    %{
      dependency_cache: %{},
      analysis_history: [],
      known_vulnerabilities: %{},
      license_database: %{},
      update_tracking: %{},
      graph_layouts: %{},
      policy_rules: default_policy_rules(),
      max_history: 50
    }
  end
  
  @impl BaseToolAgent
  def handle_tool_signal(%State{} = state, signal) do
    signal_type = signal["type"]
    data = signal["data"] || %{}
    
    case signal_type do
      "analyze_tree" ->
        cmd_async(state, AnalyzeDependencyTreeAction, data)
        
      "detect_conflicts" ->
        cmd_async(state, DetectVersionConflictsAction, data)
        
      "check_vulnerabilities" ->
        cmd_async(state, CheckSecurityVulnerabilitiesAction, data)
        
      "analyze_licenses" ->
        cmd_async(state, AnalyzeLicenseCompatibilityAction, data)
        
      "generate_updates" ->
        cmd_async(state, GenerateUpdateRecommendationsAction, data)
        
      "visualize_graph" ->
        cmd_async(state, VisualizeDependencyGraphAction, data)
        
      "generate_report" ->
        cmd_async(state, GenerateDependencyReportAction, data)
        
      _ ->
        super(state, signal)
    end
  end
  
  @impl BaseToolAgent
  def handle_action_result(state, action, result, metadata) do
    case action do
      AnalyzeDependencyTreeAction ->
        handle_tree_analysis_result(state, result, metadata)
        
      CheckSecurityVulnerabilitiesAction ->
        handle_vulnerability_check_result(state, result, metadata)
        
      AnalyzeLicenseCompatibilityAction ->
        handle_license_analysis_result(state, result, metadata)
        
      _ ->
        super(state, action, result, metadata)
    end
  end
  
  defp handle_tree_analysis_result(state, {:ok, result}, metadata) do
    # Cache dependency tree
    cache_key = generate_tree_cache_key(metadata)
    updated_cache = Map.put(state.state.dependency_cache, cache_key, %{
      tree: result.dependency_tree,
      analysis: result.tree_analysis,
      timestamp: DateTime.utc_now()
    })
    
    # Add to history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :tree_analysis,
      statistics: result.statistics,
      complexity_score: result.tree_analysis.complexity_score,
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.analysis_history]
      |> Enum.take(state.state.max_history)
    
    updated_state = %{state.state |
      dependency_cache: updated_cache,
      analysis_history: updated_history
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_tree_analysis_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_vulnerability_check_result(state, {:ok, result}, metadata) do
    # Update known vulnerabilities
    new_vulns = result.vulnerabilities
      |> Enum.map(fn vuln -> {vuln.package, vuln} end)
      |> Enum.into(%{})
    
    updated_vulns = Map.merge(state.state.known_vulnerabilities, new_vulns)
    
    # Add to history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :vulnerability_scan,
      vulnerability_count: result.vulnerability_count,
      risk_score: result.risk_score,
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.analysis_history]
      |> Enum.take(state.state.max_history)
    
    # Check if we need to emit alerts
    if result.severity_breakdown[:critical] > 0 do
      emit_security_alert(state, result)
    end
    
    updated_state = %{state.state |
      known_vulnerabilities: updated_vulns,
      analysis_history: updated_history
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_vulnerability_check_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_license_analysis_result(state, {:ok, result}, metadata) do
    # Update license database
    if result[:license_summary] do
      license_info = result.license_summary[:license_breakdown] || %{}
      updated_licenses = Map.merge(state.state.license_database, license_info)
      
      updated_state = put_in(state.state.license_database, updated_licenses)
      {:ok, %{state | state: updated_state}}
    else
      {:ok, state}
    end
  end
  
  defp handle_license_analysis_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  @impl BaseToolAgent
  def process_result(result, _metadata) do
    Map.put(result, :analyzed_at, DateTime.utc_now())
  end
  
  @impl BaseToolAgent
  def additional_actions do
    [
      AnalyzeDependencyTreeAction,
      DetectVersionConflictsAction,
      CheckSecurityVulnerabilitiesAction,
      AnalyzeLicenseCompatibilityAction,
      GenerateUpdateRecommendationsAction,
      VisualizeDependencyGraphAction,
      GenerateDependencyReportAction
    ]
  end
  
  # Helper functions
  defp generate_tree_cache_key(metadata) do
    manifest_hash = :crypto.hash(:md5, inspect(metadata[:manifest_files] || []))
      |> Base.encode16()
    
    "tree_#{manifest_hash}"
  end
  
  defp emit_security_alert(state, vulnerability_result) do
    signal = %{
      "type" => "dependency.security_alert",
      "source" => "dependency_analyzer",
      "data" => %{
        "severity" => "critical",
        "vulnerability_count" => vulnerability_result.vulnerability_count,
        "affected_packages" => vulnerability_result.affected_dependencies,
        "risk_score" => vulnerability_result.risk_score
      },
      "time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Jido.Signal.emit(signal, state)
  end
  
  defp default_policy_rules do
    %{
      blacklisted_licenses: ["GPL-3.0", "AGPL-3.0"],
      max_vulnerability_severity: :high,
      required_update_frequency_days: 30,
      max_major_version_lag: 2
    }
  end
end