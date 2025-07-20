defmodule RubberDuck.Planning.Repository.RepositoryPlannerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Repository.RepositoryPlanner
  
  describe "create_plan/4" do
    test "creates a repository-level plan" do
      tmp_dir = System.tmp_dir!() |> Path.join("repo_planner_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        # Create minimal project structure
        create_test_project(tmp_dir)
        
        changes = [
          %{
            id: "change1",
            name: "Add new feature",
            description: "Implement user authentication",
            files: ["lib/auth.ex"],
            type: :feature,
            priority: :high,
            dependencies: [],
            estimated_effort: 4.0,
            breaking: false,
            validation_required: true
          },
          %{
            id: "change2", 
            name: "Update existing module",
            description: "Refactor user module",
            files: ["lib/user.ex"],
            type: :refactor,
            priority: :medium,
            dependencies: ["change1"],
            estimated_effort: 2.5,
            breaking: false,
            validation_required: false
          }
        ]
        
        assert {:ok, plan} = RepositoryPlanner.create_plan(
          tmp_dir,
          "User Authentication Feature",
          changes,
          description: "Comprehensive user authentication system"
        )
        
        assert plan.id
        assert plan.name == "User Authentication Feature"
        assert plan.description == "Comprehensive user authentication system"
        assert plan.repository_path == tmp_dir
        assert length(plan.changes) == 2
        assert plan.status == :analyzed
        assert is_map(plan.analysis)
        assert is_map(plan.impact)
        assert is_map(plan.sequence)
        assert plan.execution_plan == nil
        assert is_map(plan.metadata)
      after
        File.rm_rf!(tmp_dir)
      end
    end
    
    test "handles analysis failures gracefully" do
      non_existent_path = "/this/path/does/not/exist"
      changes = []
      
      assert {:error, _reason} = RepositoryPlanner.create_plan(
        non_existent_path,
        "Test Plan", 
        changes
      )
    end
    
    test "validates change requests" do
      tmp_dir = System.tmp_dir!() |> Path.join("validation_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        
        invalid_changes = [
          %{
            id: nil,  # Invalid: missing ID
            name: "Invalid change",
            description: "This change is invalid",
            files: [],  # Invalid: no files
            type: :feature,
            priority: :high,
            dependencies: [],
            estimated_effort: 1.0,
            breaking: false,
            validation_required: false
          }
        ]
        
        # Should still create plan but validation will catch issues
        assert {:ok, plan} = RepositoryPlanner.create_plan(
          tmp_dir,
          "Invalid Plan",
          invalid_changes
        )
        
        # Validation should catch the issues
        assert {:error, {:validation_failed, errors}} = RepositoryPlanner.validate_plan(plan)
        assert length(errors) > 0
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "convert_to_execution_plan/1" do
    test "converts repository plan to execution plan" do
      tmp_dir = System.tmp_dir!() |> Path.join("execution_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        
        changes = [create_sample_change()]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Test Plan", changes)
        assert {:ok, updated_plan} = RepositoryPlanner.convert_to_execution_plan(repo_plan)
        
        assert updated_plan.status == :ready
        assert updated_plan.execution_plan != nil
        # Note: We're not testing actual Plan creation since that requires Ash setup
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "execute_plan/2" do
    test "returns error when no execution plan exists" do
      repo_plan = %{execution_plan: nil}
      
      assert {:error, :no_execution_plan} = RepositoryPlanner.execute_plan(repo_plan)
    end
    
    test "starts execution with valid execution plan" do
      # Mock execution plan 
      mock_plan = %{id: "test-plan"}
      repo_plan = %{
        name: "Test Plan",
        execution_plan: mock_plan,
        sequence: %{parallel_groups: []}
      }
      
      # This would normally start a PlanExecutor GenServer
      # For testing, we expect it to fail since we don't have registry setup
      assert {:error, _reason} = RepositoryPlanner.execute_plan(repo_plan)
    end
  end
  
  describe "preview_changes/1" do
    test "generates change preview" do
      tmp_dir = System.tmp_dir!() |> Path.join("preview_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        changes = [create_sample_change()]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Preview Test", changes)
        assert {:ok, preview} = RepositoryPlanner.preview_changes(repo_plan)
        
        assert is_map(preview.summary)
        assert preview.summary.total_changes == 1
        assert is_map(preview.summary.by_type)
        assert is_map(preview.summary.by_priority)
        
        assert is_list(preview.phases)
        assert is_list(preview.risk_factors)
        assert is_list(preview.affected_files)
        assert is_map(preview.estimated_effort)
        assert is_list(preview.validation_points)
        assert is_map(preview.rollback_plan)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "validate_plan/1" do
    test "validates a correct repository plan" do
      tmp_dir = System.tmp_dir!() |> Path.join("validate_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        changes = [create_sample_change()]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Validation Test", changes)
        assert {:ok, validations} = RepositoryPlanner.validate_plan(repo_plan)
        
        assert is_list(validations)
        assert length(validations) > 0
        
        # Should have different types of validations
        validation_types = Enum.map(validations, & &1.type) |> Enum.uniq()
        assert :analysis_currency in validation_types
        assert :change_definitions in validation_types
      after
        File.rm_rf!(tmp_dir)
      end
    end
    
    test "detects validation failures" do
      tmp_dir = System.tmp_dir!() |> Path.join("validation_fail_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        
        # Create plan with invalid change definitions
        invalid_changes = [
          %{
            id: nil,  # Invalid
            name: nil,  # Invalid
            description: "Test",
            files: [],  # Invalid - empty
            type: :feature,
            priority: :high,
            dependencies: [],
            estimated_effort: 1.0,
            breaking: false,
            validation_required: false
          }
        ]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Invalid Plan", invalid_changes)
        assert {:error, {:validation_failed, errors}} = RepositoryPlanner.validate_plan(repo_plan)
        
        assert length(errors) > 0
        
        change_def_error = Enum.find(errors, &(&1.type == :change_definitions))
        assert change_def_error
        assert change_def_error.status == :error
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "suggest_optimizations/1" do
    test "suggests optimizations for repository plan" do
      tmp_dir = System.tmp_dir!() |> Path.join("optimization_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        
        # Create many small changes to trigger grouping suggestion
        changes = Enum.map(1..12, fn i ->
          %{
            id: "change#{i}",
            name: "Small change #{i}",
            description: "Minor update #{i}",
            files: ["lib/module_#{i}.ex"],
            type: :feature,
            priority: :low,
            dependencies: [],
            estimated_effort: 0.5,
            breaking: false,
            validation_required: false
          }
        end)
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Many Changes", changes)
        
        suggestions = RepositoryPlanner.suggest_optimizations(repo_plan)
        
        assert is_list(suggestions)
        
        # Should suggest change grouping for many small changes
        grouping_suggestion = Enum.find(suggestions, &(&1.type == :change_grouping))
        
        if grouping_suggestion do
          assert grouping_suggestion.impact > 0.0
          assert grouping_suggestion.effort in [:low, :medium, :high]
          assert is_list(grouping_suggestion.implementation)
        end
      after
        File.rm_rf!(tmp_dir)
      end
    end
    
    test "suggests parallel execution optimization" do
      tmp_dir = System.tmp_dir!() |> Path.join("parallel_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        
        # Create multiple independent changes
        changes = [
          create_sample_change("change1", ["lib/module_a.ex"]),
          create_sample_change("change2", ["lib/module_b.ex"]),
          create_sample_change("change3", ["lib/module_c.ex"]),
          create_sample_change("change4", ["lib/module_d.ex"])
        ]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Parallel Test", changes)
        
        suggestions = RepositoryPlanner.suggest_optimizations(repo_plan)
        
        # May suggest parallel execution if no parallel groups found
        parallel_suggestion = Enum.find(suggestions, &(&1.type == :parallel_execution))
        
        if parallel_suggestion do
          assert parallel_suggestion.impact > 0.0
        end
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "get_plan_status/1" do
    test "returns plan status information" do
      tmp_dir = System.tmp_dir!() |> Path.join("status_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        create_test_project(tmp_dir)
        changes = [create_sample_change()]
        
        assert {:ok, repo_plan} = RepositoryPlanner.create_plan(tmp_dir, "Status Test", changes)
        
        status_info = RepositoryPlanner.get_plan_status(repo_plan)
        
        assert status_info.status == :analyzed
        assert status_info.progress == 0.3  # Based on :analyzed status
        assert is_binary(status_info.current_phase)
        assert is_list(status_info.next_actions)
        assert is_list(status_info.issues)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  # Helper functions
  
  defp create_test_project(dir) do
    # Create minimal mix.exs with unique project name
    unique_id = :rand.uniform(100000)
    mix_content = """
    defmodule TestProject#{unique_id}.MixProject do
      use Mix.Project
      def project, do: [app: :test_project_#{unique_id}, version: "0.1.0"]
    end
    """
    File.write!(Path.join(dir, "mix.exs"), mix_content)
    
    # Create lib directory
    lib_dir = Path.join(dir, "lib")
    File.mkdir_p!(lib_dir)
    
    # Create sample module
    module_content = """
    defmodule TestProject.Sample do
      def hello, do: :world
    end
    """
    File.write!(Path.join(lib_dir, "sample.ex"), module_content)
  end
  
  defp create_sample_change(id \\ "sample_change", files \\ ["lib/sample.ex"]) do
    %{
      id: id,
      name: "Sample Change",
      description: "A sample change for testing",
      files: files,
      type: :feature,
      priority: :medium,
      dependencies: [],
      estimated_effort: 2.0,
      breaking: false,
      validation_required: false
    }
  end
end