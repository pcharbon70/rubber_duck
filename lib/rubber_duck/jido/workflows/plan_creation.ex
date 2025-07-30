defmodule RubberDuck.Jido.Workflows.PlanCreation do
  @moduledoc """
  Workflow for creating development plans with validation and initialization.
  
  This workflow orchestrates the plan creation process:
  1. Validates input parameters
  2. Creates the plan structure
  3. Validates phases and dependencies
  4. Initializes plan resources
  5. Notifies relevant agents
  
  ## Inputs
  - `name` - Plan name (required)
  - `description` - Plan description (optional)
  - `phases` - List of plan phases (optional)
  - `metadata` - Additional metadata (optional)
  - `owner_id` - Owner identifier (required)
  """
  
  use Reactor
  
  
  # Define inputs
  input :name
  input :description
  input :phases
  input :metadata
  input :owner_id
  
  # Step 1: Validate basic inputs
  step :validate_inputs do
    argument :name, input(:name)
    argument :description, input(:description)
    argument :owner_id, input(:owner_id)
    
    run fn arguments ->
      with :ok <- validate_name(arguments.name),
           :ok <- validate_description(arguments.description),
           :ok <- validate_owner(arguments.owner_id) do
        {:ok, %{validated: true}}
      else
        {:error, reason} -> {:error, {:validation_failed, reason}}
      end
    end
    
    compensate fn _arguments, _error ->
      # No compensation needed for validation
      :ok
    end
  end
  
  # Step 2: Validate phases structure
  step :validate_phases do
    argument :phases, input(:phases)
    wait_for :validate_inputs
    
    run fn arguments ->
      phases = arguments.phases || []
      
      case validate_phases_structure(phases) do
        :ok -> {:ok, %{phases: normalize_phases(phases)}}
        {:error, reason} -> {:error, {:invalid_phases, reason}}
      end
    end
  end
  
  # Step 3: Check for duplicate plan names
  step :check_duplicates do
    argument :name, input(:name)
    argument :owner_id, input(:owner_id)
    wait_for :validate_inputs
    
    run fn arguments ->
      # Query existing plans to check for duplicates
      query_signal = %{
        "type" => "query_plans",
        "filters" => %{
          "name" => arguments.name,
          "owner_id" => arguments.owner_id
        }
      }
      
      # This would normally query the Plan Manager Agent
      # For now, we'll assume no duplicates
      {:ok, %{duplicate_check_passed: true}}
    end
  end
  
  # Step 4: Create plan structure
  step :create_plan_structure do
    argument :name, input(:name)
    argument :description, input(:description)
    argument :phases, result(:validate_phases, :phases)
    argument :metadata, input(:metadata)
    argument :owner_id, input(:owner_id)
    wait_for [:validate_phases, :check_duplicates]
    
    run fn arguments ->
      plan_data = %{
        "name" => arguments.name,
        "description" => arguments.description || "",
        "phases" => arguments.phases,
        "metadata" => enrich_metadata(arguments.metadata, arguments.owner_id),
        "owner_id" => arguments.owner_id,
        "created_at" => DateTime.utc_now(),
        "updated_at" => DateTime.utc_now()
      }
      
      {:ok, %{plan_data: plan_data}}
    end
    
    compensate fn _arguments, _error ->
      # No persistent state created yet, nothing to compensate
      :ok
    end
  end
  
  # Step 5: Initialize plan resources
  step :initialize_resources do
    argument :plan_data, result(:create_plan_structure, :plan_data)
    wait_for :create_plan_structure
    
    run fn arguments ->
      plan_data = arguments.plan_data
      
      # Initialize any required resources for the plan
      # This could include creating directories, initializing git repos, etc.
      resources = %{
        "workspace_id" => generate_workspace_id(plan_data["name"]),
        "repository_initialized" => false,
        "resource_pool_allocated" => true
      }
      
      {:ok, %{resources: resources}}
    end
    
    compensate fn arguments, _error ->
      # Clean up any resources that were created
      cleanup_resources(arguments.plan_data)
      :ok
    end
  end
  
  # Step 6: Persist plan to Plan Manager Agent
  step :persist_plan do
    argument :plan_data, result(:create_plan_structure, :plan_data)
    argument :resources, result(:initialize_resources, :resources)
    wait_for :initialize_resources
    
    run fn arguments ->
      # Merge resources into plan data
      enriched_plan = Map.merge(arguments.plan_data, %{
        "resources" => arguments.resources
      })
      
      # Create signal for Plan Manager Agent
      create_signal = %{
        "type" => "create_plan",
        "params" => enriched_plan
      }
      
      # In a real implementation, this would send to the Plan Manager Agent
      # For now, we simulate success
      plan_id = generate_plan_id(enriched_plan["name"])
      
      {:ok, %{plan_id: plan_id, plan: enriched_plan}}
    end
    
    compensate fn arguments, _error ->
      # Send delete signal to Plan Manager Agent
      delete_signal = %{
        "type" => "delete_plan",
        "plan_id" => arguments.plan_id
      }
      
      # Would send to Plan Manager Agent
      :ok
    end
  end
  
  # Step 7: Notify relevant agents
  step :notify_agents do
    argument :plan_id, result(:persist_plan, :plan_id)
    argument :plan, result(:persist_plan, :plan)
    wait_for :persist_plan
    
    run fn arguments ->
      notifications = [
        # Notify Plan Decomposer Agent if phases need decomposition
        maybe_notify_decomposer(arguments.plan),
        # Notify Task Assignment Agent if ready for assignment
        maybe_notify_task_assigner(arguments.plan),
        # Notify Progress Monitor Agent to start tracking
        notify_progress_monitor(arguments.plan_id, arguments.plan)
      ]
      
      successful_notifications = Enum.filter(notifications, & &1 == :ok)
      
      {:ok, %{
        notifications_sent: length(successful_notifications),
        plan_id: arguments.plan_id
      }}
    end
  end
  
  # Return the final result
  return :notify_agents
  
  ## Private validation functions
  
  defp validate_name(nil), do: {:error, :name_required}
  defp validate_name(name) when is_binary(name) do
    if String.length(name) >= 3 and String.length(name) <= 100 do
      :ok
    else
      {:error, :invalid_name_length}
    end
  end
  defp validate_name(_), do: {:error, :invalid_name_type}
  
  defp validate_description(nil), do: :ok
  defp validate_description(desc) when is_binary(desc) do
    if String.length(desc) <= 1000 do
      :ok
    else
      {:error, :description_too_long}
    end
  end
  defp validate_description(_), do: {:error, :invalid_description_type}
  
  defp validate_owner(nil), do: {:error, :owner_required}
  defp validate_owner(owner_id) when is_binary(owner_id), do: :ok
  defp validate_owner(_), do: {:error, :invalid_owner_type}
  
  defp validate_phases_structure(phases) when is_list(phases) do
    errors = phases
    |> Enum.with_index()
    |> Enum.map(fn {phase, index} ->
      validate_single_phase(phase, index)
    end)
    |> Enum.filter(& &1 != :ok)
    
    if length(errors) == 0 do
      :ok
    else
      {:error, errors}
    end
  end
  defp validate_phases_structure(_), do: {:error, :phases_must_be_list}
  
  defp validate_single_phase(phase, index) when is_map(phase) do
    required_fields = ["name", "description"]
    missing_fields = required_fields -- Map.keys(phase)
    
    if length(missing_fields) == 0 do
      :ok
    else
      {:error, {:phase_missing_fields, index, missing_fields}}
    end
  end
  defp validate_single_phase(_, index), do: {:error, {:invalid_phase_structure, index}}
  
  defp normalize_phases(phases) do
    phases
    |> Enum.with_index()
    |> Enum.map(fn {phase, index} ->
      phase
      |> Map.put("order", index + 1)
      |> Map.put("status", "pending")
      |> Map.put("created_at", DateTime.utc_now())
    end)
  end
  
  defp enrich_metadata(nil, owner_id) do
    %{
      "owner_id" => owner_id,
      "version" => "1.0.0",
      "tags" => [],
      "source" => "manual_creation"
    }
  end
  defp enrich_metadata(metadata, owner_id) when is_map(metadata) do
    metadata
    |> Map.put("owner_id", owner_id)
    |> Map.put_new("version", "1.0.0")
    |> Map.put_new("tags", [])
    |> Map.put_new("source", "manual_creation")
  end
  
  defp generate_workspace_id(name) do
    sanitized_name = name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    "workspace_#{sanitized_name}_#{timestamp}"
  end
  
  defp generate_plan_id(_name) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_ref = :erlang.unique_integer([:positive, :monotonic])
    "plan_#{timestamp}_#{unique_ref}"
  end
  
  defp cleanup_resources(_plan_data) do
    # In a real implementation, this would clean up any allocated resources
    :ok
  end
  
  defp maybe_notify_decomposer(plan) do
    phases = plan["phases"] || []
    
    if length(phases) > 0 and Enum.any?(phases, &needs_decomposition?/1) do
      # Send signal to Plan Decomposer Agent
      :ok
    else
      :ok
    end
  end
  
  defp needs_decomposition?(phase) do
    # Check if phase needs further decomposition
    tasks = Map.get(phase, "tasks", [])
    length(tasks) == 0 and Map.get(phase, "auto_decompose", true)
  end
  
  defp maybe_notify_task_assigner(plan) do
    if Map.get(plan, "auto_assign", false) do
      # Send signal to Task Assignment Agent
      :ok
    else
      :ok
    end
  end
  
  defp notify_progress_monitor(plan_id, _plan) do
    # Always notify progress monitor for new plans
    _signal = %{
      "type" => "track_plan",
      "plan_id" => plan_id,
      "tracking_config" => %{
        "update_interval" => 60_000, # 1 minute
        "alert_on_stall" => true,
        "stall_threshold" => 3600_000 # 1 hour
      }
    }
    
    # Would send to Progress Monitor Agent
    :ok
  end
end