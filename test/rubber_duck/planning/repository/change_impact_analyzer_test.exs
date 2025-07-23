defmodule RubberDuck.Planning.Repository.ChangeImpactAnalyzerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Repository.{ChangeImpactAnalyzer, RepositoryAnalyzer, DependencyGraph}

  describe "analyze_impact/3" do
    test "analyzes impact of file changes" do
      repo_analysis = create_mock_repo_analysis()
      changed_files = ["lib/module_a.ex"]

      assert {:ok, impact} = ChangeImpactAnalyzer.analyze_impact(repo_analysis, changed_files)

      assert impact.changed_files == changed_files
      assert is_list(impact.directly_affected)
      assert is_list(impact.transitively_affected)
      assert is_list(impact.test_files_needed)
      assert is_map(impact.risk_assessment)
      assert is_list(impact.change_propagation)
      assert is_list(impact.compilation_order)
      assert is_list(impact.parallel_groups)
      assert is_map(impact.estimated_effort)
    end

    test "calculates risk assessment correctly" do
      repo_analysis = create_complex_repo_analysis()
      # High complexity file
      changed_files = ["lib/core_module.ex"]

      assert {:ok, impact} = ChangeImpactAnalyzer.analyze_impact(repo_analysis, changed_files)

      risk = impact.risk_assessment
      assert risk.overall_risk in [:low, :medium, :high, :critical]
      assert is_list(risk.factors)
      assert is_float(risk.confidence)
      assert risk.confidence >= 0.0 and risk.confidence <= 1.0
      assert is_list(risk.recommendations)
    end

    test "identifies test coverage gaps" do
      repo_analysis = create_repo_with_poor_test_coverage()
      changed_files = ["lib/untested_module.ex"]

      assert {:ok, impact} = ChangeImpactAnalyzer.analyze_impact(repo_analysis, changed_files)

      # Should identify test coverage as a risk factor
      coverage_risk =
        Enum.find(
          impact.risk_assessment.factors,
          &(&1.type == :test_coverage_gaps)
        )

      assert coverage_risk
      assert coverage_risk.severity in [:medium, :high]
    end

    test "estimates effort based on complexity" do
      repo_analysis = create_complex_repo_analysis()
      changed_files = ["lib/core_module.ex", "lib/simple_module.ex"]

      assert {:ok, impact} = ChangeImpactAnalyzer.analyze_impact(repo_analysis, changed_files)

      effort = impact.estimated_effort
      assert effort.total_files > 0
      assert effort.complexity_score > 0.0
      assert effort.estimated_hours > 0.0
      assert effort.confidence >= 0.0 and effort.confidence <= 1.0
    end
  end

  describe "analyze_breaking_change/3" do
    test "analyzes breaking change impact" do
      repo_analysis = create_mock_repo_analysis()

      assert {:ok, impact} =
               ChangeImpactAnalyzer.analyze_breaking_change(
                 repo_analysis,
                 "ModuleA",
                 ["function1", "function2"]
               )

      # Should have breaking change risk factor
      breaking_risk =
        Enum.find(
          impact.risk_assessment.factors,
          &(&1.type == :breaking_changes)
        )

      assert breaking_risk
      assert breaking_risk.severity == :high
    end
  end

  describe "suggest_mitigations/1" do
    test "suggests mitigations for high complexity files" do
      impact_with_complexity_risk = %{
        risk_assessment: %{
          factors: [
            %{
              type: :high_complexity_files,
              severity: :medium,
              description: "Changes involve high complexity files",
              affected_files: ["lib/complex.ex"],
              mitigation: "Increase testing and code review rigor"
            }
          ]
        }
      }

      mitigations = ChangeImpactAnalyzer.suggest_mitigations(impact_with_complexity_risk)

      assert length(mitigations) > 0

      extensive_testing = Enum.find(mitigations, &(&1.type == :extensive_testing))
      assert extensive_testing
      assert extensive_testing.effectiveness > 0.0
    end

    test "suggests mitigations for breaking changes" do
      impact_with_breaking_changes = %{
        risk_assessment: %{
          factors: [
            %{
              type: :breaking_changes,
              severity: :high,
              description: "API breaking changes detected",
              affected_files: ["lib/api.ex"],
              mitigation: "Implement backward compatibility"
            }
          ]
        }
      }

      mitigations = ChangeImpactAnalyzer.suggest_mitigations(impact_with_breaking_changes)

      backward_compat = Enum.find(mitigations, &(&1.type == :backward_compatibility))
      assert backward_compat
      assert backward_compat.effort in [:low, :medium, :high]
    end

    test "suggests mitigations for many dependents" do
      impact_with_many_deps = %{
        risk_assessment: %{
          factors: [
            %{
              type: :many_dependents,
              severity: :critical,
              description: "Changes affect 60 files",
              affected_files: [],
              mitigation: "Break into smaller changes"
            }
          ]
        }
      }

      mitigations = ChangeImpactAnalyzer.suggest_mitigations(impact_with_many_deps)

      staged_deployment = Enum.find(mitigations, &(&1.type == :staged_deployment))
      assert staged_deployment
    end
  end

  # Helper functions to create mock data

  defp create_mock_repo_analysis do
    {:ok, dependency_graph} = create_mock_dependency_graph()

    %{
      files: [
        %{
          path: "lib/module_a.ex",
          type: :lib,
          complexity: :medium,
          modules: [%{name: "ModuleA"}]
        },
        %{
          path: "lib/module_b.ex",
          type: :lib,
          complexity: :simple,
          modules: [%{name: "ModuleB"}]
        },
        %{
          path: "test/module_a_test.exs",
          type: :test,
          complexity: :simple,
          modules: [%{name: "ModuleATest"}]
        }
      ],
      dependencies: dependency_graph,
      patterns: [
        %{
          type: :phoenix_context,
          name: "TestContext",
          files: ["lib/module_a.ex"],
          confidence: 0.8
        }
      ],
      structure: %{
        type: :mix_project,
        root_path: "/test/project",
        mix_projects: [],
        config_files: [],
        deps: []
      }
    }
  end

  defp create_complex_repo_analysis do
    {:ok, dependency_graph} = create_mock_dependency_graph()

    %{
      files: [
        %{
          path: "lib/core_module.ex",
          type: :lib,
          complexity: :very_complex,
          modules: [%{name: "CoreModule"}]
        },
        %{
          path: "lib/simple_module.ex",
          type: :lib,
          complexity: :simple,
          modules: [%{name: "SimpleModule"}]
        }
      ],
      dependencies: dependency_graph,
      patterns: [
        %{
          type: :otp_application,
          name: "Core Application",
          files: ["lib/core_module.ex"],
          confidence: 0.9
        }
      ],
      structure: %{
        type: :mix_project,
        root_path: "/test/project",
        mix_projects: [],
        config_files: [],
        deps: []
      }
    }
  end

  defp create_repo_with_poor_test_coverage do
    {:ok, dependency_graph} = create_mock_dependency_graph()

    %{
      files: [
        %{
          path: "lib/untested_module.ex",
          type: :lib,
          complexity: :medium,
          modules: [%{name: "UntestedModule"}]
        },
        %{
          path: "lib/another_module.ex",
          type: :lib,
          complexity: :medium,
          modules: [%{name: "AnotherModule"}]
        }
        # Notice: no test files for coverage
      ],
      dependencies: dependency_graph,
      patterns: [],
      structure: %{
        type: :mix_project,
        root_path: "/test/project",
        mix_projects: [],
        config_files: [],
        deps: []
      }
    }
  end

  defp create_mock_dependency_graph do
    file_analyses = [
      %{
        path: "lib/module_a.ex",
        modules: [
          %{
            name: "ModuleA",
            imports: ["ModuleB"],
            aliases: [],
            uses: []
          }
        ]
      },
      %{
        path: "lib/module_b.ex",
        modules: [
          %{
            name: "ModuleB",
            imports: [],
            aliases: [],
            uses: []
          }
        ]
      }
    ]

    DependencyGraph.build(file_analyses)
  end
end
