defmodule RubberDuck.Jido.Actions.Provider.TokenEstimateAction do
  @moduledoc """
  Action for estimating token usage for messages.
  
  This action uses the provider module's token estimation capabilities
  or falls back to a simple character-based estimation.
  """
  
  use Jido.Action,
    name: "token_estimate",
    description: "Estimates token usage for a set of messages",
    schema: [
      messages: [type: :list, required: true],
      model: [type: :string, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Estimate tokens using provider module
    case estimate_tokens(agent.state.provider_module, params.messages, params.model) do
      {:ok, estimate} ->
        # Emit success response
        signal_params = %{
          signal_type: "provider.token.estimate_response",
          data: %{
            estimate: estimate,
            provider: agent.name,
            model: params.model,
            timestamp: DateTime.utc_now()
          }
        }
        
        case EmitSignalAction.run(signal_params, %{agent: agent}) do
          {:ok, signal_result, _} ->
            {:ok, %{
              estimate: estimate,
              provider: agent.name,
              model: params.model,
              signal_emitted: signal_result.signal_emitted
            }, %{agent: agent}}
            
          error -> error
        end
        
      {:error, reason} ->
        # Emit error response
        signal_params = %{
          signal_type: "provider.token.estimate_failed",
          data: %{
            error: "Failed to estimate tokens: #{inspect(reason)}",
            provider: agent.name,
            model: params.model,
            timestamp: DateTime.utc_now()
          }
        }
        
        case EmitSignalAction.run(signal_params, %{agent: agent}) do
          {:ok, signal_result, _} ->
            {:ok, %{
              error: "Failed to estimate tokens: #{inspect(reason)}",
              provider: agent.name,
              model: params.model,
              signal_emitted: signal_result.signal_emitted
            }, %{agent: agent}}
            
          error -> error
        end
    end
  end

  # Private functions

  defp estimate_tokens(provider_module, messages, model) do
    if function_exported?(provider_module, :estimate_tokens, 2) do
      provider_module.estimate_tokens(messages, model)
    else
      # Simple estimation fallback
      char_count = messages
      |> Enum.map(fn msg -> String.length(msg["content"] || "") end)
      |> Enum.sum()
      
      # Rough estimate: ~4 chars per token
      {:ok, %{prompt_tokens: div(char_count, 4)}}
    end
  end
end