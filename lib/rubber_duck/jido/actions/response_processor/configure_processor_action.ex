defmodule RubberDuck.Jido.Actions.ResponseProcessor.ConfigureProcessorAction do
  @moduledoc """
  Action for updating processor configuration.
  
  This action allows dynamic configuration updates for the response processor,
  including cache settings, quality thresholds, and processing options.
  """
  
  use Jido.Action,
    name: "configure_processor",
    description: "Updates processor configuration with validation and change tracking",
    schema: [
      config_updates: [
        type: :map,
        required: true,
        doc: "Map of configuration updates to apply"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{EmitSignalAction, UpdateStateAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    config_updates = params.config_updates
    
    current_config = agent.state.config
    updated_config = Map.merge(current_config, config_updates)
    
    # Update the configuration
    with {:ok, _result, %{agent: updated_agent}} <- UpdateStateAction.run(
      %{updates: %{config: updated_config}},
      %{agent: agent}
    ) do
      # Emit success signal
      signal_data = %{
        updated_config: updated_config,
        changes: Map.keys(config_updates),
        timestamp: DateTime.utc_now()
      }
      
      case EmitSignalAction.run(
        %{signal_type: "response.configured", data: signal_data},
        %{agent: updated_agent}
      ) do
        {:ok, _result, %{agent: final_agent}} ->
          Logger.info("ResponseProcessorAgent configuration updated: #{inspect(Map.keys(config_updates))}")
          {:ok, signal_data, %{agent: final_agent}}
        {:error, reason} ->
          {:error, {:signal_emission_failed, reason}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end
end