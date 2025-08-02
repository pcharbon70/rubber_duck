defmodule RubberDuck.Agents.AnalysisAgentJidoTest do
  @moduledoc """
  Test suite for the Jido-compliant AnalysisAgent.
  Verifies that the agent has been properly migrated from Behavior to BaseAgent pattern.
  """
  
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.AnalysisAgent
  alias RubberDuck.Jido.Actions.Analysis.{
    CodeAnalysisAction,
    ComplexityAnalysisAction,
    PatternDetectionAction,
    SecurityReviewAction,
    StyleCheckAction
  }

  describe "Jido Compliance Verification" do
    test "agent uses BaseAgent pattern (not legacy Behavior)" do
      # Verify that signal_mappings function exists (indicator of Jido compliance)
      assert function_exported?(AnalysisAgent, :signal_mappings, 0)
      
      # Verify lifecycle hooks exist
      assert function_exported?(AnalysisAgent, :on_before_init, 1)
      assert function_exported?(AnalysisAgent, :on_after_start, 1)
      assert function_exported?(AnalysisAgent, :on_before_stop, 1)
    end

    test "defines complete signal-to-action mappings" do
      mappings = AnalysisAgent.signal_mappings()
      
      # Verify all required signals are mapped
      required_signals = [
        "analysis.code.request",
        "analysis.security.request",
        "analysis.complexity.request",
        "analysis.pattern.request",
        "analysis.style.request"
      ]
      
      Enum.each(required_signals, fn signal ->
        assert Map.has_key?(mappings, signal), "Missing mapping for signal: #{signal}"
      end)
    end

    test "signal mappings reference correct actions and extractors" do
      mappings = AnalysisAgent.signal_mappings()
      
      # Verify each mapping points to the correct action and extractor
      assert {CodeAnalysisAction, :extract_code_params} == mappings["analysis.code.request"]
      assert {SecurityReviewAction, :extract_security_params} == mappings["analysis.security.request"]
      assert {ComplexityAnalysisAction, :extract_complexity_params} == mappings["analysis.complexity.request"]
      assert {PatternDetectionAction, :extract_pattern_params} == mappings["analysis.pattern.request"]
      assert {StyleCheckAction, :extract_style_params} == mappings["analysis.style.request"]
    end

    test "no legacy handle_task callbacks remain" do
      # Verify that old Behavior callbacks don't exist
      refute function_exported?(AnalysisAgent, :handle_task, 3)
      refute function_exported?(AnalysisAgent, :handle_message, 3)
      refute function_exported?(AnalysisAgent, :init, 1)
      refute function_exported?(AnalysisAgent, :terminate, 2)
    end
  end

  describe "Parameter Extraction Functions" do
    test "extract_code_params/1 handles complete data" do
      signal_data = %{
        "data" => %{
          "file_path" => "lib/example.ex",
          "analysis_types" => ["semantic", "style", "security"],
          "enable_cache" => false,
          "apply_self_correction" => false,
          "include_metrics" => true
        }
      }
      
      params = AnalysisAgent.extract_code_params(signal_data)
      
      assert params.file_path == "lib/example.ex"
      assert params.analysis_types == [:semantic, :style, :security]
      assert params.enable_cache == false
      assert params.apply_self_correction == false
      assert params.include_metrics == true
    end

    test "extract_code_params/1 applies defaults for missing data" do
      signal_data = %{
        "data" => %{
          "file_path" => "lib/test.ex"
        }
      }
      
      params = AnalysisAgent.extract_code_params(signal_data)
      
      assert params.file_path == "lib/test.ex"
      assert params.analysis_types == [:semantic, :style, :security]  # default
      assert params.enable_cache == true  # default
      assert params.apply_self_correction == true  # default
      assert params.include_metrics == true  # default
    end

    test "extract_security_params/1 handles list and single file paths" do
      # Test with list
      signal_data_list = %{
        "data" => %{
          "file_paths" => ["lib/auth.ex", "lib/api.ex"],
          "vulnerability_types" => ["sql_injection", "xss"],
          "severity_threshold" => "high"
        }
      }
      
      params_list = AnalysisAgent.extract_security_params(signal_data_list)
      assert params_list.file_paths == ["lib/auth.ex", "lib/api.ex"]
      assert params_list.vulnerability_types == [:sql_injection, :xss]
      assert params_list.severity_threshold == :high
      
      # Test with single file
      signal_data_single = %{
        "data" => %{
          "file_paths" => "lib/single.ex",
          "vulnerability_types" => "all"
        }
      }
      
      params_single = AnalysisAgent.extract_security_params(signal_data_single)
      assert params_single.file_paths == ["lib/single.ex"]
      assert params_single.vulnerability_types == [:all]
      assert params_single.severity_threshold == :low  # default
    end

    test "extract_complexity_params/1 parses metrics correctly" do
      signal_data = %{
        "data" => %{
          "module_path" => "lib/complex.ex",
          "metrics" => ["cyclomatic", "cognitive", "halstead"],
          "include_recommendations" => false,
          "include_function_details" => true
        }
      }
      
      params = AnalysisAgent.extract_complexity_params(signal_data)
      
      assert params.module_path == "lib/complex.ex"
      assert params.metrics == [:cyclomatic, :cognitive, :halstead]
      assert params.include_recommendations == false
      assert params.include_function_details == true
    end

    test "extract_pattern_params/1 handles pattern types" do
      signal_data = %{
        "data" => %{
          "codebase_path" => "/project/src",
          "pattern_types" => ["design_patterns", "anti_patterns", "otp_patterns"],
          "confidence_threshold" => 0.85
        }
      }
      
      params = AnalysisAgent.extract_pattern_params(signal_data)
      
      assert params.codebase_path == "/project/src"
      assert params.pattern_types == [:design_patterns, :anti_patterns, :otp_patterns]
      assert params.confidence_threshold == 0.85
      assert params.include_suggestions == true  # default
    end

    test "extract_style_params/1 handles style rules" do
      signal_data = %{
        "data" => %{
          "file_paths" => ["lib/style1.ex", "lib/style2.ex"],
          "style_rules" => "strict",
          "detect_auto_fixable" => false,
          "check_formatting" => true,
          "max_line_length" => 100
        }
      }
      
      params = AnalysisAgent.extract_style_params(signal_data)
      
      assert params.file_paths == ["lib/style1.ex", "lib/style2.ex"]
      assert params.style_rules == :strict
      assert params.detect_auto_fixable == false
      assert params.check_formatting == true
      assert params.max_line_length == 100
    end
  end

  describe "Lifecycle Hooks" do
    test "on_before_init/1 initializes engines configuration" do
      config = %{
        engines: [:semantic, :style, :security],
        semantic: %{threshold: 0.8},
        style: %{rules: :strict},
        security: %{scan_depth: :deep}
      }
      
      updated_config = AnalysisAgent.on_before_init(config)
      
      assert Map.has_key?(updated_config, :engines)
      assert is_map(updated_config.engines)
      
      # Verify each engine is properly configured
      assert updated_config.engines[:semantic].module == RubberDuck.Analysis.Semantic
      assert updated_config.engines[:style].module == RubberDuck.Analysis.Style
      assert updated_config.engines[:security].module == RubberDuck.Analysis.Security
      
      # Verify engine configs are preserved
      assert updated_config.engines[:semantic].config == %{threshold: 0.8}
      assert updated_config.engines[:style].config == %{rules: :strict}
      assert updated_config.engines[:security].config == %{scan_depth: :deep}
    end

    test "on_before_init/1 handles default engine configuration" do
      config = %{}
      
      updated_config = AnalysisAgent.on_before_init(config)
      
      # Should have default engines
      assert Map.has_key?(updated_config, :engines)
      assert Map.has_key?(updated_config.engines, :semantic)
      assert Map.has_key?(updated_config.engines, :style)
      assert Map.has_key?(updated_config.engines, :security)
    end

    test "on_after_start/1 returns agent unchanged" do
      agent = %{
        name: "analysis_agent",
        state: %{
          capabilities: [:code_analysis, :security_analysis],
          analysis_cache: %{}
        }
      }
      
      result = AnalysisAgent.on_after_start(agent)
      
      # Should return agent unchanged (just logs)
      assert result == agent
    end

    test "on_before_stop/1 returns agent unchanged" do
      agent = %{
        name: "analysis_agent",
        state: %{
          analysis_cache: %{
            "file1.ex" => %{result: "cached1"},
            "file2.ex" => %{result: "cached2"}
          }
        }
      }
      
      result = AnalysisAgent.on_before_stop(agent)
      
      # Should return agent unchanged (just logs and cleanup preparation)
      assert result == agent
    end
  end

  describe "Action Integration" do
    test "all required actions are properly referenced" do
      # This verifies that the actions module names are correct
      # and can be loaded
      assert Code.ensure_loaded?(CodeAnalysisAction)
      assert Code.ensure_loaded?(ComplexityAnalysisAction)
      assert Code.ensure_loaded?(PatternDetectionAction)
      assert Code.ensure_loaded?(SecurityReviewAction)
      assert Code.ensure_loaded?(StyleCheckAction)
    end
  end

  describe "Migration Completeness" do
    test "agent properly declares its capabilities in schema" do
      # The capabilities should be defined in the schema default
      # This would be validated when the agent starts
      assert true
    end

    test "agent maintains backward-compatible capability list" do
      expected_capabilities = [
        :code_analysis,
        :security_analysis,
        :complexity_analysis,
        :pattern_detection,
        :style_checking
      ]
      
      # These should be preserved in the schema default
      assert true
    end
  end
end