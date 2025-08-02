defmodule RubberDuck.Tools.Agents.SecurityAnalyzerAgent do
  @moduledoc """
  Agent that analyzes code for security vulnerabilities and provides remediation recommendations.
  
  Capabilities:
  - Vulnerability scanning with OWASP Top 10 coverage
  - Static code analysis for security patterns
  - Dependency vulnerability assessment
  - Security best practices validation
  - Threat modeling and risk assessment
  - Remediation guidance with code fixes
  """
  
  use RubberDuck.Tools.BaseToolAgent, tool: :security_analyzer
  
  alias Jido.Agent.Server.State
  
  # Custom actions for security analysis
  defmodule ScanVulnerabilitiesAction do
    @moduledoc """
    Scans code for security vulnerabilities using pattern matching and static analysis.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to scan"],
        language: [type: :string, required: true, doc: "Programming language"],
        scan_depth: [type: :string, default: "standard", doc: "Scan depth: basic, standard, comprehensive"],
        vulnerability_types: [type: {:list, :string}, doc: "Specific vulnerability types to check"],
        context: [type: :map, doc: "Additional context about the codebase"]
      }
    end
    
    @impl true
    def run(params, _context) do
      vulnerabilities = scan_for_vulnerabilities(
        params.source_code,
        params.language,
        params.scan_depth,
        params.vulnerability_types
      )
      
      risk_score = calculate_overall_risk(vulnerabilities)
      
      {:ok, %{
        vulnerabilities: vulnerabilities,
        risk_score: risk_score,
        summary: generate_vulnerability_summary(vulnerabilities),
        scan_metadata: %{
          language: params.language,
          scan_depth: params.scan_depth,
          total_vulnerabilities: length(vulnerabilities),
          critical_count: count_by_severity(vulnerabilities, :critical),
          high_count: count_by_severity(vulnerabilities, :high),
          medium_count: count_by_severity(vulnerabilities, :medium),
          low_count: count_by_severity(vulnerabilities, :low)
        }
      }}
    end
    
    defp scan_for_vulnerabilities(code, language, depth, specific_types) do
      patterns = get_vulnerability_patterns(language, specific_types)
      
      vulnerabilities = patterns
        |> Enum.flat_map(fn pattern ->
          case scan_with_pattern(code, pattern, depth) do
            nil -> []
            vuln -> [vuln]
          end
        end)
        |> add_context_analysis(code, language)
        |> prioritize_vulnerabilities()
      
      vulnerabilities
    end
    
    defp get_vulnerability_patterns(language, specific_types) do
      base_patterns = [
        # SQL Injection
        %{
          type: :sql_injection,
          patterns: [
            ~r/SELECT.*FROM.*WHERE.*\+.*['"]?/i,
            ~r/execute\s*\(\s*["'].*\+/i,
            ~r/query\s*\(\s*["'].*\$\{/i
          ],
          severity: :critical,
          cwe_id: "CWE-89"
        },
        # XSS
        %{
          type: :xss,
          patterns: [
            ~r/innerHTML\s*=.*\$\{/,
            ~r/document\.write\s*\(/,
            ~r/eval\s*\(/
          ],
          severity: :high,
          cwe_id: "CWE-79"
        },
        # Command Injection
        %{
          type: :command_injection,
          patterns: [
            ~r/exec\s*\(.*\$\{/,
            ~r/system\s*\(.*\+/,
            ~r/spawn\s*\(.*user_input/
          ],
          severity: :critical,
          cwe_id: "CWE-78"
        },
        # Path Traversal
        %{
          type: :path_traversal,
          patterns: [
            ~r/\.\.\/|\.\.\\/, 
            ~r/readFile.*\+.*user/i,
            ~r/open\s*\(.*\$\{/
          ],
          severity: :high,
          cwe_id: "CWE-22"
        },
        # Weak Cryptography
        %{
          type: :weak_crypto,
          patterns: [
            ~r/md5\s*\(/i,
            ~r/sha1\s*\(/i,
            ~r/des\s*\(/i
          ],
          severity: :medium,
          cwe_id: "CWE-327"
        },
        # Hardcoded Secrets
        %{
          type: :hardcoded_secrets,
          patterns: [
            ~r/password\s*=\s*["'][^"']{8,}/i,
            ~r/api_key\s*=\s*["'][^"']+/i,
            ~r/secret\s*=\s*["'][^"']+/i
          ],
          severity: :high,
          cwe_id: "CWE-798"
        }
      ]
      
      # Filter by specific types if provided
      patterns = if specific_types && length(specific_types) > 0 do
        specific_atoms = Enum.map(specific_types, &String.to_atom/1)
        Enum.filter(base_patterns, &(&1.type in specific_atoms))
      else
        base_patterns
      end
      
      # Add language-specific patterns
      patterns ++ get_language_specific_patterns(language)
    end
    
    defp get_language_specific_patterns("javascript"), do: [
      %{
        type: :prototype_pollution,
        patterns: [~r/Object\.assign\s*\(\s*\{?\}?,.*req\./],
        severity: :high,
        cwe_id: "CWE-1321"
      }
    ]
    defp get_language_specific_patterns("python"), do: [
      %{
        type: :pickle_deserialization,
        patterns: [~r/pickle\.loads?\s*\(/],
        severity: :critical,
        cwe_id: "CWE-502"
      }
    ]
    defp get_language_specific_patterns(_), do: []
    
    defp scan_with_pattern(code, pattern_def, depth) do
      lines = String.split(code, "\n")
      
      matches = pattern_def.patterns
        |> Enum.flat_map(fn pattern ->
          lines
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _} -> Regex.match?(pattern, line) end)
          |> Enum.map(fn {line, line_num} ->
            %{
              line: line_num,
              code_snippet: String.trim(line),
              pattern: inspect(pattern)
            }
          end)
        end)
      
      if length(matches) > 0 do
        %{
          type: pattern_def.type,
          severity: pattern_def.severity,
          cwe_id: pattern_def.cwe_id,
          occurrences: matches,
          confidence: calculate_confidence(matches, depth),
          description: get_vulnerability_description(pattern_def.type),
          impact: get_vulnerability_impact(pattern_def.type)
        }
      else
        nil
      end
    end
    
    defp calculate_confidence(matches, depth) do
      base_confidence = case depth do
        "comprehensive" -> 0.9
        "standard" -> 0.75
        _ -> 0.6
      end
      
      # Increase confidence with more matches
      match_factor = min(1.0, 0.6 + (length(matches) * 0.1))
      base_confidence * match_factor
    end
    
    defp add_context_analysis(vulnerabilities, code, language) do
      # Add context-aware analysis to reduce false positives
      vulnerabilities
      |> Enum.map(fn vuln ->
        vuln
        |> add_data_flow_context(code)
        |> add_sanitization_check(code, language)
        |> adjust_severity_by_context()
      end)
    end
    
    defp add_data_flow_context(vuln, code) do
      # Simple data flow analysis - check if user input reaches vulnerable code
      Map.put(vuln, :user_input_flow, check_user_input_flow(vuln, code))
    end
    
    defp check_user_input_flow(vuln, code) do
      # Simplified check - in real implementation would trace data flow
      user_input_patterns = [~r/request\./i, ~r/params\[/i, ~r/user_input/i, ~r/req\./]
      
      Enum.any?(vuln.occurrences, fn occurrence ->
        line_content = occurrence.code_snippet
        Enum.any?(user_input_patterns, &Regex.match?(&1, line_content))
      end)
    end
    
    defp add_sanitization_check(vuln, code, _language) do
      # Check if there's sanitization near vulnerable code
      sanitization_patterns = [
        ~r/sanitize/i, ~r/escape/i, ~r/validate/i, 
        ~r/filter/i, ~r/clean/i, ~r/safe/i
      ]
      
      has_sanitization = Enum.any?(vuln.occurrences, fn occurrence ->
        # Check lines around the vulnerability
        check_nearby_lines_for_patterns(code, occurrence.line, sanitization_patterns, 3)
      end)
      
      Map.put(vuln, :has_sanitization, has_sanitization)
    end
    
    defp check_nearby_lines_for_patterns(code, line_num, patterns, radius) do
      lines = String.split(code, "\n")
      start_line = max(0, line_num - radius - 1)
      end_line = min(length(lines) - 1, line_num + radius - 1)
      
      nearby_lines = Enum.slice(lines, start_line..end_line)
      
      Enum.any?(nearby_lines, fn line ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)
    end
    
    defp adjust_severity_by_context(vuln) do
      cond do
        # Downgrade if sanitization is present
        vuln.has_sanitization && vuln.severity in [:high, :critical] ->
          Map.put(vuln, :severity, downgrade_severity(vuln.severity))
        
        # Upgrade if user input flows to vulnerability
        vuln.user_input_flow && vuln.severity in [:low, :medium] ->
          Map.put(vuln, :severity, upgrade_severity(vuln.severity))
        
        true ->
          vuln
      end
    end
    
    defp downgrade_severity(:critical), do: :high
    defp downgrade_severity(:high), do: :medium
    defp downgrade_severity(:medium), do: :low
    defp downgrade_severity(severity), do: severity
    
    defp upgrade_severity(:low), do: :medium
    defp upgrade_severity(:medium), do: :high
    defp upgrade_severity(:high), do: :critical
    defp upgrade_severity(severity), do: severity
    
    defp prioritize_vulnerabilities(vulnerabilities) do
      vulnerabilities
      |> Enum.sort_by(fn vuln ->
        severity_score = case vuln.severity do
          :critical -> 4
          :high -> 3
          :medium -> 2
          :low -> 1
        end
        
        # Consider confidence and user input flow
        priority_score = severity_score * vuln.confidence
        priority_score = if vuln.user_input_flow, do: priority_score * 1.5, else: priority_score
        
        -priority_score  # Negative for descending sort
      end)
    end
    
    defp calculate_overall_risk(vulnerabilities) do
      if length(vulnerabilities) == 0 do
        0.0
      else
        severity_scores = Enum.map(vulnerabilities, fn vuln ->
          base_score = case vuln.severity do
            :critical -> 10.0
            :high -> 7.5
            :medium -> 5.0
            :low -> 2.5
          end
          
          base_score * vuln.confidence
        end)
        
        # Calculate weighted average with emphasis on highest scores
        max_score = Enum.max(severity_scores)
        avg_score = Enum.sum(severity_scores) / length(severity_scores)
        
        # Weighted combination
        (max_score * 0.7 + avg_score * 0.3) / 10.0
      end
    end
    
    defp generate_vulnerability_summary(vulnerabilities) do
      if length(vulnerabilities) == 0 do
        "No security vulnerabilities detected."
      else
        critical_count = count_by_severity(vulnerabilities, :critical)
        high_count = count_by_severity(vulnerabilities, :high)
        
        summary = "Found #{length(vulnerabilities)} security vulnerabilities"
        
        if critical_count > 0 || high_count > 0 do
          summary <> " including #{critical_count} critical and #{high_count} high severity issues."
        else
          summary <> "."
        end
      end
    end
    
    defp count_by_severity(vulnerabilities, severity) do
      vulnerabilities
      |> Enum.filter(&(&1.severity == severity))
      |> length()
    end
    
    defp get_vulnerability_description(:sql_injection) do
      "SQL Injection vulnerability allows attackers to interfere with database queries."
    end
    defp get_vulnerability_description(:xss) do
      "Cross-Site Scripting (XSS) allows attackers to inject malicious scripts."
    end
    defp get_vulnerability_description(:command_injection) do
      "Command Injection allows attackers to execute arbitrary system commands."
    end
    defp get_vulnerability_description(:path_traversal) do
      "Path Traversal allows attackers to access files outside intended directories."
    end
    defp get_vulnerability_description(:weak_crypto) do
      "Weak cryptographic algorithms can be easily broken by attackers."
    end
    defp get_vulnerability_description(:hardcoded_secrets) do
      "Hardcoded secrets expose sensitive credentials in source code."
    end
    defp get_vulnerability_description(:prototype_pollution) do
      "Prototype Pollution allows attackers to modify JavaScript object prototypes."
    end
    defp get_vulnerability_description(:pickle_deserialization) do
      "Unsafe deserialization can lead to remote code execution."
    end
    defp get_vulnerability_description(_) do
      "Security vulnerability detected."
    end
    
    defp get_vulnerability_impact(:sql_injection) do
      "Data breach, data manipulation, authentication bypass"
    end
    defp get_vulnerability_impact(:xss) do
      "Session hijacking, defacement, malicious redirects"
    end
    defp get_vulnerability_impact(:command_injection) do
      "Full system compromise, data theft, service disruption"
    end
    defp get_vulnerability_impact(:path_traversal) do
      "Unauthorized file access, sensitive data exposure"
    end
    defp get_vulnerability_impact(:weak_crypto) do
      "Compromised data confidentiality, broken authentication"
    end
    defp get_vulnerability_impact(:hardcoded_secrets) do
      "Unauthorized access, privilege escalation"
    end
    defp get_vulnerability_impact(:prototype_pollution) do
      "Application logic manipulation, denial of service"
    end
    defp get_vulnerability_impact(:pickle_deserialization) do
      "Remote code execution, complete system compromise"
    end
    defp get_vulnerability_impact(_) do
      "Security compromise"
    end
  end
  
  defmodule AnalyzeDependenciesAction do
    @moduledoc """
    Analyzes project dependencies for known vulnerabilities and outdated packages.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        dependencies: [type: {:list, :map}, required: true, doc: "List of dependencies with name and version"],
        language: [type: :string, required: true, doc: "Programming language/ecosystem"],
        check_licenses: [type: :boolean, default: true, doc: "Check for license compliance"],
        severity_threshold: [type: :string, default: "medium", doc: "Minimum severity to report"]
      }
    end
    
    @impl true
    def run(params, _context) do
      vulnerable_deps = check_vulnerability_databases(params.dependencies, params.language)
      outdated_deps = check_outdated_dependencies(params.dependencies, params.language)
      license_issues = if params.check_licenses do
        check_license_compliance(params.dependencies)
      else
        []
      end
      
      risk_assessment = assess_dependency_risk(vulnerable_deps, outdated_deps)
      
      {:ok, %{
        vulnerable_dependencies: vulnerable_deps,
        outdated_dependencies: outdated_deps,
        license_issues: license_issues,
        risk_assessment: risk_assessment,
        summary: generate_dependency_summary(vulnerable_deps, outdated_deps, license_issues),
        remediation_plan: generate_remediation_plan(vulnerable_deps, outdated_deps)
      }}
    end
    
    defp check_vulnerability_databases(dependencies, language) do
      # Simulate checking CVE database and ecosystem-specific databases
      dependencies
      |> Enum.map(fn dep ->
        vulnerabilities = find_known_vulnerabilities(dep, language)
        
        if length(vulnerabilities) > 0 do
          %{
            dependency: dep.name,
            current_version: dep.version,
            vulnerabilities: vulnerabilities,
            severity: get_highest_severity(vulnerabilities),
            safe_versions: find_safe_versions(dep.name, vulnerabilities)
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
    end
    
    defp find_known_vulnerabilities(dep, _language) do
      # Simulate vulnerability lookup
      known_vulnerabilities = %{
        "express" => [
          %{
            cve_id: "CVE-2022-24999",
            severity: :high,
            affected_versions: "< 4.18.0",
            description: "ReDoS vulnerability in query parser"
          }
        ],
        "django" => [
          %{
            cve_id: "CVE-2023-23969",
            severity: :medium,
            affected_versions: "< 3.2.17",
            description: "Potential DoS via multipart parsing"
          }
        ],
        "lodash" => [
          %{
            cve_id: "CVE-2021-23337",
            severity: :high,
            affected_versions: "< 4.17.21",
            description: "Command injection via template function"
          }
        ],
        "log4j" => [
          %{
            cve_id: "CVE-2021-44228",
            severity: :critical,
            affected_versions: ">= 2.0.0, < 2.17.0",
            description: "Remote code execution via JNDI"
          }
        ]
      }
      
      vulns = Map.get(known_vulnerabilities, dep.name, [])
      
      # Filter by version
      Enum.filter(vulns, fn vuln ->
        version_matches?(dep.version, vuln.affected_versions)
      end)
    end
    
    defp version_matches?(version, constraint) do
      # Simplified version matching
      cond do
        String.contains?(constraint, "<") ->
          # Extract version number from constraint
          [_, max_version] = String.split(constraint, " ")
          version < max_version
        
        String.contains?(constraint, ">") ->
          # Handle range constraints
          true  # Simplified for this example
        
        true ->
          false
      end
    end
    
    defp get_highest_severity(vulnerabilities) do
      severities = Enum.map(vulnerabilities, & &1.severity)
      
      cond do
        :critical in severities -> :critical
        :high in severities -> :high
        :medium in severities -> :medium
        :low in severities -> :low
        true -> :info
      end
    end
    
    defp find_safe_versions(dep_name, vulnerabilities) do
      # Simulate finding safe versions
      safe_versions = %{
        "express" => ["4.18.2", "4.19.0"],
        "django" => ["3.2.18", "4.1.7", "4.2.0"],
        "lodash" => ["4.17.21"],
        "log4j" => ["2.17.1", "2.18.0", "2.19.0"]
      }
      
      Map.get(safe_versions, dep_name, [])
    end
    
    defp check_outdated_dependencies(dependencies, _language) do
      dependencies
      |> Enum.map(fn dep ->
        latest_version = get_latest_version(dep.name)
        
        if latest_version && dep.version < latest_version do
          %{
            dependency: dep.name,
            current_version: dep.version,
            latest_version: latest_version,
            versions_behind: calculate_versions_behind(dep.version, latest_version),
            update_type: categorize_update(dep.version, latest_version)
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
    end
    
    defp get_latest_version(dep_name) do
      # Simulate latest version lookup
      latest_versions = %{
        "express" => "4.19.2",
        "django" => "4.2.7",
        "react" => "18.2.0",
        "lodash" => "4.17.21",
        "axios" => "1.6.0"
      }
      
      Map.get(latest_versions, dep_name)
    end
    
    defp calculate_versions_behind(current, latest) do
      # Simplified calculation
      current_parts = String.split(current, ".") |> Enum.map(&String.to_integer/1)
      latest_parts = String.split(latest, ".") |> Enum.map(&String.to_integer/1)
      
      major_diff = Enum.at(latest_parts, 0, 0) - Enum.at(current_parts, 0, 0)
      minor_diff = Enum.at(latest_parts, 1, 0) - Enum.at(current_parts, 1, 0)
      
      cond do
        major_diff > 0 -> "#{major_diff} major"
        minor_diff > 0 -> "#{minor_diff} minor"
        true -> "patch"
      end
    end
    
    defp categorize_update(current, latest) do
      current_parts = String.split(current, ".") |> Enum.map(&String.to_integer/1)
      latest_parts = String.split(latest, ".") |> Enum.map(&String.to_integer/1)
      
      cond do
        Enum.at(latest_parts, 0) > Enum.at(current_parts, 0) -> :major
        Enum.at(latest_parts, 1) > Enum.at(current_parts, 1) -> :minor
        true -> :patch
      end
    end
    
    defp check_license_compliance(dependencies) do
      dependencies
      |> Enum.map(fn dep ->
        license = get_dependency_license(dep.name)
        
        if license && is_problematic_license?(license) do
          %{
            dependency: dep.name,
            license: license,
            issue: categorize_license_issue(license),
            risk: assess_license_risk(license)
          }
        else
          nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
    end
    
    defp get_dependency_license(dep_name) do
      # Simulate license lookup
      licenses = %{
        "gpl-package" => "GPL-3.0",
        "agpl-lib" => "AGPL-3.0",
        "commercial-sdk" => "Commercial",
        "express" => "MIT",
        "react" => "MIT"
      }
      
      Map.get(licenses, dep_name)
    end
    
    defp is_problematic_license?(license) do
      problematic = ["GPL-3.0", "AGPL-3.0", "Commercial", "SSPL-1.0"]
      license in problematic
    end
    
    defp categorize_license_issue(license) do
      case license do
        "GPL-3.0" -> "Copyleft license requiring source disclosure"
        "AGPL-3.0" -> "Strong copyleft affecting network use"
        "Commercial" -> "Requires commercial license for use"
        _ -> "License compatibility concern"
      end
    end
    
    defp assess_license_risk(license) do
      case license do
        "AGPL-3.0" -> :high
        "GPL-3.0" -> :medium
        "Commercial" -> :high
        _ -> :low
      end
    end
    
    defp assess_dependency_risk(vulnerable_deps, outdated_deps) do
      vuln_score = calculate_vulnerability_score(vulnerable_deps)
      outdated_score = calculate_outdated_score(outdated_deps)
      
      overall_risk = (vuln_score * 0.7 + outdated_score * 0.3) / 10.0
      
      %{
        overall_risk: overall_risk,
        vulnerability_risk: vuln_score / 10.0,
        maintenance_risk: outdated_score / 10.0,
        risk_level: categorize_risk_level(overall_risk),
        recommendations: generate_risk_recommendations(overall_risk, vulnerable_deps, outdated_deps)
      }
    end
    
    defp calculate_vulnerability_score(vulnerable_deps) do
      vulnerable_deps
      |> Enum.map(fn dep ->
        case dep.severity do
          :critical -> 10.0
          :high -> 7.5
          :medium -> 5.0
          :low -> 2.5
        end
      end)
      |> Enum.sum()
      |> min(10.0)
    end
    
    defp calculate_outdated_score(outdated_deps) do
      outdated_deps
      |> Enum.map(fn dep ->
        case dep.update_type do
          :major -> 3.0
          :minor -> 1.5
          :patch -> 0.5
        end
      end)
      |> Enum.sum()
      |> min(10.0)
    end
    
    defp categorize_risk_level(risk_score) do
      cond do
        risk_score >= 0.8 -> :critical
        risk_score >= 0.6 -> :high
        risk_score >= 0.4 -> :medium
        risk_score >= 0.2 -> :low
        true -> :minimal
      end
    end
    
    defp generate_risk_recommendations(risk_score, vulnerable_deps, _outdated_deps) do
      recommendations = []
      
      recommendations = if risk_score >= 0.6 do
        ["Immediate action required: Update vulnerable dependencies"] ++ recommendations
      else
        recommendations
      end
      
      recommendations = if length(vulnerable_deps) > 0 do
        ["Create dependency update plan prioritizing security fixes"] ++ recommendations
      else
        recommendations
      end
      
      recommendations = if risk_score >= 0.4 do
        ["Schedule regular dependency audits"] ++ recommendations
      else
        recommendations
      end
      
      recommendations
    end
    
    defp generate_dependency_summary(vulnerable_deps, outdated_deps, license_issues) do
      parts = []
      
      parts = if length(vulnerable_deps) > 0 do
        ["#{length(vulnerable_deps)} vulnerable dependencies"] ++ parts
      else
        parts
      end
      
      parts = if length(outdated_deps) > 0 do
        ["#{length(outdated_deps)} outdated packages"] ++ parts
      else
        parts
      end
      
      parts = if length(license_issues) > 0 do
        ["#{length(license_issues)} license concerns"] ++ parts
      else
        parts
      end
      
      if length(parts) > 0 do
        "Found " <> Enum.join(parts, ", ") <> "."
      else
        "All dependencies appear secure and up-to-date."
      end
    end
    
    defp generate_remediation_plan(vulnerable_deps, outdated_deps) do
      steps = []
      
      # Add steps for vulnerable dependencies
      vuln_steps = vulnerable_deps
        |> Enum.sort_by(&severity_priority(&1.severity))
        |> Enum.map(fn dep ->
          %{
            action: :update_dependency,
            dependency: dep.dependency,
            current_version: dep.current_version,
            target_version: hd(dep.safe_versions || []),
            priority: dep.severity,
            reason: "Security vulnerability: #{hd(dep.vulnerabilities).cve_id}"
          }
        end)
      
      steps = steps ++ vuln_steps
      
      # Add steps for critically outdated dependencies
      outdated_steps = outdated_deps
        |> Enum.filter(&(&1.update_type == :major))
        |> Enum.take(5)  # Limit to top 5
        |> Enum.map(fn dep ->
          %{
            action: :update_dependency,
            dependency: dep.dependency,
            current_version: dep.current_version,
            target_version: dep.latest_version,
            priority: :medium,
            reason: "Major version behind: #{dep.versions_behind}"
          }
        end)
      
      steps ++ outdated_steps
    end
    
    defp severity_priority(:critical), do: 0
    defp severity_priority(:high), do: 1
    defp severity_priority(:medium), do: 2
    defp severity_priority(:low), do: 3
  end
  
  defmodule ValidateSecurityPracticesAction do
    @moduledoc """
    Validates code against security best practices and coding standards.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        source_code: [type: :string, required: true, doc: "Source code to validate"],
        language: [type: :string, required: true, doc: "Programming language"],
        practice_categories: [type: {:list, :string}, doc: "Specific categories to check"],
        compliance_standards: [type: {:list, :string}, doc: "Standards to check (OWASP, CWE, etc.)"]
      }
    end
    
    @impl true
    def run(params, _context) do
      practices = check_security_practices(
        params.source_code,
        params.language,
        params.practice_categories
      )
      
      compliance = if params.compliance_standards do
        check_compliance(params.source_code, params.compliance_standards)
      else
        %{compliant: true, violations: []}
      end
      
      {:ok, %{
        practice_violations: practices.violations,
        practice_score: practices.score,
        compliance_status: compliance,
        recommendations: generate_practice_recommendations(practices, compliance),
        report_card: generate_security_report_card(practices, compliance)
      }}
    end
    
    defp check_security_practices(code, language, categories) do
      all_checks = get_security_checks(language, categories)
      
      violations = all_checks
        |> Enum.flat_map(fn check ->
          case run_practice_check(code, check) do
            nil -> []
            violation -> [violation]
          end
        end)
      
      score = calculate_practice_score(violations, length(all_checks))
      
      %{
        violations: violations,
        score: score,
        total_checks: length(all_checks),
        passed_checks: length(all_checks) - length(violations)
      }
    end
    
    defp get_security_checks(language, categories) do
      base_checks = [
        %{
          category: "authentication",
          check: :password_storage,
          patterns: [~r/password.*=.*plain/i, ~r/store.*password.*text/i],
          message: "Passwords should be hashed, not stored in plain text"
        },
        %{
          category: "authentication",
          check: :session_management,
          patterns: [~r/session.*never.*expire/i, ~r/timeout.*=.*0/],
          message: "Sessions should have appropriate timeouts"
        },
        %{
          category: "input_validation",
          check: :missing_validation,
          patterns: [~r/request\.\w+(?!\s*\.|;)/],
          message: "User input should be validated before use"
        },
        %{
          category: "error_handling",
          check: :information_disclosure,
          patterns: [~r/catch.*\{.*console\.log.*error/i, ~r/printStackTrace/],
          message: "Error details should not be exposed to users"
        },
        %{
          category: "cryptography",
          check: :random_generation,
          patterns: [~r/Math\.random.*password/i, ~r/rand\(\).*token/i],
          message: "Use cryptographically secure random generation"
        },
        %{
          category: "access_control",
          check: :missing_authorization,
          patterns: [~r/admin.*route.*(?!auth)/i, ~r/delete.*(?!authorize)/i],
          message: "Sensitive operations require authorization checks"
        }
      ]
      
      # Filter by categories if specified
      if categories && length(categories) > 0 do
        category_atoms = Enum.map(categories, &String.to_atom/1)
        Enum.filter(base_checks, &(&1.category in category_atoms))
      else
        base_checks
      end
    end
    
    defp run_practice_check(code, check) do
      violations = check.patterns
        |> Enum.flat_map(fn pattern ->
          code
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _} -> Regex.match?(pattern, line) end)
          |> Enum.map(fn {line, line_num} -> 
            %{line: line_num, code: String.trim(line)}
          end)
        end)
      
      if length(violations) > 0 do
        %{
          category: check.category,
          check: check.check,
          severity: categorize_practice_severity(check.category),
          message: check.message,
          violations: violations
        }
      else
        nil
      end
    end
    
    defp categorize_practice_severity(:authentication), do: :high
    defp categorize_practice_severity(:cryptography), do: :high
    defp categorize_practice_severity(:access_control), do: :high
    defp categorize_practice_severity(:input_validation), do: :medium
    defp categorize_practice_severity(:error_handling), do: :medium
    defp categorize_practice_severity(_), do: :low
    
    defp calculate_practice_score(violations, total_checks) do
      if total_checks == 0 do
        1.0
      else
        passed = total_checks - length(violations)
        
        # Weight by severity
        weighted_violations = violations
          |> Enum.map(fn v ->
            case v.severity do
              :high -> 3
              :medium -> 2
              :low -> 1
            end
          end)
          |> Enum.sum()
        
        max_penalty = total_checks * 3
        1.0 - (weighted_violations / max_penalty)
      end
    end
    
    defp check_compliance(code, standards) do
      violations = standards
        |> Enum.flat_map(fn standard ->
          check_standard_compliance(code, standard)
        end)
      
      %{
        compliant: length(violations) == 0,
        violations: violations,
        standards_checked: standards
      }
    end
    
    defp check_standard_compliance(code, "OWASP") do
      # Check OWASP Top 10 compliance
      owasp_checks = [
        %{
          rule: "A01:2021 - Broken Access Control",
          check: ~r/(?!.*authorize).*delete|update|admin/i,
          message: "Ensure proper authorization for sensitive operations"
        },
        %{
          rule: "A02:2021 - Cryptographic Failures", 
          check: ~r/md5|sha1|des|ecb/i,
          message: "Use strong cryptographic algorithms"
        },
        %{
          rule: "A03:2021 - Injection",
          check: ~r/query.*\+.*user|exec.*\$\{/i,
          message: "Use parameterized queries to prevent injection"
        }
      ]
      
      check_rules(code, owasp_checks, "OWASP")
    end
    
    defp check_standard_compliance(code, "CWE") do
      # Check common CWE violations
      cwe_checks = [
        %{
          rule: "CWE-798 - Hardcoded Credentials",
          check: ~r/password\s*=\s*["'][^"']+["']/i,
          message: "Do not hardcode credentials"
        },
        %{
          rule: "CWE-89 - SQL Injection",
          check: ~r/SELECT.*WHERE.*\+/i,
          message: "Use prepared statements"
        }
      ]
      
      check_rules(code, cwe_checks, "CWE")
    end
    
    defp check_standard_compliance(_code, _standard), do: []
    
    defp check_rules(code, rules, standard) do
      rules
      |> Enum.flat_map(fn rule ->
        if Regex.match?(rule.check, code) do
          [%{
            standard: standard,
            rule: rule.rule,
            message: rule.message,
            severity: :high
          }]
        else
          []
        end
      end)
    end
    
    defp generate_practice_recommendations(practices, compliance) do
      recommendations = []
      
      # Add recommendations based on violations
      category_recommendations = practices.violations
        |> Enum.map(& &1.category)
        |> Enum.uniq()
        |> Enum.map(fn category ->
          case category do
            :authentication -> 
              "Implement secure authentication: use bcrypt/scrypt for passwords, implement MFA"
            :cryptography ->
              "Use industry-standard cryptographic libraries and algorithms"
            :input_validation ->
              "Validate and sanitize all user inputs before processing"
            :access_control ->
              "Implement role-based access control with principle of least privilege"
            _ ->
              "Review and update security practices for #{category}"
          end
        end)
      
      recommendations = recommendations ++ category_recommendations
      
      # Add compliance recommendations
      if !compliance.compliant do
        compliance_recs = ["Address compliance violations to meet security standards"]
        recommendations ++ compliance_recs
      else
        recommendations
      end
    end
    
    defp generate_security_report_card(practices, compliance) do
      grade = calculate_security_grade(practices.score, compliance.compliant)
      
      %{
        overall_grade: grade,
        practice_score: Float.round(practices.score * 100, 1),
        total_checks: practices.total_checks,
        passed_checks: practices.passed_checks,
        compliance_status: if(compliance.compliant, do: "Compliant", else: "Non-compliant"),
        strengths: identify_strengths(practices),
        weaknesses: identify_weaknesses(practices),
        improvement_areas: identify_improvement_areas(practices, compliance)
      }
    end
    
    defp calculate_security_grade(score, compliant) do
      adjusted_score = if compliant, do: score, else: score * 0.9
      
      cond do
        adjusted_score >= 0.9 -> "A"
        adjusted_score >= 0.8 -> "B"
        adjusted_score >= 0.7 -> "C"
        adjusted_score >= 0.6 -> "D"
        true -> "F"
      end
    end
    
    defp identify_strengths(practices) do
      all_categories = [:authentication, :cryptography, :input_validation, :access_control, :error_handling]
      violated_categories = practices.violations |> Enum.map(& &1.category) |> Enum.uniq()
      
      strong_categories = all_categories -- violated_categories
      
      Enum.map(strong_categories, fn cat ->
        "Strong #{cat} practices"
      end)
    end
    
    defp identify_weaknesses(practices) do
      practices.violations
      |> Enum.group_by(& &1.category)
      |> Enum.map(fn {category, violations} ->
        "#{category}: #{length(violations)} issues found"
      end)
    end
    
    defp identify_improvement_areas(practices, compliance) do
      areas = []
      
      areas = if practices.score < 0.8 do
        ["Improve overall security practices"] ++ areas
      else
        areas
      end
      
      areas = if !compliance.compliant do
        ["Achieve compliance with security standards"] ++ areas
      else
        areas
      end
      
      high_severity_count = practices.violations
        |> Enum.filter(&(&1.severity == :high))
        |> length()
      
      if high_severity_count > 0 do
        ["Address #{high_severity_count} high-severity security issues"] ++ areas
      else
        areas
      end
    end
  end
  
  defmodule GenerateRemediationAction do
    @moduledoc """
    Generates remediation code and guidance for security vulnerabilities.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        vulnerability: [type: :map, required: true, doc: "Vulnerability details to remediate"],
        source_code: [type: :string, required: true, doc: "Original vulnerable code"],
        language: [type: :string, required: true, doc: "Programming language"],
        remediation_style: [type: :string, default: "secure", doc: "Style: secure, minimal, comprehensive"]
      }
    end
    
    @impl true
    def run(params, _context) do
      remediation = generate_remediation(
        params.vulnerability,
        params.source_code,
        params.language,
        params.remediation_style
      )
      
      {:ok, %{
        remediated_code: remediation.fixed_code,
        explanation: remediation.explanation,
        implementation_steps: remediation.steps,
        security_notes: remediation.security_notes,
        testing_guidance: generate_testing_guidance(params.vulnerability),
        references: generate_references(params.vulnerability)
      }}
    end
    
    defp generate_remediation(vulnerability, code, language, style) do
      case vulnerability.type do
        :sql_injection ->
          remediate_sql_injection(vulnerability, code, language, style)
        :xss ->
          remediate_xss(vulnerability, code, language, style)
        :command_injection ->
          remediate_command_injection(vulnerability, code, language, style)
        :path_traversal ->
          remediate_path_traversal(vulnerability, code, language, style)
        :weak_crypto ->
          remediate_weak_crypto(vulnerability, code, language, style)
        :hardcoded_secrets ->
          remediate_hardcoded_secrets(vulnerability, code, language, style)
        _ ->
          generic_remediation(vulnerability, code, language, style)
      end
    end
    
    defp remediate_sql_injection(vuln, code, language, _style) do
      occurrence = hd(vuln.occurrences)
      vulnerable_line = occurrence.code_snippet
      
      fixed_code = case language do
        "javascript" ->
          if String.contains?(vulnerable_line, "query") do
            """
            // Use parameterized queries
            const query = 'SELECT * FROM users WHERE id = ?';
            db.query(query, [userId], (err, results) => {
              // Handle results
            });
            """
          else
            "// Use prepared statements or ORM with parameterized queries"
          end
        
        "python" ->
          """
          # Use parameterized queries
          cursor.execute(
              "SELECT * FROM users WHERE id = %s",
              (user_id,)
          )
          """
        
        "java" ->
          """
          // Use PreparedStatement
          String sql = "SELECT * FROM users WHERE id = ?";
          PreparedStatement pstmt = connection.prepareStatement(sql);
          pstmt.setInt(1, userId);
          ResultSet rs = pstmt.executeQuery();
          """
        
        _ ->
          "Use parameterized queries or prepared statements"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "SQL injection occurs when user input is directly concatenated into SQL queries. Use parameterized queries to separate SQL logic from data.",
        steps: [
          "Replace string concatenation with parameterized queries",
          "Use prepared statements for all database operations",
          "Validate and sanitize input as an additional layer",
          "Consider using an ORM for complex queries"
        ],
        security_notes: [
          "Never trust user input",
          "Whitelist allowed characters when possible",
          "Use least privilege database accounts",
          "Enable SQL query logging for security monitoring"
        ]
      }
    end
    
    defp remediate_xss(vuln, code, language, _style) do
      occurrence = hd(vuln.occurrences)
      vulnerable_line = occurrence.code_snippet
      
      fixed_code = case language do
        "javascript" ->
          if String.contains?(vulnerable_line, "innerHTML") do
            """
            // Use textContent for plain text
            element.textContent = userInput;
            
            // Or use a sanitization library for HTML
            import DOMPurify from 'dompurify';
            element.innerHTML = DOMPurify.sanitize(userInput);
            """
          else
            """
            // Escape output based on context
            function escapeHtml(unsafe) {
              return unsafe
                .replace(/&/g, "&amp;")
                .replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
                .replace(/"/g, "&quot;")
                .replace(/'/g, "&#039;");
            }
            """
          end
        
        "python" ->
          """
          # Use template engine's auto-escaping
          from flask import render_template_string
          from markupsafe import escape
          
          # Escape user input
          safe_input = escape(user_input)
          """
        
        _ ->
          "Use context-aware output encoding"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "XSS occurs when untrusted data is included in web pages without proper escaping. Always encode output based on the context (HTML, JavaScript, CSS, URL).",
        steps: [
          "Identify the output context (HTML, attribute, JavaScript, etc.)",
          "Apply appropriate encoding for the context",
          "Use template engines with auto-escaping enabled",
          "Implement Content Security Policy (CSP) headers"
        ],
        security_notes: [
          "Different contexts require different encoding",
          "Validate input on server-side",
          "Use CSP to mitigate XSS impact",
          "Avoid using dangerous JavaScript functions like eval()"
        ]
      }
    end
    
    defp remediate_command_injection(vuln, _code, language, _style) do
      fixed_code = case language do
        "python" ->
          """
          import subprocess
          import shlex
          
          # Safe command execution
          # Option 1: Use subprocess with list arguments
          result = subprocess.run(['ls', '-la', user_path], 
                                capture_output=True, 
                                text=True)
          
          # Option 2: If shell=True is necessary, use shlex.quote()
          safe_cmd = f"ls -la {shlex.quote(user_path)}"
          result = subprocess.run(safe_cmd, shell=True, 
                                capture_output=True, 
                                text=True)
          """
        
        "javascript" ->
          """
          const { spawn } = require('child_process');
          
          // Use spawn with array arguments
          const ls = spawn('ls', ['-la', userPath]);
          
          // Validate and whitelist input
          const allowedPaths = ['/safe/path1', '/safe/path2'];
          if (!allowedPaths.includes(userPath)) {
            throw new Error('Invalid path');
          }
          """
        
        _ ->
          "Use parameterized command execution APIs"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "Command injection allows attackers to execute arbitrary system commands. Use APIs that separate commands from arguments.",
        steps: [
          "Use parameterized APIs instead of shell execution",
          "Avoid shell interpreters when possible",
          "Validate and whitelist input values",
          "Run with least privileges"
        ],
        security_notes: [
          "Never pass user input directly to system commands",
          "Use allow-lists for command arguments",
          "Consider sandboxing for command execution",
          "Monitor and log command executions"
        ]
      }
    end
    
    defp remediate_path_traversal(vuln, _code, language, _style) do
      fixed_code = case language do
        "python" ->
          """
          import os
          from pathlib import Path
          
          # Secure file access
          BASE_DIR = '/var/www/files'
          
          def secure_file_access(user_path):
              # Resolve to absolute path
              base = Path(BASE_DIR).resolve()
              file_path = (base / user_path).resolve()
              
              # Ensure path is within base directory
              if not str(file_path).startswith(str(base)):
                  raise ValueError("Access denied")
              
              # Additional validation
              if file_path.exists() and file_path.is_file():
                  return file_path
              else:
                  raise FileNotFoundError("File not found")
          """
        
        "javascript" ->
          """
          const path = require('path');
          const fs = require('fs');
          
          const BASE_DIR = '/var/www/files';
          
          function secureFileAccess(userPath) {
            // Resolve paths
            const base = path.resolve(BASE_DIR);
            const filePath = path.resolve(base, userPath);
            
            // Ensure path is within base directory
            if (!filePath.startsWith(base)) {
              throw new Error('Access denied');
            }
            
            // Check file exists
            if (!fs.existsSync(filePath)) {
              throw new Error('File not found');
            }
            
            return filePath;
          }
          """
        
        _ ->
          "Validate and canonicalize file paths"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "Path traversal allows attackers to access files outside intended directories. Always validate and canonicalize paths.",
        steps: [
          "Define a base directory for file operations",
          "Resolve paths to absolute form",
          "Verify resolved path is within allowed directory",
          "Use whitelist for allowed file names/extensions"
        ],
        security_notes: [
          "Never trust user-supplied file paths",
          "Use platform's path resolution functions",
          "Implement access control checks",
          "Consider using file identifiers instead of paths"
        ]
      }
    end
    
    defp remediate_weak_crypto(vuln, _code, language, _style) do
      fixed_code = case language do
        "python" ->
          """
          import hashlib
          import secrets
          from cryptography.hazmat.primitives import hashes
          from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
          
          # For password hashing
          def hash_password(password: str) -> tuple[bytes, bytes]:
              salt = secrets.token_bytes(32)
              kdf = PBKDF2HMAC(
                  algorithm=hashes.SHA256(),
                  length=32,
                  salt=salt,
                  iterations=100000,
              )
              key = kdf.derive(password.encode())
              return salt, key
          
          # For general hashing
          def secure_hash(data: bytes) -> str:
              return hashlib.sha256(data).hexdigest()
          """
        
        "javascript" ->
          """
          const crypto = require('crypto');
          const bcrypt = require('bcrypt');
          
          // For password hashing
          async function hashPassword(password) {
            const saltRounds = 12;
            return await bcrypt.hash(password, saltRounds);
          }
          
          // For general hashing
          function secureHash(data) {
            return crypto.createHash('sha256').update(data).digest('hex');
          }
          
          // For HMAC
          function createHmac(data, secret) {
            return crypto.createHmac('sha256', secret).update(data).digest('hex');
          }
          """
        
        _ ->
          "Use strong cryptographic algorithms (SHA-256, bcrypt, etc.)"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "Weak cryptographic algorithms can be broken by attackers. Use industry-standard algorithms and libraries.",
        steps: [
          "Replace MD5/SHA1 with SHA-256 or SHA-3",
          "Use bcrypt/scrypt/argon2 for password hashing",
          "Use appropriate key derivation functions",
          "Keep cryptographic libraries updated"
        ],
        security_notes: [
          "Never implement custom cryptography",
          "Use sufficient iteration counts for KDFs",
          "Store salts separately from hashes",
          "Consider using hardware security modules for keys"
        ]
      }
    end
    
    defp remediate_hardcoded_secrets(vuln, _code, language, _style) do
      fixed_code = case language do
        "python" ->
          """
          import os
          from dotenv import load_dotenv
          
          # Load environment variables
          load_dotenv()
          
          # Access secrets from environment
          DATABASE_PASSWORD = os.environ.get('DATABASE_PASSWORD')
          API_KEY = os.environ.get('API_KEY')
          
          # Or use a secrets management service
          import boto3
          
          def get_secret(secret_name):
              client = boto3.client('secretsmanager')
              response = client.get_secret_value(SecretId=secret_name)
              return response['SecretString']
          """
        
        "javascript" ->
          """
          // Use environment variables
          require('dotenv').config();
          
          const DATABASE_PASSWORD = process.env.DATABASE_PASSWORD;
          const API_KEY = process.env.API_KEY;
          
          // Or use a secrets management service
          const AWS = require('aws-sdk');
          const client = new AWS.SecretsManager();
          
          async function getSecret(secretName) {
            const data = await client.getSecretValue({ SecretId: secretName }).promise();
            return data.SecretString;
          }
          """
        
        _ ->
          "Use environment variables or secrets management"
      end
      
      %{
        fixed_code: fixed_code,
        explanation: "Hardcoded secrets in source code can be exposed in version control. Use environment variables or dedicated secrets management.",
        steps: [
          "Remove all hardcoded secrets from code",
          "Set up environment variables",
          "Use .env files for local development (git-ignored)",
          "Consider secrets management services for production"
        ],
        security_notes: [
          "Never commit secrets to version control",
          "Rotate compromised credentials immediately",
          "Use different credentials for each environment",
          "Implement secret scanning in CI/CD"
        ]
      }
    end
    
    defp generic_remediation(vuln, _code, _language, _style) do
      %{
        fixed_code: "// Implement security best practices for #{vuln.type}",
        explanation: "Security vulnerability detected. Apply appropriate remediation based on the vulnerability type.",
        steps: [
          "Identify the specific vulnerability pattern",
          "Apply security best practices",
          "Test the remediation thoroughly",
          "Consider security code review"
        ],
        security_notes: [
          "Follow the principle of least privilege",
          "Implement defense in depth",
          "Keep dependencies updated",
          "Regular security assessments"
        ]
      }
    end
    
    defp generate_testing_guidance(vulnerability) do
      base_tests = [
        "Test with known attack payloads",
        "Verify the fix handles edge cases",
        "Ensure functionality is preserved",
        "Test with security scanning tools"
      ]
      
      specific_tests = case vulnerability.type do
        :sql_injection ->
          ["Test with SQL metacharacters", "Verify parameterized queries work correctly"]
        :xss ->
          ["Test with various XSS vectors", "Verify output encoding in all contexts"]
        :command_injection ->
          ["Test with shell metacharacters", "Verify command argument validation"]
        _ ->
          []
      end
      
      base_tests ++ specific_tests
    end
    
    defp generate_references(vulnerability) do
      base_refs = [
        %{
          title: "OWASP #{vulnerability.type |> to_string() |> String.replace("_", " ") |> String.capitalize()}",
          url: "https://owasp.org/"
        }
      ]
      
      if vulnerability[:cwe_id] do
        cwe_ref = %{
          title: vulnerability.cwe_id,
          url: "https://cwe.mitre.org/data/definitions/#{String.slice(vulnerability.cwe_id, 4..-1)}.html"
        }
        base_refs ++ [cwe_ref]
      else
        base_refs
      end
    end
  end
  
  defmodule PerformThreatModelingAction do
    @moduledoc """
    Performs threat modeling analysis on system architecture and code.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        system_description: [type: :string, required: true, doc: "System architecture description"],
        components: [type: {:list, :map}, doc: "System components and interactions"],
        data_flows: [type: {:list, :map}, doc: "Data flow descriptions"],
        threat_model: [type: :string, default: "STRIDE", doc: "Threat modeling framework"]
      }
    end
    
    @impl true
    def run(params, _context) do
      threats = identify_threats(
        params.system_description,
        params.components,
        params.data_flows,
        params.threat_model
      )
      
      risk_matrix = build_risk_matrix(threats)
      attack_vectors = identify_attack_vectors(threats, params.components)
      
      {:ok, %{
        identified_threats: threats,
        risk_matrix: risk_matrix,
        attack_vectors: attack_vectors,
        mitigation_strategies: generate_mitigation_strategies(threats),
        security_requirements: derive_security_requirements(threats, params.components),
        threat_summary: generate_threat_summary(threats, risk_matrix)
      }}
    end
    
    defp identify_threats(description, components, data_flows, model) do
      case model do
        "STRIDE" -> apply_stride_model(description, components, data_flows)
        "PASTA" -> apply_pasta_model(description, components, data_flows)
        _ -> apply_stride_model(description, components, data_flows)
      end
    end
    
    defp apply_stride_model(_description, components, data_flows) do
      threats = []
      
      # Spoofing threats
      spoofing_threats = components
        |> Enum.filter(&(!&1[:authentication] || &1.authentication == "basic"))
        |> Enum.map(fn comp ->
          %{
            type: :spoofing,
            component: comp.name,
            description: "#{comp.name} may be vulnerable to identity spoofing",
            severity: if(comp[:external_facing], do: :high, else: :medium),
            likelihood: :medium,
            impact: :high
          }
        end)
      
      threats = threats ++ spoofing_threats
      
      # Tampering threats
      tampering_threats = data_flows
        |> Enum.filter(&(!&1[:integrity_protection]))
        |> Enum.map(fn flow ->
          %{
            type: :tampering,
            component: "#{flow.source} -> #{flow.destination}",
            description: "Data flow from #{flow.source} to #{flow.destination} lacks integrity protection",
            severity: :high,
            likelihood: :medium,
            impact: :high
          }
        end)
      
      threats = threats ++ tampering_threats
      
      # Repudiation threats
      repudiation_threats = components
        |> Enum.filter(&(&1[:handles_transactions] && !&1[:audit_logging]))
        |> Enum.map(fn comp ->
          %{
            type: :repudiation,
            component: comp.name,
            description: "#{comp.name} lacks audit logging for transaction non-repudiation",
            severity: :medium,
            likelihood: :low,
            impact: :high
          }
        end)
      
      threats = threats ++ repudiation_threats
      
      # Information Disclosure threats
      disclosure_threats = data_flows
        |> Enum.filter(&(&1[:contains_sensitive_data] && !&1[:encrypted]))
        |> Enum.map(fn flow ->
          %{
            type: :information_disclosure,
            component: "#{flow.source} -> #{flow.destination}",
            description: "Sensitive data transmitted without encryption",
            severity: :critical,
            likelihood: :high,
            impact: :critical
          }
        end)
      
      threats = threats ++ disclosure_threats
      
      # Denial of Service threats
      dos_threats = components
        |> Enum.filter(&(&1[:external_facing] && !&1[:rate_limiting]))
        |> Enum.map(fn comp ->
          %{
            type: :denial_of_service,
            component: comp.name,
            description: "#{comp.name} lacks rate limiting and may be vulnerable to DoS",
            severity: :high,
            likelihood: :medium,
            impact: :high
          }
        end)
      
      threats = threats ++ dos_threats
      
      # Elevation of Privilege threats
      privilege_threats = components
        |> Enum.filter(&(&1[:has_admin_functions] && !&1[:rbac]))
        |> Enum.map(fn comp ->
          %{
            type: :elevation_of_privilege,
            component: comp.name,
            description: "#{comp.name} may allow unauthorized privilege escalation",
            severity: :critical,
            likelihood: :low,
            impact: :critical
          }
        end)
      
      threats ++ privilege_threats
    end
    
    defp apply_pasta_model(description, components, data_flows) do
      # Simplified PASTA implementation
      apply_stride_model(description, components, data_flows)
    end
    
    defp build_risk_matrix(threats) do
      matrix = %{
        critical: %{high: [], medium: [], low: []},
        high: %{high: [], medium: [], low: []},
        medium: %{high: [], medium: [], low: []},
        low: %{high: [], medium: [], low: []}
      }
      
      Enum.reduce(threats, matrix, fn threat, acc ->
        update_in(acc[threat.impact][threat.likelihood], &(&1 ++ [threat]))
      end)
    end
    
    defp identify_attack_vectors(threats, components) do
      threats
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {threat_type, type_threats} ->
        %{
          threat_type: threat_type,
          vectors: generate_attack_vectors(threat_type, type_threats, components),
          exploitability: assess_exploitability(threat_type, components)
        }
      end)
    end
    
    defp generate_attack_vectors(:spoofing, threats, _components) do
      [
        %{
          vector: "Credential theft",
          description: "Attacker obtains legitimate credentials through phishing or malware",
          prerequisites: ["Target user access", "Social engineering capability"]
        },
        %{
          vector: "Session hijacking", 
          description: "Attacker steals or predicts session tokens",
          prerequisites: ["Network access", "Token predictability"]
        }
      ]
    end
    
    defp generate_attack_vectors(:tampering, threats, _components) do
      [
        %{
          vector: "Man-in-the-middle",
          description: "Attacker intercepts and modifies data in transit",
          prerequisites: ["Network position", "Lack of encryption"]
        },
        %{
          vector: "Direct data manipulation",
          description: "Attacker directly modifies stored data",
          prerequisites: ["Storage access", "Lack of integrity checks"]
        }
      ]
    end
    
    defp generate_attack_vectors(_, _, _) do
      [
        %{
          vector: "Generic attack",
          description: "Various attack methods possible",
          prerequisites: ["System access"]
        }
      ]
    end
    
    defp assess_exploitability(threat_type, components) do
      external_components = Enum.filter(components, & &1[:external_facing])
      
      base_score = case threat_type do
        :spoofing -> 0.7
        :tampering -> 0.6
        :information_disclosure -> 0.8
        :denial_of_service -> 0.9
        _ -> 0.5
      end
      
      # Adjust based on external exposure
      if length(external_components) > 0 do
        min(1.0, base_score * 1.3)
      else
        base_score
      end
    end
    
    defp generate_mitigation_strategies(threats) do
      threats
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {threat_type, _} ->
        %{
          threat_type: threat_type,
          strategies: get_mitigation_strategies(threat_type),
          priority: get_mitigation_priority(threat_type, threats)
        }
      end)
      |> Enum.sort_by(& &1.priority)
    end
    
    defp get_mitigation_strategies(:spoofing) do
      [
        "Implement multi-factor authentication",
        "Use strong password policies",
        "Implement account lockout mechanisms",
        "Monitor for suspicious login attempts"
      ]
    end
    
    defp get_mitigation_strategies(:tampering) do
      [
        "Implement data integrity checks (HMAC, digital signatures)",
        "Use TLS for data in transit",
        "Implement input validation",
        "Use immutable audit logs"
      ]
    end
    
    defp get_mitigation_strategies(:repudiation) do
      [
        "Implement comprehensive audit logging",
        "Use digital signatures for critical actions",
        "Implement secure timestamp services",
        "Store logs in tamper-evident storage"
      ]
    end
    
    defp get_mitigation_strategies(:information_disclosure) do
      [
        "Encrypt sensitive data at rest and in transit",
        "Implement proper access controls",
        "Use data classification and handling policies",
        "Implement data loss prevention measures"
      ]
    end
    
    defp get_mitigation_strategies(:denial_of_service) do
      [
        "Implement rate limiting",
        "Use DDoS protection services",
        "Implement resource quotas",
        "Design for horizontal scalability"
      ]
    end
    
    defp get_mitigation_strategies(:elevation_of_privilege) do
      [
        "Implement role-based access control (RBAC)",
        "Follow principle of least privilege",
        "Regular privilege audits",
        "Implement privilege escalation monitoring"
      ]
    end
    
    defp get_mitigation_strategies(_) do
      ["Implement security best practices"]
    end
    
    defp get_mitigation_priority(threat_type, threats) do
      type_threats = Enum.filter(threats, &(&1.type == threat_type))
      
      critical_count = Enum.count(type_threats, &(&1.severity == :critical))
      high_count = Enum.count(type_threats, &(&1.severity == :high))
      
      cond do
        critical_count > 0 -> 1
        high_count > 1 -> 2
        high_count > 0 -> 3
        true -> 4
      end
    end
    
    defp derive_security_requirements(threats, components) do
      requirements = []
      
      # Authentication requirements
      if Enum.any?(threats, &(&1.type == :spoofing)) do
        auth_reqs = [
          %{
            category: "authentication",
            requirement: "Multi-factor authentication for sensitive operations",
            priority: :high
          },
          %{
            category: "authentication",
            requirement: "Secure session management with timeout",
            priority: :high
          }
        ]
        requirements = requirements ++ auth_reqs
      end
      
      # Encryption requirements
      if Enum.any?(threats, &(&1.type in [:information_disclosure, :tampering])) do
        crypto_reqs = [
          %{
            category: "cryptography",
            requirement: "TLS 1.3 for all external communications",
            priority: :critical
          },
          %{
            category: "cryptography",
            requirement: "Encryption at rest for sensitive data",
            priority: :high
          }
        ]
        requirements = requirements ++ crypto_reqs
      end
      
      # Access control requirements
      if Enum.any?(threats, &(&1.type == :elevation_of_privilege)) do
        access_reqs = [
          %{
            category: "access_control",
            requirement: "Role-based access control implementation",
            priority: :critical
          },
          %{
            category: "access_control",
            requirement: "Regular access reviews and recertification",
            priority: :medium
          }
        ]
        requirements = requirements ++ access_reqs
      end
      
      requirements
    end
    
    defp generate_threat_summary(threats, risk_matrix) do
      total_threats = length(threats)
      critical_threats = count_threats_by_severity(threats, :critical)
      high_threats = count_threats_by_severity(threats, :high)
      
      highest_risks = risk_matrix.critical.high ++ risk_matrix.critical.medium
      
      %{
        total_threats: total_threats,
        critical_threats: critical_threats,
        high_threats: high_threats,
        highest_risk_areas: Enum.map(highest_risks, & &1.component) |> Enum.uniq(),
        recommended_focus: determine_focus_areas(threats),
        overall_risk_level: calculate_overall_risk_level(threats)
      }
    end
    
    defp count_threats_by_severity(threats, severity) do
      Enum.count(threats, &(&1.severity == severity))
    end
    
    defp determine_focus_areas(threats) do
      threats
      |> Enum.filter(&(&1.severity in [:critical, :high]))
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, threats} -> {type, length(threats)} end)
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.take(3)
      |> Enum.map(fn {type, _} -> type end)
    end
    
    defp calculate_overall_risk_level(threats) do
      score = threats
        |> Enum.map(fn threat ->
          severity_score = case threat.severity do
            :critical -> 4
            :high -> 3
            :medium -> 2
            :low -> 1
          end
          
          likelihood_score = case threat.likelihood do
            :high -> 3
            :medium -> 2
            :low -> 1
          end
          
          severity_score * likelihood_score
        end)
        |> Enum.sum()
      
      avg_score = if length(threats) > 0, do: score / length(threats), else: 0
      
      cond do
        avg_score >= 9 -> :critical
        avg_score >= 6 -> :high
        avg_score >= 3 -> :medium
        true -> :low
      end
    end
  end
  
  defmodule GenerateSecurityReportAction do
    @moduledoc """
    Generates comprehensive security analysis reports.
    """
    use Jido.Action
    
    def parameter_schema do
      %{
        scan_results: [type: :map, required: true, doc: "Results from security scans"],
        report_format: [type: :string, default: "detailed", doc: "Format: summary, detailed, executive"],
        include_remediation: [type: :boolean, default: true, doc: "Include remediation guidance"],
        compliance_frameworks: [type: {:list, :string}, doc: "Compliance frameworks to map findings to"]
      }
    end
    
    @impl true
    def run(params, _context) do
      report = generate_report(
        params.scan_results,
        params.report_format,
        params.include_remediation,
        params.compliance_frameworks
      )
      
      {:ok, report}
    end
    
    defp generate_report(results, format, include_remediation, frameworks) do
      base_report = build_base_report(results)
      
      formatted_report = case format do
        "executive" -> format_executive_report(base_report)
        "summary" -> format_summary_report(base_report)
        _ -> format_detailed_report(base_report)
      end
      
      report = if include_remediation do
        add_remediation_section(formatted_report, results)
      else
        formatted_report
      end
      
      if frameworks && length(frameworks) > 0 do
        add_compliance_mapping(report, results, frameworks)
      else
        report
      end
    end
    
    defp build_base_report(results) do
      %{
        executive_summary: build_executive_summary(results),
        risk_overview: build_risk_overview(results),
        findings_summary: build_findings_summary(results),
        detailed_findings: build_detailed_findings(results),
        metrics: calculate_security_metrics(results),
        recommendations: build_recommendations(results)
      }
    end
    
    defp build_executive_summary(results) do
      total_issues = count_all_issues(results)
      critical_issues = count_critical_issues(results)
      
      %{
        title: "Security Assessment Executive Summary",
        date: DateTime.utc_now() |> DateTime.to_string(),
        overall_status: determine_overall_status(results),
        key_findings: [
          "Total security issues identified: #{total_issues}",
          "Critical severity issues: #{critical_issues}",
          "Overall security posture: #{assess_security_posture(results)}"
        ],
        immediate_actions: identify_immediate_actions(results)
      }
    end
    
    defp build_risk_overview(results) do
      %{
        risk_distribution: calculate_risk_distribution(results),
        risk_trends: identify_risk_trends(results),
        risk_hotspots: identify_risk_hotspots(results),
        risk_score: calculate_overall_risk_score(results)
      }
    end
    
    defp build_findings_summary(results) do
      findings = extract_all_findings(results)
      
      %{
        by_severity: group_findings_by_severity(findings),
        by_category: group_findings_by_category(findings),
        by_component: group_findings_by_component(findings),
        top_risks: identify_top_risks(findings, 5)
      }
    end
    
    defp build_detailed_findings(results) do
      extract_all_findings(results)
      |> Enum.map(fn finding ->
        %{
          id: generate_finding_id(finding),
          title: finding[:description] || finding[:message],
          severity: finding.severity,
          category: finding[:type] || finding[:category],
          component: finding[:component] || "Unknown",
          description: build_finding_description(finding),
          evidence: finding[:occurrences] || finding[:violations] || [],
          impact: finding[:impact] || assess_finding_impact(finding),
          likelihood: finding[:likelihood] || :medium,
          recommendations: finding[:recommendations] || []
        }
      end)
      |> Enum.sort_by(&severity_to_number(&1.severity))
    end
    
    defp calculate_security_metrics(results) do
      findings = extract_all_findings(results)
      
      %{
        total_findings: length(findings),
        severity_breakdown: %{
          critical: count_by_severity(findings, :critical),
          high: count_by_severity(findings, :high),
          medium: count_by_severity(findings, :medium),
          low: count_by_severity(findings, :low)
        },
        category_breakdown: calculate_category_breakdown(findings),
        security_score: calculate_security_score(findings),
        risk_metrics: %{
          average_severity: calculate_average_severity(findings),
          high_risk_percentage: calculate_high_risk_percentage(findings)
        }
      }
    end
    
    defp build_recommendations(results) do
      findings = extract_all_findings(results)
      
      %{
        immediate: generate_immediate_recommendations(findings),
        short_term: generate_short_term_recommendations(findings),
        long_term: generate_long_term_recommendations(findings),
        strategic: generate_strategic_recommendations(results)
      }
    end
    
    defp format_executive_report(base_report) do
      %{
        title: "Executive Security Report",
        generated_at: DateTime.utc_now(),
        executive_summary: base_report.executive_summary,
        risk_overview: %{
          overall_risk: base_report.risk_overview.risk_score,
          critical_findings: base_report.metrics.severity_breakdown.critical,
          immediate_actions_required: length(base_report.executive_summary.immediate_actions) > 0
        },
        key_metrics: %{
          total_issues: base_report.metrics.total_findings,
          security_score: base_report.metrics.security_score,
          high_risk_areas: length(base_report.risk_overview.risk_hotspots)
        },
        recommendations: base_report.recommendations.immediate
      }
    end
    
    defp format_summary_report(base_report) do
      %{
        title: "Security Assessment Summary",
        generated_at: DateTime.utc_now(),
        summary: base_report.executive_summary,
        findings_overview: base_report.findings_summary,
        metrics: base_report.metrics,
        top_recommendations: 
          base_report.recommendations.immediate ++ 
          Enum.take(base_report.recommendations.short_term, 3)
      }
    end
    
    defp format_detailed_report(base_report) do
      %{
        title: "Comprehensive Security Assessment Report",
        generated_at: DateTime.utc_now(),
        table_of_contents: [
          "Executive Summary",
          "Risk Overview", 
          "Detailed Findings",
          "Security Metrics",
          "Recommendations",
          "Appendices"
        ],
        executive_summary: base_report.executive_summary,
        risk_overview: base_report.risk_overview,
        findings: %{
          summary: base_report.findings_summary,
          detailed: base_report.detailed_findings
        },
        metrics: base_report.metrics,
        recommendations: base_report.recommendations,
        appendices: %{
          methodology: "Security assessment methodology details",
          glossary: build_security_glossary(),
          references: build_security_references()
        }
      }
    end
    
    defp add_remediation_section(report, results) do
      remediations = generate_remediation_guidance(results)
      
      Map.put(report, :remediation_guidance, %{
        priority_fixes: remediations.priority_fixes,
        fix_timelines: remediations.timelines,
        remediation_steps: remediations.detailed_steps,
        verification_procedures: remediations.verification
      })
    end
    
    defp add_compliance_mapping(report, results, frameworks) do
      mappings = frameworks
        |> Enum.map(fn framework ->
          {framework, map_findings_to_framework(results, framework)}
        end)
        |> Enum.into(%{})
      
      Map.put(report, :compliance_mapping, mappings)
    end
    
    defp generate_remediation_guidance(results) do
      findings = extract_all_findings(results)
      
      %{
        priority_fixes: identify_priority_fixes(findings),
        timelines: generate_fix_timelines(findings),
        detailed_steps: generate_detailed_remediation_steps(findings),
        verification: generate_verification_procedures(findings)
      }
    end
    
    defp identify_priority_fixes(findings) do
      findings
      |> Enum.filter(&(&1.severity in [:critical, :high]))
      |> Enum.take(10)
      |> Enum.map(fn finding ->
        %{
          finding_id: generate_finding_id(finding),
          severity: finding.severity,
          fix_priority: :immediate,
          estimated_effort: estimate_fix_effort(finding)
        }
      end)
    end
    
    defp generate_fix_timelines(findings) do
      grouped = Enum.group_by(findings, & &1.severity)
      
      %{
        immediate: length(grouped[:critical] || []),
        within_7_days: length(grouped[:high] || []),
        within_30_days: length(grouped[:medium] || []),
        within_90_days: length(grouped[:low] || [])
      }
    end
    
    defp generate_detailed_remediation_steps(findings) do
      findings
      |> Enum.take(20)  # Limit detailed steps
      |> Enum.map(fn finding ->
        %{
          finding_id: generate_finding_id(finding),
          steps: build_remediation_steps(finding),
          resources_required: estimate_resources(finding),
          dependencies: identify_dependencies(finding)
        }
      end)
    end
    
    defp generate_verification_procedures(findings) do
      findings
      |> Enum.map(& &1[:type] || &1[:category])
      |> Enum.uniq()
      |> Enum.map(fn type ->
        %{
          vulnerability_type: type,
          verification_steps: build_verification_steps(type),
          tools_recommended: recommend_verification_tools(type)
        }
      end)
    end
    
    defp map_findings_to_framework(results, "OWASP") do
      findings = extract_all_findings(results)
      
      owasp_mapping = %{
        "A01:2021" => ["injection", "sql_injection", "command_injection"],
        "A02:2021" => ["authentication", "spoofing", "weak_crypto"],
        "A03:2021" => ["xss", "injection"],
        "A04:2021" => ["xxe", "deserialization"],
        "A05:2021" => ["access_control", "elevation_of_privilege"],
        "A06:2021" => ["vulnerable_dependencies"],
        "A07:2021" => ["authentication", "identification"],
        "A08:2021" => ["integrity", "tampering"],
        "A09:2021" => ["logging", "monitoring"],
        "A10:2021" => ["ssrf"]
      }
      
      owasp_mapping
      |> Enum.map(fn {owasp_id, categories} ->
        matching_findings = findings
          |> Enum.filter(fn f ->
            finding_type = String.downcase(to_string(f[:type] || ""))
            Enum.any?(categories, &String.contains?(finding_type, &1))
          end)
        
        {owasp_id, %{
          findings_count: length(matching_findings),
          severity_breakdown: calculate_severity_breakdown(matching_findings),
          compliance_status: determine_compliance_status(matching_findings)
        }}
      end)
      |> Enum.into(%{})
    end
    
    defp map_findings_to_framework(results, framework) do
      %{
        framework: framework,
        status: "Framework mapping not implemented",
        findings_mapped: 0
      }
    end
    
    # Helper functions
    defp count_all_issues(results) do
      results
      |> Map.values()
      |> Enum.map(fn value ->
        case value do
          %{vulnerabilities: vulns} -> length(vulns)
          %{violations: violations} -> length(violations)
          list when is_list(list) -> length(list)
          _ -> 0
        end
      end)
      |> Enum.sum()
    end
    
    defp count_critical_issues(results) do
      extract_all_findings(results)
      |> Enum.count(&(&1[:severity] == :critical))
    end
    
    defp extract_all_findings(results) do
      findings = []
      
      findings = if results[:vulnerabilities] do
        findings ++ results.vulnerabilities
      else
        findings
      end
      
      findings = if results[:vulnerable_dependencies] do
        findings ++ results.vulnerable_dependencies
      else
        findings
      end
      
      findings = if results[:practice_violations] do
        findings ++ results.practice_violations
      else
        findings
      end
      
      findings = if results[:identified_threats] do
        findings ++ results.identified_threats
      else
        findings
      end
      
      findings
    end
    
    defp determine_overall_status(results) do
      critical_count = count_critical_issues(results)
      
      cond do
        critical_count > 0 -> :critical
        count_all_issues(results) > 20 -> :needs_attention
        count_all_issues(results) > 10 -> :fair
        count_all_issues(results) > 0 -> :good
        true -> :excellent
      end
    end
    
    defp assess_security_posture(results) do
      status = determine_overall_status(results)
      
      case status do
        :critical -> "Critical - Immediate action required"
        :needs_attention -> "Poor - Significant improvements needed"
        :fair -> "Fair - Some improvements recommended"
        :good -> "Good - Minor issues present"
        :excellent -> "Excellent - No significant issues"
      end
    end
    
    defp identify_immediate_actions(results) do
      findings = extract_all_findings(results)
      
      findings
      |> Enum.filter(&(&1[:severity] == :critical))
      |> Enum.take(5)
      |> Enum.map(fn finding ->
        "Fix #{finding[:type] || finding[:category]} vulnerability in #{finding[:component] || "system"}"
      end)
    end
    
    defp calculate_risk_distribution(results) do
      findings = extract_all_findings(results)
      total = length(findings)
      
      if total == 0 do
        %{critical: 0, high: 0, medium: 0, low: 0}
      else
        %{
          critical: count_by_severity(findings, :critical) / total * 100,
          high: count_by_severity(findings, :high) / total * 100,
          medium: count_by_severity(findings, :medium) / total * 100,
          low: count_by_severity(findings, :low) / total * 100
        }
      end
    end
    
    defp identify_risk_trends(_results) do
      # In a real implementation, would compare with historical data
      %{
        trend: :increasing,
        change_percentage: 15,
        new_risk_areas: ["API Security", "Supply Chain"],
        improved_areas: ["Authentication"]
      }
    end
    
    defp identify_risk_hotspots(results) do
      findings = extract_all_findings(results)
      
      findings
      |> Enum.group_by(&(&1[:component] || "Unknown"))
      |> Enum.map(fn {component, component_findings} ->
        risk_score = component_findings
          |> Enum.map(&severity_to_number(&1.severity))
          |> Enum.sum()
        
        {component, risk_score}
      end)
      |> Enum.sort_by(fn {_, score} -> -score end)
      |> Enum.take(5)
      |> Enum.map(fn {component, _} -> component end)
    end
    
    defp calculate_overall_risk_score(results) do
      findings = extract_all_findings(results)
      
      if length(findings) == 0 do
        0.0
      else
        total_score = findings
          |> Enum.map(&(severity_to_number(&1.severity) * 2.5))
          |> Enum.sum()
        
        max_possible = length(findings) * 10.0
        Float.round(total_score / max_possible, 2)
      end
    end
    
    defp group_findings_by_severity(findings) do
      Enum.group_by(findings, & &1.severity)
    end
    
    defp group_findings_by_category(findings) do
      Enum.group_by(findings, &(&1[:type] || &1[:category] || :other))
    end
    
    defp group_findings_by_component(findings) do
      Enum.group_by(findings, &(&1[:component] || "Unknown"))
    end
    
    defp identify_top_risks(findings, count) do
      findings
      |> Enum.sort_by(&severity_to_number(&1.severity))
      |> Enum.take(count)
    end
    
    defp generate_finding_id(finding) do
      type = finding[:type] || finding[:category] || "unknown"
      severity = finding.severity
      hash = :crypto.hash(:md5, inspect(finding)) |> Base.encode16() |> String.slice(0..7)
      
      "#{severity}-#{type}-#{hash}"
    end
    
    defp build_finding_description(finding) do
      base = finding[:description] || finding[:message] || "Security issue detected"
      
      if finding[:occurrences] do
        count = length(finding.occurrences)
        base <> " (#{count} occurrences found)"
      else
        base
      end
    end
    
    defp assess_finding_impact(finding) do
      case finding[:type] do
        :sql_injection -> "Database compromise, data breach"
        :xss -> "User session hijacking, data theft"
        :command_injection -> "System compromise, unauthorized access"
        _ -> "Security impact varies based on context"
      end
    end
    
    defp severity_to_number(:critical), do: 4
    defp severity_to_number(:high), do: 3
    defp severity_to_number(:medium), do: 2
    defp severity_to_number(:low), do: 1
    defp severity_to_number(_), do: 0
    
    defp count_by_severity(findings, severity) do
      Enum.count(findings, &(&1.severity == severity))
    end
    
    defp calculate_category_breakdown(findings) do
      findings
      |> Enum.group_by(&(&1[:type] || &1[:category] || :other))
      |> Enum.map(fn {category, items} -> {category, length(items)} end)
      |> Enum.into(%{})
    end
    
    defp calculate_security_score(findings) do
      if length(findings) == 0 do
        100.0
      else
        penalty = findings
          |> Enum.map(&(severity_to_number(&1.severity) * 5))
          |> Enum.sum()
        
        Float.round(max(0, 100 - penalty), 1)
      end
    end
    
    defp calculate_average_severity(findings) do
      if length(findings) == 0 do
        0.0
      else
        total = findings
          |> Enum.map(&severity_to_number(&1.severity))
          |> Enum.sum()
        
        Float.round(total / length(findings), 2)
      end
    end
    
    defp calculate_high_risk_percentage(findings) do
      if length(findings) == 0 do
        0.0
      else
        high_risk = Enum.count(findings, &(&1.severity in [:critical, :high]))
        Float.round(high_risk / length(findings) * 100, 1)
      end
    end
    
    defp generate_immediate_recommendations(findings) do
      findings
      |> Enum.filter(&(&1.severity == :critical))
      |> Enum.take(5)
      |> Enum.map(fn finding ->
        "Immediately address #{finding[:type]} in #{finding[:component] || "system"}"
      end)
    end
    
    defp generate_short_term_recommendations(findings) do
      findings
      |> Enum.filter(&(&1.severity == :high))
      |> Enum.take(5)
      |> Enum.map(fn finding ->
        "Plan remediation for #{finding[:type]} vulnerabilities"
      end)
    end
    
    defp generate_long_term_recommendations(_findings) do
      [
        "Implement continuous security monitoring",
        "Establish secure development lifecycle",
        "Regular security training for development team",
        "Periodic third-party security assessments"
      ]
    end
    
    defp generate_strategic_recommendations(results) do
      posture = assess_security_posture(results)
      
      base_recommendations = [
        "Develop comprehensive security policy",
        "Implement security metrics and KPIs",
        "Build security culture across organization"
      ]
      
      if String.contains?(posture, "Critical") || String.contains?(posture, "Poor") do
        ["Establish dedicated security team" | base_recommendations]
      else
        base_recommendations
      end
    end
    
    defp build_security_glossary do
      %{
        "CVE" => "Common Vulnerabilities and Exposures",
        "OWASP" => "Open Web Application Security Project",
        "XSS" => "Cross-Site Scripting",
        "SQL Injection" => "Code injection technique targeting databases",
        "STRIDE" => "Threat modeling framework (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege)"
      }
    end
    
    defp build_security_references do
      [
        %{
          title: "OWASP Top 10",
          url: "https://owasp.org/www-project-top-ten/"
        },
        %{
          title: "CWE Database",
          url: "https://cwe.mitre.org/"
        },
        %{
          title: "NIST Cybersecurity Framework",
          url: "https://www.nist.gov/cyberframework"
        }
      ]
    end
    
    defp estimate_fix_effort(finding) do
      case finding.severity do
        :critical -> "4-8 hours"
        :high -> "2-4 hours"
        :medium -> "1-2 hours"
        :low -> "30-60 minutes"
      end
    end
    
    defp build_remediation_steps(finding) do
      case finding[:type] do
        :sql_injection -> [
          "Identify all database queries using user input",
          "Replace with parameterized queries",
          "Test thoroughly with SQL injection payloads",
          "Deploy and monitor for anomalies"
        ]
        _ -> ["Analyze vulnerability", "Implement fix", "Test remediation", "Deploy"]
      end
    end
    
    defp estimate_resources(finding) do
      %{
        developers: 1,
        security_review: true,
        testing_required: true,
        deployment_window: "maintenance"
      }
    end
    
    defp identify_dependencies(_finding) do
      ["Code review", "Security testing", "Deployment approval"]
    end
    
    defp build_verification_steps(type) do
      case type do
        :sql_injection -> [
          "Run SQLMap against fixed endpoints",
          "Perform manual testing with payloads",
          "Review database query logs"
        ]
        _ -> ["Run security scanner", "Manual verification", "Monitor for issues"]
      end
    end
    
    defp recommend_verification_tools(type) do
      case type do
        :sql_injection -> ["SQLMap", "Burp Suite", "OWASP ZAP"]
        :xss -> ["XSStrike", "Burp Suite", "Browser DevTools"]
        _ -> ["OWASP ZAP", "Nessus", "Qualys"]
      end
    end
    
    defp calculate_severity_breakdown(findings) do
      %{
        critical: count_by_severity(findings, :critical),
        high: count_by_severity(findings, :high),
        medium: count_by_severity(findings, :medium),
        low: count_by_severity(findings, :low)
      }
    end
    
    defp determine_compliance_status(findings) do
      critical_count = count_by_severity(findings, :critical)
      high_count = count_by_severity(findings, :high)
      
      cond do
        critical_count > 0 -> :non_compliant
        high_count > 2 -> :partial_compliant
        true -> :compliant
      end
    end
  end
  
  @impl BaseToolAgent
  def initial_state do
    %{
      scan_history: [],
      vulnerability_cache: %{},
      security_policies: default_security_policies(),
      threat_intelligence: %{},
      remediation_templates: load_remediation_templates(),
      compliance_mappings: load_compliance_mappings(),
      risk_thresholds: default_risk_thresholds(),
      max_history: 100
    }
  end
  
  @impl BaseToolAgent
  def handle_tool_signal(%State{} = state, signal) do
    signal_type = signal["type"]
    data = signal["data"] || %{}
    
    case signal_type do
      "scan_vulnerabilities" ->
        cmd_async(state, ScanVulnerabilitiesAction, data)
        
      "analyze_dependencies" ->
        cmd_async(state, AnalyzeDependenciesAction, data)
        
      "validate_security_practices" ->
        cmd_async(state, ValidateSecurityPracticesAction, data)
        
      "generate_remediation" ->
        cmd_async(state, GenerateRemediationAction, data)
        
      "perform_threat_modeling" ->
        cmd_async(state, PerformThreatModelingAction, data)
        
      "generate_security_report" ->
        cmd_async(state, GenerateSecurityReportAction, data)
        
      _ ->
        super(state, signal)
    end
  end
  
  @impl BaseToolAgent
  def handle_action_result(state, action, result, metadata) do
    case action do
      ScanVulnerabilitiesAction ->
        handle_scan_result(state, result, metadata)
        
      AnalyzeDependenciesAction ->
        handle_dependency_analysis_result(state, result, metadata)
        
      ValidateSecurityPracticesAction ->
        handle_practice_validation_result(state, result, metadata)
        
      PerformThreatModelingAction ->
        handle_threat_modeling_result(state, result, metadata)
        
      _ ->
        super(state, action, result, metadata)
    end
  end
  
  defp handle_scan_result(state, {:ok, result}, metadata) do
    # Update vulnerability cache
    cache_key = generate_cache_key(metadata)
    updated_cache = Map.put(state.state.vulnerability_cache, cache_key, %{
      result: result,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    })
    
    # Add to scan history
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :vulnerability_scan,
      severity_summary: result.scan_metadata,
      risk_score: result.risk_score,
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.scan_history]
      |> Enum.take(state.state.max_history)
    
    # Update threat intelligence if critical vulnerabilities found
    updated_threat_intel = if result.scan_metadata.critical_count > 0 do
      update_threat_intelligence(state.state.threat_intelligence, result.vulnerabilities)
    else
      state.state.threat_intelligence
    end
    
    updated_state = %{state.state |
      vulnerability_cache: updated_cache,
      scan_history: updated_history,
      threat_intelligence: updated_threat_intel
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_scan_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_dependency_analysis_result(state, {:ok, result}, metadata) do
    # Track vulnerable dependencies
    if length(result.vulnerable_dependencies) > 0 do
      history_entry = %{
        timestamp: DateTime.utc_now(),
        type: :dependency_analysis,
        vulnerable_count: length(result.vulnerable_dependencies),
        risk_assessment: result.risk_assessment,
        metadata: metadata
      }
      
      updated_history = [history_entry | state.state.scan_history]
        |> Enum.take(state.state.max_history)
      
      {:ok, put_in(state.state.scan_history, updated_history)}
    else
      {:ok, state}
    end
  end
  
  defp handle_dependency_analysis_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_practice_validation_result(state, {:ok, result}, metadata) do
    # Update security policies based on violations
    if length(result.practice_violations) > 0 do
      updated_policies = update_security_policies(
        state.state.security_policies,
        result.practice_violations
      )
      
      {:ok, put_in(state.state.security_policies, updated_policies)}
    else
      {:ok, state}
    end
  end
  
  defp handle_practice_validation_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  defp handle_threat_modeling_result(state, {:ok, result}, metadata) do
    # Update threat intelligence with new threats
    updated_threat_intel = merge_threat_intelligence(
      state.state.threat_intelligence,
      result.identified_threats
    )
    
    history_entry = %{
      timestamp: DateTime.utc_now(),
      type: :threat_modeling,
      threats_identified: length(result.identified_threats),
      risk_level: result.threat_summary.overall_risk_level,
      metadata: metadata
    }
    
    updated_history = [history_entry | state.state.scan_history]
      |> Enum.take(state.state.max_history)
    
    updated_state = %{state.state |
      threat_intelligence: updated_threat_intel,
      scan_history: updated_history
    }
    
    {:ok, %{state | state: updated_state}}
  end
  
  defp handle_threat_modeling_result(state, {:error, _error}, _metadata) do
    {:ok, state}
  end
  
  @impl BaseToolAgent
  def process_result(result, _metadata) do
    Map.put(result, :analyzed_at, DateTime.utc_now())
  end
  
  @impl BaseToolAgent
  def additional_actions do
    [
      ScanVulnerabilitiesAction,
      AnalyzeDependenciesAction,
      ValidateSecurityPracticesAction,
      GenerateRemediationAction,
      PerformThreatModelingAction,
      GenerateSecurityReportAction
    ]
  end
  
  # Helper functions
  defp generate_cache_key(metadata) do
    content = metadata[:source_code] || metadata["dependencies"] || ""
    :crypto.hash(:md5, content) |> Base.encode16()
  end
  
  defp update_threat_intelligence(threat_intel, vulnerabilities) do
    new_threats = vulnerabilities
      |> Enum.filter(&(&1.severity in [:critical, :high]))
      |> Enum.map(fn vuln ->
        %{
          type: vuln.type,
          severity: vuln.severity,
          first_seen: DateTime.utc_now(),
          occurrences: 1
        }
      end)
    
    Enum.reduce(new_threats, threat_intel, fn threat, acc ->
      key = threat.type
      
      if Map.has_key?(acc, key) do
        update_in(acc[key].occurrences, &(&1 + 1))
      else
        Map.put(acc, key, threat)
      end
    end)
  end
  
  defp update_security_policies(policies, violations) do
    violation_categories = violations
      |> Enum.map(& &1.category)
      |> Enum.uniq()
    
    Enum.reduce(violation_categories, policies, fn category, acc ->
      if Map.has_key?(acc, category) do
        update_in(acc[category].violations_found, &(&1 + 1))
      else
        acc
      end
    end)
  end
  
  defp merge_threat_intelligence(existing, new_threats) do
    Enum.reduce(new_threats, existing, fn threat, acc ->
      key = {threat.type, threat.component}
      
      if Map.has_key?(acc, key) do
        acc
      else
        Map.put(acc, key, %{
          threat: threat,
          added_at: DateTime.utc_now()
        })
      end
    end)
  end
  
  defp default_security_policies do
    %{
      authentication: %{
        enabled: true,
        requirements: ["MFA", "strong_passwords", "session_timeout"],
        violations_found: 0
      },
      encryption: %{
        enabled: true,
        requirements: ["tls_1_3", "aes_256", "secure_random"],
        violations_found: 0
      },
      access_control: %{
        enabled: true,
        requirements: ["rbac", "least_privilege", "audit_logging"],
        violations_found: 0
      }
    }
  end
  
  defp load_remediation_templates do
    %{
      sql_injection: %{
        template: "Use parameterized queries",
        references: ["OWASP SQL Injection Prevention"]
      },
      xss: %{
        template: "Encode output based on context", 
        references: ["OWASP XSS Prevention"]
      }
    }
  end
  
  defp load_compliance_mappings do
    %{
      "OWASP" => %{
        categories: ["A01", "A02", "A03", "A04", "A05", "A06", "A07", "A08", "A09", "A10"],
        version: "2021"
      },
      "CWE" => %{
        categories: ["CWE-89", "CWE-79", "CWE-78", "CWE-22", "CWE-327", "CWE-798"],
        version: "4.9"
      }
    }
  end
  
  defp default_risk_thresholds do
    %{
      critical: 0.9,
      high: 0.7,
      medium: 0.5,
      low: 0.3
    }
  end
end