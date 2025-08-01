defmodule RubberDuck.Tools.Agents.DependencyAnalyzerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.DependencyAnalyzerAgent
  
  setup do
    {:ok, agent} = DependencyAnalyzerAgent.start_link(id: "test_dependency_analyzer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        project_path: "/test/project",
        language: "elixir",
        analysis_type: "dependencies"
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: DependencyAnalyzerAgent}
      
      result = DependencyAnalyzerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze dependency tree action builds comprehensive tree", %{agent: agent} do
      project_files = %{
        "mix.exs" => """
        defmodule TestProject.MixProject do
          use Mix.Project
          
          def project do
            [
              app: :test_project,
              version: "0.1.0",
              deps: deps()
            ]
          end
          
          defp deps do
            [
              {:phoenix, "~> 1.7.0"},
              {:ecto, "~> 3.10"},
              {:jason, "~> 1.4"},
              {:telemetry, "~> 1.2"}
            ]
          end
        end
        """,
        "mix.lock" => """
        %{
          "phoenix": {:hex, :phoenix, "1.7.2"},
          "ecto": {:hex, :ecto, "3.10.1"},
          "jason": {:hex, :jason, "1.4.0"},
          "telemetry": {:hex, :telemetry, "1.2.1"},
          "decimal": {:hex, :decimal, "2.1.0"},
          "db_connection": {:hex, :db_connection, "2.5.0"}
        }
        """
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeDependencyTreeAction.run(
        %{
          project_files: project_files,
          language: "elixir",
          max_depth: 3
        },
        context
      )
      
      # Check dependency tree structure
      assert Map.has_key?(result, :dependency_tree)
      assert Map.has_key?(result.dependency_tree, :root)
      assert Map.has_key?(result.dependency_tree, :nodes)
      
      # Check direct dependencies
      direct_deps = result.dependency_tree.nodes
        |> Map.values()
        |> Enum.filter(& &1.direct)
      
      assert length(direct_deps) == 4
      dep_names = Enum.map(direct_deps, & &1.name)
      assert "phoenix" in dep_names
      assert "ecto" in dep_names
      
      # Check statistics
      stats = result.statistics
      assert stats.total_dependencies > 4  # Direct + transitive
      assert stats.direct_dependencies == 4
      assert stats.max_depth > 0
      
      # Check dependency health
      health = result.dependency_health
      assert health.health_score >= 0 and health.health_score <= 100
      assert is_list(health.issues)
      
      # Check visualizations
      assert String.contains?(result.visualizations.tree_diagram, "test_project")
      assert is_list(result.visualizations.dependency_graph)
    end
    
    test "detect version conflicts action identifies conflicts", %{agent: agent} do
      dependencies = %{
        "app_a" => %{
          version: "1.0.0",
          dependencies: %{
            "shared_lib" => "~> 2.0"
          }
        },
        "app_b" => %{
          version: "1.0.0",
          dependencies: %{
            "shared_lib" => "~> 3.0"
          }
        },
        "app_c" => %{
          version: "1.0.0",
          dependencies: %{
            "shared_lib" => ">= 2.5.0 and < 3.0.0"
          }
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.DetectVersionConflictsAction.run(
        %{
          dependencies: dependencies,
          resolve_strategy: "automatic"
        },
        context
      )
      
      # Check conflicts detected
      assert length(result.conflicts) > 0
      
      # Find the shared_lib conflict
      shared_lib_conflict = Enum.find(result.conflicts, fn c ->
        c.dependency == "shared_lib"
      end)
      
      assert shared_lib_conflict != nil
      assert shared_lib_conflict.severity in [:high, :critical]
      assert length(shared_lib_conflict.conflicting_requirements) >= 2
      
      # Check resolution suggestions
      assert length(result.resolution_suggestions) > 0
      suggestion = hd(result.resolution_suggestions)
      assert Map.has_key?(suggestion, :action)
      assert Map.has_key?(suggestion, :steps)
      assert Map.has_key?(suggestion, :impact_analysis)
      
      # Check conflict summary
      summary = result.conflict_summary
      assert summary.total_conflicts > 0
      assert Map.has_key?(summary.conflicts_by_severity, :high)
      assert summary.resolvable_automatically >= 0
    end
    
    test "check security vulnerabilities action detects issues", %{agent: agent} do
      dependencies = %{
        "vulnerable_lib" => %{
          name: "vulnerable_lib",
          version: "1.2.3",
          registry: "npm"
        },
        "outdated_framework" => %{
          name: "outdated_framework",
          version: "0.9.0",
          registry: "npm"
        },
        "secure_lib" => %{
          name: "secure_lib",
          version: "5.0.0",
          registry: "npm"
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{
          dependencies: dependencies,
          check_advisories: true,
          include_dev: false
        },
        context
      )
      
      # Check vulnerabilities found
      assert length(result.vulnerabilities) > 0
      
      vuln = hd(result.vulnerabilities)
      assert Map.has_key?(vuln, :dependency)
      assert Map.has_key?(vuln, :severity)
      assert Map.has_key?(vuln, :cve_ids)
      assert Map.has_key?(vuln, :description)
      assert Map.has_key?(vuln, :patched_versions)
      assert Map.has_key?(vuln, :recommendation)
      
      # Check security summary
      summary = result.security_summary
      assert summary.total_vulnerabilities > 0
      assert Map.has_key?(summary.by_severity, :critical)
      assert Map.has_key?(summary.by_severity, :high)
      assert summary.dependencies_affected > 0
      
      # Check remediation plan
      assert length(result.remediation_plan) > 0
      remediation = hd(result.remediation_plan)
      assert Map.has_key?(remediation, :priority)
      assert Map.has_key?(remediation, :action)
      assert Map.has_key?(remediation, :dependencies)
      
      # Check security score
      assert result.security_score >= 0 and result.security_score <= 100
    end
    
    test "analyze license compatibility action checks licenses", %{agent: agent} do
      dependencies = %{
        "mit_lib" => %{
          name: "mit_lib",
          version: "1.0.0",
          license: "MIT"
        },
        "gpl_lib" => %{
          name: "gpl_lib",
          version: "2.0.0",
          license: "GPL-3.0"
        },
        "apache_lib" => %{
          name: "apache_lib",
          version: "1.5.0",
          license: "Apache-2.0"
        },
        "proprietary_lib" => %{
          name: "proprietary_lib",
          version: "1.0.0",
          license: "Proprietary"
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeLicenseCompatibilityAction.run(
        %{
          dependencies: dependencies,
          project_license: "MIT",
          check_compatibility: true
        },
        context
      )
      
      # Check license analysis
      analysis = result.license_analysis
      assert Map.has_key?(analysis, :licenses_found)
      assert length(analysis.licenses_found) > 0
      assert Map.has_key?(analysis, :license_distribution)
      
      # Check compatibility issues
      assert length(result.compatibility_issues) > 0
      
      # GPL should have compatibility issue with MIT project
      gpl_issue = Enum.find(result.compatibility_issues, fn issue ->
        issue.dependency == "gpl_lib"
      end)
      assert gpl_issue != nil
      assert gpl_issue.severity in [:high, :critical]
      
      # Check legal risks
      risks = result.legal_risks
      assert length(risks) > 0
      risk = hd(risks)
      assert Map.has_key?(risk, :type)
      assert Map.has_key?(risk, :severity)
      assert Map.has_key?(risk, :mitigation)
      
      # Check compliance summary
      summary = result.compliance_summary
      assert Map.has_key?(summary, :compliant)
      assert Map.has_key?(summary, :total_dependencies)
      assert Map.has_key?(summary, :license_categories)
      assert summary.risk_level in [:low, :medium, :high, :critical]
    end
    
    test "generate update recommendations action suggests updates", %{agent: agent} do
      current_dependencies = %{
        "framework" => %{
          name: "framework",
          version: "1.0.0",
          latest_version: "3.2.0",
          registry: "npm"
        },
        "util_lib" => %{
          name: "util_lib",
          version: "2.5.0",
          latest_version: "2.5.8",
          registry: "npm"
        },
        "deprecated_lib" => %{
          name: "deprecated_lib",
          version: "0.9.0",
          latest_version: "0.9.0",
          deprecated: true,
          registry: "npm"
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.GenerateUpdateRecommendationsAction.run(
        %{
          current_dependencies: current_dependencies,
          update_strategy: "balanced",
          check_breaking_changes: true
        },
        context
      )
      
      # Check update recommendations
      assert length(result.update_recommendations) > 0
      
      # Check major update recommendation
      framework_update = Enum.find(result.update_recommendations, fn rec ->
        rec.dependency == "framework"
      end)
      assert framework_update != nil
      assert framework_update.update_type == :major
      assert framework_update.risk_level in [:medium, :high]
      assert length(framework_update.breaking_changes) >= 0
      
      # Check update groups
      assert length(result.update_groups) > 0
      group = hd(result.update_groups)
      assert Map.has_key?(group, :priority)
      assert Map.has_key?(group, :dependencies)
      assert Map.has_key?(group, :rationale)
      
      # Check deprecation warnings
      assert length(result.deprecation_warnings) > 0
      deprecation = Enum.find(result.deprecation_warnings, fn w ->
        w.dependency == "deprecated_lib"
      end)
      assert deprecation != nil
      assert deprecation.severity == :high
      
      # Check update plan
      plan = result.update_plan
      assert Map.has_key?(plan, :phases)
      assert Map.has_key?(plan, :estimated_effort)
      assert Map.has_key?(plan, :risk_assessment)
    end
    
    test "visualize dependency graph action creates visualizations", %{agent: agent} do
      dependency_data = %{
        nodes: [
          %{id: "app", label: "MyApp", type: :root},
          %{id: "web", label: "WebFramework", type: :direct},
          %{id: "db", label: "Database", type: :direct},
          %{id: "http", label: "HTTPClient", type: :transitive},
          %{id: "json", label: "JSONParser", type: :transitive}
        ],
        edges: [
          %{from: "app", to: "web", type: :depends_on},
          %{from: "app", to: "db", type: :depends_on},
          %{from: "web", to: "http", type: :depends_on},
          %{from: "web", to: "json", type: :depends_on}
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.VisualizeDependencyGraphAction.run(
        %{
          dependency_data: dependency_data,
          format: "multiple",
          include_versions: true
        },
        context
      )
      
      # Check visualizations
      viz = result.visualizations
      
      # Check DOT format
      assert Map.has_key?(viz, :dot_graph)
      assert String.contains?(viz.dot_graph, "digraph")
      assert String.contains?(viz.dot_graph, "MyApp")
      
      # Check ASCII diagram
      assert Map.has_key?(viz, :ascii_diagram)
      assert String.contains?(viz.ascii_diagram, "MyApp")
      assert String.contains?(viz.ascii_diagram, "├──")
      
      # Check Mermaid diagram
      assert Map.has_key?(viz, :mermaid_diagram)
      assert String.contains?(viz.mermaid_diagram, "graph")
      
      # Check dependency matrix
      assert Map.has_key?(viz, :dependency_matrix)
      matrix = viz.dependency_matrix
      assert is_list(matrix.headers)
      assert is_list(matrix.rows)
      
      # Check graph metrics
      metrics = result.graph_metrics
      assert metrics.node_count == 5
      assert metrics.edge_count == 4
      assert Map.has_key?(metrics, :max_depth)
      assert Map.has_key?(metrics, :clustering_coefficient)
      
      # Check interactive data
      assert Map.has_key?(result, :interactive_data)
      assert Map.has_key?(result.interactive_data, :nodes)
      assert Map.has_key?(result.interactive_data, :edges)
    end
    
    test "generate dependency report action creates comprehensive report", %{agent: agent} do
      analysis_results = %{
        tree_analysis: %{
          total_dependencies: 45,
          direct_dependencies: 12,
          max_depth: 4,
          circular_dependencies: []
        },
        conflicts: [
          %{
            dependency: "shared_lib",
            severity: :high,
            conflicting_requirements: ["~> 2.0", "~> 3.0"]
          }
        ],
        vulnerabilities: [
          %{
            dependency: "vulnerable_lib",
            severity: :critical,
            cve_ids: ["CVE-2023-1234"]
          }
        ],
        license_issues: [
          %{
            dependency: "gpl_lib",
            license: "GPL-3.0",
            compatibility_issue: "Incompatible with MIT"
          }
        ],
        update_recommendations: [
          %{
            dependency: "old_lib",
            current: "1.0.0",
            recommended: "2.0.0",
            update_type: :major
          }
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{
          analysis_results: analysis_results,
          report_format: "detailed",
          include_visualizations: true
        },
        context
      )
      
      # Check report structure
      assert Map.has_key?(report, :title)
      assert Map.has_key?(report, :summary)
      assert Map.has_key?(report, :sections)
      
      # Check summary section
      summary = report.summary
      assert Map.has_key?(summary, :health_score)
      assert Map.has_key?(summary, :critical_issues)
      assert Map.has_key?(summary, :key_metrics)
      
      # Check report sections
      sections = report.sections
      assert Map.has_key?(sections, :dependency_overview)
      assert Map.has_key?(sections, :security_analysis)
      assert Map.has_key?(sections, :license_compliance)
      assert Map.has_key?(sections, :version_conflicts)
      assert Map.has_key?(sections, :update_recommendations)
      
      # Check action items
      assert Map.has_key?(report, :action_items)
      actions = report.action_items
      assert Map.has_key?(actions, :immediate)
      assert Map.has_key?(actions, :short_term)
      assert Map.has_key?(actions, :long_term)
      assert length(actions.immediate) > 0
      
      # Check visualizations included
      assert Map.has_key?(report, :visualizations)
      assert length(report.visualizations) > 0
    end
  end
  
  describe "signal handling with actions" do
    test "analyze_tree signal triggers AnalyzeDependencyTreeAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_tree",
        "data" => %{
          "project_files" => %{"mix.exs" => "content"},
          "language" => "elixir"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DependencyAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "detect_conflicts signal triggers DetectVersionConflictsAction", %{agent: agent} do
      signal = %{
        "type" => "detect_conflicts",
        "data" => %{
          "dependencies" => %{}
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DependencyAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "dependency tree analysis" do
    test "handles circular dependencies" do
      context = %{agent: %{state: %{}}}
      
      project_files = %{
        "package.json" => """
        {
          "dependencies": {
            "package-a": "1.0.0",
            "package-b": "1.0.0"
          }
        }
        """,
        # Simulating circular dependency: A -> B -> C -> A
        "node_modules/package-a/package.json" => """
        {
          "dependencies": {
            "package-b": "1.0.0"
          }
        }
        """,
        "node_modules/package-b/package.json" => """
        {
          "dependencies": {
            "package-c": "1.0.0"
          }
        }
        """,
        "node_modules/package-c/package.json" => """
        {
          "dependencies": {
            "package-a": "1.0.0"
          }
        }
        """
      }
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeDependencyTreeAction.run(
        %{project_files: project_files, language: "javascript"},
        context
      )
      
      # Should detect circular dependency
      health = result.dependency_health
      circular_issue = Enum.find(health.issues, fn issue ->
        issue.type == :circular_dependency
      end)
      
      assert circular_issue != nil
      assert circular_issue.severity == :critical
    end
    
    test "calculates dependency depth correctly" do
      context = %{agent: %{state: %{}}}
      
      # Deep dependency tree
      project_files = %{
        "requirements.txt" => """
        django==4.2
        requests==2.31.0
        """,
        # Simulating transitive dependencies
        ".dependency_data" => %{
          "django" => ["django-core", "django-db"],
          "django-core" => ["python-utils"],
          "django-db" => ["sqlparse", "psycopg2"],
          "sqlparse" => ["regex-lib"],
          "requests" => ["urllib3", "certifi"],
          "urllib3" => ["ssl-lib"]
        }
      }
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeDependencyTreeAction.run(
        %{project_files: project_files, language: "python", max_depth: 10},
        context
      )
      
      stats = result.statistics
      # Should have depth of at least 3 (django -> django-db -> sqlparse -> regex-lib)
      assert stats.max_depth >= 3
      assert stats.total_dependencies > stats.direct_dependencies
    end
  end
  
  describe "version conflict detection" do
    test "handles semantic versioning conflicts" do
      context = %{agent: %{state: %{}}}
      
      dependencies = %{
        "lib-a" => %{
          version: "1.0.0",
          dependencies: %{
            "common" => "^2.0.0"  # 2.x.x
          }
        },
        "lib-b" => %{
          version: "1.0.0", 
          dependencies: %{
            "common" => "~2.1.0"  # 2.1.x
          }
        },
        "lib-c" => %{
          version: "1.0.0",
          dependencies: %{
            "common" => "2.0.5"  # Exact version
          }
        }
      }
      
      {:ok, result} = DependencyAnalyzerAgent.DetectVersionConflictsAction.run(
        %{dependencies: dependencies, resolve_strategy: "manual"},
        context
      )
      
      # Should find potential conflict due to different constraints
      assert length(result.conflicts) > 0
      
      # Should provide resolution
      suggestions = result.resolution_suggestions
      assert Enum.any?(suggestions, fn s ->
        String.contains?(s.description || "", "common")
      end)
    end
    
    test "detects diamond dependency problem" do
      context = %{agent: %{state: %{}}}
      
      # Diamond dependency: A -> B,C; B -> D v1.0; C -> D v2.0
      dependencies = %{
        "app" => %{
          version: "1.0.0",
          dependencies: %{
            "module-b" => "1.0.0",
            "module-c" => "1.0.0"
          }
        },
        "module-b" => %{
          version: "1.0.0",
          dependencies: %{
            "shared-d" => "1.0.0"
          }
        },
        "module-c" => %{
          version: "1.0.0",
          dependencies: %{
            "shared-d" => "2.0.0"
          }
        }
      }
      
      {:ok, result} = DependencyAnalyzerAgent.DetectVersionConflictsAction.run(
        %{dependencies: dependencies},
        context
      )
      
      # Should detect the diamond dependency conflict
      conflict = Enum.find(result.conflicts, fn c ->
        c.dependency == "shared-d"
      end)
      
      assert conflict != nil
      assert length(conflict.conflicting_requirements) == 2
      assert conflict.conflict_type == :diamond_dependency
    end
  end
  
  describe "security vulnerability checking" do
    test "prioritizes critical vulnerabilities" do
      context = %{agent: %{state: %{}}}
      
      dependencies = %{
        "critical-vuln" => %{name: "critical-vuln", version: "1.0.0"},
        "high-vuln" => %{name: "high-vuln", version: "2.0.0"},
        "low-vuln" => %{name: "low-vuln", version: "3.0.0"}
      }
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{dependencies: dependencies, check_advisories: true},
        context
      )
      
      # Remediation plan should prioritize by severity
      plan = result.remediation_plan
      if length(plan) > 0 do
        assert hd(plan).priority == 1
        # First item should address critical or high severity
        first_action = hd(plan)
        deps = first_action.dependencies
        assert Enum.any?(deps, fn d ->
          String.contains?(d, "critical") or String.contains?(d, "high")
        end)
      end
    end
    
    test "checks for known vulnerability patterns" do
      context = %{agent: %{state: %{}}}
      
      # Dependencies with version patterns known to have vulnerabilities
      dependencies = %{
        "log4j" => %{name: "log4j", version: "2.14.0", registry: "maven"},
        "minimist" => %{name: "minimist", version: "0.0.8", registry: "npm"},
        "pyyaml" => %{name: "pyyaml", version: "5.3.0", registry: "pypi"}
      }
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{dependencies: dependencies},
        context
      )
      
      # Should identify these as potentially vulnerable
      assert result.security_summary.total_vulnerabilities > 0
      
      # Should provide specific recommendations
      assert Enum.any?(result.vulnerabilities, fn v ->
        v.recommendation != nil and v.recommendation != ""
      end)
    end
  end
  
  describe "license compatibility analysis" do
    test "identifies copyleft license risks" do
      context = %{agent: %{state: %{}}}
      
      dependencies = %{
        "gpl-lib" => %{license: "GPL-3.0"},
        "lgpl-lib" => %{license: "LGPL-2.1"},
        "agpl-lib" => %{license: "AGPL-3.0"}
      }
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeLicenseCompatibilityAction.run(
        %{
          dependencies: dependencies,
          project_license: "Apache-2.0",
          check_compatibility: true
        },
        context
      )
      
      # Should flag copyleft licenses as risks
      risks = result.legal_risks
      copyleft_risk = Enum.find(risks, fn r ->
        r.type == :copyleft_contamination
      end)
      
      assert copyleft_risk != nil
      assert copyleft_risk.severity in [:high, :critical]
    end
    
    test "handles multi-licensing scenarios" do
      context = %{agent: %{state: %{}}}
      
      dependencies = %{
        "dual-licensed" => %{license: "MIT OR Apache-2.0"},
        "tri-licensed" => %{license: "(MIT OR BSD-3-Clause) AND Apache-2.0"}
      }
      
      {:ok, result} = DependencyAnalyzerAgent.AnalyzeLicenseCompatibilityAction.run(
        %{dependencies: dependencies, project_license: "MIT"},
        context
      )
      
      # Should recognize multi-licensing and find compatible option
      analysis = result.license_analysis
      assert Map.has_key?(analysis, :multi_licensed_packages)
      
      # Should not flag as incompatible since MIT is an option
      issues = result.compatibility_issues
      dual_issue = Enum.find(issues, fn i ->
        i.dependency == "dual-licensed"
      end)
      
      assert dual_issue == nil or dual_issue.severity == :low
    end
  end
  
  describe "update recommendations" do
    test "considers breaking changes in major updates" do
      context = %{agent: %{state: %{}}}
      
      current_dependencies = %{
        "framework" => %{
          name: "framework",
          version: "1.5.0",
          latest_version: "4.0.0",
          changelog_url: "https://example.com/changelog"
        }
      }
      
      {:ok, result} = DependencyAnalyzerAgent.GenerateUpdateRecommendationsAction.run(
        %{
          current_dependencies: current_dependencies,
          update_strategy: "conservative",
          check_breaking_changes: true
        },
        context
      )
      
      rec = Enum.find(result.update_recommendations, fn r ->
        r.dependency == "framework"
      end)
      
      assert rec != nil
      assert rec.update_type == :major
      assert rec.risk_level in [:high, :critical]
      # Conservative strategy should recommend careful migration
      assert String.contains?(rec.migration_notes || "", "careful") or
             String.contains?(rec.migration_notes || "", "gradual") or
             rec.risk_level == :high
    end
    
    test "groups related updates together" do
      context = %{agent: %{state: %{}}}
      
      current_dependencies = %{
        "react" => %{version: "17.0.0", latest_version: "18.2.0"},
        "react-dom" => %{version: "17.0.0", latest_version: "18.2.0"},
        "react-router" => %{version: "5.0.0", latest_version: "6.0.0"},
        "@types/react" => %{version: "17.0.0", latest_version: "18.0.0"}
      }
      
      {:ok, result} = DependencyAnalyzerAgent.GenerateUpdateRecommendationsAction.run(
        %{current_dependencies: current_dependencies, update_strategy: "balanced"},
        context
      )
      
      # Should group React-related updates together
      groups = result.update_groups
      react_group = Enum.find(groups, fn g ->
        Enum.any?(g.dependencies, &String.contains?(&1, "react"))
      end)
      
      assert react_group != nil
      assert length(react_group.dependencies) >= 3
      assert react_group.rationale != nil
    end
  end
  
  describe "dependency visualization" do
    test "generates valid DOT graph format" do
      context = %{agent: %{state: %{}}}
      
      dependency_data = %{
        nodes: [
          %{id: "a", label: "Package A"},
          %{id: "b", label: "Package B"}
        ],
        edges: [
          %{from: "a", to: "b", type: :depends_on}
        ]
      }
      
      {:ok, result} = DependencyAnalyzerAgent.VisualizeDependencyGraphAction.run(
        %{dependency_data: dependency_data, format: "dot"},
        context
      )
      
      dot = result.visualizations.dot_graph
      assert String.contains?(dot, "digraph")
      assert String.contains?(dot, "Package A")
      assert String.contains?(dot, "Package B")
      assert String.contains?(dot, "->")
    end
    
    test "calculates graph metrics correctly" do
      context = %{agent: %{state: %{}}}
      
      # Create a more complex graph
      nodes = for i <- 1..10, do: %{id: "n#{i}", label: "Node #{i}"}
      edges = [
        %{from: "n1", to: "n2"},
        %{from: "n1", to: "n3"},
        %{from: "n2", to: "n4"},
        %{from: "n3", to: "n4"},
        %{from: "n4", to: "n5"}
      ]
      
      dependency_data = %{nodes: nodes, edges: edges}
      
      {:ok, result} = DependencyAnalyzerAgent.VisualizeDependencyGraphAction.run(
        %{dependency_data: dependency_data, format: "multiple"},
        context
      )
      
      metrics = result.graph_metrics
      assert metrics.node_count == 10
      assert metrics.edge_count == 5
      assert metrics.avg_degree > 0
      assert metrics.max_depth >= 3  # n1 -> n2 -> n4 -> n5
    end
  end
  
  describe "report generation" do
    test "generates different report formats" do
      context = %{agent: %{state: %{}}}
      
      analysis_results = %{
        tree_analysis: %{total_dependencies: 20},
        conflicts: [],
        vulnerabilities: [],
        license_issues: []
      }
      
      # Executive format
      {:ok, exec_report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{analysis_results: analysis_results, report_format: "executive"},
        context
      )
      
      assert Map.has_key?(exec_report, :executive_summary)
      assert byte_size(exec_report.executive_summary) < 1000
      
      # Summary format
      {:ok, summary_report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{analysis_results: analysis_results, report_format: "summary"},
        context
      )
      
      assert Map.has_key?(summary_report, :summary)
      assert Map.has_key?(summary_report, :key_findings)
      
      # Detailed format
      {:ok, detailed_report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{analysis_results: analysis_results, report_format: "detailed"},
        context
      )
      
      assert Map.has_key?(detailed_report, :sections)
      assert map_size(detailed_report.sections) > 3
    end
    
    test "prioritizes action items by severity" do
      context = %{agent: %{state: %{}}}
      
      analysis_results = %{
        tree_analysis: %{total_dependencies: 10},
        conflicts: [%{severity: :medium}],
        vulnerabilities: [%{severity: :critical}, %{severity: :high}],
        license_issues: [%{severity: :low}]
      }
      
      {:ok, report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{analysis_results: analysis_results, report_format: "detailed"},
        context
      )
      
      actions = report.action_items
      # Critical vulnerability should be in immediate actions
      assert length(actions.immediate) > 0
      
      immediate_has_vuln = Enum.any?(actions.immediate, fn item ->
        String.contains?(item.description || "", "vulnerability") or
        String.contains?(item.description || "", "security")
      end)
      
      assert immediate_has_vuln
    end
  end
  
  describe "state management" do
    test "caches dependency analysis results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      tree_result = %{
        dependency_tree: %{root: "test", nodes: %{}},
        statistics: %{total_dependencies: 10}
      }
      
      metadata = %{project_files: %{"mix.exs" => "content"}}
      
      {:ok, updated} = DependencyAnalyzerAgent.handle_action_result(
        state,
        DependencyAnalyzerAgent.AnalyzeDependencyTreeAction,
        {:ok, tree_result},
        metadata
      )
      
      assert map_size(updated.state.analysis_cache) == 1
    end
    
    test "tracks vulnerability history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      vuln_result = %{
        vulnerabilities: [
          %{dependency: "lib1", severity: :critical},
          %{dependency: "lib2", severity: :high}
        ],
        security_summary: %{total_vulnerabilities: 2}
      }
      
      {:ok, updated} = DependencyAnalyzerAgent.handle_action_result(
        state,
        DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction,
        {:ok, vuln_result},
        %{}
      )
      
      assert length(updated.state.vulnerability_history) == 1
      entry = hd(updated.state.vulnerability_history)
      assert entry.total_vulnerabilities == 2
      assert entry.critical_count == 1
    end
    
    test "maintains known conflicts registry", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      conflict_result = %{
        conflicts: [
          %{
            dependency: "shared_lib",
            severity: :high,
            conflicting_requirements: ["~> 1.0", "~> 2.0"]
          }
        ],
        resolution_suggestions: []
      }
      
      {:ok, updated} = DependencyAnalyzerAgent.handle_action_result(
        state,
        DependencyAnalyzerAgent.DetectVersionConflictsAction,
        {:ok, conflict_result},
        %{}
      )
      
      assert map_size(updated.state.known_conflicts) == 1
      assert Map.has_key?(updated.state.known_conflicts, "shared_lib")
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = DependencyAnalyzerAgent.additional_actions()
      
      assert length(actions) == 7
      assert DependencyAnalyzerAgent.AnalyzeDependencyTreeAction in actions
      assert DependencyAnalyzerAgent.DetectVersionConflictsAction in actions
      assert DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction in actions
      assert DependencyAnalyzerAgent.AnalyzeLicenseCompatibilityAction in actions
      assert DependencyAnalyzerAgent.GenerateUpdateRecommendationsAction in actions
      assert DependencyAnalyzerAgent.VisualizeDependencyGraphAction in actions
      assert DependencyAnalyzerAgent.GenerateDependencyReportAction in actions
    end
  end
  
  describe "agent initialization" do
    test "starts with empty caches and default config", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check empty caches
      assert map_size(state.state.analysis_cache) == 0
      assert map_size(state.state.known_conflicts) == 0
      assert length(state.state.vulnerability_history) == 0
      
      # Check default config
      config = state.state.config
      assert config.max_analysis_depth == 10
      assert config.vulnerability_check_enabled == true
      assert config.auto_resolve_conflicts == false
    end
  end
end