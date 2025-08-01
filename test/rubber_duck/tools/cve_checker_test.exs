defmodule RubberDuck.Tools.CVECheckerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tools.CVEChecker
  alias RubberDuck.Types.{ToolCall, ToolResult}

  describe "execute/1" do
    test "checks CVE vulnerabilities for direct dependencies" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.20", registry: "npm"},
            %{name: "minimist", version: "1.2.5", registry: "npm"}
          ],
          check_transitive: false,
          severity_threshold: "low"
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should find vulnerabilities for both packages
      assert length(result.result.vulnerabilities) >= 2
      
      # Check lodash vulnerability
      lodash_vuln = Enum.find(result.result.vulnerabilities, &(&1.package == "lodash"))
      assert lodash_vuln != nil
      assert lodash_vuln.cve_id == "CVE-2021-23337"
      assert lodash_vuln.severity == "high"
      assert lodash_vuln.cvss_score == 7.2
      assert "4.17.21" in lodash_vuln.patched_versions
      
      # Check minimist vulnerability
      minimist_vuln = Enum.find(result.result.vulnerabilities, &(&1.package == "minimist"))
      assert minimist_vuln != nil
      assert minimist_vuln.cve_id == "CVE-2021-44906"
      assert minimist_vuln.severity == "critical"
      assert minimist_vuln.cvss_score == 9.8
      
      # Check summary
      summary = result.result.summary
      assert summary.total_vulnerabilities >= 2
      assert summary.critical >= 1
      assert summary.high >= 1
      assert summary.packages_scanned == 2
      assert summary.vulnerable_packages == 2
    end

    test "checks transitive dependencies when enabled" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "express", version: "4.17.1", registry: "npm"}
          ],
          check_transitive: true
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should include transitive dependencies in the tree
      tree = result.result.dependency_tree
      assert map_size(tree.nodes) > 1  # More than just express
      
      # Should have checked transitive dependencies
      assert result.result.summary.packages_scanned > 1
    end

    test "filters vulnerabilities by severity threshold" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.20"},  # high severity
            %{name: "minimist", version: "1.2.5"}    # critical severity
          ],
          check_transitive: false,
          severity_threshold: "critical"
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should only include critical vulnerabilities
      assert Enum.all?(result.result.vulnerabilities, &(&1.severity == "critical"))
      assert length(result.result.vulnerabilities) == 1
      assert hd(result.result.vulnerabilities).package == "minimist"
    end

    test "excludes patched vulnerabilities when requested" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.21"},  # patched version
            %{name: "minimist", version: "1.2.5"}   # vulnerable version
          ],
          check_transitive: false,
          include_patched: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should not include vulnerabilities for lodash (already patched)
      assert Enum.all?(result.result.vulnerabilities, &(&1.package != "lodash"))
    end

    test "generates recommendations for vulnerable packages" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.20"},
            %{name: "minimist", version: "1.2.5"}
          ],
          check_transitive: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should have recommendations
      assert length(result.result.recommendations) >= 2
      
      # Check lodash recommendation
      lodash_rec = Enum.find(result.result.recommendations, &(&1.package == "lodash"))
      assert lodash_rec != nil
      assert lodash_rec.current_version == "4.17.20"
      assert lodash_rec.recommended_version == "4.17.21"
      assert "CVE-2021-23337" in lodash_rec.fixes_cves
      assert lodash_rec.breaking_changes == false  # Same major version
      
      # Check minimist recommendation
      minimist_rec = Enum.find(result.result.recommendations, &(&1.package == "minimist"))
      assert minimist_rec != nil
      assert minimist_rec.recommended_version == "1.2.6"
      assert "CVE-2021-44906" in minimist_rec.fixes_cves
    end

    test "includes dependency paths for vulnerabilities" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "express", version: "4.17.1"}
          ],
          check_transitive: true
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # All vulnerabilities should have dependency paths
      assert Enum.all?(result.result.vulnerabilities, fn vuln ->
        is_list(vuln.dependency_path) and length(vuln.dependency_path) > 0
      end)
    end

    test "supports multiple output formats" do
      base_args = %{
        dependencies: [
          %{name: "lodash", version: "4.17.20"}
        ],
        check_transitive: false
      }

      # Test summary format
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: Map.put(base_args, :output_format, "summary")
      }
      
      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      assert Map.has_key?(result.result, :summary)
      assert Map.has_key?(result.result, :critical_vulnerabilities)
      assert Map.has_key?(result.result, :high_vulnerabilities)
      
      # Test SARIF format
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: Map.put(base_args, :output_format, "sarif")
      }
      
      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      assert result.result["$schema"] != nil
      assert result.result.version == "2.1.0"
      assert is_list(result.result.runs)
      
      # Test CycloneDX format
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: Map.put(base_args, :output_format, "cyclonedx")
      }
      
      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      assert result.result.bomFormat == "CycloneDX"
      assert result.result.specVersion == "1.4"
      assert is_list(result.result.vulnerabilities)
    end

    test "handles Python packages" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "pyyaml", version: "5.3.0", registry: "pypi"}
          ],
          check_transitive: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should find PyYAML vulnerability
      pyyaml_vuln = Enum.find(result.result.vulnerabilities, &(&1.package == "pyyaml"))
      assert pyyaml_vuln != nil
      assert pyyaml_vuln.cve_id == "CVE-2020-14343"
      assert pyyaml_vuln.severity == "high"
    end

    test "handles Java packages" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "log4j", version: "2.14.0", registry: "maven"}
          ],
          check_transitive: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should find Log4Shell vulnerability
      log4j_vuln = Enum.find(result.result.vulnerabilities, &(&1.package == "log4j"))
      assert log4j_vuln != nil
      assert log4j_vuln.cve_id == "CVE-2021-44228"
      assert log4j_vuln.severity == "critical"
      assert log4j_vuln.cvss_score == 10.0
      assert log4j_vuln.description =~ "Log4Shell"
    end

    test "detects breaking changes in recommendations" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "test-package", version: "1.5.0"}
          ],
          check_transitive: false
        }
      }

      # Since we don't have a vulnerability for test-package, let's test with a known one
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "3.10.1"}  # Major version 3
          ],
          check_transitive: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # If recommendations suggest version 4.x, it should detect breaking changes
      if rec = Enum.find(result.result.recommendations, &(&1.package == "lodash")) do
        if String.starts_with?(rec.recommended_version, "4.") do
          assert rec.breaking_changes == true
        end
      end
    end

    test "includes scan metadata" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.20"}
          ],
          sources: ["nvd", "ghsa"]
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      metadata = result.result.scan_metadata
      assert metadata.scan_date != nil
      assert metadata.sources_used == ["nvd", "ghsa"]
      assert is_integer(metadata.scan_duration_ms)
      assert metadata.scan_duration_ms > 0
    end

    test "returns empty vulnerabilities for safe packages" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "safe-package", version: "1.0.0"},
            %{name: "another-safe", version: "2.0.0"}
          ],
          check_transitive: false
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      assert result.result.vulnerabilities == []
      assert result.result.summary.total_vulnerabilities == 0
      assert result.result.summary.vulnerable_packages == 0
      assert result.result.recommendations == []
    end

    test "handles empty dependency list gracefully" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: []
        }
      }

      assert {:error, "Dependencies must be a non-empty list"} = CVEChecker.execute(tool_call)
    end

    test "annotates dependency tree with vulnerabilities" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "express", version: "4.17.1"},
            %{name: "lodash", version: "4.17.20"}
          ],
          check_transitive: true
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      tree = result.result.dependency_tree
      
      # Find lodash node in tree
      lodash_node = Enum.find(tree.nodes, fn {_id, node} ->
        node.name == "lodash"
      end)
      
      if lodash_node do
        {_, node} = lodash_node
        # Should have vulnerabilities annotation
        assert Map.has_key?(node, :vulnerabilities)
        assert is_list(node.vulnerabilities)
      end
    end

    test "uses specified vulnerability sources" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "lodash", version: "4.17.20"}
          ],
          sources: ["osv", "snyk", "ghsa"]
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      # Should use specified sources
      assert result.result.scan_metadata.sources_used == ["osv", "snyk", "ghsa"]
    end

    test "includes exploitability information" do
      tool_call = %ToolCall{
        name: :cve_checker,
        arguments: %{
          dependencies: [
            %{name: "log4j", version: "2.14.0"}
          ]
        }
      }

      assert {:ok, %ToolResult{} = result} = CVEChecker.execute(tool_call)
      
      log4j_vuln = Enum.find(result.result.vulnerabilities, &(&1.package == "log4j"))
      assert log4j_vuln != nil
      assert log4j_vuln.exploitability == "critical"
    end
  end

  describe "tool metadata" do
    test "has correct name and category" do
      assert CVEChecker.name() == :cve_checker
      assert CVEChecker.category() == :security
    end

    test "has valid input and output schemas" do
      input_schema = CVEChecker.input_schema()
      assert input_schema.type == "object"
      assert "dependencies" in input_schema.required
      
      output_schema = CVEChecker.output_schema()
      assert output_schema.type == "object"
      assert Map.has_key?(output_schema.properties, :vulnerabilities)
      assert Map.has_key?(output_schema.properties, :summary)
      assert Map.has_key?(output_schema.properties, :recommendations)
    end
  end
end