defmodule RubberDuck.Jido.Actions.Token.ConfigureManagerAction do
  @moduledoc """
  Action for updating the Token Manager Agent configuration.
  
  This action handles updates to agent configuration parameters
  such as buffer sizes, flush intervals, and alert settings.
  """
  
  use Jido.Action,
    name: "configure_manager",
    description: "Updates Token Manager Agent configuration",
    schema: [
      buffer_size: [type: :integer, default: nil],
      flush_interval: [type: :integer, default: nil],
      retention_days: [type: :integer, default: nil],
      alert_channels: [type: {:list, :string}, default: nil]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, config_updates} <- build_config_updates(params),
         {:ok, updated_agent} <- apply_config_updates(agent, config_updates) do
      {:ok, %{"config" => updated_agent.state.config}, %{agent: updated_agent}}
    end
  end

  # Private functions

  defp build_config_updates(params) do
    config_updates = params
    |> Map.take([:buffer_size, :flush_interval, :retention_days, :alert_channels])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    
    {:ok, config_updates}
  end

  defp apply_config_updates(agent, config_updates) do
    if map_size(config_updates) > 0 do
      updated_config = Map.merge(agent.state.config, config_updates)
      
      state_updates = %{
        config: updated_config
      }
      
      UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
    else
      {:ok, agent}
    end
  end
end