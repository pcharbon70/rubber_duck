defmodule RubberDuck.Jido.Actions.Provider.Local.GetResourceStatusAction do
  @moduledoc """
  Action for getting system resource status for local provider.
  
  This action collects current resource usage information including
  CPU, memory, GPU usage, and loaded model information.
  """
  
  use Jido.Action,
    name: "get_resource_status",
    description: "Gets system resource status for local provider",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    # Build resource status report
    resources = Map.merge(agent.state.resource_monitor, %{
      "loaded_models" => Map.keys(agent.state.loaded_models),
      "model_count" => map_size(agent.state.loaded_models),
      "active_requests" => map_size(agent.state.active_requests),
      "provider" => "local"
    })
    
    # Emit resource status signal
    signal_params = %{
      signal_type: "provider.resource.status",
      data: Map.merge(resources, %{
        timestamp: DateTime.utc_now()
      })
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, signal_result, _} ->
        {:ok, Map.merge(resources, %{
          signal_emitted: signal_result.signal_emitted
        }), %{agent: agent}}
        
      error -> error
    end
  end
end