# CLI-LLM Integration Feature Plan

## Overview
Connect the CLI commands to the LLM system by creating the missing engine configuration and updating engine implementations to use the LLM service.

## Problem Statement
The CLI commands are implemented but cannot execute because:
1. No engine configuration module exists to define and register engines
2. Engine implementations don't connect to the LLM service
3. Engines are not loaded during application startup

## Proposed Solution

### 1. Create Engine Configuration Module
Create `lib/rubber_duck/engines.ex` using the EngineSystem DSL to define all engines:
- `:generation` - Code generation engine
- `:completion` - Code completion engine  
- `:analysis` - Code analysis engine
- `:refactoring` - Code refactoring engine
- `:test_generation` - Test generation engine

### 2. Update Engine Implementations
Modify existing engines to use `RubberDuck.LLM.Service`:
- Update `RubberDuck.Engines.Generation` to call LLM service
- Update `RubberDuck.Engines.Completion` to call LLM service
- Create missing engines (analysis, refactoring, test_generation)

### 3. Application Startup Integration
- Add engine loading to application supervisor
- Ensure engines are registered with CapabilityRegistry
- Configure default LLM provider

### 4. Configuration
Add development configuration for easy testing:
- Mock provider for tests
- Ollama provider for local development
- Configuration examples in documentation

## Implementation Steps

1. **Engine Configuration Module**
   - Create `RubberDuck.Engines` with EngineSystem DSL
   - Define all 5 engines with proper metadata
   - Set up capability mappings

2. **Update Generation Engine**
   - Replace mock implementation with LLM service calls
   - Add proper prompt templates
   - Integrate with existing RAG system

3. **Update Completion Engine**
   - Connect to LLM service
   - Add context building from file position
   - Implement streaming support

4. **Create Missing Engines**
   - Analysis engine (connects to analysis workflow)
   - Refactoring engine (uses LLM for refactor suggestions)
   - Test generation engine (generates tests using LLM)

5. **Application Startup**
   - Add engine loader to supervision tree
   - Load engines on application start
   - Add health checks

6. **Testing & Documentation**
   - Unit tests for each engine
   - Integration tests for CLI commands
   - Usage documentation
   - Configuration examples

## Success Criteria
- All CLI commands work with LLM providers
- `mix rubber_duck generate "Hello World function"` produces actual code
- Engines are properly registered and discoverable
- Tests pass with mock provider
- Documentation shows how to configure and use

## Risk Mitigation
- Use mock provider for tests to avoid external dependencies
- Add proper error handling for LLM failures
- Implement fallback strategies
- Add rate limiting configuration

## Next Steps
After plan approval:
1. Create engine configuration module
2. Update generation engine implementation
3. Test with CLI command
4. Iterate on remaining engines