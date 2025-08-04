# Feature: Provider Implementation Agents Migration (16.3.2)

## Summary
Migrate the Provider Implementation Agents (AnthropicProviderAgent, OpenAIProviderAgent, LocalProviderAgent) from current partially Jido-compliant architecture to fully action-based architecture, creating provider-specific Actions for enhanced functionality and removing any remaining direct implementation patterns.

## Requirements
- [ ] Migrate AnthropicProviderAgent to fully action-based architecture
- [ ] Create Anthropic-specific Actions for safety features and vision support
- [ ] Migrate OpenAIProviderAgent to fully action-based architecture  
- [ ] Create OpenAI-specific Actions for function calling and streaming
- [ ] Migrate LocalProviderAgent to fully action-based architecture
- [ ] Create Local provider Actions for model management and resource monitoring
- [ ] Implement provider-specific signal-to-action mappings
- [ ] Add comprehensive error handling and validation
- [ ] Support all existing provider capabilities through Actions
- [ ] Maintain backward compatibility for provider APIs
- [ ] Follow Jido pure function patterns with tagged tuple returns
- [ ] Ensure proper state management and lifecycle hooks

## Research Summary

### Existing Usage Rules Checked
- Jido framework: Pure functions, tagged tuples, schema validation, OTP integration
- BaseAgent patterns: Uses ProviderAgent base class with Jido.Agent foundation
- Provider patterns: Common request handling, rate limiting, circuit breakers

### Documentation Reviewed
- AnthropicProviderAgent: Uses ProviderAgent base, has Anthropic-specific config and capabilities
- OpenAIProviderAgent: Uses ProviderAgent base, has OpenAI-specific config and capabilities  
- LocalProviderAgent: Uses ProviderAgent base, has local model and resource management
- ProviderAgent base: Already uses Jido.Agent with comprehensive action listing and schema

### Existing Patterns Found
- ProviderAgent base: /lib/rubber_duck/agents/provider_agent.ex - Modern Jido.Agent with actions list
- Provider Actions: /lib/rubber_duck/jido/actions/provider/*.ex - Core provider actions exist
- Anthropic provider: /lib/rubber_duck/agents/anthropic_provider_agent.ex - Uses ProviderAgent base
- OpenAI provider: /lib/rubber_duck/agents/openai_provider_agent.ex - Uses ProviderAgent base
- Local provider: /lib/rubber_duck/agents/local_provider_agent.ex - Uses ProviderAgent base with resource monitoring

### Technical Approach

#### Current Architecture Analysis
The provider agents are already using a modern architecture:
1. **ProviderAgent base class** - Uses Jido.Agent with comprehensive actions list
2. **Provider-specific agents** - Use ProviderAgent base with provider-specific configuration
3. **Actions listed but missing** - References to provider-specific Actions that don't exist yet
4. **GenServer callbacks remaining** - LocalProviderAgent has handle_info for resource monitoring

#### Phase 1: Provider-Specific Actions Creation
1. **AnthropicProviderAction Library**:
   - `ConfigureSafetyAction` - Configure safety settings and content filtering
   - `VisionRequestAction` - Handle image analysis requests for Claude 3
   - `ContextWindowManagementAction` - Handle large context windows efficiently
   - `UsageTrackingAction` - Track usage and billing information

2. **OpenAIProviderAction Library**:
   - `ConfigureFunctionsAction` - Configure function calling capabilities
   - `StreamRequestAction` - Handle streaming completion requests
   - `ModelSelectionAction` - Extract model selection logic
   - `BatchProcessingAction` - Create batch processing capabilities

3. **LocalProviderAction Library**:
   - `LoadModelAction` - Load models into memory with resource management
   - `UnloadModelAction` - Unload models and free resources
   - `GetResourceStatusAction` - Monitor CPU, GPU, memory usage
   - `ListAvailableModelsAction` - List locally available models
   - `ModelSwitchingAction` - Switch between loaded models
   - `PerformanceOptimizationAction` - Optimize local model performance

#### Phase 2: Signal-to-Action Mappings
Replace the referenced but missing Actions with actual implementations and add signal mappings:
- Anthropic: configure_safety, vision_request, context_window_management, usage_tracking
- OpenAI: configure_functions, stream_request, model_selection, batch_processing  
- Local: load_model, unload_model, get_resource_status, list_available_models, model_switching

#### Phase 3: GenServer Cleanup
Remove remaining GenServer handle_info callbacks from LocalProviderAgent and replace with:
- Resource monitoring through periodic Actions
- Scheduled sensor-based monitoring
- Signal-based resource status updates

#### Phase 4: Enhanced Provider Features
Add missing capabilities mentioned in planning document:
- Anthropic: streaming, context window management, usage tracking, billing
- OpenAI: usage optimization, batch processing, advanced function calling
- Local: performance optimization, model switching, advanced resource management

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking provider APIs | High | Maintain signal compatibility through action routing |
| Resource monitoring disruption | Medium | Careful migration of LocalProviderAgent monitoring to Actions |
| Performance overhead from Actions | Medium | Benchmark provider operations, optimize critical paths |
| Provider-specific feature complexity | Medium | Thorough testing of provider-specific Actions |
| Missing Actions causing runtime errors | High | Create all referenced Actions before deployment |

## Implementation Checklist
- [ ] Create feature branch feature/16.3.2-provider-implementation-agents-migration
- [ ] Create Anthropic provider Actions (ConfigureSafetyAction, VisionRequestAction, ContextWindowManagementAction, UsageTrackingAction)
- [ ] Create OpenAI provider Actions (ConfigureFunctionsAction, StreamRequestAction, ModelSelectionAction, BatchProcessingAction)
- [ ] Create Local provider Actions (LoadModelAction, UnloadModelAction, GetResourceStatusAction, ListAvailableModelsAction, ModelSwitchingAction, PerformanceOptimizationAction)
- [ ] Add signal-to-action mappings to all provider agents
- [ ] Remove GenServer handle_info from LocalProviderAgent
- [ ] Replace resource monitoring with Action-based approach
- [ ] Create comprehensive tests for all provider Actions
- [ ] Verify no regressions in provider functionality
- [ ] Performance test provider workflows
- [ ] Update documentation and examples

## Questions for Pascal
1. Should we maintain the existing resource monitoring frequency for LocalProviderAgent or optimize it through Actions?
2. Are there specific Anthropic safety features beyond content filtering that we should implement?
3. Should we add support for new OpenAI features like advanced function calling patterns?
4. How should we handle provider failover scenarios in the action-based architecture?

## Log

### 2024-08-02 - Research Phase Completed
- Analyzed Provider Implementation Agents: Already use modern ProviderAgent base with Jido.Agent
- Identified missing Actions: Provider agents reference Actions that don't exist yet
- Found GenServer patterns: LocalProviderAgent uses handle_info for resource monitoring
- Ready to create provider-specific Actions and complete migration to pure action-based architecture