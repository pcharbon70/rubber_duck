defmodule RubberDuck.Planning.Critics.HardCriticTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Critics.HardCritic
  alias RubberDuck.Planning.Critics.HardCritic.{
    SyntaxValidator,
    DependencyValidator,
    ConstraintChecker,
    FeasibilityAnalyzer,
    ResourceValidator
  }
  
  describe "SyntaxValidator" do
    test "validates valid Elixir code" do
      target = %{
        details: %{
          "code" => """
          def hello(name) do
            "Hello, #{name}!"
          end
          """
        }
      }
      
      {:ok, result} = SyntaxValidator.validate(target, [])
      assert result.status == :passed
    end
    
    test "detects syntax errors" do
      target = %{
        details: %{
          "code" => """
          def hello(name) do
            "Hello, #{name}!" <-- syntax error
          end
          """
        }
      }
      
      {:ok, result} = SyntaxValidator.validate(target, [])
      assert result.status == :failed
      assert result.message == "Syntax validation failed"
    end
    
    test "extracts code from markdown description" do
      target = %{
        description: """
        Here's the code:
        
        ```elixir
        def add(a, b), do: a + b
        ```
        """
      }
      
      {:ok, result} = SyntaxValidator.validate(target, [])
      assert result.status == :passed
    end
    
    test "handles no code snippets" do
      target = %{description: "Just a regular description"}
      
      {:ok, result} = SyntaxValidator.validate(target, [])
      assert result.status == :passed
      assert result.message == "No code snippets to validate"
    end
  end
  
  describe "DependencyValidator" do
    test "validates task dependencies exist" do
      task = %{
        id: "task-1",
        dependencies: ["task-2", "task-3"],
        struct_name: RubberDuck.Planning.Task
      }
      
      plan_tasks = [
        %{id: "task-1"},
        %{id: "task-2"},
        %{id: "task-3"}
      ]
      
      plan = %{tasks: plan_tasks}
      
      # Mock the Task struct
      defmodule RubberDuck.Planning.Task do
        defstruct [:id, :dependencies]
      end
      
      task_struct = struct(RubberDuck.Planning.Task, task)
      
      {:ok, result} = DependencyValidator.validate(task_struct, plan: plan)
      assert result.status == :passed
    end
    
    test "detects circular dependencies" do
      tasks = [
        %{id: "task-1", dependencies: ["task-2"]},
        %{id: "task-2", dependencies: ["task-3"]},
        %{id: "task-3", dependencies: ["task-1"]}
      ]
      
      # Mock Plan struct with tasks
      plan = %{id: "plan-1", tasks: tasks}
      
      {:ok, result} = DependencyValidator.validate(plan, [])
      assert result.status == :failed
      assert result.message == "Circular dependencies detected"
    end
    
    test "handles tasks with no dependencies" do
      tasks = [
        %{id: "task-1", dependencies: []},
        %{id: "task-2", dependencies: nil}
      ]
      
      plan = %{tasks: tasks}
      
      {:ok, result} = DependencyValidator.validate(plan, [])
      assert result.status == :passed
    end
  end
  
  describe "ConstraintChecker" do
    test "validates duration constraints" do
      target = %{estimated_duration: 10}
      
      constraint = %{
        type: :max_duration,
        parameters: %{max_hours: 20}
      }
      
      {:ok, result} = ConstraintChecker.validate(target, constraints: [constraint])
      assert result.status == :passed
    end
    
    test "detects duration constraint violations" do
      target = %{estimated_duration: 30}
      
      constraint = %{
        type: :max_duration,
        parameters: %{max_hours: 20}
      }
      
      {:ok, result} = ConstraintChecker.validate(target, constraints: [constraint])
      assert result.status == :failed
      assert result.message == "Constraint violations found"
    end
    
    test "handles no constraints" do
      target = %{}
      
      {:ok, result} = ConstraintChecker.validate(target, [])
      assert result.status == :passed
      assert result.message == "No constraints to check"
    end
  end
  
  describe "FeasibilityAnalyzer" do
    test "analyzes simple complexity as feasible" do
      target = %{complexity: :simple}
      
      {:ok, result} = FeasibilityAnalyzer.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about very complex tasks" do
      target = %{complexity: :very_complex}
      
      {:ok, result} = FeasibilityAnalyzer.validate(target, [])
      assert result.status == :warning
    end
    
    test "detects infeasible timeline" do
      target = %{
        estimated_duration: 100,
        deadline: DateTime.add(DateTime.utc_now(), 50, :hour)
      }
      
      {:ok, result} = FeasibilityAnalyzer.validate(target, [])
      assert result.status == :failed
      assert result.message == "Feasibility issues found"
    end
    
    test "warns about vague descriptions" do
      target = %{description: "Do stuff"}
      
      {:ok, result} = FeasibilityAnalyzer.validate(target, [])
      assert result.status == :warning
    end
  end
  
  describe "ResourceValidator" do
    test "validates sufficient resources" do
      target = %{
        resource_requirements: %{
          memory_mb: 512,
          cpu_cores: 2
        }
      }
      
      available = %{
        memory_mb: 1024,
        cpu_cores: 4
      }
      
      {:ok, result} = ResourceValidator.validate(target, available_resources: available)
      assert result.status == :passed
    end
    
    test "detects insufficient resources" do
      target = %{
        resource_requirements: %{
          memory_mb: 2048,
          cpu_cores: 8
        }
      }
      
      available = %{
        memory_mb: 1024,
        cpu_cores: 4
      }
      
      {:ok, result} = ResourceValidator.validate(target, available_resources: available)
      assert result.status == :failed
      assert result.message == "Resource validation failed"
    end
    
    test "handles list of required resources" do
      target = %{
        resource_requirements: ["database", "redis", "elasticsearch"]
      }
      
      available = %{
        "database" => true,
        "redis" => true
      }
      
      {:ok, result} = ResourceValidator.validate(target, available_resources: available)
      assert result.status == :failed
      assert %{missing: ["elasticsearch"]} = result.details
    end
  end
  
  describe "validate_all/2" do
    test "runs all hard critics" do
      target = %{
        description: "A simple task",
        complexity: :simple
      }
      
      results = HardCritic.validate_all(target)
      
      assert length(results) == 5
      assert Enum.all?(results, fn {critic, result} ->
        critic in HardCritic.all_critics() and match?({:ok, _}, result)
      end)
    end
    
    test "runs critics in priority order" do
      target = %{}
      results = HardCritic.validate_all(target)
      
      critics = Enum.map(results, fn {critic, _} -> critic end)
      priorities = Enum.map(critics, & &1.priority())
      
      assert priorities == Enum.sort(priorities)
    end
  end
end