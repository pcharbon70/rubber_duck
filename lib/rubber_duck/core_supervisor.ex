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

      # Multi-tier cache system (Nebulex) - only start the multilevel cache
      {RubberDuck.Nebulex.Cache, []},
      # Performance optimization modules
      {RubberDuck.PerformanceOptimizer, []},
      {RubberDuck.CacheManager, []},
      {RubberDuck.TableMaintenance, []},
      # LLM data management
      {RubberDuck.LLMDataMaintenance, []},
      # LLM Performance Monitoring and Optimization (Section 4.3)
      {RubberDuck.LLMMetricsCollector, []},
      {RubberDuck.LLMPerformanceDashboard, []},
      {RubberDuck.LLMPerformanceBenchmarker, []},
      {RubberDuck.AdaptiveCacheManager, []},
      {RubberDuck.LLMPerformanceAlerting, []},

      # Distributed state synchronization
      {RubberDuck.DistributedLock, []},
      {RubberDuck.StateSynchronizer, []},
      # Context management domain
      {RubberDuck.ContextSupervisor, []},
      # AI model coordination domain
      {RubberDuck.ModelSupervisor, []},
      # Configuration management
      {RubberDuck.ConfigSupervisor, []},
      # ILP (Intelligent Language Processing) - Section 5.1
      {RubberDuck.ILP.ResourceIsolator, []},
      {RubberDuck.ILP.RealTime.Pipeline, []},
      {RubberDuck.ILP.Batch.Orchestrator, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end