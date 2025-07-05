defmodule RubberDuck.EngineSystem.Dsl do
  @moduledoc """
  The DSL extension for RubberDuck.EngineSystem.
  
  Defines the structure and entities available in the engine system DSL.
  """
  
  @engine %Spark.Dsl.Entity{
    name: :engine,
    describe: """
    Define an engine with its configuration.
    
    Each engine must have a unique name and a module that implements
    the `RubberDuck.Engine` behavior.
    """,
    target: RubberDuck.EngineSystem.Engine,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The unique name of the engine"
      ],
      module: [
        type: :atom,
        required: true,
        doc: "The module that implements the engine behavior"
      ],
      description: [
        type: :string,
        required: false,
        doc: "A description of what the engine does"
      ],
      priority: [
        type: :integer,
        required: false,
        default: 50,
        doc: "The priority of the engine (higher numbers run first)"
      ],
      timeout: [
        type: :timeout,
        required: false,
        default: 30_000,
        doc: "Maximum execution time in milliseconds"
      ],
      config: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Engine-specific configuration"
      ],
      pool_size: [
        type: :pos_integer,
        required: false,
        default: 1,
        doc: "Number of engine instances in the pool"
      ],
      max_overflow: [
        type: :non_neg_integer,
        required: false,
        default: 0,
        doc: "Maximum number of additional workers when pool is full"
      ],
      checkout_timeout: [
        type: :timeout,
        required: false,
        default: 5_000,
        doc: "Maximum time to wait for a worker from the pool"
      ]
    ]
  }
  
  @engines %Spark.Dsl.Section{
    name: :engines,
    describe: """
    Configure engines for the system.
    
    Engines are pluggable components that handle specific tasks.
    """,
    entities: [
      @engine
    ]
  }
  
  use Spark.Dsl.Extension,
    sections: [@engines],
    transformers: [
      RubberDuck.EngineSystem.Transformers.ValidateEngines
    ]
end