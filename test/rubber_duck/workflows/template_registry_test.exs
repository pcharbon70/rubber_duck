defmodule RubberDuck.Workflows.TemplateRegistryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.TemplateRegistry

  describe "get_template/2" do
    test "returns simple analysis template for low complexity analysis" do
      template = TemplateRegistry.get_template(:analysis, :simple)

      assert template.name == :simple_analysis
      assert length(template.steps) >= 1
      assert Enum.any?(template.steps, &(&1.type == :analysis))
      refute template.parallel_execution
    end

    test "returns deep analysis template for complex analysis" do
      template = TemplateRegistry.get_template(:analysis, :complex)

      assert template.name == :deep_analysis
      assert length(template.steps) >= 3
      assert Enum.any?(template.steps, &(&1.type == :research))
      assert Enum.any?(template.steps, &(&1.type == :analysis))
      assert template.parallel_execution
    end

    test "returns generation pipeline template" do
      template = TemplateRegistry.get_template(:generation, :medium)

      assert template.name == :generation_pipeline
      assert length(template.steps) >= 4

      # Verify pipeline order
      step_types = Enum.map(template.steps, & &1.type)
      assert [:research, :analysis, :generation, :review] == step_types
    end

    test "returns refactoring template based on complexity" do
      simple_template = TemplateRegistry.get_template(:refactoring, :simple)
      complex_template = TemplateRegistry.get_template(:refactoring, :complex)

      assert simple_template.name == :simple_refactoring
      assert complex_template.name == :complex_refactoring
      assert length(complex_template.steps) > length(simple_template.steps)
    end

    test "returns nil for unknown task type" do
      assert nil == TemplateRegistry.get_template(:unknown, :simple)
    end
  end

  describe "list_templates/0" do
    test "returns all available templates" do
      templates = TemplateRegistry.list_templates()

      assert is_list(templates)
      assert length(templates) > 0

      # Verify required templates exist
      template_names = Enum.map(templates, & &1.name)
      assert :simple_analysis in template_names
      assert :deep_analysis in template_names
      assert :generation_pipeline in template_names
    end
  end

  describe "register_template/2" do
    test "registers a custom template" do
      custom_template = %{
        name: :custom_analysis,
        description: "Custom analysis workflow",
        steps: [
          %{type: :analysis, agent: :analysis, config: %{}}
        ],
        parallel_execution: false
      }

      assert :ok = TemplateRegistry.register_template(:custom_analysis, custom_template)

      # Should be retrievable
      retrieved = TemplateRegistry.get_template(:analysis, :custom)
      assert retrieved.name == :custom_analysis
    end

    test "overwrites existing template" do
      original = %{name: :test_template, steps: []}
      updated = %{name: :test_template, steps: [%{type: :analysis}]}

      TemplateRegistry.register_template(:test_template, original)
      TemplateRegistry.register_template(:test_template, updated)

      retrieved = TemplateRegistry.get_by_name(:test_template)
      assert length(retrieved.steps) == 1
    end
  end

  describe "get_by_name/1" do
    test "retrieves template by exact name" do
      template = TemplateRegistry.get_by_name(:simple_analysis)

      assert template.name == :simple_analysis
    end

    test "returns nil for non-existent template" do
      assert nil == TemplateRegistry.get_by_name(:non_existent)
    end
  end

  describe "template structure" do
    test "all templates have required fields" do
      templates = TemplateRegistry.list_templates()

      Enum.each(templates, fn template ->
        assert Map.has_key?(template, :name)
        assert Map.has_key?(template, :description)
        assert Map.has_key?(template, :steps)
        assert is_list(template.steps)
        assert Map.has_key?(template, :parallel_execution)

        # Each step should have required fields
        Enum.each(template.steps, fn step ->
          assert Map.has_key?(step, :type)
          assert Map.has_key?(step, :agent)
          assert Map.has_key?(step, :config)
        end)
      end)
    end
  end

  describe "template composition" do
    test "compose_templates/2 combines multiple templates" do
      analysis = TemplateRegistry.get_by_name(:simple_analysis)

      review = %{
        name: :review_step,
        steps: [%{type: :review, agent: :review, config: %{}}],
        parallel_execution: false
      }

      composed = TemplateRegistry.compose_templates(analysis, review)

      assert composed.name == :composed_workflow
      assert length(composed.steps) == length(analysis.steps) + length(review.steps)
    end
  end

  describe "template parameters" do
    test "apply_parameters/2 customizes template with parameters" do
      template = TemplateRegistry.get_by_name(:simple_analysis)

      params = %{
        target_files: ["file1.ex", "file2.ex"],
        analysis_depth: :deep,
        timeout: 60_000
      }

      customized = TemplateRegistry.apply_parameters(template, params)

      # Parameters should be applied to step configs
      Enum.each(customized.steps, fn step ->
        assert step.config[:target_files] == params.target_files
        assert step.config[:analysis_depth] == params.analysis_depth
        assert step.config[:timeout] == params.timeout
      end)
    end
  end
end
