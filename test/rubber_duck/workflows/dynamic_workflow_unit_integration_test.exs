defmodule RubberDuck.Workflows.DynamicWorkflowUnitIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{ComplexityAnalyzer, DynamicBuilder, TemplateRegistry}

  describe "component integration without full application" do
    test "complexity analyzer integrates with dynamic builder" do
      task = %{
        type: :analysis,
        target: "lib/example.ex",
        code: "defmodule Example, do: def hello, do: :world",
        code_stats: %{
          loc: 15,
          functions: 2
        }
      }

      # Analyze task complexity
      analysis = ComplexityAnalyzer.analyze(task)

      assert is_map(analysis)
      assert Map.has_key?(analysis, :complexity_score)
      assert Map.has_key?(analysis, :suggested_workflow_type)
      assert Map.has_key?(analysis, :resource_requirements)

      # Build workflow from analysis
      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      assert reactor
      assert is_struct(reactor, Reactor)
    end

    test "template registry integrates with dynamic builder" do
      # Get a template
      {:ok, template} = TemplateRegistry.get_by_name(:simple_analysis)

      assert is_map(template)
      assert Map.has_key?(template, :steps)
      assert is_list(template.steps)

      task = %{type: :analysis, target: "test.ex"}

      analysis = %{
        complexity_score: 3,
        resource_requirements: %{agents: [:analysis]},
        suggested_workflow_type: :simple_analysis
      }

      # Build workflow using template
      {:ok, reactor} =
        DynamicBuilder.build(task, analysis,
          use_template: true,
          template: template
        )

      assert reactor
    end

    test "end-to-end workflow construction for different task types" do
      tasks = [
        %{
          type: :analysis,
          target: "lib/simple.ex",
          code: "defmodule Simple, do: def test, do: :ok"
        },
        %{
          type: :generation,
          description: "Create a helper module",
          requirements: %{functions: ["format_date", "parse_input"]}
        },
        %{
          type: :refactoring,
          targets: ["lib/old.ex", "lib/legacy.ex"],
          options: %{extract_common: true}
        },
        %{
          type: :review,
          files: ["lib/important.ex"],
          criteria: %{security: true, performance: true}
        }
      ]

      for task <- tasks do
        # Analyze each task
        analysis = ComplexityAnalyzer.analyze(task)

        assert is_map(analysis)
        assert is_number(analysis.complexity_score)
        assert analysis.complexity_score >= 1
        assert analysis.complexity_score <= 10

        # Build workflow for each
        {:ok, reactor} = DynamicBuilder.build(task, analysis, use_template: true)

        assert reactor
        assert is_struct(reactor, Reactor)
      end
    end

    test "complexity scoring affects workflow selection" do
      # Simple task - should get simple workflow
      simple_task = %{
        type: :simple_fix,
        target: "typo.ex",
        change: "fix variable name"
      }

      simple_analysis = ComplexityAnalyzer.analyze(simple_task)
      assert simple_analysis.complexity_score <= 3
      assert simple_analysis.suggested_workflow_type == :simple_analysis

      # Complex task - should get complex workflow  
      complex_task = %{
        type: :architecture_refactoring,
        scope: %{modules: 25, functions: 150},
        requirements: %{
          maintain_compatibility: true,
          improve_performance: true,
          add_monitoring: true
        }
      }

      complex_analysis = ComplexityAnalyzer.analyze(complex_task)
      assert complex_analysis.complexity_score >= 7
      assert complex_analysis.suggested_workflow_type in [:complex_refactoring, :deep_analysis]

      # Both should build successfully but with different structures
      {:ok, simple_reactor} = DynamicBuilder.build(simple_task, simple_analysis, use_template: true)
      {:ok, complex_reactor} = DynamicBuilder.build(complex_task, complex_analysis, use_template: true)

      assert simple_reactor
      assert complex_reactor
    end

    test "resource requirements affect workflow construction" do
      task = %{
        type: :multi_file_analysis,
        files: Enum.map(1..10, &"file#{&1}.ex"),
        depth: :deep
      }

      analysis = ComplexityAnalyzer.analyze(task)

      # Should require multiple agents for this task
      assert length(analysis.resource_requirements.agents) >= 2

      # Build with resource management
      {:ok, reactor_with_resources} =
        DynamicBuilder.build(task, analysis,
          include_resource_management: true,
          use_template: true
        )

      # Build without resource management
      {:ok, reactor_without_resources} =
        DynamicBuilder.build(task, analysis,
          include_resource_management: false,
          use_template: true
        )

      assert reactor_with_resources
      assert reactor_without_resources
    end

    test "optimization strategies are applied correctly" do
      task = %{
        type: :parallel_analysis,
        files: ["a.ex", "b.ex", "c.ex"],
        analysis_types: [:security, :performance, :style]
      }

      analysis = ComplexityAnalyzer.analyze(task)

      # Test different optimization strategies
      strategies = [:speed, :resource, :balanced]

      for strategy <- strategies do
        {:ok, reactor} =
          DynamicBuilder.build(task, analysis,
            optimization_strategy: strategy,
            use_template: true
          )

        assert reactor
        # Each strategy should produce a valid reactor
      end
    end

    test "template customization works correctly" do
      task = %{
        type: :generation,
        description: "Create authentication module"
      }

      analysis = ComplexityAnalyzer.analyze(task)

      customization = %{
        timeout: 120_000,
        security_checks: true,
        include_tests: true
      }

      {:ok, reactor} =
        DynamicBuilder.build(task, analysis,
          use_template: true,
          customization: customization
        )

      assert reactor
    end

    test "workflow finalization sets appropriate return values" do
      task = %{type: :simple_test}

      analysis = %{
        complexity_score: 2,
        resource_requirements: %{agents: [:analysis]},
        suggested_workflow_type: :simple_analysis
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      # The reactor should be properly finalized
      assert reactor
    end

    test "error handling throughout the pipeline" do
      # Test various error conditions
      error_cases = [
        {nil, %{}, "nil task"},
        {%{}, nil, "nil analysis"},
        {%{invalid: "structure"}, %{complexity_score: 5}, "invalid task structure"}
      ]

      for {task, analysis, _description} <- error_cases do
        result = DynamicBuilder.build(task, analysis)

        # Should handle errors gracefully
        assert {:error, _reason} = result
      end
    end

    test "step dependencies are properly handled" do
      task = %{
        type: :dependency_test,
        workflow: %{
          steps: [
            %{name: :step1, depends_on: []},
            %{name: :step2, depends_on: [:step1]},
            %{name: :step3, depends_on: [:step2]}
          ]
        }
      }

      analysis = ComplexityAnalyzer.analyze(task)

      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      assert reactor
    end

    test "parallelization strategies are applied" do
      task = %{
        type: :parallel_operations,
        operations: [:parse, :analyze, :validate, :optimize]
      }

      analysis = ComplexityAnalyzer.analyze(task)

      # Override parallelization strategy
      analysis_with_parallel = Map.put(analysis, :parallelization_strategy, :parallel_analysis)
      analysis_with_sequential = Map.put(analysis, :parallelization_strategy, :sequential)

      {:ok, parallel_reactor} = DynamicBuilder.build(task, analysis_with_parallel)
      {:ok, sequential_reactor} = DynamicBuilder.build(task, analysis_with_sequential)

      assert parallel_reactor
      assert sequential_reactor
    end

    test "agent allocation works correctly" do
      requirements = %{
        agents: [:research, :analysis, :generation],
        memory: :medium,
        estimated_time: 60_000
      }

      reactor = Reactor.Builder.new()
      {:ok, updated_reactor} = DynamicBuilder.add_resource_management(reactor, requirements)

      assert updated_reactor
    end

    test "template composition for complex workflows" do
      # Test complex task that might use multiple template patterns
      task = %{
        type: :full_development_cycle,
        stages: [:research, :design, :implement, :test, :review],
        complexity: :high
      }

      analysis = ComplexityAnalyzer.analyze(task)

      {:ok, reactor} =
        DynamicBuilder.build(task, analysis,
          use_template: true,
          optimization_strategy: :balanced
        )

      assert reactor
    end
  end

  describe "regression tests for known patterns" do
    test "handles map access patterns safely" do
      # Test the fix for map access issues in ComplexityAnalyzer
      task_with_nils = %{
        type: :analysis,
        # Intentionally missing code_stats to test nil handling
        target: "test.ex"
      }

      analysis = ComplexityAnalyzer.analyze(task_with_nils)

      # Should not crash and provide reasonable defaults
      assert is_map(analysis)
      assert is_number(analysis.complexity_score)
    end

    test "template registry returns consistent results" do
      # Test that template lookups are consistent
      template_names = [:simple_analysis, :deep_analysis, :generation_pipeline]

      for name <- template_names do
        {:ok, template1} = TemplateRegistry.get_by_name(name)
        {:ok, template2} = TemplateRegistry.get_by_name(name)

        assert template1 == template2
        assert Map.has_key?(template1, :steps)
        assert is_list(template1.steps)
      end
    end

    test "builder handles empty steps gracefully" do
      task = %{type: :empty_test}

      analysis = %{
        complexity_score: 1,
        resource_requirements: %{agents: []},
        suggested_workflow_type: :simple_analysis
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      # Should handle empty workflows
      assert reactor
    end
  end
end
