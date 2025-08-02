defmodule RubberDuck.Agents.AnalysisAgent do
  @moduledoc """
  Analysis Agent specialized in code analysis using Jido-compliant actions.

  The Analysis Agent is responsible for:
  - Performing semantic, style, and security analysis on code
  - Detecting patterns, complexity, and potential issues
  - Providing comprehensive code quality assessments
  - Generating actionable insights and recommendations
  - Supporting incremental analysis for performance

  ## Jido Compliance
  This agent has been fully migrated to use Jido.Agent patterns with action-based
  architecture. All business logic is extracted into reusable Actions.

  ## Capabilities

  - `:code_analysis` - General code analysis across multiple dimensions
  - `:security_analysis` - Security vulnerability detection
  - `:complexity_analysis` - Code complexity metrics and assessment
  - `:pattern_detection` - Identifying code patterns and anti-patterns
  - `:style_checking` - Code style and formatting analysis

  ## Signals

  The agent responds to the following signals:
  - `analysis.code.request` - Triggers comprehensive code analysis
  - `analysis.security.request` - Triggers security review
  - `analysis.complexity.request` - Triggers complexity analysis
  - `analysis.pattern.request` - Triggers pattern detection
  - `analysis.style.request` - Triggers style checking

  ## Example Usage

      # Via signal
      signal = %{
        "type" => "analysis.code.request",
        "data" => %{
          "file_path" => "lib/example.ex",
          "analysis_types" => ["semantic", "style", "security"]
        }
      }

      Jido.Signal.Bus.publish(signal)
  """

  use RubberDuck.Agents.BaseAgent,
    name: "analysis_agent",
    description: "Code analysis and quality assessment agent",
    schema: [
      analysis_cache: [
        type: :map,
        default: %{},
        doc: "Cache for analysis results"
      ],
      engines: [
        type: :map,
        default: %{},
        doc: "Analysis engine configurations"
      ],
      metrics: [
        type: :map,
        default: %{
          tasks_completed: 0,
          cache_hits: 0,
          cache_misses: 0,
          total_execution_time: 0
        },
        doc: "Agent performance metrics"
      ],
      last_activity: [
        type: {:or, [:datetime, :nil]},
        default: nil,
        doc: "Last activity timestamp"
      ],
      enable_self_correction: [
        type: :boolean,
        default: true,
        doc: "Enable self-correction for analysis results"
      ],
      cache_ttl_seconds: [
        type: :integer,
        default: 3600,
        doc: "Cache time-to-live in seconds"
      ],
      capabilities: [
        type: {:list, :atom},
        default: [
          :code_analysis,
          :security_analysis,
          :complexity_analysis,
          :pattern_detection,
          :style_checking
        ],
        doc: "Agent capabilities"
      ]
    ],
    actions: [
      RubberDuck.Jido.Actions.Analysis.CodeAnalysisAction,
      RubberDuck.Jido.Actions.Analysis.ComplexityAnalysisAction,
      RubberDuck.Jido.Actions.Analysis.PatternDetectionAction,
      RubberDuck.Jido.Actions.Analysis.SecurityReviewAction,
      RubberDuck.Jido.Actions.Analysis.StyleCheckAction
    ]

  
  require Logger

  # Signal-to-Action Mappings
  # This replaces the old handle_task callbacks with Jido signal routing
  
  @impl true
  def signal_mappings do
    %{
      "analysis.code.request" => {RubberDuck.Jido.Actions.Analysis.CodeAnalysisAction, :extract_code_params},
      "analysis.security.request" => {RubberDuck.Jido.Actions.Analysis.SecurityReviewAction, :extract_security_params},
      "analysis.complexity.request" => {RubberDuck.Jido.Actions.Analysis.ComplexityAnalysisAction, :extract_complexity_params},
      "analysis.pattern.request" => {RubberDuck.Jido.Actions.Analysis.PatternDetectionAction, :extract_pattern_params},
      "analysis.style.request" => {RubberDuck.Jido.Actions.Analysis.StyleCheckAction, :extract_style_params}
    }
  end
  
  # Parameter extraction functions for signal-to-action mapping
  
  def extract_code_params(%{"data" => data}) do
    %{
      file_path: data["file_path"],
      analysis_types: parse_analysis_types(data["analysis_types"]),
      enable_cache: Map.get(data, "enable_cache", true),
      apply_self_correction: Map.get(data, "apply_self_correction", true),
      include_metrics: Map.get(data, "include_metrics", true)
    }
  end
  
  def extract_security_params(%{"data" => data}) do
    %{
      file_paths: ensure_list(data["file_paths"]),
      vulnerability_types: parse_vulnerability_types(data["vulnerability_types"]),
      severity_threshold: parse_severity(data["severity_threshold"]),
      include_remediation: Map.get(data, "include_remediation", true),
      check_dependencies: Map.get(data, "check_dependencies", true)
    }
  end
  
  def extract_complexity_params(%{"data" => data}) do
    %{
      module_path: data["module_path"],
      metrics: parse_metrics(data["metrics"]),
      include_recommendations: Map.get(data, "include_recommendations", true),
      include_function_details: Map.get(data, "include_function_details", false)
    }
  end
  
  def extract_pattern_params(%{"data" => data}) do
    %{
      codebase_path: data["codebase_path"],
      pattern_types: parse_pattern_types(data["pattern_types"]),
      include_suggestions: Map.get(data, "include_suggestions", true),
      confidence_threshold: Map.get(data, "confidence_threshold", 0.7)
    }
  end
  
  def extract_style_params(%{"data" => data}) do
    %{
      file_paths: ensure_list(data["file_paths"]),
      style_rules: parse_style_rules(data["style_rules"]),
      detect_auto_fixable: Map.get(data, "detect_auto_fixable", true),
      check_formatting: Map.get(data, "check_formatting", true),
      max_line_length: Map.get(data, "max_line_length", 120)
    }
  end
  
  # Lifecycle hooks for Jido compliance
  
  @impl true
  def on_before_init(config) do
    # Initialize engines based on configuration
    engines = initialize_engines(config)
    
    # Merge engine configuration into initial state
    Map.put(config, :engines, engines)
  end
  
  @impl true
  def on_after_start(agent) do
    Logger.info("Analysis Agent started successfully", 
      name: agent.name,
      capabilities: agent.state.capabilities
    )
    agent
  end
  
  @impl true
  def on_before_stop(agent) do
    Logger.info("Analysis Agent stopping, cleaning up cache",
      cache_size: map_size(agent.state.analysis_cache)
    )
    agent
  end

  # Helper Functions
  # These are preserved for backward compatibility and utility

  defp initialize_engines(config) do
    engines = Map.get(config, :engines, [:semantic, :style, :security])

    Map.new(engines, fn engine_type ->
      {engine_type,
       %{
         module: get_engine_module(engine_type),
         config: Map.get(config, engine_type, %{})
       }}
    end)
  end

  defp get_engine_module(:semantic), do: RubberDuck.Analysis.Semantic
  defp get_engine_module(:style), do: RubberDuck.Analysis.Style
  defp get_engine_module(:security), do: RubberDuck.Analysis.Security
  
  # Parsing helper functions for signal parameter extraction
  
  defp parse_analysis_types(nil), do: [:semantic, :style, :security]
  defp parse_analysis_types(types) when is_list(types) do
    Enum.map(types, &String.to_atom/1)
  end
  defp parse_analysis_types(type) when is_binary(type) do
    [String.to_atom(type)]
  end
  
  defp parse_vulnerability_types(nil), do: [:all]
  defp parse_vulnerability_types("all"), do: [:all]
  defp parse_vulnerability_types(types) when is_list(types) do
    Enum.map(types, &String.to_atom/1)
  end
  
  defp parse_severity(nil), do: :low
  defp parse_severity(severity) when is_binary(severity) do
    String.to_atom(severity)
  end
  defp parse_severity(severity) when is_atom(severity), do: severity
  
  defp parse_metrics(nil), do: [:cyclomatic, :cognitive]
  defp parse_metrics(metrics) when is_list(metrics) do
    Enum.map(metrics, &String.to_atom/1)
  end
  
  defp parse_pattern_types(nil), do: [:all]
  defp parse_pattern_types(types) when is_list(types) do
    Enum.map(types, &String.to_atom/1)
  end
  
  defp parse_style_rules(nil), do: :default
  defp parse_style_rules(rules) when is_binary(rules) do
    String.to_atom(rules)
  end
  defp parse_style_rules(rules) when is_atom(rules), do: rules
  
  defp ensure_list(value) when is_list(value), do: value
  defp ensure_list(value), do: [value]
end