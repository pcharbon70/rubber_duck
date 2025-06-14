defmodule RubberDuck.ILP.RealTime.PipelineTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.ILP.RealTime.Pipeline
  
  describe "pipeline" do
    test "can process a simple completion request" do
      request = %{
        type: :completion,
        document_uri: "file:///test.ex",
        content: "defmodule Test do\n  def hello do\n    \nend",
        position: %{line: 2, character: 4}
      }
      
      assert :ok = Pipeline.process_request(request)
    end
    
    test "returns metrics" do
      metrics = Pipeline.get_metrics()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :queue_size)
      assert Map.has_key?(metrics, :cache_stats)
      assert Map.has_key?(metrics, :pipeline_health)
    end
  end
end