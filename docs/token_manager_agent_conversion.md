# Token Manager Agent Conversion to Jido Actions Pattern

## Overview

This document summarizes the conversion of the Token Manager Agent from using `handle_signal` callbacks to the proper Jido Actions pattern. The conversion maintains all existing functionality while improving code organization, testability, and maintainability.

## What Was Done

### 1. Analysis of Original Implementation

The original `TokenManagerAgent` had 14 signal handlers:

- `track_usage` - Token usage tracking with cost calculation and provenance
- `check_budget` - Budget constraint validation
- `create_budget` - Budget creation
- `update_budget` - Budget modification  
- `get_usage` - Usage data retrieval with filtering
- `generate_report` - Report generation (usage, cost, optimization)
- `get_recommendations` - Optimization recommendations
- `update_pricing` - Pricing model updates
- `configure_manager` - Agent configuration updates
- `get_status` - Agent status and health metrics
- `get_provenance` - Request provenance lookup
- `get_lineage` - Complete lineage tree construction
- `get_workflow_usage` - Workflow-specific usage analysis
- `analyze_task_costs` - Task type cost analysis

### 2. Created Individual Action Modules

Each signal handler was converted to a dedicated Action module in `/lib/rubber_duck/jido/actions/token/`:

#### Core Token Management
- `TrackUsageAction` - Handles complete usage tracking flow
- `CheckBudgetAction` - Validates budget constraints
- `CreateBudgetAction` - Creates new budgets
- `UpdateBudgetAction` - Modifies existing budgets

#### Data Retrieval
- `GetUsageAction` - Retrieves filtered usage data
- `GetStatusAction` - Provides agent status information
- `GenerateReportAction` - Creates comprehensive reports
- `GetRecommendationsAction` - Generates actionable recommendations

#### Provenance and Lineage
- `GetProvenanceAction` - Looks up request provenance
- `GetLineageAction` - Builds complete lineage trees
- `GetWorkflowUsageAction` - Analyzes workflow usage patterns
- `AnalyzeTaskCostsAction` - Provides task-specific cost analysis

#### Configuration
- `UpdatePricingAction` - Updates pricing models
- `ConfigureManagerAction` - Modifies agent configuration

### 3. Action Module Structure

Each action follows the proper Jido pattern:

```elixir
defmodule RubberDuck.Jido.Actions.Token.ExampleAction do
  use Jido.Action,
    name: "action_name",
    description: "Clear description",
    schema: [
      # Parameter validation schema
    ]

  @impl true 
  def run(params, context) do
    # Pure function that transforms state
    # Returns {:ok, result, updated_context} or {:error, reason}
  end

  # Private helper functions
end
```

### 4. Key Features Preserved

All original functionality has been preserved:

- **Token Usage Tracking**: Complete flow including cost calculation, provenance recording, and buffer management
- **Budget Management**: Creation, updates, constraint checking, and violation tracking
- **Cost Analysis**: Comprehensive cost calculation with multiple pricing models
- **Provenance Tracking**: Full lineage tracking with relationship management
- **Report Generation**: Usage, cost, and optimization reports
- **Optimization Recommendations**: Smart recommendations based on usage patterns
- **Configuration Management**: Dynamic agent configuration updates
- **Status Monitoring**: Health checks and metrics reporting

### 5. New Agent Implementation

Created `TokenManagerAgentV2` that uses the new action-based pattern:

```elixir
defmodule RubberDuck.Agents.TokenManagerAgentV2 do
  use Jido.Agent,
    name: "token_manager_v2",
    description: "Token management with Jido Actions",
    schema: [
      # State validation schema
    ],
    actions: RubberDuck.Jido.Actions.Token.all_actions()

  # Backward compatibility through signal routing
  def handle_signal(signal_type, data, agent) do
    case Token.resolve_action(signal_type) do
      {:ok, action_module} ->
        context = %{agent: agent}
        action_module.run(data, context)
      {:error, reason} ->
        {:error, reason, agent}
    end
  end
end
```

### 6. Comprehensive Test Suite

