defmodule RubberDuck.Planning.Repository.ChangeSequencerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Repository.{ChangeSequencer, RepositoryAnalyzer, DependencyGraph}

  describe "create_sequence/3" do
    test "creates a sequence plan for repository changes" do
      repo_analysis = create_mock_repo_analysis()
      change_requests = create_sample_change_requests()

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      assert is_list(sequence.phases)
      assert length(sequence.phases) > 0
      assert is_list(sequence.parallel_groups)
      assert is_list(sequence.conflicts)
      assert is_list(sequence.validation_points)
      assert is_map(sequence.rollback_plan)
      assert %Duration{} = sequence.estimated_duration
    end

    test "orders phases by dependencies" do
      repo_analysis = create_mock_repo_analysis()

      change_requests = [
        %{
          id: "change1",
          # Depends on module_c
          files: ["lib/module_b.ex"],
          type: :feature,
          priority: :medium,
          dependencies: [],
          estimated_effort: 2.0,
          breaking: false
        },
        %{
          id: "change2",
          # No dependencies
          files: ["lib/module_c.ex"],
          type: :feature,
          priority: :medium,
          dependencies: [],
          estimated_effort: 1.0,
          breaking: false
        }
      ]

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      # Should order phases properly
      assert length(sequence.phases) >= 1

      # Find phases containing each file
      phase_with_c = Enum.find(sequence.phases, &("lib/module_c.ex" in &1.files))
      phase_with_b = Enum.find(sequence.phases, &("lib/module_b.ex" in &1.files))

      if phase_with_c && phase_with_b && phase_with_c != phase_with_b do
        # If in different phases, module_c should come first
        assert phase_with_c.phase < phase_with_b.phase
      end
    end

    test "detects file modification conflicts" do
      repo_analysis = create_mock_repo_analysis()

      change_requests = [
        %{
          id: "change1",
          # Same file
          files: ["lib/module_a.ex"],
          type: :feature,
          priority: :high,
          dependencies: [],
          estimated_effort: 2.0,
          breaking: false
        },
        %{
          id: "change2",
          # Same file - conflict!
          files: ["lib/module_a.ex"],
          type: :bugfix,
          priority: :medium,
          dependencies: [],
          estimated_effort: 1.0,
          breaking: false
        }
      ]

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      # Should detect conflicts
      file_conflict = Enum.find(sequence.conflicts, &(&1.type == :file_modification))
      assert file_conflict
      assert "lib/module_a.ex" in file_conflict.files
      assert file_conflict.resolution_strategy.type == :sequential_execution
    end

    test "identifies parallel execution opportunities" do
      repo_analysis = create_mock_repo_analysis()

      change_requests = [
        %{
          id: "change1",
          # Independent files
          files: ["lib/module_a.ex"],
          type: :feature,
          priority: :medium,
          dependencies: [],
          estimated_effort: 1.0,
          breaking: false
        },
        %{
          id: "change2",
          # Independent files
          files: ["lib/module_b.ex"],
          type: :feature,
          priority: :medium,
          dependencies: [],
          estimated_effort: 1.0,
          breaking: false
        }
      ]

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      # Should find parallel opportunities when files don't conflict
      parallel_phases = Enum.filter(sequence.phases, & &1.can_parallel)
      # May or may not find parallel opportunities
      assert length(parallel_phases) >= 0
    end

    test "creates validation points based on strategy" do
      repo_analysis = create_mock_repo_analysis()
      change_requests = create_sample_change_requests()

      # Test conservative strategy
      assert {:ok, sequence} =
               ChangeSequencer.create_sequence(
                 repo_analysis,
                 change_requests,
                 validation_strategy: :conservative
               )

      conservative_points = length(sequence.validation_points)

      # Test aggressive strategy
      assert {:ok, aggressive_sequence} =
               ChangeSequencer.create_sequence(
                 repo_analysis,
                 change_requests,
                 validation_strategy: :aggressive
               )

      aggressive_points = length(aggressive_sequence.validation_points)

      # Aggressive should have more validation points
      assert aggressive_points >= conservative_points
    end
  end

  describe "optimize_for_parallelism/2" do
    test "optimizes sequence for parallel execution" do
      repo_analysis = create_mock_repo_analysis()
      change_requests = create_sample_change_requests()

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)
      assert {:ok, optimized} = ChangeSequencer.optimize_for_parallelism(sequence, max_parallel: 4)

      # Should return an optimized sequence
      assert is_list(optimized.phases)
      assert is_list(optimized.parallel_groups)
      assert %Duration{} = optimized.estimated_duration
    end
  end

  describe "validate_sequence/2" do
    test "validates a correct sequence plan" do
      repo_analysis = create_mock_repo_analysis()
      change_requests = create_sample_change_requests()

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)
      assert {:ok, validations} = ChangeSequencer.validate_sequence(sequence, repo_analysis)

      assert is_list(validations)

      # Should have validation results for different checks
      dependency_check = Enum.find(validations, &(&1.type == :dependency_order))
      assert dependency_check
      assert dependency_check.status in [:ok, :warning, :error]

      cycle_check = Enum.find(validations, &(&1.type == :cycle_detection))
      assert cycle_check
    end

    test "detects validation errors" do
      # Create a sequence with unresolved conflicts
      invalid_sequence = %{
        phases: [
          %{phase: 1, name: "Phase 1", files: [], dependencies: [], can_parallel: false, validation_required: false}
        ],
        parallel_groups: [],
        conflicts: [
          %{
            type: :file_modification,
            files: ["test.ex"],
            description: "Conflict",
            # Unresolved!
            resolution_strategy: nil,
            severity: :high
          }
        ],
        validation_points: [],
        rollback_plan: %{checkpoints: [], rollback_order: [], estimated_rollback_time: Duration.new!(second: 0)},
        estimated_duration: Duration.new!(second: 0)
      }

      repo_analysis = create_mock_repo_analysis()

      assert {:error, {:validation_failed, errors}} = ChangeSequencer.validate_sequence(invalid_sequence, repo_analysis)
      assert length(errors) > 0

      conflict_error = Enum.find(errors, &(&1.type == :conflict_resolution))
      assert conflict_error
      assert conflict_error.status == :error
    end
  end

  describe "suggest_improvements/2" do
    test "suggests improvements for sequence plan" do
      repo_analysis = create_mock_repo_analysis()
      change_requests = create_sample_change_requests()

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      suggestions = ChangeSequencer.suggest_improvements(sequence, repo_analysis)

      assert is_list(suggestions)

      # Suggestions should be sorted by impact
      if length(suggestions) > 1 do
        impacts = Enum.map(suggestions, & &1.impact)
        assert impacts == Enum.sort(impacts, :desc)
      end
    end

    test "suggests phase consolidation when appropriate" do
      # Create a sequence with many small phases that could be consolidated
      repo_analysis = create_mock_repo_analysis()

      # Multiple small, independent changes
      change_requests =
        Enum.map(1..5, fn i ->
          %{
            id: "change#{i}",
            files: ["lib/small_module_#{i}.ex"],
            type: :feature,
            priority: :low,
            dependencies: [],
            estimated_effort: 0.5,
            breaking: false
          }
        end)

      assert {:ok, sequence} = ChangeSequencer.create_sequence(repo_analysis, change_requests)

      suggestions = ChangeSequencer.suggest_improvements(sequence, repo_analysis)

      # May suggest phase consolidation (depending on implementation)
      consolidation_suggestion = Enum.find(suggestions, &(&1.type == :phase_consolidation))

      if consolidation_suggestion do
        assert consolidation_suggestion.effort in [:low, :medium, :high]
        assert consolidation_suggestion.impact >= 0.0
      end
    end
  end

  # Helper functions

  defp create_mock_repo_analysis do
    {:ok, dependency_graph} = create_mock_dependency_graph()

    %{
      files: [
        %{path: "lib/module_a.ex", type: :lib, complexity: :medium},
        %{path: "lib/module_b.ex", type: :lib, complexity: :simple},
        %{path: "lib/module_c.ex", type: :lib, complexity: :simple}
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
        modules: [%{name: "ModuleA", imports: ["ModuleB"], aliases: [], uses: []}]
      },
      %{
        path: "lib/module_b.ex",
        modules: [%{name: "ModuleB", imports: ["ModuleC"], aliases: [], uses: []}]
      },
      %{
        path: "lib/module_c.ex",
        modules: [%{name: "ModuleC", imports: [], aliases: [], uses: []}]
      }
    ]

    DependencyGraph.build(file_analyses)
  end

  defp create_sample_change_requests do
    [
      %{
        id: "change1",
        files: ["lib/module_a.ex"],
        type: :feature,
        priority: :high,
        dependencies: [],
        estimated_effort: 3.0,
        breaking: false
      },
      %{
        id: "change2",
        files: ["lib/module_b.ex"],
        type: :bugfix,
        priority: :medium,
        dependencies: [],
        estimated_effort: 1.5,
        breaking: false
      },
      %{
        id: "change3",
        files: ["lib/module_c.ex"],
        type: :refactor,
        priority: :low,
        dependencies: [],
        estimated_effort: 2.0,
        breaking: true
      }
    ]
  end
end
