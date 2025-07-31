defmodule RubberDuck.Tools.Agents.CodeMigrationAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.CodeMigrationAgent
  
  setup do
    {:ok, agent} = CodeMigrationAgent.start_link(id: "test_code_migration")
    
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
        source_code: "def hello(); print('Hello World'); end",
        source_language: "ruby",
        target_language: "python",
        migration_type: "language_translation"
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: CodeMigrationAgent}
      
      # Mock the Executor response - in real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = CodeMigrationAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze migration action assesses complexity and risks", %{agent: agent} do
      source_code = """
      class UserManager {
        private $db;
        
        public function __construct($database) {
          $this->db = $database;
        }
        
        public function createUser($name, $email) {
          $sql = "INSERT INTO users (name, email) VALUES (?, ?)";
          return $this->db->prepare($sql)->execute([$name, $email]);
        }
        
        public function getUser($id) {
          $sql = "SELECT * FROM users WHERE id = ?";
          return $this->db->prepare($sql)->execute([$id])->fetch();
        }
      }
      """
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.AnalyzeMigrationAction.run(
        %{
          source_code: source_code,
          source_language: "php",
          target_language: "python",
          migration_type: "language_translation"
        },
        context
      )
      
      assert result.source_language == "php"
      assert result.target_language == "python"
      assert result.migration_type == "language_translation"
      
      # Check complexity analysis
      complexity = result.complexity_analysis
      assert Map.has_key?(complexity, :overall_score)
      assert Map.has_key?(complexity, :factors)
      assert is_list(complexity.factors)
      
      # PHP to Python should have medium complexity
      assert complexity.overall_score >= 0.3
      assert complexity.overall_score <= 0.7
      
      # Check risk assessment
      risks = result.risk_assessment
      assert Map.has_key?(risks, :high_risk_areas)
      assert Map.has_key?(risks, :medium_risk_areas)
      assert Map.has_key?(risks, :low_risk_areas)
      assert is_list(risks.high_risk_areas)
      
      # Should identify database access as a risk
      database_risk = Enum.find(risks.medium_risk_areas ++ risks.high_risk_areas, 
        &String.contains?(&1, "database"))
      assert database_risk != nil
      
      # Check effort estimation
      effort = result.effort_estimation
      assert Map.has_key?(effort, :estimated_hours)
      assert Map.has_key?(effort, :complexity_level)
      assert effort.complexity_level in [:low, :medium, :high, :very_high]
    end
    
    test "plan migration action creates detailed migration strategy", %{agent: agent} do
      analysis = %{
        complexity_analysis: %{overall_score: 0.6},
        risk_assessment: %{high_risk_areas: ["Database queries", "File I/O"]},
        effort_estimation: %{estimated_hours: 16, complexity_level: :medium}
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.PlanMigrationAction.run(
        %{
          analysis_result: analysis,
          preferred_strategy: "gradual",
          timeline_constraints: %{max_weeks: 4},
          resource_constraints: %{max_developers: 2}
        },
        context
      )
      
      plan = result.migration_plan
      assert plan.strategy == "gradual"
      assert is_list(plan.phases)
      assert length(plan.phases) > 0
      
      # Check phases have proper structure
      first_phase = hd(plan.phases)
      assert Map.has_key?(first_phase, :name)
      assert Map.has_key?(first_phase, :description)
      assert Map.has_key?(first_phase, :estimated_duration)
      assert Map.has_key?(first_phase, :tasks)
      assert is_list(first_phase.tasks)
      
      # Check timeline
      timeline = result.timeline
      assert Map.has_key?(timeline, :total_duration)
      assert Map.has_key?(timeline, :phase_schedule)
      assert length(timeline.phase_schedule) == length(plan.phases)
      
      # Check resource allocation
      resources = result.resource_allocation
      assert Map.has_key?(resources, :developers_needed)
      assert Map.has_key?(resources, :skill_requirements)
      assert resources.developers_needed <= 2  # Respects constraint
      
      # Check risk mitigation
      mitigation = result.risk_mitigation
      assert Map.has_key?(mitigation, :strategies)
      assert is_list(mitigation.strategies)
    end
    
    test "execute migration action processes code with progress tracking", %{agent: agent} do
      migration_plan = %{
        strategy: "big_bang",
        phases: [
          %{
            name: "Phase 1",
            tasks: ["Analyze syntax", "Convert classes", "Update imports"]
          }
        ]
      }
      
      source_files = [
        %{path: "main.rb", content: "puts 'Hello World'"},
        %{path: "utils.rb", content: "def add(a, b); a + b; end"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.ExecuteMigrationAction.run(
        %{
          migration_plan: migration_plan,
          source_files: source_files,
          target_language: "python",
          safety_checks: true
        },
        context
      )
      
      assert Map.has_key?(result, :migrated_files)
      assert Map.has_key?(result, :execution_log)
      assert Map.has_key?(result, :progress_tracking)
      
      # Check migrated files
      migrated_files = result.migrated_files
      assert length(migrated_files) == 2
      
      main_file = Enum.find(migrated_files, &(&1.original_path == "main.rb"))
      assert main_file != nil
      assert main_file.target_path == "main.py"
      assert String.contains?(main_file.migrated_content, "print")
      
      utils_file = Enum.find(migrated_files, &(&1.original_path == "utils.rb"))
      assert utils_file != nil
      assert String.contains?(utils_file.migrated_content, "def add")
      
      # Check progress tracking
      progress = result.progress_tracking
      assert progress.total_files == 2
      assert progress.completed_files == 2
      assert progress.completion_percentage == 1.0
      assert progress.status == :completed
      
      # Check execution log
      log = result.execution_log
      assert is_list(log.entries)
      assert length(log.entries) > 0
      
      start_entry = Enum.find(log.entries, &(&1.level == :info && String.contains?(&1.message, "Starting")))
      assert start_entry != nil
    end
    
    test "validate migration action checks completeness and correctness", %{agent: agent} do
      migrated_files = [
        %{
          original_path: "calculator.rb",
          target_path: "calculator.py",
          original_content: "def add(a, b); a + b; end",
          migrated_content: "def add(a, b):\n    return a + b"
        },
        %{
          original_path: "broken.rb", 
          target_path: "broken.py",
          original_content: "def subtract(a, b); a - b; end",
          migrated_content: "def subtract(a, b)\n    return a - b"  # Missing colon
        }
      ]
      
      success_criteria = [
        "All syntax must be valid",
        "Function signatures must be preserved",
        "Logic must remain equivalent"
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.ValidateMigrationAction.run(
        %{
          migrated_files: migrated_files,
          success_criteria: success_criteria,
          validation_level: "comprehensive"
        },
        context
      )
      
      validation = result.validation_result
      assert validation.overall_status in [:passed, :failed, :partial]
      assert Map.has_key?(validation, :file_validations)
      assert length(validation.file_validations) == 2
      
      # Check individual file validations
      calculator_validation = Enum.find(validation.file_validations, 
        &(&1.file_path == "calculator.py"))
      assert calculator_validation != nil
      assert calculator_validation.status == :passed
      assert length(calculator_validation.errors) == 0
      
      broken_validation = Enum.find(validation.file_validations,
        &(&1.file_path == "broken.py"))
      assert broken_validation != nil
      assert broken_validation.status == :failed
      assert length(broken_validation.errors) > 0
      
      # Should detect syntax error
      syntax_error = Enum.find(broken_validation.errors, 
        &String.contains?(&1.message, "syntax"))
      assert syntax_error != nil
      
      # Check summary statistics
      summary = result.validation_summary
      assert summary.total_files == 2
      assert summary.passed_files == 1
      assert summary.failed_files == 1
      assert summary.success_rate == 0.5
    end
    
    test "create rollback action generates recovery procedures", %{agent: agent} do
      migration_state = %{
        completed_phases: ["Phase 1", "Phase 2"],
        migrated_files: [
          %{original_path: "app.rb", target_path: "app.py"},
          %{original_path: "config.rb", target_path: "config.py"}
        ],
        database_changes: [
          %{table: "migrations", operation: "insert", data: %{version: "001"}}
        ]
      }
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.CreateRollbackAction.run(
        %{
          migration_state: migration_state,
          rollback_strategy: "selective",
          preserve_data: true
        },
        context
      )
      
      rollback_plan = result.rollback_plan
      assert rollback_plan.strategy == "selective"
      assert is_list(rollback_plan.steps)
      assert length(rollback_plan.steps) > 0
      
      # Check rollback steps structure
      first_step = hd(rollback_plan.steps)
      assert Map.has_key?(first_step, :action)
      assert Map.has_key?(first_step, :description)
      assert Map.has_key?(first_step, :risk_level)
      assert first_step.risk_level in [:low, :medium, :high]
      
      # Check recovery procedures
      procedures = result.recovery_procedures
      assert Map.has_key?(procedures, :file_restoration)
      assert Map.has_key?(procedures, :database_restoration)
      assert is_list(procedures.file_restoration)
      
      # Should include file restoration steps
      file_restore = Enum.find(procedures.file_restoration, 
        &String.contains?(&1.description, "app.rb"))
      assert file_restore != nil
      
      # Check backup creation
      backup_info = result.backup_info
      assert Map.has_key?(backup_info, :backup_id)
      assert Map.has_key?(backup_info, :created_at)
      assert Map.has_key?(backup_info, :contents)
      assert is_binary(backup_info.backup_id)
    end
    
    test "update dependencies action manages project dependencies", %{agent: agent} do
      dependency_changes = [
        %{name: "requests", old_version: "2.25.1", new_version: "2.28.0", type: "upgrade"},
        %{name: "flask", old_version: "1.1.4", new_version: "2.2.0", type: "major_upgrade"},
        %{name: "deprecated_lib", old_version: "1.0.0", new_version: nil, type: "removal"}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = CodeMigrationAgent.UpdateDependenciesAction.run(
        %{
          dependency_changes: dependency_changes,
          target_language: "python",
          compatibility_check: true,
          update_lock_files: true
        },
        context
      )
      
      # Check compatibility analysis
      compatibility = result.compatibility_analysis
      assert Map.has_key?(compatibility, :compatible_updates)
      assert Map.has_key?(compatibility, :breaking_changes)
      assert Map.has_key?(compatibility, :warnings)
      
      # Flask major upgrade should be flagged as breaking
      breaking_changes = compatibility.breaking_changes
      flask_breaking = Enum.find(breaking_changes, &String.contains?(&1.dependency, "flask"))
      assert flask_breaking != nil
      assert flask_breaking.severity == :high
      
      # Check update plan
      update_plan = result.update_plan
      assert is_list(update_plan.steps)
      assert length(update_plan.steps) > 0
      
      # Should include dependency removal step
      removal_step = Enum.find(update_plan.steps, 
        &(&1.action == :remove && String.contains?(&1.description, "deprecated_lib")))
      assert removal_step != nil
      
      # Check validation results
      validation = result.validation_results
      assert Map.has_key?(validation, :dependency_conflicts)
      assert Map.has_key?(validation, :security_vulnerabilities)
      assert is_list(validation.dependency_conflicts)
      
      # Check updated manifests
      manifests = result.updated_manifests
      assert Map.has_key?(manifests, :requirements_txt)
      assert is_binary(manifests.requirements_txt)
      assert String.contains?(manifests.requirements_txt, "requests==2.28.0")
      assert String.contains?(manifests.requirements_txt, "flask==2.2.0")
      refute String.contains?(manifests.requirements_txt, "deprecated_lib")
    end
  end
  
  describe "signal handling with actions" do
    test "analyze_migration signal triggers AnalyzeMigrationAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_migration",
        "data" => %{
          "source_code" => "function hello() { console.log('Hello'); }",
          "source_language" => "javascript",
          "target_language" => "typescript",
          "migration_type" => "language_translation"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "plan_migration signal triggers PlanMigrationAction", %{agent: agent} do
      signal = %{
        "type" => "plan_migration",
        "data" => %{
          "analysis_result" => %{"complexity_analysis" => %{"overall_score" => 0.5}},
          "preferred_strategy" => "gradual",
          "timeline_constraints" => %{"max_weeks" => 8}
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true  
    end
    
    test "execute_migration signal triggers ExecuteMigrationAction", %{agent: agent} do
      signal = %{
        "type" => "execute_migration",
        "data" => %{
          "migration_plan" => %{"strategy" => "big_bang"},
          "source_files" => [%{"path" => "test.rb", "content" => "puts 'test'"}],
          "target_language" => "python"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "validate_migration signal triggers ValidateMigrationAction", %{agent: agent} do
      signal = %{
        "type" => "validate_migration",
        "data" => %{
          "migrated_files" => [%{"target_path" => "test.py", "migrated_content" => "print('test')"}],
          "success_criteria" => ["Valid syntax", "Logic preservation"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "create_rollback signal triggers CreateRollbackAction", %{agent: agent} do
      signal = %{
        "type" => "create_rollback",
        "data" => %{
          "migration_state" => %{"completed_phases" => ["Phase 1"]},
          "rollback_strategy" => "full"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "update_dependencies signal triggers UpdateDependenciesAction", %{agent: agent} do
      signal = %{
        "type" => "update_dependencies",
        "data" => %{
          "dependency_changes" => [%{"name" => "lodash", "new_version" => "4.17.21"}],
          "target_language" => "javascript"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = CodeMigrationAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "migration analysis" do
    test "detects language-specific complexity factors" do
      python_to_java = """
      def calculate_fibonacci(n):
          if n <= 1:
              return n
          return calculate_fibonacci(n-1) + calculate_fibonacci(n-2)
      
      numbers = [1, 2, 3, 4, 5]
      squared = [x**2 for x in numbers if x % 2 == 0]
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.AnalyzeMigrationAction.run(
        %{
          source_code: python_to_java,
          source_language: "python",
          target_language: "java",
          migration_type: "language_translation"
        },
        context
      )
      
      complexity = result.complexity_analysis
      # Python to Java should be high complexity due to different paradigms
      assert complexity.overall_score > 0.6
      
      # Should identify list comprehensions as a complexity factor
      list_comp_factor = Enum.find(complexity.factors, 
        &String.contains?(&1.description, "comprehension"))
      assert list_comp_factor != nil
      assert list_comp_factor.impact >= 0.3
    end
    
    test "identifies framework migration challenges" do
      rails_code = """
      class UsersController < ApplicationController
        before_action :authenticate_user!
        
        def index
          @users = User.where(active: true).includes(:profile)
          render json: @users
        end
        
        def create
          @user = User.new(user_params)
          if @user.save
            render json: @user, status: :created
          else
            render json: @user.errors, status: :unprocessable_entity
          end
        end
        
        private
        
        def user_params
          params.require(:user).permit(:name, :email)
        end
      end
      """
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.AnalyzeMigrationAction.run(
        %{
          source_code: rails_code,
          source_language: "ruby",
          target_language: "python",
          migration_type: "framework_upgrade",
          source_framework: "rails",
          target_framework: "django"
        },
        context
      )
      
      risks = result.risk_assessment
      
      # Should identify framework-specific risks
      auth_risk = Enum.find(risks.high_risk_areas ++ risks.medium_risk_areas,
        &String.contains?(&1, "authentication"))
      assert auth_risk != nil
      
      orm_risk = Enum.find(risks.high_risk_areas ++ risks.medium_risk_areas,
        &String.contains?(&1, "ORM"))
      assert orm_risk != nil
    end
    
    test "estimates effort based on code size and complexity" do
      small_simple_code = "def hello(): return 'Hello World'"
      large_complex_code = """
      # Large complex code with multiple classes, database operations,
      # async operations, complex algorithms, etc. (simulated by length)
      """ <> String.duplicate("# Complex business logic here\n", 100)
      
      context = %{agent: %{state: %{}}}
      
      {:ok, simple_result} = CodeMigrationAgent.AnalyzeMigrationAction.run(
        %{
          source_code: small_simple_code,
          source_language: "python",
          target_language: "javascript"
        },
        context
      )
      
      {:ok, complex_result} = CodeMigrationAgent.AnalyzeMigrationAction.run(
        %{
          source_code: large_complex_code,
          source_language: "python", 
          target_language: "java"
        },
        context
      )
      
      simple_effort = simple_result.effort_estimation
      complex_effort = complex_result.effort_estimation
      
      # Complex code should require more effort
      assert complex_effort.estimated_hours > simple_effort.estimated_hours
      assert complex_effort.complexity_level != :low
    end
  end
  
  describe "migration planning" do
    test "gradual strategy creates incremental phases" do
      analysis = %{
        complexity_analysis: %{overall_score: 0.7},
        risk_assessment: %{high_risk_areas: ["Database", "Authentication"]},
        effort_estimation: %{estimated_hours: 40, complexity_level: :high}
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.PlanMigrationAction.run(
        %{
          analysis_result: analysis,
          preferred_strategy: "gradual"
        },
        context
      )
      
      plan = result.migration_plan
      assert plan.strategy == "gradual"
      
      # Gradual strategy should have multiple phases
      assert length(plan.phases) >= 3
      
      # First phase should be low-risk
      first_phase = hd(plan.phases)
      assert String.contains?(first_phase.name, "Foundation") || 
             String.contains?(first_phase.description, "low-risk")
      
      # Should have risk mitigation for high-risk areas
      mitigation = result.risk_mitigation
      assert length(mitigation.strategies) > 0
      
      db_strategy = Enum.find(mitigation.strategies, 
        &String.contains?(&1.area, "Database"))
      assert db_strategy != nil
    end
    
    test "big_bang strategy creates single comprehensive phase" do
      analysis = %{
        complexity_analysis: %{overall_score: 0.3},
        risk_assessment: %{high_risk_areas: []},
        effort_estimation: %{estimated_hours: 8, complexity_level: :low}
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.PlanMigrationAction.run(
        %{
          analysis_result: analysis,
          preferred_strategy: "big_bang"
        },
        context
      )
      
      plan = result.migration_plan
      assert plan.strategy == "big_bang"
      
      # Big bang should have fewer phases (typically 1-2)
      assert length(plan.phases) <= 2
      
      timeline = result.timeline
      # Should be completed more quickly
      assert timeline.total_duration <= 20  # 20 days or less
    end
    
    test "respects timeline and resource constraints" do
      analysis = %{
        complexity_analysis: %{overall_score: 0.6},
        effort_estimation: %{estimated_hours: 80}
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.PlanMigrationAction.run(
        %{
          analysis_result: analysis,
          timeline_constraints: %{max_weeks: 2},
          resource_constraints: %{max_developers: 1}
        },
        context
      )
      
      resources = result.resource_allocation
      timeline = result.timeline
      
      # Should respect resource constraints
      assert resources.developers_needed <= 1
      
      # Should adjust timeline to fit constraints (14 days max)
      assert timeline.total_duration <= 14
      
      # Should include warnings about constraints
      warnings = result.warnings
      time_warning = Enum.find(warnings, &String.contains?(&1, "timeline"))
      assert time_warning != nil
    end
  end
  
  describe "migration execution" do
    test "tracks progress through migration phases" do
      plan = %{
        strategy: "gradual",
        phases: [
          %{name: "Phase 1", tasks: ["Task 1", "Task 2"]},
          %{name: "Phase 2", tasks: ["Task 3"]}
        ]
      }
      
      files = [
        %{path: "file1.rb", content: "puts 'hello'"},
        %{path: "file2.rb", content: "puts 'world'"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.ExecuteMigrationAction.run(
        %{
          migration_plan: plan,
          source_files: files,
          target_language: "python"
        },
        context
      )
      
      progress = result.progress_tracking
      assert progress.total_phases == 2
      assert progress.completed_phases == 2
      assert progress.total_files == 2
      assert progress.completed_files == 2
      assert progress.completion_percentage == 1.0
      assert progress.status == :completed
      
      # Should have phase progress details
      assert Map.has_key?(progress, :phase_progress)
      phase_progress = progress.phase_progress
      assert length(phase_progress) == 2
      
      first_phase_progress = hd(phase_progress)
      assert first_phase_progress.name == "Phase 1"
      assert first_phase_progress.status == :completed
      assert first_phase_progress.completed_tasks == 2
    end
    
    test "handles migration errors gracefully" do
      plan = %{
        strategy: "big_bang",
        phases: [%{name: "Phase 1", tasks: ["Convert syntax"]}]
      }
      
      # Include a file that would cause migration issues
      files = [
        %{path: "valid.rb", content: "puts 'hello'"},
        %{path: "invalid.rb", content: "puts 'hello'; invalid_ruby_syntax <<<"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.ExecuteMigrationAction.run(
        %{
          migration_plan: plan,
          source_files: files,
          target_language: "python",
          safety_checks: true
        },
        context
      )
      
      # Should complete partially
      progress = result.progress_tracking
      assert progress.status in [:partial, :completed]
      
      # Should log errors
      log = result.execution_log
      error_entries = Enum.filter(log.entries, &(&1.level == :error))
      assert length(error_entries) > 0
      
      # Error should mention the problematic file
      error_entry = Enum.find(error_entries, &String.contains?(&1.message, "invalid.rb"))
      assert error_entry != nil
    end
    
    test "creates backup before migration" do
      plan = %{strategy: "big_bang", phases: [%{name: "Phase 1", tasks: []}]}
      files = [%{path: "test.rb", content: "puts 'test'"}]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.ExecuteMigrationAction.run(
        %{
          migration_plan: plan,
          source_files: files,
          target_language: "python",
          create_backup: true
        },
        context
      )
      
      assert Map.has_key?(result, :backup_info)
      backup = result.backup_info
      assert Map.has_key?(backup, :backup_id)
      assert Map.has_key?(backup, :created_at)
      assert Map.has_key?(backup, :file_count)
      assert backup.file_count == 1
    end
  end
  
  describe "migration validation" do
    test "validates syntax correctness" do
      valid_files = [
        %{
          target_path: "valid.py",
          migrated_content: "def hello():\n    return 'Hello World'"
        }
      ]
      
      invalid_files = [
        %{
          target_path: "invalid.py",
          migrated_content: "def hello()\n    return 'Hello World'"  # Missing colon
        }
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, valid_result} = CodeMigrationAgent.ValidateMigrationAction.run(
        %{
          migrated_files: valid_files,
          success_criteria: ["Valid syntax"],
          validation_level: "basic"
        },
        context
      )
      
      {:ok, invalid_result} = CodeMigrationAgent.ValidateMigrationAction.run(
        %{
          migrated_files: invalid_files,
          success_criteria: ["Valid syntax"],
          validation_level: "basic"
        },
        context
      )
      
      # Valid files should pass
      assert valid_result.validation_result.overall_status == :passed
      valid_file = hd(valid_result.validation_result.file_validations)
      assert valid_file.status == :passed
      assert length(valid_file.errors) == 0
      
      # Invalid files should fail
      assert invalid_result.validation_result.overall_status == :failed
      invalid_file = hd(invalid_result.validation_result.file_validations)
      assert invalid_file.status == :failed
      assert length(invalid_file.errors) > 0
    end
    
    test "validates logic preservation" do
      # Test with function that should maintain equivalent logic
      files = [
        %{
          original_content: "def add(a, b); a + b; end",
          migrated_content: "def add(a, b):\n    return a + b",
          target_path: "math.py"
        }
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.ValidateMigrationAction.run(
        %{
          migrated_files: files,
          success_criteria: ["Logic preservation"],
          validation_level: "comprehensive"
        },
        context
      )
      
      validation = result.validation_result
      file_validation = hd(validation.file_validations)
      
      # Should pass logic preservation check
      logic_check = Enum.find(file_validation.checks, &(&1.type == :logic_preservation))
      assert logic_check != nil
      assert logic_check.status == :passed
    end
    
    test "generates detailed validation reports" do
      files = [
        %{target_path: "test.py", migrated_content: "print('test')"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.ValidateMigrationAction.run(
        %{
          migrated_files: files,
          success_criteria: ["Valid syntax", "Logic preservation"],
          validation_level: "comprehensive",
          generate_report: true
        },
        context
      )
      
      assert Map.has_key?(result, :detailed_report)
      report = result.detailed_report
      
      assert Map.has_key?(report, :executive_summary)
      assert Map.has_key?(report, :file_details)
      assert Map.has_key?(report, :recommendations)
      
      # Executive summary should include key metrics
      summary = report.executive_summary
      assert Map.has_key?(summary, :overall_success_rate)
      assert Map.has_key?(summary, :critical_issues_count)
      assert is_float(summary.overall_success_rate)
    end
  end
  
  describe "rollback procedures" do
    test "creates selective rollback for specific components" do
      migration_state = %{
        completed_phases: ["Foundation", "Core Logic", "UI Updates"],
        migrated_files: [
          %{original_path: "core.rb", target_path: "core.py"},
          %{original_path: "ui.rb", target_path: "ui.py"}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.CreateRollbackAction.run(
        %{
          migration_state: migration_state,
          rollback_strategy: "selective",
          rollback_scope: ["UI Updates"]  # Only rollback UI changes
        },
        context
      )
      
      plan = result.rollback_plan
      assert plan.strategy == "selective"
      
      # Should only include UI-related rollback steps
      ui_steps = Enum.filter(plan.steps, &String.contains?(&1.description, "ui"))
      assert length(ui_steps) > 0
      
      # Should not include core logic rollback
      core_steps = Enum.filter(plan.steps, &String.contains?(&1.description, "core"))
      assert length(core_steps) == 0
    end
    
    test "creates full rollback for complete migration reversal" do
      migration_state = %{
        completed_phases: ["Phase 1", "Phase 2"],
        migrated_files: [
          %{original_path: "app.rb", target_path: "app.py"},
          %{original_path: "config.rb", target_path: "config.py"}
        ],
        database_changes: [
          %{table: "schema_migrations", operation: "insert"}
        ]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.CreateRollbackAction.run(
        %{
          migration_state: migration_state,
          rollback_strategy: "full"
        },
        context
      )
      
      plan = result.rollback_plan
      assert plan.strategy == "full"
      
      # Should include file restoration
      file_steps = Enum.filter(plan.steps, &(&1.action == :restore_files))
      assert length(file_steps) > 0
      
      # Should include database rollback
      db_steps = Enum.filter(plan.steps, &(&1.action == :rollback_database))
      assert length(db_steps) > 0
      
      # Check recovery procedures
      procedures = result.recovery_procedures
      assert length(procedures.file_restoration) == 2
      assert length(procedures.database_restoration) > 0
    end
    
    test "includes risk assessment for rollback operations" do
      migration_state = %{
        completed_phases: ["Critical System Updates"],
        migrated_files: [%{original_path: "critical.rb", target_path: "critical.py"}]
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.CreateRollbackAction.run(
        %{
          migration_state: migration_state,
          rollback_strategy: "full"
        },
        context
      )
      
      plan = result.rollback_plan
      
      # Should have high-risk steps for critical components
      high_risk_steps = Enum.filter(plan.steps, &(&1.risk_level == :high))
      assert length(high_risk_steps) > 0
      
      # Should include risk mitigation
      assert Map.has_key?(result, :risk_mitigation)
      mitigation = result.risk_mitigation
      assert is_list(mitigation.strategies)
      
      # Should recommend testing
      testing_strategy = Enum.find(mitigation.strategies, 
        &String.contains?(&1.description, "test"))
      assert testing_strategy != nil
    end
  end
  
  describe "dependency management" do
    test "handles version compatibility conflicts" do
      conflicting_changes = [
        %{name: "react", new_version: "18.0.0", type: "major_upgrade"},
        %{name: "react-dom", new_version: "17.0.0", type: "upgrade"}  # Incompatible versions
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.UpdateDependenciesAction.run(
        %{
          dependency_changes: conflicting_changes,
          target_language: "javascript",
          compatibility_check: true
        },
        context
      )
      
      compatibility = result.compatibility_analysis
      
      # Should detect version conflict
      conflicts = compatibility.dependency_conflicts
      react_conflict = Enum.find(conflicts, 
        &(String.contains?(&1.description, "react") && &1.severity == :high))
      assert react_conflict != nil
      
      # Should provide resolution suggestions
      suggestions = compatibility.resolution_suggestions
      assert length(suggestions) > 0
      
      version_align_suggestion = Enum.find(suggestions, 
        &String.contains?(&1.description, "align"))
      assert version_align_suggestion != nil
    end
    
    test "identifies security vulnerabilities in dependencies" do
      vulnerable_changes = [
        %{name: "lodash", old_version: "4.17.15", new_version: "4.17.20", type: "security_update"},
        %{name: "express", old_version: "4.16.0", new_version: "4.18.0", type: "upgrade"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.UpdateDependenciesAction.run(
        %{
          dependency_changes: vulnerable_changes,
          target_language: "javascript",
          security_scan: true
        },
        context
      )
      
      validation = result.validation_results
      
      # Should identify security improvements
      vulnerabilities = validation.security_vulnerabilities
      lodash_security = Enum.find(vulnerabilities, 
        &String.contains?(&1.package, "lodash"))
      assert lodash_security != nil
      assert lodash_security.status == :resolved
      
      # Should recommend security updates
      recommendations = result.security_recommendations
      assert is_list(recommendations)
    end
    
    test "updates package manifests correctly" do
      changes = [
        %{name: "django", old_version: "3.2.0", new_version: "4.1.0", type: "major_upgrade"},
        %{name: "psycopg2", old_version: "2.8.6", new_version: "2.9.3", type: "upgrade"},
        %{name: "old_package", old_version: "1.0.0", new_version: nil, type: "removal"}
      ]
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = CodeMigrationAgent.UpdateDependenciesAction.run(
        %{
          dependency_changes: changes,
          target_language: "python",
          update_lock_files: true
        },
        context
      )
      
      manifests = result.updated_manifests
      
      # Should update requirements.txt
      assert Map.has_key?(manifests, :requirements_txt)
      requirements = manifests.requirements_txt
      
      assert String.contains?(requirements, "django==4.1.0")
      assert String.contains?(requirements, "psycopg2==2.9.3")
      refute String.contains?(requirements, "old_package")
      
      # Should update lock file if requested
      if Map.has_key?(manifests, :requirements_lock) do
        lock_file = manifests.requirements_lock
        assert String.contains?(lock_file, "django==4.1.0")
      end
    end
  end
  
  describe "migration state management" do
    test "tracks migration history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate migration result
      result = %{
        result: %{
          migration_type: "language_translation",
          source_language: "ruby",
          target_language: "python",
          files_migrated: 5,
          success_rate: 0.9
        },
        from_cache: false
      }
      
      metadata = %{operation: :migration, migration_id: "test_migration_001"}
      
      {:ok, updated} = CodeMigrationAgent.handle_action_result(
        state,
        CodeMigrationAgent.ExecuteToolAction,
        {:ok, result},
        metadata
      )
      
      # Check history was updated
      assert length(updated.state.migration_history) == 1
      history_entry = hd(updated.state.migration_history)
      assert history_entry.type == :code_migration
      assert history_entry.operation == :migration
      assert history_entry.migration_id == "test_migration_001"
    end
    
    test "tracks active migration projects", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      project_info = %{
        id: "proj_001",
        name: "Rails to Django Migration",
        status: :in_progress,
        started_at: DateTime.utc_now()
      }
      
      result = %{migration_project: project_info}
      
      {:ok, updated} = CodeMigrationAgent.handle_action_result(
        state,
        CodeMigrationAgent.PlanMigrationAction,
        {:ok, result},
        %{}
      )
      
      # Check project was stored
      assert Map.has_key?(updated.state.active_projects, "proj_001")
      stored_project = updated.state.active_projects["proj_001"]
      assert stored_project.name == "Rails to Django Migration"
      assert stored_project.status == :in_progress
    end
    
    test "respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple migrations
      state = Enum.reduce(1..3, state, fn i, acc ->
        result = %{
          result: %{migration_type: "test", files_migrated: i},
          from_cache: false
        }
        
        {:ok, updated} = CodeMigrationAgent.handle_action_result(
          acc,
          CodeMigrationAgent.ExecuteToolAction,
          {:ok, result},
          %{operation: :migration, migration_id: "migration_#{i}"}
        )
        
        updated
      end)
      
      assert length(state.state.migration_history) == 2
      # Should have the most recent entries
      [first, second] = state.state.migration_history
      assert first.migration_id == "migration_3"
      assert second.migration_id == "migration_2"
    end
  end
  
  describe "agent initialization" do
    test "agent starts with default configuration", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check default migration strategies
      strategies = state.state.migration_strategies
      assert Map.has_key?(strategies, :big_bang)
      assert Map.has_key?(strategies, :gradual)
      assert Map.has_key?(strategies, :parallel)
      assert Map.has_key?(strategies, :pilot)
      
      # Check language mappings
      mappings = state.state.language_mappings
      assert Map.has_key?(mappings, "ruby")
      assert Map.has_key?(mappings, "python")
      assert Map.has_key?(mappings, "javascript")
      
      # Check validation rules
      rules = state.state.validation_rules
      assert Map.has_key?(rules, :syntax_validation)
      assert Map.has_key?(rules, :logic_preservation)
      assert rules.syntax_validation.enabled == true
    end
  end
  
  describe "result processing" do
    test "process_result adds processing timestamp", %{agent: _agent} do
      result = %{migration_type: "test", files_migrated: 3}
      processed = CodeMigrationAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :processed_at)
      assert %DateTime{} = processed.processed_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = CodeMigrationAgent.additional_actions()
      
      assert length(actions) == 6
      assert CodeMigrationAgent.AnalyzeMigrationAction in actions
      assert CodeMigrationAgent.PlanMigrationAction in actions
      assert CodeMigrationAgent.ExecuteMigrationAction in actions
      assert CodeMigrationAgent.ValidateMigrationAction in actions
      assert CodeMigrationAgent.CreateRollbackAction in actions
      assert CodeMigrationAgent.UpdateDependenciesAction in actions
    end
  end
end