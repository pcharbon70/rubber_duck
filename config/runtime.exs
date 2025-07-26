import Config

# Timeout configuration overrides from environment variables
# These can override any timeout defined in config/timeouts.exs

# Helper function to parse timeout environment variables
parse_timeout = fn env_var, default ->
  case System.get_env(env_var) do
    nil -> default
    value -> String.to_integer(value)
  end
end

# Channel timeouts
if System.get_env("RUBBER_DUCK_CHANNEL_TIMEOUT") do
  config :rubber_duck, [:timeouts, :channels, :conversation],
    parse_timeout.("RUBBER_DUCK_CHANNEL_TIMEOUT", 60_000)
end

if System.get_env("RUBBER_DUCK_MCP_HEARTBEAT_TIMEOUT") do
  config :rubber_duck, [:timeouts, :channels, :mcp_heartbeat],
    parse_timeout.("RUBBER_DUCK_MCP_HEARTBEAT_TIMEOUT", 15_000)
end

# Engine timeouts
if System.get_env("RUBBER_DUCK_ENGINE_DEFAULT_TIMEOUT") do
  config :rubber_duck, [:timeouts, :engines, :default],
    parse_timeout.("RUBBER_DUCK_ENGINE_DEFAULT_TIMEOUT", 5_000)
end

# Tool execution timeouts
if System.get_env("RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT") do
  config :rubber_duck, [:timeouts, :tools, :default],
    parse_timeout.("RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT", 30_000)
end

# LLM provider timeouts
if System.get_env("RUBBER_DUCK_LLM_DEFAULT_TIMEOUT") do
  config :rubber_duck, [:timeouts, :llm_providers, :default],
    parse_timeout.("RUBBER_DUCK_LLM_DEFAULT_TIMEOUT", 30_000)
end

if System.get_env("RUBBER_DUCK_LLM_STREAMING_TIMEOUT") do
  config :rubber_duck, [:timeouts, :llm_providers, :default_streaming],
    parse_timeout.("RUBBER_DUCK_LLM_STREAMING_TIMEOUT", 300_000)
end

# Circuit breaker timeouts
if System.get_env("RUBBER_DUCK_CIRCUIT_BREAKER_TIMEOUT") do
  config :rubber_duck, [:timeouts, :infrastructure, :circuit_breaker, :call_timeout],
    parse_timeout.("RUBBER_DUCK_CIRCUIT_BREAKER_TIMEOUT", 30_000)
end

if System.get_env("RUBBER_DUCK_CIRCUIT_BREAKER_RESET_TIMEOUT") do
  config :rubber_duck, [:timeouts, :infrastructure, :circuit_breaker, :reset_timeout],
    parse_timeout.("RUBBER_DUCK_CIRCUIT_BREAKER_RESET_TIMEOUT", 60_000)
end

# Helper function for deep merging maps
deep_merge = fn deep_merge_fn, map1, map2 when is_map(map1) and is_map(map2) ->
  Map.merge(map1, map2, fn _k, v1, v2 ->
    if is_map(v1) and is_map(v2) do
      deep_merge_fn.(deep_merge_fn, v1, v2)
    else
      v2
    end
  end)
end

# Support for JSON-based timeout overrides
# This allows setting multiple timeouts via a single environment variable
if json_timeouts = System.get_env("RUBBER_DUCK_TIMEOUTS_JSON") do
  case Jason.decode(json_timeouts) do
    {:ok, timeout_overrides} ->
      # Deep merge the overrides into the existing timeout configuration
      existing_timeouts = Application.get_env(:rubber_duck, :timeouts, %{})
      merged_timeouts = deep_merge.(deep_merge, existing_timeouts, timeout_overrides)
      config :rubber_duck, :timeouts, merged_timeouts
      
    {:error, error} ->
      IO.warn("Failed to parse RUBBER_DUCK_TIMEOUTS_JSON: #{inspect(error)}")
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :rubber_duck, RubberDuck.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :rubber_duck,
    token_signing_secret:
      System.get_env("TOKEN_SIGNING_SECRET") ||
        raise("Missing environment variable `TOKEN_SIGNING_SECRET`!")
end
