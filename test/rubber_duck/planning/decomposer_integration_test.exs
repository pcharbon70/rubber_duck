defmodule RubberDuck.Planning.DecomposerIntegrationTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Planning.Decomposer
  
  @moduletag :skip
  
  describe "integration tests with actual engine" do
    @tag :integration
    test "decomposes a simple task with mock provider" do
      # This test would require the full engine system to be running
      # Skip for now until we have proper test setup
      
      description = "Create a user authentication system"
      context = %{provider: :mock, model: "test-model"}
      
      # This would fail without proper engine setup
      assert {:ok, _tasks} = Decomposer.decompose(description, context)
    end
  end
end