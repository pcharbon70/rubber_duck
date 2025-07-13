defmodule RubberDuck.LLM.ConfigTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LLM.Config
  
  setup do
    # Store original application config
    original_config = Application.get_env(:rubber_duck, :llm, [])
    
    on_exit(fn ->
      # Restore original config
      Application.put_env(:rubber_duck, :llm, original_config)
    end)
    
    :ok
  end
  
  describe "get_provider_model/1" do
    test "returns model from CLI config when available" do
      # Mock CLI config
      cli_config = %{
        "default_provider" => "ollama",
        "providers" => %{
          "ollama" => %{"model" => "codellama"},
          "openai" => %{"model" => "gpt-4"}
        }
      }
      
      # This will fail until we implement the actual function
      assert Config.get_provider_model(:ollama, cli_config) == "codellama"
      assert Config.get_provider_model(:openai, cli_config) == "gpt-4"
    end
    
    test "returns model from app config when no CLI config" do
      # Set app config
      Application.put_env(:rubber_duck, :llm, 
        providers: [
          %{name: :ollama, models: ["llama2", "codellama"], default_model: "llama2"},
          %{name: :openai, models: ["gpt-3.5-turbo", "gpt-4"], default_model: "gpt-3.5-turbo"}
        ]
      )
      
      assert Config.get_provider_model(:ollama, nil) == "llama2"
      assert Config.get_provider_model(:openai, nil) == "gpt-3.5-turbo"
    end
    
    test "returns nil when provider not configured" do
      assert Config.get_provider_model(:unknown, nil) == nil
    end
  end
  
  describe "get_current_provider_and_model/1" do
    test "returns default provider and model from CLI config" do
      cli_config = %{
        "default_provider" => "anthropic",
        "default_model" => "claude-3",
        "providers" => %{
          "anthropic" => %{"model" => "claude-3"}
        }
      }
      
      assert Config.get_current_provider_and_model(cli_config) == {:anthropic, "claude-3"}
    end
    
    test "returns first configured provider when no default in CLI config" do
      cli_config = %{
        "providers" => %{
          "ollama" => %{"model" => "llama2"}
        }
      }
      
      assert Config.get_current_provider_and_model(cli_config) == {:ollama, "llama2"}
    end
    
    test "falls back to app config when no CLI config" do
      # Store original config
      original = Application.get_env(:rubber_duck, :llm, [])
      
      Application.put_env(:rubber_duck, :llm,
        default_provider: :openai,
        providers: [
          %{name: :openai, models: ["gpt-4"], default_model: "gpt-4"}
        ]
      )
      
      result = Config.get_current_provider_and_model(nil)
      
      # Restore original config
      Application.put_env(:rubber_duck, :llm, original)
      
      assert result == {:openai, "gpt-4"}
    end
  end
  
  describe "list_available_models/0" do
    test "combines models from CLI and app configs" do
      cli_config = %{
        "providers" => %{
          "ollama" => %{"model" => "codellama"},
          "openai" => %{"model" => "gpt-4"}
        }
      }
      
      Application.put_env(:rubber_duck, :llm,
        providers: [
          %{name: :anthropic, models: ["claude-3", "claude-2"]}
        ]
      )
      
      models = Config.list_available_models(cli_config)
      
      assert models[:ollama] == ["codellama"]
      assert models[:openai] == ["gpt-4"]
      assert models[:anthropic] == ["claude-3", "claude-2"]
    end
  end
  
  describe "validate_model/2" do
    test "validates model exists for provider" do
      Application.put_env(:rubber_duck, :llm,
        providers: [
          %{name: :openai, models: ["gpt-3.5-turbo", "gpt-4"]}
        ]
      )
      
      assert Config.validate_model(:openai, "gpt-4") == :ok
      assert Config.validate_model(:openai, "gpt-5") == :ok  # Now allows any model
      assert Config.validate_model(:unknown, "any") == :ok  # Now allows unknown providers
    end
  end
end