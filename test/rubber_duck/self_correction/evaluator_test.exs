defmodule RubberDuck.SelfCorrection.EvaluatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.SelfCorrection.Evaluator
  
  describe "evaluate/4" do
    test "evaluates code quality" do
      content = """
      defmodule Example do
        def add(x, y) do
          x + y
        end
      end
      """
      
      result = Evaluator.evaluate(content, :code, %{language: "elixir"}, %{})
      
      assert is_float(result.overall_score)
      assert result.overall_score > 0.5
      assert is_map(result.dimensions)
      assert Map.has_key?(result.dimensions, :syntax)
      assert Map.has_key?(result.dimensions, :semantics)
      assert Map.has_key?(result.dimensions, :logic)
      assert Map.has_key?(result.dimensions, :clarity)
      assert Map.has_key?(result.dimensions, :completeness)
      assert Map.has_key?(result.dimensions, :coherence)
    end
    
    test "evaluates text quality" do
      content = "This is a well-written paragraph with clear meaning."
      
      result = Evaluator.evaluate(content, :text, %{}, %{})
      
      assert is_float(result.overall_score)
      assert result.overall_score > 0.6
      assert Map.has_key?(result.metadata, :readability)
    end
    
    test "detects syntax issues" do
      content = """
      def broken(x do
        x + 1
      """
      
      result = Evaluator.evaluate(content, :code, %{}, %{})
      
      assert result.dimensions.syntax < 0.5
      assert result.overall_score < 0.5
    end
    
    test "detects semantic issues" do
      content = """
      def a(b, c) do
        d = b + c
        d
      end
      """
      
      result = Evaluator.evaluate(content, :code, %{}, %{})
      
      assert result.dimensions.semantics < 0.8  # Poor naming
    end
    
    test "detects logic issues" do
      content = """
      if true do
        "always"
      else
        "never"
      end
      """
      
      result = Evaluator.evaluate(content, :code, %{}, %{})
      
      assert result.dimensions.logic < 0.8  # Constant condition
    end
    
    test "evaluates mixed content" do
      content = """
      # Example
      
      Here's some code:
      
      ```elixir
      def hello, do: "world"
      ```
      """
      
      result = Evaluator.evaluate(content, :mixed, %{}, %{})
      
      assert is_float(result.overall_score)
      assert Map.has_key?(result.metadata, :content_mix)
    end
  end
  
  describe "compare_evaluations/2" do
    test "compares two evaluations" do
      eval1 = %{
        overall_score: 0.6,
        dimensions: %{
          syntax: 0.7,
          semantics: 0.5,
          logic: 0.6
        }
      }
      
      eval2 = %{
        overall_score: 0.8,
        dimensions: %{
          syntax: 0.9,
          semantics: 0.7,
          logic: 0.8
        }
      }
      
      comparison = Evaluator.compare_evaluations(eval1, eval2)
      
      assert comparison.overall_improvement == 0.2
      assert comparison.improved == true
      assert comparison.dimension_improvements.syntax == 0.2
      assert comparison.dimension_improvements.semantics == 0.2
      assert comparison.dimension_improvements.logic == 0.2
    end
    
    test "detects no improvement" do
      eval1 = %{
        overall_score: 0.8,
        dimensions: %{syntax: 0.8, semantics: 0.8, logic: 0.8}
      }
      
      eval2 = %{
        overall_score: 0.7,
        dimensions: %{syntax: 0.7, semantics: 0.7, logic: 0.7}
      }
      
      comparison = Evaluator.compare_evaluations(eval1, eval2)
      
      assert comparison.improved == false
      assert comparison.overall_improvement == -0.1
    end
  end
  
  describe "meets_threshold?/2" do
    test "checks if evaluation meets threshold" do
      good_eval = %{overall_score: 0.85}
      bad_eval = %{overall_score: 0.65}
      
      assert Evaluator.meets_threshold?(good_eval) == true
      assert Evaluator.meets_threshold?(good_eval, 0.9) == false
      assert Evaluator.meets_threshold?(bad_eval) == false
      assert Evaluator.meets_threshold?(bad_eval, 0.6) == true
    end
  end
  
  describe "dimension scoring" do
    test "syntax scoring detects balanced delimiters" do
      good_syntax = "{ [ ( ) ] }"
      bad_syntax = "{ [ ( ] }"
      
      good_result = Evaluator.evaluate(good_syntax, :code, %{}, %{})
      bad_result = Evaluator.evaluate(bad_syntax, :code, %{}, %{})
      
      assert good_result.dimensions.syntax > bad_result.dimensions.syntax
    end
    
    test "clarity scoring considers sentence length" do
      clear = "This is clear. Short sentences help."
      unclear = "This is a very long sentence that goes on and on and on without any breaks or pauses making it very difficult to read and understand what the main point is supposed to be."
      
      clear_result = Evaluator.evaluate(clear, :text, %{}, %{})
      unclear_result = Evaluator.evaluate(unclear, :text, %{}, %{})
      
      assert clear_result.dimensions.clarity > unclear_result.dimensions.clarity
    end
    
    test "completeness scoring detects incomplete content" do
      complete = "This is a complete thought."
      incomplete = "This is incomplete..."
      
      complete_result = Evaluator.evaluate(complete, :text, %{}, %{})
      incomplete_result = Evaluator.evaluate(incomplete, :text, %{}, %{})
      
      assert complete_result.dimensions.completeness > incomplete_result.dimensions.completeness
    end
    
    test "coherence scoring for consistent code" do
      coherent = """
      def add(x, y) do
        x + y
      end
      
      def subtract(x, y) do
        x - y
      end
      """
      
      incoherent = """
      def add(x,y) do
          x+y
      end
      def subtract( x , y )do
      x-y
      end
      """
      
      coherent_result = Evaluator.evaluate(coherent, :code, %{}, %{})
      incoherent_result = Evaluator.evaluate(incoherent, :code, %{}, %{})
      
      assert coherent_result.dimensions.coherence > incoherent_result.dimensions.coherence
    end
  end
end