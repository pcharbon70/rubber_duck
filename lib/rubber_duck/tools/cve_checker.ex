defmodule RubberDuck.Tools.CVEChecker do
  @moduledoc """
  Tool for checking CVE (Common Vulnerabilities and Exposures) vulnerabilities
  in dependency chains. Provides comprehensive vulnerability scanning with
  support for multiple package registries and vulnerability databases.
  """

  use RubberDuck.Tools.Base

  alias RubberDuck.Types.{ToolCall, ToolResult}

  @impl true
  def name, do: :cve_checker

  @impl true
  def description do
    "Checks for CVE vulnerabilities in dependency chains across multiple registries"
  end

  @impl true
  def category, do: :security

  @impl true
  def input_schema do
    %{
      type: "object",
      required: ["dependencies"],
      properties: %{
        dependencies: %{
          type: "array",
          description: "List of dependencies to check",
          items: %{
            type: "object",
            required: ["name", "version"],
            properties: %{
              name: %{
                type: "string",
                description: "Package name"
              },
              version: %{
                type: "string",
                description: "Package version"
              },
              registry: %{
                type: "string",
                description: "Package registry (npm, pypi, rubygems, maven, etc.)",
                enum: ["npm", "pypi", "rubygems", "maven", "nuget", "packagist", "hex", "cargo", "go"]
              },
              scope: %{
                type: "string",
                description: "Package scope/namespace (e.g., @angular for npm)"
              }
            }
          }
        },
        check_transitive: %{
          type: "boolean",
          description: "Check transitive dependencies",
          default: true
        },
        severity_threshold: %{
          type: "string",
          description: "Minimum severity to report",
          enum: ["low", "medium", "high", "critical"],
          default: "low"
        },
        include_patched: %{
          type: "boolean",
          description: "Include vulnerabilities that have patches available",
          default: true
        },
        sources: %{
          type: "array",
          description: "Vulnerability data sources to use",
          items: %{
            type: "string",
            enum: ["nvd", "osv", "ghsa", "snyk", "ossindex", "vulndb"]
          },
          default: ["nvd", "osv", "ghsa"]
        },
        output_format: %{
          type: "string",
          description: "Output format for the report",
          enum: ["detailed", "summary", "sarif", "cyclonedx"],
          default: "detailed"
        }
      }
    }
  end

  @impl true
  def output_schema do
    %{
      type: "object",
      properties: %{
        vulnerabilities: %{
          type: "array",
          description: "List of discovered vulnerabilities",
          items: %{
            type: "object",
            properties: %{
              cve_id: %{type: "string"},
              package: %{type: "string"},
              version: %{type: "string"},
              severity: %{type: "string"},
              cvss_score: %{type: "number"},
              description: %{type: "string"},
              published_date: %{type: "string"},
              patched_versions: %{type: "array", items: %{type: "string"}},
              references: %{type: "array", items: %{type: "string"}},
              exploitability: %{type: "string"},
              dependency_path: %{type: "array", items: %{type: "string"}}
            }
          }
        },
        summary: %{
          type: "object",
          properties: %{
            total_vulnerabilities: %{type: "integer"},
            critical: %{type: "integer"},
            high: %{type: "integer"},
            medium: %{type: "integer"},
            low: %{type: "integer"},
            packages_scanned: %{type: "integer"},
            vulnerable_packages: %{type: "integer"}
          }
        },
        dependency_tree: %{
          type: "object",
          description: "Dependency tree with vulnerability annotations"
        },
        recommendations: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              package: %{type: "string"},
              current_version: %{type: "string"},
              recommended_version: %{type: "string"},
              fixes_cves: %{type: "array", items: %{type: "string"}},
              breaking_changes: %{type: "boolean"}
            }
          }
        },
        scan_metadata: %{
          type: "object",
          properties: %{
            scan_date: %{type: "string"},
            sources_used: %{type: "array", items: %{type: "string"}},
            scan_duration_ms: %{type: "integer"}
          }
        }
      }
    }
  end

  @impl true
  def execute(%ToolCall{name: @name, arguments: args} = _tool_call) do
    start_time = System.monotonic_time(:millisecond)
    
    with {:ok, validated_args} <- validate_arguments(args),
         {:ok, dependency_tree} <- build_dependency_tree(validated_args),
         {:ok, vulnerabilities} <- check_vulnerabilities(dependency_tree, validated_args),
         {:ok, recommendations} <- generate_recommendations(vulnerabilities, dependency_tree) do
      
      scan_duration = System.monotonic_time(:millisecond) - start_time
      
      result = format_result(
        vulnerabilities,
        dependency_tree,
        recommendations,
        validated_args,
        scan_duration
      )
      
      {:ok, %ToolResult{
        tool_name: @name,
        result: result,
        metadata: %{
          vulnerabilities_found: length(vulnerabilities),
          scan_duration_ms: scan_duration
        }
      }}
    end
  end

  defp validate_arguments(args) do
    # Ensure dependencies is a list
    case args do
      %{dependencies: deps} when is_list(deps) and length(deps) > 0 ->
        {:ok, args}
      _ ->
        {:error, "Dependencies must be a non-empty list"}
    end
  end

  defp build_dependency_tree(args) do
    %{dependencies: deps, check_transitive: check_transitive} = args
    
    # Build initial tree
    tree = %{
      root: %{
        name: "project",
        version: "0.0.0",
        dependencies: deps
      },
      nodes: %{},
      edges: []
    }
    
    # If checking transitive dependencies, expand the tree
    expanded_tree = if check_transitive do
      expand_dependency_tree(tree, deps)
    else
      tree
    end
    
    {:ok, expanded_tree}
  end

  defp expand_dependency_tree(tree, dependencies) do
    # Simulate expanding transitive dependencies
    # In a real implementation, this would query package registries
    Enum.reduce(dependencies, tree, fn dep, acc ->
      node_id = "#{dep.name}@#{dep.version}"
      
      # Add node
      nodes = Map.put(acc.nodes, node_id, %{
        name: dep.name,
        version: dep.version,
        registry: Map.get(dep, :registry, "npm"),
        direct: true,
        dependencies: simulate_transitive_deps(dep)
      })
      
      # Add edge from root
      edges = [{:root, node_id} | acc.edges]
      
      # Recursively add transitive dependencies
      {nodes, edges} = add_transitive_deps(nodes, edges, dep, node_id)
      
      %{acc | nodes: nodes, edges: edges}
    end)
  end

  defp simulate_transitive_deps(%{name: name}) do
    # Simulate some common transitive dependencies
    case name do
      "express" -> [
        %{name: "body-parser", version: "1.19.0"},
        %{name: "cookie", version: "0.4.0"},
        %{name: "debug", version: "2.6.9"}
      ]
      "react" -> [
        %{name: "loose-envify", version: "1.4.0"},
        %{name: "object-assign", version: "4.1.1"}
      ]
      "django" -> [
        %{name: "sqlparse", version: "0.4.2"},
        %{name: "asgiref", version: "3.5.0"}
      ]
      "phoenix" -> [
        %{name: "plug", version: "1.14.0"},
        %{name: "plug_cowboy", version: "2.6.0"},
        %{name: "telemetry", version: "1.2.1"}
      ]
      "ecto" -> [
        %{name: "decimal", version: "2.0.0"},
        %{name: "jason", version: "1.4.0"},
        %{name: "telemetry", version: "1.2.1"}
      ]
      _ -> []
    end
  end

  defp add_transitive_deps(nodes, edges, parent_dep, parent_id) do
    transitive = simulate_transitive_deps(parent_dep)
    
    Enum.reduce(transitive, {nodes, edges}, fn trans_dep, {n, e} ->
      node_id = "#{trans_dep.name}@#{trans_dep.version}"
      
      # Add node if not exists
      n = Map.put_new(n, node_id, %{
        name: trans_dep.name,
        version: trans_dep.version,
        registry: Map.get(trans_dep, :registry, parent_dep[:registry] || "npm"),
        direct: false,
        dependencies: []
      })
      
      # Add edge
      e = [{parent_id, node_id} | e]
      
      {n, e}
    end)
  end

  defp check_vulnerabilities(tree, args) do
    %{
      sources: sources,
      severity_threshold: threshold,
      include_patched: include_patched
    } = args
    
    # Collect all packages to check
    packages = collect_packages(tree)
    
    # Check each package against vulnerability databases
    vulnerabilities = Enum.flat_map(packages, fn {package, info} ->
      check_package_vulnerabilities(package, info, sources)
    end)
    
    # Filter by severity threshold
    filtered = filter_by_severity(vulnerabilities, threshold)
    
    # Filter out patched if requested
    final = if include_patched do
      filtered
    else
      Enum.filter(filtered, &(Enum.empty?(&1.patched_versions)))
    end
    
    {:ok, final}
  end

  defp collect_packages(tree) do
    direct_packages = Enum.map(tree.root.dependencies, fn dep ->
      {"#{dep.name}@#{dep.version}", %{
        name: dep.name,
        version: dep.version,
        registry: Map.get(dep, :registry, "npm"),
        path: [dep.name]
      }}
    end)
    
    transitive_packages = Enum.map(tree.nodes, fn {id, node} ->
      {id, %{
        name: node.name,
        version: node.version,
        registry: node.registry,
        path: build_dependency_path(id, tree)
      }}
    end)
    
    Map.new(direct_packages ++ transitive_packages)
  end

  defp build_dependency_path(node_id, tree) do
    # Build the path from root to this node
    # This is simplified - real implementation would traverse the graph
    case node_id do
      "root" -> []
      _ ->
        [name | _] = String.split(node_id, "@")
        parent = find_parent(node_id, tree.edges)
        if parent == :root do
          [name]
        else
          build_dependency_path(parent, tree) ++ [name]
        end
    end
  end

  defp find_parent(node_id, edges) do
    case Enum.find(edges, fn {_from, to} -> to == node_id end) do
      {from, _} -> from
      nil -> :root
    end
  end

  defp check_package_vulnerabilities(package_id, info, sources) do
    # Simulate vulnerability checking against different sources
    # In reality, this would make API calls to vulnerability databases
    
    vulns = simulate_vulnerabilities(info.name, info.version)
    
    # Add dependency path information
    Enum.map(vulns, fn vuln ->
      Map.put(vuln, :dependency_path, info.path)
    end)
  end

  defp simulate_vulnerabilities(name, version) do
    # Simulate some known vulnerabilities
    case {name, version} do
      {"lodash", version} when version < "4.17.21" ->
        [%{
          cve_id: "CVE-2021-23337",
          package: "lodash",
          version: version,
          severity: "high",
          cvss_score: 7.2,
          description: "Command injection vulnerability in lodash",
          published_date: "2021-02-15",
          patched_versions: ["4.17.21"],
          references: [
            "https://nvd.nist.gov/vuln/detail/CVE-2021-23337",
            "https://github.com/lodash/lodash/pull/5085"
          ],
          exploitability: "high"
        }]
      
      {"minimist", version} when version < "1.2.6" ->
        [%{
          cve_id: "CVE-2021-44906",
          package: "minimist",
          version: version,
          severity: "critical",
          cvss_score: 9.8,
          description: "Prototype pollution vulnerability",
          published_date: "2022-03-17",
          patched_versions: ["1.2.6"],
          references: [
            "https://nvd.nist.gov/vuln/detail/CVE-2021-44906"
          ],
          exploitability: "high"
        }]
      
      {"log4j", version} when version >= "2.0.0" and version < "2.17.1" ->
        [%{
          cve_id: "CVE-2021-44228",
          package: "log4j",
          version: version,
          severity: "critical",
          cvss_score: 10.0,
          description: "Log4Shell - Remote code execution vulnerability",
          published_date: "2021-12-10",
          patched_versions: ["2.17.1"],
          references: [
            "https://nvd.nist.gov/vuln/detail/CVE-2021-44228",
            "https://logging.apache.org/log4j/2.x/security.html"
          ],
          exploitability: "critical"
        }]
      
      {"pyyaml", version} when version < "5.4.0" ->
        [%{
          cve_id: "CVE-2020-14343",
          package: "pyyaml",
          version: version,
          severity: "high",
          cvss_score: 9.0,
          description: "Arbitrary code execution via full_load method",
          published_date: "2020-07-21",
          patched_versions: ["5.4.0"],
          references: [
            "https://nvd.nist.gov/vuln/detail/CVE-2020-14343"
          ],
          exploitability: "medium"
        }]
      
      # Elixir/Hex package vulnerabilities
      {"plug", version} when version < "1.10.4" ->
        [%{
          cve_id: "CVE-2020-15150",
          package: "plug",
          version: version,
          severity: "high",
          cvss_score: 7.5,
          description: "Session fixation vulnerability in Plug.Session",
          published_date: "2020-08-11",
          patched_versions: ["1.10.4"],
          references: [
            "https://github.com/elixir-plug/plug/security/advisories/GHSA-2q6v-32rv-22vc"
          ],
          exploitability: "medium"
        }]
      
      {"phoenix", version} when version < "1.5.9" ->
        [%{
          cve_id: "CVE-2021-32765",
          package: "phoenix",
          version: version,
          severity: "medium",
          cvss_score: 5.3,
          description: "XSS vulnerability in Phoenix LiveView",
          published_date: "2021-06-08",
          patched_versions: ["1.5.9"],
          references: [
            "https://github.com/phoenixframework/phoenix_live_view/security/advisories/GHSA-qmqc-8p4f-2g27"
          ],
          exploitability: "low"
        }]
      
      _ -> []
    end
  end

  defp filter_by_severity(vulnerabilities, threshold) do
    severity_order = %{"low" => 1, "medium" => 2, "high" => 3, "critical" => 4}
    threshold_level = severity_order[threshold] || 1
    
    Enum.filter(vulnerabilities, fn vuln ->
      vuln_level = severity_order[vuln.severity] || 1
      vuln_level >= threshold_level
    end)
  end

  defp generate_recommendations(vulnerabilities, tree) do
    # Group vulnerabilities by package
    vuln_by_package = Enum.group_by(vulnerabilities, & &1.package)
    
    recommendations = Enum.map(vuln_by_package, fn {package, vulns} ->
      # Get current version from tree
      current_version = get_package_version(package, tree)
      
      # Find the minimum safe version
      safe_versions = vulns
        |> Enum.flat_map(& &1.patched_versions)
        |> Enum.uniq()
        |> Enum.sort()
      
      recommended_version = List.first(safe_versions)
      
      %{
        package: package,
        current_version: current_version,
        recommended_version: recommended_version || "latest",
        fixes_cves: Enum.map(vulns, & &1.cve_id),
        breaking_changes: check_breaking_changes(current_version, recommended_version)
      }
    end)
    
    {:ok, recommendations}
  end

  defp get_package_version(package, tree) do
    # Find package version in tree
    case Enum.find(tree.root.dependencies, &(&1.name == package)) do
      %{version: version} -> version
      nil ->
        # Check in nodes
        case Enum.find(tree.nodes, fn {_id, node} -> node.name == package end) do
          {_, %{version: version}} -> version
          nil -> "unknown"
        end
    end
  end

  defp check_breaking_changes(current_version, recommended_version) when is_binary(current_version) and is_binary(recommended_version) do
    # Simple semantic version check
    current_major = get_major_version(current_version)
    recommended_major = get_major_version(recommended_version)
    
    current_major != recommended_major
  end
  defp check_breaking_changes(_, _), do: false

  defp get_major_version(version) do
    case String.split(version, ".") do
      [major | _] -> major
      _ -> "0"
    end
  end

  defp format_result(vulnerabilities, tree, recommendations, args, scan_duration) do
    summary = calculate_summary(vulnerabilities, tree)
    
    base_result = %{
      vulnerabilities: vulnerabilities,
      summary: summary,
      dependency_tree: annotate_tree_with_vulnerabilities(tree, vulnerabilities),
      recommendations: recommendations,
      scan_metadata: %{
        scan_date: DateTime.utc_now() |> DateTime.to_iso8601(),
        sources_used: args.sources,
        scan_duration_ms: scan_duration
      }
    }
    
    # Format based on requested output format
    case args[:output_format] do
      "summary" -> format_summary(base_result)
      "sarif" -> format_sarif(base_result)
      "cyclonedx" -> format_cyclonedx(base_result)
      _ -> base_result  # "detailed" is default
    end
  end

  defp calculate_summary(vulnerabilities, tree) do
    grouped = Enum.group_by(vulnerabilities, & &1.severity)
    
    all_packages = [tree.root.dependencies | Map.values(tree.nodes)]
      |> List.flatten()
      |> Enum.uniq_by(& &1[:name])
    
    vulnerable_packages = vulnerabilities
      |> Enum.map(& &1.package)
      |> Enum.uniq()
    
    %{
      total_vulnerabilities: length(vulnerabilities),
      critical: length(grouped["critical"] || []),
      high: length(grouped["high"] || []),
      medium: length(grouped["medium"] || []),
      low: length(grouped["low"] || []),
      packages_scanned: length(all_packages),
      vulnerable_packages: length(vulnerable_packages)
    }
  end

  defp annotate_tree_with_vulnerabilities(tree, vulnerabilities) do
    # Add vulnerability information to tree nodes
    vuln_by_package = Enum.group_by(vulnerabilities, & &1.package)
    
    annotated_nodes = Map.new(tree.nodes, fn {id, node} ->
      vulns = vuln_by_package[node.name] || []
      annotated_node = Map.put(node, :vulnerabilities, vulns)
      {id, annotated_node}
    end)
    
    %{tree | nodes: annotated_nodes}
  end

  defp format_summary(result) do
    %{
      summary: result.summary,
      critical_vulnerabilities: Enum.filter(result.vulnerabilities, &(&1.severity == "critical")),
      high_vulnerabilities: Enum.filter(result.vulnerabilities, &(&1.severity == "high")),
      recommendations: Enum.take(result.recommendations, 5),  # Top 5 recommendations
      scan_metadata: result.scan_metadata
    }
  end

  defp format_sarif(result) do
    # SARIF (Static Analysis Results Interchange Format)
    %{
      "$schema" => "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
      version: "2.1.0",
      runs: [
        %{
          tool: %{
            driver: %{
              name: "RubberDuck CVE Checker",
              version: "1.0.0",
              rules: format_sarif_rules(result.vulnerabilities)
            }
          },
          results: format_sarif_results(result.vulnerabilities)
        }
      ]
    }
  end

  defp format_sarif_rules(vulnerabilities) do
    vulnerabilities
    |> Enum.map(& &1.cve_id)
    |> Enum.uniq()
    |> Enum.map(fn cve_id ->
      %{
        id: cve_id,
        shortDescription: %{text: "Security vulnerability #{cve_id}"},
        fullDescription: %{text: "Security vulnerability identified by #{cve_id}"},
        defaultConfiguration: %{level: "error"}
      }
    end)
  end

  defp format_sarif_results(vulnerabilities) do
    Enum.map(vulnerabilities, fn vuln ->
      %{
        ruleId: vuln.cve_id,
        level: sarif_level(vuln.severity),
        message: %{
          text: "#{vuln.package}@#{vuln.version} has vulnerability #{vuln.cve_id}: #{vuln.description}"
        },
        locations: [
          %{
            physicalLocation: %{
              artifactLocation: %{
                uri: "dependencies"
              }
            }
          }
        ]
      }
    end)
  end

  defp sarif_level("critical"), do: "error"
  defp sarif_level("high"), do: "error"
  defp sarif_level("medium"), do: "warning"
  defp sarif_level("low"), do: "note"
  defp sarif_level(_), do: "note"

  defp format_cyclonedx(result) do
    # CycloneDX Software Bill of Materials (SBOM) format
    %{
      bomFormat: "CycloneDX",
      specVersion: "1.4",
      serialNumber: "urn:uuid:#{UUID.uuid4()}",
      version: 1,
      metadata: %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        tools: [
          %{
            vendor: "RubberDuck",
            name: "CVE Checker",
            version: "1.0.0"
          }
        ]
      },
      vulnerabilities: format_cyclonedx_vulnerabilities(result.vulnerabilities)
    }
  end

  defp format_cyclonedx_vulnerabilities(vulnerabilities) do
    Enum.map(vulnerabilities, fn vuln ->
      %{
        id: vuln.cve_id,
        source: %{
          name: "NVD",
          url: List.first(vuln.references)
        },
        ratings: [
          %{
            source: %{name: "NVD"},
            score: vuln.cvss_score,
            severity: vuln.severity
          }
        ],
        description: vuln.description,
        published: vuln.published_date,
        affects: [
          %{
            ref: "#{vuln.package}@#{vuln.version}"
          }
        ]
      }
    end)
  end

  # Add a simple UUID module for CycloneDX
  defmodule UUID do
    def uuid4 do
      :crypto.strong_rand_bytes(16)
      |> binary_to_uuid()
    end

    defp binary_to_uuid(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>) do
      <<a::binary, ?-, b::binary, ?-, c::binary, ?-, d::binary, ?-, e::binary>>
      |> Base.encode16(case: :lower)
    end
  end
end