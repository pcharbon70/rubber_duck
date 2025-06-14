defmodule RubberDuck.LLMAbstraction.ProviderTest do
  use ExUnit.Case, async: true

  alias RubberDuck.LLMAbstraction.Provider

  describe "validate_required_keys/2" do
    test "returns :ok when all required keys are present" do
      config = %{api_key: "test", model: "gpt-4"}
      assert :ok = Provider.validate_required_keys(config, [:api_key, :model])
    end

    test "returns error when required keys are missing" do
      config = %{api_key: "test"}
      assert {:error, {:missing_required_keys, [:model, :endpoint]}} = 
        Provider.validate_required_keys(config, [:api_key, :model, :endpoint])
    end

    test "works with atom and string keys" do
      config = %{api_key: "test", model: "gpt-4"}
      assert :ok = Provider.validate_required_keys(config, [:api_key, :model])
    end
  end

  describe "extract_options/2" do
    test "merges options with defaults" do
      opts = [temperature: 0.8, max_tokens: 100]
      defaults = [temperature: 0.7, max_tokens: 150, model: "default"]
      
      result = Provider.extract_options(opts, defaults)
      
      assert result[:temperature] == 0.8
      assert result[:max_tokens] == 100
      assert result[:model] == "default"
    end

    test "returns defaults when no options provided" do
      defaults = [temperature: 0.7, max_tokens: 150]
      result = Provider.extract_options([], defaults)
      
      assert result == defaults
    end
  end
end