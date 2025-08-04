defmodule RubberDuck.Jido.Actions.Workflow.FanoutActionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Actions.Workflow.FanoutAction
  
  # Test actions for fanout
  defmodule EchoAction do
    use Jido.Action,
      name: "echo",
      schema: [
        input_data: [type: :any],
        prefix: [type: :string, default: ""]
      ]
    
    def run(params, context) do
      result = "#{params.prefix}#{inspect(params.input_data)}"
      {:ok, result, context}
    end
  end
  
  defmodule SlowAction do
    use Jido.Action,
      name: "slow",
      schema: [
        input_data: [type: :any],
        delay: [type: :integer, default: 100]
      ]
    
    def run(params, context) do
      Process.sleep(params.delay)
      {:ok, "slow_result", context}
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
    test "broadcasts to multiple targets in parallel" do
      params = %{
        targets: [
          %{action: EchoAction, params: %{prefix: "A:"}},
          %{action: EchoAction, params: %{prefix: "B:"}},
          %{action: EchoAction, params: %{prefix: "C:"}}
        ],
        input_data: "test",
        aggregation: :collect_all
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = FanoutAction.run(params, context)
      assert result.targets_executed == 3
      assert result.successful == 3
      assert result.failed == 0
      
      # Check all results were collected
      results = result.results
      assert length(results) == 3
      assert Enum.all?(results, fn r -> r.status == :success end)
    end
    
    test "aggregation :all_success requires all to succeed" do
      params = %{
        targets: [
          %{action: EchoAction},
          %{action: FailingAction},
          %{action: EchoAction}
        ],
        input_data: "test",
        aggregation: :all_success
      }
      
      context = %{agent: self()}
      
      assert {:error, error_data} = FanoutAction.run(params, context)
      assert {:not_all_successful, failures} = error_data.error
      assert length(failures) == 1
    end
    
    test "aggregation :any_success succeeds if any succeed" do
      params = %{
        targets: [
          %{action: FailingAction},
          %{action: EchoAction},
          %{action: FailingAction}
        ],
        input_data: "test",
        aggregation: :any_success
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = FanoutAction.run(params, context)
      assert result.successful == 1
      assert result.failed == 2
      assert length(result.results) == 1
    end
    
    test "aggregation :race returns first completed" do
      params = %{
        targets: [
          %{action: SlowAction, params: %{delay: 200}},
          %{action: EchoAction},
          %{action: SlowAction, params: %{delay: 300}}
        ],
        input_data: "test",
        aggregation: :race,
        timeout: 1000
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = FanoutAction.run(params, context)
      # Should get the EchoAction result as it's fastest
      assert is_binary(result.results)
    end
    
    test "respects max_concurrency for batched execution" do
      params = %{
        targets: [
          %{action: EchoAction, params: %{prefix: "1"}},
          %{action: EchoAction, params: %{prefix: "2"}},
          %{action: EchoAction, params: %{prefix: "3"}},
          %{action: EchoAction, params: %{prefix: "4"}}
        ],
        input_data: "test",
        max_concurrency: 2,
        aggregation: :collect_all
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = FanoutAction.run(params, context)
      assert result.targets_executed == 4
      assert result.successful == 4
    end
    
    test "handles timeout correctly" do
      params = %{
        targets: [
          %{action: SlowAction, params: %{delay: 1000}}
        ],
        input_data: "test",
        timeout: 100,
        aggregation: :collect_all
      }
      
      context = %{agent: self()}
      
      assert {:ok, result, _context} = FanoutAction.run(params, context)
      assert result.failed == 1
      assert [timeout_result] = result.results
      assert timeout_result.status == :timeout
    end
  end
end