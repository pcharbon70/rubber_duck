# Used by "mix format"
# Comprehensive formatting rules for RubberDuck project

[
  # Include all Elixir files in the project
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/*/seeds.exs",
    "priv/repo/migrations/*.exs"
  ],

  # Plugins for DSL formatting
  plugins: [Spark.Formatter],

  # Import dependencies for proper formatting of their macros/functions
  import_deps: [:ash_postgres, :reactor, :ash_phoenix, :ash],

  # Subdirectories with their own formatter configuration
  subdirectories: ["apps/*"],

  # Line length limit
  line_length: 120,

  # Custom local functions to not add parentheses to
  locals_without_parens: [
    # Ash DSL
    action: 1,
    action: 2,
    actions: 1,
    argument: 2,
    argument: 3,
    attribute: 2,
    attribute: 3,
    belongs_to: 2,
    belongs_to: 3,
    calculate: 2,
    calculate: 3,
    change: 1,
    change: 2,
    code_interface: 1,
    count: 2,
    count: 3,
    create: 1,
    create: 2,
    default: 1,
    default_context: 1,
    define: 2,
    define: 3,
    destroy: 1,
    destroy: 2,
    destination_attribute: 1,
    destination_attribute_on_join_resource: 1,
    filter: 1,
    first: 3,
    first: 4,
    from: 1,
    get: 2,
    get: 3,
    get?: 1,
    has_many: 2,
    has_many: 3,
    has_one: 2,
    has_one: 3,
    identity: 2,
    identity: 3,
    join_relationship: 1,
    list: 3,
    list: 4,
    load: 1,
    manual: 1,
    many_to_many: 2,
    many_to_many: 3,
    modify: 2,
    modify: 3,
    on: 1,
    policy: 1,
    prepare: 1,
    prepare: 2,
    primary?: 1,
    primary_key?: 1,
    private?: 1,
    read: 1,
    read: 2,
    relate: 2,
    relate: 3,
    relationship: 3,
    relationship: 4,
    required?: 1,
    resource: 1,
    soft?: 1,
    source_attribute: 1,
    source_attribute_on_join_resource: 1,
    through: 1,
    type: 1,
    update: 1,
    update: 2,
    upsert?: 1,
    validate: 1,
    validate: 2,

    # Phoenix DSL
    plug: 1,
    plug: 2,
    pipeline: 2,
    pipe_through: 1,
    action_fallback: 1,
    controller: 1,
    view: 1,
    layout: 1,

    # Phoenix LiveView
    live: 2,
    live: 3,
    live: 4,
    live_session: 2,
    live_session: 3,
    on_mount: 1,

    # Router helpers
    get: 2,
    get: 3,
    post: 2,
    post: 3,
    put: 2,
    put: 3,
    patch: 2,
    patch: 3,
    delete: 2,
    delete: 3,
    resources: 2,
    resources: 3,
    resources: 4,

    # Ecto
    field: 1,
    field: 2,
    field: 3,
    belongs_to: 2,
    belongs_to: 3,
    has_one: 2,
    has_one: 3,
    has_many: 2,
    has_many: 3,
    many_to_many: 2,
    many_to_many: 3,
    embeds_one: 2,
    embeds_one: 3,
    embeds_many: 2,
    embeds_many: 3,

    # Tests
    test: 1,
    test: 2,
    describe: 1,
    setup: 1,
    setup: 2,

    # Reactor DSL
    step: 1,
    step: 2,
    step: 3,
    return: 1,
    input: 1,
    input: 2,

    # Custom RubberDuck DSL (future use)
    engine: 1,
    engine: 2,
    capability: 1,
    capability: 2,
    memory_tier: 1,
    memory_tier: 2,
    context_strategy: 1,
    context_strategy: 2
  ],

  # Export the locals_without_parens for use in other projects
  export: [
    locals_without_parens: [
      engine: 1,
      engine: 2,
      capability: 1,
      capability: 2,
      memory_tier: 1,
      memory_tier: 2,
      context_strategy: 1,
      context_strategy: 2
    ]
  ]
]
