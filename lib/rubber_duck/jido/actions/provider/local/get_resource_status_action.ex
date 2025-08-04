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
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  
  require Logger

  @impl true
  def run(_params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context
      with :ok <- validate_context(context) do
        agent = context.agent
        
        # Build resource status report with safe access
        case build_resource_status_report(agent) do
          {:ok, resources} ->
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
                
              {:error, reason} ->
                ErrorHandling.system_error("Failed to emit resource status signal: #{inspect(reason)}", %{reason: reason})
              error ->
                ErrorHandling.categorize_error(error)
            end
            
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: state}}) when is_map(state), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent state", %{})
  
  defp build_resource_status_report(agent) do
    try do
      resource_monitor = Map.get(agent.state, :resource_monitor, %{})
      loaded_models = Map.get(agent.state, :loaded_models, %{})
      active_requests = Map.get(agent.state, :active_requests, %{})
      
      resources = Map.merge(resource_monitor, %{
        "loaded_models" => Map.keys(loaded_models),
        "model_count" => map_size(loaded_models),
        "active_requests" => map_size(active_requests),
        "provider" => "local"
      })
      
      {:ok, resources}
    rescue
      error ->
        ErrorHandling.system_error("Failed to build resource status: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
end