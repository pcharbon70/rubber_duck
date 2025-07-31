defmodule RubberDuck.Jido.Agents.CodeAnalysisAgent do
  @moduledoc """
  Code Analysis Agent for comprehensive code analysis using the Jido pattern.
  
  This agent performs comprehensive code analysis combining static analysis
  with LLM-enhanced insights. It handles both direct file analysis and
  conversational code analysis requests.
  
  ## Available Actions
  
  - `code_analysis_request` - Analyze a specific file
  - `conversation_analysis_request` - Analyze code within conversation context
  - `get_analysis_metrics` - Request current analysis metrics
  """

  use Jido.Agent,
    name: "code_analysis",
    description: "Performs comprehensive code analysis with static and LLM-enhanced insights",
    schema: [
      analysis_queue: [type: {:list, :map}, default: []],
      active_analyses: [type: :map, default: %{}],
      analysis_cache: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        files_analyzed: 0,
        conversations_analyzed: 0,
        total_issues: 0,
        analysis_time_ms: 0,
        cache_hits: 0,
        llm_enhancements: 0,
        cache_misses: 0
      }],
      analyzers: [type: {:list, :atom}, default: [:static, :security, :style]],
      llm_config: [type: :map, default: %{temperature: 0.3, max_tokens: 2000}],
      cache_ttl_ms: [type: :integer, default: 300_000] # 5 minutes
    ],
    actions: [
      RubberDuck.Jido.Actions.CodeAnalysis.CodeAnalysisRequestAction,
      RubberDuck.Jido.Actions.CodeAnalysis.ConversationAnalysisRequestAction,
      RubberDuck.Jido.Actions.CodeAnalysis.GetAnalysisMetricsAction
    ]

  require Logger

  @impl true
  def mount(agent) do
    Logger.info("Code Analysis Agent initialized", agent_id: agent.id)
    {:ok, agent}
  end
end