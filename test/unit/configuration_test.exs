defmodule ConfigurationTest do
  @moduledoc """
  Unit tests for configuration loading and environment-specific settings.
  """
  
  use ExUnit.Case, async: true

  describe "base configuration loading" do
    test "all apps have required base configuration" do
      # Test that each app has its base configuration loaded
      assert Application.get_all_env(:rubber_duck_core) != []
      assert Application.get_all_env(:rubber_duck_storage) != []
      assert Application.get_all_env(:rubber_duck_engines) != []
      assert Application.get_all_env(:rubber_duck_web) != []
    end

    test "configuration validation passes" do
      # Test that our configuration validation module works
      assert_no_exception(fn ->
        RubberDuckCore.Config.validate!()
      end)
    end

    test "environment helpers work correctly" do
      # Test environment detection
      assert RubberDuckCore.Environment.current() == :test
      assert RubberDuckCore.Environment.test?() == true
      assert RubberDuckCore.Environment.dev?() == false
      assert RubberDuckCore.Environment.prod?() == false
    end
  end

  describe "rubber_duck_core configuration" do
    test "has required configuration keys" do
      config = Application.get_all_env(:rubber_duck_core)
      
      assert Keyword.has_key?(config, :ecto_repos)
      assert Keyword.has_key?(config, :pubsub)
      assert Keyword.has_key?(config, :max_conversation_messages)
      assert Keyword.has_key?(config, :conversation_retention_days)
    end

    test "configuration values are valid types" do
      max_messages = Application.get_env(:rubber_duck_core, :max_conversation_messages)
      retention_days = Application.get_env(:rubber_duck_core, :conversation_retention_days)
      pubsub_config = Application.get_env(:rubber_duck_core, :pubsub)
      
      assert is_integer(max_messages) and max_messages > 0
      assert is_integer(retention_days) and retention_days > 0
      assert is_list(pubsub_config)
      assert Keyword.has_key?(pubsub_config, :name)
    end

    test "test environment has appropriate values" do
      # In test environment, we should have smaller limits
      max_messages = Application.get_env(:rubber_duck_core, :max_conversation_messages)
      retention_days = Application.get_env(:rubber_duck_core, :conversation_retention_days)
      
      # Test config should have smaller values than production
      assert max_messages <= 1000  # Should be reasonable for tests
      assert retention_days <= 90  # Should not be too large for tests
    end
  end

  describe "rubber_duck_storage configuration" do
    test "has required configuration keys" do
      config = Application.get_all_env(:rubber_duck_storage)
      
      assert Keyword.has_key?(config, :ecto_repos)
      assert Keyword.has_key?(config, :cache_ttl)
      assert Keyword.has_key?(config, :cache_max_size)
    end

    test "configuration values are valid types" do
      cache_ttl = Application.get_env(:rubber_duck_storage, :cache_ttl)
      cache_max_size = Application.get_env(:rubber_duck_storage, :cache_max_size)
      
      assert is_integer(cache_ttl) and cache_ttl > 0
      assert is_integer(cache_max_size) and cache_max_size > 0
    end

    test "test environment has fast cache expiry" do
      # Test environment should have very short cache TTL
      cache_ttl = Application.get_env(:rubber_duck_storage, :cache_ttl)
      
      # Should be short for tests (our config sets it to 1 second)
      assert cache_ttl <= :timer.seconds(10)
    end
  end

  describe "rubber_duck_engines configuration" do
    test "has required configuration keys" do
      config = Application.get_all_env(:rubber_duck_engines)
      
      assert Keyword.has_key?(config, :engine_pool_size)
      assert Keyword.has_key?(config, :engine_timeout)
      assert Keyword.has_key?(config, :max_concurrent_analyses)
      assert Keyword.has_key?(config, :engines)
    end

    test "configuration values are valid types" do
      pool_size = Application.get_env(:rubber_duck_engines, :engine_pool_size)
      timeout = Application.get_env(:rubber_duck_engines, :engine_timeout)
      max_concurrent = Application.get_env(:rubber_duck_engines, :max_concurrent_analyses)
      engines_config = Application.get_env(:rubber_duck_engines, :engines)
      
      assert is_integer(pool_size) and pool_size > 0
      assert is_integer(timeout) and timeout > 0
      assert is_integer(max_concurrent) and max_concurrent > 0
      assert is_list(engines_config)
    end

    test "engines configuration is properly structured" do
      engines_config = Application.get_env(:rubber_duck_engines, :engines)
      
      # Should be a keyword list of engine configurations
      assert is_list(engines_config)
      
      # Each engine should have a map configuration
      Enum.each(engines_config, fn {engine_name, config} ->
        assert is_atom(engine_name)
        assert is_map(config)
        assert Map.has_key?(config, :enabled)
        assert is_boolean(config.enabled)
      end)
    end

    test "test environment has minimal engine configuration" do
      pool_size = Application.get_env(:rubber_duck_engines, :engine_pool_size)
      max_concurrent = Application.get_env(:rubber_duck_engines, :max_concurrent_analyses)
      
      # Test should have small pools for faster execution
      assert pool_size <= 5
      assert max_concurrent <= 5
    end
  end

  describe "rubber_duck_web configuration" do
    test "has endpoint configuration" do
      endpoint_config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint)
      
      assert is_list(endpoint_config)
      assert Keyword.has_key?(endpoint_config, :pubsub_server)
      assert Keyword.has_key?(endpoint_config, :secret_key_base)
    end

    test "test environment has server disabled" do
      endpoint_config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint)
      
      # In test, server should be disabled
      assert Keyword.get(endpoint_config, :server, false) == false
    end

    test "has websocket timeout configuration" do
      timeout = Application.get_env(:rubber_duck_web, :websocket_timeout)
      
      # Should have a timeout value
      assert is_integer(timeout) and timeout > 0
    end
  end

  describe "configuration files exist and are valid" do
    test "all required config files exist" do
      required_files = [
        "config/config.exs",
        "config/dev.exs", 
        "config/test.exs",
        "config/prod.exs",
        "config/runtime.exs"
      ]
      
      Enum.each(required_files, fn file ->
        assert File.exists?(file), "Configuration file #{file} is missing"
      end)
    end

    test "config files have valid Elixir syntax" do
      config_files = [
        "config/config.exs",
        "config/dev.exs",
        "config/test.exs", 
        "config/prod.exs",
        "config/runtime.exs"
      ]
      
      Enum.each(config_files, fn file ->
        {:ok, content} = File.read(file)
        
        # Should start with import Config
        assert String.starts_with?(content, "import Config"),
          "Config file #{file} should start with 'import Config'"
        
        # Should have valid syntax (this will fail if syntax is invalid)
        assert_no_exception(fn ->
          Code.compile_string(content, file)
        end)
      end)
    end

    test "base config imports environment-specific configs" do
      {:ok, config_content} = File.read("config/config.exs")
      
      # Should import environment-specific config at the end
      assert String.contains?(config_content, ~s/import_config "\#{config_env()}.exs"/)
    end
  end

  describe "configuration helper modules" do
    test "config helper modules are available" do
      assert Code.ensure_loaded?(RubberDuckCore.Config)
      assert Code.ensure_loaded?(RubberDuckCore.Environment)
      assert Code.ensure_loaded?(RubberDuckStorage.Config)
      assert Code.ensure_loaded?(RubberDuckEngines.Config)
      assert Code.ensure_loaded?(RubberDuckWeb.Config)
    end

    test "storage config helpers work" do
      assert is_integer(RubberDuckStorage.Config.cache_ttl())
      assert is_integer(RubberDuckStorage.Config.cache_max_size())
      assert is_boolean(RubberDuckStorage.Config.log_queries?())
    end

    test "engines config helpers work" do
      assert is_integer(RubberDuckEngines.Config.pool_size())
      assert is_integer(RubberDuckEngines.Config.engine_timeout())
      assert is_integer(RubberDuckEngines.Config.max_concurrent_analyses())
      assert is_list(RubberDuckEngines.Config.enabled_engines())
    end

    test "web config helpers work" do
      assert is_boolean(RubberDuckWeb.Config.debug_websockets?())
      assert is_integer(RubberDuckWeb.Config.websocket_timeout())
      assert is_integer(RubberDuckWeb.Config.port())
    end
  end

  # Helper function to assert no exception is raised
  defp assert_no_exception(fun) do
    try do
      fun.()
      true
    rescue
      error -> 
        flunk("Expected no exception, but got: #{inspect(error)}")
    end
  end
end