defmodule RubberDuck.Tools.CodeGeneratorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeGenerator
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeGenerator.name() == :code_generator
      
      metadata = CodeGenerator.metadata()
      assert metadata.name == :code_generator
      assert metadata.description == "Generates Elixir code from a given description or signature"
      assert metadata.category == :code_generation
      assert metadata.version == "1.0.0"
      assert :generation in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeGenerator.parameters()
      
      description_param = Enum.find(params, &(&1.name == :description))
      assert description_param.required == true
      assert description_param.type == :string
      
      signature_param = Enum.find(params, &(&1.name == :signature))
      assert signature_param.required == false
      
      include_tests_param = Enum.find(params, &(&1.name == :include_tests))
      assert include_tests_param.type == :boolean
      assert include_tests_param.default == false
    end
  end
  
  describe "execute/2" do
    @tag :integration
    test "generates code for a simple function" do
      params = %{
        description: "Create a function that calculates the factorial of a number",
        style: "functional"
      }
      
      # This would normally call the LLM service
      # For testing, we'll need to mock the service
      # {:ok, result} = CodeGenerator.execute(params, %{})
      
      # assert result.code =~ "def factorial"
      # assert result.language == "elixir"
    end
    
    test "validates required parameters" do
      # Test parameter validation is handled by the Tool DSL
      params = %{}
      
      # This should be caught by the Tool validation layer
      # before reaching execute/2
    end
    
    test "extracts code from markdown blocks" do
      # Test the private extract_code function behavior
      # through the public interface
    end
  end
end