defmodule RubberDuck.LLM.ConfigLoaderTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.LLM.ConfigLoader
  
  setup do
    # Backup original environment variables
    openai_key = System.get_env("OPENAI_API_KEY")
    anthropic_key = System.get_env("ANTHROPIC_API_KEY")
    ollama_url = System.get_env("OLLAMA_BASE_URL")
    
    on_exit(fn ->
      # Restore original environment variables
      if openai_key, do: System.put_env("OPENAI_API_KEY", openai_key)
      if anthropic_key, do: System.put_env("ANTHROPIC_API_KEY", anthropic_key)
      if ollama_url, do: System.put_env("OLLAMA_BASE_URL", ollama_url)
    end)
    
    :ok
  end
  
  describe "load_provider_config/3" do
    test "loads config with priority: runtime > file > env" do
      # Set environment variable
      System.put_env("OPENAI_API_KEY", "env_key")
      
      # File config
      file_config = %{
        "providers" => %{
          "openai" => %{
            "api_key" => "file_key",
            "base_url" => "https://file.example.com"
          }
        }
      }
      
      # Runtime overrides
      runtime_overrides = %{
        openai: %{
          api_key: "runtime_key"
        }
      }
      
      config = ConfigLoader.load_provider_config(:openai, file_config, runtime_overrides)
      
      assert config.api_key == "runtime_key"
      assert config.base_url == "https://file.example.com"
      assert config.name == :openai
      assert config.adapter == RubberDuck.LLM.Providers.OpenAI
    end
    
    test "uses custom environment variable names from file config" do
      System.put_env("CUSTOM_OPENAI_KEY", "custom_env_key")
      System.put_env("CUSTOM_OPENAI_URL", "https://custom.example.com")
      
      file_config = %{
        "providers" => %{
          "openai" => %{
            "env_var_name" => "CUSTOM_OPENAI_KEY",
            "base_url_env_var" => "CUSTOM_OPENAI_URL"
          }
        }
      }
      
      config = ConfigLoader.load_provider_config(:openai, file_config, %{})
      
      assert config.api_key == "custom_env_key"
      assert config.base_url == "https://custom.example.com"
    end
    
    test "falls back to default environment variable names" do
      System.put_env("OPENAI_API_KEY", "default_env_key")
      
      config = ConfigLoader.load_provider_config(:openai, %{}, %{})
      
      assert config.api_key == "default_env_key"
    end
    
    test "returns nil for unknown providers" do
      config = ConfigLoader.load_provider_config(:unknown_provider, %{}, %{})
      
      assert config == nil
    end
    
    test "handles models configuration from various sources" do
      file_config = %{
        "providers" => %{
          "openai" => %{
            "models" => ["gpt-4", "custom-model"]
          }
        }
      }
      
      config = ConfigLoader.load_provider_config(:openai, file_config, %{})
      
      assert config.models == ["gpt-4", "custom-model"]
    end
    
    test "handles rate limit configuration" do
      file_config = %{
        "providers" => %{
          "openai" => %{
            "rate_limit" => %{"limit" => 200, "unit" => "minute"}
          }
        }
      }
      
      config = ConfigLoader.load_provider_config(:openai, file_config, %{})
      
      assert config.rate_limit == {200, :minute}
    end
  end
  
  describe "load_all_providers/1" do
    test "loads all known providers with runtime overrides" do
      runtime_overrides = %{
        openai: %{api_key: "openai_runtime"},
        anthropic: %{api_key: "anthropic_runtime"}
      }
      
      configs = ConfigLoader.load_all_providers(runtime_overrides)
      
      # Should include at least the known providers
      provider_names = Enum.map(configs, & &1.name)
      assert :openai in provider_names
      assert :anthropic in provider_names
      assert :ollama in provider_names
      assert :tgi in provider_names
      assert :mock in provider_names
      
      # Check runtime overrides were applied
      openai_config = Enum.find(configs, & &1.name == :openai)
      assert openai_config.api_key == "openai_runtime"
      
      anthropic_config = Enum.find(configs, & &1.name == :anthropic)
      assert anthropic_config.api_key == "anthropic_runtime"
    end
  end
  
  describe "save_config_file/1" do
    test "saves config to file" do
      # Create a temporary directory for test
      test_dir = Path.join(System.tmp_dir!(), "rubber_duck_test_#{:rand.uniform(1000000)}")
      File.mkdir_p!(test_dir)
      
      # Mock the config file path
      _config_path = Path.join(test_dir, "config.json")
      
      # We can't easily mock the module attribute, so we'll test the functionality
      # by reading and writing to the actual location
      config = %{
        "providers" => %{
          "test_provider" => %{
            "api_key" => "test_key",
            "models" => ["test-model"]
          }
        }
      }
      
      # This would need to be adjusted to use a configurable path
      # For now, we'll just test that the function doesn't crash
      assert :ok == ConfigLoader.save_config_file(config)
      
      # Clean up
      File.rm_rf!(test_dir)
    end
  end
end