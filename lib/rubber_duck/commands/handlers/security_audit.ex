defmodule RubberDuck.Commands.Handlers.SecurityAudit do
  @moduledoc """
  Handler for security audit commands.
  
  Provides security audit functionality including reports,
  analysis, and configuration validation.
  """
  
  @behaviour RubberDuck.Commands.Handler
  
  alias RubberDuck.Commands.Command
  alias RubberDuck.Instructions.SecurityAuditTools
  
  @impl true
  def execute(%Command{name: :security_audit, args: args} = _command) do
    case Map.get(args, :subcommand) do
      "report" -> 
        opts = parse_report_options(args)
        generate_security_report(opts)
        
      "help" ->
        {:ok, format_help()}
        
      _ ->
        {:error, "Unknown security audit command. Use 'security audit help' for available commands."}
    end
  end
  
  @impl true
  def execute(%Command{name: :security_audit} = _command) do
    {:ok, format_help()}
  end
  
  @impl true
  def execute(_command) do
    {:error, "Invalid command for security audit handler"}
  end
  
  ## Private Functions
  
  defp generate_security_report(opts) do
    case SecurityAuditTools.generate_security_report(opts) do
      {:ok, report} ->
        format_security_report(report)
        
      {:error, reason} ->
        {:error, "Failed to generate security report: #{inspect(reason)}"}
    end
  end
  
  defp parse_report_options(args) do
    opts = []
    
    # Parse timeframe
    opts = case Map.get(args, :timeframe) do
      nil -> opts
      timeframe when is_binary(timeframe) -> 
        case Integer.parse(timeframe) do
          {hours, ""} -> Keyword.put(opts, :timeframe, hours)
          _ -> opts
        end
      timeframe when is_integer(timeframe) -> 
        Keyword.put(opts, :timeframe, timeframe)
      _ -> opts
    end
    
    # Parse user ID
    opts = case Map.get(args, :user) do
      nil -> opts
      user_id -> Keyword.put(opts, :user_id, user_id)
    end
    
    opts
  end
  
  defp format_security_report(report) do
    output = [
      "\n=== Security Report ===",
      "Generated: #{DateTime.to_string(report.generated_at)}",
      "Timeframe: #{report.timeframe}",
      "",
      "=== Summary ===",
      "Total Events: #{report.summary.total_events}",
      "Security Violations: #{report.summary.security_violations}",
      "Success Rate: #{Float.round(report.summary.success_rate, 2)}%",
      "",
      "=== Event Breakdown ==="
    ]
    
    breakdown = Enum.map(report.summary.event_breakdown, fn {type, count} ->
      "  #{type}: #{count}"
    end)
    
    output = output ++ breakdown
    
    output = if report.security_violations.total_violations > 0 do
      output ++ [
        "",
        "=== Security Violations ===",
        "Total Violations: #{report.security_violations.total_violations}"
      ]
    else
      output
    end
    
    output = if length(report.recommendations) > 0 do
      output ++ [
        "",
        "=== Recommendations ==="
      ] ++ Enum.map(report.recommendations, fn rec -> "  • #{rec}" end)
    else
      output
    end
    
    {:ok, Enum.join(output, "\n")}
  end
  
  defp format_help do
    """
    
    === Security Audit Commands ===
    
    security audit report [options]
      Generate a comprehensive security report
      Options:
        --timeframe <hours>  Timeframe for report (default: 24)
        --user <user_id>     Filter by specific user
    
    security audit help
      Show this help message
    
    Examples:
      security audit report --timeframe 48 --user user123
    """
  end
end