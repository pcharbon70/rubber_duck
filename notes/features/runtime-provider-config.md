# Feature: Runtime Provider Configuration

## Summary
Implement runtime configuration for LLM providers, allowing API keys and base URLs to be configured via environment variables (with configurable names) and local config file (~/.rubber_duck/config.json).

## Requirements
- [ ] Load provider configuration from multiple sources (config.json, env vars, runtime updates)
- [ ] Support configurable environment variable names per provider
- [ ] Allow runtime updates of API keys and base URLs
- [ ] Implement config file monitoring for auto-reload
- [ ] Create UI for provider configuration
- [ ] Per-user provider configuration overrides
- [ ] No backward compatibility required
- [ ] No encryption for API keys in config.json

## Research Summary
### Existing Configuration System
- Providers configured statically in `config/llm.exs`
- API keys read from hardcoded env vars (e.g., `OPENAI_API_KEY`)
- Base URLs are either hardcoded or from specific env vars
- `ProviderConfig` struct holds configuration
- `UserLLMConfig` tracks user preferences but not credentials

### Config File Location
- User specified: `~/.rubber_duck/config.json`
- Currently contains minimal test data

### Provider Structure
- Each provider has `validate_config/1` checking for API keys
- Providers use `config.base_url || @default_base_url` pattern
- All providers implement the `Provider` behaviour

## Technical Approach
### 1. Configuration Loading Priority
1. Runtime overrides (highest)
2. ~/.rubber_duck/config.json
3. Environment variables
4. Remove static config

### 2. Config JSON Schema
```json
{
  "providers": {
    "openai": {
      "api_key": "sk-...",
      "base_url": "https://api.openai.com/v1",
      "env_var_name": "OPENAI_API_KEY",
      "base_url_env_var": "OPENAI_BASE_URL"
    },
    "anthropic": {
      "api_key": "sk-ant-...",
      "env_var_name": "ANTHROPIC_API_KEY"
    },
    "ollama": {
      "base_url": "http://localhost:11434",
      "base_url_env_var": "OLLAMA_BASE_URL"
    }
  }
}
```

### 3. Implementation Components
- `ConfigLoader` - Loads and merges configurations
- `ProviderConfig` updates - Add runtime override support
- `LLM.Service` updates - Use ConfigLoader, add update API
- Provider updates - Fetch credentials dynamically
- LiveView for configuration UI

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Invalid config crashes service | High | Validate on load, fallback to last known good |
| API keys exposed in logs | High | Filter sensitive data from logs |
| Config file not found | Low | Create default if missing |
| Race conditions on updates | Medium | Use GenServer serialization |

## Implementation Checklist
- [ ] Create ConfigLoader module
- [ ] Update ProviderConfig struct
- [ ] Modify LLM Service init and config handling
- [ ] Update all providers to use dynamic config
- [ ] Add config file watcher
- [ ] Create provider config LiveView
- [ ] Add provider config channel
- [ ] Write comprehensive tests
- [ ] Update documentation

## Questions for Pascal
None - requirements are clear.

## Log
- 2024-01-24: Feature branch created
- 2024-01-24: Initial research completed
- 2024-01-24: No encryption required for API keys
- 2024-01-24: No backward compatibility needed