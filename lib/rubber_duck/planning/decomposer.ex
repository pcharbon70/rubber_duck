defmodule RubberDuck.Planning.Decomposer do
  @moduledoc """
  Public API for task decomposition functionality.

  This module provides a simplified interface to the TaskDecomposer engine,
  handling configuration, execution, and result formatting for the planning system.
  """

  alias RubberDuck.Engine.Manager, as: EngineManager
  require Logger

  @default_timeout 30_000

  @doc """
  Decomposes a high-level description into structured tasks.

  ## Parameters
    - description: String description of what needs to be done
    - context: Map containing additional context like user_id, constraints, etc.

  ## Returns
    - {:ok, tasks} - List of task maps ready for database insertion
    - {:error, reason} - Error if decomposition fails
  """
  def decompose(description, context \\ %{}) do
    # Prepare input for the decomposer engine
    input = %{
      query: description,
      context: context,
      # Determine strategy based on context
      strategy: determine_strategy(description, context)
    }

    # Add required LLM configuration
    input = add_llm_config(input, context)

    # Execute decomposition
    case execute_decomposition(input) do
      {:ok, result} ->
        # Convert to format expected by planning system
        tasks = format_tasks_for_planning(result.tasks)
        {:ok, tasks}

      {:error, reason} ->
        Logger.error("Task decomposition failed: #{inspect(reason)}")
        {:error, format_error(reason)}
    end
  end

  @doc """
  Decomposes tasks using a specific pattern from the pattern library.
  """
  def decompose_with_pattern(pattern_name, context \\ %{}) do
    alias RubberDuck.Planning.PatternLibrary

    case PatternLibrary.apply_pattern(pattern_name, context) do
      {:ok, decomposition} ->
        tasks = format_tasks_for_planning(decomposition.tasks)
        {:ok, tasks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists available decomposition patterns.
  """
  def list_patterns do
    RubberDuck.Planning.PatternLibrary.list_patterns()
  end

  # Private functions

  defp determine_strategy(description, context) do
    cond do
      # If context specifies a strategy, use it
      context[:strategy] in [:linear, :hierarchical, :tree_of_thought] ->
        context[:strategy]

      # Pattern-based strategy selection
      String.contains?(String.downcase(description), ["step by step", "sequential", "then"]) ->
        :linear

      String.contains?(String.downcase(description), ["feature", "component", "module"]) ->
        :hierarchical

      String.contains?(String.downcase(description), ["explore", "research", "investigate"]) ->
        :tree_of_thought

      # Default to hierarchical for complex requests
      String.length(description) > 200 ->
        :hierarchical

      true ->
        :linear
    end
  end

  defp add_llm_config(input, context) do
    # Extract LLM config from context or use defaults
    llm_config = %{
      provider: context[:provider] || :openai,
      model: context[:model] || "gpt-4",
      temperature: context[:temperature] || 0.7,
      max_tokens: context[:max_tokens] || 2000
    }

    Map.merge(input, llm_config)
  end

  defp execute_decomposition(input) do
    # Initialize the engine if not already done
    ensure_engine_started()

    # Execute with timeout
    timeout = input[:timeout] || @default_timeout
    
    case EngineManager.execute(:task_decomposer, input, timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Decomposition execution error: #{inspect(e)}")
      {:error, :execution_failed}
  end

  defp ensure_engine_started do
    # The engine should be loaded by the application supervisor
    # Just return :ok here as the engine registry will handle missing engines
    :ok
  end

  defp format_tasks_for_planning(tasks) when is_list(tasks) do
    tasks
    |> Enum.with_index()
    |> Enum.map(fn {task, index} ->
      %{
        name: task["name"] || "Task #{index + 1}",
        description: task["description"] || "",
        position: task["position"] || index,
        complexity: normalize_complexity(task["complexity"]),
        success_criteria: format_success_criteria(task["success_criteria"]),
        validation_rules: task["validation_rules"] || %{},
        metadata: %{
          estimated_duration: task["estimated_duration"],
          risks: task["risks"] || [],
          prerequisites: task["prerequisites"] || [],
          optional: task["optional"] || false
        }
      }
    end)
  end

  defp format_tasks_for_planning(_), do: []

  defp normalize_complexity(nil), do: :medium
  defp normalize_complexity(complexity) when is_atom(complexity), do: complexity
  
  defp normalize_complexity(complexity) when is_binary(complexity) do
    case String.downcase(complexity) do
      "trivial" -> :trivial
      "simple" -> :simple
      "medium" -> :medium
      "complex" -> :complex
      "very_complex" -> :very_complex
      _ -> :medium
    end
  end
  
  defp normalize_complexity(_), do: :medium

  defp format_success_criteria(%{"criteria" => criteria}) when is_list(criteria) do
    %{"criteria" => criteria}
  end
  
  defp format_success_criteria(criteria) when is_list(criteria) do
    %{"criteria" => criteria}
  end
  
  defp format_success_criteria(_) do
    %{"criteria" => ["Task completed successfully"]}
  end

  defp format_error(:execution_failed), do: "Failed to execute task decomposition"
  defp format_error({:engine_error, _, reason}), do: "Engine error: #{inspect(reason)}"
  defp format_error({:validation_failed, reason}), do: "Validation failed: #{reason}"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end