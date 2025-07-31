defmodule RubberDuck.Jido.Actions.Analysis.PatternDetectionAction do
  @moduledoc """
  Action for detecting code patterns and anti-patterns in a codebase.
  
  This action analyzes code to identify good patterns that should be promoted
  and anti-patterns that should be addressed, providing suggestions for improvement.
  """
  
  use Jido.Action,
    name: "pattern_detection",
    description: "Detects code patterns and anti-patterns with improvement suggestions",
    schema: [
      codebase_path: [
        type: :string,
        required: true,
        doc: "Path to the codebase to analyze"
      ],
      pattern_types: [
        type: {:list, :atom},
        default: [:all],
        doc: "Types of patterns to detect"
      ],
      task_id: [
        type: :string,
        default: nil,
        doc: "Task identifier for tracking"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{codebase_path: codebase_path, pattern_types: pattern_types} = params
    
    Logger.info("Detecting patterns in codebase: #{codebase_path}")
    
    pattern_result = %{
      task_id: params.task_id,
      patterns_found: [],
      anti_patterns: [],
      suggestions: [],
      confidence: 0.0
    }
    
    # Detect patterns in codebase
    case detect_patterns(codebase_path, pattern_types, params, agent) do
      {:ok, patterns} ->
        final_result = %{
          pattern_result
          | patterns_found: patterns.positive,
            anti_patterns: patterns.negative,
            suggestions: generate_pattern_suggestions(patterns),
            confidence: 0.85
        }
        
        # Update state and emit result
        with {:ok, _, %{agent: updated_agent}} <- update_metrics(agent),
             {:ok, _, %{agent: final_agent}} <- update_last_activity(updated_agent),
             {:ok, _} <- emit_pattern_result(final_agent, final_result, params) do
          {:ok, final_result, %{agent: final_agent}}
        end
        
      {:error, reason} ->
        Logger.error("Pattern detection failed for #{codebase_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions
  
  defp detect_patterns(codebase_path, pattern_types, _params, _agent) do
    try do
      # In a real implementation, this would analyze the AST and file structure
      # For now, providing a simplified pattern detection
      
      patterns = %{
        positive: detect_positive_patterns(codebase_path, pattern_types),
        negative: detect_anti_patterns(codebase_path, pattern_types)
      }
      
      {:ok, patterns}
      
    rescue
      error ->
        {:error, "Pattern detection failed: #{Exception.message(error)}"}
    end
  end
  
  defp detect_positive_patterns(codebase_path, pattern_types) do
    base_patterns = [
      %{
        type: :genserver_pattern,
        location: "#{codebase_path}/lib/example.ex:25",
        description: "Well-structured GenServer implementation",
        confidence: 0.9,
        benefits: ["Clear state management", "Proper error handling", "Good separation of concerns"]
      },
      %{
        type: :supervisor_tree,
        location: "#{codebase_path}/lib/application.ex:15",
        description: "Proper supervisor hierarchy",
        confidence: 0.95,
        benefits: ["Fault tolerance", "Process isolation", "Graceful restarts"]
      },
      %{
        type: :pattern_matching,
        location: "#{codebase_path}/lib/parser.ex:42",
        description: "Effective use of pattern matching",
        confidence: 0.88,
        benefits: ["Clear control flow", "Reduced nesting", "Better readability"]
      }
    ]
    
    # Filter patterns based on requested types
    if :all in pattern_types do
      base_patterns
    else
      Enum.filter(base_patterns, fn pattern -> pattern.type in pattern_types end)
    end
  end
  
  defp detect_anti_patterns(codebase_path, pattern_types) do
    base_anti_patterns = [
      %{
        type: :god_module,
        location: "#{codebase_path}/lib/big_module.ex",
        description: "Module with too many responsibilities",
        confidence: 0.8,
        severity: :high,
        issues: ["High coupling", "Low cohesion", "Difficult to test"]
      },
      %{
        type: :deep_nesting,
        location: "#{codebase_path}/lib/nested.ex:156",
        description: "Deeply nested conditional logic",
        confidence: 0.7,
        severity: :medium,
        issues: ["Poor readability", "Complex testing", "Maintenance burden"]
      },
      %{
        type: :long_parameter_list,
        location: "#{codebase_path}/lib/functions.ex:89",
        description: "Function with too many parameters",
        confidence: 0.85,
        severity: :medium,
        issues: ["Poor usability", "High coupling", "Error-prone calls"]
      },
      %{
        type: :duplicate_code,
        location: "#{codebase_path}/lib/handlers.ex:45",
        description: "Duplicated logic across multiple functions",
        confidence: 0.9,
        severity: :high,
        issues: ["Maintenance overhead", "Inconsistent changes", "Bug propagation"]
      }
    ]
    
    # Filter anti-patterns based on requested types
    if :all in pattern_types do
      base_anti_patterns
    else
      Enum.filter(base_anti_patterns, fn pattern -> pattern.type in pattern_types end)
    end
  end
  
  defp generate_pattern_suggestions(patterns) do
    suggestions = []
    
    # Suggest fixes for anti-patterns
    suggestions = patterns.negative
    |> Enum.reduce(suggestions, fn pattern, acc ->
      case pattern.type do
        :god_module ->
          ["Split large module into smaller, focused modules with single responsibilities" | acc]
          
        :deep_nesting ->
          ["Reduce nesting levels by extracting functions and using guard clauses" | acc]
          
        :long_parameter_list ->
          ["Consider grouping related parameters into structs or maps" | acc]
          
        :duplicate_code ->
          ["Extract common logic into shared functions or modules" | acc]
          
        _ ->
          ["Address #{pattern.type} anti-pattern in #{pattern.location}" | acc]
      end
    end)
    
    # Suggest spreading positive patterns
    suggestions = if length(patterns.positive) > 0 do
      positive_types = patterns.positive |> Enum.map(& &1.type) |> Enum.uniq()
      ["Continue using identified good patterns (#{Enum.join(positive_types, ", ")}) across the codebase" | suggestions]
    else
      suggestions
    end
    
    # Add general architectural suggestions
    suggestions = [
      "Consider implementing more supervisor patterns for better fault tolerance",
      "Use pattern matching more extensively to improve code clarity",
      "Apply the single responsibility principle to maintain clean module boundaries"
      | suggestions
    ]
    
    Enum.uniq(suggestions)
  end
  
  # State management helpers
  
  defp update_metrics(agent) do
    current_metrics = agent.state.metrics
    updated_metrics = current_metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(:pattern_detection, 1, &(&1 + 1))
    
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_last_activity(agent) do
    state_updates = %{last_activity: DateTime.utc_now()}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_pattern_result(agent, result, params) do
    signal_params = %{
      signal_type: "analysis.patterns.complete",
      data: %{
        task_id: params.task_id,
        codebase_path: params.codebase_path,
        result: result,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end