defmodule RubberDuck.Jido.Actions.Metrics.RecordResourcesAction do
  @moduledoc """
  Action for recording agent resource usage metrics.
  
  This action captures resource utilization data including memory usage,
  queue lengths, and process reductions for monitoring agent health.
  """
  
  use Jido.Action,
    name: "record_resources",
    description: "Records agent resource usage metrics",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent being monitored"
      ],
      memory: [
        type: :integer,
        required: true,
        doc: "Memory usage in bytes"
      ],
      queue_length: [
        type: :integer,
        required: true,
        doc: "Current message queue length"
      ],
      reductions: [
        type: :integer,
        required: true,
        doc: "Process reductions count"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id, memory: memory, queue_length: queue_length, reductions: reductions} = params
    
    Logger.debug("Recording resource usage", 
      agent_id: agent_id, 
      memory: memory, 
      queue_length: queue_length,
      reductions: reductions
    )
    
    # Update current window resource data
    resource_data = {memory, queue_length, reductions}
    
    state_updates = %{
      current_window: put_in(
        agent.state.current_window,
        [:resources, agent_id],
        resource_data
      )
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        {:ok, %{recorded: true}, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, reason}
    end
  end
end