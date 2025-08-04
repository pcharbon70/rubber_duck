defmodule RubberDuck.Tools.Agents.CVEAnalyzerAgent do
  @moduledoc """
  Agent for comprehensive CVE vulnerability analysis across multiple package registries.
  
  Provides advanced orchestration of CVE checking with features like:
  - Multi-registry vulnerability scanning
  - Batch analysis of dependencies
  - Vulnerability trend analysis
  - Security advisory generation
  - Automated patch recommendations
  - Compliance reporting
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :cve_checker,
    name: "cve_analyzer_agent",
    description: "Analyzes CVE vulnerabilities across dependency chains"
  
  # Additional actions for CVE analysis
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchScanAction,
      __MODULE__.AnalyzeTrendsAction,
      __MODULE__.GenerateAdvisoryAction,
      __MODULE__.CompareScansAction,
      __MODULE__.GenerateComplianceReportAction,
      __MODULE__.MonitorVulnerabilitiesAction,
      __MODULE__.GeneratePatchPlanAction
    ]
  end
  
  # Handle custom signals
  @impl true
  def handle_tool_signal(state, signal) do
    case signal["type"] do
      "batch_scan" ->
        {:ok, state, {:cmd, __MODULE__.BatchScanAction, signal["data"]}}
        
      "analyze_trends" ->
        {:ok, state, {:cmd, __MODULE__.AnalyzeTrendsAction, signal["data"]}}
        
      "generate_advisory" ->
        {:ok, state, {:cmd, __MODULE__.GenerateAdvisoryAction, signal["data"]}}
        
      "compare_scans" ->
        {:ok, state, {:cmd, __MODULE__.CompareScansAction, signal["data"]}}
        
      "generate_compliance" ->
        {:ok, state, {:cmd, __MODULE__.GenerateComplianceReportAction, signal["data"]}}
        
      "monitor_vulnerabilities" ->
        {:ok, state, {:cmd, __MODULE__.MonitorVulnerabilitiesAction, signal["data"]}}
        
      "generate_patch_plan" ->
        {:ok, state, {:cmd, __MODULE__.GeneratePatchPlanAction, signal["data"]}}
        
      _ ->
        # Let BaseToolAgent handle standard signals
        super(state, signal)
    end
  end
  
  # Initialize agent state
  def init_state(base_state) do
    Map.merge(base_state, %{
      scan_history: [],
      vulnerability_trends: %{},
      known_vulnerabilities: %{},
      compliance_policies: %{},
      monitoring_config: %{
        alert_thresholds: %{
          critical: 0,
          high: 2,
          medium: 5
        },
        scan_interval: :daily
      },
      patch_history: []
    })
  end
  
  # Handle action results for state updates
  def handle_action_result(state, action, result, metadata) do
    case action do
      __MODULE__.BatchScanAction ->
        case result do
          {:ok, scan_results} ->
            updated_state = state
            |> add_to_scan_history(scan_results, metadata)
            |> update_vulnerability_trends(scan_results)
            |> check_monitoring_alerts(scan_results)
            
            {:ok, updated_state}
            
          _error -> 
            {:ok, state}
        end
        
      __MODULE__.AnalyzeTrendsAction ->
        case result do
          {:ok, trends} ->
            {:ok, put_in(state.vulnerability_trends, trends)}
          _ ->
            {:ok, state}
        end
        
      __MODULE__.GeneratePatchPlanAction ->
        case result do
          {:ok, patch_plan} ->
            {:ok, %{state | patch_history: [patch_plan | state.patch_history]}}
          _ ->
            {:ok, state}
        end
        
      _ ->
        # Let BaseToolAgent handle standard results
        super(state, action, result, metadata)
    end
  end
  
  # Custom actions
  
  defmodule BatchScanAction do
    @moduledoc """
    Scans multiple projects or dependency files in batch.
    """
    use Jido.Action, name: "batch_scan"
    
    def parameter_schema do
      %{
        projects: [type: {:list, :map}, required: true, doc: "List of projects to scan"],
        scan_options: [type: :map, doc: "Common scan options for all projects"],
        parallel: [type: :boolean, default: true, doc: "Run scans in parallel"],
        aggregate_results: [type: :boolean, default: true, doc: "Aggregate results across projects"]
      }
    end
    
    @impl true
    def run(params, context) do
      results = if params.parallel do
        scan_projects_parallel(params.projects, params.scan_options, context)
      else
        scan_projects_sequential(params.projects, params.scan_options, context)
      end
      
      final_results = if params.aggregate_results do
        aggregate_scan_results(results)
      else
        results
      end
      
      {:ok, final_results}
    end
    
    defp scan_projects_parallel(projects, options, context) do
      projects
      |> Task.async_stream(fn project ->
        scan_single_project(project, options, context)
      end, max_concurrency: 5, timeout: 30_000)
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {:error, :timeout}
      end)
    end
    
    defp scan_projects_sequential(projects, options, context) do
      Enum.map(projects, &scan_single_project(&1, options, context))
    end
    
    defp scan_single_project(project, options, _context) do
      # Use CVE checker tool
      tool_params = Map.merge(options, %{
        dependencies: project.dependencies
      })
      
      case RubberDuck.Tools.CVEChecker.execute(tool_params, %{}) do
        {:ok, result} ->
          %{
            project: project.name,
            scan_result: result.result,
            timestamp: DateTime.utc_now()
          }
        {:error, reason} ->
          %{
            project: project.name,
            error: reason,
            timestamp: DateTime.utc_now()
          }
      end
    end
    
    defp aggregate_scan_results(results) do
      %{
        total_projects: length(results),
        successful_scans: Enum.count(results, &(!Map.has_key?(&1, :error))),
        total_vulnerabilities: aggregate_vulnerabilities(results),
        summary_by_severity: aggregate_by_severity(results),
        affected_projects: get_affected_projects(results),
        scan_results: results
      }
    end
    
    defp aggregate_vulnerabilities(results) do
      results
      |> Enum.filter(&Map.has_key?(&1, :scan_result))
      |> Enum.flat_map(& &1.scan_result.vulnerabilities)
      |> Enum.uniq_by(& &1.cve_id)
    end
    
    defp aggregate_by_severity(results) do
      results
      |> Enum.filter(&Map.has_key?(&1, :scan_result))
      |> Enum.flat_map(& &1.scan_result.vulnerabilities)
      |> Enum.group_by(& &1.severity)
      |> Enum.map(fn {severity, vulns} -> {severity, length(vulns)} end)
      |> Map.new()
    end
    
    defp get_affected_projects(results) do
      results
      |> Enum.filter(fn r ->
        Map.has_key?(r, :scan_result) && length(r.scan_result.vulnerabilities) > 0
      end)
      |> Enum.map(& &1.project)
    end
  end
  
  defmodule AnalyzeTrendsAction do
    @moduledoc """
    Analyzes vulnerability trends over time.
    """
    use Jido.Action, name: "analyze_trends"
    
    def parameter_schema do
      %{
        time_period: [type: :string, default: "30d", doc: "Time period to analyze"],
        group_by: [type: :string, default: "severity", doc: "Group trends by (severity, package, date)"],
        include_resolved: [type: :boolean, default: false, doc: "Include resolved vulnerabilities"]
      }
    end
    
    @impl true
    def run(params, context) do
      scan_history = context.agent.state.scan_history
      
      trends = analyze_trends(
        scan_history,
        params.time_period,
        params.group_by,
        params.include_resolved
      )
      
      {:ok, trends}
    end
    
    defp analyze_trends(history, period, group_by, _include_resolved) do
      filtered_history = filter_by_period(history, period)
      
      %{
        period: period,
        data_points: length(filtered_history),
        trends: calculate_trends(filtered_history, group_by),
        summary: generate_trend_summary(filtered_history),
        predictions: predict_future_trends(filtered_history)
      }
    end
    
    defp filter_by_period(history, period) do
      cutoff_date = calculate_cutoff_date(period)
      
      Enum.filter(history, fn scan ->
        DateTime.compare(scan.timestamp, cutoff_date) == :gt
      end)
    end
    
    defp calculate_cutoff_date("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
    defp calculate_cutoff_date("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
    defp calculate_cutoff_date("90d"), do: DateTime.add(DateTime.utc_now(), -90, :day)
    defp calculate_cutoff_date(_), do: DateTime.add(DateTime.utc_now(), -30, :day)
    
    defp calculate_trends(history, "severity") do
      history
      |> Enum.map(fn scan ->
        severity_counts = scan.scan_result.summary
        %{
          timestamp: scan.timestamp,
          critical: severity_counts[:critical] || 0,
          high: severity_counts[:high] || 0,
          medium: severity_counts[:medium] || 0,
          low: severity_counts[:low] || 0
        }
      end)
    end
    
    defp calculate_trends(history, "package") do
      history
      |> Enum.flat_map(fn scan ->
        scan.scan_result.vulnerabilities
        |> Enum.group_by(& &1.package)
        |> Enum.map(fn {package, vulns} ->
          %{
            timestamp: scan.timestamp,
            package: package,
            vulnerability_count: length(vulns)
          }
        end)
      end)
    end
    
    defp generate_trend_summary(history) do
      if length(history) < 2 do
        %{trend: :insufficient_data}
      else
        first_scan = hd(history)
        last_scan = List.last(history)
        
        %{
          trend: calculate_overall_trend(first_scan, last_scan),
          improvement_rate: calculate_improvement_rate(history),
          most_improved: find_most_improved_areas(history),
          areas_of_concern: find_concerning_areas(history)
        }
      end
    end
    
    defp calculate_overall_trend(first, last) do
      first_total = total_vulnerabilities(first)
      last_total = total_vulnerabilities(last)
      
      cond do
        last_total < first_total -> :improving
        last_total > first_total -> :worsening
        true -> :stable
      end
    end
    
    defp total_vulnerabilities(scan) do
      scan.scan_result.summary.total_vulnerabilities
    end
    
    defp calculate_improvement_rate(history) do
      # Simplified calculation
      if length(history) < 2 do
        0.0
      else
        first_total = total_vulnerabilities(hd(history))
        last_total = total_vulnerabilities(List.last(history))
        
        if first_total == 0 do
          0.0
        else
          ((first_total - last_total) / first_total) * 100
        end
      end
    end
    
    defp find_most_improved_areas(_history) do
      # Simplified - would need more sophisticated analysis
      []
    end
    
    defp find_concerning_areas(_history) do
      # Simplified - would need more sophisticated analysis
      []
    end
    
    defp predict_future_trends(history) do
      %{
        next_period_estimate: estimate_next_period(history),
        confidence: calculate_confidence(history)
      }
    end
    
    defp estimate_next_period(history) do
      # Simplified prediction
      if length(history) < 3 do
        :insufficient_data
      else
        # Simple moving average
        recent = Enum.take(history, -3)
        avg = Enum.sum(Enum.map(recent, &total_vulnerabilities/1)) / 3
        round(avg)
      end
    end
    
    defp calculate_confidence(history) do
      cond do
        length(history) < 3 -> :low
        length(history) < 10 -> :medium
        true -> :high
      end
    end
  end
  
  defmodule GenerateAdvisoryAction do
    @moduledoc """
    Generates security advisories for critical vulnerabilities.
    """
    use Jido.Action, name: "generate_advisory"
    
    def parameter_schema do
      %{
        vulnerabilities: [type: {:list, :map}, required: true, doc: "Vulnerabilities to include"],
        format: [type: :string, default: "markdown", doc: "Advisory format"],
        severity_threshold: [type: :string, default: "high", doc: "Minimum severity"],
        include_remediation: [type: :boolean, default: true, doc: "Include remediation steps"]
      }
    end
    
    @impl true
    def run(params, _context) do
      filtered_vulns = filter_by_severity(params.vulnerabilities, params.severity_threshold)
      
      advisory = generate_advisory(
        filtered_vulns,
        params.format,
        params.include_remediation
      )
      
      {:ok, advisory}
    end
    
    defp filter_by_severity(vulns, threshold) do
      severity_levels = %{"critical" => 4, "high" => 3, "medium" => 2, "low" => 1}
      min_level = severity_levels[threshold] || 3
      
      Enum.filter(vulns, fn vuln ->
        severity_levels[vuln.severity] >= min_level
      end)
    end
    
    defp generate_advisory(vulns, "markdown", include_remediation) do
      sections = [
        generate_header(),
        generate_summary(vulns),
        generate_vulnerability_details(vulns),
        if(include_remediation, do: generate_remediation_section(vulns), else: nil),
        generate_references(vulns)
      ]
      
      %{
        content: Enum.filter(sections, & &1) |> Enum.join("\n\n"),
        format: "markdown",
        generated_at: DateTime.utc_now(),
        vulnerability_count: length(vulns)
      }
    end
    
    defp generate_header do
      """
      # Security Advisory
      
      **Generated**: #{DateTime.utc_now() |> DateTime.to_string()}
      **Severity**: Critical/High
      """
    end
    
    defp generate_summary(vulns) do
      critical_count = Enum.count(vulns, &(&1.severity == "critical"))
      high_count = Enum.count(vulns, &(&1.severity == "high"))
      
      """
      ## Summary
      
      This security advisory addresses #{length(vulns)} vulnerabilities:
      - Critical: #{critical_count}
      - High: #{high_count}
      
      Immediate action is recommended to address these security issues.
      """
    end
    
    defp generate_vulnerability_details(vulns) do
      details = vulns
      |> Enum.map(&format_vulnerability_detail/1)
      |> Enum.join("\n\n")
      
      """
      ## Vulnerability Details
      
      #{details}
      """
    end
    
    defp format_vulnerability_detail(vuln) do
      """
      ### #{vuln.cve_id} - #{vuln.package}
      
      - **Severity**: #{String.capitalize(vuln.severity)} (CVSS: #{vuln.cvss_score})
      - **Affected Version**: #{vuln.version}
      - **Description**: #{vuln.description}
      - **Exploitability**: #{vuln.exploitability}
      - **Published**: #{vuln.published_date}
      """
    end
    
    defp generate_remediation_section(vulns) do
      steps = vulns
      |> Enum.map(&format_remediation_step/1)
      |> Enum.join("\n")
      
      """
      ## Remediation Steps
      
      #{steps}
      """
    end
    
    defp format_remediation_step(vuln) do
      patched = Enum.join(vuln.patched_versions, ", ")
      "- **#{vuln.package}**: Upgrade to version #{patched}"
    end
    
    defp generate_references(vulns) do
      refs = vulns
      |> Enum.flat_map(& &1.references)
      |> Enum.uniq()
      |> Enum.map(fn ref -> "- #{ref}" end)
      |> Enum.join("\n")
      
      """
      ## References
      
      #{refs}
      """
    end
  end
  
  defmodule CompareScansAction do
    @moduledoc """
    Compares two vulnerability scans to identify changes.
    """
    use Jido.Action, name: "compare_scans"
    
    def parameter_schema do
      %{
        baseline_scan: [type: :map, required: true, doc: "Baseline scan results"],
        current_scan: [type: :map, required: true, doc: "Current scan results"],
        include_unchanged: [type: :boolean, default: false, doc: "Include unchanged vulnerabilities"]
      }
    end
    
    @impl true
    def run(params, _context) do
      comparison = compare_scans(
        params.baseline_scan,
        params.current_scan,
        params.include_unchanged
      )
      
      {:ok, comparison}
    end
    
    defp compare_scans(baseline, current, include_unchanged) do
      baseline_vulns = Map.new(baseline.vulnerabilities, & {&1.cve_id, &1})
      current_vulns = Map.new(current.vulnerabilities, & {&1.cve_id, &1})
      
      new_vulns = find_new_vulnerabilities(baseline_vulns, current_vulns)
      resolved_vulns = find_resolved_vulnerabilities(baseline_vulns, current_vulns)
      unchanged_vulns = if include_unchanged do
        find_unchanged_vulnerabilities(baseline_vulns, current_vulns)
      else
        []
      end
      
      %{
        comparison_date: DateTime.utc_now(),
        baseline_date: baseline[:scan_metadata][:scan_date],
        current_date: current[:scan_metadata][:scan_date],
        new_vulnerabilities: new_vulns,
        resolved_vulnerabilities: resolved_vulns,
        unchanged_vulnerabilities: unchanged_vulns,
        summary: %{
          new_count: length(new_vulns),
          resolved_count: length(resolved_vulns),
          unchanged_count: length(unchanged_vulns),
          net_change: length(new_vulns) - length(resolved_vulns)
        }
      }
    end
    
    defp find_new_vulnerabilities(baseline, current) do
      current
      |> Enum.filter(fn {cve_id, _} -> !Map.has_key?(baseline, cve_id) end)
      |> Enum.map(fn {_, vuln} -> vuln end)
    end
    
    defp find_resolved_vulnerabilities(baseline, current) do
      baseline
      |> Enum.filter(fn {cve_id, _} -> !Map.has_key?(current, cve_id) end)
      |> Enum.map(fn {_, vuln} -> vuln end)
    end
    
    defp find_unchanged_vulnerabilities(baseline, current) do
      baseline
      |> Enum.filter(fn {cve_id, _} -> Map.has_key?(current, cve_id) end)
      |> Enum.map(fn {_, vuln} -> vuln end)
    end
  end
  
  defmodule GenerateComplianceReportAction do
    @moduledoc """
    Generates compliance reports based on security policies.
    """
    use Jido.Action, name: "generate_compliance_report"
    
    def parameter_schema do
      %{
        scan_results: [type: :map, required: true, doc: "Scan results to evaluate"],
        compliance_framework: [type: :string, default: "general", doc: "Compliance framework"],
        policies: [type: :map, doc: "Custom compliance policies"],
        format: [type: :string, default: "detailed", doc: "Report format"]
      }
    end
    
    @impl true
    def run(params, _context) do
      policies = params.policies || get_default_policies(params.compliance_framework)
      
      report = generate_compliance_report(
        params.scan_results,
        policies,
        params.format
      )
      
      {:ok, report}
    end
    
    defp get_default_policies("general") do
      %{
        max_critical_vulnerabilities: 0,
        max_high_vulnerabilities: 2,
        max_total_vulnerabilities: 10,
        required_scan_frequency: :weekly,
        prohibited_licenses: ["GPL-3.0", "AGPL-3.0"],
        required_security_score: 70
      }
    end
    
    defp get_default_policies("strict") do
      %{
        max_critical_vulnerabilities: 0,
        max_high_vulnerabilities: 0,
        max_total_vulnerabilities: 5,
        required_scan_frequency: :daily,
        prohibited_licenses: ["GPL-3.0", "AGPL-3.0", "GPL-2.0"],
        required_security_score: 85
      }
    end
    
    defp generate_compliance_report(scan_results, policies, format) do
      violations = check_policy_violations(scan_results, policies)
      compliance_score = calculate_compliance_score(violations, policies)
      
      %{
        report_date: DateTime.utc_now(),
        compliance_framework: policies,
        scan_results_summary: summarize_scan_results(scan_results),
        violations: violations,
        compliance_score: compliance_score,
        compliance_status: determine_status(compliance_score),
        recommendations: generate_recommendations(violations),
        format: format
      }
    end
    
    defp check_policy_violations(scan_results, policies) do
      # Check vulnerability limits
      summary = scan_results.summary
      
      [] ++
        (if (summary[:critical] || 0) > policies.max_critical_vulnerabilities do
           [{:critical_vulnerability_limit_exceeded, %{
             limit: policies.max_critical_vulnerabilities,
             actual: summary[:critical] || 0
           }}]
         else
           []
         end) ++
        (if (summary[:high] || 0) > policies.max_high_vulnerabilities do
           [{:high_vulnerability_limit_exceeded, %{
             limit: policies.max_high_vulnerabilities,
             actual: summary[:high] || 0
           }}]
         else
           []
         end) ++
        (if (summary[:total_vulnerabilities] || 0) > policies.max_total_vulnerabilities do
           [{:total_vulnerability_limit_exceeded, %{
             limit: policies.max_total_vulnerabilities,
             actual: summary[:total_vulnerabilities] || 0
           }}]
         else
           []
         end)
    end
    
    defp calculate_compliance_score(violations, _policies) do
      base_score = 100
      deductions = length(violations) * 15
      
      max(0, base_score - deductions)
    end
    
    defp determine_status(score) do
      cond do
        score >= 90 -> :compliant
        score >= 70 -> :partially_compliant
        true -> :non_compliant
      end
    end
    
    defp summarize_scan_results(scan_results) do
      %{
        total_vulnerabilities: scan_results.summary[:total_vulnerabilities] || 0,
        severity_breakdown: Map.take(scan_results.summary, [:critical, :high, :medium, :low]),
        packages_scanned: scan_results.summary[:packages_scanned] || 0
      }
    end
    
    defp generate_recommendations(violations) do
      violations
      |> Enum.map(&generate_recommendation_for_violation/1)
      |> Enum.uniq()
    end
    
    defp generate_recommendation_for_violation({:critical_vulnerability_limit_exceeded, _}) do
      "Immediately address all critical vulnerabilities"
    end
    
    defp generate_recommendation_for_violation({:high_vulnerability_limit_exceeded, _}) do
      "Prioritize resolution of high-severity vulnerabilities"
    end
    
    defp generate_recommendation_for_violation({:total_vulnerability_limit_exceeded, _}) do
      "Implement a vulnerability management program to reduce overall exposure"
    end
  end
  
  defmodule MonitorVulnerabilitiesAction do
    @moduledoc """
    Sets up continuous monitoring for new vulnerabilities.
    """
    use Jido.Action, name: "monitor_vulnerabilities"
    
    def parameter_schema do
      %{
        dependencies: [type: {:list, :map}, required: true, doc: "Dependencies to monitor"],
        monitoring_config: [type: :map, doc: "Monitoring configuration"],
        alert_channels: [type: {:list, :string}, default: ["log"], doc: "Alert channels"]
      }
    end
    
    @impl true
    def run(params, context) do
      config = Map.merge(
        context.agent.state.monitoring_config,
        params.monitoring_config || %{}
      )
      
      monitoring_setup = setup_monitoring(
        params.dependencies,
        config,
        params.alert_channels
      )
      
      {:ok, monitoring_setup}
    end
    
    defp setup_monitoring(dependencies, config, channels) do
      %{
        monitored_dependencies: dependencies,
        monitoring_config: config,
        alert_channels: channels,
        monitoring_id: generate_monitoring_id(),
        created_at: DateTime.utc_now(),
        status: :active,
        next_scan: calculate_next_scan(config.scan_interval)
      }
    end
    
    defp generate_monitoring_id do
      :crypto.strong_rand_bytes(16) |> Base.encode16()
    end
    
    defp calculate_next_scan(:hourly), do: DateTime.add(DateTime.utc_now(), 3600, :second)
    defp calculate_next_scan(:daily), do: DateTime.add(DateTime.utc_now(), 86400, :second)
    defp calculate_next_scan(:weekly), do: DateTime.add(DateTime.utc_now(), 604800, :second)
    defp calculate_next_scan(_), do: DateTime.add(DateTime.utc_now(), 86400, :second)
  end
  
  defmodule GeneratePatchPlanAction do
    @moduledoc """
    Generates a comprehensive patching plan for vulnerabilities.
    """
    use Jido.Action, name: "generate_patch_plan"
    
    def parameter_schema do
      %{
        vulnerabilities: [type: {:list, :map}, required: true, doc: "Vulnerabilities to patch"],
        strategy: [type: :string, default: "balanced", doc: "Patching strategy"],
        test_requirements: [type: :map, doc: "Testing requirements for patches"],
        rollback_planning: [type: :boolean, default: true, doc: "Include rollback plans"]
      }
    end
    
    @impl true
    def run(params, _context) do
      patch_plan = generate_patch_plan(
        params.vulnerabilities,
        params.strategy,
        params.test_requirements,
        params.rollback_planning
      )
      
      {:ok, patch_plan}
    end
    
    defp generate_patch_plan(vulns, strategy, test_reqs, include_rollback) do
      grouped_vulns = group_vulnerabilities_by_package(vulns)
      phases = plan_patch_phases(grouped_vulns, strategy)
      
      %{
        plan_id: generate_plan_id(),
        created_at: DateTime.utc_now(),
        strategy: strategy,
        total_vulnerabilities: length(vulns),
        affected_packages: map_size(grouped_vulns),
        phases: phases,
        estimated_duration: estimate_duration(phases),
        test_plan: generate_test_plan(phases, test_reqs),
        rollback_plan: if(include_rollback, do: generate_rollback_plan(phases), else: nil)
      }
    end
    
    defp group_vulnerabilities_by_package(vulns) do
      Enum.group_by(vulns, & &1.package)
    end
    
    defp plan_patch_phases(grouped_vulns, "aggressive") do
      # Patch everything at once
      [%{
        phase_number: 1,
        packages: Map.keys(grouped_vulns),
        updates: format_updates(grouped_vulns),
        risk_level: :high,
        estimated_duration: "2-4 hours"
      }]
    end
    
    defp plan_patch_phases(grouped_vulns, "conservative") do
      # One package at a time
      grouped_vulns
      |> Enum.with_index(1)
      |> Enum.map(fn {{package, vulns}, index} ->
        %{
          phase_number: index,
          packages: [package],
          updates: format_single_update(package, vulns),
          risk_level: :low,
          estimated_duration: "1-2 hours"
        }
      end)
    end
    
    defp plan_patch_phases(grouped_vulns, _) do
      # Balanced - group by severity
      critical_packages = find_packages_by_severity(grouped_vulns, "critical")
      high_packages = find_packages_by_severity(grouped_vulns, "high")
      other_packages = Map.keys(grouped_vulns) -- (critical_packages ++ high_packages)
      
      phases = []
      
      phases = if length(critical_packages) > 0 do
        [%{
          phase_number: 1,
          packages: critical_packages,
          updates: format_updates_for_packages(grouped_vulns, critical_packages),
          risk_level: :high,
          priority: :critical,
          estimated_duration: "2-3 hours"
        } | phases]
      else
        phases
      end
      
      phases = if length(high_packages) > 0 do
        [%{
          phase_number: length(phases) + 1,
          packages: high_packages,
          updates: format_updates_for_packages(grouped_vulns, high_packages),
          risk_level: :medium,
          priority: :high,
          estimated_duration: "2-3 hours"
        } | phases]
      else
        phases
      end
      
      if length(other_packages) > 0 do
        [%{
          phase_number: length(phases) + 1,
          packages: other_packages,
          updates: format_updates_for_packages(grouped_vulns, other_packages),
          risk_level: :low,
          priority: :medium,
          estimated_duration: "1-2 hours"
        } | phases]
      else
        phases
      end
      |> Enum.reverse()
    end
    
    defp find_packages_by_severity(grouped_vulns, severity) do
      grouped_vulns
      |> Enum.filter(fn {_, vulns} ->
        Enum.any?(vulns, &(&1.severity == severity))
      end)
      |> Enum.map(fn {package, _} -> package end)
    end
    
    defp format_updates(grouped_vulns) do
      Enum.map(grouped_vulns, fn {package, vulns} ->
        format_single_update(package, vulns)
      end)
    end
    
    defp format_single_update(package, vulns) do
      target_version = get_safe_version(vulns)
      
      %{
        package: package,
        current_version: hd(vulns).version,
        target_version: target_version,
        fixes_cves: Enum.map(vulns, & &1.cve_id),
        update_command: generate_update_command(package, target_version)
      }
    end
    
    defp format_updates_for_packages(grouped_vulns, packages) do
      packages
      |> Enum.map(fn package ->
        format_single_update(package, grouped_vulns[package])
      end)
    end
    
    defp get_safe_version(vulns) do
      vulns
      |> Enum.flat_map(& &1.patched_versions)
      |> Enum.uniq()
      |> List.first()
    end
    
    defp generate_update_command(package, version) do
      # Would detect package manager
      "npm install #{package}@#{version}"
    end
    
    defp estimate_duration(phases) do
      total_hours = length(phases) * 2
      "#{total_hours}-#{total_hours + 2} hours"
    end
    
    defp generate_test_plan(phases, _test_reqs) do
      %{
        pre_patch_tests: ["Run full test suite", "Create system backup"],
        per_phase_tests: Enum.map(phases, fn phase ->
          %{
            phase: phase.phase_number,
            tests: [
              "Unit tests for affected components",
              "Integration tests",
              "Smoke tests for critical paths"
            ]
          }
        end),
        post_patch_tests: ["Full regression test", "Performance benchmarks"]
      }
    end
    
    defp generate_rollback_plan(phases) do
      %{
        backup_strategy: "Full system backup before patching",
        rollback_phases: Enum.map(phases, fn phase ->
          %{
            phase: phase.phase_number,
            rollback_commands: Enum.map(phase.updates || [], fn update ->
              "npm install #{update.package}@#{update.current_version}"
            end),
            verification_steps: ["Verify service startup", "Run smoke tests"]
          }
        end)
      }
    end
    
    defp generate_plan_id do
      :crypto.strong_rand_bytes(8) |> Base.encode16()
    end
  end
  
  # Helper functions
  
  defp add_to_scan_history(state, scan_results, metadata) do
    history_entry = Map.merge(scan_results, %{
      timestamp: DateTime.utc_now(),
      metadata: metadata
    })
    
    %{state | scan_history: [history_entry | Enum.take(state.scan_history, 99)]}
  end
  
  defp update_vulnerability_trends(state, scan_results) do
    # Update trends based on new scan results
    trends = state.vulnerability_trends
    
    # Add data point
    new_point = %{
      timestamp: DateTime.utc_now(),
      vulnerabilities: scan_results.total_vulnerabilities,
      by_severity: scan_results.summary_by_severity
    }
    
    updated_trends = Map.update(trends, :data_points, [new_point], fn points ->
      [new_point | Enum.take(points, 999)]
    end)
    
    %{state | vulnerability_trends: updated_trends}
  end
  
  defp check_monitoring_alerts(state, scan_results) do
    thresholds = state.monitoring_config.alert_thresholds
    summary = scan_results.summary_by_severity || %{}
    
    alerts = [] ++
      (if (summary[:critical] || 0) > thresholds.critical,
       do: [:critical_threshold_exceeded],
       else: []) ++
      (if (summary[:high] || 0) > thresholds.high,
       do: [:high_threshold_exceeded],
       else: []) ++
      (if (summary[:medium] || 0) > thresholds.medium,
       do: [:medium_threshold_exceeded],
       else: [])
    
    if length(alerts) > 0 do
      emit_monitoring_alerts(alerts, scan_results)
    end
    
    state
  end
  
  defp emit_monitoring_alerts(alerts, scan_results) do
    Enum.each(alerts, fn alert ->
      Jido.Signal.emit(%{
        source: "cve_analyzer_agent",
        type: "vulnerability.alert",
        data: %{
          alert_type: alert,
          scan_results: scan_results,
          timestamp: DateTime.utc_now()
        }
      })
    end)
  end
end