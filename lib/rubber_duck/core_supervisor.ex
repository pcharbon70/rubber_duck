defmodule RubberDuck.CoreSupervisor do
  @moduledoc """
  Core supervisor for organizing different domain-specific supervisors.

  This supervisor manages the core business logic components of the
  distributed AI assistant system.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Database management (must start first)
      {RubberDuck.MnesiaManager, []},
      # Circuit breaker registry for LLM providers
      {Registry, keys: :unique, name: RubberDuck.CircuitBreakerRegistry},
      # LLM provider abstraction layer
      {RubberDuck.LLMAbstraction.ProviderRegistry, []},
      {RubberDuck.LLMAbstraction.LoadBalancer, []},
      {RubberDuck.LLMAbstraction.FailoverManager, []},
      # Distributed state synchronization
      {RubberDuck.DistributedLock, []},
      {RubberDuck.StateSynchronizer, []},
      # Context management domain
      {RubberDuck.ContextSupervisor, []},
      # AI model coordination domain
      {RubberDuck.ModelSupervisor, []},
      # Configuration management
      {RubberDuck.ConfigSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end