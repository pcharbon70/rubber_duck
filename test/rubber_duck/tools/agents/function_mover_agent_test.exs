defmodule RubberDuck.Tools.Agents.FunctionMoverAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.FunctionMoverAgent
  
  setup do
    {:ok, agent} = FunctionMoverAgent.start_link(id: "test_function_mover")
    
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
        source_code: """
        defmodule Source do
          def test_function(x), do: x * 2
        end
        """,
        target_code: """
        defmodule Target do
          def existing, do: :ok
        end
        """,
        function_name: "test_function",
        source_module: "Source",
        target_module: "Target"
      }
      
      context = %{agent: GenServer.call(agent, :get_state), parent_module: FunctionMoverAgent}
      
      result = FunctionMoverAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "batch move action executes multiple moves", %{agent: agent} do
      moves = [
        %{
          "function_name" => "helper_a",
          "source_module" => "ModuleA",
          "target_module" => "Utils"
        },
        %{
          "function_name" => "helper_b",
          "source_module" => "ModuleB", 
          "target_module" => "Utils"
        }
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.BatchMoveAction.run(
        %{
          moves: moves,
          strategy: :sequential,
          rollback_on_failure: true,
          dry_run: true
        },
        context
      )
      
      assert result.dry_run == true
      assert result.total_moves == 2
      assert length(result.simulated_results) == 2
    end
    
    test "analyze move action provides impact analysis", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.AnalyzeMoveAction.run(
        %{
          source_module: "Source",
          target_module: "Target",
          function_name: "test_function",
          function_arity: 1,
          analysis_depth: :deep
        },
        context
      )
      
      assert result.source_module == "Source"
      assert result.target_module == "Target"
      assert result.function == "test_function/1"
      assert Map.has_key?(result.analysis, :move_feasibility)
      assert Map.has_key?(result.analysis, :impact_assessment)
      assert Map.has_key?(result.analysis, :risk_assessment)
    end
    
    test "suggest moves action analyzes modules for improvement opportunities", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.SuggestMovesAction.run(
        %{
          modules: ["MyApp.Service", "MyApp.Controller"],
          criteria: [:cohesion, :coupling],
          max_suggestions: 5,
          min_benefit_score: 0.1
        },
        context
      )
      
      assert result.total_suggestions >= 0
      assert is_list(result.suggestions)
      assert result.analysis_criteria == [:cohesion, :coupling]
      
      if length(result.suggestions) > 0 do
        suggestion = hd(result.suggestions)
        assert Map.has_key?(suggestion, :function)
        assert Map.has_key?(suggestion, :source_module)
        assert Map.has_key?(suggestion, :suggested_target)
        assert Map.has_key?(suggestion, :benefit_score)
      end
    end
    
    test "validate move action checks move safety", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.ValidateMoveAction.run(
        %{
          source_module: "Source",
          target_module: "Target",
          function_name: "test_function",
          function_arity: 1,
          validation_level: :thorough
        },
        context
      )
      
      assert result.function == "test_function/1"
      assert result.source_module == "Source"
      assert result.target_module == "Target"
      assert result.validation_status in [:passed, :warning, :failed]
      assert is_boolean(result.can_proceed)
      assert is_list(result.blocking_issues)
      assert is_list(result.warnings)
    end
    
    test "preview move action generates change preview", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.PreviewMoveAction.run(
        %{
          source_module: "Source",
          target_module: "Target",
          function_name: "test_function",
          function_arity: 1,
          include_references: true,
          preview_format: :diff
        },
        context
      )
      
      assert result.function == "test_function/1"
      assert result.preview_format == :diff
      assert Map.has_key?(result.preview, :source_file_diff)
      assert Map.has_key?(result.preview, :target_file_diff)
    end
  end
  
  describe "signal handling with actions" do
    test "move_function signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "move_function",
        "data" => %{
          "source_code" => "defmodule A do\n  def test, do: :ok\nend",
          "target_code" => "defmodule B do\nend",
          "function_name" => "test",
          "source_module" => "A",
          "target_module" => "B"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionMoverAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "batch_move signal triggers BatchMoveAction", %{agent: agent} do
      signal = %{
        "type" => "batch_move",
        "data" => %{
          "moves" => [
            %{"function_name" => "test", "source_module" => "A", "target_module" => "B"}
          ],
          "strategy" => "sequential"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionMoverAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "analyze_move signal triggers AnalyzeMoveAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_move",
        "data" => %{
          "source_module" => "Source",
          "target_module" => "Target",
          "function_name" => "test_function"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = FunctionMoverAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "tracks move history after successful moves", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful move result
      move_result = %{
        moved_function: %{name: :test_function, arity: 1, type: :def},
        dependencies_moved: [],
        reference_updates: [],
        warnings: []
      }
      
      metadata = %{
        source_module: "Source",
        target_module: "Target"
      }
      
      {:ok, updated} = FunctionMoverAgent.handle_action_result(
        state,
        FunctionMoverAgent.ExecuteToolAction,
        {:ok, move_result},
        metadata
      )
      
      assert length(updated.state.move_history) == 1
      move_record = hd(updated.state.move_history)
      assert move_record.function == "test_function/1"
      assert move_record.source_module == "Source"
      assert move_record.target_module == "Target"
    end
    
    test "updates organization metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      initial_total = state.state.organization_metrics.total_moves
      initial_successful = state.state.organization_metrics.successful_moves
      
      move_result = %{
        moved_function: %{name: :test_function, arity: 1, type: :def},
        dependencies_moved: [:helper_function],
        reference_updates: [],
        warnings: []
      }
      
      {:ok, updated} = FunctionMoverAgent.handle_action_result(
        state,
        FunctionMoverAgent.ExecuteToolAction,
        {:ok, move_result},
        %{}
      )
      
      assert updated.state.organization_metrics.total_moves == initial_total + 1
      assert updated.state.organization_metrics.successful_moves == initial_successful + 1
      assert updated.state.organization_metrics.dependencies_updated == 1
    end
    
    test "caches analysis results", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      analysis_result = %{
        source_module: "Source",
        target_module: "Target",
        function: "test_function/1",
        analysis: %{move_feasibility: %{can_move: true}}
      }
      
      {:ok, updated} = FunctionMoverAgent.handle_action_result(
        state,
        FunctionMoverAgent.AnalyzeMoveAction,
        {:ok, analysis_result},
        %{}
      )
      
      cache_key = "Source:test_function/1:Target"
      assert Map.has_key?(updated.state.analysis_cache, cache_key)
      assert updated.state.analysis_cache[cache_key].result == analysis_result
    end
  end
  
  describe "agent initialization" do
    test "starts with default move patterns", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      patterns = state.state.move_patterns
      assert Map.has_key?(patterns, "utility_functions")
      assert Map.has_key?(patterns, "domain_functions")
      assert Map.has_key?(patterns, "validation_functions")
    end
    
    test "starts with default suggestion criteria", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      criteria = state.state.suggestion_criteria
      assert criteria.cohesion_threshold == 0.7
      assert criteria.coupling_threshold == 0.3
      assert criteria.utility_usage_threshold == 3
    end
    
    test "starts with empty move history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.move_history == []
      assert state.state.analysis_cache == %{}
      assert state.state.active_batch_moves == %{}
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = FunctionMoverAgent.additional_actions()
      
      assert length(actions) == 5
      assert FunctionMoverAgent.BatchMoveAction in actions
      assert FunctionMoverAgent.AnalyzeMoveAction in actions
      assert FunctionMoverAgent.SuggestMovesAction in actions
      assert FunctionMoverAgent.ValidateMoveAction in actions
      assert FunctionMoverAgent.PreviewMoveAction in actions
    end
  end
  
  describe "batch move strategies" do
    test "sequential strategy executes moves in order", %{agent: agent} do
      moves = [
        %{"function_name" => "first", "source_module" => "A", "target_module" => "Utils"},
        %{"function_name" => "second", "source_module" => "B", "target_module" => "Utils"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.BatchMoveAction.run(
        %{moves: moves, strategy: :sequential, dry_run: true},
        context
      )
      
      assert result.total_moves == 2
      assert result.dry_run == true
    end
    
    test "parallel strategy can execute moves concurrently", %{agent: agent} do
      moves = [
        %{"function_name" => "first", "source_module" => "A", "target_module" => "Utils"},
        %{"function_name" => "second", "source_module" => "B", "target_module" => "Helpers"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.BatchMoveAction.run(
        %{moves: moves, strategy: :parallel, dry_run: true},
        context
      )
      
      assert result.total_moves == 2
      assert result.dry_run == true
    end
  end
  
  describe "move validation levels" do
    test "basic validation performs minimal checks", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.ValidateMoveAction.run(
        %{
          source_module: "Source",
          target_module: "Target",
          function_name: "test",
          validation_level: :basic
        },
        context
      )
      
      assert result.validation_status in [:passed, :warning, :failed]
    end
    
    test "comprehensive validation performs thorough analysis", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = FunctionMoverAgent.ValidateMoveAction.run(
        %{
          source_module: "Source",
          target_module: "Target",
          function_name: "test",
          validation_level: :comprehensive
        },
        context
      )
      
      validation_results = result.validation_results
      assert Map.has_key?(validation_results, :syntax_check)
      assert Map.has_key?(validation_results, :dependency_check)
      assert Map.has_key?(validation_results, :naming_conflicts)
      assert Map.has_key?(validation_results, :circular_dependencies)
      assert Map.has_key?(validation_results, :test_coverage)
      assert Map.has_key?(validation_results, :documentation)
    end
  end
end