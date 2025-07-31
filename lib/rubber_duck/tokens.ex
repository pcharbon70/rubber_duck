defmodule RubberDuck.Tokens do
  use Ash.Domain,
    otp_app: :rubber_duck

  @moduledoc """
  Domain for managing token usage, budgets, and provenance tracking.

  This domain provides comprehensive token management capabilities including:
  - Token usage tracking and persistence
  - Budget management and enforcement
  - Provenance and lineage tracking
  - Cost analytics and reporting
  """

  resources do
    resource RubberDuck.Tokens.Resources.TokenUsage do
      # Usage tracking operations
      define :record_usage, action: :create
      define :bulk_record_usage, action: :bulk_create
      define :get_usage, action: :read, args: [:id]
      define :list_user_usage, action: :by_user, args: [:user_id]
      define :list_project_usage, action: :by_project, args: [:project_id]
      define :list_usage_in_range, action: :by_date_range, args: [:start_date, :end_date]
      define :sum_user_tokens, action: :sum_tokens_by_user, args: [:user_id]
      define :sum_project_cost, action: :sum_cost_by_project, args: [:project_id]
    end

    resource RubberDuck.Tokens.Resources.Budget do
      # Budget management operations
      define :create_budget, action: :create
      define :update_budget, action: :update
      define :get_budget, action: :read, args: [:id]
      define :list_budgets, action: :read
      define :list_active_budgets, action: :active
      define :find_applicable_budgets, action: :applicable, args: [:user_id, :project_id]
      define :update_spending, action: :update_spending, args: [:amount]
      define :reset_budget_period, action: :reset_period
      define :check_budget_limit, action: :check_limit, args: [:amount], get?: true
      define :activate_override, action: :activate_override, args: [:approval_data]
      define :deactivate_override, action: :deactivate_override
    end

    resource RubberDuck.Tokens.Resources.TokenProvenance do
      # Provenance tracking operations
      define :record_provenance, action: :create
      define :bulk_record_provenance, action: :bulk_create
      define :get_provenance, action: :read, args: [:id]
      define :get_by_request, action: :by_request_id, args: [:request_id]
      define :list_workflow_provenance, action: :by_workflow, args: [:workflow_id]
      define :list_task_provenance, action: :by_task_type, args: [:task_type]
      define :find_duplicates, action: :find_duplicates, args: [:input_hash]
      define :get_lineage, action: :get_lineage, args: [:request_id]
    end

    resource RubberDuck.Tokens.Resources.ProvenanceRelationship do
      # Relationship management operations
      define :create_relationship, action: :create
      define :bulk_create_relationships, action: :bulk_create
      define :get_relationship, action: :read, args: [:id]
      define :find_ancestors, action: :find_ancestors, args: [:request_id]
      define :find_descendants, action: :find_descendants, args: [:request_id]
      define :find_roots, action: :find_roots, args: [:request_id]
      define :build_lineage_tree, action: :build_lineage_tree, args: [:request_id]
    end
  end
end