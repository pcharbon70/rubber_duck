defmodule RubberDuck.CLIClient.AuthTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.CLIClient.Auth
  
  @test_config_dir Path.join(System.tmp_dir!(), "rubber_duck_test_#{:rand.uniform(10000)}")
  @test_config_file Path.join(@test_config_dir, "config.json")
  
  setup do
    # Create test directory
    File.mkdir_p!(@test_config_dir)
    
    # Override config paths for testing
    original_dir = Process.put(:rubber_duck_config_dir, @test_config_dir)
    original_file = Process.put(:rubber_duck_config_file, @test_config_file)
    
    on_exit(fn ->
      # Restore original values
      if original_dir, do: Process.put(:rubber_duck_config_dir, original_dir)
      if original_file, do: Process.put(:rubber_duck_config_file, original_file)
      
      # Clean up test directory
      File.rm_rf!(@test_config_dir)
    end)
    
    :ok
  end
  
  describe "LLM configuration" do
    test "get_llm_config returns nil when no config exists" do
      assert Auth.get_llm_config() == nil
    end
    
    test "get_llm_config returns LLM settings when configured" do
      llm_config = %{
        "default_provider" => "ollama",
        "default_model" => "codellama",
        "providers" => %{
          "ollama" => %{"model" => "codellama"},
          "openai" => %{"model" => "gpt-4"}
        }
      }
      
      config = %{
        "api_key" => "test_key",
        "server_url" => "ws://localhost:5555",
        "llm" => llm_config
      }
      
      File.write!(@test_config_file, Jason.encode!(config))
      
      assert Auth.get_llm_config() == llm_config
    end
    
    test "save_llm_settings updates LLM configuration" do
      # First save basic credentials
      assert :ok = Auth.save_credentials("test_key", "ws://localhost:5555")
      
      # Then update LLM settings
      llm_settings = %{
        "default_provider" => "anthropic",
        "default_model" => "claude-3",
        "providers" => %{
          "anthropic" => %{"model" => "claude-3"}
        }
      }
      
      assert :ok = Auth.save_llm_settings(llm_settings)
      
      # Verify the settings were saved
      assert Auth.get_llm_config() == llm_settings
      
      # Verify credentials are preserved
      assert Auth.get_api_key() == "test_key"
      assert Auth.get_server_url() == "ws://localhost:5555"
    end
    
    test "update_provider_model updates specific provider model" do
      # Set up initial config
      initial_llm = %{
        "default_provider" => "ollama",
        "default_model" => "llama2",
        "providers" => %{
          "ollama" => %{"model" => "llama2"},
          "openai" => %{"model" => "gpt-3.5-turbo"}
        }
      }
      
      config = %{
        "api_key" => "test_key",
        "server_url" => "ws://localhost:5555",
        "llm" => initial_llm
      }
      
      File.write!(@test_config_file, Jason.encode!(config))
      
      # Update specific provider model
      assert :ok = Auth.update_provider_model("openai", "gpt-4")
      
      # Verify the update
      updated_config = Auth.get_llm_config()
      assert updated_config["providers"]["openai"]["model"] == "gpt-4"
      assert updated_config["providers"]["ollama"]["model"] == "llama2"
    end
    
    test "set_default_provider updates default provider" do
      initial_llm = %{
        "default_provider" => "ollama",
        "default_model" => "llama2",
        "providers" => %{
          "ollama" => %{"model" => "llama2"},
          "openai" => %{"model" => "gpt-4"}
        }
      }
      
      config = %{
        "api_key" => "test_key",
        "server_url" => "ws://localhost:5555",
        "llm" => initial_llm
      }
      
      File.write!(@test_config_file, Jason.encode!(config))
      
      # Update default provider
      assert :ok = Auth.set_default_provider("openai")
      
      # Verify the update
      updated_config = Auth.get_llm_config()
      assert updated_config["default_provider"] == "openai"
      assert updated_config["default_model"] == "gpt-4"
    end
    
    test "get_current_model returns model for current provider" do
      llm_config = %{
        "default_provider" => "ollama",
        "default_model" => "codellama",
        "providers" => %{
          "ollama" => %{"model" => "codellama"},
          "openai" => %{"model" => "gpt-4"}
        }
      }
      
      config = %{
        "api_key" => "test_key",
        "server_url" => "ws://localhost:5555",
        "llm" => llm_config
      }
      
      File.write!(@test_config_file, Jason.encode!(config))
      
      assert Auth.get_current_model() == {"ollama", "codellama"}
      assert Auth.get_current_model("openai") == {"openai", "gpt-4"}
      assert Auth.get_current_model("anthropic") == {"anthropic", nil}
    end
  end
end