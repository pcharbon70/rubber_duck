defmodule RubberDuck.Jido.Actions.Analysis.StyleCheckAction do
  @moduledoc """
  Action for code style analysis and formatting checks.
  
  This action analyzes code files for style violations, categorizes them by
  severity, and identifies violations that can be automatically fixed.
  """
  
  use Jido.Action,
    name: "style_check",
    description: "Performs code style analysis and identifies formatting violations",
    schema: [
      file_paths: [
        type: {:list, :string},
        required: true,
        doc: "List of file paths to check for style violations"
      ],
      style_rules: [
        type: :atom,
        default: :default,
        doc: "Style rules to apply (e.g., :default, :strict, :relaxed)"
      ],
      task_id: [
        type: :string,
        default: nil,
        doc: "Task identifier for tracking"
      ]
    ]

  alias RubberDuck.Analysis.Style
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{file_paths: file_paths, style_rules: style_rules} = params
    
    Logger.info("Checking style for #{length(file_paths)} files")
    
    style_result = %{
      task_id: params.task_id,
      violations: [],
      summary: %{},
      auto_fixable: [],
      confidence: 0.95
    }
    
    # Check style for each file
    case check_files_style(file_paths, style_rules, agent, style_result) do
      {:ok, final_result} ->
        # Generate summary
        final_result_with_summary = %{
          final_result
          | summary: summarize_style_violations(final_result.violations)
        }
        
        # Update state and emit result
        with {:ok, _, %{agent: updated_agent}} <- update_metrics(agent),
             {:ok, _, %{agent: final_agent}} <- update_last_activity(updated_agent),
             {:ok, _} <- emit_style_result(final_agent, final_result_with_summary, params) do
          {:ok, final_result_with_summary, %{agent: final_agent}}
        end
        
      {:error, reason} ->
        Logger.error("Style check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions
  
  defp check_files_style(file_paths, style_rules, agent, initial_result) do
    try do
      final_result = file_paths
      |> Enum.reduce(initial_result, fn file_path, acc ->
        case check_file_style(file_path, style_rules, agent) do
          {:ok, violations} ->
            %{
              acc
              | violations: acc.violations ++ violations,
                auto_fixable: acc.auto_fixable ++ filter_auto_fixable(violations)
            }
          {:error, reason} ->
            Logger.warning("Failed to check style for #{file_path}: #{inspect(reason)}")
            acc
        end
      end)
      
      {:ok, final_result}
      
    rescue
      error ->
        {:error, "Style checking failed: #{Exception.message(error)}"}
    end
  end
  
  defp check_file_style(file_path, style_rules, agent) do
    engine_config = get_in(agent.state.engines, [:style, :config]) || %{}
    
    case Style.analyze(file_path, Map.put(engine_config, :rules, style_rules)) do
      {:ok, result} ->
        violations = Map.get(result, :violations, [])
        {:ok, violations}
        
      error ->
        error
    end
  end
  
  defp filter_auto_fixable(violations) do
    Enum.filter(violations, fn violation ->
      Map.get(violation, :auto_fixable, false)
    end)
  end
  
  defp summarize_style_violations(violations) do
    violations
    |> Enum.group_by(fn violation -> Map.get(violation, :rule, :unknown) end)
    |> Map.new(fn {rule, rule_violations} ->
      {rule, %{
        count: length(rule_violations),
        severity: get_most_severe(rule_violations),
        auto_fixable_count: Enum.count(rule_violations, &Map.get(&1, :auto_fixable, false)),
        locations: Enum.map(rule_violations, fn v ->
          "#{Map.get(v, :file, "unknown")}:#{Map.get(v, :line, 0)}"
        end) |> Enum.take(5) # Limit to first 5 locations
      }}
    end)
  end
  
  defp get_most_severe(violations) do
    severities = [:error, :warning, :info]
    
    violations
    |> Enum.map(fn v -> Map.get(v, :severity, :info) end)
    |> Enum.min_by(&Enum.find_index(severities, fn s -> s == &1 end), fn -> :info end)
  end
  
  # State management helpers
  
  defp update_metrics(agent) do
    current_metrics = agent.state.metrics
    updated_metrics = current_metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(:style_check, 1, &(&1 + 1))
    
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_last_activity(agent) do
    state_updates = %{last_activity: DateTime.utc_now()}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_style_result(agent, result, params) do
    signal_params = %{
      signal_type: "analysis.style.complete",
      data: %{
        task_id: params.task_id,
        result: result,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end