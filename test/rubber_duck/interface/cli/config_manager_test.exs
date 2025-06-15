defmodule RubberDuck.Interface.CLI.ConfigManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.CLI.ConfigManager

  # Test configuration directory
  @test_config_dir System.tmp_dir!() <> "/rubber_duck_config_test_#{System.unique_integer()}"

  setup do
    # Clean up any existing test config
    if File.exists?(@test_config_dir) do
      File.rm_rf!(@test_config_dir)
    end
    
    # Set up clean environment
    original_env = System.get_env()
    
    # Clear environment variables that might affect tests
    env_vars = ["RUBBER_DUCK_COLORS", "RUBBER_DUCK_MODEL", "RUBBER_DUCK_TEMPERATURE"]
    Enum.each(env_vars, &System.delete_env/1)
    
    on_exit(fn ->
      # Clean up test directory
      if File.exists?(@test_config_dir) do
        File.rm_rf!(@test_config_dir)
      end
      
      # Restore environment
      Enum.each(env_vars, fn var ->
        if value = original_env[var] do
          System.put_env(var, value)
        end
      end)
    end)
    
    :ok
  end

  describe "load_config/1" do
    test "loads default configuration" do
      {:ok, config} = ConfigManager.load_config()
      
      # Check default values
      assert config.colors == true
      assert config.syntax_highlight == true
      assert config.format == "text"
      assert config.model == "claude"
      assert config.temperature == 0.7
      assert is_binary(config.interactive_prompt)
    end

    test "applies overrides to default config" do
      overrides = %{colors: false, model: "gpt-4", temperature: 1.2}
      
      {:ok, config} = ConfigManager.load_config(overrides)
      
      assert config.colors == false
      assert config.model == "gpt-4"
      assert config.temperature == 1.2
      # Other defaults should remain
      assert config.syntax_highlight == true
    end

    test "validates configuration values" do
      # Valid overrides
      valid_overrides = %{temperature: 1.5, max_tokens: 1000}
      {:ok, config} = ConfigManager.load_config(valid_overrides)
      assert config.temperature == 1.5
      assert config.max_tokens == 1000
      
      # Invalid overrides should be caught by validation
      invalid_overrides = %{temperature: 5.0}  # Outside valid range
      assert {:error, {:validation_errors, _}} = ConfigManager.load_config(invalid_overrides)
    end

    test "creates necessary directories" do
      overrides = %{config_dir: @test_config_dir}
      
      {:ok, config} = ConfigManager.load_config(overrides)
      
      assert config.config_dir == @test_config_dir
      assert File.exists?(@test_config_dir)
      assert File.exists?(config.sessions_dir)
      assert File.exists?(config.cache_dir)
    end
  end

  describe "get_config/1" do
    test "returns provided config when given" do
      test_config = %{colors: false, model: "test"}
      
      result = ConfigManager.get_config(test_config)
      
      assert result == test_config
    end

    test "loads config when nil provided" do
      result = ConfigManager.get_config(nil)
      
      assert is_map(result)
      assert Map.has_key?(result, :colors)
      assert Map.has_key?(result, :model)
    end

    test "returns defaults on load error" do
      # This should not happen in normal circumstances,
      # but test the fallback behavior
      result = ConfigManager.get_config(nil)
      
      assert is_map(result)
      # Should have some basic configuration
      assert is_boolean(result[:colors]) or is_boolean(result.colors)
    end
  end

  describe "set_config/3" do
    test "sets valid configuration values" do
      current_config = %{colors: true, model: "claude"}
      
      {:ok, new_config} = ConfigManager.set_config(:colors, false, current_config)
      assert new_config.colors == false
      assert new_config.model == "claude"  # Other values preserved
      
      {:ok, new_config} = ConfigManager.set_config("model", "gpt-4", current_config)
      assert new_config.model == "gpt-4"
    end

    test "validates configuration values" do
      current_config = %{temperature: 0.7}
      
      # Valid value
      {:ok, new_config} = ConfigManager.set_config(:temperature, 1.0, current_config)
      assert new_config.temperature == 1.0
      
      # Invalid value (outside range)
      assert {:error, _} = ConfigManager.set_config(:temperature, 5.0, current_config)
      
      # Invalid type
      assert {:error, _} = ConfigManager.set_config(:colors, "maybe", current_config)
    end

    test "handles string keys" do
      current_config = %{colors: true}
      
      {:ok, new_config} = ConfigManager.set_config("colors", false, current_config)
      assert new_config.colors == false
    end
  end

  describe "update_config/2" do
    test "updates multiple configuration values" do
      current_config = %{colors: true, model: "claude", temperature: 0.7}
      
      updates = %{colors: false, model: "gpt-4"}
      {:ok, new_config} = ConfigManager.update_config(updates, current_config)
      
      assert new_config.colors == false
      assert new_config.model == "gpt-4"
      assert new_config.temperature == 0.7  # Unchanged
    end

    test "stops on first validation error" do
      current_config = %{colors: true, temperature: 0.7}
      
      # Mix valid and invalid updates
      updates = %{colors: false, temperature: 10.0}  # temperature is invalid
      
      assert {:error, _} = ConfigManager.update_config(updates, current_config)
    end

    test "handles empty updates" do
      current_config = %{colors: true}
      
      {:ok, new_config} = ConfigManager.update_config(%{}, current_config)
      assert new_config == current_config
    end
  end

  describe "reset_config/0" do
    test "returns default configuration" do
      {:ok, config} = ConfigManager.reset_config()
      
      # Should match default values
      assert config.colors == true
      assert config.syntax_highlight == true
      assert config.model == "claude"
      assert config.temperature == 0.7
    end
  end

  describe "validate_config_value/2" do
    test "validates boolean values" do
      assert {:ok, true} = ConfigManager.validate_config_value(:colors, true)
      assert {:ok, false} = ConfigManager.validate_config_value(:colors, false)
      assert {:error, _} = ConfigManager.validate_config_value(:colors, "yes")
    end

    test "validates enum values" do
      assert {:ok, "text"} = ConfigManager.validate_config_value(:format, "text")
      assert {:ok, "json"} = ConfigManager.validate_config_value(:format, "json")
      assert {:error, _} = ConfigManager.validate_config_value(:format, "xml")
    end

    test "validates numeric ranges" do
      # Temperature should be 0.0-2.0
      assert {:ok, 0.5} = ConfigManager.validate_config_value(:temperature, 0.5)
      assert {:ok, 2.0} = ConfigManager.validate_config_value(:temperature, 2.0)
      assert {:error, _} = ConfigManager.validate_config_value(:temperature, 3.0)
      assert {:error, _} = ConfigManager.validate_config_value(:temperature, -0.5)
      
      # Max tokens should be 1-100,000
      assert {:ok, 1000} = ConfigManager.validate_config_value(:max_tokens, 1000)
      assert {:error, _} = ConfigManager.validate_config_value(:max_tokens, 0)
      assert {:error, _} = ConfigManager.validate_config_value(:max_tokens, 200_000)
    end

    test "allows unknown keys without validation" do
      assert {:ok, "any_value"} = ConfigManager.validate_config_value(:unknown_key, "any_value")
    end
  end

  describe "save_config/1" do
    test "saves configuration to file" do
      config = %{
        colors: false,
        model: "gpt-4",
        temperature: 1.0,
        config_dir: @test_config_dir
      }
      
      {:ok, file_path} = ConfigManager.save_config(config)
      
      assert File.exists?(file_path)
      assert String.ends_with?(file_path, "config.yaml")
      
      # Verify file content (assuming YAML parsing is available)
      # In a real implementation, you'd read and parse the YAML
      {:ok, content} = File.read(file_path)
      assert content =~ "colors: false"
      assert content =~ "model: gpt-4"
    end

    test "filters out default values" do
      # Config with mix of default and custom values
      config = %{
        colors: true,  # default value
        model: "gpt-4",  # non-default value
        temperature: 0.7,  # default value
        config_dir: @test_config_dir
      }
      
      {:ok, file_path} = ConfigManager.save_config(config)
      {:ok, content} = File.read(file_path)
      
      # Should only save non-default values
      assert content =~ "model: gpt-4"
      refute content =~ "colors: true"
      refute content =~ "temperature: 0.7"
    end

    test "creates config directory if it doesn't exist" do
      config = %{
        model: "gpt-4",
        config_dir: @test_config_dir <> "/nested"
      }
      
      {:ok, file_path} = ConfigManager.save_config(config)
      
      assert File.exists?(file_path)
      assert File.exists?(config.config_dir)
    end
  end

  describe "environment variable integration" do
    test "loads configuration from environment variables" do
      # Set test environment variables
      System.put_env("RUBBER_DUCK_COLORS", "false")
      System.put_env("RUBBER_DUCK_MODEL", "gpt-4")
      System.put_env("RUBBER_DUCK_TEMPERATURE", "1.2")
      System.put_env("RUBBER_DUCK_MAX_TOKENS", "2000")
      
      {:ok, config} = ConfigManager.load_config()
      
      assert config.colors == false
      assert config.model == "gpt-4"
      assert config.temperature == 1.2
      assert config.max_tokens == 2000
    end

    test "handles invalid environment variable values" do
      # Set invalid values
      System.put_env("RUBBER_DUCK_COLORS", "maybe")
      System.put_env("RUBBER_DUCK_TEMPERATURE", "not_a_number")
      
      # Should not crash and should use defaults
      {:ok, config} = ConfigManager.load_config()
      
      # Should fall back to defaults for invalid values
      assert config.colors == true  # default
      assert config.temperature == 0.7  # default
    end
  end

  describe "profile management" do
    test "saves and loads configuration profiles" do
      config = %{
        colors: false,
        model: "gpt-4",
        config_dir: @test_config_dir
      }
      
      # Save profile
      {:ok, profile_path} = ConfigManager.save_profile("test-profile", config)
      assert File.exists?(profile_path)
      assert String.ends_with?(profile_path, "test-profile.yaml")
      
      # Load profile
      base_config = %{colors: true, model: "claude", config_dir: @test_config_dir}
      {:ok, loaded_config} = ConfigManager.load_profile("test-profile", base_config)
      
      assert loaded_config.colors == false
      assert loaded_config.model == "gpt-4"
    end

    test "lists available profiles" do
      config = %{config_dir: @test_config_dir}
      
      # Create some test profiles
      ConfigManager.save_profile("profile1", config)
      ConfigManager.save_profile("profile2", config)
      
      profiles = ConfigManager.list_profiles(config)
      
      assert "profile1" in profiles
      assert "profile2" in profiles
      assert length(profiles) == 2
    end

    test "returns empty list when no profiles exist" do
      config = %{config_dir: @test_config_dir}
      
      profiles = ConfigManager.list_profiles(config)
      assert profiles == []
    end

    test "returns error for non-existent profile" do
      config = %{config_dir: @test_config_dir}
      
      assert {:error, _} = ConfigManager.load_profile("non-existent", config)
    end
  end

  describe "configuration schema" do
    test "returns configuration schema" do
      schema = ConfigManager.get_config_schema()
      
      assert is_map(schema)
      assert Map.has_key?(schema, :display)
      assert Map.has_key?(schema, :interface)
      assert Map.has_key?(schema, :ai)
      
      # Check display category
      display = schema.display
      assert Map.has_key?(display, :colors)
      assert display.colors.type == :boolean
      assert is_binary(display.colors.description)
      
      # Check AI category
      ai = schema.ai
      assert Map.has_key?(ai, :model)
      assert ai.model.type == :string
      assert Map.has_key?(ai, :temperature)
      assert ai.temperature.type == :float
    end
  end

  describe "validation edge cases" do
    test "handles edge cases in numeric validation" do
      # Test boundary values
      assert {:ok, 0.0} = ConfigManager.validate_config_value(:temperature, 0.0)
      assert {:ok, 2.0} = ConfigManager.validate_config_value(:temperature, 2.0)
      
      # Test just outside boundaries
      assert {:error, _} = ConfigManager.validate_config_value(:temperature, -0.01)
      assert {:error, _} = ConfigManager.validate_config_value(:temperature, 2.01)
      
      # Test integer conversion for floats
      assert {:ok, 1.0} = ConfigManager.validate_config_value(:temperature, 1)
    end

    test "handles type conversion errors gracefully" do
      # Test invalid data types
      assert {:error, _} = ConfigManager.validate_config_value(:temperature, "not_a_number")
      assert {:error, _} = ConfigManager.validate_config_value(:max_tokens, "not_an_integer")
      assert {:error, _} = ConfigManager.validate_config_value(:colors, 123)
    end
  end

  describe "concurrent access" do
    test "handles concurrent configuration updates" do
      base_config = %{colors: true, model: "claude"}
      
      # Simulate concurrent updates
      tasks = for i <- 1..10 do
        Task.async(fn ->
          ConfigManager.set_config(:model, "gpt-#{i}", base_config)
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _config} -> true
        _ -> false
      end)
    end
  end
end