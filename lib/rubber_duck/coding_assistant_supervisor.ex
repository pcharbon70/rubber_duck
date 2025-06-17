defmodule RubberDuck.CodingAssistantSupervisor do
  @moduledoc """
  Supervisor for the Coding Assistant domain.
  
  This supervisor manages all components of the coding assistant system,
  including the engine registry, engine supervisor, and auto-started engines.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Engine Registry for discovery and routing
      {RubberDuck.CodingAssistant.EngineRegistry, []},
      
      # Distributed Engine Supervisor using Horde
      {RubberDuck.CodingAssistant.EngineSupervisor, []},
      
      # Auto-start the CodeAnalyser engine
      {
        Task,
        fn -> auto_start_engines() end
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp auto_start_engines do
    # Wait a moment for the supervisor to fully initialize
    Process.sleep(1000)
    
    # Start the CodeAnalyser engine with default configuration
    case RubberDuck.CodingAssistant.EngineSupervisor.start_engine(
      RubberDuck.CodingAssistant.Engines.CodeAnalyser,
      %{
        languages: [:elixir, :javascript, :python],
        cache_size: 1000,
        security_rules: :default
      }
    ) do
      {:ok, _pid} ->
        IO.puts("CodeAnalyser engine started successfully")
        
      {:error, reason} ->
        IO.puts("Failed to start CodeAnalyser engine: #{inspect(reason)}")
    end
  end
end