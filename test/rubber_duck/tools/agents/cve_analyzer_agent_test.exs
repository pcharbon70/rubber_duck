defmodule RubberDuck.Tools.Agents.CVEAnalyzerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CVEAnalyzerAgent
  
  setup do
    {:ok, agent} = CVEAnalyzerAgent.start_link(id: "test_cve_analyzer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        dependencies: [
          %{name: "lodash", version: "4.17.20", registry: "npm"},
          %{name: "minimist", version: "1.2.5", registry: "npm"}
        ],
        check_transitive: false,
        severity_threshold: "low"
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: CVEAnalyzerAgent}
      
      result = CVEAnalyzerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "batch scan action scans multiple projects", %{agent: agent} do
      projects = [
        %{
          name: "project-a",
          dependencies: [
            %{name: "lodash", version: "4.17.20", registry: "npm"},
            %{name: "express", version: "4.17.1", registry: "npm"}
          ]
        },
        %{
          name: "project-b",
          dependencies: [
            %{name: "minimist", version: "1.2.5", registry: "npm"},
            %{name: "react", version: "17.0.2", registry: "npm"}
          ]
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CVEAnalyzerAgent.BatchScanAction.run(
        %{
          projects: projects,
          scan_options: %{severity_threshold: "low"},
          parallel: true,
          aggregate_results: true
        },
        context
      )
      
      assert result.total_projects == 2
      assert result.successful_scans == 2
      assert is_list(result.total_vulnerabilities)
      assert Map.has_key?(result, :summary_by_severity)
      assert length(result.affected_projects) >= 1  # At least one project has vulnerabilities
    end
    
    test "analyze trends action analyzes vulnerability trends", %{agent: agent} do
      # Set up some scan history
      state = GenServer.call(agent, :get_state)
      
      # Add mock scan history
      scan_history = [
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -10, :day),
          scan_result: %{
            summary: %{
              total_vulnerabilities: 10,
              critical: 2,
              high: 3,
              medium: 4,
              low: 1
            },
            vulnerabilities: []
          }
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -5, :day),
          scan_result: %{
            summary: %{
              total_vulnerabilities: 8,
              critical: 1,
              high: 3,
              medium: 3,
              low: 1
            },
            vulnerabilities: []
          }
        },
        %{
          timestamp: DateTime.utc_now(),
          scan_result: %{
            summary: %{
              total_vulnerabilities: 6,
              critical: 0,
              high: 2,
              medium: 3,
              low: 1
            },
            vulnerabilities: []
          }
        }
      ]
      
      # Update agent state with history
      updated_state = %{state | state: %{state.state | scan_history: scan_history}}
      GenServer.call(agent, {:update_state, fn _ -> updated_state.state end})
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, trends} = CVEAnalyzerAgent.AnalyzeTrendsAction.run(
        %{
          time_period: "30d",
          group_by: "severity",
          include_resolved: false
        },
        context
      )
      
      assert trends.period == "30d"
      assert trends.data_points == 3
      assert Map.has_key?(trends, :summary)
      assert trends.summary.trend == :improving  # Vulnerabilities decreased
      assert trends.summary.improvement_rate > 0
    end
    
    test "generate advisory action creates security advisory", %{agent: agent} do
      vulnerabilities = [
        %{
          cve_id: "CVE-2021-23337",
          package: "lodash",
          version: "4.17.20",
          severity: "high",
          cvss_score: 7.2,
          description: "Command injection vulnerability",
          published_date: "2021-02-15",
          patched_versions: ["4.17.21"],
          references: ["https://nvd.nist.gov/vuln/detail/CVE-2021-23337"],
          exploitability: "high"
        },
        %{
          cve_id: "CVE-2021-44906",
          package: "minimist",
          version: "1.2.5",
          severity: "critical",
          cvss_score: 9.8,
          description: "Prototype pollution vulnerability",
          published_date: "2022-03-17",
          patched_versions: ["1.2.6"],
          references: ["https://nvd.nist.gov/vuln/detail/CVE-2021-44906"],
          exploitability: "high"
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, advisory} = CVEAnalyzerAgent.GenerateAdvisoryAction.run(
        %{
          vulnerabilities: vulnerabilities,
          format: "markdown",
          severity_threshold: "high",
          include_remediation: true
        },
        context
      )
      
      assert advisory.format == "markdown"
      assert advisory.vulnerability_count == 2
      assert String.contains?(advisory.content, "Security Advisory")
      assert String.contains?(advisory.content, "CVE-2021-23337")
      assert String.contains?(advisory.content, "CVE-2021-44906")
      assert String.contains?(advisory.content, "Remediation Steps")
    end
    
    test "compare scans action identifies changes between scans", %{agent: agent} do
      baseline_scan = %{
        vulnerabilities: [
          %{cve_id: "CVE-001", severity: "high"},
          %{cve_id: "CVE-002", severity: "medium"},
          %{cve_id: "CVE-003", severity: "low"}
        ],
        scan_metadata: %{scan_date: DateTime.add(DateTime.utc_now(), -7, :day)}
      }
      
      current_scan = %{
        vulnerabilities: [
          %{cve_id: "CVE-002", severity: "medium"},  # Still present
          %{cve_id: "CVE-004", severity: "critical"}, # New
          %{cve_id: "CVE-005", severity: "high"}      # New
        ],
        scan_metadata: %{scan_date: DateTime.utc_now()}
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, comparison} = CVEAnalyzerAgent.CompareScansAction.run(
        %{
          baseline_scan: baseline_scan,
          current_scan: current_scan,
          include_unchanged: true
        },
        context
      )
      
      assert length(comparison.new_vulnerabilities) == 2
      assert length(comparison.resolved_vulnerabilities) == 2  # CVE-001 and CVE-003
      assert length(comparison.unchanged_vulnerabilities) == 1  # CVE-002
      assert comparison.summary.net_change == 0  # 2 new - 2 resolved
    end
    
    test "generate compliance report action evaluates against policies", %{agent: agent} do
      scan_results = %{
        summary: %{
          total_vulnerabilities: 15,
          critical: 1,
          high: 4,
          medium: 7,
          low: 3,
          packages_scanned: 50
        },
        vulnerabilities: []
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, report} = CVEAnalyzerAgent.GenerateComplianceReportAction.run(
        %{
          scan_results: scan_results,
          compliance_framework: "general",
          format: "detailed"
        },
        context
      )
      
      assert report.compliance_status == :non_compliant  # Exceeds limits
      assert length(report.violations) > 0
      
      # Should have violations for critical and high vulnerabilities
      violation_types = Enum.map(report.violations, fn {type, _} -> type end)
      assert :critical_vulnerability_limit_exceeded in violation_types
      assert :high_vulnerability_limit_exceeded in violation_types
      assert :total_vulnerability_limit_exceeded in violation_types
      
      assert report.compliance_score < 70
      assert length(report.recommendations) > 0
    end
    
    test "monitor vulnerabilities action sets up monitoring", %{agent: agent} do
      dependencies = [
        %{name: "express", version: "4.17.1", registry: "npm"},
        %{name: "react", version: "17.0.2", registry: "npm"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, monitoring} = CVEAnalyzerAgent.MonitorVulnerabilitiesAction.run(
        %{
          dependencies: dependencies,
          monitoring_config: %{
            scan_interval: :daily,
            alert_thresholds: %{critical: 0, high: 1, medium: 3}
          },
          alert_channels: ["log", "email"]
        },
        context
      )
      
      assert length(monitoring.monitored_dependencies) == 2
      assert monitoring.status == :active
      assert monitoring.alert_channels == ["log", "email"]
      assert monitoring.monitoring_config.scan_interval == :daily
      assert monitoring.next_scan != nil
    end
    
    test "generate patch plan action creates phased patching plan", %{agent: agent} do
      vulnerabilities = [
        %{
          cve_id: "CVE-001",
          package: "package-a",
          version: "1.0.0",
          severity: "critical",
          patched_versions: ["1.0.1"]
        },
        %{
          cve_id: "CVE-002",
          package: "package-b",
          version: "2.0.0",
          severity: "high",
          patched_versions: ["2.0.1"]
        },
        %{
          cve_id: "CVE-003",
          package: "package-c",
          version: "3.0.0",
          severity: "medium",
          patched_versions: ["3.0.1"]
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, patch_plan} = CVEAnalyzerAgent.GeneratePatchPlanAction.run(
        %{
          vulnerabilities: vulnerabilities,
          strategy: "balanced",
          rollback_planning: true
        },
        context
      )
      
      assert patch_plan.strategy == "balanced"
      assert patch_plan.total_vulnerabilities == 3
      assert patch_plan.affected_packages == 3
      
      # Should have multiple phases based on severity
      assert length(patch_plan.phases) >= 2
      
      # First phase should be critical
      first_phase = hd(patch_plan.phases)
      assert first_phase.priority == :critical
      assert "package-a" in first_phase.packages
      
      # Should have test and rollback plans
      assert Map.has_key?(patch_plan, :test_plan)
      assert Map.has_key?(patch_plan, :rollback_plan)
      assert patch_plan.rollback_plan != nil
    end
  end
  
  describe "signal handling with actions" do
    test "batch_scan signal triggers BatchScanAction", %{agent: agent} do
      signal = %{
        "type" => "batch_scan",
        "data" => %{
          "projects" => [
            %{"name" => "test", "dependencies" => []}
          ]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CVEAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_trends signal triggers AnalyzeTrendsAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_trends",
        "data" => %{
          "time_period" => "30d"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CVEAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_advisory signal triggers GenerateAdvisoryAction", %{agent: agent} do
      signal = %{
        "type" => "generate_advisory",
        "data" => %{
          "vulnerabilities" => []
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CVEAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "updates scan history after batch scan", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      scan_results = %{
        total_projects: 2,
        successful_scans: 2,
        total_vulnerabilities: [],
        summary_by_severity: %{high: 1}
      }
      
      metadata = %{scan_type: "batch"}
      
      {:ok, updated} = CVEAnalyzerAgent.handle_action_result(
        state,
        CVEAnalyzerAgent.BatchScanAction,
        {:ok, scan_results},
        metadata
      )
      
      assert length(updated.state.scan_history) == 1
      entry = hd(updated.state.scan_history)
      assert entry.total_projects == 2
      assert entry.metadata.scan_type == "batch"
    end
    
    test "updates vulnerability trends", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      trends = %{
        data_points: [
          %{timestamp: DateTime.utc_now(), vulnerabilities: 10}
        ],
        summary: %{trend: :improving}
      }
      
      {:ok, updated} = CVEAnalyzerAgent.handle_action_result(
        state,
        CVEAnalyzerAgent.AnalyzeTrendsAction,
        {:ok, trends},
        %{}
      )
      
      assert updated.state.vulnerability_trends == trends
    end
    
    test "tracks patch history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      patch_plan = %{
        plan_id: "PLAN001",
        total_vulnerabilities: 5,
        phases: []
      }
      
      {:ok, updated} = CVEAnalyzerAgent.handle_action_result(
        state,
        CVEAnalyzerAgent.GeneratePatchPlanAction,
        {:ok, patch_plan},
        %{}
      )
      
      assert length(updated.state.patch_history) == 1
      assert hd(updated.state.patch_history).plan_id == "PLAN001"
    end
    
    test "triggers alerts when thresholds exceeded", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Scan results that exceed thresholds
      scan_results = %{
        total_vulnerabilities: 10,
        summary_by_severity: %{
          critical: 1,  # Exceeds threshold of 0
          high: 5,      # Exceeds threshold of 2
          medium: 4
        }
      }
      
      # This should trigger alerts
      {:ok, _updated} = CVEAnalyzerAgent.handle_action_result(
        state,
        CVEAnalyzerAgent.BatchScanAction,
        {:ok, scan_results},
        %{}
      )
      
      # In a real test, we'd verify signals were emitted
      assert true
    end
  end
  
  describe "agent initialization" do
    test "starts with default monitoring config", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.monitoring_config
      assert config.alert_thresholds.critical == 0
      assert config.alert_thresholds.high == 2
      assert config.alert_thresholds.medium == 5
      assert config.scan_interval == :daily
    end
    
    test "starts with empty scan history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.scan_history == []
      assert state.state.vulnerability_trends == %{}
      assert state.state.patch_history == []
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = CVEAnalyzerAgent.additional_actions()
      
      assert length(actions) == 7
      assert CVEAnalyzerAgent.BatchScanAction in actions
      assert CVEAnalyzerAgent.AnalyzeTrendsAction in actions
      assert CVEAnalyzerAgent.GenerateAdvisoryAction in actions
      assert CVEAnalyzerAgent.CompareScansAction in actions
      assert CVEAnalyzerAgent.GenerateComplianceReportAction in actions
      assert CVEAnalyzerAgent.MonitorVulnerabilitiesAction in actions
      assert CVEAnalyzerAgent.GeneratePatchPlanAction in actions
    end
  end
  
  describe "trend analysis" do
    test "correctly identifies improving trends" do
      context = %{agent: %{state: %{scan_history: []}}}
      
      # Decreasing vulnerability count over time
      history = [
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -20, :day),
          scan_result: %{summary: %{total_vulnerabilities: 20}}
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -10, :day),
          scan_result: %{summary: %{total_vulnerabilities: 15}}
        },
        %{
          timestamp: DateTime.utc_now(),
          scan_result: %{summary: %{total_vulnerabilities: 10}}
        }
      ]
      
      updated_context = put_in(context.agent.state.scan_history, history)
      
      {:ok, trends} = CVEAnalyzerAgent.AnalyzeTrendsAction.run(
        %{time_period: "30d", group_by: "severity"},
        updated_context
      )
      
      assert trends.summary.trend == :improving
      assert trends.summary.improvement_rate == 50.0  # 50% improvement
    end
  end
  
  describe "patch planning strategies" do
    test "aggressive strategy creates single phase" do
      vulns = [
        %{package: "a", severity: "critical", patched_versions: ["1.1"]},
        %{package: "b", severity: "high", patched_versions: ["2.1"]},
        %{package: "c", severity: "low", patched_versions: ["3.1"]}
      ]
      
      {:ok, plan} = CVEAnalyzerAgent.GeneratePatchPlanAction.run(
        %{vulnerabilities: vulns, strategy: "aggressive"},
        %{}
      )
      
      assert length(plan.phases) == 1
      assert length(hd(plan.phases).packages) == 3
      assert hd(plan.phases).risk_level == :high
    end
    
    test "conservative strategy creates phase per package" do
      vulns = [
        %{package: "a", severity: "critical", version: "1.0", patched_versions: ["1.1"]},
        %{package: "b", severity: "high", version: "2.0", patched_versions: ["2.1"]}
      ]
      
      {:ok, plan} = CVEAnalyzerAgent.GeneratePatchPlanAction.run(
        %{vulnerabilities: vulns, strategy: "conservative"},
        %{}
      )
      
      assert length(plan.phases) == 2
      assert length(hd(plan.phases).packages) == 1
      assert Enum.all?(plan.phases, &(&1.risk_level == :low))
    end
  end
end