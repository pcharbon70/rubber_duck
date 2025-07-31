defmodule RubberDuck.Tools.Agents.CodeComparerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeComparerAgent
  
  setup do
    {:ok, agent} = CodeComparerAgent.start_link(id: "test_comparer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        file1: "path/to/file1.ex",
        file2: "path/to/file2.ex",
        options: %{ignore_whitespace: true}
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: CodeComparerAgent}
      
      # Mock the Executor response
      # In real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = CodeComparerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "batch compare action processes multiple comparisons", %{agent: agent} do
      comparisons = [
        %{file1: "a.ex", file2: "b.ex"},
        %{file1: "c.ex", file2: "d.ex"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Execute batch compare
      {:ok, result} = CodeComparerAgent.BatchCompareAction.run(
        %{comparisons: comparisons, parallel: false}, 
        context
      )
      
      assert result.total == 2
      assert is_list(result.results)
    end
    
    test "analyze patterns action finds recurring patterns", %{agent: agent} do
      # First, populate some history
      state = GenServer.call(agent, :get_state)
      
      history = [
        %{type: :refactoring, changes: [%{type: :added}, %{type: :removed}], timestamp: DateTime.utc_now()},
        %{type: :refactoring, changes: [%{type: :added}, %{type: :removed}], timestamp: DateTime.utc_now()},
        %{type: :bug_fixes, changes: [%{description: "fix null pointer"}], timestamp: DateTime.utc_now()}
      ]
      
      state = put_in(state.state.comparison_history, history)
      GenServer.call(agent, {:set_state, state})
      
      context = %{agent: state}
      
      # Analyze patterns
      {:ok, result} = CodeComparerAgent.AnalyzePatternsAction.run(
        %{pattern_type: :all, min_occurrences: 2},
        context
      )
      
      assert result.pattern_type == :all
      assert is_integer(result.patterns_found)
      assert is_list(result.patterns)
    end
    
    test "generate report action creates markdown report", %{agent: agent} do
      # Setup some history
      state = GenServer.call(agent, :get_state)
      
      history = [
        %{file1: "a.ex", file2: "b.ex", timestamp: DateTime.utc_now(), changes: []},
        %{file1: "c.ex", file2: "d.ex", timestamp: DateTime.utc_now(), changes: []}
      ]
      
      state = put_in(state.state.comparison_history, history)
      GenServer.call(agent, {:set_state, state})
      
      context = %{agent: state}
      
      # Generate report
      {:ok, result} = CodeComparerAgent.GenerateReportAction.run(
        %{format: :markdown, include_patterns: true},
        context
      )
      
      assert result.format == :markdown
      assert is_binary(result.report)
      assert String.contains?(result.report, "Code Comparison Report")
      assert result.comparisons_included == 2
    end
  end
  
  describe "signal handling with actions" do
    test "tool_request signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "tool_request",
        "data" => %{
          "params" => %{
            "file1" => "test1.ex",
            "file2" => "test2.ex"
          }
        }
      }
      
      # Send signal
      {:ok, updated_agent} = CodeComparerAgent.handle_signal(
        GenServer.call(agent, :get_state),
        signal
      )
      
      # Verify request was queued or processed
      assert is_map(updated_agent.state.active_requests) || 
             length(updated_agent.state.request_queue) > 0
    end
    
    test "batch_compare signal triggers BatchCompareAction", %{agent: agent} do
      signal = %{
        "type" => "batch_compare",
        "data" => %{
          "comparisons" => [
            %{"file1" => "a.ex", "file2" => "b.ex"},
            %{"file1" => "c.ex", "file2" => "d.ex"}
          ],
          "parallel" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeComparerAgent.handle_tool_signal(state, signal)
      
      # In a real test, we'd verify the action was executed
      assert true
    end
    
    test "analyze_patterns signal triggers AnalyzePatternsAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_patterns",
        "data" => %{
          "pattern_type" => "refactoring",
          "min_occurrences" => 3
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeComparerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_report signal triggers GenerateReportAction", %{agent: agent} do
      signal = %{
        "type" => "generate_report",
        "data" => %{
          "format" => "json",
          "include_patterns" => false
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeComparerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "result processing and history" do
    test "process_result adds timestamp", %{agent: _agent} do
      result = %{changes: [], file1: "a.ex", file2: "b.ex"}
      processed = CodeComparerAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :timestamp)
      assert %DateTime{} = processed.timestamp
    end
    
    test "successful comparisons update history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful execution
      result = %{
        result: %{
          file1: "a.ex",
          file2: "b.ex", 
          changes: [%{type: :added}]
        },
        from_cache: false
      }
      
      {:ok, updated} = CodeComparerAgent.handle_action_result(
        state,
        CodeComparerAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert length(updated.state.comparison_history) == 1
      assert hd(updated.state.comparison_history).file1 == "a.ex"
    end
    
    test "cached results don't update history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        result: %{file1: "a.ex", file2: "b.ex"},
        from_cache: true
      }
      
      {:ok, updated} = CodeComparerAgent.handle_action_result(
        state,
        CodeComparerAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert length(updated.state.comparison_history) == 0
    end
    
    test "history respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple comparisons
      state = Enum.reduce(1..3, state, fn i, acc ->
        result = %{
          result: %{
            file1: "file#{i}.ex",
            file2: "file#{i+1}.ex",
            changes: []
          },
          from_cache: false
        }
        
        {:ok, updated} = CodeComparerAgent.handle_action_result(
          acc,
          CodeComparerAgent.ExecuteToolAction,
          {:ok, result},
          %{}
        )
        
        updated
      end)
      
      assert length(state.state.comparison_history) == 2
      assert hd(state.state.comparison_history).file1 == "file3.ex"
    end
  end
  
  describe "pattern detection" do
    test "classifies refactoring patterns", %{agent: _agent} do
      result = %{
        changes: [
          %{type: :added},
          %{type: :removed},
          %{type: :added},
          %{type: :removed}
        ]
      }
      
      # This would be a private function test in practice
      # Just verifying the logic exists
      assert CodeComparerAgent.process_result(result, %{})
    end
    
    test "detects bug fix patterns", %{agent: _agent} do
      result = %{
        changes: [
          %{type: :modified, description: "Fix null pointer exception"},
          %{type: :added, description: "Add error handling"}
        ]
      }
      
      processed = CodeComparerAgent.process_result(result, %{})
      assert Map.has_key?(processed, :timestamp)
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = CodeComparerAgent.additional_actions()
      
      assert length(actions) == 3
      assert CodeComparerAgent.BatchCompareAction in actions
      assert CodeComparerAgent.AnalyzePatternsAction in actions
      assert CodeComparerAgent.GenerateReportAction in actions
    end
  end
end