defmodule RubberDuck.Jido.Actions.Analysis.SecurityReviewAction do
  @moduledoc """
  Action for security-focused analysis of code files.
  
  This action analyzes files for security vulnerabilities, categorizes them by
  severity, and provides recommendations for addressing security issues.
  """
  
  use Jido.Action,
    name: "security_review",
    description: "Performs security vulnerability analysis on code files",
    schema: [
      file_paths: [
        type: {:list, :string},
        required: true,
        doc: "List of file paths to analyze for security issues"
      ],
      vulnerability_types: [
        type: :atom,
        default: :all,
        doc: "Types of vulnerabilities to check for"
      ],
      task_id: [
        type: :string,
        default: nil,
        doc: "Task identifier for tracking"
      ]
    ]

  alias RubberDuck.Analysis.Security
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{file_paths: file_paths, vulnerability_types: vulnerability_types} = params
    
    Logger.info("Starting security review for #{length(file_paths)} files")
    
    security_result = %{
      task_id: params.task_id,
      vulnerabilities: [],
      severity_summary: %{critical: 0, high: 0, medium: 0, low: 0},
      scanned_files: length(file_paths),
      timestamp: DateTime.utc_now()
    }
    
    # Analyze each file for security issues
    case analyze_files_for_security(file_paths, vulnerability_types, agent, security_result) do
      {:ok, final_result} ->
        # Add recommendations
        final_result_with_recommendations = Map.put(
          final_result,
          :recommendations,
          generate_security_recommendations(final_result.vulnerabilities)
        )
        
        # Update metrics and emit result
        with {:ok, _, %{agent: updated_agent}} <- update_metrics(agent),
             {:ok, _, %{agent: final_agent}} <- update_last_activity(updated_agent),
             {:ok, _} <- emit_security_result(final_agent, final_result_with_recommendations, params) do
          {:ok, final_result_with_recommendations, %{agent: final_agent}}
        end
        
      {:error, reason} ->
        Logger.error("Security review failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions
  
  defp analyze_files_for_security(file_paths, vulnerability_types, agent, initial_result) do
    try do
      final_result = file_paths
      |> Enum.reduce(initial_result, fn file_path, acc ->
        case analyze_file_security(file_path, vulnerability_types, agent) do
          {:ok, vulnerabilities} ->
            %{
              acc
              | vulnerabilities: acc.vulnerabilities ++ vulnerabilities,
                severity_summary: update_severity_summary(acc.severity_summary, vulnerabilities)
            }
          {:error, reason} ->
            Logger.warning("Failed to analyze #{file_path}: #{inspect(reason)}")
            acc
        end
      end)
      
      {:ok, final_result}
      
    rescue
      error ->
        {:error, "Security analysis failed: #{Exception.message(error)}"}
    end
  end
  
  defp analyze_file_security(file_path, vulnerability_types, agent) do
    engine_config = get_in(agent.state.engines, [:security, :config]) || %{}
    
    case Security.analyze(file_path, Map.put(engine_config, :vulnerability_types, vulnerability_types)) do
      {:ok, result} ->
        # Security.analyze returns issues, not vulnerabilities
        vulnerabilities = Map.get(result, :issues, [])
        {:ok, vulnerabilities}
        
      error ->
        error
    end
  end
  
  defp update_severity_summary(summary, vulnerabilities) do
    Enum.reduce(vulnerabilities, summary, fn vuln, acc ->
      severity = Map.get(vuln, :severity, :low)
      Map.update(acc, severity, 1, &(&1 + 1))
    end)
  end
  
  defp generate_security_recommendations(vulnerabilities) do
    vulnerabilities
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, vulns} ->
      %{
        type: type,
        count: length(vulns),
        recommendation: get_security_recommendation(type, length(vulns))
      }
    end)
  end
  
  defp get_security_recommendation(:sql_injection, _count) do
    "Use parameterized queries and avoid string concatenation in SQL"
  end
  
  defp get_security_recommendation(:hardcoded_secrets, _count) do
    "Move secrets to environment variables or secure vault"
  end
  
  defp get_security_recommendation(:xss_vulnerability, _count) do
    "Sanitize and escape user input before rendering in HTML"
  end
  
  defp get_security_recommendation(:path_traversal, _count) do
    "Validate and sanitize file paths, use allowlists when possible"
  end
  
  defp get_security_recommendation(:command_injection, _count) do
    "Avoid shell command execution with user input, use safe alternatives"
  end
  
  defp get_security_recommendation(_, _count) do
    "Review and address security vulnerabilities according to best practices"
  end
  
  # State management helpers
  
  defp update_metrics(agent) do
    current_metrics = agent.state.metrics
    updated_metrics = current_metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(:security_review, 1, &(&1 + 1))
    
    state_updates = %{metrics: updated_metrics}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp update_last_activity(agent) do
    state_updates = %{last_activity: DateTime.utc_now()}
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_security_result(agent, result, params) do
    signal_params = %{
      signal_type: "analysis.security.complete",
      data: %{
        task_id: params.task_id,
        result: result,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end