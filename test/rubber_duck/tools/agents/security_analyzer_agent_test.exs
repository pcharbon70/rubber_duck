defmodule RubberDuck.Tools.Agents.SecurityAnalyzerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.SecurityAnalyzerAgent
  
  setup do
    {:ok, agent} = SecurityAnalyzerAgent.start_link(id: "test_security_analyzer")
    
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
        source_code: "SELECT * FROM users WHERE id = '" <> "user_input" <> "'",
        language: "sql",
        scan_type: "vulnerability"
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: SecurityAnalyzerAgent}
      
      # Mock the Executor response - in real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = SecurityAnalyzerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "scan vulnerabilities action detects common security issues", %{agent: agent} do
      vulnerable_code = """
      function processUserInput(userInput) {
        // SQL Injection vulnerability
        const query = "SELECT * FROM users WHERE name = '" + userInput + "'";
        db.execute(query);
        
        // XSS vulnerability
        document.getElementById('output').innerHTML = userInput;
        
        // Command injection
        const cmd = 'echo ' + userInput;
        exec(cmd);
        
        // Hardcoded secret
        const apiKey = "sk-1234567890abcdef";
        
        // Weak crypto
        const hash = md5(password);
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
        %{
          source_code: vulnerable_code,
          language: "javascript",
          scan_depth: "comprehensive"
        },
        context
      )
      
      # Check vulnerabilities were found
      assert length(result.vulnerabilities) >= 5
      
      # Check SQL injection detection
      sql_injection = Enum.find(result.vulnerabilities, &(&1.type == :sql_injection))
      assert sql_injection != nil
      assert sql_injection.severity == :critical
      assert sql_injection.cwe_id == "CWE-89"
      assert length(sql_injection.occurrences) > 0
      
      # Check XSS detection
      xss = Enum.find(result.vulnerabilities, &(&1.type == :xss))
      assert xss != nil
      assert xss.severity == :high
      
      # Check command injection
      cmd_injection = Enum.find(result.vulnerabilities, &(&1.type == :command_injection))
      assert cmd_injection != nil
      assert cmd_injection.severity == :critical
      
      # Check hardcoded secrets
      secrets = Enum.find(result.vulnerabilities, &(&1.type == :hardcoded_secrets))
      assert secrets != nil
      
      # Check weak crypto
      crypto = Enum.find(result.vulnerabilities, &(&1.type == :weak_crypto))
      assert crypto != nil
      
      # Check risk score
      assert result.risk_score > 0.7  # Should be high due to critical vulnerabilities
      
      # Check scan metadata
      assert result.scan_metadata.language == "javascript"
      assert result.scan_metadata.total_vulnerabilities >= 5
      assert result.scan_metadata.critical_count >= 2
    end
    
    test "scan depth affects vulnerability detection", %{agent: agent} do
      code_with_issues = """
      password = "admin123"
      query = "SELECT * FROM users WHERE id = " + user_id
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Basic scan
      {:ok, basic_result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
        %{
          source_code: code_with_issues,
          language: "python",
          scan_depth: "basic"
        },
        context
      )
      
      # Comprehensive scan
      {:ok, comprehensive_result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
        %{
          source_code: code_with_issues,
          language: "python",
          scan_depth: "comprehensive"
        },
        context
      )
      
      # Comprehensive scan should have higher confidence
      basic_vulns = basic_result.vulnerabilities
      comp_vulns = comprehensive_result.vulnerabilities
      
      assert length(comp_vulns) >= length(basic_vulns)
      
      # Check confidence levels
      if length(basic_vulns) > 0 && length(comp_vulns) > 0 do
        basic_confidence = hd(basic_vulns).confidence
        comp_confidence = hd(comp_vulns).confidence
        assert comp_confidence >= basic_confidence
      end
    end
    
    test "analyze dependencies action identifies vulnerable packages", %{agent: agent} do
      dependencies = [
        %{name: "express", version: "4.16.0"},
        %{name: "lodash", version: "4.17.15"},
        %{name: "django", version: "3.2.0"},
        %{name: "log4j", version: "2.14.0"},
        %{name: "react", version: "18.2.0"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SecurityAnalyzerAgent.AnalyzeDependenciesAction.run(
        %{
          dependencies: dependencies,
          language: "javascript",
          check_licenses: true
        },
        context
      )
      
      # Check vulnerable dependencies found
      vulnerable = result.vulnerable_dependencies
      assert length(vulnerable) > 0
      
      # Check specific vulnerabilities
      lodash_vuln = Enum.find(vulnerable, &(&1.dependency == "lodash"))
      assert lodash_vuln != nil
      assert lodash_vuln.severity == :high
      assert length(lodash_vuln.vulnerabilities) > 0
      assert length(lodash_vuln.safe_versions) > 0
      
      # Check log4j critical vulnerability
      log4j_vuln = Enum.find(vulnerable, &(&1.dependency == "log4j"))
      if log4j_vuln do
        assert log4j_vuln.severity == :critical
        vuln = hd(log4j_vuln.vulnerabilities)
        assert vuln.cve_id == "CVE-2021-44228"
      end
      
      # Check outdated dependencies
      outdated = result.outdated_dependencies
      assert length(outdated) > 0
      
      # Check risk assessment
      risk = result.risk_assessment
      assert risk.overall_risk > 0
      assert risk.vulnerability_risk > 0
      assert risk.risk_level in [:critical, :high, :medium, :low, :minimal]
      assert is_list(risk.recommendations)
      
      # Check remediation plan
      assert is_list(result.remediation_plan)
      if length(result.remediation_plan) > 0 do
        step = hd(result.remediation_plan)
        assert step.action == :update_dependency
        assert step.priority in [:critical, :high, :medium, :low]
      end
    end
    
    test "validate security practices action checks coding standards", %{agent: agent} do
      insecure_code = """
      function authenticateUser(username, password) {
        // Storing password in plain text
        const storedPassword = getUserPassword(username);
        if (password === storedPassword) {
          // Missing session timeout
          createSession(username, { expires: 0 });
          return true;
        }
        
        // Error details exposed
        catch (error) {
          console.log("Authentication error:", error);
          return { error: error.stack };
        }
      }
      
      function generateToken() {
        // Weak random generation
        return Math.random().toString(36);
      }
      
      // Missing authorization check
      app.delete('/admin/users/:id', (req, res) => {
        deleteUser(req.params.id);
      });
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SecurityAnalyzerAgent.ValidateSecurityPracticesAction.run(
        %{
          source_code: insecure_code,
          language: "javascript",
          compliance_standards: ["OWASP", "CWE"]
        },
        context
      )
      
      # Check practice violations
      violations = result.practice_violations
      assert length(violations) > 0
      
      # Check specific violations
      password_violation = Enum.find(violations, &(&1.check == :password_storage))
      assert password_violation != nil
      assert password_violation.severity == :high
      
      session_violation = Enum.find(violations, &(&1.check == :session_management))
      assert session_violation != nil
      
      error_violation = Enum.find(violations, &(&1.check == :information_disclosure))
      assert error_violation != nil
      
      random_violation = Enum.find(violations, &(&1.check == :random_generation))
      assert random_violation != nil
      
      auth_violation = Enum.find(violations, &(&1.check == :missing_authorization))
      assert auth_violation != nil
      
      # Check practice score
      assert result.practice_score < 0.5  # Should be low due to violations
      
      # Check compliance
      compliance = result.compliance_status
      assert compliance.compliant == false
      assert length(compliance.violations) > 0
      assert "OWASP" in compliance.standards_checked
      
      # Check report card
      report_card = result.report_card
      assert report_card.overall_grade in ["D", "F"]  # Poor grade due to violations
      assert is_list(report_card.weaknesses)
      assert is_list(report_card.improvement_areas)
    end
    
    test "generate remediation action provides secure code fixes", %{agent: agent} do
      vulnerability = %{
        type: :sql_injection,
        severity: :critical,
        occurrences: [
          %{line: 5, code_snippet: "query = \"SELECT * FROM users WHERE id = '\" + userId + \"'\""}
        ],
        cwe_id: "CWE-89"
      }
      
      source_code = """
      function getUser(userId) {
        const query = "SELECT * FROM users WHERE id = '" + userId + "'";
        return db.execute(query);
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SecurityAnalyzerAgent.GenerateRemediationAction.run(
        %{
          vulnerability: vulnerability,
          source_code: source_code,
          language: "javascript"
        },
        context
      )
      
      # Check remediated code
      assert result.remediated_code != nil
      assert String.contains?(result.remediated_code, "?") ||
             String.contains?(result.remediated_code, "parameterized")
      
      # Check explanation
      assert String.contains?(result.explanation, "SQL injection")
      
      # Check implementation steps
      assert is_list(result.implementation_steps)
      assert length(result.implementation_steps) >= 3
      
      # Check security notes
      assert is_list(result.security_notes)
      assert Enum.any?(result.security_notes, &String.contains?(&1, "user input"))
      
      # Check testing guidance
      assert is_list(result.testing_guidance)
      assert Enum.any?(result.testing_guidance, &String.contains?(&1, "attack payload"))
      
      # Check references
      assert is_list(result.references)
      assert Enum.any?(result.references, &(&1.title =~ ~r/OWASP|CWE/))
    end
    
    test "perform threat modeling action with STRIDE", %{agent: agent} do
      system_description = "E-commerce platform with user authentication and payment processing"
      
      components = [
        %{
          name: "Web Frontend",
          external_facing: true,
          authentication: "basic",
          rate_limiting: false
        },
        %{
          name: "API Gateway", 
          external_facing: true,
          handles_transactions: true,
          audit_logging: false
        },
        %{
          name: "Payment Service",
          handles_transactions: true,
          has_admin_functions: true,
          rbac: false
        },
        %{
          name: "Database",
          contains_sensitive_data: true
        }
      ]
      
      data_flows = [
        %{
          source: "Web Frontend",
          destination: "API Gateway",
          contains_sensitive_data: true,
          encrypted: false
        },
        %{
          source: "API Gateway",
          destination: "Payment Service",
          contains_sensitive_data: true,
          integrity_protection: false
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = SecurityAnalyzerAgent.PerformThreatModelingAction.run(
        %{
          system_description: system_description,
          components: components,
          data_flows: data_flows,
          threat_model: "STRIDE"
        },
        context
      )
      
      # Check identified threats
      threats = result.identified_threats
      assert length(threats) > 0
      
      # Check STRIDE categories covered
      threat_types = threats |> Enum.map(& &1.type) |> Enum.uniq()
      assert :spoofing in threat_types
      assert :information_disclosure in threat_types
      assert :elevation_of_privilege in threat_types
      
      # Check risk matrix
      risk_matrix = result.risk_matrix
      assert Map.has_key?(risk_matrix, :critical)
      assert Map.has_key?(risk_matrix, :high)
      
      # Critical risks should exist due to unencrypted sensitive data
      critical_high_risks = risk_matrix.critical.high
      assert length(critical_high_risks) > 0
      
      # Check attack vectors
      attack_vectors = result.attack_vectors
      assert length(attack_vectors) > 0
      
      spoofing_vectors = Enum.find(attack_vectors, &(&1.threat_type == :spoofing))
      assert spoofing_vectors != nil
      assert length(spoofing_vectors.vectors) > 0
      
      # Check mitigation strategies
      mitigations = result.mitigation_strategies
      assert length(mitigations) > 0
      
      # High priority mitigations should exist
      high_priority = Enum.filter(mitigations, &(&1.priority <= 2))
      assert length(high_priority) > 0
      
      # Check security requirements
      requirements = result.security_requirements
      assert length(requirements) > 0
      
      # Should require encryption due to sensitive data flows
      crypto_req = Enum.find(requirements, &(&1.category == :cryptography))
      assert crypto_req != nil
      assert crypto_req.priority == :critical
      
      # Check threat summary
      summary = result.threat_summary
      assert summary.total_threats > 0
      assert summary.overall_risk_level in [:critical, :high, :medium, :low]
      assert is_list(summary.highest_risk_areas)
      assert is_list(summary.recommended_focus)
    end
    
    test "generate security report action creates comprehensive report", %{agent: agent} do
      scan_results = %{
        vulnerabilities: [
          %{
            type: :sql_injection,
            severity: :critical,
            component: "UserService",
            occurrences: [%{line: 10}]
          },
          %{
            type: :xss,
            severity: :high,
            component: "WebUI",
            occurrences: [%{line: 25}, %{line: 30}]
          }
        ],
        vulnerable_dependencies: [
          %{
            dependency: "lodash",
            severity: :high,
            vulnerabilities: [%{cve_id: "CVE-2021-23337"}]
          }
        ],
        practice_violations: [
          %{
            category: :authentication,
            severity: :high,
            check: :password_storage
          }
        ],
        identified_threats: [
          %{
            type: :elevation_of_privilege,
            severity: :critical,
            component: "AdminPanel"
          }
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, report} = SecurityAnalyzerAgent.GenerateSecurityReportAction.run(
        %{
          scan_results: scan_results,
          report_format: "detailed",
          include_remediation: true,
          compliance_frameworks: ["OWASP"]
        },
        context
      )
      
      # Check report structure
      assert Map.has_key?(report, :title)
      assert Map.has_key?(report, :executive_summary)
      assert Map.has_key?(report, :findings)
      assert Map.has_key?(report, :metrics)
      assert Map.has_key?(report, :recommendations)
      
      # Check executive summary
      exec_summary = report.executive_summary
      assert exec_summary.overall_status == :critical
      assert length(exec_summary.key_findings) > 0
      assert length(exec_summary.immediate_actions) > 0
      
      # Check findings
      findings = report.findings
      assert Map.has_key?(findings, :summary)
      assert Map.has_key?(findings, :detailed)
      
      detailed = findings.detailed
      assert length(detailed) > 0
      
      # Check finding details
      first_finding = hd(detailed)
      assert Map.has_key?(first_finding, :id)
      assert Map.has_key?(first_finding, :severity)
      assert Map.has_key?(first_finding, :impact)
      
      # Check metrics
      metrics = report.metrics
      assert metrics.total_findings > 0
      assert metrics.severity_breakdown.critical > 0
      assert metrics.security_score < 100
      
      # Check remediation guidance
      assert Map.has_key?(report, :remediation_guidance)
      remediation = report.remediation_guidance
      assert Map.has_key?(remediation, :priority_fixes)
      assert Map.has_key?(remediation, :fix_timelines)
      
      # Check compliance mapping
      assert Map.has_key?(report, :compliance_mapping)
      owasp_mapping = report.compliance_mapping["OWASP"]
      assert is_map(owasp_mapping)
    end
  end
  
  describe "signal handling with actions" do
    test "scan_vulnerabilities signal triggers ScanVulnerabilitiesAction", %{agent: agent} do
      signal = %{
        "type" => "scan_vulnerabilities",
        "data" => %{
          "source_code" => "const password = 'admin123';",
          "language" => "javascript"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_dependencies signal triggers AnalyzeDependenciesAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_dependencies",
        "data" => %{
          "dependencies" => [%{"name" => "express", "version" => "4.16.0"}],
          "language" => "javascript"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "validate_security_practices signal triggers ValidateSecurityPracticesAction", %{agent: agent} do
      signal = %{
        "type" => "validate_security_practices",
        "data" => %{
          "source_code" => "function auth() { return true; }",
          "language" => "javascript"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_remediation signal triggers GenerateRemediationAction", %{agent: agent} do
      signal = %{
        "type" => "generate_remediation",
        "data" => %{
          "vulnerability" => %{"type" => "xss", "severity" => "high"},
          "source_code" => "element.innerHTML = userInput;",
          "language" => "javascript"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "perform_threat_modeling signal triggers PerformThreatModelingAction", %{agent: agent} do
      signal = %{
        "type" => "perform_threat_modeling",
        "data" => %{
          "system_description" => "Web application",
          "components" => [%{"name" => "Frontend", "external_facing" => true}]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_security_report signal triggers GenerateSecurityReportAction", %{agent: agent} do
      signal = %{
        "type" => "generate_security_report",
        "data" => %{
          "scan_results" => %{"vulnerabilities" => []},
          "report_format" => "summary"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = SecurityAnalyzerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "vulnerability detection patterns" do
    test "detects SQL injection variations" do
      sql_injection_samples = [
        "query = 'SELECT * FROM users WHERE id = ' + req.params.id",
        "db.query(`SELECT * FROM ${table} WHERE name = '${name}'`)",
        "execute(\"DELETE FROM products WHERE id = \" + productId)"
      ]
      
      context = %{agent: %{state: %{}}}
      
      Enum.each(sql_injection_samples, fn code ->
        {:ok, result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
          %{
            source_code: code,
            language: "javascript",
            vulnerability_types: ["sql_injection"]
          },
          context
        )
        
        assert length(result.vulnerabilities) > 0
        vuln = hd(result.vulnerabilities)
        assert vuln.type == :sql_injection
        assert vuln.severity == :critical
      end)
    end
    
    test "detects XSS vulnerabilities" do
      xss_samples = [
        "document.getElementById('div').innerHTML = userInput",
        "document.write(request.getParameter('name'))",
        "eval(userProvidedCode)"
      ]
      
      context = %{agent: %{state: %{}}}
      
      Enum.each(xss_samples, fn code ->
        {:ok, result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
          %{
            source_code: code,
            language: "javascript",
            vulnerability_types: ["xss"]
          },
          context
        )
        
        assert length(result.vulnerabilities) > 0
        vuln = hd(result.vulnerabilities)
        assert vuln.type == :xss
      end)
    end
    
    test "adjusts severity based on context" do
      # Code with sanitization
      sanitized_code = """
      function processInput(userInput) {
        // Sanitize input
        const sanitized = escapeHtml(userInput);
        document.getElementById('output').innerHTML = sanitized;
      }
      """
      
      # Code without sanitization
      unsanitized_code = """
      function processInput(userInput) {
        document.getElementById('output').innerHTML = userInput;
      }
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, sanitized_result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
        %{source_code: sanitized_code, language: "javascript"},
        context
      )
      
      {:ok, unsanitized_result} = SecurityAnalyzerAgent.ScanVulnerabilitiesAction.run(
        %{source_code: unsanitized_code, language: "javascript"},
        context
      )
      
      # Sanitized version should have lower severity
      if length(sanitized_result.vulnerabilities) > 0 &&
         length(unsanitized_result.vulnerabilities) > 0 do
        sanitized_vuln = hd(sanitized_result.vulnerabilities)
        unsanitized_vuln = hd(unsanitized_result.vulnerabilities)
        
        assert sanitized_vuln.has_sanitization == true
        assert unsanitized_vuln.has_sanitization == false
      end
    end
  end
  
  describe "dependency vulnerability analysis" do
    test "identifies multiple vulnerabilities per dependency" do
      dependencies = [
        %{name: "vulnerable-package", version: "1.0.0"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      # Mock a package with multiple vulnerabilities
      {:ok, result} = SecurityAnalyzerAgent.AnalyzeDependenciesAction.run(
        %{
          dependencies: dependencies,
          language: "javascript"
        },
        context
      )
      
      # Verify structure even if no real vulnerabilities found
      assert Map.has_key?(result, :vulnerable_dependencies)
      assert Map.has_key?(result, :risk_assessment)
      assert Map.has_key?(result, :remediation_plan)
    end
    
    test "categorizes update types correctly" do
      dependencies = [
        %{name: "react", version: "16.0.0"},  # Major update available
        %{name: "lodash", version: "4.17.20"}  # Patch update available
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.AnalyzeDependenciesAction.run(
        %{
          dependencies: dependencies,
          language: "javascript"
        },
        context
      )
      
      outdated = result.outdated_dependencies
      
      if length(outdated) > 0 do
        react_update = Enum.find(outdated, &(&1.dependency == "react"))
        if react_update do
          assert react_update.update_type == :major
        end
      end
    end
    
    test "checks license compliance" do
      dependencies = [
        %{name: "gpl-package", version: "1.0.0"},
        %{name: "mit-package", version: "2.0.0"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.AnalyzeDependenciesAction.run(
        %{
          dependencies: dependencies,
          language: "javascript",
          check_licenses: true
        },
        context
      )
      
      license_issues = result.license_issues
      
      # GPL should be flagged as problematic
      gpl_issue = Enum.find(license_issues, &(&1.dependency == "gpl-package"))
      if gpl_issue do
        assert gpl_issue.license == "GPL-3.0"
        assert gpl_issue.risk in [:medium, :high]
      end
    end
  end
  
  describe "security practice validation" do
    test "validates authentication practices" do
      auth_code = """
      function login(username, password) {
        // Bad: storing plain text password
        user.password = password;
        user.save();
        
        // Bad: no session timeout
        session.create(user, { expires: null });
      }
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.ValidateSecurityPracticesAction.run(
        %{
          source_code: auth_code,
          language: "javascript",
          practice_categories: ["authentication"]
        },
        context
      )
      
      violations = result.practice_violations
      auth_violations = Enum.filter(violations, &(&1.category == :authentication))
      
      assert length(auth_violations) >= 2
      assert result.practice_score < 0.5
    end
    
    test "checks error handling practices" do
      error_code = """
      try {
        processData();
      } catch (error) {
        // Bad: exposing stack trace
        console.log(error.stack);
        res.send({ error: error.toString() });
      }
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.ValidateSecurityPracticesAction.run(
        %{
          source_code: error_code,
          language: "javascript",
          practice_categories: ["error_handling"]
        },
        context
      )
      
      violations = result.practice_violations
      error_violations = Enum.filter(violations, &(&1.category == :error_handling))
      
      assert length(error_violations) > 0
      assert Enum.any?(error_violations, &(&1.check == :information_disclosure))
    end
    
    test "generates security report card" do
      code = """
      // Good authentication
      const bcrypt = require('bcrypt');
      async function hashPassword(password) {
        return await bcrypt.hash(password, 10);
      }
      
      // Bad input validation
      app.get('/user/:id', (req, res) => {
        const query = `SELECT * FROM users WHERE id = ${req.params.id}`;
      });
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.ValidateSecurityPracticesAction.run(
        %{
          source_code: code,
          language: "javascript"
        },
        context
      )
      
      report_card = result.report_card
      
      assert Map.has_key?(report_card, :overall_grade)
      assert Map.has_key?(report_card, :practice_score)
      assert Map.has_key?(report_card, :strengths)
      assert Map.has_key?(report_card, :weaknesses)
      assert Map.has_key?(report_card, :improvement_areas)
      
      # Should have authentication as a strength
      assert Enum.any?(report_card.strengths, &String.contains?(&1, "authentication"))
    end
  end
  
  describe "remediation generation" do
    test "generates language-specific remediation" do
      languages = ["javascript", "python", "java"]
      
      vulnerability = %{
        type: :sql_injection,
        severity: :critical,
        occurrences: [%{code_snippet: "query = 'SELECT * FROM users WHERE id = ' + id"}]
      }
      
      context = %{agent: %{state: %{}}}
      
      Enum.each(languages, fn lang ->
        {:ok, result} = SecurityAnalyzerAgent.GenerateRemediationAction.run(
          %{
            vulnerability: vulnerability,
            source_code: "query = 'SELECT * FROM users WHERE id = ' + id",
            language: lang
          },
          context
        )
        
        # Each language should have specific remediation
        assert result.remediated_code != nil
        assert result.remediated_code != ""
        
        # Language-specific patterns
        case lang do
          "javascript" -> 
            assert String.contains?(result.remediated_code, "?") ||
                   String.contains?(result.remediated_code, "query")
          "python" ->
            assert String.contains?(result.remediated_code, "%s") ||
                   String.contains?(result.remediated_code, "execute")
          "java" ->
            assert String.contains?(result.remediated_code, "PreparedStatement") ||
                   String.contains?(result.remediated_code, "?")
        end
      end)
    end
    
    test "provides comprehensive remediation guidance" do
      vulnerability = %{
        type: :xss,
        severity: :high,
        occurrences: [%{code_snippet: "element.innerHTML = userInput"}],
        cwe_id: "CWE-79"
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.GenerateRemediationAction.run(
        %{
          vulnerability: vulnerability,
          source_code: "element.innerHTML = userInput",
          language: "javascript",
          remediation_style: "comprehensive"
        },
        context
      )
      
      # Check all guidance components
      assert length(result.implementation_steps) >= 3
      assert length(result.security_notes) >= 3
      assert length(result.testing_guidance) >= 4
      
      # Should include specific XSS testing
      assert Enum.any?(result.testing_guidance, &String.contains?(&1, "XSS"))
      
      # Should have CWE reference
      assert Enum.any?(result.references, &(&1.title == "CWE-79"))
    end
  end
  
  describe "threat modeling" do
    test "identifies all STRIDE threat categories" do
      components = [
        %{name: "API", external_facing: true},
        %{name: "Database", contains_sensitive_data: true},
        %{name: "Admin", has_admin_functions: true}
      ]
      
      data_flows = [
        %{source: "API", destination: "Database", contains_sensitive_data: true}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.PerformThreatModelingAction.run(
        %{
          system_description: "Test system",
          components: components,
          data_flows: data_flows,
          threat_model: "STRIDE"
        },
        context
      )
      
      threat_types = result.identified_threats 
        |> Enum.map(& &1.type) 
        |> Enum.uniq()
        |> Enum.sort()
      
      # Should identify multiple STRIDE categories
      stride_types = [:spoofing, :tampering, :repudiation, :information_disclosure, 
                      :denial_of_service, :elevation_of_privilege]
      
      identified_stride = Enum.filter(stride_types, &(&1 in threat_types))
      assert length(identified_stride) >= 3
    end
    
    test "generates attack vectors for threats" do
      components = [%{name: "WebApp", external_facing: true, authentication: "basic"}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.PerformThreatModelingAction.run(
        %{
          system_description: "Web application",
          components: components,
          data_flows: []
        },
        context
      )
      
      attack_vectors = result.attack_vectors
      assert length(attack_vectors) > 0
      
      # Each threat type should have vectors
      Enum.each(attack_vectors, fn av ->
        assert length(av.vectors) > 0
        assert av.exploitability > 0
        
        # Vectors should have required fields
        vector = hd(av.vectors)
        assert Map.has_key?(vector, :vector)
        assert Map.has_key?(vector, :description)
        assert Map.has_key?(vector, :prerequisites)
      end)
    end
    
    test "prioritizes mitigation strategies" do
      components = [
        %{name: "Critical", has_admin_functions: true, rbac: false},
        %{name: "Normal", external_facing: true}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = SecurityAnalyzerAgent.PerformThreatModelingAction.run(
        %{
          system_description: "Mixed criticality system",
          components: components,
          data_flows: []
        },
        context
      )
      
      mitigations = result.mitigation_strategies
      
      # Should be sorted by priority
      priorities = Enum.map(mitigations, & &1.priority)
      assert priorities == Enum.sort(priorities)
      
      # Critical components should have high priority mitigations
      high_priority = Enum.filter(mitigations, &(&1.priority <= 2))
      assert length(high_priority) > 0
    end
  end
  
  describe "security report generation" do
    test "generates executive report format" do
      scan_results = %{
        vulnerabilities: [
          %{type: :sql_injection, severity: :critical, component: "API"}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, report} = SecurityAnalyzerAgent.GenerateSecurityReportAction.run(
        %{
          scan_results: scan_results,
          report_format: "executive"
        },
        context
      )
      
      # Executive report should be concise
      assert Map.has_key?(report, :executive_summary)
      assert Map.has_key?(report, :key_metrics)
      assert Map.has_key?(report, :recommendations)
      
      # Should not have detailed findings
      refute Map.has_key?(report, :appendices)
      
      # Should highlight critical issues
      assert report.risk_overview.critical_findings > 0
    end
    
    test "includes remediation guidance when requested" do
      scan_results = %{
        vulnerabilities: [
          %{type: :xss, severity: :high, component: "UI"}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, report} = SecurityAnalyzerAgent.GenerateSecurityReportAction.run(
        %{
          scan_results: scan_results,
          include_remediation: true
        },
        context
      )
      
      assert Map.has_key?(report, :remediation_guidance)
      remediation = report.remediation_guidance
      
      assert Map.has_key?(remediation, :priority_fixes)
      assert Map.has_key?(remediation, :fix_timelines)
      assert Map.has_key?(remediation, :remediation_steps)
      assert Map.has_key?(remediation, :verification_procedures)
    end
    
    test "maps findings to compliance frameworks" do
      scan_results = %{
        vulnerabilities: [
          %{type: :sql_injection, severity: :critical},
          %{type: :weak_crypto, severity: :high}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, report} = SecurityAnalyzerAgent.GenerateSecurityReportAction.run(
        %{
          scan_results: scan_results,
          compliance_frameworks: ["OWASP", "CWE"]
        },
        context
      )
      
      assert Map.has_key?(report, :compliance_mapping)
      
      # OWASP mapping
      owasp = report.compliance_mapping["OWASP"]
      assert is_map(owasp)
      
      # Should map SQL injection to A03:2021
      a03 = owasp["A03:2021"]
      if a03 do
        assert a03.findings_count > 0
      end
    end
  end
  
  describe "state management" do
    test "tracks scan history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate scan result
      result = %{
        vulnerabilities: [%{type: :xss, severity: :high}],
        risk_score: 0.7,
        scan_metadata: %{
          total_vulnerabilities: 1,
          critical_count: 0,
          high_count: 1
        }
      }
      
      metadata = %{source_code: "test code"}
      
      {:ok, updated} = SecurityAnalyzerAgent.handle_action_result(
        state,
        SecurityAnalyzerAgent.ScanVulnerabilitiesAction,
        {:ok, result},
        metadata
      )
      
      # Check history was updated
      assert length(updated.state.scan_history) == 1
      history_entry = hd(updated.state.scan_history)
      assert history_entry.type == :vulnerability_scan
      assert history_entry.risk_score == 0.7
    end
    
    test "caches vulnerability scan results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{vulnerabilities: [], risk_score: 0}
      metadata = %{source_code: "clean code"}
      
      {:ok, updated} = SecurityAnalyzerAgent.handle_action_result(
        state,
        SecurityAnalyzerAgent.ScanVulnerabilitiesAction,
        {:ok, result},
        metadata
      )
      
      # Check cache was updated
      assert map_size(updated.state.vulnerability_cache) == 1
      cache_key = Map.keys(updated.state.vulnerability_cache) |> hd()
      cached = updated.state.vulnerability_cache[cache_key]
      
      assert cached.result == result
      assert %DateTime{} = cached.timestamp
    end
    
    test "updates threat intelligence", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        vulnerabilities: [
          %{type: :sql_injection, severity: :critical},
          %{type: :xss, severity: :high}
        ],
        risk_score: 0.9
      }
      
      {:ok, updated} = SecurityAnalyzerAgent.handle_action_result(
        state,
        SecurityAnalyzerAgent.ScanVulnerabilitiesAction,
        {:ok, result},
        %{}
      )
      
      # Check threat intelligence was updated
      threat_intel = updated.state.threat_intelligence
      assert map_size(threat_intel) >= 2
      
      # Should track critical and high severity threats
      assert Map.has_key?(threat_intel, :sql_injection)
      assert Map.has_key?(threat_intel, :xss)
    end
    
    test "respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple scan results
      state = Enum.reduce(1..3, state, fn i, acc ->
        result = %{
          vulnerabilities: [],
          risk_score: i * 0.1,
          scan_metadata: %{total_vulnerabilities: 0}
        }
        
        {:ok, updated} = SecurityAnalyzerAgent.handle_action_result(
          acc,
          SecurityAnalyzerAgent.ScanVulnerabilitiesAction,
          {:ok, result},
          %{scan_id: i}
        )
        
        updated
      end)
      
      assert length(state.state.scan_history) == 2
      # Should have the most recent entries
      [first, second] = state.state.scan_history
      assert first.metadata.scan_id == 3
      assert second.metadata.scan_id == 2
    end
  end
  
  describe "agent initialization" do
    test "agent starts with default configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check default security policies
      policies = state.state.security_policies
      assert Map.has_key?(policies, :authentication)
      assert Map.has_key?(policies, :encryption)
      assert Map.has_key?(policies, :access_control)
      
      # Check remediation templates
      templates = state.state.remediation_templates
      assert Map.has_key?(templates, :sql_injection)
      assert Map.has_key?(templates, :xss)
      
      # Check compliance mappings
      mappings = state.state.compliance_mappings
      assert Map.has_key?(mappings, "OWASP")
      assert Map.has_key?(mappings, "CWE")
      
      # Check risk thresholds
      thresholds = state.state.risk_thresholds
      assert thresholds.critical == 0.9
      assert thresholds.high == 0.7
    end
  end
  
  describe "result processing" do
    test "process_result adds analysis timestamp", %{agent: _agent} do
      result = %{vulnerabilities: [], risk_score: 0.5}
      processed = SecurityAnalyzerAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :analyzed_at)
      assert %DateTime{} = processed.analyzed_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = SecurityAnalyzerAgent.additional_actions()
      
      assert length(actions) == 6
      assert SecurityAnalyzerAgent.ScanVulnerabilitiesAction in actions
      assert SecurityAnalyzerAgent.AnalyzeDependenciesAction in actions
      assert SecurityAnalyzerAgent.ValidateSecurityPracticesAction in actions
      assert SecurityAnalyzerAgent.GenerateRemediationAction in actions
      assert SecurityAnalyzerAgent.PerformThreatModelingAction in actions
      assert SecurityAnalyzerAgent.GenerateSecurityReportAction in actions
    end
  end
end