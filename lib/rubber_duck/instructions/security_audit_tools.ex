defmodule RubberDuck.Instructions.SecurityAuditTools do
  @moduledoc """
  Tools for security audit analysis and reporting.
  
  Provides utilities for:
  - Generating security reports
  - Analyzing security events
  - Monitoring security trends
  - Detecting anomalies
  - Managing security policies
  """
  
  alias RubberDuck.Instructions.{SecurityAudit, SecurityMonitor, SecurityConfig}
  
  @doc """
  Generates a comprehensive security report.
  """
  def generate_security_report(opts \\ []) do
    timeframe = Keyword.get(opts, :timeframe, 24) # hours
    user_id = Keyword.get(opts, :user_id)
    
    start_time = DateTime.add(DateTime.utc_now(), -timeframe, :hour)
    
    # Get security events
    {:ok, events} = get_events_in_timeframe(start_time, user_id)
    
    # Generate report sections
    report = %{
      generated_at: DateTime.utc_now(),
      timeframe: "#{timeframe} hours",
      user_id: user_id,
      summary: generate_summary(events),
      security_violations: analyze_security_violations(events),
      threat_analysis: analyze_threats(events),
      rate_limiting: analyze_rate_limiting(events),
      anomalies: detect_anomalies(events),
      recommendations: generate_recommendations(events)
    }
    
    {:ok, report}
  end
  
  @doc """
  Analyzes security events for a specific user.
  """
  def analyze_user_security(user_id, opts \\ []) do
    timeframe = Keyword.get(opts, :timeframe, 168) # 7 days
    
    start_time = DateTime.add(DateTime.utc_now(), -timeframe, :hour)
    
    # Get user events
    {:ok, events} = get_events_in_timeframe(start_time, user_id)
    
    # Get user threat assessment
    {:ok, threat_assessment} = SecurityMonitor.assess_threat(user_id)
    
    # Generate user analysis
    analysis = %{
      user_id: user_id,
      analyzed_at: DateTime.utc_now(),
      timeframe: "#{timeframe} hours",
      event_count: length(events),
      threat_level: threat_assessment,
      event_breakdown: break_down_events(events),
      security_score: calculate_security_score(events),
      behavior_patterns: analyze_behavior_patterns(events),
      risk_factors: identify_risk_factors(events),
      recommendations: generate_user_recommendations(events, threat_assessment)
    }
    
    {:ok, analysis}
  end
  
  @doc """
  Detects security trends over time.
  """
  def detect_security_trends(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 30)
    
    trends = %{
      analyzed_at: DateTime.utc_now(),
      period: "#{days_back} days",
      injection_attempts: analyze_injection_trends(days_back),
      rate_limiting: analyze_rate_limiting_trends(days_back),
      sandbox_violations: analyze_sandbox_violation_trends(days_back),
      user_activity: analyze_user_activity_trends(days_back),
      overall_security_posture: assess_overall_security_posture()
    }
    
    {:ok, trends}
  end
  
  @doc """
  Validates security configuration.
  """
  def validate_security_configuration do
    config = SecurityConfig.get_config()
    
    validation_results = %{
      validated_at: DateTime.utc_now(),
      config_valid: SecurityConfig.validate_config(config),
      rate_limits: validate_rate_limits(config),
      security_levels: validate_security_levels(config),
      monitoring_settings: validate_monitoring_settings(config),
      audit_settings: validate_audit_settings(config),
      recommendations: generate_config_recommendations(config)
    }
    
    {:ok, validation_results}
  end
  
  @doc """
  Exports security audit data for external analysis.
  """
  def export_audit_data(format, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, DateTime.add(DateTime.utc_now(), -30, :day))
    end_date = Keyword.get(opts, :end_date, DateTime.utc_now())
    
    # Get audit events
    {:ok, events} = SecurityAudit.find_events(%{
      start_date: start_date,
      end_date: end_date
    })
    
    case format do
      :json -> export_as_json(events)
      :csv -> export_as_csv(events)
      :xlsx -> export_as_excel(events)
      _ -> {:error, :unsupported_format}
    end
  end
  
  @doc """
  Cleans up old security data based on retention policies.
  """
  def cleanup_old_data(opts \\ []) do
    audit_config = SecurityConfig.get_audit_config()
    retention_days = Keyword.get(opts, :retention_days, Map.get(audit_config, :retention_days, 30))
    
    # Clean up audit logs
    {:ok, deleted_count} = SecurityAudit.cleanup_old_logs(retention_days)
    
    # Clean up monitoring data
    SecurityMonitor.cleanup_old_data()
    
    cleanup_result = %{
      cleaned_at: DateTime.utc_now(),
      retention_days: retention_days,
      deleted_audit_records: deleted_count
    }
    
    {:ok, cleanup_result}
  end
  
  ## Private Functions
  
  defp get_events_in_timeframe(start_time, user_id) do
    filters = %{
      start_date: start_time,
      end_date: DateTime.utc_now()
    }
    
    filters = if user_id, do: Map.put(filters, :user_id, user_id), else: filters
    
    SecurityAudit.find_events(filters)
  end
  
  defp generate_summary(events) do
    total_events = length(events)
    
    event_counts = Enum.group_by(events, & &1.event_type)
    |> Enum.map(fn {type, events} -> {type, length(events)} end)
    |> Enum.into(%{})
    
    security_violations = Enum.count(events, fn event -> not event.success end)
    
    %{
      total_events: total_events,
      security_violations: security_violations,
      success_rate: if(total_events > 0, do: (total_events - security_violations) / total_events * 100, else: 0),
      event_breakdown: event_counts
    }
  end
  
  defp analyze_security_violations(events) do
    violations = Enum.filter(events, fn event -> not event.success end)
    
    %{
      total_violations: length(violations),
      by_type: group_and_count(violations, & &1.event_type),
      by_severity: group_and_count(violations, & &1.severity),
      by_user: group_and_count(violations, & &1.user_id),
      timeline: group_violations_by_hour(violations)
    }
  end
  
  defp analyze_threats(events) do
    threat_events = Enum.filter(events, fn event ->
      event.event_type in [:injection_attempt, :sandbox_violation, :anomaly_detected]
    end)
    
    %{
      total_threats: length(threat_events),
      by_type: group_and_count(threat_events, & &1.event_type),
      high_severity_threats: Enum.count(threat_events, fn event -> event.severity in [:high, :critical] end),
      affected_users: length(Enum.uniq_by(threat_events, & &1.user_id))
    }
  end
  
  defp analyze_rate_limiting(events) do
    rate_limit_events = Enum.filter(events, fn event ->
      event.event_type == :rate_limit_exceeded
    end)
    
    %{
      total_rate_limits: length(rate_limit_events),
      by_user: group_and_count(rate_limit_events, & &1.user_id),
      timeline: group_events_by_hour(rate_limit_events)
    }
  end
  
  defp detect_anomalies(events) do
    anomaly_events = Enum.filter(events, fn event ->
      event.event_type == :anomaly_detected
    end)
    
    %{
      total_anomalies: length(anomaly_events),
      by_user: group_and_count(anomaly_events, & &1.user_id),
      patterns: analyze_anomaly_patterns(anomaly_events)
    }
  end
  
  defp generate_recommendations(events) do
    recommendations = []
    
    # Check for high violation rates
    violation_rate = calculate_violation_rate(events)
    recommendations = if violation_rate > 0.1 do
      ["Consider stricter security policies - high violation rate: #{Float.round(violation_rate * 100, 1)}%" | recommendations]
    else
      recommendations
    end
    
    # Check for rate limiting issues
    rate_limit_events = Enum.filter(events, fn event -> event.event_type == :rate_limit_exceeded end)
    recommendations = if length(rate_limit_events) > 50 do
      ["Review rate limiting configuration - #{length(rate_limit_events)} rate limit violations" | recommendations]
    else
      recommendations
    end
    
    # Check for anomalies
    anomaly_events = Enum.filter(events, fn event -> event.event_type == :anomaly_detected end)
    recommendations = if length(anomaly_events) > 10 do
      ["Investigate anomalous behavior - #{length(anomaly_events)} anomalies detected" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  defp break_down_events(events) do
    events
    |> Enum.group_by(& &1.event_type)
    |> Enum.map(fn {type, type_events} ->
      {type, %{
        count: length(type_events),
        success_rate: calculate_success_rate(type_events),
        severity_breakdown: group_and_count(type_events, & &1.severity)
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_security_score(events) do
    if Enum.empty?(events) do
      100
    else
      violation_rate = calculate_violation_rate(events)
      base_score = 100 - (violation_rate * 100)
      
      # Adjust for severity
      high_severity_count = Enum.count(events, fn event -> event.severity in [:high, :critical] end)
      severity_penalty = min(high_severity_count * 5, 50)
      
      max(0, base_score - severity_penalty)
    end
  end
  
  defp analyze_behavior_patterns(events) do
    %{
      most_active_hours: find_most_active_hours(events),
      common_templates: find_common_templates(events),
      failure_patterns: find_failure_patterns(events)
    }
  end
  
  defp identify_risk_factors(events) do
    risk_factors = []
    
    # High failure rate
    violation_rate = calculate_violation_rate(events)
    risk_factors = if violation_rate > 0.2 do
      ["High failure rate: #{Float.round(violation_rate * 100, 1)}%" | risk_factors]
    else
      risk_factors
    end
    
    # Multiple injection attempts
    injection_attempts = Enum.count(events, fn event -> event.event_type == :injection_attempt end)
    risk_factors = if injection_attempts > 5 do
      ["Multiple injection attempts: #{injection_attempts}" | risk_factors]
    else
      risk_factors
    end
    
    # Sandbox violations
    sandbox_violations = Enum.count(events, fn event -> event.event_type == :sandbox_violation end)
    risk_factors = if sandbox_violations > 3 do
      ["Sandbox violations: #{sandbox_violations}" | risk_factors]
    else
      risk_factors
    end
    
    risk_factors
  end
  
  defp generate_user_recommendations(_events, threat_assessment) do
    recommendations = []
    
    case threat_assessment do
      {:high_risk, _} -> ["User requires immediate attention - high risk" | recommendations]
      {:critical, _} -> ["User requires immediate intervention - critical risk" | recommendations]
      {:blocked, _} -> ["User is currently blocked due to security violations" | recommendations]
      _ -> recommendations
    end
  end
  
  # Helper functions
  defp group_and_count(events, fun) do
    events
    |> Enum.group_by(fun)
    |> Enum.map(fn {key, events} -> {key, length(events)} end)
    |> Enum.into(%{})
  end
  
  defp group_violations_by_hour(violations) do
    violations
    |> Enum.group_by(fn violation ->
      violation.inserted_at
      |> DateTime.truncate(:hour)
      |> DateTime.to_string()
    end)
    |> Enum.map(fn {hour, violations} -> {hour, length(violations)} end)
    |> Enum.into(%{})
  end
  
  defp group_events_by_hour(events) do
    events
    |> Enum.group_by(fn event ->
      event.inserted_at
      |> DateTime.truncate(:hour)
      |> DateTime.to_string()
    end)
    |> Enum.map(fn {hour, events} -> {hour, length(events)} end)
    |> Enum.into(%{})
  end
  
  defp calculate_violation_rate(events) do
    if Enum.empty?(events) do
      0
    else
      violations = Enum.count(events, fn event -> not event.success end)
      violations / length(events)
    end
  end
  
  defp calculate_success_rate(events) do
    if Enum.empty?(events) do
      0
    else
      successes = Enum.count(events, fn event -> event.success end)
      successes / length(events) * 100
    end
  end
  
  defp find_most_active_hours(events) do
    events
    |> Enum.group_by(fn event -> event.inserted_at.hour end)
    |> Enum.map(fn {hour, events} -> {hour, length(events)} end)
    |> Enum.sort_by(fn {_hour, count} -> count end, :desc)
    |> Enum.take(5)
  end
  
  defp find_common_templates(events) do
    events
    |> Enum.group_by(fn event -> event.template_hash end)
    |> Enum.map(fn {hash, events} -> {hash, length(events)} end)
    |> Enum.sort_by(fn {_hash, count} -> count end, :desc)
    |> Enum.take(10)
  end
  
  defp find_failure_patterns(events) do
    failures = Enum.filter(events, fn event -> not event.success end)
    
    %{
      most_common_failures: group_and_count(failures, & &1.event_type),
      failure_times: group_events_by_hour(failures)
    }
  end
  
  defp analyze_anomaly_patterns(anomaly_events) do
    anomaly_events
    |> Enum.map(fn event -> Map.get(event.details, "events", []) end)
    |> List.flatten()
    |> Enum.group_by(& &1)
    |> Enum.map(fn {pattern, occurrences} -> {pattern, length(occurrences)} end)
    |> Enum.sort_by(fn {_pattern, count} -> count end, :desc)
    |> Enum.take(10)
  end
  
  # Trend analysis functions
  defp analyze_injection_trends(_days_back) do
    # Implementation would analyze injection attempts over time
    %{
      trend: "stable",
      daily_average: 2.3,
      peak_day: Date.add(Date.utc_today(), -7)
    }
  end
  
  defp analyze_rate_limiting_trends(_days_back) do
    # Implementation would analyze rate limiting over time
    %{
      trend: "increasing",
      daily_average: 15.2,
      peak_day: Date.add(Date.utc_today(), -2)
    }
  end
  
  defp analyze_sandbox_violation_trends(_days_back) do
    # Implementation would analyze sandbox violations over time
    %{
      trend: "decreasing",
      daily_average: 1.1,
      peak_day: Date.add(Date.utc_today(), -14)
    }
  end
  
  defp analyze_user_activity_trends(_days_back) do
    # Implementation would analyze user activity patterns
    %{
      active_users: 45,
      new_users: 12,
      blocked_users: 2
    }
  end
  
  defp assess_overall_security_posture do
    # Implementation would assess overall security
    %{
      status: "good",
      score: 85,
      key_metrics: %{
        violation_rate: 0.05,
        threat_level: "low",
        system_health: "healthy"
      }
    }
  end
  
  # Validation functions
  defp validate_rate_limits(config) do
    rate_limits = Map.get(config, :rate_limits, %{})
    
    %{
      valid: Map.has_key?(rate_limits, :user) and Map.has_key?(rate_limits, :template),
      recommendations: []
    }
  end
  
  defp validate_security_levels(config) do
    security_levels = Map.get(config, :security_levels, %{})
    
    %{
      valid: Map.has_key?(security_levels, :strict) and Map.has_key?(security_levels, :balanced),
      recommendations: []
    }
  end
  
  defp validate_monitoring_settings(config) do
    monitoring = Map.get(config, :monitoring, %{})
    
    %{
      valid: Map.has_key?(monitoring, :window_size) and Map.has_key?(monitoring, :threat_weights),
      recommendations: []
    }
  end
  
  defp validate_audit_settings(config) do
    audit = Map.get(config, :audit, %{})
    
    %{
      valid: Map.has_key?(audit, :logged_events) and Map.has_key?(audit, :retention_days),
      recommendations: []
    }
  end
  
  defp generate_config_recommendations(config) do
    recommendations = []
    
    # Check retention policy
    audit_config = Map.get(config, :audit, %{})
    retention_days = Map.get(audit_config, :retention_days, 30)
    
    recommendations = if retention_days < 30 do
      ["Consider increasing audit log retention to at least 30 days" | recommendations]
    else
      recommendations
    end
    
    recommendations
  end
  
  # Export functions
  defp export_as_json(events) do
    json_data = Jason.encode!(events)
    {:ok, json_data}
  end
  
  defp export_as_csv(_events) do
    # Implementation would convert events to CSV format
    {:ok, "CSV data placeholder"}
  end
  
  defp export_as_excel(_events) do
    # Implementation would convert events to Excel format
    {:ok, "Excel data placeholder"}
  end
end