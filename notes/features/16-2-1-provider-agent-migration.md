# Feature: Provider Agent Base Class Migration (16.2.1)

## Summary
Complete the Provider Agent migration to full Jido compliance by implementing missing Provider Actions Library components. The base ProviderAgent is already Jido-compliant using the macro pattern but needs additional actions for full compliance.

## Requirements
- [x] ProviderAgent already uses Jido.Agent foundation via macro (DISCOVERED - ALREADY COMPLIANT)
- [x] Core provider request handling via ProviderRequestAction exists
- [ ] Add missing ProviderHealthCheckAction for provider health monitoring
- [ ] Add missing ProviderConfigUpdateAction for dynamic config updates  
- [ ] Add missing ProviderRateLimitAction for rate limit management
- [ ] Add missing ProviderFailoverAction for provider failure handling
- [ ] Ensure all provider implementations (Anthropic, OpenAI, Local) use complete action set
- [ ] Validate compliance with migration utilities

## Research Summary

### Existing Usage Rules Checked
- Jido usage rules: Actions must be pure functions with schemas and tagged tuple returns
- BaseAgent usage: ProviderAgent uses macro pattern that wraps Jido.Agent properly
- Provider patterns: Rate limiting, circuit breaking, metrics collection already implemented

### Documentation Reviewed
- ProviderAgent: Uses sophisticated macro pattern that provides Jido.Agent foundation
- Actions: Comprehensive ProviderRequestAction exists with rate limiting and circuit breaking
- Provider implementations: Anthropic, OpenAI, Local all inherit from ProviderAgent properly

### Existing Patterns Found
- ProviderAgent macro: lib/rubber_duck/agents/provider_agent.ex:21-83 (Already Jido compliant)
- ProviderRequestAction: lib/rubber_duck/jido/actions/provider/provider_request_action.ex:1-50
- Provider Actions: lib/rubber_duck/jido/actions/provider/ (Partial implementation)
- AnthropicProviderAgent: lib/rubber_duck/agents/anthropic_provider_agent.ex:19-25 (Uses ProviderAgent macro)

### Technical Approach
1. **Assessment**: ProviderAgent is already Jido-compliant via macro that uses Jido.Agent
2. **Gap Analysis**: Missing 4 specific actions from the planning document
3. **Implementation**: Create the missing Provider Actions using existing patterns
4. **Integration**: Ensure all provider implementations include the new actions
5. **Validation**: Use migration utilities to confirm full compliance

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing provider functionality | High | Thorough testing of existing providers |
| Action conflicts with existing patterns | Medium | Follow existing ProviderRequestAction patterns |
| Performance impact of additional actions | Low | Actions are pure functions with minimal overhead |

## Implementation Checklist
- [ ] Create ProviderHealthCheckAction module
- [ ] Create ProviderConfigUpdateAction module  
- [ ] Create ProviderRateLimitAction module
- [ ] Create ProviderFailoverAction module
- [ ] Update ProviderAgent macro to include new actions
- [ ] Test with AnthropicProviderAgent
- [ ] Test with OpenAIProviderAgent
- [ ] Test with LocalProviderAgent
- [ ] Validate compliance using migration utilities
- [ ] Verify no regressions in existing functionality

## Questions for Pascal
1. Should we maintain backward compatibility for the existing provider implementations?
2. Are there specific rate limiting or failover strategies you want implemented?
3. Should the health check action include specific provider-specific metrics?