defmodule RubberDuck.Jido.Actions.Base.EmitSignalAction do
  @moduledoc """
  Base action for emitting signals in the Jido pattern.
  
  This action provides a way to emit CloudEvents signals from within
  other actions, maintaining proper source attribution and ensuring
  signals follow the established hierarchical naming conventions.
  """
  
  use Jido.Action,
    name: "emit_signal",
    description: "Emits a CloudEvents signal through the signal bus",
    schema: [
      signal_type: [
        type: :string,
        required: true,
        doc: "The hierarchical signal type (e.g., 'token.budget.created')"
      ],
      data: [
        type: :map,
        default: %{},
        doc: "The signal data payload"
      ],
      source: [
        type: :string,
        default: nil,
        doc: "Override source attribution (defaults to agent ID)"
      ],
      subject: [
        type: :string,
        default: nil,
        doc: "The subject of the signal"
      ],
      extensions: [
        type: :map,
        default: %{},
        doc: "CloudEvents extension attributes"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Build the signal
    signal_attrs = %{
      type: params.signal_type,
      source: params.source || "agent:#{agent.id}",
      data: Map.put(params.data, :timestamp, DateTime.utc_now())
    }
    
    # Add optional fields
    signal_attrs = if params.subject do
      Map.put(signal_attrs, :subject, params.subject)
    else
      signal_attrs
    end
    
    # Add extensions if provided
    signal_attrs = if map_size(params.extensions) > 0 do
      Map.merge(signal_attrs, params.extensions)
    else
      signal_attrs
    end
    
    # Create and emit the signal
    case Jido.Signal.new(signal_attrs) do
      {:ok, signal} ->
        case Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal]) do
          {:ok, recorded_signals} ->
            {:ok, %{
              signal_emitted: true,
              signal_id: signal.id,
              signal_type: signal.type,
              recorded_count: length(recorded_signals)
            }, %{agent: agent}}
            
          {:error, reason} ->
            Logger.error("Failed to emit signal: #{inspect(reason)}")
            {:error, {:signal_emission_failed, reason}}
        end
        
      {:error, reason} ->
        Logger.error("Failed to create signal: #{inspect(reason)}")
        {:error, {:signal_creation_failed, reason}}
    end
  end
end