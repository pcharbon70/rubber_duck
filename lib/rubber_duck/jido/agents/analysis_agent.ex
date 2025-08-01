defmodule RubberDuck.Jido.Agents.AnalysisAgent do
  @moduledoc """
  Analysis Agent for comprehensive code analysis using the Jido pattern.

  The Analysis Agent is responsible for:
  - Performing semantic, style, and security analysis on code
  - Detecting patterns, complexity, and potential issues
  - Providing comprehensive code quality assessments
  - Generating actionable insights and recommendations
  - Supporting incremental analysis for performance

  ## Available Actions

  - `analyze_code` - General code analysis across multiple dimensions
  - `security_review` - Security vulnerability detection
  - `complexity_analysis` - Code complexity metrics and assessment
  - `pattern_detection` - Identifying code patterns and anti-patterns
  - `style_check` - Code style and formatting analysis
  """

  use Jido.Agent,
    name: "analysis",
    description: "Comprehensive code analysis with semantic, style, and security checks",
    schema: [
      analysis_cache: [type: :map, default: %{}],
      engines: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        tasks_completed: 0,
        analyze_code: 0,
        analyze_code_cached: 0,
        security_review: 0,
        complexity_analysis: 0,
        pattern_detection: 0,
        style_check: 0,
        total_execution_time: 0,
        cache_hits: 0,
        cache_misses: 0
      }],
      last_activity: [type: :utc_datetime, default: nil],
      config: [type: :map, default: %{}]
    ],
    actions: [
      RubberDuck.Jido.Actions.Analysis.AnalyzeCodeAction,
      RubberDuck.Jido.Actions.Analysis.SecurityReviewAction,
      RubberDuck.Jido.Actions.Analysis.ComplexityAnalysisAction,
      RubberDuck.Jido.Actions.Analysis.PatternDetectionAction,
      RubberDuck.Jido.Actions.Analysis.StyleCheckAction
    ]

  require Logger

  def mount(agent) do
    # Initialize engines based on config
    engines = initialize_engines(agent.state.config)
    
    # Update state with initialized engines and set last activity
    updated_state = agent.state
    |> Map.put(:engines, engines)
    |> Map.put(:last_activity, DateTime.utc_now())
    
    Logger.info("Analysis Agent initialized", agent_id: agent.id)
    
    {:ok, %{agent | state: updated_state}}
  end

  # Helper Functions

  defp initialize_engines(config) do
    engines = Map.get(config, :engines, [:semantic, :style, :security])

    Map.new(engines, fn engine_type ->
      {engine_type, %{
        module: get_engine_module(engine_type),
        config: Map.get(config, engine_type, %{})
      }}
    end)
  end

  defp get_engine_module(:semantic), do: RubberDuck.Analysis.Semantic
  defp get_engine_module(:style), do: RubberDuck.Analysis.Style
  defp get_engine_module(:security), do: RubberDuck.Analysis.Security
end