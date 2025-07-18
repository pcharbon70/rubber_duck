defmodule RubberDuck.LLM.ConfigUserAwareTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.LLM.Config
  alias RubberDuck.UserConfig
  
  @valid_user_id "user_123"
  @valid_provider :openai
  @valid_model "gpt-4"
  
  setup do
    # Store original application config
    original_config = Application.get_env(:rubber_duck, :llm, [])
    
    # Set up test application config
    Application.put_env(:rubber_duck, :llm, 
      default_provider: :anthropic,
      providers: [
        %{name: :anthropic, models: ["claude-3-sonnet", "claude-3-haiku"], default_model: "claude-3-sonnet"},
        %{name: :openai, models: ["gpt-4", "gpt-3.5-turbo"], default_model: "gpt-4"}
      ]
    )
    
    on_exit(fn ->
      # Restore original config
      Application.put_env(:rubber_duck, :llm, original_config)
    end)
    
    :ok
  end
  
  describe "get_provider_model/2 with user context" do
    test "returns user's preferred model when available" do
      # Set user's preference
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Get provider model with user context
      assert Config.get_provider_model(@valid_provider, @valid_user_id) == @valid_model
    end
    
    test "falls back to app config when no user preference" do
      # Get provider model without user preference
      assert Config.get_provider_model(:anthropic, "new_user") == "claude-3-sonnet"
      assert Config.get_provider_model(:openai, "new_user") == "gpt-4"
    end
    
    test "falls back to app config when user_id is nil" do
      # Get provider model with nil user_id
      assert Config.get_provider_model(:anthropic, nil) == "claude-3-sonnet"
      assert Config.get_provider_model(:openai, nil) == "gpt-4"
    end
    
    test "handles user with different provider preference" do
      # Set user's preference for different provider
      {:ok, _config} = UserConfig.set_default(@valid_user_id, :anthropic, "claude-3-haiku")
      
      # Get provider model - should use user's preference
      assert Config.get_provider_model(:anthropic, @valid_user_id) == "claude-3-haiku"
      
      # Different provider should still use app config
      assert Config.get_provider_model(:openai, @valid_user_id) == "gpt-4"
    end
  end
  
  describe "get_current_provider_and_model/1 with user context" do
    test "returns user's default when available" do
      # Set user's default
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Get current provider and model
      assert Config.get_current_provider_and_model(@valid_user_id) == {@valid_provider, @valid_model}
    end
    
    test "falls back to app config when no user default" do
      # Get current provider and model without user preference
      assert Config.get_current_provider_and_model("new_user") == {:anthropic, "claude-3-sonnet"}
    end
    
    test "falls back to app config when user_id is nil" do
      # Get current provider and model with nil user_id
      assert Config.get_current_provider_and_model(nil) == {:anthropic, "claude-3-sonnet"}
    end
  end
  
  describe "list_available_models/1 with user context" do
    test "merges user models with app models" do
      # Set user's custom models
      {:ok, _config1} = UserConfig.add_model(@valid_user_id, :openai, "gpt-4-custom")
      {:ok, _config2} = UserConfig.add_model(@valid_user_id, :ollama, "llama2")
      
      # List available models
      models = Config.list_available_models(@valid_user_id)
      
      # Should contain both app and user models
      assert "gpt-4" in models[:openai]
      assert "gpt-3.5-turbo" in models[:openai]
      assert "gpt-4-custom" in models[:openai]
      assert "claude-3-sonnet" in models[:anthropic]
      assert "llama2" in models[:ollama]
    end
    
    test "returns only app models when no user models" do
      # List available models without user models
      models = Config.list_available_models("new_user")
      
      # Should only contain app models
      assert models[:openai] == ["gpt-4", "gpt-3.5-turbo"]
      assert models[:anthropic] == ["claude-3-sonnet", "claude-3-haiku"]
      refute Map.has_key?(models, :ollama)
    end
    
    test "returns app models when user_id is nil" do
      # List available models with nil user_id
      models = Config.list_available_models(nil)
      
      # Should only contain app models
      assert models[:openai] == ["gpt-4", "gpt-3.5-turbo"]
      assert models[:anthropic] == ["claude-3-sonnet", "claude-3-haiku"]
    end
  end
  
  describe "validate_model/3 with user context" do
    test "validates models from both app and user config" do
      # Set user's custom model
      {:ok, _config} = UserConfig.add_model(@valid_user_id, :ollama, "custom-model")
      
      # Validate app models
      assert Config.validate_model(:openai, "gpt-4", @valid_user_id) == :ok
      assert Config.validate_model(:anthropic, "claude-3-sonnet", @valid_user_id) == :ok
      
      # Validate user's custom model
      assert Config.validate_model(:ollama, "custom-model", @valid_user_id) == :ok
    end
    
    test "accepts any model for flexibility" do
      # Even unknown models should be accepted
      assert Config.validate_model(:unknown_provider, "unknown-model", @valid_user_id) == :ok
    end
  end
  
  describe "get_user_default_provider_and_model/1" do
    test "returns user's default configuration" do
      # Set user's default
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Get user default
      assert Config.get_user_default_provider_and_model(@valid_user_id) == {:ok, {@valid_provider, @valid_model}}
    end
    
    test "returns :not_found when no user default" do
      assert Config.get_user_default_provider_and_model("new_user") == :not_found
    end
    
    test "returns :not_found when user_id is nil" do
      assert Config.get_user_default_provider_and_model(nil) == :not_found
    end
  end
  
  describe "get_user_provider_model/2" do
    test "returns user's provider-specific model" do
      # Set user's model for specific provider
      {:ok, _config} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      
      # Get provider model
      assert Config.get_user_provider_model(@valid_user_id, @valid_provider) == {:ok, @valid_model}
    end
    
    test "returns :not_found when no provider config" do
      assert Config.get_user_provider_model(@valid_user_id, :anthropic) == :not_found
    end
    
    test "returns :not_found when user_id is nil" do
      assert Config.get_user_provider_model(nil, @valid_provider) == :not_found
    end
  end
  
  describe "get_user_models/1" do
    test "returns user's models organized by provider" do
      # Set user's models
      {:ok, _config1} = UserConfig.add_model(@valid_user_id, :openai, "gpt-4")
      {:ok, _config2} = UserConfig.add_model(@valid_user_id, :anthropic, "claude-3-sonnet")
      
      # Get user models
      assert {:ok, models} = Config.get_user_models(@valid_user_id)
      assert models[:openai] == ["gpt-4"]
      assert models[:anthropic] == ["claude-3-sonnet"]
    end
    
    test "returns :not_found when no user models" do
      assert Config.get_user_models("new_user") == :not_found
    end
    
    test "returns :not_found when user_id is nil" do
      assert Config.get_user_models(nil) == :not_found
    end
  end
  
  describe "set_user_default/3" do
    test "sets user's default configuration" do
      # Set user default
      assert {:ok, config} = Config.set_user_default(@valid_user_id, @valid_provider, @valid_model)
      assert config.user_id == @valid_user_id
      assert config.provider == @valid_provider
      assert config.model == @valid_model
      assert config.is_default == true
    end
    
    test "returns error for invalid parameters" do
      # Invalid user_id type
      assert_raise FunctionClauseError, fn ->
        Config.set_user_default(123, @valid_provider, @valid_model)
      end
      
      # Invalid provider type
      assert_raise FunctionClauseError, fn ->
        Config.set_user_default(@valid_user_id, "invalid", @valid_model)
      end
      
      # Invalid model type
      assert_raise FunctionClauseError, fn ->
        Config.set_user_default(@valid_user_id, @valid_provider, 123)
      end
    end
  end
  
  describe "integration with existing functionality" do
    test "user preferences don't affect app config behavior" do
      # Set user preference
      {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # App config behavior should remain unchanged
      assert Config.get_provider_model(:anthropic, nil) == "claude-3-sonnet"
      assert Config.get_current_provider_and_model(nil) == {:anthropic, "claude-3-sonnet"}
      
      # Only user-aware calls should be affected
      assert Config.get_provider_model(@valid_provider, @valid_user_id) == @valid_model
      assert Config.get_current_provider_and_model(@valid_user_id) == {@valid_provider, @valid_model}
    end
  end
end