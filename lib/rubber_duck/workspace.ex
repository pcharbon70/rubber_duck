defmodule RubberDuck.Workspace do
  use Ash.Domain,
    otp_app: :rubber_duck

  require Ash.Query

  resources do
    resource RubberDuck.Workspace.Project do
      define :create_project, action: :create
      define :list_projects, action: :read
      define :get_project, action: :read, get_by: [:id]
      define :update_project, action: :update
      define :delete_project, action: :destroy
    end

    resource RubberDuck.Workspace.CodeFile do
      define :create_code_file, action: :create
      define :list_code_files, action: :read
      define :get_code_file, action: :read, get_by: [:id]
      define :update_code_file, action: :update
      define :delete_code_file, action: :destroy
      define :semantic_search, action: :semantic_search
    end

    resource RubberDuck.Workspace.AnalysisResult do
      define :create_analysis_result, action: :create
      define :list_analysis_results, action: :read
      define :get_analysis_result, action: :read, get_by: [:id]
      define :update_analysis_result, action: :update
      define :delete_analysis_result, action: :destroy
    end

    resource RubberDuck.Workspace.ProjectCollaborator do
      # We'll implement custom functions for collaborator management
      # since they need special authorization logic
    end

    resource RubberDuck.Projects.SecurityAudit do
      define :log_security_event, action: :log_access
      define :list_project_audits, action: :by_project
      define :list_security_violations, action: :security_violations
      define :list_recent_activity, action: :recent_activity
    end
    
    resource RubberDuck.Projects.FileAudit do
      define :log_operation, action: :log_operation
      define :list_by_project, action: :by_project
      define :list_by_user, action: :by_user
      define :list_recent_failures, action: :recent_failures
      define :list_security_events, action: :security_events
    end
  end

  # Custom functions for collaborator management
  def add_project_collaborator(project, user, permission, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    # Check if actor is the project owner
    if actor && actor.id == project.owner_id do
      Ash.create(RubberDuck.Workspace.ProjectCollaborator, %{
        project_id: project.id,
        user_id: user.id,
        permission: permission
      })
    else
      {:error, Ash.Error.Forbidden.exception([])}
    end
  end

  def list_project_collaborators!(project, opts \\ []) do
    RubberDuck.Workspace.ProjectCollaborator
    |> Ash.Query.filter(project_id: project.id)
    |> Ash.read!(opts)
  end

  @doc """
  Checks if a user can perform a specific operation on a project.
  
  This function checks project ownership and collaborator permissions.
  """
  def can?(user, operation, project) do
    cond do
      # Owner can do anything
      project.owner_id == user.id ->
        true
        
      # Check collaborator permissions
      true ->
        case get_collaborator_permission(project, user) do
          :admin -> true
          :write -> operation in [:read, :write, :create, :list, :copy]
          :read -> operation in [:read, :list]
          nil -> false
        end
    end
  end
  
  defp get_collaborator_permission(project, user) do
    case RubberDuck.Workspace.ProjectCollaborator
         |> Ash.Query.filter(project_id: project.id, user_id: user.id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} -> nil
      {:ok, collaborator} -> collaborator.permission
      {:error, _} -> nil
    end
  end
end
