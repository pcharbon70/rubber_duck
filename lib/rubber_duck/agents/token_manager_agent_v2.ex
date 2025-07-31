defmodule RubberDuck.Agents.TokenManagerAgentV2 do
  @moduledoc """
  Token Manager Agent for centralized token usage tracking and budget management.
  
  This agent has been converted to use the proper Jido Agent pattern with Actions
  instead of handle_signal callbacks. It provides comprehensive token usage monitoring,
  budget enforcement, cost tracking, and optimization recommendations.
  
  ## Responsibilities
  
  - Real-time token usage tracking
  - Budget creation and enforcement
  - Cost calculation and allocation
  - Usage analytics and reporting
  - Optimization recommendations
  
  ## Architecture
  
  This agent now uses Jido Actions instead of signal handlers:
  - All signal handlers have been converted to individual Action modules
  - State transformations are pure functions
  - Signal emission is handled through EmitSignalAction
  - Agent is now a data structure managed by OTP processes
  
  ## State Structure
  
  ```elixir
  %{
    budgets: %{budget_id => Budget.t()},
    active_requests: %{request_id => request_data},
    usage_buffer: [TokenUsage.t()],
    provenance_buffer: [TokenProvenance.t()],
    provenance_graph: [ProvenanceRelationship.t()],
    pricing_models: %{provider => pricing_data},
    metrics: %{
      total_tokens: integer,
      total_cost: Decimal.t(),
      requests_tracked: integer,
      budget_violations: integer,
      last_flush: DateTime.t()
    },
    config: %{
      buffer_size: integer,
      flush_interval: integer,
      retention_days: integer,
      alert_channels: [String.t()]
    }
  }
  ```
  """

  use Jido.Agent,
    name: "token_manager_v2",
    description: "Manages token usage tracking, budgets, and optimization with Jido Actions",
    schema: [
      budgets: [type: :map, default: %{}],
      active_requests: [type: :map, default: %{}],
      usage_buffer: [type: :list, default: []],
      provenance_buffer: [type: :list, default: []],
      provenance_graph: [type: :list, default: []],
      pricing_models: [type: :map, required: true],
      metrics: [type: :map, required: true],
      config: [type: :map, required: true]
    ],
    actions: RubberDuck.Jido.Actions.Token.all_actions()

  alias RubberDuck.Agents.TokenManager.{
    TokenUsage, 
    Budget, 
    UsageReport,
    TokenProvenance,
    ProvenanceRelationship
  }
  alias RubberDuck.Jido.Actions.Token
  
  require Logger

  @default_config %{
    buffer_size: 100,
    flush_interval: 5_000,
    retention_days: 90,
    alert_channels: ["email", "slack"],
    budget_check_mode: :async,
    optimization_enabled: true
  }

  @pricing_models %{
    "openai" => %{
      "gpt-4" => %{prompt: 0.03, completion: 0.06, unit: 1000},
      "gpt-3.5-turbo" => %{prompt: 0.0015, completion: 0.002, unit: 1000},
      "gpt-4-32k" => %{prompt: 0.06, completion: 0.12, unit: 1000}
    },
    "anthropic" => %{
      "claude-3-opus" => %{prompt: 0.015, completion: 0.075, unit: 1000},
      "claude-3-sonnet" => %{prompt: 0.003, completion: 0.015, unit: 1000},
      "claude-3-haiku" => %{prompt: 0.00025, completion: 0.00125, unit: 1000}
    },
    "local" => %{
      "llama-2-70b" => %{prompt: 0.0, completion: 0.0, unit: 1000},
      "mistral-7b" => %{prompt: 0.0, completion: 0.0, unit: 1000}
    }
  }

  ## Initialization

  @impl true
  def on_init(context) do
    state = %{
      budgets: %{},
      active_requests: %{},
      usage_buffer: [],
      provenance_buffer: [],
      provenance_graph: [],  # List of ProvenanceRelationship
      pricing_models: @pricing_models,
      metrics: %{
        total_tokens: 0,
        total_cost: Decimal.new(0),
        requests_tracked: 0,
        budget_violations: 0,
        last_flush: DateTime.utc_now()
      },
      config: Map.merge(@default_config, Map.get(context, :config, %{}))
    }
    
    # Schedule periodic tasks will be handled by the Jido runtime
    # or through separate scheduling mechanisms
    
    {:ok, state}
  end

  ## Action Integration
  
  @doc """
  Handles incoming signals by routing them to appropriate actions.
  This provides backward compatibility while using the new action-based architecture.
  """
  def handle_signal(signal_type, data, agent) do
    case Token.resolve_action(signal_type) do
      {:ok, action_module} ->
        # Convert agent to the expected context format for actions
        context = %{agent: agent}
        
        case action_module.run(data, context) do
          {:ok, result, %{agent: updated_agent}} ->
            {:ok, result, updated_agent}
          {:ok, result} ->
            {:ok, result, agent}
          {:error, reason} ->
            {:error, reason, agent}
        end
        
      {:error, reason} ->
        Logger.warning("Unknown signal type: #{signal_type}")
        {:error, reason, agent}
    end
  end

  ## Lifecycle Hooks
  
  @impl true
  def on_before_validate_state(state) do
    # Validate that required state fields are present and correctly typed
    with :ok <- validate_budgets(state.budgets),
         :ok <- validate_metrics(state.metrics),
         :ok <- validate_pricing_models(state.pricing_models) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  ## Periodic Tasks (to be handled by external schedulers)
  
  @doc """
  Creates a periodic task configuration for buffer flushing.
  This should be used by external scheduling systems.
  """
  def flush_buffer_task_config do
    %{
      name: "flush_buffer",
      schedule: "*/5 * * * *", # every 5 seconds
      action: Token.TrackUsageAction,
      params: %{flush_trigger: true}
    }
  end
  
  @doc """
  Creates a periodic task configuration for metrics updates.
  """
  def metrics_update_task_config do
    %{
      name: "update_metrics",
      schedule: "0 * * * *", # every minute
      action: Token.GetStatusAction,
      params: %{emit_metrics: true}
    }
  end
  
  @doc """
  Creates a periodic task configuration for cleanup.
  """
  def cleanup_task_config do
    %{
      name: "cleanup_old_data",
      schedule: "0 0 * * *", # hourly
      action: Token.ConfigureManagerAction,
      params: %{cleanup_trigger: true}
    }
  end

  ## State Validation Helpers
  
  defp validate_budgets(budgets) when is_map(budgets), do: :ok
  defp validate_budgets(_), do: {:error, "budgets must be a map"}
  
  defp validate_metrics(%{total_tokens: tokens, total_cost: cost} = _metrics) 
       when is_integer(tokens) and tokens >= 0 do
    case Decimal.decimal?(cost) do
      true -> :ok
      false -> {:error, "total_cost must be a Decimal"}
    end
  end
  defp validate_metrics(_), do: {:error, "invalid metrics structure"}
  
  defp validate_pricing_models(models) when is_map(models), do: :ok
  defp validate_pricing_models(_), do: {:error, "pricing_models must be a map"}
  
  ## Utility Functions for Actions
  
  @doc """
  Calculates token cost based on usage and pricing models.
  This is used by the TrackUsageAction.
  """
  def calculate_token_cost(usage, pricing_models) do
    case get_in(pricing_models, [usage.provider, usage.model]) do
      nil ->
        Logger.warning("No pricing model found for #{usage.provider}/#{usage.model}")
        %{amount: Decimal.new(0), currency: "USD"}
        
      pricing ->
        prompt_cost = Decimal.mult(
          Decimal.new(usage.prompt_tokens),
          Decimal.div(Decimal.new(pricing.prompt), Decimal.new(pricing.unit))
        )
        
        completion_cost = Decimal.mult(
          Decimal.new(usage.completion_tokens),
          Decimal.div(Decimal.new(pricing.completion), Decimal.new(pricing.unit))
        )
        
        total_cost = Decimal.add(prompt_cost, completion_cost)
        %{amount: total_cost, currency: "USD"}
    end
  end
  
  @doc """
  Returns the default configuration for the Token Manager Agent.
  """
  def default_config, do: @default_config
  
  @doc """
  Returns the default pricing models.
  """
  def default_pricing_models, do: @pricing_models
end