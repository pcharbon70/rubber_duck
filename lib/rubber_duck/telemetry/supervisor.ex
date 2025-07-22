defmodule RubberDuck.Telemetry.Supervisor do
  @moduledoc """
  Supervisor for telemetry handlers.
  
  Starts and manages all telemetry handler modules, ensuring they
  are properly attached during application startup.
  """
  
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    # Attach all telemetry handlers
    attach_handlers()
    
    # No child processes needed - handlers are just function attachments
    Supervisor.init([], strategy: :one_for_one)
  end
  
  defp attach_handlers do
    # Attach all domain-specific handlers
    RubberDuck.Telemetry.EnhancementHandler.attach()
    RubberDuck.Telemetry.ToolHandler.attach()
    RubberDuck.Telemetry.StatusHandler.attach()
    RubberDuck.Telemetry.SecurityHandler.attach()
    RubberDuck.Telemetry.WorkflowHandler.attach()
    
    # Keep existing AshHandler
    if Code.ensure_loaded?(RubberDuck.Telemetry.AshHandler) do
      RubberDuck.Telemetry.AshHandler.attach()
    end
    
    :ok
  end
end