defmodule RubberDuck.Jido.Agents.WorkflowPersistenceAsh do
  @moduledoc """
  Persistence layer for workflow state management using Ash resources.
  
  This module provides:
  - Workflow state serialization/deserialization using PostgreSQL
  - Checkpoint management during workflow execution
  - Recovery mechanisms for halted workflows
  - Version management for workflow definitions
  - Integration with agent state persistence
  
  ## Storage Backend
  
  Uses Ash resources with PostgreSQL for persistent storage.
  
  ## Example
  
      # Save workflow state
      {:ok, workflow_id} = WorkflowPersistence.save_workflow_state(
        workflow_id,
        MyWorkflow,
        reactor_state,
        context,
        %{status: :halted}
      )
      
      # Load workflow state
      {:ok, state} = WorkflowPersistence.load_workflow_state(workflow_id)
      
      # Save checkpoint
      {:ok, checkpoint_id} = WorkflowPersistence.save_checkpoint(
        workflow_id,
        "process_step",
        %{intermediate_result: data}
      )
  """
  
  require Logger
  
  alias RubberDuck.Workflows.{Workflow, Checkpoint, Version}
  
  @type workflow_id :: String.t()
  @type checkpoint_id :: String.t()
  @type version_id :: String.t()
  
  # Client API - No longer needs GenServer
  
  @doc """
  Module doesn't require starting anymore as it uses Ash resources.
  Kept for backward compatibility.
  """
  def start_link(_opts \\ []) do
    {:ok, self()}
  end
  
  @doc """
  Saves the current workflow state.
  """
  def save_workflow_state(workflow_id, module, reactor_state, context, metadata \\ %{}) do
    attrs = %{
      workflow_id: workflow_id,
      module: module,
      reactor_state: reactor_state,
      context: context,
      metadata: metadata,
      status: metadata[:status] || :halted
    }
    
    case Workflow
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, workflow} -> {:ok, workflow.workflow_id}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Loads a workflow state.
  """
  def load_workflow_state(workflow_id) do
    case Workflow
         |> Ash.Query.for_read(:get_by_workflow_id, %{workflow_id: workflow_id})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, workflow} -> {:ok, workflow}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Deletes a workflow state.
  """
  def delete_workflow_state(workflow_id) do
    case load_workflow_state(workflow_id) do
      {:ok, workflow} ->
        case Ash.destroy(workflow) do
          :ok -> :ok
          {:error, error} -> {:error, error}
        end
      {:error, :not_found} -> :ok
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Creates a checkpoint during workflow execution.
  """
  def save_checkpoint(workflow_id, step_name, state, metadata \\ %{}) do
    checkpoint_id = "cp_" <> generate_id()
    
    attrs = %{
      checkpoint_id: checkpoint_id,
      workflow_id: workflow_id,
      step_name: step_name,
      state: state,
      metadata: metadata
    }
    
    case Checkpoint
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, checkpoint} -> {:ok, checkpoint.checkpoint_id}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Loads the latest checkpoint for a workflow.
  """
  def load_checkpoint(workflow_id) do
    case Checkpoint
         |> Ash.Query.for_read(:get_latest, %{workflow_id: workflow_id})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :no_checkpoints}
      {:ok, checkpoint} -> {:ok, checkpoint}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Loads a specific checkpoint.
  """
  def load_checkpoint(workflow_id, checkpoint_id) do
    case Checkpoint
         |> Ash.Query.for_read(:get_by_checkpoint_id, %{checkpoint_id: checkpoint_id})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, checkpoint} -> 
        if checkpoint.workflow_id == workflow_id do
          {:ok, checkpoint}
        else
          {:error, :not_found}
        end
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Lists all checkpoints for a workflow.
  """
  def list_checkpoints(workflow_id) do
    case Checkpoint
         |> Ash.Query.for_read(:list_by_workflow, %{workflow_id: workflow_id})
         |> Ash.read() do
      {:ok, checkpoints} -> {:ok, checkpoints}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Saves a workflow version.
  """
  def save_version(module, version, definition) do
    attrs = %{
      module: module,
      version: version,
      definition: definition
    }
    
    case Version
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create() do
      {:ok, _version} -> {:ok, version}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Gets the current version of a workflow module.
  """
  def get_current_version(module) do
    case Version
         |> Ash.Query.for_read(:get_current, %{module: module})
         |> Ash.read_one() do
      {:ok, nil} -> {:error, :no_version}
      {:ok, version} -> {:ok, version}
      {:error, error} -> {:error, error}
    end
  end
  
  @doc """
  Lists all persisted workflows.
  """
  def list_workflows(opts \\ []) do
    query = Workflow
    
    query = if status = opts[:status] do
      Ash.Query.for_read(query, :list_by_status, %{status: status})
    else
      query
    end
    
    query = if module = opts[:module] do
      Ash.Query.for_read(query, :list_by_module, %{module: module})
    else
      query
    end
    
    # For now, skip date filtering as it requires more complex query building
    # TODO: Implement date filtering properly
    
    query = case opts[:order_by] do
      :created_at -> Ash.Query.sort(query, [created_at: :desc])
      :updated_at -> Ash.Query.sort(query, [updated_at: :desc])
      _ -> query
    end
    
    query = if limit = opts[:limit] do
      Ash.Query.limit(query, limit)
    else
      query
    end
    
    Ash.read(query)
  end
  
  @doc """
  Cleans up old workflow states and checkpoints.
  """
  def cleanup(older_than_days \\ 7) do
    # Clean up old workflows (checkpoints cascade delete)
    # For now, read all workflows and filter manually
    {:ok, all_workflows} = Ash.read(Workflow)
    
    cutoff_date = DateTime.add(DateTime.utc_now(), -older_than_days * 24 * 60 * 60, :second)
    
    old_workflows = Enum.filter(all_workflows, fn workflow ->
      DateTime.compare(workflow.created_at, cutoff_date) == :lt
    end)
    
    workflow_count = length(old_workflows)
    
    Enum.each(old_workflows, fn workflow ->
      Ash.destroy!(workflow)
    end)
    
    Logger.info("Cleaned up #{workflow_count} workflows")
    {:ok, %{workflows: workflow_count, checkpoints: 0}}
  end
  
  # Private helper functions
  
  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end