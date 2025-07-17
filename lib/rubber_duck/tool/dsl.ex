defmodule RubberDuck.Tool.Dsl do
  @moduledoc """
  Spark DSL extension for defining tools declaratively.
  
  This DSL provides sections for metadata, parameters, execution configuration,
  and security settings.
  """
  
  @parameter %Spark.Dsl.Entity{
    name: :parameter,
    describe: "Defines a parameter that the tool accepts",
    args: [:name],
    target: RubberDuck.Tool.Parameter,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the parameter"
      ],
      type: [
        type: {:in, [:string, :integer, :float, :boolean, :map, :list, :any]},
        required: true,
        doc: "The data type of the parameter"
      ],
      required: [
        type: :boolean,
        default: false,
        doc: "Whether this parameter is required"
      ],
      default: [
        type: :any,
        required: false,
        doc: "Default value if not provided"
      ],
      description: [
        type: :string,
        required: false,
        doc: "Human-readable description of the parameter"
      ],
      constraints: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Additional constraints like min/max, regex patterns, etc."
      ]
    ]
  }
  
  @execution %Spark.Dsl.Entity{
    name: :execution,
    describe: "Configuration for how the tool executes",
    args: [],
    target: RubberDuck.Tool.Execution,
    schema: [
      handler: [
        type: :any,
        required: true,
        doc: "Function that handles tool execution (params, context) -> {:ok, result} | {:error, reason}"
      ],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Execution timeout in milliseconds"
      ],
      async: [
        type: :boolean,
        default: false,
        doc: "Whether the tool can be executed asynchronously"
      ],
      retries: [
        type: :non_neg_integer,
        default: 0,
        doc: "Number of retry attempts on failure"
      ]
    ]
  }
  
  @security %Spark.Dsl.Entity{
    name: :security,
    describe: "Security configuration for the tool",
    args: [],
    target: RubberDuck.Tool.Security,
    schema: [
      sandbox: [
        type: {:in, [:none, :strict, :balanced, :relaxed]},
        default: :balanced,
        doc: "Sandboxing level for tool execution"
      ],
      capabilities: [
        type: {:list, :atom},
        default: [],
        doc: "Required system capabilities (e.g., :file_read, :network)"
      ],
      rate_limit: [
        type: :keyword_list,
        required: false,
        doc: "Rate limiting configuration (e.g., [per_minute: 10])"
      ],
      file_access: [
        type: {:list, :string},
        required: false,
        doc: "List of allowed file paths for sandbox execution"
      ],
      network_access: [
        type: :boolean,
        required: false,
        doc: "Whether network access is allowed in sandbox"
      ],
      allowed_modules: [
        type: {:list, :atom},
        required: false,
        doc: "List of allowed Elixir modules for sandbox execution"
      ],
      allowed_functions: [
        type: {:list, :atom},
        required: false,
        doc: "List of allowed function names for sandbox execution"
      ]
    ]
  }
  
  @tool %Spark.Dsl.Section{
    name: :tool,
    describe: """
    The tool section defines the tool's metadata, parameters, execution, and security configuration.
    """,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The unique name of the tool"
      ],
      description: [
        type: :string,
        required: false,
        doc: "A human-readable description of what the tool does"
      ],
      category: [
        type: :atom,
        required: false,
        doc: "The category this tool belongs to for organization"
      ],
      version: [
        type: :string,
        required: false,
        default: "1.0.0",
        doc: "Semantic version of the tool"
      ],
      tags: [
        type: {:list, :atom},
        required: false,
        default: [],
        doc: "Additional tags for categorization"
      ]
    ],
    entities: [
      @parameter,
      @execution,
      @security
    ]
  }
  
  @sections [@tool]
  
  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: [
      RubberDuck.Tool.Transformers.ValidateMetadata,
      RubberDuck.Tool.Transformers.BuildIntrospection
    ]
end