Created a complete test suite demonstrating:

- **Initialization Testing**: Validates proper state setup
- **Action Integration**: Tests signal routing to actions
- **Direct Action Usage**: Shows how to use actions independently
- **State Validation**: Ensures proper state management
- **Utility Functions**: Tests helper functions and calculations

## Benefits of the Conversion

### 1. Improved Architecture
- **Separation of Concerns**: Each action handles one specific responsibility
- **Pure Functions**: Actions are pure functions with no side effects
- **Composability**: Actions can be combined and reused
- **Testability**: Each action can be tested in isolation

### 2. Better Code Organization
- **Modular Structure**: Related functionality is grouped logically
- **Clear Interfaces**: Well-defined schemas and return values
- **Documentation**: Each action is thoroughly documented
- **Maintainability**: Easier to understand and modify individual pieces

### 3. Enhanced Flexibility
- **Direct Action Usage**: Actions can be called directly without signals
- **Custom Workflows**: Actions can be composed into complex workflows
- **External Integration**: Actions can be used by other systems
- **Backward Compatibility**: Original signal interface still works

### 4. Improved Testing
- **Unit Testing**: Each action can be tested independently
- **Integration Testing**: Test action combinations
- **Mocking**: Easy to mock dependencies and test edge cases
- **Coverage**: Better test coverage through focused testing

## Files Created

### Action Modules
- `/lib/rubber_duck/jido/actions/token/track_usage_action.ex`
- `/lib/rubber_duck/jido/actions/token/check_budget_action.ex`
- `/lib/rubber_duck/jido/actions/token/create_budget_action.ex`
- `/lib/rubber_duck/jido/actions/token/update_budget_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_usage_action.ex`
- `/lib/rubber_duck/jido/actions/token/generate_report_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_recommendations_action.ex`
- `/lib/rubber_duck/jido/actions/token/update_pricing_action.ex`
- `/lib/rubber_duck/jido/actions/token/configure_manager_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_status_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_provenance_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_lineage_action.ex`
- `/lib/rubber_duck/jido/actions/token/get_workflow_usage_action.ex`
- `/lib/rubber_duck/jido/actions/token/analyze_task_costs_action.ex`

### Support Files
- `/lib/rubber_duck/jido/actions/token.ex` - Index and mapping module
- `/lib/rubber_duck/agents/token_manager_agent_v2.ex` - New agent implementation
- `/test/rubber_duck/agents/token_manager_agent_v2_test.exs` - Comprehensive test suite

## Usage Examples

### Using Actions Directly

```elixir
# Track token usage
params = %{
  request_id: "req-123",
  provider: "openai", 
  model: "gpt-4",
  prompt_tokens: 100,
  completion_tokens: 50,
  user_id: "user-456",
  project_id: "proj-789",
  metadata: %{},
  provenance: %{parent_request_id: nil}
}

{:ok, result, updated_context} = 
  RubberDuck.Jido.Actions.Token.TrackUsageAction.run(params, %{agent: agent})
```

### Using Through Signal Interface (Backward Compatibility)

```elixir
{:ok, result, updated_agent} = 
  TokenManagerAgentV2.handle_signal("track_usage", params, agent)
```

### Composing Actions in Workflows

```elixir
workflow = [
  {CheckBudgetAction, budget_params},
  {TrackUsageAction, usage_params},
  {GenerateReportAction, report_params}
]
```

## Migration Path

1. **Phase 1**: Deploy new action modules alongside existing agent
2. **Phase 2**: Update external systems to use `TokenManagerAgentV2`
3. **Phase 3**: Migrate signal senders to use actions directly where beneficial
4. **Phase 4**: Remove old `TokenManagerAgent` after full migration

## Conclusion

The conversion successfully transforms the Token Manager Agent from a traditional GenServer with signal handlers to a modern Jido Agent with composable actions. This maintains all existing functionality while providing significant architectural improvements in modularity, testability, and maintainability.

The new pattern enables better testing, easier maintenance, and more flexible integration patterns while preserving backward compatibility for existing systems.