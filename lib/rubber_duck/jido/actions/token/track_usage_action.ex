defmodule RubberDuck.Jido.Actions.Token.TrackUsageAction do
  @moduledoc """
  Action for tracking token usage in the Token Manager Agent.
  
  This action processes token usage data, calculates costs, creates provenance records,
  and updates the agent's state accordingly. It handles the complete flow of:
  
  - Token usage recording
  - Cost calculation based on pricing models  
  - Provenance tracking and relationship management
  - Buffer management and flushing
  - Budget updates and violation checking
  - Signal emission for downstream processors
  """
  
  use Jido.Action,
    name: "track_usage",
    description: "Tracks token usage with cost calculation and provenance",
    schema: [
      request_id: [type: :string, required: true],
      provider: [type: :string, required: true],
      model: [type: :string, required: true],
      prompt_tokens: [type: :integer, required: true],
      completion_tokens: [type: :integer, required: true],
      user_id: [type: :string, required: true],
      project_id: [type: :string, required: true],
      metadata: [type: :map, default: %{}],
      provenance: [type: :map, required: true]
    ]

  alias RubberDuck.Agents.TokenManager.{
    TokenUsage, 
    TokenProvenance,
    ProvenanceRelationship
  }
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, usage} <- create_token_usage(params),
         {:ok, usage_with_cost} <- calculate_cost(usage, agent.state.pricing_models),
         {:ok, provenance} <- create_provenance_record(usage_with_cost, params, agent),
         {:ok, updated_agent} <- update_agent_state(agent, usage_with_cost, provenance),
         {:ok, final_agent} <- maybe_flush_buffer(updated_agent),
         {:ok, _} <- emit_tracking_signal(final_agent, usage_with_cost, provenance) do
      {:ok, %{
        "tracked" => true, 
        "usage" => usage_with_cost, 
        "provenance" => provenance
      }, %{agent: final_agent}}
    end
  end

  # Private functions

  defp create_token_usage(params) do
    usage = TokenUsage.new(%{
      request_id: params.request_id,
      provider: params.provider,
      model: params.model,
      prompt_tokens: params.prompt_tokens,
      completion_tokens: params.completion_tokens,
      total_tokens: params.prompt_tokens + params.completion_tokens,
      user_id: params.user_id,
      project_id: params.project_id,
      team_id: Map.get(params.metadata, "team_id"),
      feature: Map.get(params.metadata, "feature"),
      metadata: params.metadata
    })
    
    {:ok, usage}
  end

  defp calculate_cost(usage, pricing_models) do
    case get_in(pricing_models, [usage.provider, usage.model]) do
      nil ->
        Logger.warning("No pricing model found for #{usage.provider}/#{usage.model}")
        updated_usage = %{usage | cost: Decimal.new(0), currency: "USD"}
        {:ok, updated_usage}
        
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
        updated_usage = %{usage | cost: total_cost, currency: "USD"}
        {:ok, updated_usage}
    end
  end

  defp create_provenance_record(usage, params, agent) do
    provenance_data = params.provenance
    
    provenance = TokenProvenance.new(Map.merge(provenance_data, %{
      usage_id: usage.id,
      request_id: params.request_id,
      root_request_id: Map.get(provenance_data, :root_request_id, 
        get_root_request_id(agent, provenance_data[:parent_request_id], params.request_id)),
      depth: calculate_request_depth(agent, provenance_data[:parent_request_id])
    }))
    
    {:ok, provenance}
  end

  defp update_agent_state(agent, usage, provenance) do
    # Update usage buffer
    new_usage_buffer = [usage | agent.state.usage_buffer]
    trimmed_usage_buffer = if length(new_usage_buffer) > agent.state.config.buffer_size do
      Enum.take(new_usage_buffer, agent.state.config.buffer_size)
    else
      new_usage_buffer
    end

    # Update provenance buffer
    new_provenance_buffer = [provenance | agent.state.provenance_buffer]
    trimmed_provenance_buffer = if length(new_provenance_buffer) > agent.state.config.buffer_size do
      Enum.take(new_provenance_buffer, agent.state.config.buffer_size)
    else
      new_provenance_buffer
    end

    # Create relationship if this has a parent
    new_provenance_graph = if provenance.parent_request_id do
      relationship = ProvenanceRelationship.new(
        provenance.parent_request_id,
        usage.request_id,
        :triggered_by,
        %{signal_type: provenance.signal_type}
      )
      [relationship | agent.state.provenance_graph]
    else
      agent.state.provenance_graph
    end

    # Update metrics
    new_metrics = %{agent.state.metrics |
      total_tokens: agent.state.metrics.total_tokens + usage.total_tokens,
      total_cost: Decimal.add(agent.state.metrics.total_cost, usage.cost),
      requests_tracked: agent.state.metrics.requests_tracked + 1
    }

    # Update all applicable budgets
    applicable_budgets = find_all_applicable_budgets(agent.state.budgets, usage)
    updated_budgets = Enum.reduce(applicable_budgets, agent.state.budgets, fn budget, acc ->
      updated_budget = RubberDuck.Agents.TokenManager.Budget.add_usage(budget, usage.cost)
      Map.put(acc, budget.id, updated_budget)
    end)

    # Apply state updates
    state_updates = %{
      usage_buffer: trimmed_usage_buffer,
      provenance_buffer: trimmed_provenance_buffer,
      provenance_graph: new_provenance_graph,
      metrics: new_metrics,
      budgets: updated_budgets
    }

    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp maybe_flush_buffer(agent) do
    if length(agent.state.usage_buffer) >= agent.state.config.buffer_size do
      flush_usage_buffer(agent)
    else
      {:ok, agent}
    end
  end

  defp flush_usage_buffer(agent) do
    if agent.state.usage_buffer != [] do
      Logger.info("Flushing #{length(agent.state.usage_buffer)} usage records")
      
      # Emit flush signal
      signal_params = %{
        signal_type: "token.usage.flush",
        data: %{
          usage_records: agent.state.usage_buffer,
          count: length(agent.state.usage_buffer),
          timestamp: DateTime.utc_now()
        }
      }
      
      with {:ok, _, _} <- EmitSignalAction.run(signal_params, %{agent: agent}) do
        # Clear buffer and update last flush time
        state_updates = %{
          usage_buffer: [],
          metrics: Map.put(agent.state.metrics, :last_flush, DateTime.utc_now())
        }
        
        UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
      end
    else
      {:ok, agent}
    end
  end

  defp emit_tracking_signal(agent, usage, provenance) do
    signal_params = %{
      signal_type: "token.usage.tracked",
      data: %{
        request_id: usage.request_id,
        total_tokens: usage.total_tokens,
        cost: usage.cost,
        currency: usage.currency,
        lineage: %{
          parent: provenance.parent_request_id,
          root: provenance.root_request_id,
          depth: provenance.depth
        },
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp find_all_applicable_budgets(budgets, usage) do
    budgets
    |> Map.values()
    |> Enum.filter(fn budget ->
      budget.active and budget_applies_to_usage?(budget, usage)
    end)
  end

  defp budget_applies_to_usage?(budget, usage) do
    case budget.type do
      :global -> true
      :user -> budget.entity_id == usage.user_id
      :project -> budget.entity_id == usage.project_id
      :team -> budget.entity_id == usage.team_id
      _ -> false
    end
  end

  defp get_root_request_id(_agent, nil, request_id), do: request_id
  defp get_root_request_id(agent, parent_request_id, _request_id) do
    case find_provenance_by_request(agent.state.provenance_buffer, parent_request_id) do
      nil -> parent_request_id
      parent_prov -> parent_prov.root_request_id
    end
  end

  defp calculate_request_depth(_agent, nil), do: 0
  defp calculate_request_depth(agent, parent_request_id) do
    case find_provenance_by_request(agent.state.provenance_buffer, parent_request_id) do
      nil -> 1
      parent_prov -> parent_prov.depth + 1
    end
  end

  defp find_provenance_by_request(provenance_buffer, request_id) do
    Enum.find(provenance_buffer, fn prov -> 
      prov.request_id == request_id 
    end)
  end
end