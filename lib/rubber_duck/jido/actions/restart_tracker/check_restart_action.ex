defmodule RubberDuck.Jido.Actions.RestartTracker.CheckRestartAction do
  @moduledoc """
  Action for checking if an agent can be restarted based on its restart history.
  
  Returns `:ok` if the agent can be restarted, or `{:error, :backoff}` if it's
  still in the backoff period.
  """
  
  use Jido.Action,
    name: "check_restart",
    description: "Checks if an agent can be restarted based on backoff policy",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent to check restart eligibility for"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id} = params
    
    Logger.debug("Checking restart eligibility", agent_id: agent_id)
    
    if not agent.state.enabled do
      # Backoff enforcement is disabled
      emit_check_result(agent, agent_id, :ok, "Backoff enforcement disabled")
      {:ok, %{can_restart: true, reason: "disabled"}, %{agent: agent}}
    else
      now = DateTime.utc_now()
      
      case get_restart_info(agent.state.restart_data, agent_id) do
        nil ->
          # No restart history, allow restart
          emit_check_result(agent, agent_id, :ok, "No restart history")
          {:ok, %{can_restart: true, reason: "no_history"}, %{agent: agent}}
          
        %{backoff_until: nil} ->
          # Not in backoff period, allow restart
          emit_check_result(agent, agent_id, :ok, "Not in backoff period")
          {:ok, %{can_restart: true, reason: "no_backoff"}, %{agent: agent}}
          
        %{backoff_until: backoff_until} ->
          if DateTime.compare(now, backoff_until) == :gt do
            # Backoff period has expired, allow restart
            emit_check_result(agent, agent_id, :ok, "Backoff period expired")
            {:ok, %{can_restart: true, reason: "backoff_expired"}, %{agent: agent}}
          else
            # Still in backoff period, deny restart
            remaining = DateTime.diff(backoff_until, now, :millisecond)
            Logger.warning("Agent #{agent_id} still in backoff for #{remaining}ms")
            
            emit_check_result(agent, agent_id, {:error, :backoff}, "Still in backoff period")
            {:ok, %{can_restart: false, reason: "in_backoff", remaining_ms: remaining}, %{agent: agent}}
          end
      end
    end
  end

  # Private functions
  
  defp get_restart_info(restart_data, agent_id) do
    Map.get(restart_data, agent_id)
  end
  
  defp emit_check_result(agent, agent_id, result, reason) do
    signal_params = %{
      signal_type: "restart_tracker.check.result",
      data: %{
        agent_id: agent_id,
        result: format_result(result),
        reason: reason,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
  
  defp format_result(:ok), do: "allowed"
  defp format_result({:error, :backoff}), do: "denied"
  defp format_result(other), do: inspect(other)
end