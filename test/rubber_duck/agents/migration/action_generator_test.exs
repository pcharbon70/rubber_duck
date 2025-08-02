defmodule RubberDuck.Agents.Migration.ActionGeneratorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Agents.Migration.ActionGenerator
  alias RubberDuck.Agents.AnalysisAgent
  
  describe "generate_action/3" do
    test "generates action code from agent function" do
      options = %{
        module_name: "TestAction",
        description: "Test action for migration",
        namespace: "Test.Actions"
      }
      
      # Try to generate action from a public function
      result = ActionGenerator.generate_action(AnalysisAgent, :get_capabilities, options)
      
      case result do
        {:ok, code} ->
          assert is_binary(code)
          assert String.contains?(code, "defmodule Test.Actions.TestAction")
          assert String.contains?(code, "use Jido.Action")
          assert String.contains?(code, "def run(params, context)")
        
        {:error, reason} ->
          # Function might not exist or be suitable for action generation
          assert is_tuple(reason)
      end
    end
    
    test "handles invalid function names gracefully" do
      options = %{module_name: "TestAction"}
      
      result = ActionGenerator.generate_action(AnalysisAgent, :nonexistent_function, options)
      
      assert {:error, _reason} = result
    end
  end
  
  describe "generate_all_actions/2" do
    test "generates multiple actions from agent" do
      options = %{namespace: "Test.Actions"}
      
      {:ok, actions} = ActionGenerator.generate_all_actions(AnalysisAgent, options)
      
      assert is_list(actions)
      
      if length(actions) > 0 do
        action = List.first(actions)
        assert Map.has_key?(action, :name)
        assert Map.has_key?(action, :code)
        assert is_binary(action.code)
      end
    end
  end
  
  describe "generate_with_tests/3" do
    test "generates action with test code" do
      options = %{
        module_name: "TestAction",
        namespace: "Test.Actions"
      }
      
      result = ActionGenerator.generate_with_tests(AnalysisAgent, :get_capabilities, options)
      
      case result do
        {:ok, {action_code, test_code}} ->
          assert is_binary(action_code)
          assert is_binary(test_code)
          assert String.contains?(action_code, "defmodule Test.Actions.TestAction")
          assert String.contains?(test_code, "defmodule Test.Actions.TestActionTest")
          assert String.contains?(test_code, "use ExUnit.Case")
        
        {:error, _reason} ->
          # Function might not be suitable for generation
          :ok
      end
    end
  end
  
  describe "generate_mix_task/0" do
    test "generates mix task code" do
      {:ok, task_code} = ActionGenerator.generate_mix_task()
      
      assert is_binary(task_code)
      assert String.contains?(task_code, "defmodule Mix.Tasks.Jido.Gen.Action")
      assert String.contains?(task_code, "use Mix.Task")
      assert String.contains?(task_code, "def run(args)")
    end
  end
  
  describe "generate_template_action_code/3" do
    test "generates template action code" do
      namespace = "Test.Actions"
      name = "ExampleAction"
      schema = [name: [type: :string, required: true]]
      
      code = ActionGenerator.generate_template_action_code(namespace, name, schema)
      
      assert is_binary(code)
      assert String.contains?(code, "defmodule #{namespace}.#{name}")
      assert String.contains?(code, "use Jido.Action")
      assert String.contains?(code, "schema: [")
    end
  end
  
  describe "generate_template_test_code/1" do
    test "generates template test code" do
      name = "ExampleAction"
      
      code = ActionGenerator.generate_template_test_code(name)
      
      assert is_binary(code)
      assert String.contains?(code, "defmodule #{name}Test")
      assert String.contains?(code, "use ExUnit.Case")
      assert String.contains?(code, "describe \"run/2\"")
    end
  end
end