defmodule RubberDuck.Jido.Actions.Provider.OpenAI.ConfigureFunctionsAction do
  @moduledoc """
  Action for configuring OpenAI function calling capabilities.
  
  This action stores function definitions in the agent state for use
  in subsequent OpenAI requests that support function calling.
  """
  
  use Jido.Action,
    name: "configure_functions",
    description: "Configures OpenAI function calling capabilities",
    schema: [
      functions: [type: :list, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  
  require Logger

  @impl true
  def run(params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context and parameters
      with :ok <- validate_context(context),
           :ok <- validate_functions(params.functions) do
        
        agent = context.agent
        
        # Store functions in agent state
        state_updates = %{functions: params.functions}
        
        with {:ok, _, %{agent: updated_agent}} <- UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}),
             {:ok, signal_result, _} <- emit_configuration_signal(updated_agent, params.functions) do
          {:ok, %{
            functions_configured: true,
            provider: "openai",
            function_count: length(params.functions),
            signal_emitted: signal_result.signal_emitted
          }, %{agent: updated_agent}}
        else
          {:error, reason} ->
            ErrorHandling.system_error("Failed to configure functions: #{inspect(reason)}", %{reason: reason})
          error ->
            ErrorHandling.categorize_error(error)
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: state}}) when is_map(state), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent state", %{})
  
  defp validate_functions(functions) when is_list(functions) do
    # Validate each function has required structure
    if Enum.all?(functions, &valid_function_structure?/1) do
      :ok
    else
      ErrorHandling.validation_error("Invalid function structure", %{functions: functions})
    end
  end
  defp validate_functions(_), do: ErrorHandling.validation_error("Functions must be a list", %{})
  
  defp valid_function_structure?(%{"name" => name}) when is_binary(name) and byte_size(name) > 0, do: true
  defp valid_function_structure?(_), do: false
  
  defp emit_configuration_signal(agent, functions) do
    signal_params = %{
      signal_type: "provider.functions.configured",
      data: %{
        provider: "openai",
        function_count: length(functions),
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end