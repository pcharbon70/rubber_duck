defmodule RubberDuck.Workspace do
  use Ash.Domain,
    otp_app: :rubber_duck

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
  end
end
