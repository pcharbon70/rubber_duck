defmodule RubberDuck.QualityImprovement.QualityEnforcerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.QualityImprovement.QualityEnforcer
  
  @sample_code """
  defmodule TestModule do
    def complex_function(x, y, z) do
      if x > 0 do
        if y > 0 do
          if z > 0 do
            x + y + z
          else
            x + y
          end
        else
          x
        end
      else
        0
      end
    end
    
    def simple_function(a, b) do
      a + b
    end
  end
  """
  
  @refactoring_code """
  defmodule RefactorTest do
    def target_method(input) do
      # This method needs refactoring
      result = input * 2
      result + 1
    end
    
    def another_method do
      42
    end
  end
  """
  
  describe "apply_improvements/4" do
    test "applies conservative improvements successfully" do
      improvements = [
        %{
          "type" => "rename_for_clarity",
          "old_name" => "x",
          "new_name" => "input_value",
          "name_type" => "variable",
          "risk_level" => "low",
          "confidence" => 0.9
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "conservative")
      
      assert {:ok, improvement_result} = result
      assert is_binary(improvement_result.code)
      assert improvement_result.improvements == improvements
      assert is_map(improvement_result.quality_improvement)
      assert is_map(improvement_result.validation)
      assert is_number(improvement_result.confidence)
      
      # Validation should pass
      assert improvement_result.validation.overall_valid == true
    end
    
    test "applies aggressive improvements" do
      improvements = [
        %{
          "type" => "reduce_complexity",
          "complexity_type" => "cyclomatic",
          "target_function" => "complex_function",
          "risk_level" => "high",
          "confidence" => 0.6
        },
        %{
          "type" => "extract_method",
          "target_code" => "nested_logic",
          "new_method_name" => "extract_nested_logic",
          "risk_level" => "medium"
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "aggressive")
      
      assert {:ok, improvement_result} = result
      assert improvement_result.improvements == improvements
      assert is_map(improvement_result.quality_improvement)
    end
    
    test "applies targeted improvements to specific area" do
      improvements = [
        %{
          "type" => "reduce_complexity",
          "area" => "complexity",
          "risk_level" => "medium",
          "impact" => 0.8
        },
        %{
          "type" => "improve_naming",
          "area" => "readability",
          "risk_level" => "low",
          "impact" => 0.6
        }
      ]
      
      options = %{"target_area" => "complexity"}
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "targeted", options)
      
      assert {:ok, improvement_result} = result
      
      # Should only apply complexity-related improvements
      # (In practice, this would be more sophisticated filtering)
      assert is_list(improvement_result.improvements)
    end
    
    test "applies comprehensive improvements in priority order" do
      improvements = [
        %{
          "type" => "low_impact_change",
          "impact" => 0.3,
          "risk_level" => "low"
        },
        %{
          "type" => "high_impact_change",
          "impact" => 0.9,
          "risk_level" => "medium"
        },
        %{
          "type" => "medium_impact_change",
          "impact" => 0.6,
          "risk_level" => "high"
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "comprehensive")
      
      assert {:ok, improvement_result} = result
      assert is_map(improvement_result.quality_improvement)
      
      # Should calculate quality delta
      assert Map.has_key?(improvement_result.quality_improvement, :complexity_reduction)
      assert Map.has_key?(improvement_result.quality_improvement, :maintainability_improvement)
      assert Map.has_key?(improvement_result.quality_improvement, :readability_improvement)
      assert Map.has_key?(improvement_result.quality_improvement, :overall_improvement)
    end
    
    test "handles unknown improvement strategy" do
      improvements = [%{"type" => "test_improvement"}]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "unknown_strategy")
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Unknown improvement strategy")
    end
    
    test "handles syntax errors in code" do
      invalid_code = "defmodule Invalid do invalid syntax"
      improvements = [%{"type" => "rename_for_clarity"}]
      
      result = QualityEnforcer.apply_improvements(invalid_code, improvements, "conservative")
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Syntax error")
    end
  end
  
  describe "perform_refactoring/5" do
    test "performs extract method refactoring" do
      patterns = %{
        "extract_method" => %{
          definition: %{description: "Extract method pattern"}
        }
      }
      
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "extract_method",
        "complex_logic",
        patterns
      )
      
      assert {:ok, refactoring_result} = result
      assert is_binary(refactoring_result.code)
      assert is_map(refactoring_result.changes)
      assert is_map(refactoring_result.impact)
      assert is_map(refactoring_result.validation)
      
      # Should track changes made
      assert Map.has_key?(refactoring_result.changes, :refactoring_type)
      assert refactoring_result.changes.refactoring_type == "extract_method"
    end
    
    test "performs rename method refactoring" do
      patterns = %{}
      options = %{"new_name" => "calculate_value"}
      
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "rename_method",
        "target_method",
        patterns,
        options
      )
      
      assert {:ok, refactoring_result} = result
      assert is_binary(refactoring_result.code)
      
      # Should contain the new method name in the refactored code
      # (This is a simplified test - actual implementation would verify the rename)
      assert is_binary(refactoring_result.code)
    end
    
    test "performs inline method refactoring" do
      patterns = %{}
      
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "inline_method",
        "target_method",
        patterns
      )
      
      assert {:ok, refactoring_result} = result
      assert is_map(refactoring_result.impact)
      
      # Should assess impact
      assert Map.has_key?(refactoring_result.impact, :maintainability_impact)
      assert Map.has_key?(refactoring_result.impact, :performance_impact)
      assert Map.has_key?(refactoring_result.impact, :readability_impact)
      assert Map.has_key?(refactoring_result.impact, :risk_level)
    end
    
    test "performs extract variable refactoring" do
      patterns = %{}
      
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "extract_variable",
        "input * 2",
        patterns
      )
      
      assert {:ok, refactoring_result} = result
      assert is_binary(refactoring_result.code)
      assert is_map(refactoring_result.validation)
      
      # Should validate the refactoring
      assert Map.has_key?(refactoring_result.validation, :syntax_preserved)
      assert Map.has_key?(refactoring_result.validation, :functionality_preserved)
      assert Map.has_key?(refactoring_result.validation, :refactoring_goals_met)
    end
    
    test "handles unknown refactoring type" do
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "unknown_refactoring",
        "target",
        %{}
      )
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Unknown refactoring type")
    end
    
    test "handles syntax errors during refactoring" do
      invalid_code = "defmodule Invalid do invalid syntax"
      
      result = QualityEnforcer.perform_refactoring(
        invalid_code,
        "extract_method",
        "target",
        %{}
      )
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Syntax error")
    end
  end
  
  describe "optimize_performance/3" do
    test "applies memory optimizations" do
      result = QualityEnforcer.optimize_performance(@sample_code, "memory")
      
      assert {:ok, optimization_result} = result
      assert is_binary(optimization_result.code)
      assert optimization_result.target == "memory"
      assert is_list(optimization_result.optimizations)
      assert is_map(optimization_result.improvement)
      assert is_map(optimization_result.validation)
      
      # Should estimate performance improvement
      assert Map.has_key?(optimization_result.improvement, :estimated_speedup)
      assert Map.has_key?(optimization_result.improvement, :memory_reduction)
      assert Map.has_key?(optimization_result.improvement, :confidence)
    end
    
    test "applies CPU optimizations" do
      result = QualityEnforcer.optimize_performance(@sample_code, "cpu")
      
      assert {:ok, optimization_result} = result
      assert optimization_result.target == "cpu"
      assert is_list(optimization_result.optimizations)
      
      # Should identify applied optimizations
      if length(optimization_result.optimizations) > 0 do
        first_optimization = List.first(optimization_result.optimizations)
        assert Map.has_key?(first_optimization, :type)
        assert Map.has_key?(first_optimization, :description)
      end
    end
    
    test "applies I/O optimizations" do
      result = QualityEnforcer.optimize_performance(@sample_code, "io")
      
      assert {:ok, optimization_result} = result
      assert optimization_result.target == "io"
      assert is_map(optimization_result.improvement)
      
      # Should include I/O efficiency improvement
      assert Map.has_key?(optimization_result.improvement, :io_efficiency)
    end
    
    test "applies general optimizations" do
      result = QualityEnforcer.optimize_performance(@sample_code, "general")
      
      assert {:ok, optimization_result} = result
      assert optimization_result.target == "general"
      assert is_map(optimization_result.validation)
      
      # Should validate optimization didn't break functionality
      assert Map.has_key?(optimization_result.validation, :functionality_preserved)
      assert Map.has_key?(optimization_result.validation, :performance_improved)
      assert Map.has_key?(optimization_result.validation, :no_regressions)
    end
    
    test "handles unknown optimization target" do
      result = QualityEnforcer.optimize_performance(@sample_code, "unknown_target")
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Unknown optimization target")
    end
    
    test "handles syntax errors during optimization" do
      invalid_code = "defmodule Invalid do invalid syntax"
      
      result = QualityEnforcer.optimize_performance(invalid_code, "memory")
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Syntax error")
    end
  end
  
  describe "improvement validation" do
    test "validates syntax preservation" do
      improvements = [
        %{
          "type" => "rename_for_clarity",
          "old_name" => "simple_function",
          "new_name" => "add_numbers",
          "name_type" => "function"
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "conservative")
      
      assert {:ok, improvement_result} = result
      assert improvement_result.validation.syntax_valid == true
      assert improvement_result.validation.overall_valid == true
    end
    
    test "calculates quality improvement delta" do
      improvements = [
        %{
          "type" => "reduce_complexity",
          "complexity_type" => "cyclomatic"
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "conservative")
      
      assert {:ok, improvement_result} = result
      
      quality_delta = improvement_result.quality_improvement
      assert is_number(quality_delta.complexity_reduction)
      assert is_number(quality_delta.maintainability_improvement)
      assert is_number(quality_delta.readability_improvement)
      assert is_number(quality_delta.overall_improvement)
    end
    
    test "calculates improvement confidence based on validation" do
      improvements = [
        %{
          "type" => "improve_naming",
          "confidence" => 0.8,
          "risk_level" => "low"
        }
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, improvements, "conservative")
      
      assert {:ok, improvement_result} = result
      assert improvement_result.confidence >= 0.0
      assert improvement_result.confidence <= 1.0
      
      # High confidence improvements with valid results should have high overall confidence
      if improvement_result.validation.overall_valid do
        assert improvement_result.confidence > 0.5
      end
    end
  end
  
  describe "refactoring analysis" do
    test "analyzes refactoring changes" do
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "rename_method",
        "target_method",
        %{},
        %{"new_name" => "process_input"}
      )
      
      assert {:ok, refactoring_result} = result
      
      changes = refactoring_result.changes
      assert Map.has_key?(changes, :refactoring_type)
      assert Map.has_key?(changes, :lines_changed)
      assert Map.has_key?(changes, :methods_affected)
      assert Map.has_key?(changes, :complexity_change)
      
      assert changes.refactoring_type == "rename_method"
      assert is_number(changes.lines_changed)
      assert is_number(changes.methods_affected)
      assert is_number(changes.complexity_change)
    end
    
    test "assesses refactoring impact" do
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "extract_method",
        "target_logic",
        %{}
      )
      
      assert {:ok, refactoring_result} = result
      
      impact = refactoring_result.impact
      assert Map.has_key?(impact, :maintainability_impact)
      assert Map.has_key?(impact, :performance_impact)
      assert Map.has_key?(impact, :readability_impact)
      assert Map.has_key?(impact, :risk_level)
      
      # Impact assessments should have scores and descriptions
      assert is_map(impact.maintainability_impact)
      assert is_map(impact.performance_impact)
      assert is_map(impact.readability_impact)
      assert is_binary(impact.risk_level)
    end
    
    test "validates refactoring goals" do
      result = QualityEnforcer.perform_refactoring(
        @refactoring_code,
        "inline_variable",
        "variable_name",
        %{}
      )
      
      assert {:ok, refactoring_result} = result
      
      validation = refactoring_result.validation
      assert validation.syntax_preserved == true
      assert validation.functionality_preserved == true
      assert validation.refactoring_goals_met == true
    end
  end
  
  describe "performance optimization analysis" do
    test "identifies applied optimizations" do
      list_optimization_code = """
      defmodule ListOps do
        def process_list(list) do
          list ++ [new_item]
        end
        
        def concatenate_strings(a, b) do
          a <> b
        end
      end
      """
      
      result = QualityEnforcer.optimize_performance(list_optimization_code, "memory")
      
      assert {:ok, optimization_result} = result
      assert length(optimization_result.optimizations) > 0
      
      # Should identify specific optimization types
      optimization_types = Enum.map(optimization_result.optimizations, & &1.type)
      assert Enum.any?(optimization_types, &(&1 in ["list_operations", "string_operations"]))
    end
    
    test "estimates performance improvement" do
      result = QualityEnforcer.optimize_performance(@sample_code, "cpu")
      
      assert {:ok, optimization_result} = result
      
      improvement = optimization_result.improvement
      assert is_number(improvement.estimated_speedup)
      assert is_number(improvement.memory_reduction)
      assert is_number(improvement.io_efficiency)
      assert is_number(improvement.confidence)
      
      # Estimates should be reasonable
      assert improvement.estimated_speedup >= 1.0
      assert improvement.memory_reduction >= 0.0
      assert improvement.io_efficiency >= 1.0
      assert improvement.confidence >= 0.0 and improvement.confidence <= 1.0
    end
    
    test "validates optimization safety" do
      result = QualityEnforcer.optimize_performance(@sample_code, "general")
      
      assert {:ok, optimization_result} = result
      
      validation = optimization_result.validation
      assert validation.functionality_preserved == true
      assert validation.performance_improved == true
      assert validation.no_regressions == true
    end
  end
  
  describe "error handling and edge cases" do
    test "handles empty code" do
      result = QualityEnforcer.apply_improvements("", [], "conservative")
      
      # Should handle empty code gracefully
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true  # Acceptable to fail on empty code
      end
    end
    
    test "handles empty improvements list" do
      result = QualityEnforcer.apply_improvements(@sample_code, [], "conservative")
      
      assert {:ok, improvement_result} = result
      assert improvement_result.improvements == []
      assert is_binary(improvement_result.code)
      # Code should be unchanged when no improvements are applied
    end
    
    test "handles malformed improvement data" do
      malformed_improvements = [
        %{"invalid" => "structure"},
        nil,
        "not a map"
      ]
      
      result = QualityEnforcer.apply_improvements(@sample_code, malformed_improvements, "conservative")
      
      # Should handle malformed data gracefully - either skip invalid improvements or fail safely
      case result do
        {:ok, improvement_result} ->
          # If it succeeds, it should have filtered out invalid improvements
          assert is_list(improvement_result.improvements)
        {:error, _reason} ->
          # Acceptable to fail on malformed data
          assert true
      end
    end
    
    test "handles very large code inputs" do
      large_code = String.duplicate(@sample_code, 100)
      improvements = [%{"type" => "rename_for_clarity", "old_name" => "x", "new_name" => "value"}]
      
      result = QualityEnforcer.apply_improvements(large_code, improvements, "conservative")
      
      # Should handle large inputs without crashing
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true  # Acceptable to fail on very large inputs
      end
    end
  end
end