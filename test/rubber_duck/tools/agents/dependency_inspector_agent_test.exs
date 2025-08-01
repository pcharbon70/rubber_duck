defmodule RubberDuck.Tools.Agents.DependencyInspectorAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.DependencyInspectorAgent
  
  setup do
    {:ok, agent} = DependencyInspectorAgent.start_link(id: "test_dependency_inspector")
    
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
          use GenServer
          import Enum
          alias MyApp.Utils
          
          def start_link(opts) do
            GenServer.start_link(__MODULE__, opts)
          end
        end
        """,
        analysis_type: "comprehensive",
        include_stdlib: false
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      result = DependencyInspectorAgent.ExecuteToolAction.run(%{params: params}, context)
      
      assert match?({:ok, _}, result)
    end
    
    test "analyze dependency tree action builds tree structure", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.AnalyzeDependencyTreeAction.run(
        %{
          root_path: ".",
          max_depth: 3,
          include_dev: false,
          include_test: false,
          visualization_format: :tree
        },
        context
      )
      
      assert result.root_path == "."
      assert result.tree_depth == 3
      assert Map.has_key?(result, :tree_structure)
      assert Map.has_key?(result, :analysis)
      assert Map.has_key?(result, :visualization)
      
      analysis = result.analysis
      assert Map.has_key?(analysis, :node_count)
      assert Map.has_key?(analysis, :edge_count)
      assert Map.has_key?(analysis, :dependency_types)
    end
    
    test "check circular dependencies action detects cycles", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CheckCircularDependenciesAction.run(
        %{
          paths: ["lib"],
          include_transitive: true,
          max_cycle_length: 10
        },
        context
      )
      
      assert result.paths_analyzed == ["lib"]
      assert result.total_modules >= 0
      assert result.total_dependencies >= 0
      assert is_boolean(result.circular_dependencies_found)
      assert is_list(result.cycles)
      assert Map.has_key?(result, :cycle_analysis)
      assert is_list(result.recommendations)
    end
    
    test "find unused dependencies action identifies unused deps", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.FindUnusedDependenciesAction.run(
        %{
          project_path: ".",
          check_dev_deps: false,
          check_test_deps: false,
          confidence_threshold: 0.8
        },
        context
      )
      
      assert result.project_path == "."
      assert result.total_declared >= 0
      assert result.total_used >= 0
      assert is_list(result.potentially_unused)
      assert result.unused_count >= 0
      assert is_list(result.recommendations)
      assert Map.has_key?(result, :confidence_scores)
    end
    
    test "monitor dependency health action checks health metrics", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.MonitorDependencyHealthAction.run(
        %{
          project_path: ".",
          check_outdated: true,
          check_security: true,
          check_licenses: true,
          security_source: :built_in
        },
        context
      )
      
      assert Map.has_key?(result, :outdated)
      assert Map.has_key?(result, :security)
      assert Map.has_key?(result, :licenses)
      assert Map.has_key?(result, :overall_health)
      
      health = result.overall_health
      assert is_float(health.score)
      assert health.rating in [:excellent, :good, :fair, :poor, :critical]
      assert is_binary(health.summary)
    end
    
    test "compare dependencies action compares dependency sets", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CompareDependenciesAction.run(
        %{
          source_path: "lib",
          target_path: "test",
          comparison_type: :versions,
          include_transitive: false
        },
        context
      )
      
      assert result.source_path == "lib"
      assert result.target_path == "test"
      assert result.comparison_type == :versions
      
      comparison = result.comparison
      assert Map.has_key?(comparison, :added)
      assert Map.has_key?(comparison, :removed)
      assert Map.has_key?(comparison, :unchanged)
      assert Map.has_key?(comparison, :statistics)
      
      assert Map.has_key?(result, :summary)
      assert is_list(result.recommendations)
    end
  end
  
  describe "signal handling" do
    test "analyze_dependencies signal triggers ExecuteToolAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_dependencies",
        "data" => %{
          "file_path" => "lib",
          "analysis_type" => "comprehensive",
          "include_stdlib" => false
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DependencyInspectorAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "check_circular_dependencies signal triggers CheckCircularDependenciesAction", %{agent: agent} do
      signal = %{
        "type" => "check_circular_dependencies",
        "data" => %{
          "paths" => ["lib", "test"],
          "include_transitive" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DependencyInspectorAgent.handle_signal(state, signal)
      
      assert true
    end
    
    test "monitor_dependency_health signal triggers MonitorDependencyHealthAction", %{agent: agent} do
      signal = %{
        "type" => "monitor_dependency_health",
        "data" => %{
          "project_path" => ".",
          "check_security" => true
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = DependencyInspectorAgent.handle_signal(state, signal)
      
      assert true
    end
  end
  
  describe "state management" do
    test "tracks analysis history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful analysis result
      analysis_result = %{
        summary: %{
          total_dependencies: 25,
          external_count: 15,
          internal_count: 10,
          hex_deps_count: 12
        },
        external: %{hex: [], erlang: [], elixir: []},
        internal: [],
        warnings: ["Found 2 unknown module references"]
      }
      
      {:ok, updated} = DependencyInspectorAgent.handle_action_result(
        state,
        DependencyInspectorAgent.ExecuteToolAction,
        {:ok, analysis_result},
        %{}
      )
      
      assert length(updated.state.analysis_history) == 1
      analysis_record = hd(updated.state.analysis_history)
      assert analysis_record.external_count == 15
      assert analysis_record.internal_count == 10
      assert analysis_record.warnings == ["Found 2 unknown module references"]
    end
    
    test "updates known dependencies after analysis", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      analysis_result = %{
        summary: %{total_dependencies: 5},
        external: %{
          hex: [{Phoenix, "phoenix"}, {Ecto, "ecto"}],
          erlang: [],
          elixir: []
        },
        internal: [MyApp.Utils, MyApp.Core]
      }
      
      {:ok, updated} = DependencyInspectorAgent.handle_action_result(
        state,
        DependencyInspectorAgent.ExecuteToolAction,
        {:ok, analysis_result},
        %{}
      )
      
      known = updated.state.known_dependencies
      assert known.external == analysis_result.external
      assert known.internal == analysis_result.internal
      assert known.last_updated != nil
    end
    
    test "updates health metrics after health monitoring", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      health_result = %{
        overall_health: %{score: 85.0, rating: :good, summary: "Minor issues found"},
        outdated: %{outdated_count: 3},
        security: %{vulnerabilities_found: 1},
        licenses: %{compliant: true}
      }
      
      {:ok, updated} = DependencyInspectorAgent.handle_action_result(
        state,
        DependencyInspectorAgent.MonitorDependencyHealthAction,
        {:ok, health_result},
        %{}
      )
      
      metrics = updated.state.health_metrics
      assert metrics.health_score == 85.0
      assert metrics.outdated_count == 3
      assert metrics.security_issues == 1
    end
  end
  
  describe "agent initialization" do
    test "starts with default monitoring configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      config = state.state.monitoring_config
      assert config.check_outdated == true
      assert config.check_security == true
      assert config.check_licenses == true
      assert "MIT" in config.allowed_licenses
      assert config.max_dependency_depth == 3
    end
    
    test "starts with default dependency policies", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      policies = state.state.dependency_policies
      assert policies["banned_packages"] == []
      assert policies["required_packages"] == []
      assert Map.has_key?(policies["layer_rules"], "web")
      assert "phoenix" in policies["layer_rules"]["web"]
    end
    
    test "starts with empty analysis history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      assert state.state.analysis_history == []
      assert state.state.analysis_cache == %{}
      assert state.state.active_analyses == %{}
    end
    
    test "starts with initial health metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      metrics = state.state.health_metrics
      assert metrics.total_dependencies == 0
      assert metrics.outdated_count == 0
      assert metrics.security_issues == 0
      assert metrics.unused_count == 0
      assert metrics.circular_count == 0
      assert metrics.health_score == 100.0
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = DependencyInspectorAgent.additional_actions()
      
      assert length(actions) == 6
      assert DependencyInspectorAgent.ExecuteToolAction in actions
      assert DependencyInspectorAgent.AnalyzeDependencyTreeAction in actions
      assert DependencyInspectorAgent.CheckCircularDependenciesAction in actions
      assert DependencyInspectorAgent.FindUnusedDependenciesAction in actions
      assert DependencyInspectorAgent.MonitorDependencyHealthAction in actions
      assert DependencyInspectorAgent.CompareDependenciesAction in actions
    end
  end
  
  describe "dependency tree analysis" do
    test "builds tree with correct depth calculation", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.AnalyzeDependencyTreeAction.run(
        %{root_path: ".", max_depth: 2, visualization_format: :tree},
        context
      )
      
      tree = result.tree_structure
      assert Map.has_key?(tree, :root)
      assert Map.has_key?(tree, :depth)
      assert Map.has_key?(tree, :total_dependencies)
      
      # Tree depth should not exceed max_depth
      assert tree.depth <= 2
    end
    
    test "generates different visualization formats", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      # Test tree format
      {:ok, tree_result} = DependencyInspectorAgent.AnalyzeDependencyTreeAction.run(
        %{root_path: ".", visualization_format: :tree},
        context
      )
      assert tree_result.visualization.format == :tree
      
      # Test graph format
      {:ok, graph_result} = DependencyInspectorAgent.AnalyzeDependencyTreeAction.run(
        %{root_path: ".", visualization_format: :graph},
        context
      )
      assert graph_result.visualization.format == :graph
      assert Map.has_key?(graph_result.visualization, :nodes)
      assert Map.has_key?(graph_result.visualization, :edges)
      
      # Test matrix format
      {:ok, matrix_result} = DependencyInspectorAgent.AnalyzeDependencyTreeAction.run(
        %{root_path: ".", visualization_format: :matrix},
        context
      )
      assert matrix_result.visualization.format == :matrix
      assert Map.has_key?(matrix_result.visualization, :matrix)
    end
  end
  
  describe "circular dependency detection" do
    test "handles empty dependency graph gracefully", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CheckCircularDependenciesAction.run(
        %{paths: ["nonexistent_path"], max_cycle_length: 5},
        context
      )
      
      assert result.circular_dependencies_found == false
      assert result.cycles == []
    end
    
    test "categorizes cycles by length", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CheckCircularDependenciesAction.run(
        %{paths: ["lib"], max_cycle_length: 10},
        context
      )
      
      if result.circular_dependencies_found do
        analysis = result.cycle_analysis
        assert Map.has_key?(analysis, :total_cycles)
        assert Map.has_key?(analysis, :cycle_categories)
        
        categories = analysis.cycle_categories
        assert is_map(categories)
        # Categories should be one of: direct_mutual, small_cycle, medium_cycle, large_cycle
      end
    end
  end
  
  describe "unused dependency detection" do
    test "calculates confidence scores for unused dependencies", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.FindUnusedDependenciesAction.run(
        %{project_path: ".", confidence_threshold: 0.7},
        context
      )
      
      if result.unused_count > 0 do
        scores = result.confidence_scores
        assert is_map(scores)
        
        # All confidence scores should be floats between 0 and 1
        Enum.each(scores, fn {_dep, score} ->
          assert is_float(score)
          assert score >= 0.0 and score <= 1.0
        end)
      end
    end
  end
  
  describe "health monitoring" do
    test "calculates health score based on multiple factors", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.MonitorDependencyHealthAction.run(
        %{
          project_path: ".",
          check_outdated: true,
          check_security: true,
          check_licenses: true
        },
        context
      )
      
      health = result.overall_health
      assert health.score >= 0.0 and health.score <= 100.0
      
      # Rating should correspond to score
      assert case health.rating do
        :excellent -> health.score >= 90
        :good -> health.score >= 80 and health.score < 90
        :fair -> health.score >= 70 and health.score < 80
        :poor -> health.score >= 60 and health.score < 70
        :critical -> health.score < 60
      end
    end
    
    test "generates security recommendations for vulnerabilities", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.MonitorDependencyHealthAction.run(
        %{project_path: ".", check_security: true, security_source: :built_in},
        context
      )
      
      if result.security.vulnerabilities_found > 0 do
        assert length(result.security.recommendations) > 0
        
        # Should have urgent recommendation for critical vulnerabilities
        if result.security.critical_count > 0 do
          urgent_rec = Enum.find(result.security.recommendations, fn rec ->
            String.contains?(rec, "URGENT")
          end)
          assert urgent_rec != nil
        end
      end
    end
  end
  
  describe "dependency comparison" do
    test "calculates change statistics correctly", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CompareDependenciesAction.run(
        %{
          source_path: "lib",
          target_path: "lib",
          comparison_type: :versions
        },
        context
      )
      
      stats = result.comparison.statistics
      assert is_integer(stats.source_total)
      assert is_integer(stats.target_total)
      assert is_float(stats.change_percentage)
      assert stats.change_percentage >= 0.0
    end
    
    test "assesses change impact levels", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = DependencyInspectorAgent.CompareDependenciesAction.run(
        %{source_path: "lib", target_path: "test"},
        context
      )
      
      summary = result.summary
      assert summary.change_impact in [:none, :minor, :moderate, :major]
    end
  end
end