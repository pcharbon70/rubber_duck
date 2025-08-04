defmodule RubberDuck.Jido.Actions.Workflow.PipelineActionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Actions.Workflow.PipelineAction
  
  # Test actions for pipeline
  defmodule AddOneAction do
    use Jido.Action,
      name: "add_one",
      schema: [input_data: [type: :integer, required: true]]
    
    def run(params, context) do
      result = params.input_data + 1
      {:ok, result, context}
    end
  end
  
  defmodule MultiplyByTwoAction do
    use Jido.Action,
      name: "multiply_by_two",
      schema: [input_data: [type: :integer, required: true]]
    
    def run(params, context) do
      result = params.input_data * 2
      {:ok, result, context}
    end
  end
  
  defmodule FailingAction do
    use Jido.Action,
      name: "failing",
      schema: [input_data: [type: :any]]
    
    def run(_params, _context) do
      {:error, :intentional_failure}
    end
  end
  
  describe "run/2" do
    test "executes pipeline stages in sequence" do
      params = %{
        stages: [
          %{action: AddOneAction},
          %{action: MultiplyByTwoAction},
          %{action: AddOneAction}
        ],
        initial_data: 5
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = PipelineAction.run(params, context)
      assert result.final_data == 13  # (5 + 1) * 2 + 1
      assert length(result.stage_results) == 3
    end
    
    test "supports transformation functions between stages" do
      params = %{
        stages: [
          %{action: AddOneAction},
          %{
            action: MultiplyByTwoAction,
            transform: fn x -> x + 10 end
          }
        ],
        initial_data: 5
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = PipelineAction.run(params, context)
      assert result.final_data == 32  # ((5 + 1) + 10) * 2
    end
    
    test "stops on error when stop_on_error is true" do
      params = %{
        stages: [
          %{action: AddOneAction},
          %{action: FailingAction},
          %{action: MultiplyByTwoAction}
        ],
        initial_data: 5,
        stop_on_error: true
      }
      
      context = %{agent: self()}
      
      assert {:error, error_data} = PipelineAction.run(params, context)
      assert error_data.failed_at_stage == 2
      assert error_data.error == :intentional_failure
      assert length(error_data.partial_results) == 1
    end
    
    test "continues on error when stop_on_error is false" do
      params = %{
        stages: [
          %{action: AddOneAction},
          %{action: FailingAction},
          %{action: AddOneAction}
        ],
        initial_data: 5,
        stop_on_error: false
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = PipelineAction.run(params, context)
      assert result.stages_executed == 3
    end
    
    test "generates unique pipeline_id if not provided" do
      params = %{
        stages: [%{action: AddOneAction}],
        initial_data: 1
      }
      
      context = %{agent: self()}
      
      assert {:ok, result1, _} = PipelineAction.run(params, context)
      assert {:ok, result2, _} = PipelineAction.run(params, context)
      
      assert result1.pipeline_id != result2.pipeline_id
      assert String.starts_with?(result1.pipeline_id, "pipeline_")
    end
    
    test "uses provided pipeline_id" do
      params = %{
        stages: [%{action: AddOneAction}],
        initial_data: 1,
        pipeline_id: "custom_pipeline_123"
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _} = PipelineAction.run(params, context)
      assert result.pipeline_id == "custom_pipeline_123"
    end
  end
end