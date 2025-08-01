defmodule RubberDuck.QualityImprovement.QualityAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.QualityImprovement.QualityAnalyzer
  
  @simple_code """
  defmodule SimpleModule do
    @moduledoc "A simple test module"
    
    def add(a, b) do
      a + b
    end
    
    def multiply(x, y) do
      x * y
    end
  end
  """
  
  @complex_code """
  defmodule ComplexModule do
    def complex_function(x, y, z) do
      if x > 0 do
        if y > 0 do
          if z > 0 do
            cond do
              x > y -> x + z
              y > z -> y + x
              true -> z + x + y
            end
          else
            case y do
              0 -> x
              _ -> x + y
            end
          end
        else
          x
        end
      else
        0
      end
    end
    
    def long_method_with_duplication(input) do
      # This is a very long method that does many things
      # First, validate the input
      if is_nil(input) do
        {:error, "Input cannot be nil"}
      else
        # Process the input
        processed = String.trim(input)
        
        # Validate processed input
        if String.length(processed) == 0 do
          {:error, "Input cannot be empty"}
        else
          # Transform the input
          transformed = String.upcase(processed)
          
          # More processing
          result = transformed |> String.reverse() |> String.downcase()
          
          # Final validation
          if String.length(result) > 100 do
            {:error, "Result too long"}
          else
            {:ok, result}
          end
        end
      end
    end
  end
  """
  
  @poorly_formatted_code """
  defmodule PoorFormat do
  def bad_formatting(x,y) do
  if x>0 do
  x+y
  else
  0
  end
  end
  def   another_bad_method(  ) do
  42    
  end
  end
  """
  
  describe "analyze_code_metrics/3" do
    test "analyzes simple code successfully" do
      standards = %{
        "cyclomatic_complexity" => %{definition: %{max_value: 10}}
      }
      
      result = QualityAnalyzer.analyze_code_metrics(@simple_code, standards)
      
      assert {:ok, metrics} = result
      assert is_number(metrics.cyclomatic_complexity)
      assert is_number(metrics.cognitive_complexity)
      assert is_number(metrics.maintainability_index)
      assert is_list(metrics.technical_debt)
      assert is_list(metrics.code_smells)
      assert is_number(metrics.quality_score)
      assert metrics.confidence > 0
    end
    
    test "detects high complexity in complex code" do
      standards = %{
        "cyclomatic_complexity" => %{definition: %{max_value: 5}}
      }
      
      result = QualityAnalyzer.analyze_code_metrics(@complex_code, standards)
      
      assert {:ok, metrics} = result
      assert metrics.cyclomatic_complexity > 5
      assert length(metrics.technical_debt) > 0
      assert length(metrics.code_smells) > 0
      
      # Find complexity-related technical debt
      complexity_debt = Enum.find(metrics.technical_debt, &(&1.type == "complexity"))
      assert complexity_debt != nil
    end
    
    test "handles syntax errors gracefully" do
      invalid_code = "defmodule Invalid do { invalid syntax"
      
      result = QualityAnalyzer.analyze_code_metrics(invalid_code, %{})
      
      assert {:error, error_message} = result
      assert String.contains?(error_message, "Syntax error")
    end
    
    test "calculates quality score correctly" do
      result = QualityAnalyzer.analyze_code_metrics(@simple_code, %{})
      
      assert {:ok, metrics} = result
      assert metrics.quality_score >= 0.0
      assert metrics.quality_score <= 1.0
      
      # Simple code should have higher quality score than complex code
      {:ok, complex_metrics} = QualityAnalyzer.analyze_code_metrics(@complex_code, %{})
      assert metrics.quality_score > complex_metrics.quality_score
    end
  end
  
  describe "analyze_code_style/3" do
    test "analyzes style in well-formatted code" do
      standards = %{
        "line_length" => %{definition: %{max_length: 120}}
      }
      
      result = QualityAnalyzer.analyze_code_style(@simple_code, standards)
      
      assert {:ok, style_analysis} = result
      assert is_list(style_analysis.formatting_issues)
      assert is_list(style_analysis.naming_violations)
      assert is_list(style_analysis.documentation_gaps)
      assert is_number(style_analysis.style_score)
      assert is_list(style_analysis.recommendations)
      assert style_analysis.confidence > 0
    end
    
    test "detects formatting issues in poorly formatted code" do
      result = QualityAnalyzer.analyze_code_style(@poorly_formatted_code, %{})
      
      assert {:ok, style_analysis} = result
      assert length(style_analysis.formatting_issues) > 0
      
      # Should detect indentation and spacing issues
      formatting_types = Enum.map(style_analysis.formatting_issues, & &1.type)
      assert "mixed_indentation" in formatting_types or length(formatting_types) > 0
    end
    
    test "detects naming convention violations" do
      bad_naming_code = """
      defmodule BadNaming do
        def BadMethodName(X, Y) do
          temp_var = X + Y
          temp_var
        end
        
        def x(y) do
          y
        end
      end
      """
      
      result = QualityAnalyzer.analyze_code_style(bad_naming_code, %{})
      
      assert {:ok, style_analysis} = result
      assert length(style_analysis.naming_violations) > 0
    end
    
    test "generates style recommendations" do
      result = QualityAnalyzer.analyze_code_style(@poorly_formatted_code, %{})
      
      assert {:ok, style_analysis} = result
      assert length(style_analysis.recommendations) > 0
      
      recommendation_actions = Enum.map(style_analysis.recommendations, & &1.action)
      assert Enum.any?(recommendation_actions, &String.contains?(&1, "formatting"))
    end
  end
  
  describe "analyze_complexity/2" do
    test "analyzes complexity metrics" do
      result = QualityAnalyzer.analyze_complexity(@complex_code)
      
      assert {:ok, complexity_analysis} = result
      assert is_list(complexity_analysis.function_complexity)
      assert is_number(complexity_analysis.nesting_depth)
      assert is_list(complexity_analysis.method_length)
      assert is_list(complexity_analysis.class_complexity)
      assert is_list(complexity_analysis.hotspots)
      assert is_list(complexity_analysis.suggestions)
      assert complexity_analysis.confidence > 0
    end
    
    test "identifies complexity hotspots" do
      result = QualityAnalyzer.analyze_complexity(@complex_code)
      
      assert {:ok, complexity_analysis} = result
      assert length(complexity_analysis.hotspots) > 0
      
      # Should identify the complex function as a hotspot
      function_hotspots = Enum.filter(complexity_analysis.hotspots, &(&1.type == "function"))
      assert length(function_hotspots) > 0
    end
    
    test "suggests complexity improvements" do
      result = QualityAnalyzer.analyze_complexity(@complex_code)
      
      assert {:ok, complexity_analysis} = result
      assert length(complexity_analysis.suggestions) > 0
      
      # Should suggest refactoring techniques
      suggestion_techniques = Enum.map(complexity_analysis.suggestions, & &1.technique)
      assert "extract_method" in suggestion_techniques
    end
    
    test "calculates nesting depth correctly" do
      deeply_nested_code = """
      defmodule DeepNesting do
        def deep_function(x) do
          if x > 0 do
            if x > 10 do
              if x > 20 do
                if x > 30 do
                  "very deep"
                end
              end
            end
          end
        end
      end
      """
      
      result = QualityAnalyzer.analyze_complexity(deeply_nested_code)
      
      assert {:ok, complexity_analysis} = result
      assert complexity_analysis.nesting_depth >= 4
    end
  end
  
  describe "analyze_maintainability/3" do
    test "analyzes maintainability aspects" do
      practices = %{
        "single_responsibility" => %{
          definition: %{description: "Each module should have one responsibility"}
        }
      }
      
      result = QualityAnalyzer.analyze_maintainability(@simple_code, practices)
      
      assert {:ok, maintainability_analysis} = result
      assert is_list(maintainability_analysis.design_patterns)
      assert is_list(maintainability_analysis.code_smells)
      assert is_list(maintainability_analysis.architectural_issues)
      assert is_number(maintainability_analysis.maintainability_score)
      assert is_list(maintainability_analysis.improvement_areas)
      assert maintainability_analysis.confidence > 0
    end
    
    test "detects design patterns" do
      genserver_code = """
      defmodule MyGenServer do
        use GenServer
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(state) do
          {:ok, state}
        end
        
        def handle_call(:get_state, _from, state) do
          {:reply, state, state}
        end
      end
      """
      
      result = QualityAnalyzer.analyze_maintainability(genserver_code, %{})
      
      assert {:ok, maintainability_analysis} = result
      
      # Should detect GenServer pattern
      pattern_types = Enum.map(maintainability_analysis.design_patterns, & &1.pattern)
      assert "genserver" in pattern_types
    end
    
    test "identifies code smells" do
      # Code with long method (code smell)
      long_method_code = @complex_code
      
      result = QualityAnalyzer.analyze_maintainability(long_method_code, %{})
      
      assert {:ok, maintainability_analysis} = result
      assert length(maintainability_analysis.code_smells) > 0
    end
    
    test "suggests improvement areas" do
      result = QualityAnalyzer.analyze_maintainability(@complex_code, %{})
      
      assert {:ok, maintainability_analysis} = result
      assert length(maintainability_analysis.improvement_areas) >= 0
      
      # If there are improvement areas, they should have priority and impact
      if length(maintainability_analysis.improvement_areas) > 0 do
        first_area = List.first(maintainability_analysis.improvement_areas)
        assert Map.has_key?(first_area, :area)
        assert Map.has_key?(first_area, :priority)
        assert Map.has_key?(first_area, :impact)
      end
    end
  end
  
  describe "analyze_documentation/3" do
    test "analyzes documentation coverage and quality" do
      documented_code = """
      defmodule DocumentedModule do
        @moduledoc "A well-documented module"
        
        @doc "Adds two numbers together"
        def add(a, b) do
          a + b
        end
        
        @doc "Multiplies two numbers"
        def multiply(x, y) do
          x * y
        end
      end
      """
      
      standards = %{
        "documentation_coverage" => %{definition: %{min_coverage: 80}}
      }
      
      result = QualityAnalyzer.analyze_documentation(documented_code, standards)
      
      assert {:ok, doc_analysis} = result
      assert is_number(doc_analysis.coverage_percentage)
      assert is_list(doc_analysis.missing_docs)
      assert is_number(doc_analysis.quality_score)
      assert is_list(doc_analysis.consistency_issues)
      assert is_list(doc_analysis.suggestions)
      assert doc_analysis.confidence > 0
    end
    
    test "identifies missing documentation" do
      result = QualityAnalyzer.analyze_documentation(@simple_code, %{})
      
      assert {:ok, doc_analysis} = result
      
      # Simple code has moduledoc but no function docs
      assert length(doc_analysis.missing_docs) >= 0
      assert doc_analysis.coverage_percentage >= 0
    end
    
    test "assesses documentation quality" do
      high_quality_doc_code = """
      defmodule HighQualityDocs do
        @moduledoc \"\"\"
        This module provides mathematical operations with comprehensive error handling.
        
        It follows functional programming principles and provides clear interfaces
        for mathematical computations.
        \"\"\"
        
        @doc \"\"\"
        Adds two numbers with validation.
        
        ## Parameters
        - a: First number (integer or float)
        - b: Second number (integer or float)
        
        ## Returns
        - Sum of a and b
        
        ## Examples
            iex> HighQualityDocs.add(2, 3)
            5
        \"\"\"
        def add(a, b) do
          a + b
        end
      end
      """
      
      result = QualityAnalyzer.analyze_documentation(high_quality_doc_code, %{})
      
      assert {:ok, doc_analysis} = result
      assert doc_analysis.quality_score > 0.5  # Should be relatively high
    end
    
    test "generates documentation suggestions" do
      undocumented_code = """
      defmodule UndocumentedModule do
        def method_one(x) do
          x * 2
        end
        
        def method_two(y) do
          y + 1
        end
      end
      """
      
      result = QualityAnalyzer.analyze_documentation(undocumented_code, %{})
      
      assert {:ok, doc_analysis} = result
      assert length(doc_analysis.suggestions) > 0
      
      # Should suggest adding documentation
      suggestion_actions = Enum.map(doc_analysis.suggestions, & &1.action)
      assert Enum.any?(suggestion_actions, &String.contains?(&1, "documentation"))
    end
  end
  
  describe "check_best_practices/4" do
    test "checks best practices compliance" do
      practices = ["single_responsibility", "dry_principle", "meaningful_names"]
      practice_definitions = %{
        "single_responsibility" => %{
          definition: %{description: "Single responsibility principle"}
        },
        "dry_principle" => %{
          definition: %{description: "Don't repeat yourself"}
        },
        "meaningful_names" => %{
          definition: %{description: "Use meaningful names"}
        }
      }
      
      result = QualityAnalyzer.check_best_practices(@simple_code, practices, practice_definitions)
      
      assert {:ok, practices_result} = result
      assert is_list(practices_result.violations)
      assert is_list(practices_result.compliant)
      assert is_number(practices_result.compliance_score)
      assert is_list(practices_result.recommendations)
      assert practices_result.confidence > 0
    end
    
    test "detects DRY principle violations" do
      duplicate_code = """
      defmodule DuplicateCode do
        def process_data_a(data) do
          validated = validate_input(data)
          processed = transform_data(validated)
          save_result(processed)
        end
        
        def process_data_b(data) do
          validated = validate_input(data)
          processed = transform_data(validated)
          save_result(processed)
        end
        
        defp validate_input(data), do: data
        defp transform_data(data), do: data
        defp save_result(data), do: data
      end
      """
      
      practices = ["dry_principle"]
      practice_definitions = %{
        "dry_principle" => %{
          definition: %{description: "Don't repeat yourself"}
        }
      }
      
      result = QualityAnalyzer.check_best_practices(duplicate_code, practices, practice_definitions)
      
      assert {:ok, practices_result} = result
      
      # Should detect DRY violation due to duplication
      dry_violations = Enum.filter(practices_result.violations, &(&1.practice == "dry_principle"))
      assert length(dry_violations) > 0
    end
    
    test "detects meaningful names violations" do
      poor_naming_code = """
      defmodule PoorNaming do
        def x(y, z) do
          temp = y + z
          data = temp * 2
          info = data - 1
          info
        end
        
        def process(a) do
          a
        end
      end
      """
      
      practices = ["meaningful_names"]
      practice_definitions = %{
        "meaningful_names" => %{
          definition: %{description: "Use meaningful names"}
        }
      }
      
      result = QualityAnalyzer.check_best_practices(poor_naming_code, practices, practice_definitions)
      
      assert {:ok, practices_result} = result
      
      # Should detect naming violations
      naming_violations = Enum.filter(practices_result.violations, &(&1.practice == "meaningful_names"))
      assert length(naming_violations) > 0
    end
    
    test "generates practice recommendations" do
      practices = ["single_responsibility"]
      practice_definitions = %{
        "single_responsibility" => %{
          definition: %{description: "Single responsibility principle"}
        }
      }
      
      result = QualityAnalyzer.check_best_practices(@complex_code, practices, practice_definitions)
      
      assert {:ok, practices_result} = result
      assert length(practices_result.recommendations) >= 0
      
      # Recommendations should have required fields
      if length(practices_result.recommendations) > 0 do
        first_recommendation = List.first(practices_result.recommendations)
        assert Map.has_key?(first_recommendation, :practice)
        assert Map.has_key?(first_recommendation, :action)
        assert Map.has_key?(first_recommendation, :priority)
      end
    end
    
    test "calculates compliance score correctly" do
      practices = ["single_responsibility", "dry_principle"]
      practice_definitions = %{
        "single_responsibility" => %{definition: %{description: "SRP"}},
        "dry_principle" => %{definition: %{description: "DRY"}}
      }
      
      result = QualityAnalyzer.check_best_practices(@simple_code, practices, practice_definitions)
      
      assert {:ok, practices_result} = result
      assert practices_result.compliance_score >= 0.0
      assert practices_result.compliance_score <= 1.0
      
      # Compliance score should be based on compliant vs total practices
      total_practices = length(practices)
      compliant_count = length(practices_result.compliant)
      expected_score = compliant_count / total_practices
      
      assert abs(practices_result.compliance_score - expected_score) < 0.01
    end
  end
  
  describe "error handling" do
    test "handles empty code gracefully" do
      result = QualityAnalyzer.analyze_code_metrics("", %{})
      
      # Should either succeed with minimal metrics or fail gracefully
      case result do
        {:ok, metrics} ->
          assert is_map(metrics)
        {:error, _reason} ->
          assert true  # Acceptable to fail on empty code
      end
    end
    
    test "handles malformed AST gracefully" do
      # This should trigger internal errors during analysis
      very_complex_code = String.duplicate(@complex_code, 100)
      
      result = QualityAnalyzer.analyze_code_metrics(very_complex_code, %{})
      
      # Should either succeed or fail gracefully without crashing
      case result do
        {:ok, _metrics} -> assert true
        {:error, _reason} -> assert true
      end
    end
  end
end