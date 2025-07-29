defmodule RubberDuck.Jido.CloudEvents.ValidatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.CloudEvents.Validator
  
  describe "validate/1" do
    test "validates a minimal valid CloudEvent" do
      event = %{
        "specversion" => "1.0",
        "id" => "test-123",
        "source" => "/test/source",
        "type" => "com.example.test"
      }
      
      assert Validator.validate(event) == :ok
    end
    
    test "validates a complete CloudEvent with optional fields" do
      event = %{
        "specversion" => "1.0",
        "id" => "test-123",
        "source" => "https://example.com/source",
        "type" => "com.example.test",
        "time" => "2025-01-29T10:00:00Z",
        "datacontenttype" => "application/json",
        "dataschema" => "https://example.com/schema",
        "subject" => "test-subject",
        "data" => %{"key" => "value"}
      }
      
      assert Validator.validate(event) == :ok
    end
    
    test "rejects non-map input" do
      assert {:error, [{:error, "event", "must be a map"}]} = Validator.validate("not a map")
      assert {:error, [{:error, "event", "must be a map"}]} = Validator.validate([])
      assert {:error, [{:error, "event", "must be a map"}]} = Validator.validate(nil)
    end
    
    test "reports all missing required fields" do
      assert {:error, errors} = Validator.validate(%{})
      
      assert {:error, "specversion", "required field missing"} in errors
      assert {:error, "id", "required field missing"} in errors
      assert {:error, "source", "required field missing"} in errors
      assert {:error, "type", "required field missing"} in errors
      assert length(errors) == 4
    end
    
    test "validates specversion must be 1.0" do
      event = %{
        "specversion" => "0.3",
        "id" => "test-123",
        "source" => "/test",
        "type" => "test"
      }
      
      assert {:error, errors} = Validator.validate(event)
      assert {:error, "specversion", "must be '1.0', got '0.3'"} in errors
    end
    
    test "validates id must be non-empty string" do
      base_event = %{
        "specversion" => "1.0",
        "source" => "/test",
        "type" => "test"
      }
      
      # Empty string
      assert {:error, errors} = Validator.validate(Map.put(base_event, "id", ""))
      assert {:error, "id", "must not be empty"} in errors
      
      # Non-string
      assert {:error, errors} = Validator.validate(Map.put(base_event, "id", 123))
      assert {:error, "id", "must be a string"} in errors
    end
    
    test "validates source must be valid URI-reference" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "type" => "test"
      }
      
      # Valid sources
      assert :ok = Validator.validate(Map.put(base_event, "source", "/path"))
      assert :ok = Validator.validate(Map.put(base_event, "source", "https://example.com"))
      assert :ok = Validator.validate(Map.put(base_event, "source", "service/component"))
      
      # Invalid sources
      assert {:error, errors} = Validator.validate(Map.put(base_event, "source", ""))
      assert {:error, "source", "must not be empty"} in errors
      
      assert {:error, errors} = Validator.validate(Map.put(base_event, "source", "has spaces"))
      assert {:error, "source", "must be a valid URI-reference"} in errors
    end
    
    test "validates type must be non-empty string" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test"
      }
      
      # Empty string
      assert {:error, errors} = Validator.validate(Map.put(base_event, "type", ""))
      assert {:error, "type", "must not be empty"} in errors
      
      # Non-string
      assert {:error, errors} = Validator.validate(Map.put(base_event, "type", :atom))
      assert {:error, "type", "must be a string"} in errors
    end
    
    test "validates time must be RFC3339 timestamp" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test",
        "type" => "test"
      }
      
      # Valid timestamps
      assert :ok = Validator.validate(Map.put(base_event, "time", "2025-01-29T10:00:00Z"))
      assert :ok = Validator.validate(Map.put(base_event, "time", "2025-01-29T10:00:00.123Z"))
      assert :ok = Validator.validate(Map.put(base_event, "time", "2025-01-29T10:00:00+01:00"))
      
      # Invalid timestamps
      assert {:error, errors} = Validator.validate(Map.put(base_event, "time", "not a timestamp"))
      assert {:error, "time", "must be a valid RFC3339 timestamp"} in errors
      
      assert {:error, errors} = Validator.validate(Map.put(base_event, "time", "2025-01-29"))
      assert {:error, "time", "must be a valid RFC3339 timestamp"} in errors
    end
    
    test "validates datacontenttype must be non-empty string" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test",
        "type" => "test"
      }
      
      # Valid
      assert :ok = Validator.validate(Map.put(base_event, "datacontenttype", "application/json"))
      
      # Invalid
      assert {:error, errors} = Validator.validate(Map.put(base_event, "datacontenttype", ""))
      assert {:error, "datacontenttype", "must be a non-empty string"} in errors
    end
    
    test "validates dataschema must be valid URI" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test",
        "type" => "test"
      }
      
      # Valid
      assert :ok = Validator.validate(Map.put(base_event, "dataschema", "https://example.com/schema"))
      
      # Invalid
      assert {:error, errors} = Validator.validate(Map.put(base_event, "dataschema", "not a uri"))
      assert {:error, "dataschema", "must be a valid URI"} in errors
    end
    
    test "validates cannot have both data and data_base64" do
      event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test",
        "type" => "test",
        "data" => %{"key" => "value"},
        "data_base64" => Base.encode64("binary data")
      }
      
      assert {:error, errors} = Validator.validate(event)
      assert {:error, "data", "cannot have both 'data' and 'data_base64' fields"} in errors
    end
    
    test "validates extension field names" do
      base_event = %{
        "specversion" => "1.0",
        "id" => "123",
        "source" => "/test",
        "type" => "test"
      }
      
      # Valid extension names
      assert :ok = Validator.validate(Map.put(base_event, "myextension", "value"))
      assert :ok = Validator.validate(Map.put(base_event, "ext123", "value"))
      
      # Invalid extension names
      assert {:error, errors} = Validator.validate(Map.put(base_event, "MyExtension", "value"))
      assert {:error, "MyExtension", _} = List.keyfind(errors, "MyExtension", 1)
      
      assert {:error, errors} = Validator.validate(Map.put(base_event, "123ext", "value"))
      assert {:error, "123ext", _} = List.keyfind(errors, "123ext", 1)
      
      assert {:error, errors} = Validator.validate(Map.put(base_event, "verylongextensionnameover20chars", "value"))
      assert {:error, "verylongextensionnameover20chars", _} = List.keyfind(errors, "verylongextensionnameover20chars", 1)
    end
  end
  
  describe "valid?/1" do
    test "returns true for valid events" do
      event = %{
        "specversion" => "1.0",
        "id" => "test-123",
        "source" => "/test/source",
        "type" => "com.example.test"
      }
      
      assert Validator.valid?(event) == true
    end
    
    test "returns false for invalid events" do
      assert Validator.valid?(%{}) == false
      assert Validator.valid?(%{"id" => "123"}) == false
      assert Validator.valid?("not a map") == false
    end
  end
end