defmodule RubberDuck.Enhancement.TechniqueSelector do
  @moduledoc """
  Intelligent selection of enhancement techniques based on task characteristics.

  Analyzes task type, complexity, and context to determine the optimal
  combination of enhancement techniques (CoT, RAG, Self-Correction).
  """

  require Logger

  @type task :: %{
          type: atom(),
          content: String.t(),
          context: map(),
          options: keyword()
        }

  @type technique :: :cot | :rag | :self_correction
  @type technique_config :: {technique(), map()}

  @doc """
  Selects appropriate enhancement techniques for a given task.

  Returns a list of techniques with their configurations.
  """
  @spec select_techniques(task(), map()) :: [technique_config()]
  def select_techniques(task, config \\ %{}) do
    # Analyze task characteristics
    analysis = analyze_task(task)

    # Get technique recommendations
    recommendations = get_recommendations(analysis, task.type)

    # Apply user preferences and constraints
    techniques = apply_constraints(recommendations, task.options, config)

    # Log selection
    Logger.debug("Selected techniques for #{task.type}: #{inspect(techniques)}")

    techniques
  end

  @doc """
  Analyzes task characteristics to inform technique selection.
  """
  @spec analyze_task(task()) :: map()
  def analyze_task(task) do
    %{
      complexity: calculate_complexity(task),
      requires_context: requires_context?(task),
      requires_reasoning: requires_reasoning?(task),
      error_prone: is_error_prone?(task),
      content_length: String.length(task.content),
      has_structure: has_structure?(task.content),
      language: detect_language(task)
    }
  end

  @doc """
  Calculates task-specific complexity score.
  """
  @spec calculate_task_complexity(task()) :: float()
  def calculate_task_complexity(task) do
    analysis = analyze_task(task)
    analysis.complexity
  end

  # Private functions

  defp calculate_complexity(task) do
    base_complexity =
      case task.type do
        :code_generation -> 0.7
        :code_analysis -> 0.6
        :documentation -> 0.4
        :refactoring -> 0.8
        :debugging -> 0.9
        :question_answering -> 0.5
        _ -> 0.5
      end

    # Adjust based on content
    length_factor = min(1.0, String.length(task.content) / 1000)

    # Check for specific complexity indicators
    complexity_indicators = [
      {~r/algorithm|optimization|performance/, 0.2},
      {~r/distributed|concurrent|parallel/, 0.2},
      {~r/security|encryption|authentication/, 0.15},
      {~r/machine learning|AI|neural/, 0.15}
    ]

    indicator_bonus =
      Enum.reduce(complexity_indicators, 0, fn {pattern, weight}, acc ->
        if Regex.match?(pattern, task.content), do: acc + weight, else: acc
      end)

    min(1.0, base_complexity + length_factor * 0.2 + indicator_bonus)
  end

  defp requires_context?(task) do
    context_indicators = [
      ~r/this|that|it|they|above|below|previous/i,
      ~r/context|based on|referring to|mentioned/i,
      ~r/\.\.\.|etc|and so on/i
    ]

    Enum.any?(context_indicators, &Regex.match?(&1, task.content)) ||
      task.type in [:code_analysis, :refactoring, :debugging]
  end

  defp requires_reasoning?(task) do
    reasoning_indicators = [
      ~r/why|how|explain|reason|because/i,
      ~r/compare|analyze|evaluate|assess/i,
      ~r/pros and cons|trade-?offs?|advantages/i,
      ~r/best|optimal|recommend|suggest/i
    ]

    Enum.any?(reasoning_indicators, &Regex.match?(&1, task.content)) ||
      task.type in [:debugging, :code_analysis]
  end

  defp is_error_prone?(task) do
    error_indicators = [
      ~r/error|bug|issue|problem|fix/i,
      ~r/wrong|incorrect|mistake|fault/i,
      ~r/fail|crash|broken|not working/i
    ]

    has_errors = Enum.any?(error_indicators, &Regex.match?(&1, task.content))

    has_errors || task.type in [:debugging, :code_generation] ||
      calculate_complexity(task) > 0.7
  end

  defp has_structure?(content) do
    # Check for code-like structure
    code_patterns = [
      ~r/def|function|class|module/,
      ~r/if|else|for|while/,
      ~r/\{|\}|\[|\]/,
      ~r/=>|->|::/
    ]

    Enum.any?(code_patterns, &Regex.match?(&1, content))
  end

  defp detect_language(task) do
    cond do
      task.context[:language] -> task.context[:language]
      String.contains?(task.content, ["defmodule", "def ", "|>"]) -> :elixir
      String.contains?(task.content, ["function", "const", "=>"]) -> :javascript
      String.contains?(task.content, ["def ", "class ", "import"]) -> :python
      true -> :unknown
    end
  end

  defp get_recommendations(analysis, task_type) do
    recommendations = []

    # RAG is useful for context-heavy tasks
    recommendations =
      if analysis.requires_context || analysis.content_length > 500 do
        [
          {:rag,
           %{
             retrieval_strategy: determine_retrieval_strategy(analysis),
             max_sources: 5,
             relevance_threshold: 0.7
           }}
          | recommendations
        ]
      else
        recommendations
      end

    # CoT is essential for reasoning tasks
    recommendations =
      if analysis.requires_reasoning || analysis.complexity > 0.6 do
        [
          {:cot,
           %{
             chain_type: determine_chain_type(task_type),
             max_steps: calculate_max_steps(analysis.complexity),
             validation_enabled: true
           }}
          | recommendations
        ]
      else
        recommendations
      end

    # Self-correction for error-prone or complex tasks
    recommendations =
      if analysis.error_prone || analysis.complexity > 0.7 do
        [
          {:self_correction,
           %{
             strategies: [:syntax, :semantic, :logic],
             max_iterations: 3,
             convergence_threshold: 0.1
           }}
          | recommendations
        ]
      else
        recommendations
      end

    # Ensure at least one technique is selected
    if Enum.empty?(recommendations) do
      # Default based on task type
      case task_type do
        :code_generation -> [{:cot, %{chain_type: :generation}}, {:self_correction, %{}}]
        :code_analysis -> [{:rag, %{}}, {:cot, %{chain_type: :analysis}}]
        :documentation -> [{:rag, %{}}, {:cot, %{chain_type: :explanation}}]
        _ -> [{:cot, %{chain_type: :default}}]
      end
    else
      recommendations
    end
  end

  defp determine_retrieval_strategy(analysis) do
    cond do
      analysis.has_structure -> :hybrid
      analysis.requires_reasoning -> :contextual
      true -> :semantic
    end
  end

  defp determine_chain_type(task_type) do
    case task_type do
      :code_generation -> :generation
      :code_analysis -> :analysis
      :debugging -> :debugging
      :documentation -> :explanation
      :refactoring -> :transformation
      _ -> :default
    end
  end

  defp calculate_max_steps(complexity) do
    # More complex tasks may need more reasoning steps
    base_steps = 3
    complexity_bonus = round(complexity * 4)
    base_steps + complexity_bonus
  end

  defp apply_constraints(recommendations, task_options, config) do
    recommendations
    |> filter_by_user_preferences(task_options)
    |> apply_resource_constraints(config)
    |> order_by_priority()
  end

  defp filter_by_user_preferences(recommendations, task_options) do
    # Allow user to exclude certain techniques
    excluded = Keyword.get(task_options, :exclude_techniques, [])

    Enum.reject(recommendations, fn {technique, _config} ->
      technique in excluded
    end)
  end

  defp apply_resource_constraints(recommendations, config) do
    # Apply any resource constraints (e.g., max techniques)
    max_techniques = Map.get(config, :max_techniques, 3)

    recommendations
    |> Enum.sort_by(&technique_priority/1, :desc)
    |> Enum.take(max_techniques)
  end

  defp technique_priority({:self_correction, _}), do: 3
  defp technique_priority({:cot, _}), do: 2
  defp technique_priority({:rag, _}), do: 1

  defp order_by_priority(recommendations) do
    # Order techniques for optimal execution
    # RAG -> CoT -> Self-Correction is usually the best order
    priority_order = [:rag, :cot, :self_correction]

    Enum.sort_by(recommendations, fn {technique, _} ->
      Enum.find_index(priority_order, &(&1 == technique)) || 999
    end)
  end
end
