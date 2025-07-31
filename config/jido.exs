import Config

# Jido Framework Configuration
config :rubber_duck, :jido,
  # Agent supervision configuration
  agent_supervisor: [
    name: RubberDuck.Jido.Supervisor,
    strategy: :one_for_one,
    max_restarts: 3,
    max_seconds: 5
  ],

  # Jido native signal bus configuration
  signal_bus: [
    name: RubberDuck.SignalBus,
    # CloudEvents are handled natively by Jido.Signal
    # Middleware for signal processing
    middleware: [
      # Add middleware here if needed
    ]
  ],

  # Workflow engine configuration
  workflow_engine: [
    name: RubberDuck.Jido.WorkflowEngine,
    max_concurrent_workflows: 100,
    checkpoint_interval: :timer.seconds(30),
    # Workflow state persistence
    persistence: [
      enabled: true,
      adapter: :ets,
      table_name: :jido_workflow_state
    ]
  ],

  # Registry configuration
  registry: [
    name: RubberDuck.Jido.Registry,
    keys: :unique,
    partitions: System.schedulers_online()
  ],

  # Telemetry configuration
  telemetry: [
    enabled: true,
    prefix: [:rubber_duck, :jido],
    # Events to track
    events: [
      [:agent, :start],
      [:agent, :stop],
      [:signal, :emit],
      [:signal, :receive],
      [:workflow, :start],
      [:workflow, :complete],
      [:workflow, :error]
    ]
  ],

  # Development tools configuration
  dev_tools: [
    dashboard: [
      enabled: Mix.env() == :dev,
      port: 4001,
      interface: "localhost"
    ],
    introspection: [
      enabled: true,
      max_depth: 5
    ],
    debug: [
      log_signals: Mix.env() == :dev,
      log_state_changes: false
    ]
  ],

  # Agent defaults
  agent_defaults: [
    # Default timeout for agent operations
    timeout: :timer.seconds(30),
    # Default memory allocation per agent (in KB)
    memory_limit: 25,
    # Default message queue size
    mailbox_limit: 1000,
    # Restart strategy for individual agents
    restart: :transient,
    shutdown: :timer.seconds(5)
  ]

# Environment-specific configuration
if config_env() == :test do
  config :rubber_duck, :jido,
    agent_defaults: [
      timeout: :timer.seconds(5),
      memory_limit: 10,
      mailbox_limit: 100
    ],
    dev_tools: [
      dashboard: [enabled: false],
      debug: [log_signals: false]
    ]
end

if config_env() == :prod do
  config :rubber_duck, :jido,
    signal_bus: [
      # Production signal bus configuration
      # Persistence is handled by Jido.Signal.Bus natively
    ],
    workflow_engine: [
      persistence: [
        enabled: true,
        adapter: :postgres
      ]
    ],
    dev_tools: [
      dashboard: [enabled: false],
      debug: [
        log_signals: false,
        log_state_changes: false
      ]
    ]
end