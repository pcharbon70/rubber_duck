defmodule RubberDuck.Enhancement.BasicTest do
  use ExUnit.Case
  
  alias RubberDuck.Enhancement.{TechniqueSelector, PipelineBuilder, MetricsCollector}
  
  describe "technique selection" do
    test "selects techniques for code generation task" do
      task = %{
        type: :code_generation,
        content: "Create a function",
        context: %{},
        options: []
      }
      
      techniques = TechniqueSelector.select_techniques(task)
      assert is_list(techniques)
      assert length(techniques) > 0
    end
  end
  
  describe "pipeline building" do
    test "builds sequential pipeline" do
      techniques = [{:rag, %{}}, {:cot, %{}}]
      pipeline = PipelineBuilder.build(techniques, :sequential)
      
      assert pipeline == techniques
    end
    
    test "validates non-empty pipeline" do
      pipeline = [{:rag, %{}}, {:cot, %{}}]
      assert PipelineBuilder.validate(pipeline) == :ok
    end
  end
  
  describe "metrics collection" do
    test "collects basic metrics" do
      result = %{
        original: "test",
        enhanced: "enhanced test",
        duration_ms: 100,
        context: %{}
      }
      
      metrics = MetricsCollector.collect(result, [:cot])
      
      assert metrics["execution_time_ms"] == 100
      assert metrics["content_length_original"] == 4
      assert metrics["content_length_enhanced"] == 13
    end
  end
end