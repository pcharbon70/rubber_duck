defmodule RubberDuck.Jido.Signals.Pipeline.SignalNormalizerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Jido.Signals.Pipeline.SignalNormalizer
  
  describe "transform/2" do
    test "normalizes signal structure with string keys" do
      signal = %{
        "type" => "user.created",
        "source" => "test",
        "data" => %{"user_id" => "123"}
      }
      
      assert {:ok, normalized} = SignalNormalizer.transform(signal, [])
      assert normalized.type == "user.created"
      assert normalized.source == "test"
      assert normalized.data == %{"user_id" => "123"}
      assert normalized._normalized == true
    end
    
    test "converts field name variations" do
      signal = %{
        "event_type" => "user.created",
        "event_source" => "test",
        "payload" => %{"id" => "123"}
      }
      
      assert {:ok, normalized} = SignalNormalizer.transform(signal, [])
      assert normalized.type == "user.created"
      assert normalized.source == "test"
      assert normalized.data == %{"id" => "123"}
    end
    
    test "adds missing required fields with defaults" do
      signal = %{
        "type" => "user.created",
        "source" => "test",
        "data" => %{}
      }
      
      assert {:ok, normalized} = SignalNormalizer.transform(signal, [])
      assert normalized.id =~ ~r/^sig_/
      assert normalized.time
      assert normalized.specversion == "1.0"
    end
    
    test "ensures hierarchical type format" do
      signal = %{
        "type" => "created",
        "source" => "test",
        "data" => %{}
      }
      
      assert {:ok, normalized} = SignalNormalizer.transform(signal, [])
      assert normalized.type == "unknown.created"
    end
    
    test "ensures proper source format" do
      signal = %{
        "type" => "user.created",
        "source" => "test",
        "data" => %{}
      }
      
      assert {:ok, normalized} = SignalNormalizer.transform(signal, [])
      assert normalized.source == "unknown:test"
    end
  end
  
  describe "should_transform?/2" do
    test "returns true for unnormalized signals" do
      signal = %{type: "test", source: "test", data: %{}}
      assert SignalNormalizer.should_transform?(signal, [])
    end
    
    test "returns false for already normalized signals" do
      signal = %{type: "test", source: "test", data: %{}, _normalized: true}
      refute SignalNormalizer.should_transform?(signal, [])
    end
  end
end