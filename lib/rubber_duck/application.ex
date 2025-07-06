defmodule RubberDuck.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RubberDuck.Repo,
      RubberDuck.Telemetry,
      # Registry for circuit breakers
      {Registry, keys: :unique, name: RubberDuck.CircuitBreakerRegistry},
      # Registry for engines
      {Registry, keys: :unique, name: RubberDuck.Engine.Registry, id: RubberDuck.Engine.ProcessRegistry},
      # Engine system components
      RubberDuck.Engine.CapabilityRegistry,
      RubberDuck.Engine.Supervisor,
      # Plugin system components
      {Registry, keys: :unique, name: RubberDuck.Plugin.Registry},
      RubberDuck.Plugin.Supervisor,
      RubberDuck.Plugin.MessageBus,
      RubberDuck.PluginManager,
      # LLM system components
      RubberDuck.LLM.Supervisor,
      # Memory system components
      RubberDuck.Memory.Manager,
      # Context building components
      RubberDuck.Context.Cache,
      RubberDuck.Context.AdaptiveSelector,
      RubberDuck.Embeddings.Service,
      # Chain-of-Thought system
      RubberDuck.CoT.ConversationManager,
      # RAG (Retrieval Augmented Generation) system
      RubberDuck.RAG.Supervisor,
      # Self-Correction system
      RubberDuck.SelfCorrection.Supervisor,
      # Enhancement Integration system
      RubberDuck.Enhancement.Supervisor,
      # Workflow system components
      RubberDuck.Workflows.Registry,
      RubberDuck.Workflows.Executor,
      RubberDuck.Workflows.Cache,
      RubberDuck.Workflows.Metrics.Aggregator
      # Error boundary GenServer - started manually in tests
      # RubberDuck.ErrorBoundary
    ]

    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
