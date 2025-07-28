defmodule RubberDuck.Planning.Critics.PhaseStructureCritic do
  @moduledoc """
  Hard critic that validates the structure and progression of phases in a plan.
  
  This critic ensures:
  - Phases have clear names and descriptions
  - Phase progression is logical
  - No empty phases exist
  - Critical milestones are defined
  - Phase transitions make sense
  """
  
  @behaviour RubberDuck.Planning.Critics.CriticBehaviour
  
  alias RubberDuck.Planning.{Plan, Phase}
  alias RubberDuck.Planning.Critics.CriticBehaviour
  require Logger
  
  @impl true
  def name, do: "Phase Structure Validator"
  
  @impl true
  def type, do: :hard
  
  @impl true
  def priority, do: 15
  
  @impl true
  def validate(%Plan{} = plan, opts) do
    # Load phases if not already loaded
    plan = ensure_phases_loaded(plan, opts)
    
    case plan.phases do
      [] ->
        # Plans without phases are valid (backward compatibility)
        {:ok, CriticBehaviour.validation_result(:passed, "No phases to validate")}
        
      phases ->
        validate_phase_structure(phases)
    end
  end
  
  @impl true
  def validate(%Phase{} = phase, _opts) do
    # Validate individual phase
    validate_single_phase(phase)
  end
  
  @impl true
  def validate(_, _) do
    {:ok, CriticBehaviour.validation_result(:passed, "Not applicable for this target type")}
  end
  
  # Private functions
  
  defp ensure_phases_loaded(%Plan{phases: %Ash.NotLoaded{}} = plan, opts) do
    case Ash.load(plan, [:phases], opts) do
      {:ok, loaded_plan} -> loaded_plan
      _ -> plan
    end
  end
  defp ensure_phases_loaded(plan, _opts), do: plan
  
  defp validate_phase_structure(phases) do
    checks = [
      validate_phase_count(phases),
      validate_phase_names(phases),
      validate_phase_descriptions(phases),
      validate_phase_ordering(phases),
      validate_phase_progression(phases),
      validate_phase_completeness(phases)
    ]
    
    failed_checks = Enum.filter(checks, &match?({:error, _}, &1))
    warnings = Enum.filter(checks, &match?({:warning, _}, &1))
    
    cond do
      not Enum.empty?(failed_checks) ->
        errors = Enum.map(failed_checks, fn {:error, msg} -> msg end)
        {:ok, CriticBehaviour.validation_result(
          :failed,
          "Phase structure validation failed",
          details: %{errors: errors},
          suggestions: generate_phase_suggestions(failed_checks)
        )}
        
      not Enum.empty?(warnings) ->
        warning_msgs = Enum.map(warnings, fn {:warning, msg} -> msg end)
        {:ok, CriticBehaviour.validation_result(
          :warning,
          "Phase structure has minor issues",
          details: %{warnings: warning_msgs},
          suggestions: generate_phase_suggestions(warnings)
        )}
        
      true ->
        {:ok, CriticBehaviour.validation_result(:passed, "Phase structure is valid")}
    end
  end
  
  defp validate_single_phase(phase) do
    checks = [
      validate_phase_name(phase),
      validate_phase_description(phase),
      validate_phase_metadata(phase)
    ]
    
    case Enum.find(checks, &match?({:error, _}, &1)) do
      {:error, msg} ->
        {:ok, CriticBehaviour.validation_result(
          :failed,
          msg,
          suggestions: ["Ensure phase has a clear name and description"]
        )}
        
      nil ->
        {:ok, CriticBehaviour.validation_result(:passed, "Phase is valid")}
    end
  end
  
  defp validate_phase_count(phases) do
    case length(phases) do
      0 -> {:error, "Plan has no phases"}
      n when n > 10 -> {:warning, "Plan has many phases (#{n}), consider consolidation"}
      _ -> :ok
    end
  end
  
  defp validate_phase_names(phases) do
    issues = phases
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {phase, index} ->
      case validate_phase_name(phase) do
        {:error, msg} -> ["Phase #{index}: #{msg}"]
        _ -> []
      end
    end)
    
    case issues do
      [] -> :ok
      _ -> {:error, "Phase name issues: #{Enum.join(issues, "; ")}"}
    end
  end
  
  defp validate_phase_name(%{name: nil}), do: {:error, "Missing phase name"}
  defp validate_phase_name(%{name: ""}), do: {:error, "Empty phase name"}
  defp validate_phase_name(%{name: name}) when is_binary(name) do
    cond do
      String.length(name) < 3 ->
        {:error, "Phase name too short"}
        
      String.length(name) > 100 ->
        {:error, "Phase name too long"}
        
      not String.match?(name, ~r/^[A-Za-z]/) ->
        {:error, "Phase name should start with a letter"}
        
      true ->
        :ok
    end
  end
  defp validate_phase_name(_), do: {:error, "Invalid phase name format"}
  
  defp validate_phase_descriptions(phases) do
    without_desc = phases
    |> Enum.with_index(1)
    |> Enum.filter(fn {phase, _} -> 
      is_nil(phase.description) or phase.description == ""
    end)
    |> Enum.map(fn {phase, index} -> 
      "Phase #{index} (#{phase.name})"
    end)
    
    case without_desc do
      [] -> :ok
      phases -> {:warning, "Phases without descriptions: #{Enum.join(phases, ", ")}"}
    end
  end
  
  defp validate_phase_description(%{description: nil}), do: {:warning, "Missing description"}
  defp validate_phase_description(%{description: ""}), do: {:warning, "Empty description"}
  defp validate_phase_description(%{description: desc}) when is_binary(desc) do
    if String.length(desc) < 10 do
      {:warning, "Phase description is very brief"}
    else
      :ok
    end
  end
  defp validate_phase_description(_), do: :ok
  
  defp validate_phase_ordering(phases) do
    sorted_phases = Enum.sort_by(phases, & &1.position)
    
    # Check for position gaps
    positions = Enum.map(sorted_phases, & &1.position)
    expected = Enum.to_list(0..(length(phases) - 1))
    
    if positions == expected do
      :ok
    else
      {:warning, "Phase positions have gaps or duplicates"}
    end
  end
  
  defp validate_phase_progression(phases) do
    # Check logical progression based on common patterns
    sorted_phases = Enum.sort_by(phases, & &1.position)
    phase_names = Enum.map(sorted_phases, &String.downcase(&1.name))
    
    issues = check_progression_patterns(phase_names)
    
    case issues do
      [] -> :ok
      _ -> {:warning, "Phase progression issues: #{Enum.join(issues, "; ")}"}
    end
  end
  
  defp check_progression_patterns(phase_names) do
    issues = []
    
    # Check for implementation before design
    design_index = Enum.find_index(phase_names, &String.contains?(&1, "design"))
    impl_index = Enum.find_index(phase_names, &String.contains?(&1, "implement"))
    
    issues = if design_index && impl_index && impl_index < design_index do
      ["Implementation phase comes before design phase" | issues]
    else
      issues
    end
    
    # Check for testing after implementation
    test_index = Enum.find_index(phase_names, &String.contains?(&1, ["test", "validation"]))
    
    issues = if impl_index && test_index && test_index < impl_index do
      ["Testing phase comes before implementation" | issues]
    else
      issues
    end
    
    # Check for deployment without testing
    deploy_index = Enum.find_index(phase_names, &String.contains?(&1, ["deploy", "release"]))
    
    if deploy_index && is_nil(test_index) do
      ["Deployment phase without testing phase" | issues]
    else
      issues
    end
  end
  
  defp validate_phase_completeness(phases) do
    # Load tasks for each phase if needed
    phases_with_tasks = Enum.map(phases, &ensure_tasks_loaded/1)
    
    empty_phases = phases_with_tasks
    |> Enum.with_index(1)
    |> Enum.filter(fn {phase, _} -> 
      Enum.empty?(phase.tasks || [])
    end)
    |> Enum.map(fn {phase, index} -> 
      "Phase #{index} (#{phase.name})"
    end)
    
    case empty_phases do
      [] -> :ok
      phases -> {:error, "Empty phases without tasks: #{Enum.join(phases, ", ")}"}
    end
  end
  
  defp ensure_tasks_loaded(%Phase{tasks: %Ash.NotLoaded{}} = phase) do
    case Ash.load(phase, [:tasks]) do
      {:ok, loaded} -> loaded
      _ -> phase
    end
  end
  defp ensure_tasks_loaded(phase), do: phase
  
  defp validate_phase_metadata(%{metadata: nil}), do: :ok
  defp validate_phase_metadata(%{metadata: metadata}) when is_map(metadata) do
    # Check for recommended metadata
    if Map.has_key?(metadata, "deliverables") or Map.has_key?(metadata, "milestone") do
      :ok
    else
      {:warning, "Phase lacks deliverables or milestone definition"}
    end
  end
  defp validate_phase_metadata(_), do: :ok
  
  defp generate_phase_suggestions(issues) do
    base_suggestions = [
      "Ensure all phases have clear, descriptive names",
      "Add descriptions to explain each phase's purpose",
      "Order phases in logical progression",
      "Ensure each phase contains at least one task"
    ]
    
    specific_suggestions = issues
    |> Enum.flat_map(fn
      {:error, %{message: msg}} when is_binary(msg) ->
        cond do
          String.contains?(msg, "empty") ->
            ["Add tasks to empty phases or remove them"]
          String.contains?(msg, "name") ->
            ["Use descriptive phase names starting with a letter"]
          true -> []
        end
      {:warning, %{message: msg}} when is_binary(msg) ->
        if String.contains?(msg, "progression") do
          ["Review phase ordering for logical flow"]
        else
          []
        end
      _ -> []
    end)
    |> Enum.uniq()
    
    base_suggestions ++ specific_suggestions
  end
end