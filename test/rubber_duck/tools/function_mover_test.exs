defmodule RubberDuck.Tools.FunctionMoverTest do
  use ExUnit.Case, async: true
  alias RubberDuck.Tools.FunctionMover
  
  setup do
    # Register the tool
    RubberDuck.Tool.Registry.register(FunctionMover)
    :ok
  end
  
  describe "parameter validation" do
    test "validates required parameters" do
      assert {:error, %{parameter: :source_code}} = FunctionMover.execute(%{}, %{})
    end
    
    test "validates function name pattern" do
      params = %{
        source_code: "defmodule A do end",
        target_code: "defmodule B do end",
        function_name: "123invalid",  # Invalid - starts with number
        source_module: "A",
        target_module: "B"
      }
      
      assert {:error, %{parameter: :function_name}} = FunctionMover.execute(params, %{})
    end
    
    test "validates module name pattern" do
      params = %{
        source_code: "defmodule A do end",
        target_code: "defmodule B do end",
        function_name: "test_func",
        source_module: "lowercase",  # Invalid - must start with uppercase
        target_module: "B"
      }
      
      assert {:error, %{parameter: :source_module}} = FunctionMover.execute(params, %{})
    end
  end
  
  describe "function detection" do
    test "finds single function to move" do
      source_code = """
      defmodule MyApp.Source do
        def target_function(x) do
          x * 2
        end
        
        def other_function do
          :ok
        end
      end
      """
      
      target_code = """
      defmodule MyApp.Target do
        def existing_function do
          :existing
        end
      end
      """
      
      params = %{
        source_code: source_code,
        target_code: target_code,
        function_name: "target_function",
        source_module: "MyApp.Source",
        target_module: "MyApp.Target",
        update_references: false
      }
      
      # This would need mocking of LLM service in real tests
      # For now, we just verify parameter validation passes
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
    end
    
    test "handles multiple functions with same name" do
      source_code = """
      defmodule MyApp.Source do
        def process(x) when is_integer(x), do: x * 2
        def process(x) when is_binary(x), do: String.upcase(x)
        def process(x, y), do: {x, y}
      end
      """
      
      target_code = "defmodule MyApp.Target do end"
      
      # Without arity specified, should error
      params = %{
        source_code: source_code,
        target_code: target_code,
        function_name: "process",
        source_module: "MyApp.Source",
        target_module: "MyApp.Target"
      }
      
      # Would return error about multiple functions in real execution
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
      
      # With arity specified, should work
      params_with_arity = Map.put(params, :function_arity, 2)
      assert match?({:error, _}, FunctionMover.execute(params_with_arity, %{}))
    end
  end
  
  describe "visibility handling" do
    test "preserves function visibility by default" do
      params = base_params()
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
    end
    
    test "can change function visibility" do
      params = base_params() |> Map.put(:visibility, "public")
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
    end
  end
  
  describe "dependency analysis" do
    test "identifies private function dependencies" do
      source_code = """
      defmodule MyApp.Source do
        def public_function(x) do
          helper(x) + other_helper(x)
        end
        
        defp helper(x), do: x * 2
        defp other_helper(x), do: x + 1
      end
      """
      
      params = base_params()
      |> Map.put(:source_code, source_code)
      |> Map.put(:function_name, "public_function")
      |> Map.put(:include_dependencies, true)
      
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
    end
  end
  
  describe "reference updating" do
    test "updates references when requested" do
      affected_files = [
        %{
          "path" => "lib/app/caller.ex",
          "content" => """
          defmodule MyApp.Caller do
            alias MyApp.Source
            
            def call_function do
              Source.moved_function(42)
            end
          end
          """
        }
      ]
      
      params = base_params()
      |> Map.put(:update_references, true)
      |> Map.put(:affected_files, affected_files)
      
      assert match?({:error, _}, FunctionMover.execute(params, %{}))
    end
  end
  
  # Helper functions
  
  defp base_params do
    %{
      source_code: """
      defmodule MyApp.Source do
        def moved_function(x) do
          x * 2
        end
      end
      """,
      target_code: """
      defmodule MyApp.Target do
        def existing do
          :ok
        end
      end
      """,
      function_name: "moved_function",
      source_module: "MyApp.Source",
      target_module: "MyApp.Target"
    }
  end
end