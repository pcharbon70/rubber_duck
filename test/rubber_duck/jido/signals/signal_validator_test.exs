defmodule RubberDuck.Jido.Signals.SignalValidatorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Signals.SignalValidator
  
  describe "validate/1" do
    test "validates a complete signal" do
      signal = %{
        type: "user.created",
        source: "agent:123",
        data: %{user_id: "u123", name: "John"}
      }
      
      assert {:ok, validated} = SignalValidator.validate(signal)
      assert validated.type == "user.created"
      assert validated.source == "agent:123"
      assert validated.category == :event
      assert Map.has_key?(validated, :time)
      assert Map.has_key?(validated, :id)
    end
    
    test "rejects signal with missing required fields" do
      signal = %{type: "user.created"}
      
      assert {:error, errors} = SignalValidator.validate(signal)
      assert {:missing_field, "source"} in errors
      assert {:missing_field, "data"} in errors
    end
    
    test "rejects signal with invalid type format" do
      signal = %{
        type: "invalid",
        source: "agent:123",
        data: %{}
      }
      
      assert {:error, errors} = SignalValidator.validate(signal)
      assert {:invalid_type_format, _} = Enum.find(errors, fn {type, _} -> type == :invalid_type_format end)
    end
    
    test "validates signal with optional fields" do
      signal = %{
        type: "user.created",
        source: "agent:123",
        data: %{},
        subject: "user:456",
        id: "sig_123"
      }
      
      assert {:ok, validated} = SignalValidator.validate(signal)
      assert validated.subject == "user:456"
      assert validated.id == "sig_123"
    end
    
    test "enriches signal with category" do
      signal = %{
        type: "analysis.request",
        source: "agent:123",
        data: %{}
      }
      
      assert {:ok, validated} = SignalValidator.validate(signal)
      assert validated.category == :request
    end
  end
  
  describe "validate_jido_signal/1" do
    test "validates through Jido.Signal" do
      signal = %{
        type: "user.created",
        source: "agent:123",
        data: %{user_id: "u123"}
      }
      
      # This will use Jido.Signal.new internally
      assert {:ok, _validated} = SignalValidator.validate_jido_signal(signal)
    end
    
    test "rejects invalid Jido signal" do
      signal = %{invalid: "signal"}
      
      assert {:error, errors} = SignalValidator.validate_jido_signal(signal)
      assert [{:jido_signal_invalid, _}] = errors
    end
  end
  
  describe "validate_batch/1" do
    test "validates multiple signals" do
      signals = [
        %{type: "user.created", source: "agent:1", data: %{}},
        %{type: "order.updated", source: "agent:2", data: %{}},
        %{type: "payment.completed", source: "agent:3", data: %{}}
      ]
      
      assert {:ok, validated} = SignalValidator.validate_batch(signals)
      assert length(validated) == 3
    end
    
    test "reports errors for invalid signals in batch" do
      signals = [
        %{type: "user.created", source: "agent:1", data: %{}},
        %{type: "invalid", source: "agent:2"},  # Missing data
        %{type: "order.updated", source: "agent:3", data: %{}}
      ]
      
      assert {:error, result} = SignalValidator.validate_batch(signals)
      assert result.valid_count == 2
      assert result.invalid_count == 1
      assert Map.has_key?(result.errors, 1)
    end
  end
  
  describe "matches_category?/2" do
    test "checks if signal type matches category patterns" do
      assert SignalValidator.matches_category?("user.created", :event)
      assert SignalValidator.matches_category?("analysis.request", :request)
      assert SignalValidator.matches_category?("server.execute", :command)
      assert SignalValidator.matches_category?("data.query", :query)
      assert SignalValidator.matches_category?("system.alert", :notification)
    end
    
    test "rejects mismatched patterns" do
      refute SignalValidator.matches_category?("user.created", :request)
      refute SignalValidator.matches_category?("analysis.request", :event)
    end
  end
  
  describe "suggest_type/2" do
    test "suggests valid type for request category" do
      assert "user.request" = SignalValidator.suggest_type("user", :request)
      assert "analysis.request" = SignalValidator.suggest_type("analysis.request", :request)
    end
    
    test "suggests valid type for event category" do
      assert "user.create.created" = SignalValidator.suggest_type("user.create", :event)
      assert "order.update.updated" = SignalValidator.suggest_type("order.update", :event)
      assert "file.delete.deleted" = SignalValidator.suggest_type("file.delete", :event)
    end
    
    test "suggests valid type for command category" do
      assert "server.execute" = SignalValidator.suggest_type("server", :command)
      assert "process.stop.execute" = SignalValidator.suggest_type("process.stop", :command)
    end
    
    test "suggests valid type for query category" do
      assert "user.query" = SignalValidator.suggest_type("user", :query)
      assert "data.fetch.query" = SignalValidator.suggest_type("data.fetch", :query)
    end
    
    test "suggests valid type for notification category" do
      assert "system.notify" = SignalValidator.suggest_type("system", :notification)
      assert "alert.notify" = SignalValidator.suggest_type("alert", :notification)
    end
  end
end