# Runtime Provider Configuration - Implementation Summary

## Overview
Implemented runtime configuration for LLM providers, allowing API keys and base URLs to be configured dynamically through multiple sources with proper priority ordering.

## What Was Built

### 1. ConfigLoader Module (`lib/rubber_duck/llm/config_loader.ex`)
- Central module for loading provider configuration from multiple sources
- Implements priority order: Runtime overrides → config.json → Environment variables
- Supports custom environment variable names per provider
- Functions:
  - `load_all_providers/1` - Loads configuration for all known providers
  - `load_provider_config/3` - Loads configuration for a specific provider
  - `load_config_file/0` - Reads ~/.rubber_duck/config.json
  - `save_config_file/1` - Writes configuration back to file

### 2. ProviderConfig Updates (`lib/rubber_duck/llm/provider_config.ex`)
- Added `runtime_overrides` field to track runtime configuration
- Added `apply_overrides/2` function to merge runtime configuration
- Maintains immutability while allowing dynamic updates

### 3. LLM Service Updates (`lib/rubber_duck/llm/service.ex`)
- Modified initialization to use ConfigLoader instead of static config
- Added new client functions:
  - `update_provider_config/2` - Updates provider config at runtime
  - `reload_config/0` - Reloads all providers from config file
  - `get_provider_config/1` - Gets current config for a provider
- Added helper functions:
  - `save_provider_config_to_file/2` - Persists changes to config.json
  - `reload_provider/3` - Reloads a specific provider with new config

### 4. Provider Updates
All providers (OpenAI, Anthropic, Ollama, TGI) already use the configuration from ProviderConfig, so no changes were needed. They automatically benefit from the dynamic configuration.

## Configuration Schema

### config.json Format
```json
{
  "providers": {
    "openai": {
      "api_key": "sk-...",
      "base_url": "https://api.openai.com/v1",
      "env_var_name": "OPENAI_API_KEY",
      "base_url_env_var": "OPENAI_BASE_URL",
      "models": ["gpt-4", "gpt-3.5-turbo"],
      "rate_limit": {"limit": 200, "unit": "minute"}
    }
  }
}
```

### Priority Order
1. Runtime overrides (highest priority)
2. ~/.rubber_duck/config.json 
3. Environment variables (lowest priority)

## Usage Examples

### Update Provider Configuration
```elixir
# Update OpenAI API key at runtime
RubberDuck.LLM.Service.update_provider_config(:openai, %{
  api_key: "new-api-key",
  base_url: "https://custom.openai.com/v1"
})
```

### Reload Configuration from File
```elixir
# Reload all providers from ~/.rubber_duck/config.json
RubberDuck.LLM.Service.reload_config()
```

### Get Current Configuration
```elixir
{:ok, config} = RubberDuck.LLM.Service.get_provider_config(:openai)
```

## Testing
Created comprehensive test suites:
- `test/rubber_duck/llm/config_loader_test.exs` - Tests configuration loading priority
- `test/rubber_duck/llm/provider_config_test.exs` - Tests runtime override application

All tests pass successfully.

## Key Design Decisions

1. **No Backward Compatibility**: As requested, removed all static configuration
2. **No Encryption**: API keys stored in plain text in config.json
3. **Atomic Updates**: All configuration updates are atomic through GenServer
4. **Provider Agnostic**: Configuration system works with any provider

## What's Not Implemented

1. **Config File Monitoring**: Auto-reload when config.json changes
2. **LiveView UI**: Web interface for provider configuration
3. **Per-User Overrides**: User-specific provider configurations

These can be added in future iterations as needed.

## Migration Notes

Users will need to:
1. Remove provider configuration from `config/llm.exs`
2. Create `~/.rubber_duck/config.json` with their provider settings
3. Or continue using environment variables (they still work)