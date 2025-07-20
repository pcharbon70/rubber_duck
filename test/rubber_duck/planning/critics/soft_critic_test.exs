defmodule RubberDuck.Planning.Critics.SoftCriticTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Critics.SoftCritic
  alias RubberDuck.Planning.Critics.SoftCritic.{
    StyleChecker,
    BestPracticeValidator,
    PerformanceAnalyzer,
    SecurityChecker
  }
  
  describe "StyleChecker" do
    test "validates good naming conventions" do
      target = %{name: "Process User Registration"}
      
      {:ok, result} = StyleChecker.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about short names" do
      target = %{name: "Do"}
      
      {:ok, result} = StyleChecker.validate(target, [])
      assert result.status == :warning
      assert result.message == "Style improvements recommended"
    end
    
    test "checks description quality" do
      target = %{
        description: "This task processes user registration by validating input data, creating user records, and sending confirmation emails."
      }
      
      {:ok, result} = StyleChecker.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about missing description" do
      target = %{}
      
      {:ok, result} = StyleChecker.validate(target, [])
      assert result.status == :warning
    end
    
    test "checks documentation completeness" do
      target = %{
        description: "Task description",
        success_criteria: ["User created", "Email sent"],
        acceptance_criteria: ["All validations pass"]
      }
      
      {:ok, result} = StyleChecker.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about complex tasks" do
      task = %{
        complexity: :very_complex,
        dependencies: List.duplicate("dep", 15),
        struct_name: RubberDuck.Planning.Task
      }
      
      defmodule RubberDuck.Planning.Task do
        defstruct [:complexity, :dependencies, :subtasks]
      end
      
      task_struct = struct(RubberDuck.Planning.Task, task)
      
      {:ok, result} = StyleChecker.validate(task_struct, [])
      assert result.status == :warning
    end
  end
  
  describe "BestPracticeValidator" do
    test "validates single responsibility" do
      target = %{
        description: "Validate user input data",
        complexity: :simple
      }
      
      {:ok, result} = BestPracticeValidator.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about multiple responsibilities" do
      target = %{
        description: "Create user, update profile, delete old records, fetch permissions, process payments, and manage notifications",
        complexity: :very_complex
      }
      
      {:ok, result} = BestPracticeValidator.validate(target, [])
      assert result.status == :warning
    end
    
    test "checks for clear interfaces" do
      target = %{
        inputs: %{user_data: "map", config: "map"},
        outputs: %{user: "User struct", status: "atom"}
      }
      
      {:ok, result} = BestPracticeValidator.validate(target, [])
      assert result.status == :passed
    end
    
    test "checks error handling documentation" do
      target = %{
        description: "Process payment with retry logic and fallback handling"
      }
      
      {:ok, result} = BestPracticeValidator.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about missing testing strategy" do
      target = %{
        description: "Complex business logic implementation"
      }
      
      {:ok, result} = BestPracticeValidator.validate(target, [])
      assert result.message =~ "best practice"
    end
  end
  
  describe "PerformanceAnalyzer" do
    test "warns about nested loops" do
      target = %{
        details: %{
          "algorithm" => "Use nested loop iteration to process matrix"
        }
      }
      
      {:ok, result} = PerformanceAnalyzer.validate(target, [])
      assert result.status == :warning
      assert result.message == "Performance concerns identified"
    end
    
    test "approves batch processing" do
      target = %{
        description: "Process records in bulk batches of 1000"
      }
      
      {:ok, result} = PerformanceAnalyzer.validate(target, [])
      assert result.status == :passed
    end
    
    test "suggests pagination for large datasets" do
      target = %{
        description: "Load all user records from database"
      }
      
      {:ok, result} = PerformanceAnalyzer.validate(target, [])
      assert result.status == :warning
    end
    
    test "checks resource usage" do
      target = %{
        resource_requirements: %{
          memory_mb: 2000,
          cpu_percent: 90
        }
      }
      
      {:ok, result} = PerformanceAnalyzer.validate(target, [])
      assert result.status == :warning
      assert result.details.concerns
    end
  end
  
  describe "SecurityChecker" do
    test "detects authentication requirements" do
      target = %{
        description: "Implement user authentication endpoint",
        security_requirements: %{auth_required: true}
      }
      
      {:ok, result} = SecurityChecker.validate(target, [])
      assert result.status == :passed
    end
    
    test "warns about missing auth requirements" do
      target = %{
        description: "Create API endpoint for user profile access"
      }
      
      {:ok, result} = SecurityChecker.validate(target, [])
      assert result.status == :warning
      assert result.message == "Security considerations needed"
    end
    
    test "detects sensitive data handling" do
      target = %{
        description: "Store user password in database"
      }
      
      {:ok, result} = SecurityChecker.validate(target, [])
      assert result.status == :warning
    end
    
    test "checks input validation" do
      target = %{
        description: "Accept user input and validate before processing"
      }
      
      {:ok, result} = SecurityChecker.validate(target, [])
      assert result.status == :passed
    end
    
    test "detects potential SQL injection" do
      target = %{
        description: "Build SQL query by concatenating user input"
      }
      
      {:ok, result} = SecurityChecker.validate(target, [])
      assert result.status == :warning
      assert result.details.concerns
    end
  end
  
  describe "validate_all/2" do
    test "runs all soft critics" do
      target = %{
        name: "Good Task Name",
        description: "A well-described task that follows best practices.",
        complexity: :medium
      }
      
      results = SoftCritic.validate_all(target)
      
      assert length(results) == 4
      assert Enum.all?(results, fn {critic, result} ->
        critic in SoftCritic.all_critics() and match?({:ok, _}, result)
      end)
    end
    
    test "handles critic execution errors gracefully" do
      # Create a target that might cause issues
      target = nil
      
      results = SoftCritic.validate_all(target)
      
      # Should still return results, even if some critics fail
      assert is_list(results)
    end
  end
end