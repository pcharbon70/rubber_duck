defmodule RubberDuck.LLM.ProviderConfigTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LLM.ProviderConfig
  
  describe "apply_overrides/2" do
    setup do
      config = %ProviderConfig{
        name: :openai,
        adapter: RubberDuck.LLM.Providers.OpenAI,
        api_key: "original_key",
        base_url: "https://original.example.com",
        models: ["gpt-4"],
        priority: 1,
        rate_limit: {100, :minute},
        max_retries: 3,
        timeout: 30_000,
        headers: %{"original" => "header"},
        options: [original: "option"]
      }
      
      {:ok, config: config}
    end
    
    test "applies api_key override", %{config: config} do
      overrides = %{api_key: "new_key"}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.api_key == "new_key"
      assert updated.runtime_overrides == overrides
    end
    
    test "applies base_url override", %{config: config} do
      overrides = %{base_url: "https://new.example.com"}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.base_url == "https://new.example.com"
    end
    
    test "applies models override", %{config: config} do
      overrides = %{models: ["gpt-4-turbo", "gpt-3.5"]}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.models == ["gpt-4-turbo", "gpt-3.5"]
    end
    
    test "applies numeric overrides", %{config: config} do
      overrides = %{
        priority: 2,
        max_retries: 5,
        timeout: 60_000
      }
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.priority == 2
      assert updated.max_retries == 5
      assert updated.timeout == 60_000
    end
    
    test "applies rate_limit override", %{config: config} do
      overrides = %{rate_limit: {200, :hour}}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.rate_limit == {200, :hour}
    end
    
    test "merges headers", %{config: config} do
      overrides = %{headers: %{"new" => "header", "another" => "value"}}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.headers == %{
        "original" => "header",
        "new" => "header",
        "another" => "value"
      }
    end
    
    test "merges options", %{config: config} do
      overrides = %{options: [new: "option", another: "value"]}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert Keyword.get(updated.options, :original) == "option"
      assert Keyword.get(updated.options, :new) == "option"
      assert Keyword.get(updated.options, :another) == "value"
    end
    
    test "ignores nil values in overrides", %{config: config} do
      overrides = %{api_key: nil, base_url: "https://new.example.com"}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.api_key == "original_key"  # Not overridden
      assert updated.base_url == "https://new.example.com"  # Overridden
    end
    
    test "stores runtime_overrides", %{config: config} do
      overrides = %{api_key: "new_key", custom: "value"}
      updated = ProviderConfig.apply_overrides(config, overrides)
      
      assert updated.runtime_overrides == overrides
    end
  end
end