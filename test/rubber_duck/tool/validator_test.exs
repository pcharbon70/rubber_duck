defmodule RubberDuck.Tool.ValidatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tool.Validator
  
  defmodule TestTool do
    use RubberDuck.Tool
    
    tool do
      name :test_tool
      description "A test tool for validation"
      category :testing
      version "1.0.0"
      
      parameter :name do
        type :string
        required true
        description "The name parameter"
        constraints [
          min_length: 2,
          max_length: 50,
          pattern: "^[a-zA-Z0-9_]+$"
        ]
      end
      
      parameter :age do
        type :integer
        required true
        description "The age parameter"
        constraints [
          min: 0,
          max: 150
        ]
      end
      
      parameter :email do
        type :string
        required false
        description "Optional email parameter"
        constraints [
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        ]
      end
      
      parameter :tags do
        type :list
        required false
        description "Optional tags list"
        constraints [
          min_length: 1,
          max_length: 10
        ]
      end
      
      parameter :metadata do
        type :map
        required false
        description "Optional metadata map"
      end
      
      execution do
        handler &TestTool.execute/2
      end
    end
    
    def execute(_params, _context) do
      {:ok, "test result"}
    end
  end
  
  defmodule EnumTool do
    use RubberDuck.Tool
    
    tool do
      name :enum_tool
      description "A tool with enum constraints"
      
      parameter :status do
        type :string
        required true
        constraints [
          enum: ["active", "inactive", "pending"]
        ]
      end
      
      execution do
        handler &EnumTool.execute/2
      end
    end
    
    def execute(_params, _context) do
      {:ok, "enum result"}
    end
  end
  
  describe "parameter validation" do
    test "validates required parameters" do
      # Missing required parameter
      params = %{age: 25}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :name and error.type == :required
      end)
    end
    
    test "validates parameter types" do
      # Wrong type for age
      params = %{name: "john", age: "twenty-five"}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :age and error.type == :type_mismatch
      end)
    end
    
    test "validates string constraints" do
      # Name too short
      params = %{name: "a", age: 25}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :name and error.type == :min_length
      end)
      
      # Name too long
      params = %{name: String.duplicate("a", 51), age: 25}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :name and error.type == :max_length
      end)
      
      # Invalid pattern
      params = %{name: "john doe", age: 25}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :name and error.type == :pattern
      end)
    end
    
    test "validates integer constraints" do
      # Age too low
      params = %{name: "john", age: -1}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :age and error.type == :min
      end)
      
      # Age too high
      params = %{name: "john", age: 200}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :age and error.type == :max
      end)
    end
    
    test "validates email pattern" do
      # Invalid email
      params = %{name: "john", age: 25, email: "invalid-email"}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :email and error.type == :pattern
      end)
      
      # Valid email
      params = %{name: "john", age: 25, email: "john@example.com"}
      
      assert {:ok, validated_params} = Validator.validate_parameters(TestTool, params)
      assert validated_params.email == "john@example.com"
    end
    
    test "validates list constraints" do
      # Empty list when min_length is 1
      params = %{name: "john", age: 25, tags: []}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :tags and error.type == :min_length
      end)
      
      # Too many items
      params = %{name: "john", age: 25, tags: Enum.to_list(1..11)}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :tags and error.type == :max_length
      end)
    end
    
    test "validates enum constraints" do
      # Invalid enum value
      params = %{status: "unknown"}
      
      assert {:error, errors} = Validator.validate_parameters(EnumTool, params)
      assert Enum.any?(errors, fn error -> 
        error.field == :status and error.type == :enum
      end)
      
      # Valid enum value
      params = %{status: "active"}
      
      assert {:ok, validated_params} = Validator.validate_parameters(EnumTool, params)
      assert validated_params.status == "active"
    end
    
    test "validates successfully with all valid parameters" do
      params = %{
        name: "john_doe",
        age: 25,
        email: "john@example.com",
        tags: ["tag1", "tag2"],
        metadata: %{key: "value"}
      }
      
      assert {:ok, validated_params} = Validator.validate_parameters(TestTool, params)
      assert validated_params.name == "john_doe"
      assert validated_params.age == 25
      assert validated_params.email == "john@example.com"
      assert validated_params.tags == ["tag1", "tag2"]
      assert validated_params.metadata == %{key: "value"}
    end
    
    test "handles optional parameters correctly" do
      # Only required parameters
      params = %{name: "john", age: 25}
      
      assert {:ok, validated_params} = Validator.validate_parameters(TestTool, params)
      assert validated_params.name == "john"
      assert validated_params.age == 25
      assert Map.has_key?(validated_params, :email) == false
    end
  end
  
  describe "partial validation" do
    test "validates only provided fields in partial mode" do
      # Only validate name parameter
      params = %{name: "john"}
      
      assert {:ok, validated_params} = Validator.validate_parameters(TestTool, params, partial: true)
      assert validated_params.name == "john"
      
      # Invalid name in partial mode
      params = %{name: "a"}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params, partial: true)
      assert Enum.any?(errors, fn error -> 
        error.field == :name and error.type == :min_length
      end)
    end
    
    test "ignores missing required fields in partial mode" do
      # Missing required field but partial mode
      params = %{age: 25}
      
      assert {:ok, validated_params} = Validator.validate_parameters(TestTool, params, partial: true)
      assert validated_params.age == 25
    end
  end
  
  describe "error messages" do
    test "provides detailed error messages" do
      params = %{name: "a", age: 200}
      
      assert {:error, errors} = Validator.validate_parameters(TestTool, params)
      
      name_error = Enum.find(errors, &(&1.field == :name))
      assert name_error.message =~ "must be at least 2 characters"
      assert name_error.suggestion =~ "provide a name with at least 2 characters"
      
      age_error = Enum.find(errors, &(&1.field == :age))
      assert age_error.message =~ "must be at most 150"
      assert age_error.suggestion =~ "provide an age between 0 and 150"
    end
    
    test "provides suggestions for enum errors" do
      params = %{status: "unknown"}
      
      assert {:error, errors} = Validator.validate_parameters(EnumTool, params)
      
      status_error = Enum.find(errors, &(&1.field == :status))
      assert status_error.message =~ "must be one of"
      assert status_error.suggestion =~ "Use one of: active, inactive, pending"
    end
  end
  
  describe "JSON Schema validation" do
    test "validates against generated JSON schema" do
      # Get the schema from our JSON Schema generator
      schema = RubberDuck.Tool.JsonSchema.generate(TestTool)
      
      # Valid parameters should pass schema validation
      params = %{name: "john", age: 25}
      
      assert {:ok, _} = Validator.validate_against_schema(params, schema)
      
      # Invalid parameters should fail schema validation
      params = %{name: "a", age: 200}
      
      assert {:error, _} = Validator.validate_against_schema(params, schema)
    end
    
    test "combines schema validation with custom validation" do
      params = %{name: "john", age: 25}
      
      # Should pass both schema and custom validation
      assert {:ok, _} = Validator.validate_parameters(TestTool, params)
      
      # Should fail custom validation even if schema passes
      params = %{name: "a", age: 25}
      
      assert {:error, _} = Validator.validate_parameters(TestTool, params)
    end
  end
  
  describe "validation performance" do
    test "handles large parameter sets efficiently" do
      # Test with many parameters
      params = %{
        name: "john",
        age: 25,
        tags: Enum.to_list(1..100) |> Enum.map(&"tag#{&1}"),
        metadata: Enum.into(1..100, %{}, fn i -> {"key#{i}", "value#{i}"} end)
      }
      
      start_time = System.monotonic_time(:millisecond)
      result = Validator.validate_parameters(TestTool, params)
      end_time = System.monotonic_time(:millisecond)
      
      # Should complete within reasonable time (100ms)
      assert end_time - start_time < 100
      
      # Should still validate correctly
      assert {:error, _} = result # tags list too long
    end
  end
end