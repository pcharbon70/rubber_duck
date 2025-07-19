defmodule RubberDuck.Memory.UserLLMConfigTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Memory.UserLLMConfig
  alias RubberDuck.Memory

  @valid_attrs %{
    user_id: "user_123",
    provider: :openai,
    model: "gpt-4",
    is_default: false,
    metadata: %{"custom" => "value"}
  }

  @invalid_attrs %{
    user_id: nil,
    provider: :invalid_provider,
    model: nil
  }

  setup do
    # Create the UserProfile that the UserLLMConfig depends on
    {:ok, _profile} =
      Memory.UserProfile
      |> Ash.Changeset.for_create(:create, %{user_id: @valid_attrs.user_id})
      |> Ash.create()

    :ok
  end

  describe "create/1" do
    test "creates user LLM config with valid attributes" do
      assert {:ok, config} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, @valid_attrs)
               |> Ash.create()

      assert config.user_id == @valid_attrs.user_id
      assert config.provider == @valid_attrs.provider
      assert config.model == @valid_attrs.model
      assert config.is_default == @valid_attrs.is_default
      assert config.usage_count == 0
      assert config.metadata == @valid_attrs.metadata
    end

    test "creates config with default values" do
      minimal_attrs = %{
        user_id: "user_456",
        provider: :anthropic,
        model: "claude-3-sonnet"
      }

      assert {:ok, config} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, minimal_attrs)
               |> Ash.create()

      assert config.is_default == false
      assert config.usage_count == 0
      assert config.metadata == %{}
    end

    test "enforces unique user_id and provider combination" do
      # Create first config
      assert {:ok, _config1} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, @valid_attrs)
               |> Ash.create()

      # Attempt to create duplicate should fail
      assert {:error, %Ash.Error.Invalid{}} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, @valid_attrs)
               |> Ash.create()
    end

    test "validates provider constraints" do
      invalid_provider_attrs = %{@valid_attrs | provider: :invalid_provider}

      assert {:error, %Ash.Error.Invalid{}} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, invalid_provider_attrs)
               |> Ash.create()
    end

    test "validates required fields" do
      assert {:error, %Ash.Error.Invalid{}} =
               UserLLMConfig
               |> Ash.Changeset.for_create(:create, @invalid_attrs)
               |> Ash.create()
    end
  end

  describe "update/2" do
    test "updates user LLM config" do
      # Create config
      {:ok, config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create()

      # Update config
      update_attrs = %{model: "gpt-3.5-turbo", metadata: %{"updated" => true}}

      assert {:ok, updated_config} =
               config
               |> Ash.Changeset.for_update(:update, update_attrs)
               |> Ash.update()

      assert updated_config.model == "gpt-3.5-turbo"
      assert updated_config.metadata == %{"updated" => true}
      # Unchanged
      assert updated_config.user_id == @valid_attrs.user_id
    end
  end

  describe "increment_usage/1" do
    test "increments usage count and updates metadata" do
      # Create config
      {:ok, config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create()

      assert config.usage_count == 0

      # Increment usage
      assert {:ok, updated_config} =
               config
               |> Ash.Changeset.for_update(:increment_usage, %{})
               |> Ash.update()

      assert updated_config.usage_count == 1
      assert updated_config.metadata["usage_count"] == 1
      assert updated_config.metadata["last_used"] != nil
    end

    test "handles multiple increments" do
      # Create config
      {:ok, config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create()

      # Increment multiple times
      {:ok, config} =
        config
        |> Ash.Changeset.for_update(:increment_usage, %{})
        |> Ash.update()

      {:ok, config} =
        config
        |> Ash.Changeset.for_update(:increment_usage, %{})
        |> Ash.update()

      assert config.usage_count == 2
      assert config.metadata["usage_count"] == 2
    end
  end

  describe "get_by_user/1" do
    test "returns all configs for a user" do
      user_id = "user_789"

      # Create UserProfile for this user
      {:ok, _profile} =
        Memory.UserProfile
        |> Ash.Changeset.for_create(:create, %{user_id: user_id})
        |> Ash.create()

      # Create UserProfile for other user
      {:ok, _other_profile} =
        Memory.UserProfile
        |> Ash.Changeset.for_create(:create, %{user_id: "other_user"})
        |> Ash.create()

      # Create multiple configs for the user
      {:ok, config1} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: :openai})
        |> Ash.create()

      {:ok, config2} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: :anthropic})
        |> Ash.create()

      # Create config for different user
      {:ok, _config3} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: "other_user"})
        |> Ash.create()

      # Query by user
      {:ok, configs} =
        UserLLMConfig
        |> Ash.Query.for_read(:get_by_user, %{user_id: user_id})
        |> Ash.read()

      assert length(configs) == 2
      config_ids = Enum.map(configs, & &1.id)
      assert config1.id in config_ids
      assert config2.id in config_ids
    end

    test "returns empty list for user with no configs" do
      {:ok, configs} =
        UserLLMConfig
        |> Ash.Query.for_read(:get_by_user, %{user_id: "nonexistent_user"})
        |> Ash.read()

      assert configs == []
    end
  end

  describe "get_user_default/1" do
    test "returns user's default configuration" do
      user_id = "user_abc"

      # Create non-default config
      {:ok, _config1} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: :openai, is_default: false})
        |> Ash.create()

      # Create default config
      {:ok, default_config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: :anthropic, is_default: true})
        |> Ash.create()

      # Query default
      {:ok, config} =
        UserLLMConfig
        |> Ash.Query.for_read(:get_user_default, %{user_id: user_id})
        |> Ash.read_one()

      assert config.id == default_config.id
      assert config.is_default == true
    end

    test "returns nil when no default exists" do
      {:ok, config} =
        UserLLMConfig
        |> Ash.Query.for_read(:get_user_default, %{user_id: "nonexistent_user"})
        |> Ash.read_one()

      assert config == nil
    end
  end

  describe "get_by_user_and_provider/2" do
    test "returns configs for specific user and provider" do
      user_id = "user_def"
      provider = :openai

      # Create config for user and provider
      {:ok, target_config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: provider})
        |> Ash.create()

      # Create config for same user but different provider
      {:ok, _other_config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{@valid_attrs | user_id: user_id, provider: :anthropic})
        |> Ash.create()

      # Query by user and provider
      {:ok, configs} =
        UserLLMConfig
        |> Ash.Query.for_read(:get_by_user_and_provider, %{user_id: user_id, provider: provider})
        |> Ash.read()

      assert length(configs) == 1
      assert hd(configs).id == target_config.id
    end
  end

  describe "set_user_default action" do
    test "creates new config when none exists" do
      user_id = "user_ghi"
      provider = :openai
      model = "gpt-4"

      # Use the custom action
      assert {:ok, config} =
               UserLLMConfig
               |> Ash.Changeset.for_action(:set_user_default, %{user_id: user_id, provider: provider, model: model})
               |> Ash.create()

      assert config.user_id == user_id
      assert config.provider == provider
      assert config.model == model
      assert config.is_default == true
    end

    test "updates existing config when it exists" do
      user_id = "user_jkl"
      provider = :openai

      # Create initial config
      {:ok, original_config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, %{
          @valid_attrs
          | user_id: user_id,
            provider: provider,
            model: "gpt-3.5-turbo"
        })
        |> Ash.create()

      # Update via set_user_default
      new_model = "gpt-4"

      assert {:ok, updated_config} =
               UserLLMConfig
               |> Ash.Changeset.for_action(:set_user_default, %{user_id: user_id, provider: provider, model: new_model})
               |> Ash.create()

      assert updated_config.id == original_config.id
      assert updated_config.model == new_model
      assert updated_config.is_default == true
    end
  end

  describe "calculations" do
    test "is_recently_used calculation" do
      # Create config and increment usage
      {:ok, config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create()

      {:ok, config} =
        config
        |> Ash.Changeset.for_update(:increment_usage, %{})
        |> Ash.update()

      # Load with calculation - get the config by ID
      {:ok, config_with_calc} =
        UserLLMConfig
        |> Ash.Query.load(:is_recently_used)
        |> Ash.get(config.id)

      # Since we just used it, it should be recently used
      assert config_with_calc.is_recently_used == true
    end

    test "provider_string calculation" do
      # Create config
      {:ok, config} =
        UserLLMConfig
        |> Ash.Changeset.for_create(:create, @valid_attrs)
        |> Ash.create()

      # Load with calculation - get the config by ID
      {:ok, config_with_calc} =
        UserLLMConfig
        |> Ash.Query.load(:provider_string)
        |> Ash.get(config.id)

      assert config_with_calc.provider_string == "openai"
    end
  end

  describe "Memory domain integration" do
    test "Memory domain functions work correctly" do
      user_id = "user_memory_test"
      provider = :openai
      model = "gpt-4"

      # Test set_user_default via Memory domain
      assert {:ok, config} = Memory.set_user_default(user_id, provider, model)
      assert config.user_id == user_id
      assert config.provider == provider
      assert config.model == model

      # Test get_user_default via Memory domain
      assert {:ok, default_config} = Memory.get_user_default(user_id)
      assert default_config.id == config.id

      # Test get_user_configs via Memory domain
      assert {:ok, configs} = Memory.get_user_configs(user_id)
      assert length(configs) == 1
      assert hd(configs).id == config.id

      # Test get_provider_configs via Memory domain
      assert {:ok, provider_configs} = Memory.get_provider_configs(user_id, provider)
      assert length(provider_configs) == 1
      assert hd(provider_configs).id == config.id
    end
  end
end
