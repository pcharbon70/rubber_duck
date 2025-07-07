defmodule RubberDuck.Enhancement.TechniqueSelectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Enhancement.TechniqueSelector

  describe "select_techniques/2" do
    test "selects appropriate techniques for code generation" do
      task = %{
        type: :code_generation,
        content: "Create a function to calculate prime numbers up to n",
        context: %{language: :elixir},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)

      assert length(techniques) > 0
      assert Enum.any?(techniques, fn {tech, _} -> tech == :cot end)
      assert Enum.any?(techniques, fn {tech, _} -> tech == :self_correction end)
    end

    test "selects RAG for context-heavy tasks" do
      task = %{
        type: :code_analysis,
        content:
          "Analyze the performance of the previous implementation and suggest improvements based on the patterns we discussed",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)

      assert Enum.any?(techniques, fn {tech, _} -> tech == :rag end)
    end

    test "selects CoT for reasoning tasks" do
      task = %{
        type: :question_answering,
        content: "Explain why recursion is preferred over iteration for tree traversal",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)

      assert Enum.any?(techniques, fn {tech, _} -> tech == :cot end)
    end

    test "selects self-correction for error-prone tasks" do
      task = %{
        type: :debugging,
        content: "Fix the bug in this function that's causing a crash",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)

      assert Enum.any?(techniques, fn {tech, _} -> tech == :self_correction end)
    end

    test "respects user technique exclusions" do
      task = %{
        type: :code_generation,
        content: "Create a simple function",
        context: %{},
        options: [exclude_techniques: [:rag, :self_correction]]
      }

      techniques = TechniqueSelector.select_techniques(task)

      assert Enum.all?(techniques, fn {tech, _} -> tech not in [:rag, :self_correction] end)
      assert Enum.any?(techniques, fn {tech, _} -> tech == :cot end)
    end

    test "returns techniques in optimal order" do
      task = %{
        type: :code_generation,
        content: "Complex task requiring all techniques",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task, %{})
      technique_names = Enum.map(techniques, fn {tech, _} -> tech end)

      # RAG should come before CoT, and self-correction should be last
      rag_index = Enum.find_index(technique_names, &(&1 == :rag))
      cot_index = Enum.find_index(technique_names, &(&1 == :cot))
      sc_index = Enum.find_index(technique_names, &(&1 == :self_correction))

      if rag_index && cot_index do
        assert rag_index < cot_index
      end

      if sc_index && cot_index do
        assert cot_index < sc_index
      end
    end
  end

  describe "analyze_task/1" do
    test "analyzes task complexity correctly" do
      simple_task = %{
        type: :text,
        content: "Hello world",
        context: %{},
        options: []
      }

      complex_task = %{
        type: :code_generation,
        content: "Implement a distributed caching system with optimization for performance and security",
        context: %{},
        options: []
      }

      simple_analysis = TechniqueSelector.analyze_task(simple_task)
      complex_analysis = TechniqueSelector.analyze_task(complex_task)

      assert simple_analysis.complexity < complex_analysis.complexity
      assert complex_analysis.complexity > 0.8
    end

    test "detects context requirements" do
      context_task = %{
        type: :code_analysis,
        content: "Based on the above code, what improvements can be made?",
        context: %{},
        options: []
      }

      no_context_task = %{
        type: :code_generation,
        content: "Create a new sorting algorithm",
        context: %{},
        options: []
      }

      assert TechniqueSelector.analyze_task(context_task).requires_context == true
      assert TechniqueSelector.analyze_task(no_context_task).requires_context == false
    end

    test "detects reasoning requirements" do
      reasoning_task = %{
        type: :question_answering,
        content: "Why is functional programming better for concurrent systems?",
        context: %{},
        options: []
      }

      simple_task = %{
        type: :text,
        content: "Format this text",
        context: %{},
        options: []
      }

      assert TechniqueSelector.analyze_task(reasoning_task).requires_reasoning == true
      assert TechniqueSelector.analyze_task(simple_task).requires_reasoning == false
    end

    test "detects error-prone content" do
      error_task = %{
        type: :debugging,
        content: "The function is broken and crashes with an error",
        context: %{},
        options: []
      }

      normal_task = %{
        type: :documentation,
        content: "Write documentation for the API",
        context: %{},
        options: []
      }

      assert TechniqueSelector.analyze_task(error_task).error_prone == true
      assert TechniqueSelector.analyze_task(normal_task).error_prone == false
    end

    test "detects programming language" do
      elixir_task = %{
        type: :code_analysis,
        content: "defmodule Example do\n  def hello, do: :world\nend",
        context: %{},
        options: []
      }

      js_task = %{
        type: :code_analysis,
        content: "const example = () => { return 'hello'; }",
        context: %{},
        options: []
      }

      assert TechniqueSelector.analyze_task(elixir_task).language == :elixir
      assert TechniqueSelector.analyze_task(js_task).language == :javascript
    end
  end

  describe "calculate_task_complexity/1" do
    test "returns higher complexity for complex task types" do
      simple_task = %{
        type: :documentation,
        content: "Document this",
        context: %{},
        options: []
      }

      complex_task = %{
        type: :debugging,
        content: "Debug this",
        context: %{},
        options: []
      }

      assert TechniqueSelector.calculate_task_complexity(simple_task) <
               TechniqueSelector.calculate_task_complexity(complex_task)
    end

    test "considers content indicators" do
      basic_task = %{
        type: :code_generation,
        content: "Create a simple function",
        context: %{},
        options: []
      }

      advanced_task = %{
        type: :code_generation,
        content: "Create a machine learning algorithm with optimization for distributed processing",
        context: %{},
        options: []
      }

      assert TechniqueSelector.calculate_task_complexity(basic_task) <
               TechniqueSelector.calculate_task_complexity(advanced_task)
    end
  end

  describe "technique configuration" do
    test "provides appropriate CoT configuration" do
      task = %{
        type: :code_generation,
        content: "Generate code",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)
      cot_config = Enum.find(techniques, fn {tech, _} -> tech == :cot end)

      assert cot_config != nil
      {_, config} = cot_config
      assert config.chain_type == :generation
      assert config.max_steps > 0
      assert config.validation_enabled == true
    end

    test "provides appropriate RAG configuration" do
      task = %{
        type: :code_analysis,
        content: "Analyze this based on context",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)
      rag_config = Enum.find(techniques, fn {tech, _} -> tech == :rag end)

      assert rag_config != nil
      {_, config} = rag_config
      assert config.retrieval_strategy in [:semantic, :hybrid, :contextual]
      assert config.max_sources > 0
      assert config.relevance_threshold > 0
    end

    test "provides appropriate self-correction configuration" do
      task = %{
        type: :debugging,
        content: "Fix errors",
        context: %{},
        options: []
      }

      techniques = TechniqueSelector.select_techniques(task)
      sc_config = Enum.find(techniques, fn {tech, _} -> tech == :self_correction end)

      assert sc_config != nil
      {_, config} = sc_config
      assert :syntax in config.strategies
      assert config.max_iterations > 0
      assert config.convergence_threshold > 0
    end
  end
end
