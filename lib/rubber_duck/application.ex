defmodule RubberDuck.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      RubberDuck.Repo,
      RubberDuck.Telemetry,
      # Telemetry handlers supervisor
      RubberDuck.Telemetry.Supervisor,
      # Registry for circuit breakers
      {Registry, keys: :unique, name: RubberDuck.CircuitBreakerRegistry},
      # Registry for engines
      {Registry, keys: :unique, name: RubberDuck.Engine.Registry, id: RubberDuck.Engine.ProcessRegistry},
      # Registry for file watchers
      {Registry, keys: :unique, name: RubberDuck.Projects.FileWatcher.Registry},
      # Registry for plan executors
      {Registry, keys: :unique, name: RubberDuck.ExecutorRegistry},
      # Engine system components
      RubberDuck.Engine.CapabilityRegistry,
      RubberDuck.Engine.TaskRegistry,
      RubberDuck.Engine.Supervisor,
      # Engine loader - loads engines after startup
      RubberDuck.Engine.Loader,
      # Plugin system components
      {Registry, keys: :unique, name: RubberDuck.Plugin.Registry},
      RubberDuck.Plugin.Supervisor,
      RubberDuck.Plugin.MessageBus,
      RubberDuck.PluginManager,
      # LLM system components
      RubberDuck.LLM.Supervisor,
      RubberDuck.LLM.ConnectionManager,
      RubberDuck.LLM.ModelConfig,
      # Memory system components
      RubberDuck.Memory.Manager,
      # Agent system components
      RubberDuck.Agents.AgentRegistry,
      RubberDuck.Agents.Supervisor,
      # Jido agent framework integration
      RubberDuck.Jido.Supervisor,
      # Context building components
      RubberDuck.Context.Cache,
      RubberDuck.Context.AdaptiveSelector,
      RubberDuck.Embeddings.Service,
      # Session context manager
      RubberDuck.SessionContext,
      # Chain-of-Thought system
      RubberDuck.CoT.ConversationManager,
      RubberDuck.CoT.ChainRegistry,
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
      RubberDuck.Workflows.Metrics.Aggregator,
      # Phoenix PubSub for channels
      {Phoenix.PubSub, name: RubberDuck.PubSub},
      # Task supervisor for async tool executions
      {Task.Supervisor, name: RubberDuck.TaskSupervisor},
      # Status broadcasting system
      RubberDuck.Status.Broadcaster,
      # Result processing components
      RubberDuck.Cache.ETS,
      # Monitoring and observability components
      RubberDuck.Tool.Monitoring,
      RubberDuck.Tool.Monitoring.Dashboard,
      RubberDuck.Tool.Telemetry.Poller,
      # Composition workflow monitoring
      RubberDuck.Tool.Composition.Metrics,
      # Tool registry (required by integration bridge)
      RubberDuck.Tool.Registry,
      # Tool integration bridge components
      RubberDuck.Tool.ExternalRegistry,
      RubberDuck.Tool.ExternalRouter,
      RubberDuck.Tool.StatePersistence,
      # Tool security system
      RubberDuck.Tool.SecurityManager,
      RubberDuck.Tool.Security.RateLimiter,
      RubberDuck.Tool.Security.Monitor,
      # Phoenix Presence for tracking users
      RubberDuckWeb.Presence,
      # Message queue for offline users
      RubberDuckWeb.MessageQueue,
      # Instruction template security system
      RubberDuck.Instructions.SecurityPipeline,
      # Analysis and metrics system
      RubberDuck.Analysis.MetricsCollector,
      # Collaboration system components
      {Registry, keys: :unique, name: RubberDuckWeb.Collaboration.EditorRegistry},
      RubberDuckWeb.Collaboration.EditorSupervisor,
      RubberDuckWeb.Collaboration.PresenceTracker,
      RubberDuckWeb.Collaboration.SharedSelections,
      RubberDuckWeb.Collaboration.SessionManager,
      RubberDuckWeb.Collaboration.Communication,
      # Project file watcher system
      RubberDuck.Projects.FileWatcher.Supervisor,
      # Multi-project watcher manager
      RubberDuck.Projects.WatcherManager,
      # File cache system
      RubberDuck.Projects.FileCache,
      # Enhanced cache system with statistics
      RubberDuck.Projects.CacheStats,
      RubberDuck.Projects.FileCacheEnhanced,
      # Registry for FileManagerWatcher
      {Registry, keys: :unique, name: RubberDuck.Projects.FileManagerWatcher.Registry},
      # FileManagerWatcher supervisor
      RubberDuck.Projects.FileManagerWatcher.Supervisor,
      # File collaboration system
      {Registry, keys: :unique, name: RubberDuck.CollaborationRegistry},
      RubberDuck.Projects.CollaborationSupervisor,
      # Web endpoint - start last
      RubberDuckWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :rubber_duck]}
      # Error boundary GenServer - started manually in tests
      # RubberDuck.ErrorBoundary
    ]

    opts = [strategy: :one_for_one, name: RubberDuck.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Log WebSocket endpoint information after startup
    log_websocket_info()

    result
  end

  defp log_websocket_info do
    port = Application.get_env(:rubber_duck, RubberDuckWeb.Endpoint)[:http][:port]
    host = Application.get_env(:rubber_duck, RubberDuckWeb.Endpoint)[:url][:host] || "localhost"

    Logger.info("""

    ============================================
    RubberDuck Server Started Successfully!
    ============================================
    HTTP Endpoint: http://#{host}:#{port}
    WebSocket Endpoint: ws://#{host}:#{port}/socket/websocket
    ============================================
    """)
  end
end
