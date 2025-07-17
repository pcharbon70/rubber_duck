defmodule RubberDuck.Tool.JsonSchemaTest do
  use ExUnit.Case
  
  alias RubberDuck.Tool.JsonSchema
  
  defmodule TestCalculator do
    use RubberDuck.Tool
    
    tool do
      name :calculator
      description "A calculator tool that performs basic arithmetic operations"
      category :math
      version "1.0.0"
      tags [:math, :arithmetic, :utility]
      
      parameter :operation do
        type :string
        required true
        description "The operation to perform"
        constraints [
          enum: ["add", "subtract", "multiply", "divide"]
        ]
      end
      
      parameter :numbers do
        type :list
        required true
        description "List of numbers to operate on"
        constraints [
          min_length: 2,
          max_length: 10
        ]
      end
      
      parameter :precision do
        type :integer
        required false
        default 2
        description "Number of decimal places for the result"
        constraints [
          min: 0,
          max: 10
        ]
      end
      
      parameter :options do
        type :map
        required false
        description "Additional options for the calculation"
      end
      
      execution do
        handler &TestCalculator.execute/2
        timeout 5_000
        async false
        retries 1
      end
      
      security do
        sandbox :none
        capabilities []
      end
    end
    
    def execute(_params, _context) do
      {:ok, 42}
    end
  end
  
  defmodule SimpleTextTool do
    use RubberDuck.Tool
    
    tool do
      name :text_processor
      description "Simple text processing tool"
      category :text
      version "1.0.0"
      
      parameter :text do
        type :string
        required true
        description "The text to process"
      end
      
      execution do
        handler &SimpleTextTool.execute/2
      end
    end
    
    def execute(_params, _context) do
      {:ok, "processed"}
    end
  end
  
  describe "JSON Schema generation" do
    test "generates complete schema for complex tool" do
      schema = JsonSchema.generate(TestCalculator)
      
      assert schema["type"] == "object"
      assert schema["title"] == "Calculator Tool"
      assert schema["description"] == "A calculator tool that performs basic arithmetic operations"
      assert schema["version"] == "1.0.0"
      
      # Check properties
      properties = schema["properties"]
      assert is_map(properties)
      
      # Check operation parameter
      operation = properties["operation"]
      assert operation["type"] == "string"
      assert operation["description"] == "The operation to perform"
      assert operation["enum"] == ["add", "subtract", "multiply", "divide"]
      
      # Check numbers parameter
      numbers = properties["numbers"]
      assert numbers["type"] == "array"
      assert numbers["description"] == "List of numbers to operate on"
      assert numbers["minItems"] == 2
      assert numbers["maxItems"] == 10
      
      # Check precision parameter
      precision = properties["precision"]
      assert precision["type"] == "integer"
      assert precision["default"] == 2
      assert precision["minimum"] == 0
      assert precision["maximum"] == 10
      
      # Check options parameter
      options = properties["options"]
      assert options["type"] == "object"
      
      # Check required fields
      required = schema["required"]
      assert "operation" in required
      assert "numbers" in required
      refute "precision" in required
      refute "options" in required
    end
    
    test "generates schema for simple tool" do
      schema = JsonSchema.generate(SimpleTextTool)
      
      assert schema["type"] == "object"
      assert schema["title"] == "Text Processor Tool"
      assert schema["description"] == "Simple text processing tool"
      assert schema["version"] == "1.0.0"
      
      # Check properties
      properties = schema["properties"]
      text = properties["text"]
      assert text["type"] == "string"
      assert text["description"] == "The text to process"
      
      # Check required fields
      required = schema["required"]
      assert required == ["text"]
    end
    
    test "includes metadata in schema" do
      schema = JsonSchema.generate(TestCalculator)
      
      # Check metadata section
      metadata = schema["metadata"]
      assert metadata["name"] == "calculator"
      assert metadata["category"] == "math"
      assert metadata["version"] == "1.0.0"
      assert metadata["tags"] == ["math", "arithmetic", "utility"]
      
      # Check execution metadata
      execution = metadata["execution"]
      assert execution["timeout"] == 5_000
      assert execution["async"] == false
      assert execution["retries"] == 1
      
      # Check security metadata
      security = metadata["security"]
      assert security["sandbox"] == "none"
      assert security["capabilities"] == []
    end
    
    test "handles different parameter types" do
      defmodule TypeTestTool do
        use RubberDuck.Tool
        
        tool do
          name :type_test
          description "Tool to test different parameter types"
          
          parameter :string_param do
            type :string
            required true
          end
          
          parameter :integer_param do
            type :integer
            required true
          end
          
          parameter :float_param do
            type :float
            required true
          end
          
          parameter :boolean_param do
            type :boolean
            required true
          end
          
          parameter :list_param do
            type :list
            required true
          end
          
          parameter :map_param do
            type :map
            required true
          end
          
          parameter :any_param do
            type :any
            required true
          end
          
          execution do
            handler &TypeTestTool.execute/2
          end
        end
        
        def execute(_params, _context) do
          {:ok, "test"}
        end
      end
      
      schema = JsonSchema.generate(TypeTestTool)
      properties = schema["properties"]
      
      assert properties["string_param"]["type"] == "string"
      assert properties["integer_param"]["type"] == "integer"
      assert properties["float_param"]["type"] == "number"
      assert properties["boolean_param"]["type"] == "boolean"
      assert properties["list_param"]["type"] == "array"
      assert properties["map_param"]["type"] == "object"
      # 'any' type should not have a type restriction
      refute Map.has_key?(properties["any_param"], "type")
    end
    
    test "handles constraints properly" do
      defmodule ConstraintTestTool do
        use RubberDuck.Tool
        
        tool do
          name :constraint_test
          description "Tool to test parameter constraints"
          
          parameter :min_max_string do
            type :string
            required true
            constraints [
              min_length: 5,
              max_length: 50
            ]
          end
          
          parameter :pattern_string do
            type :string
            required true
            constraints [
              pattern: "^[a-zA-Z0-9]+$"
            ]
          end
          
          parameter :enum_param do
            type :string
            required true
            constraints [
              enum: ["option1", "option2", "option3"]
            ]
          end
          
          parameter :numeric_range do
            type :integer
            required true
            constraints [
              min: 1,
              max: 100
            ]
          end
          
          execution do
            handler &ConstraintTestTool.execute/2
          end
        end
        
        def execute(_params, _context) do
          {:ok, "test"}
        end
      end
      
      schema = JsonSchema.generate(ConstraintTestTool)
      properties = schema["properties"]
      
      # Test string length constraints
      min_max = properties["min_max_string"]
      assert min_max["minLength"] == 5
      assert min_max["maxLength"] == 50
      
      # Test pattern constraint
      pattern = properties["pattern_string"]
      assert pattern["pattern"] == "^[a-zA-Z0-9]+$"
      
      # Test enum constraint
      enum_param = properties["enum_param"]
      assert enum_param["enum"] == ["option1", "option2", "option3"]
      
      # Test numeric range
      numeric = properties["numeric_range"]
      assert numeric["minimum"] == 1
      assert numeric["maximum"] == 100
    end
  end
  
  describe "schema validation" do
    test "validates generated schemas are valid JSON Schema" do
      schema = JsonSchema.generate(TestCalculator)
      
      # Basic JSON Schema structure
      assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
      assert is_binary(schema["type"])
      assert is_map(schema["properties"])
      assert is_list(schema["required"])
    end
    
    test "schema can be used to validate tool input" do
      schema = JsonSchema.generate(TestCalculator)
      
      # This would be used with a JSON Schema validator
      # For now, just ensure the schema structure is correct
      assert schema["type"] == "object"
      assert Map.has_key?(schema, "properties")
      assert Map.has_key?(schema, "required")
      assert Map.has_key?(schema, "metadata")
    end
  end
  
  describe "schema export" do
    test "exports schema as JSON string" do
      json_string = JsonSchema.to_json(TestCalculator)
      
      assert is_binary(json_string)
      
      # Should be valid JSON
      decoded = Jason.decode!(json_string)
      assert is_map(decoded)
      assert decoded["title"] == "Calculator Tool"
    end
    
    test "exports schema to file" do
      temp_path = System.tmp_dir!() |> Path.join("test_schema.json")
      
      try do
        assert :ok = JsonSchema.to_file(TestCalculator, temp_path)
        assert File.exists?(temp_path)
        
        # Read and validate content
        content = File.read!(temp_path)
        decoded = Jason.decode!(content)
        assert decoded["title"] == "Calculator Tool"
      after
        File.rm(temp_path)
      end
    end
  end
end