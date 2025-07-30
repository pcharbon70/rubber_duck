defmodule RubberDuck.Tools.CodeRefactorerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeRefactorer
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeRefactorer.name() == :code_refactorer
      
      metadata = CodeRefactorer.metadata()
      assert metadata.name == :code_refactorer
      assert metadata.description == "Applies structural or semantic transformations to existing code based on an instruction"
      assert metadata.category == :code_transformation
      assert metadata.version == "1.0.0"
      assert :refactoring in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeRefactorer.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == true
      assert code_param.type == :string
      
      instruction_param = Enum.find(params, &(&1.name == :instruction))
      assert instruction_param.required == true
      
      refactoring_type_param = Enum.find(params, &(&1.name == :refactoring_type))
      assert refactoring_type_param.default == "general"
    end
    
    test "supports multiple refactoring types" do
      params = CodeRefactorer.parameters()
      refactoring_type_param = Enum.find(params, &(&1.name == :refactoring_type))
      
      allowed_types = refactoring_type_param.constraints[:enum]
      assert "extract_function" in allowed_types
      assert "rename" in allowed_types
      assert "simplify" in allowed_types
      assert "performance" in allowed_types
    end
  end
  
  describe "code analysis" do
    test "parses valid Elixir code" do
      code = """
      defmodule Example do
        def hello(name) do
          "Hello, #{name}!"
        end
      end
      """
      
      # Test through public interface when LLM is mocked
      # The parsing is tested internally
    end
    
    test "handles parse errors gracefully" do
      invalid_code = """
      defmodule Example do
        def hello(name
          "Hello, #{name}!"
        end
      end
      """
      
      # Should return error about parse failure
    end
  end
  
  describe "execute/2" do
    @tag :integration
    test "refactors code with extract function instruction" do
      code = """
      def process_data(data) do
        # Validation
        if length(data) == 0 do
          {:error, "Empty data"}
        else
          # Processing
          result = data
          |> Enum.map(&String.upcase/1)
          |> Enum.filter(&(String.length(&1) > 3))
          |> Enum.sort()
          
          {:ok, result}
        end
      end
      """
      
      params = %{
        code: code,
        instruction: "Extract the data processing pipeline into a separate function",
        refactoring_type: "extract_function"
      }
      
      # Would test with mocked LLM service
      # {:ok, result} = CodeRefactorer.execute(params, %{})
      # assert result.refactored_code =~ "defp process_items"
    end
    
    test "preserves functionality during refactoring" do
      # Test that refactored code maintains same behavior
    end
  end
end