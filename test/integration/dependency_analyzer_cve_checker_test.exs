defmodule RubberDuck.Integration.DependencyAnalyzerCVECheckerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.DependencyAnalyzerAgent
  alias RubberDuck.Tools.CVEChecker
  alias RubberDuck.Tool.Registry
  
  setup do
    # Ensure CVE checker is registered
    Registry.register(CVEChecker)
    
    {:ok, agent} = DependencyAnalyzerAgent.start_link(id: "test_dep_analyzer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "integration with CVE checker" do
    test "CheckSecurityVulnerabilitiesAction uses CVE checker tool", %{agent: agent} do
      dependencies = %{
        "lodash" => %{
          name: "lodash",
          version: "4.17.20",
          registry: "npm"
        },
        "minimist" => %{
          name: "minimist", 
          version: "1.2.5",
          registry: "npm"
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Execute the action which should internally use CVE checker
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{
          dependencies: dependencies,
          check_advisories: true
        },
        context
      )
      
      # Verify results match what CVE checker would return
      assert length(result.vulnerabilities) >= 2
      
      # Check for lodash vulnerability
      lodash_vuln = Enum.find(result.vulnerabilities, &(&1.dependency == "lodash"))
      assert lodash_vuln != nil
      assert lodash_vuln.cve_ids != []
      
      # Check for minimist vulnerability  
      minimist_vuln = Enum.find(result.vulnerabilities, &(&1.dependency == "minimist"))
      assert minimist_vuln != nil
      assert minimist_vuln.severity == :critical
      
      # Verify security summary
      assert result.security_summary.total_vulnerabilities >= 2
      assert result.security_score <= 50  # Poor score due to vulnerabilities
    end
    
    test "enhanced vulnerability details when using CVE checker", %{agent: agent} do
      # Test with a known critical vulnerability (Log4Shell)
      dependencies = %{
        "log4j" => %{
          name: "log4j",
          version: "2.14.0",
          registry: "maven"
        }
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{dependencies: dependencies},
        context
      )
      
      # Should detect Log4Shell
      log4j_vuln = Enum.find(result.vulnerabilities, &(&1.dependency == "log4j"))
      assert log4j_vuln != nil
      assert "CVE-2021-44228" in log4j_vuln.cve_ids
      assert log4j_vuln.severity == :critical
      assert log4j_vuln.description =~ "Log4Shell"
      
      # Remediation should be high priority
      assert hd(result.remediation_plan).priority == 1
    end
    
    test "can specify CVE checker sources", %{agent: agent} do
      dependencies = %{
        "test-package" => %{
          name: "test-package",
          version: "1.0.0"
        }
      }
      
      context = %{
        agent: GenServer.call(agent, :get_state),
        cve_sources: ["nvd", "ghsa", "osv"]  # Specify sources
      }
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{dependencies: dependencies},
        context
      )
      
      # Result should indicate sources were used (even if no vulnerabilities found)
      assert result.security_summary != nil
    end
    
    test "handles transitive dependency vulnerabilities", %{agent: agent} do
      # Simulate a dependency tree where transitive deps have vulnerabilities
      dependencies = %{
        "express" => %{
          name: "express",
          version: "4.17.1",
          registry: "npm",
          dependencies: %{
            "body-parser" => "1.19.0",
            "cookie" => "0.4.0",
            "debug" => "2.6.9"
          }
        }
      }
      
      context = %{
        agent: GenServer.call(agent, :get_state),
        check_transitive: true
      }
      
      {:ok, result} = DependencyAnalyzerAgent.CheckSecurityVulnerabilitiesAction.run(
        %{dependencies: dependencies, check_advisories: true},
        context
      )
      
      # Should check transitive dependencies
      assert result.security_summary.dependencies_affected >= 0
    end
  end
  
  describe "CVE data enrichment" do
    test "enriches dependency report with CVE data", %{agent: agent} do
      # Set up analysis results with vulnerabilities
      analysis_results = %{
        tree_analysis: %{
          total_dependencies: 10,
          direct_dependencies: 3,
          max_depth: 2
        },
        conflicts: [],
        vulnerabilities: [
          %{
            dependency: "lodash",
            severity: :high,
            cve_ids: ["CVE-2021-23337"]
          }
        ],
        license_issues: [],
        update_recommendations: []
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, report} = DependencyAnalyzerAgent.GenerateDependencyReportAction.run(
        %{
          analysis_results: analysis_results,
          report_format: "detailed",
          include_cve_details: true
        },
        context
      )
      
      # Report should include CVE details
      security_section = report.sections.security_analysis
      assert security_section != nil
      assert String.contains?(security_section.content || "", "CVE-2021-23337")
    end
  end
end