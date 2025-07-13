# Feature: Dynamic LLM Provider and Model Configuration

## Summary
Enable dynamic configuration of LLM providers and models through both CLI config file and runtime commands, allowing users to select specific models per provider and set defaults.

## Requirements
- [x] Support storing default LLM provider and model in CLI config file
- [x] Add CLI commands to set model per provider (llm set-model)
- [x] Add CLI command to set default provider (llm set-default)
- [x] Add CLI command to list available models (llm list-models)
- [x] Replace hardcoded model selection in generation engine
- [x] Maintain backward compatibility with existing behavior
- [x] Support provider-specific model configuration
- [x] Allow runtime override of config file settings

## Research Summary
### Existing Usage Rules Checked
- Ash Framework: Reviewed domain/resource patterns, code interfaces, and configuration approaches
- Elixir: Pattern matching, error handling with tagged tuples, configuration management

### Documentation Reviewed
- Current CLI config implementation in `RubberDuck.CLIClient.Auth`
- LLM Service configuration in `RubberDuck.LLM.Service` and `ConnectionManager`
- Existing provider configuration structure using `ProviderConfig`
- Command parsing and handler patterns

### Existing Patterns Found
- CLI config stored in `~/.rubber_duck/config.json` using Jason
- Application config accessed via `Application.get_env(:rubber_duck, :llm, [])`
- Provider configurations stored as list of maps with name, adapter, models
- Command handlers follow consistent pattern with execute/validate functions
- Subcommands already supported in LLM handler (status, connect, disconnect, enable, disable)

### Technical Approach
1. **Extend CLI Config Structure**
   - Add "llm" section to existing JSON config with default_provider, default_model, and per-provider models
   - Update Auth module to include LLM config management functions

2. **Create Centralized Config Module**
   - New `RubberDuck.LLM.Config` module to manage LLM configuration
   - Merge CLI config with application config (CLI takes precedence)
   - Provide consistent API for getting current provider/model

3. **Add New CLI Subcommands**
   - Extend parser with :set_model, :set_default, :list_models subcommands
   - Update LLM handler to process new commands
   - Integrate with Config module for persistence

4. **Dynamic Model Selection**
   - Update generation engine to use Config module instead of hardcoded models
   - Pass selected model through LLM Service options
   - Maintain language-based defaults as fallback

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing workflows | High | Maintain backward compatibility with defaults |
| Invalid model names | Medium | Validate against provider's supported models |
| Config file corruption | Low | Validate JSON structure, handle parse errors gracefully |
| Provider not supporting model | Medium | Fallback to provider's default model |

## Implementation Checklist
- [ ] Create failing tests for new functionality
- [ ] Extend RubberDuck.CLIClient.Auth with LLM config functions
- [ ] Create RubberDuck.LLM.Config module
- [ ] Add new subcommands to Parser
- [ ] Update LLM Handler with new subcommand handlers
- [ ] Update Generation Engine to use dynamic model selection
- [ ] Update Connection Manager to track current model
- [ ] Run all tests and fix any issues
- [ ] Update CLI documentation

## Questions for Pascal
1. Should we support model aliases (e.g., "gpt4" -> "gpt-4-turbo-preview")?
2. Should list-models query the provider API or use a static list?
3. Do we need model validation against provider capabilities?

## Log
- Created feature branch: feature/004-dynamic-llm-configuration
- Researched existing configuration patterns in codebase
- Identified CLI config uses JSON in ~/.rubber_duck/config.json
- Found LLM providers configured via Application config
- Discovered existing subcommand pattern in LLM handler