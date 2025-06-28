defmodule RubberDuckCore.Startup do
  @moduledoc """
  Application startup validation and initialization.
  """

  require Logger

  @doc """
  Performs startup validation and initialization tasks.
  Should be called from Application.start/2.
  """
  def validate_and_init! do
    Logger.info("Starting RubberDuck in #{Mix.env()} environment")
    
    # Validate configuration
    validate_config()
    
    # Log startup information
    log_startup_info()
    
    # Perform environment-specific initialization
    init_environment()
    
    :ok
  end

  defp validate_config do
    try do
      RubberDuckCore.Config.validate!()
      Logger.info("Configuration validation passed")
    rescue
      e ->
        Logger.error("Configuration validation failed: #{Exception.message(e)}")
        raise e
    end
  end

  defp log_startup_info do
    Logger.info("RubberDuck Configuration Summary:")
    Logger.info("  Environment: #{Mix.env()}")
    Logger.info("  Debug Mode: #{RubberDuckCore.Environment.debug?()}")
    Logger.info("  Log Level: #{RubberDuckCore.Environment.log_level()}")
    
    # Core settings
    core_config = Application.get_all_env(:rubber_duck_core)
    Logger.info("  Max Conversation Messages: #{core_config[:max_conversation_messages]}")
    Logger.info("  Conversation Retention Days: #{core_config[:conversation_retention_days]}")
    
    # Storage settings
    storage_config = Application.get_all_env(:rubber_duck_storage)
    Logger.info("  Cache TTL: #{storage_config[:cache_ttl]} ms")
    Logger.info("  Cache Max Size: #{storage_config[:cache_max_size]}")
    
    # Engine settings
    engine_config = Application.get_all_env(:rubber_duck_engines)
    Logger.info("  Engine Pool Size: #{engine_config[:engine_pool_size]}")
    enabled_engines = 
      engine_config[:engines]
      |> Enum.filter(fn {_name, config} -> Map.get(config, :enabled, false) end)
      |> Enum.map(fn {name, _config} -> name end)
    Logger.info("  Enabled Engines: #{inspect(enabled_engines)}")
    
    # Web settings
    web_config = Application.get_all_env(:rubber_duck_web)
    endpoint_config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    http_config = Keyword.get(endpoint_config, :http, [])
    Logger.info("  WebSocket Timeout: #{web_config[:websocket_timeout]} ms")
    Logger.info("  Server Port: #{Keyword.get(http_config, :port, 4000)}")
  end

  defp init_environment do
    RubberDuckCore.Environment.when_dev(fn ->
      Logger.info("Development mode initialization")
      # Add any dev-specific initialization
    end)
    
    RubberDuckCore.Environment.when_test(fn ->
      Logger.info("Test mode initialization")
      # Ensure test database is created
      ensure_test_database()
    end)
    
    RubberDuckCore.Environment.when_prod(fn ->
      Logger.info("Production mode initialization")
      # Add any prod-specific initialization
      validate_production_config()
    end)
  end

  defp ensure_test_database do
    # This would normally create/migrate the test database
    # For now, just log
    Logger.debug("Test database initialization would happen here")
  end

  defp validate_production_config do
    # Additional production-only validations
    endpoint_config = Application.get_env(:rubber_duck_web, RubberDuckWeb.Endpoint, [])
    
    unless Keyword.has_key?(endpoint_config, :secret_key_base) do
      raise "SECRET_KEY_BASE must be set in production"
    end
    
    # Check database configuration
    repo_config = Application.get_env(:rubber_duck_storage, RubberDuckStorage.Repo, [])
    
    unless Keyword.has_key?(repo_config, :url) or Keyword.has_key?(repo_config, :database) do
      raise "Database configuration missing in production"
    end
  end
end