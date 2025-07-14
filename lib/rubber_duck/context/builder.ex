defmodule RubberDuck.Context.Builder do
  @moduledoc """
  Behavior for context building strategies.

  Each strategy implements a different approach to building context for LLM requests,
  such as Fill-in-the-Middle (FIM), Retrieval Augmented Generation (RAG), or
  long context windows.
  """

  @type context :: %{
          content: String.t(),
          metadata: map(),
          token_count: non_neg_integer(),
          strategy: atom(),
          sources: list(map()),
          instruction_context: map() | nil,
          instruction_system_prompt: String.t() | nil
        }

  @type options :: keyword()

  @doc """
  Builds context using the strategy's specific approach.

  ## Options
  - `:max_tokens` - Maximum tokens allowed in context
  - `:user_id` - User ID for personalization
  - `:session_id` - Session ID for recent context
  - `:query_type` - Type of query (e.g., :completion, :generation, :analysis)
  - `:project_path` - Project path for instruction loading
  - `:workspace_path` - Workspace path for instruction scoping
  - `:enable_instructions` - Whether to load and apply instructions (default: true)
  """
  @callback build(query :: String.t(), options :: options()) ::
              {:ok, context()} | {:error, term()}

  @doc """
  Returns the strategy name for identification.
  """
  @callback name() :: atom()

  @doc """
  Returns the types of queries this strategy is optimized for.
  """
  @callback supported_query_types() :: list(atom())

  @doc """
  Estimates the quality score for this strategy given a query.
  Returns a score between 0.0 and 1.0.
  """
  @callback estimate_quality(query :: String.t(), options :: options()) :: float()
end
