defmodule RubberDuck.UserConfigTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.UserConfig
  alias RubberDuck.Memory
  
  @valid_user_id "user_123"
  @valid_provider :openai
  @valid_model "gpt-4"
  @invalid_provider :invalid_provider
  
  setup do
    # Create the UserProfile that the UserLLMConfig depends on
    {:ok, _profile} = Memory.UserProfile
      |> Ash.Changeset.for_create(:create, %{user_id: @valid_user_id})
      |> Ash.create()
    
    :ok
  end
  
  describe "set_default/3" do
    test "sets user default LLM configuration" do
      assert {:ok, config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      assert config.user_id == @valid_user_id
      assert config.provider == @valid_provider
      assert config.model == @valid_model
      assert config.is_default == true
    end
    
    test "rejects invalid provider" do
      assert {:error, :invalid_provider} = UserConfig.set_default(@valid_user_id, @invalid_provider, @valid_model)
    end
    
    test "overwrites existing default when setting new default" do
      # Set first default
      assert {:ok, _config1} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Set second default with different provider
      assert {:ok, config2} = UserConfig.set_default(@valid_user_id, :anthropic, "claude-3-sonnet")
      assert config2.provider == :anthropic
      assert config2.model == "claude-3-sonnet"
      assert config2.is_default == true
      
      # Verify first config is no longer default
      {:ok, configs} = UserConfig.get_all_configs(@valid_user_id)
      openai_config = Map.get(configs, :openai)
      anthropic_config = Map.get(configs, :anthropic)
      
      assert openai_config.is_default == false
      assert anthropic_config.is_default == true
    end
  end
  
  describe "add_model/3" do
    test "adds a model to user configuration" do
      assert {:ok, config} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      assert config.user_id == @valid_user_id
      assert config.provider == @valid_provider
      assert config.model == @valid_model
      assert config.is_default == false
    end
    
    test "rejects invalid provider" do
      assert {:error, :invalid_provider} = UserConfig.add_model(@valid_user_id, @invalid_provider, @valid_model)
    end
    
    test "updates existing config when adding model to existing provider" do
      # Add first model
      assert {:ok, _config1} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      
      # Add second model to same provider
      assert {:ok, config2} = UserConfig.add_model(@valid_user_id, @valid_provider, "gpt-3.5-turbo")
      assert config2.model == "gpt-3.5-turbo"
      
      # Verify only one config exists for this provider
      {:ok, configs} = UserConfig.get_all_configs(@valid_user_id)
      assert Map.has_key?(configs, @valid_provider)
      assert configs[@valid_provider].model == "gpt-3.5-turbo"
    end
  end
  
  describe "get_default/1" do
    test "returns user's default configuration" do
      # Set a default
      assert {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Get default
      assert {:ok, default} = UserConfig.get_default(@valid_user_id)
      assert default.provider == @valid_provider
      assert default.model == @valid_model
    end
    
    test "returns error when no default exists" do
      assert {:error, :not_found} = UserConfig.get_default("non_existent_user")
    end
  end
  
  describe "get_all_configs/1" do
    test "returns all user configurations" do
      # Add multiple configurations
      assert {:ok, _config1} = UserConfig.add_model(@valid_user_id, :openai, "gpt-4")
      assert {:ok, _config2} = UserConfig.add_model(@valid_user_id, :anthropic, "claude-3-sonnet")
      
      # Get all configs
      assert {:ok, configs} = UserConfig.get_all_configs(@valid_user_id)
      assert Map.has_key?(configs, :openai)
      assert Map.has_key?(configs, :anthropic)
      
      assert configs[:openai].model == "gpt-4"
      assert configs[:anthropic].model == "claude-3-sonnet"
    end
    
    test "returns empty map when no configurations exist" do
      assert {:ok, configs} = UserConfig.get_all_configs("non_existent_user")
      assert configs == %{}
    end
  end
  
  describe "get_provider_config/2" do
    test "returns configuration for specific provider" do
      # Add a configuration
      assert {:ok, _config} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      
      # Get provider config
      assert {:ok, config} = UserConfig.get_provider_config(@valid_user_id, @valid_provider)
      assert config.model == @valid_model
      assert config.usage_count == 0
      assert is_map(config.metadata)
    end
    
    test "returns error when provider not configured" do
      assert {:error, :not_found} = UserConfig.get_provider_config(@valid_user_id, :anthropic)
    end
  end
  
  describe "remove_provider_config/2" do
    test "removes provider configuration" do
      # Add a configuration
      assert {:ok, _config} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      
      # Verify it exists
      assert {:ok, _config} = UserConfig.get_provider_config(@valid_user_id, @valid_provider)
      
      # Remove it
      assert :ok = UserConfig.remove_provider_config(@valid_user_id, @valid_provider)
      
      # Verify it's gone
      assert {:error, :not_found} = UserConfig.get_provider_config(@valid_user_id, @valid_provider)
    end
    
    test "returns error when provider not configured" do
      assert {:error, :not_found} = UserConfig.remove_provider_config(@valid_user_id, :anthropic)
    end
  end
  
  describe "clear_all_configs/1" do
    test "removes all user configurations" do
      # Add multiple configurations
      assert {:ok, _config1} = UserConfig.add_model(@valid_user_id, :openai, "gpt-4")
      assert {:ok, _config2} = UserConfig.add_model(@valid_user_id, :anthropic, "claude-3-sonnet")
      
      # Verify they exist
      assert {:ok, configs} = UserConfig.get_all_configs(@valid_user_id)
      assert map_size(configs) == 2
      
      # Clear all
      assert :ok = UserConfig.clear_all_configs(@valid_user_id)
      
      # Verify they're gone
      assert {:ok, configs} = UserConfig.get_all_configs(@valid_user_id)
      assert configs == %{}
    end
    
    test "succeeds when no configurations exist" do
      assert :ok = UserConfig.clear_all_configs("non_existent_user")
    end
  end
  
  describe "get_resolved_config/1" do
    test "returns user's configuration when available" do
      # Set a default
      assert {:ok, _config} = UserConfig.set_default(@valid_user_id, @valid_provider, @valid_model)
      
      # Get resolved config
      assert {:ok, resolved} = UserConfig.get_resolved_config(@valid_user_id)
      assert resolved.provider == @valid_provider
      assert resolved.model == @valid_model
    end
    
    test "falls back to global config when no user config exists" do
      # Create a new user profile
      new_user_id = "new_user"
      {:ok, _profile} = Memory.UserProfile
        |> Ash.Changeset.for_create(:create, %{user_id: new_user_id})
        |> Ash.create()
      
      # Mock global config
      Application.put_env(:rubber_duck, :llm, 
        default_provider: :openai,
        providers: [
          %{name: :openai, models: ["gpt-3.5-turbo"], default_model: "gpt-3.5-turbo"}
        ]
      )
      
      # Get resolved config for user without preferences
      assert {:ok, resolved} = UserConfig.get_resolved_config(new_user_id)
      assert resolved.provider == :openai
      assert resolved.model == "gpt-3.5-turbo"
    end
  end
  
  describe "get_usage_stats/1" do
    test "returns usage statistics for user" do
      # Add configurations
      assert {:ok, _config1} = UserConfig.add_model(@valid_user_id, :openai, "gpt-4")
      assert {:ok, _config2} = UserConfig.add_model(@valid_user_id, :anthropic, "claude-3-sonnet")
      
      # Get usage stats
      assert {:ok, stats} = UserConfig.get_usage_stats(@valid_user_id)
      assert stats.total_requests == 0
      assert is_map(stats.providers)
      assert Map.has_key?(stats.providers, :openai)
      assert Map.has_key?(stats.providers, :anthropic)
    end
    
    test "returns empty stats when no configurations exist" do
      assert {:ok, stats} = UserConfig.get_usage_stats("non_existent_user")
      assert stats.total_requests == 0
      assert stats.providers == %{}
    end
  end
  
  # Test with usage tracking
  describe "usage tracking integration" do
    test "increments usage count when provider is used" do
      # Add a configuration
      assert {:ok, _config} = UserConfig.add_model(@valid_user_id, @valid_provider, @valid_model)
      
      # Simulate usage by directly calling Memory functions
      {:ok, [config]} = Memory.get_provider_configs(@valid_user_id, @valid_provider)
      Memory.increment_usage(config, %{})
      
      # Verify usage was incremented
      assert {:ok, updated_config} = UserConfig.get_provider_config(@valid_user_id, @valid_provider)
      assert updated_config.usage_count == 1
    end
  end
end