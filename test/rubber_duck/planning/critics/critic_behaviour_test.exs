defmodule RubberDuck.Planning.Critics.CriticBehaviourTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Critics.CriticBehaviour
  
  defmodule TestCritic do
    @behaviour CriticBehaviour
    
    @impl true
    def name, do: "Test Critic"
    
    @impl true
    def type, do: :hard
    
    @impl true
    def priority, do: 50
    
    @impl true
    def validate(_target, _opts) do
      {:ok, %{status: :passed, message: "Test passed"}}
    end
  end
  
  describe "validation_result/3" do
    test "creates a basic validation result" do
      result = CriticBehaviour.validation_result(:passed, "All good")
      
      assert result == %{
        status: :passed,
        message: "All good"
      }
    end
    
    test "creates a validation result with optional fields" do
      result = CriticBehaviour.validation_result(:failed, "Issues found",
        severity: :error,
        details: %{errors: ["Error 1", "Error 2"]},
        suggestions: ["Fix error 1", "Fix error 2"],
        metadata: %{timestamp: ~U[2024-01-20 12:00:00Z]}
      )
      
      assert result.status == :failed
      assert result.message == "Issues found"
      assert result.severity == :error
      assert result.details == %{errors: ["Error 1", "Error 2"]}
      assert result.suggestions == ["Fix error 1", "Fix error 2"]
      assert result.metadata.timestamp
    end
  end
  
  describe "default_severity/2" do
    test "returns appropriate severity for passed status" do
      assert CriticBehaviour.default_severity(:passed, :hard) == :info
      assert CriticBehaviour.default_severity(:passed, :soft) == :info
    end
    
    test "returns appropriate severity for warning status" do
      assert CriticBehaviour.default_severity(:warning, :hard) == :error
      assert CriticBehaviour.default_severity(:warning, :soft) == :warning
    end
    
    test "returns appropriate severity for failed status" do
      assert CriticBehaviour.default_severity(:failed, :hard) == :critical
      assert CriticBehaviour.default_severity(:failed, :soft) == :warning
    end
  end
  
  describe "behaviour implementation" do
    test "TestCritic implements all required callbacks" do
      assert TestCritic.name() == "Test Critic"
      assert TestCritic.type() == :hard
      assert TestCritic.priority() == 50
      
      {:ok, result} = TestCritic.validate(%{}, [])
      assert result.status == :passed
      assert result.message == "Test passed"
    end
  end
end