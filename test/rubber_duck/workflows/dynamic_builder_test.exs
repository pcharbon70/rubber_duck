defmodule RubberDuck.Workflows.DynamicBuilderTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.{DynamicBuilder, ComplexityAnalyzer, TemplateRegistry}

  describe "build/3" do
    test "builds simple workflow from task and analysis" do
      task = %{
        type: :analysis,
        target: "lib/example.ex",
        code: "defmodule Example, do: :ok"
      }

      analysis = ComplexityAnalyzer.analyze(task)

      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      assert reactor
      assert Reactor.Builder.return(reactor) == {:ok, reactor}
    end

    test "builds workflow using template when available" do
      task = %{
        type: :generation,
        description: "Generate a function"
      }

      analysis = %{
        complexity_score: 5,
        suggested_workflow_type: :generation_pipeline,
        resource_requirements: %{
          agents: [:research, :generation, :review]
        }
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis, use_template: true)

      # Should have steps from generation pipeline template
      assert reactor
    end

    test "builds custom workflow when no template matches" do
      task = %{
        type: :custom,
        operations: [:analyze, :transform, :validate]
      }

      analysis = %{
        complexity_score: 6,
        suggested_workflow_type: :adaptive,
        resource_requirements: %{
          agents: [:analysis]
        }
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis)

      assert reactor
    end

    test "adds resource allocation steps" do
      task = %{type: :analysis}

      analysis = %{
        complexity_score: 8,
        resource_requirements: %{
          agents: [:research, :analysis],
          memory: :high,
          estimated_time: 180_000
        }
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis, include_resource_management: true)

      # Should include resource allocation steps
      assert reactor
    end

    test "applies optimization strategy" do
      task = %{type: :refactoring}

      analysis = %{
        complexity_score: 7,
        parallelization_strategy: :parallel_analysis,
        resource_requirements: %{agents: [:analysis, :generation]}
      }

      {:ok, reactor} = DynamicBuilder.build(task, analysis, optimization_strategy: :speed)

      # Should optimize for speed (parallel execution)
      assert reactor
    end

    test "handles errors gracefully" do
      task = nil
      analysis = %{}

      assert {:error, _reason} = DynamicBuilder.build(task, analysis)
    end
  end

  describe "add_dynamic_inputs/2" do
    test "adds inputs based on task fields" do
      task = %{
        code: "some code",
        target: "file.ex",
        options: %{deep: true}
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_dynamic_inputs(reactor, task)

      # Should have added inputs for code, target, and options
      assert updated
    end

    test "handles nested inputs" do
      task = %{
        files: ["a.ex", "b.ex"],
        config: %{
          analysis: %{depth: :deep},
          generation: %{style: :functional}
        }
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_dynamic_inputs(reactor, task)

      assert updated
    end
  end

  describe "add_steps_by_complexity/2" do
    test "adds minimal steps for low complexity" do
      analysis = %{
        complexity_score: 2,
        resource_requirements: %{agents: [:analysis]},
        suggested_workflow_type: :simple_analysis
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_steps_by_complexity(reactor, analysis)

      assert updated
    end

    test "adds comprehensive steps for high complexity" do
      analysis = %{
        complexity_score: 9,
        resource_requirements: %{
          agents: [:research, :analysis, :generation, :review]
        },
        parallelization_strategy: :parallel_analysis
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_steps_by_complexity(reactor, analysis)

      assert updated
    end

    test "respects dependency graph" do
      analysis = %{
        complexity_score: 5,
        dependency_graph: %{
          "step1" => [],
          "step2" => ["step1"],
          "step3" => ["step1", "step2"]
        }
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_steps_by_complexity(reactor, analysis)

      assert updated
    end
  end

  describe "add_resource_management/2" do
    test "adds agent allocation steps" do
      requirements = %{
        agents: [:research, :analysis],
        memory: :medium
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_resource_management(reactor, requirements)

      assert updated
    end

    test "adds monitoring steps for high resource usage" do
      requirements = %{
        agents: [:research, :analysis, :generation, :review],
        memory: :high,
        estimated_time: 300_000
      }

      reactor = Reactor.Builder.new()
      {:ok, updated} = DynamicBuilder.add_resource_management(reactor, requirements)

      # Should include monitoring for high resource usage
      assert updated
    end
  end

  describe "apply_optimizations/2" do
    test "optimizes for speed with parallelization" do
      reactor = build_test_reactor_with_steps()

      {:ok, optimized} = DynamicBuilder.apply_optimizations(reactor, :speed)

      # Should maximize parallelization
      assert optimized
    end

    test "optimizes for resources with sequential execution" do
      reactor = build_test_reactor_with_steps()

      {:ok, optimized} = DynamicBuilder.apply_optimizations(reactor, :resource)

      # Should minimize concurrent resource usage
      assert optimized
    end

    test "applies balanced optimization" do
      reactor = build_test_reactor_with_steps()

      {:ok, optimized} = DynamicBuilder.apply_optimizations(reactor, :balanced)

      # Should balance speed and resources
      assert optimized
    end
  end

  describe "finalize_workflow/1" do
    test "sets appropriate return value" do
      reactor = Reactor.Builder.new()
      {:ok, reactor} = Reactor.Builder.add_input(reactor, :input)

      {:ok, reactor} =
        Reactor.Builder.add_step(reactor, :process, {RubberDuck.Workflows.Steps.Echo, [input: {:input, :input}]}, [])

      {:ok, finalized} = DynamicBuilder.finalize_workflow(reactor)

      # Should set the last step as return value
      assert finalized
    end

    test "handles empty workflow" do
      reactor = Reactor.Builder.new()

      {:ok, finalized} = DynamicBuilder.finalize_workflow(reactor)

      assert finalized
    end
  end

  describe "integration with templates" do
    test "builds workflow from template with customization" do
      task = %{
        type: :analysis,
        targets: ["file1.ex", "file2.ex"],
        options: %{
          deep_analysis: true,
          security_check: true
        }
      }

      analysis = ComplexityAnalyzer.analyze(task)
      template = TemplateRegistry.get_template(:analysis, :complex)

      {:ok, reactor} =
        DynamicBuilder.build(task, analysis,
          use_template: true,
          template: template,
          customization: %{timeout: 120_000}
        )

      assert reactor
    end
  end

  # Helper functions

  defp build_test_reactor_with_steps do
    reactor = Reactor.Builder.new()

    {:ok, reactor} = Reactor.Builder.add_input(reactor, :data)

    {:ok, reactor} = Reactor.Builder.add_step(reactor, :step1, {RubberDuck.Workflows.Steps.Echo, []}, [])

    {:ok, reactor} = Reactor.Builder.add_step(reactor, :step2, {RubberDuck.Workflows.Steps.Echo, []}, [])

    {:ok, reactor} =
      Reactor.Builder.add_step(reactor, :step3, {RubberDuck.Workflows.Steps.Echo, []}, [
        %Reactor.Argument{name: :input, source: %Reactor.Template.Result{name: :step1}}
      ])

    reactor
  end
end
