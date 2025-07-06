defmodule RubberDuck.CoT.Dsl do
  @moduledoc """
  DSL for defining Chain-of-Thought reasoning chains.
  """
  
  @step %Spark.Dsl.Entity{
    name: :step,
    describe: "Define a reasoning step",
    target: RubberDuck.CoT.Step,
    args: [:name],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of this reasoning step"
      ],
      prompt: [
        type: :string,
        required: true,
        doc: "The prompt template for this step"
      ],
      depends_on: [
        type: {:or, [:atom, {:list, :atom}]},
        doc: "Steps that must complete before this one"
      ],
      validates: [
        type: {:or, [:atom, {:list, :atom}]},
        doc: "Validation functions to run on the result"
      ],
      max_tokens: [
        type: :pos_integer,
        default: 1000,
        doc: "Maximum tokens for this step's response"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Temperature for this step's LLM call"
      ],
      retries: [
        type: :non_neg_integer,
        default: 2,
        doc: "Number of retries if validation fails"
      ],
      optional: [
        type: :boolean,
        default: false,
        doc: "Whether this step can be skipped"
      ]
    ]
  }
  
  @reasoning_chain %Spark.Dsl.Section{
    name: :reasoning_chain,
    describe: "Configure the chain-of-thought reasoning process",
    entities: [@step],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of this reasoning chain"
      ],
      description: [
        type: :string,
        doc: "Description of what this reasoning chain does"
      ],
      max_steps: [
        type: :pos_integer,
        default: 10,
        doc: "Maximum number of reasoning steps allowed"
      ],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Timeout for the entire reasoning chain in milliseconds"
      ],
      template: [
        type: {:in, [:default, :analytical, :creative, :troubleshooting, :custom]},
        default: :default,
        doc: "The reasoning template to use"
      ],
      cache_ttl: [
        type: :pos_integer,
        default: 900,
        doc: "Cache TTL in seconds"
      ]
    ]
  }
  
  @sections [@reasoning_chain]
  
  use Spark.Dsl.Extension, 
    sections: @sections
end