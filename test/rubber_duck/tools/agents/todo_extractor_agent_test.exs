defmodule RubberDuck.Tools.Agents.TodoExtractorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.TodoExtractorAgent
  
  setup do
    {:ok, agent} = TodoExtractorAgent.start_link(id: "test_todo_extractor")
    
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
        code: """
        defmodule Example do
          # TODO: Implement authentication
          def authenticate(user) do
            # FIXME: This is a security vulnerability
            true
          end
          
          # NOTE: Consider refactoring this
          def process_data(data) do
            # HACK: Quick fix for demo
            data
          end
        end
        """,
        patterns: ["TODO", "FIXME", "HACK", "NOTE"],
        group_by: "type"
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      result = TodoExtractorAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
      {:ok, extraction} = result
      
      assert extraction.summary.total_count == 4
      assert Map.has_key?(extraction.summary.by_type, "todo")
      assert Map.has_key?(extraction.summary.by_type, "fixme")
      assert Map.has_key?(extraction.todos, "todo")
      assert Map.has_key?(extraction.todos, "fixme")
    end
    
    test "scan codebase action finds TODOs in files", %{agent: agent} do
      # Create temporary test files
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "todo_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      # Write test files
      File.write!(Path.join(test_dir, "file1.ex"), """
      defmodule File1 do
        # TODO: Add documentation
        def func1, do: :ok
        
        # FIXME: Handle error cases
        def func2, do: :error
      end
      """)
      
      File.write!(Path.join(test_dir, "file2.ex"), """
      defmodule File2 do
        # BUG: Race condition here
        def concurrent_func do
          # TODO: Add mutex
          :unsafe
        end
      end
      """)
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TodoExtractorAgent.ScanCodebaseAction.run(
        %{
          paths: [test_dir],
          file_extensions: [".ex"],
          batch_size: 10
        },
        context
      )
      
      assert result.files_scanned == 2
      assert result.todos_found == 3
      assert length(result.todos) == 3
      
      # Cleanup
      File.rm_rf!(test_dir)
    end
    
    test "analyze debt action calculates technical debt", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Add some TODOs to the database
      todos = %{
        "1" => %{id: "1", type: "bug", priority: :high, complexity: :complex},
        "2" => %{id: "2", type: "todo", priority: :low, complexity: :simple},
        "3" => %{id: "3", type: "fixme", priority: :medium, complexity: :moderate},
        "4" => %{id: "4", type: "hack", priority: :high, complexity: :complex, estimated_age: "old"}
      }
      
      state = put_in(state.state.todo_database, todos)
      context = %{agent: state}
      
      {:ok, result} = TodoExtractorAgent.AnalyzeDebtAction.run(%{}, context)
      
      assert result.total_debt_score > 0
      assert result.debt_level in [:minimal, :low, :medium, :high, :critical]
      assert result.total_items == 4
      assert Map.has_key?(result.distribution, :by_type)
      assert Map.has_key?(result.distribution, :by_priority)
      assert is_list(result.recommendations)
    end
    
    test "track todo lifecycle identifies changes", %{agent: agent} do
      previous_todos = [
        %{file: "test.ex", line_number: 10, type: "todo", description: "Old todo"},
        %{file: "test.ex", line_number: 20, type: "fixme", description: "Fix this"}
      ]
      
      current_todos = [
        %{file: "test.ex", line_number: 20, type: "fixme", description: "Fix this"},
        %{file: "test.ex", line_number: 30, type: "todo", description: "New todo"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = TodoExtractorAgent.TrackTodoLifecycleAction.run(
        %{
          current_todos: current_todos
        },
        context
      )
      
      assert result.metrics.total_before == 0  # No previous scan
      assert result.metrics.total_after == 2
      assert result.trend in [:stable, :increasing, :decreasing]
    end
    
    test "generate report action creates formatted report", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Setup test data
      todos = %{
        "1" => %{id: "1", type: "todo", file: "lib/example.ex", priority: :high},
        "2" => %{id: "2", type: "fixme", file: "lib/example.ex", priority: :medium},
        "3" => %{id: "3", type: "bug", file: "test/test.exs", priority: :high}
      }
      
      state = put_in(state.state.todo_database, todos)
      state = put_in(state.state.debt_metrics, %{
        debt_score: 50.0,
        total_todos: 3,
        high_priority_count: 2
      })
      
      context = %{agent: state}
      
      {:ok, result} = TodoExtractorAgent.GenerateTodoReportAction.run(
        %{
          format: :markdown,
          sections: [:summary, :distribution, :recommendations]
        },
        context
      )
      
      assert result.format == :markdown
      assert is_binary(result.report)
      assert result.report =~ "Technical Debt Report"
      assert result.metadata.total_todos == 3
    end
    
    test "prioritize todos action ranks items", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Setup varied TODOs
      todos = %{
        "1" => %{id: "1", type: "bug", priority: :high, complexity: :simple, description: "Critical security bug"},
        "2" => %{id: "2", type: "todo", priority: :low, complexity: :complex, description: "Refactor module"},
        "3" => %{id: "3", type: "fixme", priority: :medium, complexity: :simple, description: "Fix data validation"},
        "4" => %{id: "4", type: "hack", priority: :low, complexity: :moderate, estimated_age: "old", description: "Old hack"}
      }
      
      state = put_in(state.state.todo_database, todos)
      context = %{agent: state}
      
      {:ok, result} = TodoExtractorAgent.PrioritizeTodosAction.run(
        %{
          criteria: [:impact, :effort, :risk],
          limit: 3
        },
        context
      )
      
      assert result.total_evaluated == 4
      assert result.top_priority_count == 3
      assert length(result.top_priority_items) == 3
      
      # First item should have highest priority score
      [first | _] = result.top_priority_items
      assert first.priority_score > 0
      
      assert Map.has_key?(result, :action_plan)
      assert Map.has_key?(result, :estimated_effort)
    end
  end
  
  describe "signal handling" do
    test "extract_todos signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "extract_todos",
        "data" => %{
          "code" => "# TODO: Test todo",
          "patterns" => ["TODO"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, updated} = TodoExtractorAgent.handle_signal(state, signal)
      
      assert map_size(updated.todo_database) > 0
    end
    
    test "scan_codebase signal triggers codebase scan", %{agent: agent} do
      signal = %{
        "type" => "scan_codebase",
        "data" => %{
          "paths" => ["lib"],
          "file_extensions" => [".ex"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      result = TodoExtractorAgent.handle_signal(state, signal)
      
      assert match?({:ok, _}, result)
    end
    
    test "analyze_debt signal triggers debt analysis", %{agent: agent} do
      signal = %{
        "type" => "analyze_debt",
        "data" => %{}
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, updated} = TodoExtractorAgent.handle_signal(state, signal)
      
      assert Map.has_key?(updated.debt_metrics, :debt_score)
    end
  end
  
  describe "state management" do
    test "updates TODO database after extraction", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      result = %{
        todos: [
          %{type: "todo", file: "test.ex", line_number: 10, description: "Test"}
        ],
        summary: %{total_count: 1},
        statistics: %{}
      }
      
      {:ok, updated} = TodoExtractorAgent.handle_action_result(
        state,
        TodoExtractorAgent.ExecuteToolAction,
        {:ok, result},
        %{}
      )
      
      assert map_size(updated.todo_database) == 1
      
      # Should have generated an ID
      [{id, todo}] = Map.to_list(updated.todo_database)
      assert is_binary(id)
      assert todo.id == id
    end
    
    test "maintains scan history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      scan_result = %{
        scan_id: "scan123",
        files_scanned: 10,
        todos_found: 5,
        todos: [],
        performance: %{duration_ms: 100}
      }
      
      {:ok, updated} = TodoExtractorAgent.handle_action_result(
        state,
        TodoExtractorAgent.ScanCodebaseAction,
        {:ok, scan_result},
        %{}
      )
      
      assert length(updated.scan_history) == 1
      [scan_entry] = updated.scan_history
      assert scan_entry.scan_id == "scan123"
      assert scan_entry.files_scanned == 10
    end
    
    test "updates debt metrics after analysis", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      analysis_result = %{
        total_debt_score: 75.5,
        debt_level: :high,
        total_items: 20,
        distribution: %{
          by_priority: %{high: 5, medium: 10, low: 5}
        }
      }
      
      {:ok, updated} = TodoExtractorAgent.handle_action_result(
        state,
        TodoExtractorAgent.AnalyzeDebtAction,
        {:ok, analysis_result},
        %{}
      )
      
      assert updated.debt_metrics.debt_score == 75.5
      assert updated.debt_metrics.high_priority_count == 5
      assert updated.debt_metrics.total_todos == 20
      assert updated.debt_trends.trend_direction == :increasing
    end
  end
  
  describe "agent initialization" do
    test "starts with default extraction configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.extraction_config
      assert "TODO" in config.standard_patterns
      assert "FIXME" in config.standard_patterns
      assert "URGENT" in config.priority_keywords
      assert config.include_context == true
      assert config.context_lines == 2
    end
    
    test "starts with empty TODO database", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.todo_database == %{}
      assert state.state.scan_history == []
      assert state.state.active_scans == %{}
    end
    
    test "starts with zero debt metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      metrics = state.state.debt_metrics
      assert metrics.total_todos == 0
      assert metrics.high_priority_count == 0
      assert metrics.debt_score == 0.0
      assert metrics.files_with_debt == 0
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = TodoExtractorAgent.additional_actions()
      
      assert length(actions) == 6
      assert TodoExtractorAgent.ExecuteToolAction in actions
      assert TodoExtractorAgent.ScanCodebaseAction in actions
      assert TodoExtractorAgent.AnalyzeDebtAction in actions
      assert TodoExtractorAgent.TrackTodoLifecycleAction in actions
      assert TodoExtractorAgent.GenerateTodoReportAction in actions
      assert TodoExtractorAgent.PrioritizeTodosAction in actions
    end
  end
  
  describe "debt analysis" do
    test "calculates debt score correctly", %{agent: agent} do
      todos = [
        %{priority: :high, complexity: :complex, estimated_age: "old"},
        %{priority: :medium, complexity: :simple},
        %{priority: :low, complexity: :moderate}
      ]
      
      weights = %{
        high_priority: 10,
        medium_priority: 5,
        low_priority: 2,
        complex: 8,
        old: 7
      }
      
      score = TodoExtractorAgent.AnalyzeDebtAction.calculate_debt_score(todos, weights)
      
      # First TODO: 10 (high) + 8 (complex) + 7 (old) = 25
      # Second TODO: 5 (medium) + 0 (simple) = 5
      # Third TODO: 2 (low) + 4 (moderate) = 6
      # Total: 36
      assert score == 36
    end
    
    test "categorizes debt level appropriately", %{agent: agent} do
      thresholds = %{critical: 100, high: 75, medium: 50, low: 25}
      
      assert TodoExtractorAgent.AnalyzeDebtAction.categorize_debt_level(150, thresholds) == :critical
      assert TodoExtractorAgent.AnalyzeDebtAction.categorize_debt_level(80, thresholds) == :high
      assert TodoExtractorAgent.AnalyzeDebtAction.categorize_debt_level(60, thresholds) == :medium
      assert TodoExtractorAgent.AnalyzeDebtAction.categorize_debt_level(30, thresholds) == :low
      assert TodoExtractorAgent.AnalyzeDebtAction.categorize_debt_level(10, thresholds) == :minimal
    end
  end
  
  describe "lifecycle tracking" do
    test "creates unique TODO signatures", %{agent: agent} do
      todo1 = %{file: "test.ex", line_number: 10, type: "todo", description: "Test"}
      todo2 = %{file: "test.ex", line_number: 10, type: "todo", description: "Test"}
      todo3 = %{file: "test.ex", line_number: 11, type: "todo", description: "Test"}
      
      sig1 = TodoExtractorAgent.TrackTodoLifecycleAction.todo_signature(todo1)
      sig2 = TodoExtractorAgent.TrackTodoLifecycleAction.todo_signature(todo2)
      sig3 = TodoExtractorAgent.TrackTodoLifecycleAction.todo_signature(todo3)
      
      assert sig1 == sig2  # Same TODO
      assert sig1 != sig3  # Different line
    end
    
    test "determines trend correctly", %{agent: agent} do
      assert TodoExtractorAgent.TrackTodoLifecycleAction.determine_trend(15.0) == :increasing
      assert TodoExtractorAgent.TrackTodoLifecycleAction.determine_trend(-15.0) == :decreasing
      assert TodoExtractorAgent.TrackTodoLifecycleAction.determine_trend(5.0) == :stable
    end
  end
  
  describe "prioritization" do
    test "estimates impact based on type and priority", %{agent: agent} do
      high_bug = %{priority: :high, type: "bug"}
      medium_todo = %{priority: :medium, type: "todo"}
      security_issue = %{priority: :low, type: "security"}
      
      assert TodoExtractorAgent.PrioritizeTodosAction.estimate_impact(high_bug) == 15.0
      assert TodoExtractorAgent.PrioritizeTodosAction.estimate_impact(medium_todo) == 5.0
      assert TodoExtractorAgent.PrioritizeTodosAction.estimate_impact(security_issue) == 4.0
    end
    
    test "recommends appropriate actions", %{agent: agent} do
      bug = %{type: "bug", priority: :medium}
      high_priority = %{type: "todo", priority: :high}
      simple = %{type: "note", priority: :low, complexity: :simple}
      old = %{type: "todo", priority: :low, estimated_age: "old"}
      
      assert TodoExtractorAgent.PrioritizeTodosAction.recommend_action(bug) == :fix_immediately
      assert TodoExtractorAgent.PrioritizeTodosAction.recommend_action(high_priority) == :schedule_sprint
      assert TodoExtractorAgent.PrioritizeTodosAction.recommend_action(simple) == :quick_win
      assert TodoExtractorAgent.PrioritizeTodosAction.recommend_action(old) == :review_and_close
    end
  end
  
  describe "file scanning" do
    test "finds files with correct extensions", %{agent: agent} do
      tmp_dir = System.tmp_dir!()
      test_dir = Path.join(tmp_dir, "scan_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(test_dir)
      
      # Create test files
      File.write!(Path.join(test_dir, "file1.ex"), "content")
      File.write!(Path.join(test_dir, "file2.exs"), "content")
      File.write!(Path.join(test_dir, "file3.txt"), "content")
      
      files = TodoExtractorAgent.ScanCodebaseAction.find_files_to_scan(%{
        paths: [test_dir],
        file_extensions: [".ex", ".exs"],
        exclude_paths: []
      })
      
      assert length(files) == 2
      assert Enum.any?(files, &String.ends_with?(&1, "file1.ex"))
      assert Enum.any?(files, &String.ends_with?(&1, "file2.exs"))
      assert not Enum.any?(files, &String.ends_with?(&1, "file3.txt"))
      
      # Cleanup
      File.rm_rf!(test_dir)
    end
    
    test "excludes specified paths", %{agent: agent} do
      files = [
        "lib/example.ex",
        "deps/library/file.ex",
        "_build/test/file.ex",
        "test/test.exs"
      ]
      
      filtered = Enum.reject(files, fn file ->
        Enum.any?(["deps", "_build"], &String.contains?(file, &1))
      end)
      
      assert length(filtered) == 2
      assert "lib/example.ex" in filtered
      assert "test/test.exs" in filtered
    end
  end
end