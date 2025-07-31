defmodule RubberDuck.Jido.Actions.Token do
  @moduledoc """
  Token Management Actions for the Jido-based Token Manager Agent.
  
  This module provides a collection of actions that replace the signal handlers
  in the original TokenManagerAgent implementation. Each action is a pure function
  that transforms agent state and emits appropriate signals.
  
  ## Available Actions
  
  ### Core Token Management
  - `TrackUsageAction` - Tracks token usage with cost calculation and provenance
  - `CheckBudgetAction` - Validates budget constraints before usage
  - `CreateBudgetAction` - Creates new budget configurations
  - `UpdateBudgetAction` - Modifies existing budget settings
  
  ### Data Retrieval  
  - `GetUsageAction` - Retrieves usage data with filtering
  - `GetStatusAction` - Provides agent health and status information
  - `GenerateReportAction` - Creates comprehensive usage and cost reports
  - `GetRecommendationsAction` - Generates optimization recommendations
  
  ### Provenance and Lineage
  - `GetProvenanceAction` - Retrieves provenance for specific requests
  - `GetLineageAction` - Builds complete lineage trees
  - `GetWorkflowUsageAction` - Analyzes usage by workflow
  - `AnalyzeTaskCostsAction` - Provides detailed task cost analysis
  
  ### Configuration
  - `UpdatePricingAction` - Updates LLM provider pricing models
  - `ConfigureManagerAction` - Modifies agent configuration
  
  ## Usage Example
  
      # Using an action directly
      params = %{
        request_id: "req-123",
        provider: "openai",
        model: "gpt-4",
        prompt_tokens: 150,
        completion_tokens: 50,
        user_id: "user-456",
        project_id: "proj-789",
        metadata: %{},
        provenance: %{parent_request_id: nil}
      }
      
      {:ok, result, updated_context} = 
        RubberDuck.Jido.Actions.Token.TrackUsageAction.run(params, %{agent: agent})
  
  ## Signal Mapping
  
  This table shows the mapping from original signal handlers to actions:
  
  | Original Signal | Action Module |
  |---|---|
  | `track_usage` | `TrackUsageAction` |
  | `check_budget` | `CheckBudgetAction` |
  | `create_budget` | `CreateBudgetAction` |
  | `update_budget` | `UpdateBudgetAction` |
  | `get_usage` | `GetUsageAction` |
  | `generate_report` | `GenerateReportAction` |
  | `get_recommendations` | `GetRecommendationsAction` |
  | `update_pricing` | `UpdatePricingAction` |
  | `configure_manager` | `ConfigureManagerAction` |
  | `get_status` | `GetStatusAction` |
  | `get_provenance` | `GetProvenanceAction` |
  | `get_lineage` | `GetLineageAction` |
  | `get_workflow_usage` | `GetWorkflowUsageAction` |
  | `analyze_task_costs` | `AnalyzeTaskCostsAction` |
  """
  
  alias RubberDuck.Jido.Actions.Token.{
    TrackUsageAction,
    CheckBudgetAction,
    CreateBudgetAction,
    UpdateBudgetAction,
    GetUsageAction,
    GenerateReportAction,
    GetRecommendationsAction,
    UpdatePricingAction,
    ConfigureManagerAction,
    GetStatusAction,
    GetProvenanceAction,
    GetLineageAction,
    GetWorkflowUsageAction,
    AnalyzeTaskCostsAction
  }
  
  @doc """
  Returns all available token management actions.
  """
  def all_actions do
    [
      TrackUsageAction,
      CheckBudgetAction,
      CreateBudgetAction,
      UpdateBudgetAction,
      GetUsageAction,
      GenerateReportAction,
      GetRecommendationsAction,
      UpdatePricingAction,
      ConfigureManagerAction,
      GetStatusAction,
      GetProvenanceAction,
      GetLineageAction,
      GetWorkflowUsageAction,
      AnalyzeTaskCostsAction
    ]
  end
  
  @doc """
  Maps signal types to their corresponding action modules.
  """
  def signal_to_action_map do
    %{
      "track_usage" => TrackUsageAction,
      "check_budget" => CheckBudgetAction,
      "create_budget" => CreateBudgetAction,
      "update_budget" => UpdateBudgetAction,
      "get_usage" => GetUsageAction,
      "generate_report" => GenerateReportAction,
      "get_recommendations" => GetRecommendationsAction,
      "update_pricing" => UpdatePricingAction,
      "configure_manager" => ConfigureManagerAction,
      "get_status" => GetStatusAction,
      "get_provenance" => GetProvenanceAction,
      "get_lineage" => GetLineageAction,
      "get_workflow_usage" => GetWorkflowUsageAction,
      "analyze_task_costs" => AnalyzeTaskCostsAction
    }
  end
  
  @doc """
  Resolves an action module from a signal type.
  """
  def resolve_action(signal_type) do
    case Map.get(signal_to_action_map(), signal_type) do
      nil -> {:error, "Unknown signal type: #{signal_type}"}
      action_module -> {:ok, action_module}
    end
  end
end