defmodule RubberDuck.Enhancement.PipelineBuilderTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Enhancement.PipelineBuilder

  describe "build/3" do
    test "builds sequential pipeline" do
      techniques = [
        {:rag, %{strategy: :semantic}},
        {:cot, %{chain_type: :default}},
        {:self_correction, %{max_iterations: 2}}
      ]

      pipeline = PipelineBuilder.build(techniques, :sequential)

      assert pipeline == techniques
      assert length(pipeline) == 3
    end

    test "builds parallel pipeline with grouping" do
      techniques = [
        {:rag, %{}},
        {:cot, %{}},
        {:self_correction, %{}}
      ]

      config = %{max_parallel_techniques: 2}
      pipeline = PipelineBuilder.build(techniques, :parallel, config)

      # Should have some parallel grouping
      assert Enum.any?(pipeline, fn
               {:parallel, _steps} -> true
               _ -> false
             end)
    end

    test "builds conditional pipeline" do
      techniques = [
        {:rag, %{}},
        {:self_correction, %{}}
      ]

      pipeline = PipelineBuilder.build(techniques, :conditional)

      # Should have conditional steps
      assert Enum.any?(pipeline, fn
               {:conditional, _, _, _} -> true
               _ -> false
             end)
    end

    test "handles empty techniques list" do
      assert PipelineBuilder.build([], :sequential) == []
    end

    test "respects max parallel configuration" do
      techniques = Enum.map(1..6, fn i -> {:"tech_#{i}", %{}} end)
      config = %{max_parallel_techniques: 3}

      pipeline = PipelineBuilder.build(techniques, :parallel, config)

      # Check that no parallel group exceeds the limit
      Enum.each(pipeline, fn
        {:parallel, steps} -> assert length(steps) <= 3
        _ -> :ok
      end)
    end
  end

  describe "optimize/1" do
    test "merges adjacent parallel steps" do
      pipeline = [
        {:parallel, [{:rag, %{}}, {:cot, %{}}]},
        {:parallel, [{:other, %{}}]},
        {:self_correction, %{}}
      ]

      optimized = PipelineBuilder.optimize(pipeline)

      # Should merge the first two parallel steps
      assert length(optimized) < length(pipeline)
    end

    test "removes duplicate techniques" do
      pipeline = [
        {:rag, %{}},
        {:cot, %{}},
        # Duplicate
        {:rag, %{}},
        {:self_correction, %{}}
      ]

      optimized = PipelineBuilder.optimize(pipeline)

      # Should remove the duplicate RAG
      rag_count =
        Enum.count(optimized, fn
          {:rag, _} -> true
          _ -> false
        end)

      assert rag_count == 1
    end

    test "reorders for optimal performance" do
      pipeline = [
        {:self_correction, %{}},
        {:cot, %{}},
        {:rag, %{}}
      ]

      optimized = PipelineBuilder.optimize(pipeline)

      # Should reorder to RAG -> CoT -> Self-correction
      technique_order = Enum.map(optimized, fn {tech, _} -> tech end)

      rag_index = Enum.find_index(technique_order, &(&1 == :rag))
      cot_index = Enum.find_index(technique_order, &(&1 == :cot))
      sc_index = Enum.find_index(technique_order, &(&1 == :self_correction))

      assert rag_index < cot_index
      assert cot_index < sc_index
    end
  end

  describe "validate/1" do
    test "validates non-empty pipeline" do
      pipeline = [{:rag, %{}}, {:cot, %{}}]
      assert PipelineBuilder.validate(pipeline) == :ok
    end

    test "rejects empty pipeline" do
      assert {:error, "Pipeline cannot be empty"} = PipelineBuilder.validate([])
    end

    test "detects resource limit violations" do
      # Create a pipeline with too many steps
      pipeline = Enum.map(1..15, fn i -> {:"tech_#{i}", %{}} end)

      assert {:error, "Pipeline exceeds resource limits"} = PipelineBuilder.validate(pipeline)
    end

    test "validates complex pipelines" do
      pipeline = [
        {:rag, %{}},
        {:parallel, [{:cot, %{}}, {:other, %{}}]},
        {:conditional, {:has_errors, true}, {:self_correction, %{}}, {:noop, %{}}}
      ]

      assert PipelineBuilder.validate(pipeline) == :ok
    end
  end

  describe "estimate_resources/1" do
    test "estimates execution time for sequential pipeline" do
      pipeline = [
        # ~2000ms
        {:rag, %{}},
        # ~3000ms
        {:cot, %{}},
        # ~4000ms
        {:self_correction, %{}}
      ]

      resources = PipelineBuilder.estimate_resources(pipeline)

      assert resources.estimated_time_ms >= 9000
      assert resources.max_parallel_tasks == 1
    end

    test "estimates resources for parallel pipeline" do
      pipeline = [
        # Max of 2000, 3000 = 3000ms
        {:parallel, [{:rag, %{}}, {:cot, %{}}]},
        # 4000ms
        {:self_correction, %{}}
      ]

      resources = PipelineBuilder.estimate_resources(pipeline)

      assert resources.estimated_time_ms >= 7000
      assert resources.max_parallel_tasks == 2
    end

    test "estimates memory usage" do
      pipeline = [
        {:rag, %{}},
        {:cot, %{}},
        {:self_correction, %{}}
      ]

      resources = PipelineBuilder.estimate_resources(pipeline)

      assert resources.memory_estimate_mb > 0
      # Reasonable upper bound
      assert resources.memory_estimate_mb < 500
    end

    test "counts API calls" do
      pipeline = [
        # 2 API calls
        {:rag, %{}},
        # 1 API call
        {:cot, %{}},
        # 3 API calls
        {:self_correction, %{}}
      ]

      resources = PipelineBuilder.estimate_resources(pipeline)

      assert resources.api_calls == 6
    end

    test "handles conditional branches in estimation" do
      pipeline = [
        {
          :conditional,
          {:has_errors, true},
          # 4000ms, 3 API calls
          {:self_correction, %{}},
          # 0ms, 0 API calls
          {:noop, %{}}
        }
      ]

      resources = PipelineBuilder.estimate_resources(pipeline)

      # Should average the branches
      # (4000 + 0) / 2
      assert resources.estimated_time_ms == 2000
    end
  end

  describe "parallel grouping logic" do
    test "prevents self-correction from running in parallel with others" do
      techniques = [
        {:rag, %{}},
        {:self_correction, %{}},
        {:cot, %{}}
      ]

      pipeline = PipelineBuilder.build(techniques, :parallel, %{max_parallel_techniques: 3})

      # Self-correction should not be in a parallel group with others
      Enum.each(pipeline, fn
        {:parallel, steps} ->
          if Enum.any?(steps, fn {tech, _} -> tech == :self_correction end) do
            assert length(steps) == 1
          end

        _ ->
          :ok
      end)
    end

    test "allows RAG and CoT to run in parallel" do
      techniques = [
        {:rag, %{}},
        {:cot, %{}}
      ]

      pipeline = PipelineBuilder.build(techniques, :parallel, %{})

      # RAG and CoT can be grouped together
      assert [{:parallel, [{:rag, %{}}, {:cot, %{}}]}] = pipeline
    end
  end

  describe "conditional pipeline building" do
    test "makes self-correction conditional on errors" do
      techniques = [{:self_correction, %{strategies: [:syntax]}}]

      pipeline = PipelineBuilder.build(techniques, :conditional)

      assert [{:conditional, {:has_errors, true}, {:self_correction, _}, {:noop, %{}}}] = pipeline
    end

    test "preserves technique order in conditional pipeline" do
      techniques = [
        {:rag, %{}},
        {:cot, %{}},
        {:self_correction, %{}}
      ]

      pipeline = PipelineBuilder.build(techniques, :conditional)

      # Should maintain logical order even with conditions
      assert length(pipeline) >= length(techniques)
    end
  end
end
