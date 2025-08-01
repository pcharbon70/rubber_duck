defmodule RubberDuck.CorrectionStrategy.StrategyLibrary do
  @moduledoc """
  Strategy library management for correction strategies.
  
  Provides functionality for:
  - Strategy registration and discovery
  - Metadata management and versioning
  - Prerequisites and constraints validation
  - Success rate tracking and updates
  """

  @doc """
  Registers a new correction strategy in the library.
  """
  def register_strategy(library, strategy_id, strategy_definition) do
    validated_strategy = validate_strategy_definition(strategy_definition)
    
    case validated_strategy do
      {:ok, strategy} ->
        updated_library = Map.put(library, strategy_id, strategy)
        {:ok, updated_library}
      
      {:error, reason} ->
        {:error, "Strategy validation failed: #{reason}"}
    end
  end

  @doc """
  Retrieves a strategy by ID from the library.
  """
  def get_strategy(library, strategy_id) do
    case Map.get(library, strategy_id) do
      nil -> {:error, "Strategy not found: #{strategy_id}"}
      strategy -> {:ok, strategy}
    end
  end

  @doc """
  Lists all strategies in the library, optionally filtered by category.
  """
  def list_strategies(library, category \\ nil) do
    strategies = if category do
      library
      |> Enum.filter(fn {_id, strategy} -> strategy.category == category end)
    else
      library |> Enum.to_list()
    end
    
    {:ok, strategies}
  end

  @doc """
  Updates strategy metadata based on performance feedback.
  """
  def update_strategy_performance(library, strategy_id, performance_data) do
    case Map.get(library, strategy_id) do
      nil ->
        {:error, "Strategy not found: #{strategy_id}"}
      
      strategy ->
        updated_strategy = apply_performance_update(strategy, performance_data)
        updated_library = Map.put(library, strategy_id, updated_strategy)
        {:ok, updated_library}
    end
  end

  @doc """
  Validates strategy prerequisites against error context.
  """
  def check_prerequisites(strategy, error_context, system_state \\ %{}) do
    strategy.prerequisites
    |> Enum.reduce_while({:ok, []}, fn prerequisite, {:ok, checked} ->
      case evaluate_prerequisite(prerequisite, error_context, system_state) do
        {:ok, result} -> {:cont, {:ok, [result | checked]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Private Functions

  defp validate_strategy_definition(strategy) do
    required_fields = [:name, :category, :description, :base_cost, :success_rate]
    
    missing_fields = required_fields
    |> Enum.filter(fn field -> not Map.has_key?(strategy, field) end)
    
    if length(missing_fields) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      validated_strategy = strategy
      |> Map.put_new(:prerequisites, [])
      |> Map.put_new(:constraints, [])
      |> Map.put_new(:metadata, %{})
      |> ensure_valid_success_rate()
      |> ensure_positive_cost()
      
      {:ok, validated_strategy}
    end
  end

  defp ensure_valid_success_rate(strategy) do
    success_rate = max(0.0, min(1.0, strategy.success_rate))
    %{strategy | success_rate: success_rate}
  end

  defp ensure_positive_cost(strategy) do
    base_cost = max(0.0, strategy.base_cost)
    %{strategy | base_cost: base_cost}
  end

  defp apply_performance_update(strategy, performance_data) do
    # Update success rate using exponential moving average
    alpha = 0.1  # Learning rate
    current_success_rate = strategy.success_rate
    observed_success_rate = performance_data["success_rate"] || current_success_rate
    
    new_success_rate = current_success_rate * (1 - alpha) + observed_success_rate * alpha
    
    # Update average cost if provided
    updated_strategy = %{strategy | success_rate: new_success_rate}
    
    if Map.has_key?(performance_data, "avg_cost") do
      current_cost = strategy.base_cost
      observed_cost = performance_data["avg_cost"]
      new_cost = current_cost * (1 - alpha) + observed_cost * alpha
      
      %{updated_strategy | base_cost: new_cost}
    else
      updated_strategy
    end
  end

  defp evaluate_prerequisite(prerequisite, error_context, system_state) do
    case prerequisite do
      "user_available" ->
        user_available = Map.get(system_state, :user_available, false)
        if user_available do
          {:ok, "User available for guidance"}
        else
          {:error, "User not available for interactive correction"}
        end
      
      "syntax_parser_available" ->
        # Check if syntax parser is available for the language
        language = Map.get(error_context, "language", "unknown")
        supported_languages = ["elixir", "javascript", "python"]
        
        if language in supported_languages do
          {:ok, "Syntax parser available for #{language}"}
        else
          {:error, "No syntax parser available for #{language}"}
        end
      
      "test_suite_exists" ->
        has_tests = Map.get(system_state, :has_test_suite, false)
        if has_tests do
          {:ok, "Test suite available for validation"}
        else
          {:error, "No test suite available for validation"}
        end
      
      _ ->
        # Unknown prerequisites default to satisfied
        {:ok, "Unknown prerequisite assumed satisfied: #{prerequisite}"}
    end
  end
end