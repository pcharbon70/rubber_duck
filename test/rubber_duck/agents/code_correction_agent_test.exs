defmodule RubberDuck.Agents.CodeCorrectionAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.CodeCorrectionAgent

  setup do
    {:ok, _agent} = CodeCorrectionAgent.start_link([])
    
    # Initialize the agent
    agent = %{
      id: "test_correction_agent",
      state: %{
        correction_status: :idle,
        active_corrections: %{},
        fix_history: [],
        syntax_patterns: %{
          "missing_comma" => %{
            pattern: ~r/\[\s*(\w+)\s+(\w+)\s*\]/,
            fix_template: "[$1, $2]",
            usage_count: 0,
            success_rate: 1.0
          }
        },
        semantic_rules: %{
          "undefined_variable" => %{
            condition: %{error_type: "undefined_variable"},
            action: %{type: "define_variable", scope: "local"},
            priority: 1,
            usage_count: 0
          }
        },
        test_integration: %{
          enabled: true,
          test_generator: nil,
          validation_config: %{}
        },
        metrics: %{
          total_fixes: 0,
          successful_fixes: 0,
          failed_fixes: 0,
          syntax_fixes: 0,
          semantic_fixes: 0,
          refactoring_fixes: 0,
          combined_fixes: 0,
          avg_fix_time: 0.0,
          avg_confidence: 0.0,
          rollback_count: 0,
          test_generation_count: 0,
          success_rate: 0.0,
          quality_improvements: %{
            total_improvements: 0,
            avg_improvement_score: 0.0
          }
        }
      }
    }
    
    {:ok, agent: agent}
  end

  describe "apply_correction signal" do
    test "successfully applies syntax correction", %{agent: agent} do
      error_data = %{
        "code" => "def test do\n  [a b]\nend",
        "error_type" => "syntax_error",
        "error_message" => "syntax error before: b"
      }
      
      strategy = %{
        "name" => "syntax_fix",
        "type" => "syntax"
      }
      
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "corr_123",
        "error_data" => error_data,
        "strategy" => strategy,
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, result, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.success == true
      assert result.correction_id == "corr_123"
      assert result.result.type == :syntax
      assert result.result.fixed_code =~ "[a, b]"
      assert map_size(updated_agent.state.active_corrections) == 0
      assert length(updated_agent.state.fix_history) == 1
    end

    test "successfully applies semantic correction", %{agent: agent} do
      error_data = %{
        "code" => "def test do\n  IO.puts(x)\nend",
        "error_type" => "undefined_variable",
        "variable_name" => "x",
        "error_message" => "undefined variable x"
      }
      
      strategy = %{
        "name" => "semantic_fix",
        "type" => "semantic"
      }
      
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "corr_456",
        "error_data" => error_data,
        "strategy" => strategy,
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, result, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.success == true
      assert result.result.type == :semantic
      assert result.result.fixed_code =~ "x = nil"
      assert length(result.result.semantic_changes) > 0
    end

    test "handles correction failure gracefully", %{agent: agent} do
      error_data = %{
        "code" => "invalid",
        "error_type" => "unknown_error"
      }
      
      strategy = %{
        "name" => "unknown_strategy",
        "type" => "unknown"
      }
      
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "corr_789",
        "error_data" => error_data,
        "strategy" => strategy,
        "options" => %{}
      }
      
      {:error, reason, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert is_binary(reason)
      assert map_size(updated_agent.state.active_corrections) == 0
      assert updated_agent.state.metrics.failed_fixes == 1
    end
  end

  describe "validate_fix signal" do
    test "validates fix successfully", %{agent: agent} do
      fix_data = %{
        "fixed_code" => "def test do\n  x = 1\n  IO.puts(x)\nend",
        "original_code" => "def test do\n  IO.puts(x)\nend"
      }
      
      signal = %{
        "type" => "validate_fix",
        "fix_data" => fix_data,
        "error_context" => %{"error_type" => "undefined_variable"},
        "validation_level" => "basic"
      }
      
      {:ok, result, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.overall_valid == true
      assert result.level == "basic"
      assert is_map(result.checks)
      assert result.confidence > 0
    end
  end

  describe "generate_tests signal" do
    test "generates tests when enabled", %{agent: agent} do
      fix_data = %{
        "id" => "fix_123",
        "type" => :syntax,
        "original_code" => "[a b]",
        "fixed_code" => "[a, b]"
      }
      
      signal = %{
        "type" => "generate_tests",
        "fix_data" => fix_data,
        "test_config" => %{"framework" => "exunit"}
      }
      
      {:ok, result, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.generated == true
      assert is_list(result.tests)
      assert length(result.tests) > 0
    end

    test "skips test generation when disabled", %{agent: agent} do
      agent = put_in(agent.state.test_integration.enabled, false)
      
      signal = %{
        "type" => "generate_tests",
        "fix_data" => %{},
        "test_config" => %{}
      }
      
      {:ok, result, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.generated == false
      assert result.reason =~ "disabled"
    end
  end

  describe "rollback_fix signal" do
    test "rolls back a completed fix", %{agent: agent} do
      # Add a fix to history
      completed_fix = %{
        correction_id: "corr_001",
        status: :completed,
        error_data: %{"code" => "original code"},
        fix_result: %{
          type: :syntax,
          original_code: "original code",
          fixed_code: "fixed code"
        }
      }
      
      agent = update_in(agent.state.fix_history, &[completed_fix | &1])
      
      signal = %{
        "type" => "rollback_fix",
        "correction_id" => "corr_001",
        "reason" => "Test failed"
      }
      
      {:ok, result, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.restored_code == "original code"
      assert length(updated_agent.state.fix_history) == 2  # Original + rollback
    end

    test "handles rollback of non-existent fix", %{agent: agent} do
      signal = %{
        "type" => "rollback_fix",
        "correction_id" => "non_existent",
        "reason" => "Test"
      }
      
      {:error, reason, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert reason =~ "not found"
    end
  end

  describe "analyze_impact signal" do
    test "analyzes fix impact", %{agent: agent} do
      fix_data = %{
        "type" => :refactoring,
        "original_code" => "def test, do: 1 + 1",
        "fixed_code" => "def test do\n  1 + 1\nend"
      }
      
      signal = %{
        "type" => "analyze_impact",
        "fix_data" => fix_data,
        "analysis_scope" => "local"
      }
      
      {:ok, result, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert is_map(result.code_quality)
      assert is_map(result.performance)
      assert is_map(result.maintainability)
      assert is_map(result.test_coverage)
    end
  end

  describe "get_fix_metrics signal" do
    test "returns metrics for all time", %{agent: agent} do
      # Add some metrics
      agent = agent
      |> put_in([:state, :metrics, :total_fixes], 10)
      |> put_in([:state, :metrics, :successful_fixes], 8)
      |> put_in([:state, :metrics, :success_rate], 0.8)
      
      signal = %{
        "type" => "get_fix_metrics",
        "time_range" => "all"
      }
      
      {:ok, metrics, _updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert metrics.total_fixes == 10
      assert metrics.successful_fixes == 8
      assert metrics.success_rate == 0.8
    end
  end

  describe "pattern management" do
    test "adds syntax pattern", %{agent: agent} do
      signal = %{
        "type" => "add_syntax_pattern",
        "pattern_id" => "missing_do",
        "pattern" => ~r/def\s+(\w+)\(([^)]*)\)\s*\n/,
        "fix_template" => "def $1($2) do\n"
      }
      
      {:ok, result, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.added == true
      assert Map.has_key?(updated_agent.state.syntax_patterns, "missing_do")
    end

    test "adds semantic rule", %{agent: agent} do
      signal = %{
        "type" => "add_semantic_rule",
        "rule_id" => "type_mismatch",
        "rule" => %{
          "condition" => %{error_type: "type_error"},
          "action" => %{type: "convert_type"},
          "priority" => 2
        }
      }
      
      {:ok, result, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert result.added == true
      assert Map.has_key?(updated_agent.state.semantic_rules, "type_mismatch")
    end
  end

  describe "correction execution" do
    test "determines correction type correctly", %{agent: agent} do
      # Test syntax error type
      syntax_error = %{
        "code" => "[a b]",
        "error_type" => "syntax_error"
      }
      
      syntax_strategy = %{"type" => "syntax"}
      
      syntax_signal = %{
        "type" => "apply_correction",
        "correction_id" => "syntax_test",
        "error_data" => syntax_error,
        "strategy" => syntax_strategy,
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, result, _} = CodeCorrectionAgent.handle_signal(agent, syntax_signal)
      assert result.result.type == :syntax
      
      # Test semantic error type
      semantic_error = %{
        "code" => "x + 1",
        "error_type" => "undefined_variable",
        "variable_name" => "x"
      }
      
      semantic_strategy = %{"type" => "semantic"}
      
      semantic_signal = %{
        "type" => "apply_correction",
        "correction_id" => "semantic_test",
        "error_data" => semantic_error,
        "strategy" => semantic_strategy,
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, result, _} = CodeCorrectionAgent.handle_signal(agent, semantic_signal)
      assert result.result.type == :semantic
    end
  end

  describe "metrics tracking" do
    test "updates metrics after successful correction", %{agent: agent} do
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "metrics_test",
        "error_data" => %{
          "code" => "[a b]",
          "error_type" => "syntax_error"
        },
        "strategy" => %{"name" => "test", "type" => "syntax"},
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, _, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert updated_agent.state.metrics.total_fixes == 1
      assert updated_agent.state.metrics.successful_fixes == 1
      assert updated_agent.state.metrics.syntax_fixes == 1
    end

    test "tracks failed corrections", %{agent: agent} do
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "fail_test",
        "error_data" => %{
          "code" => "invalid",
          "error_type" => "unknown"
        },
        "strategy" => %{"type" => "unknown"},
        "options" => %{}
      }
      
      {:error, _, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      assert updated_agent.state.metrics.total_fixes == 1
      assert updated_agent.state.metrics.failed_fixes == 1
    end
  end

  describe "state management" do
    test "maintains correction history limit", %{agent: agent} do
      # Add many fixes to history
      large_history = Enum.map(1..1500, fn i ->
        %{
          correction_id: "fix_#{i}",
          status: :completed,
          completed_at: DateTime.utc_now()
        }
      end)
      
      agent = put_in(agent.state.fix_history, large_history)
      
      # Apply another correction
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "new_fix",
        "error_data" => %{"code" => "[a b]", "error_type" => "syntax_error"},
        "strategy" => %{"type" => "syntax"},
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, _, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      # History should be limited to max size (1000)
      assert length(updated_agent.state.fix_history) <= 1000
    end

    test "updates correction status correctly", %{agent: agent} do
      assert agent.state.correction_status == :idle
      
      # Start a correction
      signal = %{
        "type" => "apply_correction",
        "correction_id" => "status_test",
        "error_data" => %{"code" => "[a b]", "error_type" => "syntax_error"},
        "strategy" => %{"type" => "syntax"},
        "options" => %{"skip_validation" => true}
      }
      
      {:ok, _, updated_agent} = CodeCorrectionAgent.handle_signal(agent, signal)
      
      # Should return to idle after completion
      assert updated_agent.state.correction_status == :idle
    end
  end
end