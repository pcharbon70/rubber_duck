# Feature 5.4: Text Generation Inference (TGI) Provider

## Overview
Implement a provider for Hugging Face Text Generation Inference (TGI) server to enable high-performance inference with any compatible Hugging Face model. TGI provides optimized inference with features like Flash Attention, Paged Attention, and advanced structured generation capabilities.

## Goals
- Add TGI provider with complete Provider behavior implementation
- Support both OpenAI-compatible (`/v1/chat/completions`) and native TGI endpoints (`/generate`, `/generate_stream`)
- Implement streaming for real-time responses
- Add health check and model discovery functionality
- Support advanced features like function calling and guided generation
- Provide comprehensive documentation for TGI deployment and usage

## Technical Approach

### TGI Provider Features
- **Dual API Support**: Both OpenAI-compatible and native TGI endpoints
- **High Performance**: Built for production inference with optimizations
- **Function Calling**: Advanced structured generation and tool use
- **Streaming**: Real-time response streaming on both APIs
- **Self-hosted**: No external API dependencies
- **Model Flexibility**: Can serve any compatible HuggingFace model

### Key Endpoints
1. **Chat Completions**: `/v1/chat/completions` (OpenAI-compatible)
2. **Generate**: `/generate` (TGI-native)
3. **Generate Stream**: `/generate_stream` (TGI-native streaming)
4. **Health**: `/health` (server health check)
5. **Info**: `/info` (model information)

### Implementation Strategy
1. Create TGI provider module with Provider behavior
2. Implement endpoint selection logic (chat vs generate)
3. Add request/response parsing for both API formats
4. Implement streaming support for both endpoints
5. Add health check and model discovery
6. Configure TGI in LLM providers
7. Create comprehensive test suite
8. Add deployment and usage documentation

## Implementation Plan

### Phase 1: Core Provider Implementation
1. **Research TGI API** - Study both chat and generate endpoints in detail
2. **Create TGI provider module** - Implement Provider behavior with all required callbacks
3. **Implement chat endpoint** - Support OpenAI-compatible `/v1/chat/completions`
4. **Implement generate endpoint** - Support native TGI `/generate` endpoint
5. **Add endpoint selection logic** - Choose appropriate endpoint based on request type

### Phase 2: Advanced Features
6. **Implement streaming support** - Add real-time response streaming for both endpoints
7. **Add health check** - Implement server health monitoring and model discovery
8. **Add function calling support** - Implement structured generation capabilities
9. **Add guided generation** - Support JSON mode and schema-based generation

### Phase 3: Integration and Testing
10. **Add TGI to LLM configuration** - Configure TGI provider in `config/llm.exs`
11. **Update Response module** - Add TGI response parsing and pricing
12. **Create comprehensive test suite** - Test all provider functions and edge cases
13. **Add deployment documentation** - Create setup guide for TGI server deployment

### Phase 4: Documentation and Validation
14. **Document usage patterns** - Add examples for different use cases
15. **Create troubleshooting guide** - Common issues and solutions
16. **Performance optimization guide** - Best practices for TGI deployment
17. **Validate implementation** - End-to-end testing with real TGI server

## Technical Specifications

### Provider Configuration
```elixir
%{
  name: :tgi,
  adapter: RubberDuck.LLM.Providers.TGI,
  base_url: System.get_env("TGI_BASE_URL", "http://localhost:8080"),
  models: ["llama-3.1-8b", "mistral-7b", "codellama-13b"],
  priority: 4,
  timeout: 120_000,
  options: [
    supports_function_calling: true,
    supports_json_mode: true,
    supports_guided_generation: true
  ]
}
```

### Supported Features
- ✅ Streaming responses
- ✅ System messages
- ✅ Function calling
- ✅ JSON mode
- ✅ Guided generation
- ✅ Custom stop sequences
- ✅ Temperature control
- ✅ Top-p sampling
- ❌ Vision (model-dependent)
- ❌ Image generation

### Request/Response Formats

#### Chat Completions (OpenAI-compatible)
```json
{
  "model": "tgi",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello"}
  ],
  "stream": true,
  "max_tokens": 100,
  "temperature": 0.7
}
```

#### Generate (TGI-native)
```json
{
  "inputs": "Hello, how are you?",
  "parameters": {
    "max_new_tokens": 100,
    "temperature": 0.7,
    "top_p": 0.9,
    "stop": [".", "!"]
  }
}
```

## Files to Create/Modify

### New Files
- `lib/rubber_duck/llm/providers/tgi.ex` - Main TGI provider implementation
- `test/rubber_duck/llm/providers/tgi_test.exs` - Comprehensive test suite
- `docs/tgi_setup.md` - TGI deployment and usage guide

### Modified Files
- `config/llm.exs` - Add TGI provider configuration
- `lib/rubber_duck/llm/response.ex` - Add TGI response parsing

## Success Criteria
- [ ] TGI provider implements all Provider behavior callbacks
- [ ] Supports both chat and generate endpoints
- [ ] Streaming works correctly for both APIs
- [ ] Health check discovers available models
- [ ] Function calling and guided generation work
- [ ] Comprehensive test coverage (>90%)
- [ ] Documentation covers deployment and usage
- [ ] Integration with existing LLM service works seamlessly

## Dependencies
- **External**: Text Generation Inference server running
- **Internal**: Existing Provider behavior, Request/Response modules
- **Testing**: Mock HTTP server for testing without real TGI deployment

## Risks and Mitigations
- **Risk**: TGI server deployment complexity
  - **Mitigation**: Provide comprehensive setup documentation and Docker examples
- **Risk**: Model compatibility issues
  - **Mitigation**: Test with popular models and document compatibility matrix
- **Risk**: Performance with large models
  - **Mitigation**: Implement proper timeout handling and resource monitoring

## Timeline
- **Phase 1**: 2-3 hours (Core provider implementation)
- **Phase 2**: 2-3 hours (Advanced features and streaming)
- **Phase 3**: 1-2 hours (Integration and testing)
- **Phase 4**: 1-2 hours (Documentation and validation)
- **Total**: 6-10 hours

## Testing Strategy
- Unit tests for all provider functions
- Integration tests with mock TGI server
- End-to-end tests with real TGI deployment
- Performance tests with different model sizes
- Error handling tests for various failure scenarios

## Future Enhancements
- Multi-model support (serving multiple models from one TGI instance)
- Batch processing for improved throughput
- GPU utilization monitoring
- Advanced guided generation schemas
- Integration with HuggingFace Hub for model discovery